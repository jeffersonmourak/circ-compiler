# Compiler Pipeline

### Self-contained WASM artifact per circuit

**Decision.** The compiler produces a single `.wasm` file per `.circ` source. The artifact embeds both the simulation engine and the circuit-specific construction code — no companion runtime file, no external dependencies at load time.

**Rationale.** A two-file model (shared engine `.wasm` + per-circuit data blob) saves bytes when many circuits ship together, but it forces consumers to coordinate two artifacts, version-match them, and load them in order. For the v0 use case — embedding a single circuit in a page or a Node script — one file is the simplest deliverable. Browsers cache the artifact unchanged; a CDN entry is one URL.

**Alternatives.** A circuit-as-data-blob loaded by the existing `circ-renderer-lib.wasm`. Smaller per-circuit footprint and lets the engine evolve independently, but creates a coupling that v0 doesn't need. Revisit if many-circuit pages become a real workload.

### Pipeline shape: parse → IR Zig file → in-process Compilation.create() → wasm

**Decision.** Compilation runs as `.circ source → langlang parse tree → emitted Zig IR file → in-process `Compilation.create()` / `comp.update()` → .wasm`. The Zig 0.15.x self-hosted compiler is vendored into `vendor/zig-compiler/` and linked directly into the `circ-compile` binary. No `zig` binary is required at circuit-compile time.

**Rationale.** Emitting Zig source as the IR reuses everything the Zig compiler already does — type checking, optimisation, WASM lowering, debug info. Calling the compiler in-process (rather than via a subprocess) eliminates `zig` as a runtime dependency: the resulting binary is self-contained and ships without a Zig installation requirement. Phase 0 confirmed that the self-hosted WASM backend calls `Compilation.create()` with zero LLVM C/C++ library symbols in the final binary (`nm` check, `have_llvm = false`, `use_llvm = false`), making in-process embedding tractable.

**Accepted tradeoff.** The vendored compiler source is pinned to Zig 0.15.1 exactly. Upgrading the host toolchain requires re-vendoring the matching Zig source and re-auditing the `Compilation` API call sites — the internal compiler API is not stable across versions. This coupling is the price of zero-runtime-dependency distribution.

**Alternatives.** Direct WASM emission from the IR (skip Zig): faster, but requires hand-written WASM lowering for every primitive and a custom optimiser — rejected. Subprocess `zig build` (the previous decision): requires `zig` in PATH at circuit-compile time — replaced by this decision in Phase 2. Embedding rejected in an earlier revision of this document due to API instability; the self-hosted WASM backend (no LLVM required) and the explicit version-lock tradeoff make embedding acceptable now.

### IR shape: code-emitting Zig file

**Decision.** Each `.circ` file emits one Zig function (`buildXxx`) that takes the circuit and its declared inputs as arguments, creates internal components and connections by calling the engine API, and returns a struct of declared outputs. Sub-circuit instances become call sites of these functions.

**Rationale.** A code-emitting IR keeps the runtime engine unchanged — it only ever sees primitive `createComponent` / `connect` calls. Sub-circuits flatten naturally at call time, with each instance creating fresh component IDs. The Zig compiler can inline these functions if it wants, so there's no runtime cost to the abstraction. One function per file (not per instance) keeps the emitted source proportional to the source `.circ` files, not the instantiation count.

**Alternatives.** A data-only IR (a const describing the graph, consumed by a generic builder at module init). Smaller emitted files but loses Zig's type checking on connections, and inlining is harder. Hybrid (data + builder) was considered but adds two layers without clear benefit over the function-per-file approach.

### Zig compiler called in-process via vendored source

**Decision.** The CLI calls `Compilation.create()` and `comp.update()` from the Zig 0.15.1 self-hosted compiler, vendored under `vendor/zig-compiler/` and linked into the `circ-compile` binary. The `lib/orchestrator/inprocess.zig` module owns this call. `zig build` is no longer invoked as a subprocess at circuit-compile time.

**Rationale.** In-process compilation eliminates `zig` as a runtime PATH dependency. Error output is surfaced via `error_bundle.renderToStdErr()`, matching what users would see from `zig build`. The `--emit-zig` and `--inspect` CLI modes are unaffected — they bypass the compilation step entirely. The `--build-dir` flag behaviour (preserve on failure, clean on success unless specified) is preserved; the in-process path still writes intermediates to a workspace directory.

**Configuration.** The embedded compiler is configured with `have_llvm = false`, `use_llvm = false`, `use_lib_llvm = false`, `use_lld = false`, target `wasm32-freestanding`, `output_mode = .Exe`, `entry = .disabled`, `cache_mode = .none`, `dev = .full`, `enable_debug_extensions = true`. `std.Thread.Pool` must be initialized with `track_ids = true` (Zig compiler workers unwrap `id.?` unconditionally). `output_mode = .Obj` is not viable for `wasm32-freestanding` with a ZCU in Zig 0.15.1 — `.Exe` with `entry = .disabled` is the correct substitute for library-style `pub export fn` outputs.

**Alternatives.** Subprocess `zig build` (the previous decision): simpler integration but requires `zig` in PATH at circuit-compile time — replaced by this decision. Two-phase emit-only CLI requiring users to run `zig build` themselves: rejected — doesn't match the `circ-compile in.circ -o out.wasm` contract.

**Prior decision note.** An earlier revision of this document listed "embedding Zig as a library" as rejected due to API instability. That rejection is superseded: the version-lock tradeoff is now explicitly accepted, and LLVM-free linkage was confirmed in Phase 0.

### Vendored runtime template

**Decision.** The runtime sources (simulation engine, `build.zig` template, WASM entry point) are embedded into the CLI binary at the CLI's own build time via `@embedFile`. At circuit-compile time the CLI writes them out to the temp directory alongside the emitted IR.

**Rationale.** The CLI is a single self-contained binary — no install prefix, no runtime path lookup, no version drift between the CLI and the runtime it emits against. Reproducibility is built in: the same CLI binary always produces output against the same runtime version. Users who don't touch the runtime never see it.

**Alternatives.** Runtime located via env var or `--runtime-path` flag. Allows independent updates of the runtime without rebuilding the CLI, but adds a moving part to packaging and creates a class of "CLI/runtime mismatch" bugs that vendoring eliminates.

### Build directory: temp by default, user-overridable

**Decision.** The temp directory holding the emitted Zig sources defaults to `/tmp/circ-compile-<random>/`. A `--build-dir <path>` flag overrides this. On compile failure the directory is preserved; on success it is removed unless `--build-dir` was specified.

**Rationale.** Random temp dirs prevent concurrent compilations colliding and keep the user's filesystem clean. Preserving the dir on failure is the standard debugging affordance — the user can `cd` in and run `zig build` manually with full error output. The override exists for users who want to inspect successful builds, integrate with their own build tooling, or commit the emitted Zig as part of their workflow.

**Alternatives.** Always-keep or always-clean. Always-keep clutters `/tmp`; always-clean throws away the only debuggable artifact when something breaks. The current rule (clean on success unless overridden) matches gcc's behaviour with `-save-temps`.
