# Phase 5 — Build Orchestration

## Goal

Wrap the in-process emitter from Phase 4 in the production build pipeline: a self-contained CLI binary that embeds the runtime template via `@embedFile`, lays out a temp directory, shells out to `zig build`, and produces a `.wasm` artifact at the user's chosen path. After this phase, "given a `.circ` file and an output path, produce a `.wasm`" works as a complete in-process operation orchestrated from Zig — but without the user-facing CLI argument parsing yet (Phase 6).

## Scope

In scope:

- A `lib/orchestrator/` module that takes an emitted Zig source string + an output path and produces the `.wasm`.
- The `@embedFile`-vendored runtime template: every Zig file the emitted `compiled.zig` needs to compile, plus a production `build.zig` template, plus the WASM entry point.
- Temp directory creation (`/tmp/circ-compile-<rand>/`) and cleanup policy (clean on success unless `--build-dir` was specified, preserve on failure).
- `zig build` subprocess invocation with stderr streamed verbatim under a header (`zig build failed in <build-dir>:`).
- Output `.wasm` copy from the temp dir's build output to the user's chosen path.
- A `--build-dir <path>` *parameter* on the orchestrator's API (the CLI flag is wired up in Phase 6, but the orchestrator function takes the parameter today so Phase 6 only adds plumbing).
- Unit tests for the orchestration helpers (temp-dir creation, embed extraction, subprocess wrapper).
- End-to-end tests that exercise the actual subprocess + temp-dir path (distinct from Phase 4's in-process behavioural tests).

Out of scope:

- CLI argument parsing, the three CLI modes, the `--warnings-as-errors` flag. Phase 6.
- Sub-circuit emission and import resolution. Phase 7. The orchestrator in Phase 5 calls into the same single-file emitter from Phase 4.
- Built-in macro library. Phase 8.
- Any change to the emitter itself. Phase 5 is purely orchestration around Phase 4's output.

## Architectural anchors recap

- The CLI binary is self-contained — runtime sources are embedded via `@embedFile` at the CLI's *own* build time and written to the temp directory at circuit-compile time (`decisions/tooling.md`, `decisions/compiler-pipeline.md`).
- The full embed: `build.zig` template + WASM entry point + the simulation engine (`lib/circuit.zig`, `lib/memory.zig`, `lib/log.zig`, anything they transitively need). Q8a, decision (ii).
- Temp directory layout is flat under `src/`; emitted file is named `compiled.zig` (Q8b confirmed).
- Subprocess errors stream stderr verbatim under a header (Q8c, decision (iii)).
- `--build-dir` preserves on success; default temp dir cleans on success but preserves on failure (`decisions/cli.md`).

## Temp directory layout

```
<build_dir>/
  build.zig             ← embedded production template
  src/
    main.zig            ← embedded WASM entry point (calls into compiled.zig)
    circuit.zig         ← embedded engine
    memory.zig          ← embedded engine
    log.zig             ← embedded engine
    transport.zig       ← embedded engine
    compiled.zig        ← emitted from Phase 4
```

`src/main.zig` is small — its job is to pull in `compiled.zig` and re-export the runtime functions, or simply delegate. Since `compiled.zig` already declares the `export fn` set, `main.zig` may just be `comptime { _ = @import("compiled.zig"); }`. Decide at slice time which form Zig's WASM linker expects.

## Embed manifest

The CLI's own `build.zig` (the one that builds the CLI binary, *not* the embedded template) needs to know which files to `@embedFile`. Two approaches:

- (i) Hard-coded list in a `lib/orchestrator/embed.zig` file: `pub const runtime_files = [_]EmbeddedFile{ .{ .name = "build.zig", .content = @embedFile("../../templates/build.zig") }, ... };`
- (ii) Build-time generation: a build step scans `templates/` and produces `embed.zig` automatically.

(i) is simpler and explicit — when an embedded file is added or removed, the change is visible in one diff. (ii) is automation that obscures the embed list. Pick (i).

The `templates/` directory at the repo root (or `lib/orchestrator/templates/` — pick at slice time) holds:
- `build.zig` — the production build template.
- `main.zig` — the WASM entry point.
- Symlinks or copies of engine files? Or `@embedFile("../../lib/circuit.zig")` directly from inside `embed.zig`?

Recommendation: `@embedFile` references engine files directly from `lib/` — no duplication. The template-specific files (`build.zig`, `main.zig`) live under `templates/`.

## Subprocess error handling

When `zig build` exits non-zero, the orchestrator:

1. Captures the subprocess's stderr (and stdout if Zig writes errors to stdout).
2. Prints `zig build failed in <build-dir>:` to the orchestrator's stderr.
3. Streams the captured output verbatim after the header.
4. Returns an error to the caller.
5. Does *not* delete the build directory — failure preserves the temp dir for debugging.

When `zig build` succeeds:

1. Locates the produced `.wasm` (typically `<build-dir>/zig-out/bin/<name>.wasm` or similar; pin the exact path at slice time based on what the production `build.zig` template emits).
2. Copies it to the user-specified output path.
3. If the user didn't specify `--build-dir`, deletes the temp directory.

## Orchestrator API

```zig
pub const OrchestratorOptions = struct {
    output_wasm_path:   []const u8,
    build_dir:          ?[]const u8 = null,   // null = use temp dir, auto-clean on success
};

pub const OrchestratorResult = struct {
    output_wasm_path:   []const u8,
    build_dir:          []const u8,           // path used (temp or user-supplied)
    cleaned_up:         bool,                 // true if temp dir was deleted
};

pub fn compile(
    allocator: std.mem.Allocator,
    emitted_zig_source: []const u8,
    options: OrchestratorOptions,
) !OrchestratorResult;
```

Phase 6 calls `compile(...)` after running parse → resolve → validate → emit. The orchestrator does not know about `.circ` source — it takes a Zig string (the emitter's output) and treats it as opaque.

## Slices

### Slice 5.1 — Embed manifest and template files

**What ships.** `templates/build.zig` and `templates/main.zig` containing the production WASM build template and entry point. `lib/orchestrator/embed.zig` exposing the embed manifest as a `const` array of `{ name, content }` records, populated via `@embedFile`.

The CLI's own `build.zig` is updated so the orchestrator module compiles correctly — it doesn't yet *use* the embed manifest, but the manifest must compile.

**Tests.** A test that iterates the embed manifest and asserts every entry has non-empty content (catches `@embedFile` paths that silently produce empty buffers if the file moves). A test that asserts the manifest contains the expected file names (`build.zig`, `main.zig`, `circuit.zig`, `memory.zig`, `log.zig`, `transport.zig`).

**Files touched.** `templates/build.zig`, `templates/main.zig`, `lib/orchestrator/embed.zig`, `build.zig` (CLI's own).

**Why this slice exists alone.** The embed manifest fixes which files are part of the runtime template. Locking it before the orchestrator code uses it makes sure the template scope is decided cleanly.

### Slice 5.2 — Temp dir creation and embed extraction

**What ships.** `lib/orchestrator/workspace.zig` with two helpers:

- `createWorkspace(allocator, build_dir_override) → Workspace` — creates the directory (random under `/tmp` if no override), creates the `src/` subdir.
- `writeRuntime(workspace) → void` — writes every embedded file from the manifest into the workspace.
- `writeEmittedSource(workspace, source) → void` — writes `compiled.zig` into the workspace's `src/` dir.

A `Workspace` struct holds the path and a `cleanup_on_success` flag (true if the temp dir was created here, false if `--build-dir` was supplied).

**Tests.** Unit tests for each helper:

- `createWorkspace(null, ...)` produces a path under `/tmp/circ-compile-*` that exists.
- `createWorkspace("/path/to/dir", ...)` uses the supplied path; `cleanup_on_success` is false.
- `writeRuntime` produces a workspace where every manifest file's content matches the embed.
- `writeEmittedSource` writes the file to `<workspace>/src/compiled.zig`.

Tests use `std.testing.tmpDir()` for paths so they don't leave artifacts in `/tmp`.

**Files touched.** `lib/orchestrator/workspace.zig`.

### Slice 5.3 — Subprocess wrapper

**What ships.** `lib/orchestrator/subprocess.zig` wrapping `std.process.Child` for the `zig build` invocation. Captures stdout/stderr, returns an exit code + the captured streams. Streams stderr to the parent process's stderr verbatim under the `zig build failed in <build-dir>:` header on non-zero exit.

**Tests.** Unit tests:

- A successful invocation (e.g. `zig version`) returns exit 0 and the version string in stdout.
- A failing invocation (`zig --invalid-flag` or similar) returns non-zero, captures stderr, and the wrapper prints the header.
- The header includes the supplied build-dir path verbatim.

**Files touched.** `lib/orchestrator/subprocess.zig`.

### Slice 5.4 — Output copy and cleanup

**What ships.** `lib/orchestrator/finalize.zig`:

- `copyOutput(workspace, target_path)` — finds the `.wasm` produced by `zig build`, copies it to `target_path`. Errors clearly if the expected path doesn't exist (means the production `build.zig` template emitted to a different path than expected — internal bug).
- `cleanup(workspace)` — deletes the workspace directory if `cleanup_on_success` is true.

**Tests.** Unit tests:

- `copyOutput` from a workspace with a fixture `.wasm` to a temp output path produces the correct bytes at the target.
- `copyOutput` errors if the expected `.wasm` is missing.
- `cleanup` deletes the workspace when the flag is true.
- `cleanup` is a no-op when the flag is false.

**Files touched.** `lib/orchestrator/finalize.zig`.

### Slice 5.5 — Top-level orchestrator and end-to-end test

**What ships.** `lib/orchestrator/main.zig` exposing the `compile(...)` function from the API sketch above. It composes slices 5.2, 5.3, 5.4 in order. On success, returns the `OrchestratorResult`; on subprocess failure, propagates the error and leaves the workspace in place.

**Tests.** End-to-end tests that exercise the *real* subprocess path:

- Take a small fixture (e.g. the inverter from Phase 4).
- Run Phase 2 → Phase 3 → Phase 4 to produce emitted Zig.
- Call `orchestrator.compile(...)` with no `build_dir` override and a temp output path.
- Assert the output `.wasm` exists, is a valid WASM module (magic bytes `\x00asm`), and the temp dir was cleaned up.
- A second test supplies a `build_dir`; assert the build dir is preserved and contains the expected files.
- A third test deliberately produces invalid Zig (e.g. by manually constructing a broken emitter output) and asserts the orchestrator returns an error and preserves the build dir.

These tests are slow (each runs a real `zig build`) — keep the count small and reuse fixtures.

**Files touched.** `lib/orchestrator/main.zig`, fixtures and harness.

## Definition of done for Phase 5

- All five slices committed.
- `zig build test` passes.
- Calling `lib/orchestrator/main.compile(...)` with valid emitted Zig produces a working `.wasm` at the target path.
- Subprocess failures preserve the build directory and print the verbatim stderr under a header.
- The CLI binary (still without arg parsing) embeds all runtime files via `@embedFile`.
- The production `build.zig` template produces a `.wasm` at a deterministic path the orchestrator knows.

## Open questions to resolve at slice time

- Whether the production `build.zig` template uses Zig's standard WASM target conventions or a custom configuration. Recommendation: standard `target: .{ .cpu_arch = .wasm32, .os_tag = .freestanding }` with `single_threaded = true`. If the existing `circ-renderer-lib` build target in the repo's main `build.zig` works, mirror its configuration.
- The exact path the production template emits the WASM to. Common options: `zig-out/bin/compiled.wasm` or `zig-out/lib/compiled.wasm`. Pin one and document it where `finalize.copyOutput` looks.
- Whether to vendor `templates/build.zig` and `templates/main.zig` under `templates/` or under `lib/orchestrator/templates/`. Recommendation: top-level `templates/` — it's a project-level concept, not an orchestrator implementation detail.
- How to handle the case where `zig` isn't on `PATH`. The subprocess wrapper will fail with a system error; the wrapper should detect this specific case and produce a helpful message ("zig binary not found on PATH; install Zig or set ZIG_PATH"). Detect via `error.FileNotFound` from `std.process.Child.spawn`.
- Whether `@embedFile` paths in `lib/orchestrator/embed.zig` work cleanly when the file moves. Zig will fail to compile if a path is wrong, which is the right failure mode — but verify at slice time that engine refactors won't silently break embeds.

## Notes for the next phase

Phase 6 wires the CLI argument parser around the orchestrator. Concretely: the CLI parses argv, runs Phase 2 → 3 → 4 to produce emitted Zig, calls `orchestrator.compile(...)` with the user's `-o` path and `--build-dir` (if supplied), and prints diagnostics from Phase 3 to stderr. If Phase 3 produced any hard errors, the CLI exits non-zero before calling the orchestrator at all.

The `--emit-zig` and `--inspect` modes from Phase 6 do not call the orchestrator — they short-circuit after Phase 4 (or Phase 2/3 respectively) and write to stdout instead.
