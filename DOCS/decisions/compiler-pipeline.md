# Compiler Pipeline

### Self-contained WASM artifact per circuit

**Decision.** The compiler produces a single `.wasm` file per `.circ` source. The artifact embeds both the simulation engine and the circuit-specific construction code — no companion runtime file, no external dependencies at load time.

**Rationale.** A two-file model (shared engine `.wasm` + per-circuit data blob) saves bytes when many circuits ship together, but it forces consumers to coordinate two artifacts, version-match them, and load them in order. For the v0 use case — embedding a single circuit in a page or a Node script — one file is the simplest deliverable. Browsers cache the artifact unchanged; a CDN entry is one URL.

**Alternatives.** A circuit-as-data-blob loaded by the existing `circ-renderer-lib.wasm`. Smaller per-circuit footprint and lets the engine evolve independently, but creates a coupling that v0 doesn't need. Revisit if many-circuit pages become a real workload.

### Pipeline shape: parse → IR Zig file → `zig build wasm` (subprocess) → wasm

**Decision.** Compilation runs as `.circ` source → langlang parse tree → emitted Zig IR file → **`zig build wasm`** run as a **subprocess** inside the workspace directory that `circ-compile` materializes on disk (template `build.zig` + `src/main.zig` + runtime sources). The **`zig` executable must be on `PATH`** whenever the CLI compiles to `.wasm` (default compile mode). The `circ-compile` binary does **not** embed or vendor the Zig compiler source tree.

**Rationale.** Emitting Zig source as the IR reuses the installed Zig toolchain for type checking, optimisation, and WASM lowering. Subprocess integration is simple, stable across Zig minor releases for the user-facing `zig build` contract, and keeps the application repository free of a full compiler checkout. Release binaries stay small.

**Accepted tradeoff.** End users who compile `.circ` to `.wasm` need a **compatible Zig** (same major.minor as the project targets, currently **0.15.x**) discoverable as `zig` on `PATH`. CI and Docker flows install Zig before invoking `circ-compile`.

**Alternatives.** In-process `Compilation.create()` with a vendored compiler slice: no `zig` on `PATH` at circuit-compile time, but required vendoring a large pinned source tree in-repo — **replaced by this decision (2026-05)** in favour of subprocess + no vendor. Direct WASM emission from the IR: rejected (too much custom lowering).

### IR shape: code-emitting Zig file

**Decision.** Each `.circ` file emits one Zig function (`buildXxx`) that takes the circuit and its declared inputs as arguments, creates internal components and connections by calling the engine API, and returns a struct of declared outputs. Sub-circuit instances become call sites of these functions.

**Rationale.** A code-emitting IR keeps the runtime engine unchanged — it only ever sees primitive `createComponent` / `connect` calls. Sub-circuits flatten naturally at call time, with each instance creating fresh component IDs. The Zig compiler can inline these functions if it wants, so there's no runtime cost to the abstraction. One function per file (not per instance) keeps the emitted source proportional to the source `.circ` files, not the instantiation count.

**Alternatives.** A data-only IR (a const describing the graph, consumed by a generic builder at module init). Smaller emitted files but loses Zig's type checking on connections, and inlining is harder. Hybrid (data + builder) was considered but adds two layers without clear benefit over the function-per-file approach.

### Orchestration: workspace + subprocess (default)

**Decision.** `lib/orchestrator/main.zig` writes the embedded runtime template into a workspace directory, writes `src/compiled.zig`, then — **by default** — invokes `lib/orchestrator/subprocess.zig` to run `zig`, `build`, `wasm` with `cwd` set to that workspace. On non-zero exit, the CLI returns failure after subprocess stderr is printed. `lib/orchestrator/finalize.zig` copies `zig-out/bin/compiled.wasm` to the user’s `-o` path.

**Optional in-process path.** With **`-Dorchestrator-use-inprocess=true`** and a wired **`zig_compiler`** graph (**`ZIG_COMPILER_SRC`** / stub + **`libinprocess`**, see build options), the orchestrator calls **`lib/orchestrator/inprocess.zig`** (or the FFI stub module) instead of the subprocess. Default remains subprocess so release **`circ-compile`** stays small and only requires **`zig`** on PATH.

**Rationale.** Centralises PATH/`zig` discovery and error surfacing; matches what a developer would run manually inside the temp dir.

**Prior decision note.** An earlier revision used in-process compilation with a vendored compiler under `vendor/zig-compiler/`. That approach is **superseded** by subprocess-by-default plus **external** ziglang checkout for optional embedding (`libinprocess`).

### Optional FFI archive `libinprocess.a`

**Decision.** The repository may still produce a **static library** exporting **`circ_inprocess_compile`** (`zig build inprocess-lib`) for experiments or downstream FFI callers. Building it requires:

1. A **ziglang/zig source checkout** at the matching release (same minor as the toolchain, currently **0.15.x**), via **`ZIG_COMPILER_SRC`** or **`-Dzig-compiler-src=`**. The Zig **install** tarball includes **`lib/std`**, **`lib/compiler_rt`**, and **`lib/compiler/*` tooling**, but **does not** ship the self-hosted compiler’s **`src/`** tree (`Compilation.zig`, `Sema.zig`, …), so **`~/.asdf/.../lib/` alone cannot satisfy this link.**

2. On first successful configure, **`build.zig`** copies **`lib/zig_compiler_exports/zig_compiler_exports.zig`** into **`$ZIG_COMPILER_SRC/src/circ_zig_compiler_exports.zig`** if that file is absent (small shim; safe to commit inside a fork or delete after builds).

**Rationale.** Keeps the application repo free of a full compiler tree while still allowing a deliberate, reproducible path to the prior FFI artifact for advanced users.

### Vendored runtime template

**Decision.** The runtime sources (simulation engine, `build.zig` template, WASM entry point) are embedded into the CLI binary at the CLI's own build time via `@embedFile`. At circuit-compile time the CLI writes them out to the temp directory alongside the emitted IR.

**Rationale.** The CLI is a single self-contained binary — no install prefix, no runtime path lookup, no version drift between the CLI and the runtime it emits against. Reproducibility is built in: the same CLI binary always produces output against the same runtime version. Users who don't touch the runtime never see it.

**Alternatives.** Runtime located via env var or `--runtime-path` flag. Allows independent updates of the runtime without rebuilding the CLI, but adds a moving part to packaging and creates a class of "CLI/runtime mismatch" bugs that vendoring eliminates.

### Build directory: temp by default, user-overridable

**Decision.** The temp directory holding the emitted Zig sources defaults to `/tmp/circ-compile-<random>/`. A `--build-dir <path>` flag overrides this. On compile failure the directory is preserved; on success it is removed unless `--build-dir` was specified.

**Rationale.** Random temp dirs prevent concurrent compilations colliding and keep the user's filesystem clean. Preserving the dir on failure is the standard debugging affordance — the user can `cd` in and run `zig build` manually with full error output. The override exists for users who want to inspect successful builds, integrate with their own build tooling, or commit the emitted Zig as part of their workflow.

**Alternatives.** Always-keep or always-clean. Always-keep clutters `/tmp`; always-clean throws away the only debuggable artifact when something breaks. The current rule (clean on success unless overridden) matches gcc's behaviour with `-save-temps`.
