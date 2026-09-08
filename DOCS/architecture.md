# Architecture

`circ-compiler` is a one-shot compiler: it takes a `.circ` source (plus any sibling files it imports) and emits a self-contained `.wasm` artifact. The shipping pipeline is pure Zig from front to back; there is no runtime SDK in this repo, no rendering layer, and no JavaScript code in the build.

## End-to-end pipeline

```
   .circ source(s)
        │
        ▼
   ┌───────────────────────────────────────────────────────────┐
   │  Front-end (lib/syntax/, lib/parser/, lib/grammar/)       │
   │  PEG parser (langlang Go output + CGo c-archive shim,     │
   │  generated from proto-circ.peg) → Zig AST                 │
   │  (lib/syntax/ast.zig, translate.zig)                      │
   └───────────────────────────────────────────────────────────┘
        │
        ▼
   ┌───────────────────────────────────────────────────────────┐
   │  Resolver (lib/resolver/)                                 │
   │  scan_imports → import_cycle → resolve_bodies             │
   │  Auto-imports virtual <builtin>/ macros for projects      │
   │  → IR (lib/ir/types.zig)                                  │
   └───────────────────────────────────────────────────────────┘
        │
        ▼
   ┌───────────────────────────────────────────────────────────┐
   │  Validator (lib/validator/)                               │
   │  Stable diagnostic codes E001–E018, W001–W003             │
   │  Hard errors block emission; --warnings-as-errors promotes│
   └───────────────────────────────────────────────────────────┘
        │
        ▼
   ┌───────────────────────────────────────────────────────────┐
   │  Topology (lib/topology/)                                 │
   │  serializer.zig       → circ.topology.v0.min (runtime)    │
   │  full_serializer.zig  → circ.topology.v0.full (tooling)   │
   └───────────────────────────────────────────────────────────┘
        │
        ▼
   ┌───────────────────────────────────────────────────────────┐
   │  Section writer (lib/topology/section_writer.zig)         │
   │  Splices both topology sections into a vendored prebuilt  │
   │  runtime WASM (zig-out/lib/circ-runtime.wasm at build     │
   │  time, embedded into the CLI as runtime_embed).           │
   └───────────────────────────────────────────────────────────┘
        │
        ▼
   final .wasm  ← hands to host (Node, browser, etc.)
```

