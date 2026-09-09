# Compiler Architecture Decisions

This directory captures the architectural decisions guiding the development of the `.circ` compiler — a CLI that consumes a `.circ` source file and produces a self-contained `.wasm` artifact simulating that specific circuit.

Each decision follows the format: **decision**, **rationale**, **alternatives**.

## Topics

### [compiler-pipeline.md](compiler-pipeline.md)
- Output artifact shape (single self-contained `.wasm` per circuit)
- Compilation pipeline (`.circ → topology binary → custom-section splice → .wasm`)
- IR shape: paired `circ.topology.v0.{min,full}` binary payloads
- Prebuilt runtime WASM embedded in the CLI via `@embedFile`
- `-Dwasm-optimize` (ReleaseSmall, stripped) for both wasm builds
- Host protocol: `topology_alloc` + memcpy + `init()`

### [runtime-api.md](runtime-api.md)
- Settle-only `run()` semantics
- Initial state is implicitly `undefined`; `init()` does not pre-settle
- Pin identification by component ID (no separate pin-index space)
- Paired `getOutputValue` / `getOutputDefined` BigInt exports
- `setPin(id, value, defined)` symmetry with the output getters
- Pull-based, no `onStateChange` callback
- Topology section copied into linear memory at startup
- Deliberately omitted: `deinit`, `reset`, `stop`, `getStateSnapshot`, `getTopology`, `getPendingEvents`, `getFileInfo`, `freeBuffer`
- Native memories (engine kind + mode, cell planes, raw image format, replace-all load, the eight memory exports, topology v03 records, `--sim` preloads and verbs, tooling policy, `--inspect`)

### [language.md](language.md)
- Sub-circuits emit a flat topology binary at serialize time
- Source-path debug info lives in `circ.topology.v0.full`, not on `Component`
- Built-in primitives (`and`, `not`, `wire`, `led`, `output_pin`, `input_pin`) vs auto-imported macro family (`or`, `nand`, `nor`, `xor`, `xnor`)
- Import statement syntax (`import name "path"`)
- LEDs vs `output` declarations
- Multi-bit wires (17 decisions: width syntax, bit numbering, slice/concat, parametric sub-circuits, topology v02)
- Native memories (`rom`/`ram` declarations via `CallWidths`, contents are runtime configuration, edge rule, `E008` policy, `E017`/`E018`)

### [validation.md](validation.md)
- Hard errors vs warnings vs accepted
- Combinational loops are hard errors
- `--warnings-as-errors` flag for CI strictness
- Diagnostic format (location + message; snippets deferred)

### [cli.md](cli.md)
- Five invocation modes (`-o`, `--emit-zig`, `--inspect`, `--preview`, `--truth-table`)
- Mode-specific flag gating (`--expand-macros`, `--format`, `--strict`, …)
- No intermediate `zig build` subprocess; no build-directory override
- `--mem=<name>=<path>` is scoped to `--sim` and `--truth-table`

### [tooling.md](tooling.md)
- Parser generated straight to Zig by the maintainer's langlang fork (supersedes the Go c-archive bridge)
- Pin = the fork's tag `go/v0.0.13-zig.2`; skew signal = the generated header's runtime sha256
- Generated parser vendored in the repo
- Contract pinned before the switch (`Errors (n)` dump, recovery goldens, `expected-analyze`)
- Go retired in one cut-over

### [libcirc.md](libcirc.md)
- One wasm module, ten `circ_*` exports, JSON in / bytes-or-JSON out, status codes 0–5
- Overlay-first virtual file loading (no disk on freestanding)
- Library memory model (per-call arena, library-owned result, `memory.reset()`)
- `-Dwasm-optimize` governs both wasm builds
- The renderer follows the compiler, once, per topology version
- Playground artifacts are committed; the module runs in a Web Worker
- Not exported through libcirc (`--sim`, `--emit-zig`, `--inspect`)

### [playground.md](playground.md)
- The compile fast path resolves implicit builtins (usage-aware `.project_if_imports`; `--inspect` unchanged)
- The JavaScript budget is per page and gzip is the gate (`bun run bundle`, `bundle-budget.json`, the build-free CodeMirror tripwire)

## Conventions

- Decisions use `###` headings inside topic files.
- Each decision is small (decision / rationale / alternatives, ~15 lines).
- No numbering — decisions are referenced by heading slug. The multi-bit fold inside `language.md` is numbered §1–§17 only because it lifted the stage numbering from `DOCS/archive/plan-multi-bit-language.md` verbatim.
- The runtime principle of "few dependencies, Zig-only" applies across every decision unless explicitly noted.
