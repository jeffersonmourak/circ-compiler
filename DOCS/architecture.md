# Architecture

`circ-compiler` is a one-shot compiler: it takes a `.circ` source (plus any sibling files it imports) and emits a self-contained `.wasm` artifact. The shipping pipeline is pure Zig from front to back; the Zig build has no runtime SDK, no rendering layer and no JavaScript. (The docs site under `site/` is a separate bun/Astro build that consumes `libcirc.wasm` and the pinned `circ-renderer` package.)

## End-to-end pipeline

```
   .circ source(s)
        │
        ▼
   ┌───────────────────────────────────────────────────────────┐
   │  Front-end (lib/syntax/, lib/parser/, lib/grammar/)       │
   │  PEG parser generated to Zig by langlang from             │
   │  proto-circ.peg (lib/parser/parser.zig) → Zig AST         │
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

Allocations route through `memory.allocator` from `lib/memory.zig`. It is an `ArenaAllocator` over `page_allocator` on every target; `free` is a no-op, and `memory.reset()` exists only for libcirc's per-call teardown. The engine owns its components; `Circuit.deinit()` walks `nodes` and frees each, releases the propagation scratch buffer, and iterates the `tiers: [MAX_WIDTH + 1]?Pool` array tearing down every lazily-allocated tier.

### State storage layout

Wire state does **not** live inline on `Component`. Each component carries an opaque `PoolHandle` into a width-tiered Structure-of-Arrays pool owned by `Circuit`. Reads and writes flow through `Circuit.readState` / `Circuit.writeState`, which dispatch on `PoolHandle.tier` exactly once and then perform a direct bitmap operation against the pool's `(values, defined)` u64 buffers. The width=1 tier packs 64 slots per word.

The value currency above the pool is `BitVecState` (`value`, `defined`, `width`). It is what events carry, what gates evaluate, and what listeners receive. The split lets every legal width (1 through 64) live in its own lazily-allocated pool tier, with the propagator untouched — each tier indexes by `tier == width` (tier 0 is unused). The width=1 tier packs 64 slots per word; wider tiers store one u64 per slot. Widths > 64 trap at allocation time. See `DOCS/simulation-engine.md` for the full surface.

## Layer 2 — Prebuilt runtime template (`templates/`)

The runtime template is the WASM shell that ships embedded inside every compiled artifact. It lives in `templates/main.zig` and `templates/interpreter.zig`, and is built once (`zig build`) into `zig-out/lib/circ-runtime.wasm`. `build.zig` generates a `runtime_embed` module (a `@embedFile` of the prebuilt artifact) into which `lib/libcirc/modes.zig` splices the topology, so users need no Zig toolchain at runtime.

The template:

- Exports a fixed runtime API to JavaScript: `topology_alloc`, `init`, `run`, `setPin(id, value, defined)`, `getOutputValue(id)`, `getOutputDefined(id)`, plus the memory export family (`getMemInfo`, `memBuffer`, `memLoad`, `memStore`, `memClear`, `setMemWord`, `getMemValue`, `getMemDefined`) for circuits that declare `rom`/`ram` (see [wasm-api.md](wasm-api.md) for full signatures). The two getters return paired `BitVecState` halves crossed as `i64` / `BigInt`.
- Imports two log callbacks from the host (`debugEnabled`, `onDebugLog`) — that's it. There is no `onStateChange`; hosts poll `getOutputValue` / `getOutputDefined` after `run()`.
- Reads the per-circuit topology from the buffer the host loaded via `topology_alloc`, then calls `interpreter.initFromTopology` to materialise the circuit using the engine in `lib/circuit.zig`.

`section_writer.combineTwo` (in `lib/topology/`) appends two custom sections — `circ.topology.v0.min` (runtime-readable) and `circ.topology.v0.full` (tooling-readable) — to the embedded runtime blob. No re-link, no `zig` subprocess on the user's machine.

## Layer 3 — Compiler front-end and middle (`lib/syntax/`, `lib/resolver/`, `lib/ir/`, `lib/validator/`)

This is the heart of the compiler:

- **`lib/grammar/proto-circ.peg`** — PEG grammar source. Regenerate `lib/parser/parser.zig` with `zig build parser:gen` when the grammar changes; the generated source is vendored. The generator is the maintainer's [langlang fork](https://github.com/jeffersonmourak/langlang) (`go install github.com/jeffersonmourak/langlang/go/cmd/langlang@v0.0.13-zig.2`), upstream `go/v0.0.12` plus a Zig output language.
- **`lib/parser/parser.zig`** — the generated parser: header (`Code generated by langlang`, `Source File`, `Runtime: … abi=1 sha256=…`), `pub const runtime` (the VM: `Tree`, `Machine`, `Interpreter`, `Bytecode`), the `bytecode` comptime tables, the `Rule` enum, and `Parser = runtime.Interpreter(bytecode, Rule, …)`. Never hand-edited; `zig build parser:gen` rewrites it.
- **`lib/syntax/`** — `translate.zig` walks `parser.runtime.Tree` (`typ`/`name`/`range`/`childAt`/`childrenLen`/`child`) into `ast.zig`; `span.zig` carries source spans through the rest of the pipeline.
- **`lib/resolver/`** — splits into `scan_imports` (auto-imports `<builtin>/` macros if the file participates in a project), `import_cycle` (rejects cyclic imports with `E010`), `file_loader`, `resolve_bodies` (whole-project resolution into per-module IRs), and `builtins` (the in-memory definitions of `or`, `nand`, `nor`, `xor`, `xnor`).
- **`lib/ir/`** — `types.zig` defines `Module` / `Project` / `Component` / `Pin`. `resolver.zig` is the single-file path used by `--inspect`.
- **`lib/validator/`** — `run.zig` for single-module validation, `run_project.zig` for whole-project. `codes.zig` is the registry of stable diagnostic codes; `diagnostics.zig` formats them.

## Layer 4 — Topology and emit (`lib/topology/`, `lib/emit/`)

- **`lib/topology/serializer.zig`** writes the compact `.min` blob: a flat ordered list of primitive components and their connections. Sub-circuits are fully flattened — there is no hierarchy at runtime.
- **`lib/topology/full_serializer.zig`** writes the `.full` blob: includes per-file IDs, port names, component aliases, and macro provenance for tooling that needs human-readable structure.
- **`lib/emit/`** is the experimental `--emit-zig` pipeline: it generates standalone Zig source that can be compiled to a `.wasm` with a richer (but unstable) export surface (`getStateSnapshot`, `getFileInfo`, `freeBuffer`, …). This path is not used by default compile.

## Layer 5 — Preview (`lib/preview/`)

`circ-compile --preview` renders an ASCII schematic of the resolved circuit without producing any artifact. The pipeline reuses `full_serializer.buildFromModule|Project` to get the structured topology, then `lib/preview/layout/orchestrator.zig` turns it into a `LayoutGrid` through five stages: `collapse` (macro boxes; wires, slices and concats folded away) → `layering` (longest-path layers, dummy nodes for long edges, back edges flagged) → `ordering` (port-aware barycenter sweeps) → `coords` (one row per node, aligned to the port that feeds it) → `channels` (per-gap track routing with doglegs, return lanes for feedback and demand-sized gaps). `lib/preview/render.zig` then paints the routed grid with box, wire and junction glyphs. See [preview.md](preview.md) for the conventions and flags, and [decisions/preview-layout.md](decisions/preview-layout.md) for the layout decisions.

## Drivers over the engine (`lib/sim/`, `lib/truth_table/`, `lib/analyze/`)

Three more modes run the front end in process and produce no artifact. `lib/sim/` implements the `--sim` stdio protocol (`protocol.zig` parses verbs, `loop.zig` drives a `lib/engine_session.zig` instance, images go through `lib/memimage.zig`; see [sim-protocol.md](sim-protocol.md)). `lib/truth_table/` enumerates every input vector for `--truth-table` over the same engine session. `lib/analyze/` produces the `--analyze` JSON for editor tooling ([analyze-api.md](analyze-api.md)). The back halves live in `lib/libcirc/modes.zig`, so the CLI and the library share them.

## Layer 6 — Library (`lib/libcirc.zig`, `lib/libcirc/`)

The front end above is also a library. `lib/libcirc/frontend.zig` runs load → parse → resolve → validation along the route a mode needs (single module, project if imports, project) over an in-memory file set, `modes.zig` holds the back halves (topology, artifact, layout/render, truth table, analysis), `json.zig` is the request/response codec, and `c_api.zig` is the ten-export C ABI (`circ_alloc`, `circ_free`, `circ_version`, `circ_analyze`, `circ_compile`, `circ_preview`, `circ_truth_table`, `circ_result_ptr`, `circ_result_len`, `circ_reset`; status `0` ok, `1` diagnostics, `2` bad request, `3` refused, `4` out of memory, `5` internal). `build/frontend_modules.zig` creates the module graph once per target, so the CLI (`cmd/circ-compile/main.zig` is a client of the same API), `zig build libcirc` (`libcirc.a` + `include/libcirc.h`) and `zig build libcirc-wasm` (`wasm32-freestanding`, root `wasm_root.zig`) share every front-end module object. Files come from an overlay first and from disk only on hosted targets. See [libcirc-api.md](libcirc-api.md) and [decisions/libcirc.md](decisions/libcirc.md).

## Build targets

`zig build` produces several independent binaries (driven by `build.zig`):

| Build step             | Output                              | Purpose                                                              |
|------------------------|-------------------------------------|----------------------------------------------------------------------|
| `circ-compile`         | `zig-out/bin/circ-compile`          | The `.circ` → `.wasm` CLI compiler.                                  |
| (default `zig build`)  | `zig-out/lib/circ-runtime.wasm`     | The prebuilt runtime template embedded into compiled artifacts; follows `-Dwasm-optimize` (default ReleaseSmall). |
| `zig build libcirc`    | `zig-out/lib/libcirc.a` + `include/libcirc.h` | The front end as a static C library (Layer 6).                 |
| `zig build libcirc-wasm` | `zig-out/lib/libcirc.wasm`        | The same C ABI for `wasm32-freestanding`; the site's `/playground` runs it in a Web Worker. |
| `zig build test`       | fast unit + integration suite       | Suite under `tests/` (dev-loop default). Set `CIRC_SKIP_PERF=1` to skip the perf smoke.  |
| `zig build test-all`   | `test` + slow emit-zig smoke        | Adds `test-emit` (a nested `zig build wasm` per fixture); the gate CI runs.  |
| `zig build test-emit`  | the emit-zig smoke alone            | The nested per-fixture `zig build wasm` that `test-all` adds. |
| `zig build bench`      | engine benchmark                    | Runs the engine over the truth-table fixtures against the goldens under `tests/fixtures/bench/` (see [benchmark.md](benchmark.md)). |
| `zig build libcirc-smoke` | runs `examples/c/analyze.c`      | Compiles and runs the C example against `libcirc.a`. |
| `zig build parser:gen` | `lib/parser/parser.zig`             | Regenerates the vendored parser from `lib/grammar/proto-circ.peg` (needs the pinned langlang fork). |

This build has no "TypeScript SDK" target, Canvas-2D rendering layer, or `compiler:run` step; those prototypes were removed in favour of the CLI-only model. The canvas that draws circuits today is the separate `circ-renderer` package, pinned by the site.
