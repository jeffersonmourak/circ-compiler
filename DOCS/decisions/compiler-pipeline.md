# Compiler Pipeline

### Self-contained WASM artifact per circuit

**Decision.** The compiler produces a single `.wasm` file per `.circ` source. The artifact embeds both the simulation engine and the circuit-specific construction code — no companion runtime file, no external dependencies at load time.

**Rationale.** A two-file model (shared engine `.wasm` + per-circuit data blob) saves bytes when many circuits ship together, but it forces consumers to coordinate two artifacts, version-match them, and load them in order. For the v0 use case — embedding a single circuit in a page or a Node script — one file is the simplest deliverable. Browsers cache the artifact unchanged; a CDN entry is one URL.

**Alternatives.** A circuit-as-data-blob loaded by the existing `circ-renderer-lib.wasm`. Smaller per-circuit footprint and lets the engine evolve independently, but creates a coupling that v0 doesn't need. Revisit if many-circuit pages become a real workload.

### Pipeline shape: parse → IR Zig file → zig build → wasm

**Decision.** Compilation runs as `.circ source → langlang parse tree → emitted Zig IR file → zig build → .wasm`. The CLI orchestrates each step and produces the final artifact.

**Rationale.** Emitting Zig source as the IR reuses everything the Zig toolchain already does — type checking on the IR, optimisation, WASM lowering, debug info. Writing a custom WASM emitter would mean rebuilding all of that. The Zig compiler is already a hard dependency of the project, so requiring it at compile time adds no new prerequisite.

**Alternatives.** Direct WASM emission from the IR (skip Zig). Faster compilation, but requires hand-written WASM lowering for every primitive and a custom optimiser. Embedding the Zig compiler as a library was also rejected — couples the CLI to Zig's internal API, which is unstable across versions.

### IR shape: code-emitting Zig file

**Decision.** Each `.circ` file emits one Zig function (`buildXxx`) that takes the circuit and its declared inputs as arguments, creates internal components and connections by calling the engine API, and returns a struct of declared outputs. Sub-circuit instances become call sites of these functions.

**Rationale.** A code-emitting IR keeps the runtime engine unchanged — it only ever sees primitive `createComponent` / `connect` calls. Sub-circuits flatten naturally at call time, with each instance creating fresh component IDs. The Zig compiler can inline these functions if it wants, so there's no runtime cost to the abstraction. One function per file (not per instance) keeps the emitted source proportional to the source `.circ` files, not the instantiation count.

**Alternatives.** A data-only IR (a const describing the graph, consumed by a generic builder at module init). Smaller emitted files but loses Zig's type checking on connections, and inlining is harder. Hybrid (data + builder) was considered but adds two layers without clear benefit over the function-per-file approach.

### zig build invoked as a subprocess

**Decision.** The CLI shells out to `zig build` as a subprocess against a temporary working directory containing the emitted IR file plus the vendored runtime template (engine sources, `build.zig`, WASM entry point). The resulting `.wasm` is copied to the user's `-o` path.

**Rationale.** Subprocess invocation matches the standard Zig build flow, gives users the same error messages they'd see running `zig build` themselves, and keeps the CLI loosely coupled to the Zig compiler version. The `--emit-zig` and `--inspect` modes from the CLI design fall out for free — they are the same emission step without the subsequent build call.

**Alternatives.** Embedding Zig as a library (rejected: API instability). Two-phase emit-only CLI requiring users to run `zig build` themselves (rejected: doesn't match the spec of `circ-compile in.circ -o out.wasm` producing a `.wasm`).

### Vendored runtime template

**Decision.** The runtime sources (simulation engine, `build.zig` template, WASM entry point) are embedded into the CLI binary at the CLI's own build time via `@embedFile`. At circuit-compile time the CLI writes them out to the temp directory alongside the emitted IR.

**Rationale.** The CLI is a single self-contained binary — no install prefix, no runtime path lookup, no version drift between the CLI and the runtime it emits against. Reproducibility is built in: the same CLI binary always produces output against the same runtime version. Users who don't touch the runtime never see it.

**Alternatives.** Runtime located via env var or `--runtime-path` flag. Allows independent updates of the runtime without rebuilding the CLI, but adds a moving part to packaging and creates a class of "CLI/runtime mismatch" bugs that vendoring eliminates.

### Build directory: temp by default, user-overridable

**Decision.** The temp directory holding the emitted Zig sources defaults to `/tmp/circ-compile-<random>/`. A `--build-dir <path>` flag overrides this. On compile failure the directory is preserved; on success it is removed unless `--build-dir` was specified.

**Rationale.** Random temp dirs prevent concurrent compilations colliding and keep the user's filesystem clean. Preserving the dir on failure is the standard debugging affordance — the user can `cd` in and run `zig build` manually with full error output. The override exists for users who want to inspect successful builds, integrate with their own build tooling, or commit the emitted Zig as part of their workflow.

**Alternatives.** Always-keep or always-clean. Always-keep clutters `/tmp`; always-clean throws away the only debuggable artifact when something breaks. The current rule (clean on success unless overridden) matches gcc's behaviour with `-save-temps`.