The CLI driver is `cmd/circ-compile/main.zig`. It dispatches several mutually exclusive modes — `run()` is the authoritative set, and the [README usage table](../README.md#usage) documents what each produces; only the default mode produces a `.wasm`. A separate `--analyze` invocation is handled in `main()` ahead of `run()`: it reads a JSON request on stdin (rather than a file path) and emits structured diagnostics, symbols, and references for editor tooling such as the external circ-lsp server. See [analyze-api.md](analyze-api.md).

## Layer 1 — Simulation engine (`lib/circuit.zig`)

The engine is pure Zig and oblivious to WebAssembly, JSON, or topology. It models a circuit as a directed graph of `Component`s and advances time with a min-heap event queue.

### Component kinds

There are nine kinds (`ComponentType` in `lib/circuit.zig`):

| Kind             | Inputs                                  | Output port | Notes                                                              |
|------------------|-----------------------------------------|-------------|---------------------------------------------------------------------|
| `input_pin_gate` | `"in"` (sub-circuit only)               | `"out"`     | Top-level input pins are driven by the host via `setPin`.          |
| `not_gate`       | `"in"`                                  | `"out"`     | Output is `flip(dominant("in"))`.                                  |
| `and_gate`       | `"a"`, `"b"`                            | `"out"`     | `low` if either input is `low`; `undefined` if either is undefined.|
| `wire`           | `"in"`                                  | `"out"`     | Relays the dominant defined input.                                 |
| `output_pin`     | `"in"`                                  | `"out"`     | Sub-circuit output: passes input through, exposed to the parent.   |
| `led`            | `"in"`                                  | `"out"`     | Visualisation primitive; tracks input state.                       |
| `slice`          | `"in"`                                  | `"out"`     | Bit-shape kind: masks bits `[lo, hi)` of `from`. Output width is `hi - lo`. Lowered from `a[lo..hi]` and `a[i]`; users never write it directly. |
| `concat`         | `"operand_0"`, `"operand_1"`, … per op  | `"out"`     | Bit-shape kind: ORs each operand into its bit-position slot. Output width is the sum of operand widths. Lowered from `{a, b, ...}`. |
| `memory`         | `"addr"` (+ `"din"`, `"we"`, `"clk"` for `.ram`) | `"out"` | Native `rom`/`ram`. Asynchronous read: `out` is `cells[addr]`, undefined when any address bit is; a `.ram` writes `din` on the defined rising edge of `clk` while `we` is high. Cells live on the payload, not in the state pool. |

### Event-driven propagation

```text
propagateEvent(component, new_state)
    if component.output_state == new_state:
        current_time += PROPAGATION_DELAY        # no-op short-circuit
        return
    enqueue Event { ts = current_time + PROPAGATION_DELAY, component, new_state }
    propagate()

propagate()
    while queue non-empty:
        T = peek.timestamp
        current_time = T
        # Phase 1 — drain every event at timestamp T, commit state, collect changed.
        changed = []
        while peek.timestamp == T:
            event = pop_min(queue)
            if event.component.output_state == event.new_state: continue
            event.component.output_state = event.new_state
            changed.append(event.component)
        # Phase 2 — walk outputs of changed components; recalc + notify.
        for c in changed:
            for downstream in c.outputs:
                recalculateAndReschedule(downstream)
                notifyStateChange(downstream)
```

The per-timestamp batching matters: without it, a downstream gate with multiple upstream events at the same `T` could read partial state, dedup the corrective re-enqueue, and get stuck on the wrong final value. See `simulation-engine.md` for the full rationale.

Delays are compile-time constants (`PROPAGATION_DELAY = 5`, `WIRE_PROPAGATION_DELAY = 1`); the delay switch in `lib/circuit.zig` is the source of truth for which component kinds take the wire delay versus the gate delay. See [simulation-engine.md](simulation-engine.md) for the full timing model.

### Memory

Allocations route through `memory.allocator` from `lib/memory.zig`. In the WASM target this is `std.heap.wasm_allocator`; on native (`zig build test`) it's a `GeneralPurposeAllocator`. The engine owns its components; `Circuit.deinit()` walks `nodes` and frees each, releases the propagation scratch buffer, and iterates the `tiers: [MAX_WIDTH + 1]?Pool` array tearing down every lazily-allocated tier.

### State storage layout

Wire state does **not** live inline on `Component`. Each component carries an opaque `PoolHandle` into a width-tiered Structure-of-Arrays pool owned by `Circuit`. Reads and writes flow through `Circuit.readState` / `Circuit.writeState`, which dispatch on `PoolHandle.tier` exactly once and then perform a direct bitmap operation against the pool's `(values, defined)` u64 buffers. The width=1 tier packs 64 slots per word.

The value currency above the pool is `BitVecState` (`value`, `defined`, `width`). It is what events carry, what gates evaluate, and what listeners receive. The split lets every legal width (1 through 64) live in its own lazily-allocated pool tier, with the propagator untouched — each tier indexes by `tier == width` (tier 0 is unused). The width=1 tier packs 64 slots per word; wider tiers store one u64 per slot. Widths > 64 trap at allocation time. See `DOCS/simulation-engine.md` for the full surface.

## Layer 2 — Prebuilt runtime template (`templates/`)

The runtime template is the WASM shell that ships embedded inside every compiled artifact. It lives in `templates/main.zig` and `templates/interpreter.zig`, and is built once (`zig build`) into `zig-out/lib/circ-runtime.wasm`. The CLI embeds that blob via `lib/runtime_embed` (a `@embedFile` of the prebuilt artifact) so users do not need a Zig toolchain at runtime.

The template:

- Exports a fixed runtime API to JavaScript: `topology_alloc`, `init`, `run`, `setPin(id, value, defined)`, `getOutputValue(id)`, `getOutputDefined(id)` (see [wasm-api.md](wasm-api.md) for full signatures). The two getters return paired `BitVecState` halves crossed as `i64` / `BigInt`.
- Imports two log callbacks from the host (`debugEnabled`, `onDebugLog`) — that's it. There is no `onStateChange`; hosts poll `getOutputValue` / `getOutputDefined` after `run()`.
- Reads the per-circuit topology from the buffer the host loaded via `topology_alloc`, then calls `interpreter.initFromTopology` to materialise the circuit using the engine in `lib/circuit.zig`.

`section_writer.combineTwo` (in `lib/topology/`) appends two custom sections — `circ.topology.v0.min` (runtime-readable) and `circ.topology.v0.full` (tooling-readable) — to the embedded runtime blob. No re-link, no `zig` subprocess on the user's machine.

## Layer 3 — Compiler front-end and middle (`lib/syntax/`, `lib/resolver/`, `lib/ir/`, `lib/validator/`)

This is the heart of the compiler:

- **`lib/grammar/proto-circ.peg`** — PEG grammar source. Regenerate `lib/parser/parser.go` with [langlang](https://github.com/clarete/langlang) when the grammar changes; the generated source is vendored.
- **`lib/parser/`** — `parser.go` (langlang-generated) plus `shim/shim.go` (CGo bridge exposing a C-callable surface). `go build -buildmode=c-archive` produces `parser.a` + `parser.h`, which Zig links via `lib/syntax/CParser.zig`.
- **`lib/syntax/`** — `CParser.zig` is the FFI wrapper, `translate.zig` lowers the parse tree to the Zig AST in `ast.zig`, `span.zig` carries source spans through the rest of the pipeline.
- **`lib/resolver/`** — splits into `scan_imports` (auto-imports `<builtin>/` macros if the file participates in a project), `import_cycle` (rejects cyclic imports with `E010`), `file_loader`, `resolve_bodies` (whole-project resolution into per-module IRs), and `builtins` (the in-memory definitions of `or`, `nand`, `nor`, `xor`, `xnor`).
- **`lib/ir/`** — `types.zig` defines `Module` / `Project` / `Component` / `Pin`. `resolver.zig` is the single-file path used by `--inspect`.
- **`lib/validator/`** — `run.zig` for single-module validation, `run_project.zig` for whole-project. `codes.zig` is the registry of stable diagnostic codes; `diagnostics.zig` formats them.

## Layer 4 — Topology and emit (`lib/topology/`, `lib/emit/`)

- **`lib/topology/serializer.zig`** writes the compact `.min` blob: a flat ordered list of primitive components and their connections. Sub-circuits are fully flattened — there is no hierarchy at runtime.
- **`lib/topology/full_serializer.zig`** writes the `.full` blob: includes per-file IDs, port names, component aliases, and macro provenance for tooling that needs human-readable structure.
- **`lib/emit/`** is the experimental `--emit-zig` pipeline: it generates standalone Zig source that can be compiled to a `.wasm` with a richer (but unstable) export surface (`getStateSnapshot`, `getFileInfo`, `freeBuffer`, …). This path is not used by default compile.

## Layer 5 — Preview (`lib/preview/`)

`circ-compile --preview` renders an ASCII schematic of the resolved circuit without producing any artifact. The pipeline reuses `full_serializer.buildFromModule|Project` to get the structured topology, runs `lib/preview/layout.zig` to place gates, then `lib/preview/render.zig` to draw wires (with detour routing for crossing/feedback). See [preview.md](preview.md) for the conventions and flags.

## Build targets

`zig build` produces several independent binaries (driven by `build.zig`):

| Build step             | Output                              | Purpose                                                              |
|------------------------|-------------------------------------|----------------------------------------------------------------------|
| `circ-compile`         | `zig-out/bin/circ-compile`          | The `.circ` → `.wasm` CLI compiler.                                  |
| (default `zig build`)  | `zig-out/lib/circ-runtime.wasm`     | The prebuilt runtime template embedded into compiled artifacts.       |
| `zig build test`       | fast unit + integration suite       | Suite under `tests/` (dev-loop default). Set `CIRC_SKIP_PERF=1` to skip the perf smoke.  |
| `zig build test-all`   | `test` + slow emit-zig smoke        | Adds `test-emit` (a nested `zig build wasm` per fixture); the gate CI runs.  |

There is no longer a "TypeScript SDK" target, a Canvas-2D rendering layer, or a `compiler:run` step — those were prototypes that have been removed in favour of the CLI-only model.
