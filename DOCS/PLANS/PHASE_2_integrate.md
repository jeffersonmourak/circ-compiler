# Phase 2 — Integrate

> **Dependencies:** Phase 1 (Vendor) must be complete — the `zig-compiler` module must be linked into `circ-compile` before this phase begins.
> **Warnings:** `Compilation.create()` is an internal Zig API with no stability guarantee. Any Zig version bump requires re-validating this call site. See `DOCS/PLANS_PROMPT.md` — Recurring Traps for the full list of known hazards (global state, `std.process.exit()`, signal handlers, cache seeding).

## Goal

The `zig build` subprocess call in `lib/orchestrator/subprocess.zig` is replaced with an in-process call to the vendored `Compilation.create()` API in a new `lib/orchestrator/inprocess.zig`. `circ-compile` produces byte-for-byte identical `.wasm` output to the current subprocess path and the full test suite passes. The `--emit-zig`, `--inspect`, and `--build-dir` CLI modes are unaffected.

## Scope

**In scope:**
- `lib/orchestrator/inprocess.zig` — new file implementing the in-process compilation call
- Updating `lib/orchestrator/main.zig` to call `inprocess.compile` instead of `subprocess_mod.runCommand`
- Configuring `Compilation.create()` to write output to the same workspace path `zig build wasm` currently uses
- One new integration test asserting byte-for-byte output equality between subprocess and in-process paths
- Full test suite passing after the swap

**Explicitly deferred:**
- Removing or deprecating `lib/orchestrator/subprocess.zig` (it remains untouched)
- Removing the workspace disk write (`workspace_mod.writeEmittedSource`) — the in-process path still reads from disk
- CI matrix / no-Zig-in-PATH validation (Phase 3)
- Error message parity between subprocess stderr and in-process diagnostics beyond what the existing test suite enforces

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| orchestrator | `lib/orchestrator/inprocess.zig` | Calls `Compilation.create()` via `@import("zig-compiler")`, drives compilation, writes output to workspace path, returns `!void` |
| tests | `tests/orchestrator/inprocess_test.zig` | Compiles a known `.circ` fixture via in-process path; asserts output is valid WASM and byte-for-byte equal to subprocess output |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| orchestrator | `lib/orchestrator/main.zig` | Replace `subprocess_mod.runCommand(...)` call at line 42 with `try inprocess.compile(allocator, workspace.path, stderr_writer)`; remove `run_result` and its `defer deinit` |

**New dependencies:** None beyond the `zig-compiler` module already linked in Phase 1.

## Data & State

`inprocess.compile` replaces the `RunResult` exit-code pattern with a Zig error union:

```zig
// lib/orchestrator/inprocess.zig
pub fn compile(
    allocator: std.mem.Allocator,
    workspace_path: []const u8,
    stderr_writer: anytype,
) !void
```

- **Input:** `workspace_path` — directory where `workspace_mod.writeEmittedSource` has already written the emitted Zig source. `Compilation.create()` receives a file path derived from this directory, not an in-memory buffer.
- **Output:** `.wasm` artifact written by `Compilation.create()` to the same path within the workspace that `zig build wasm` currently produces (resolved during implementation — see `TODO(phase2)` below).
- **On error:** returns a Zig error; the caller (`main.zig`) propagates it, which surfaces as `error.ZigBuildFailed` to the CLI layer. Diagnostic output is written to `stderr_writer` before returning the error.

`Compilation.create()` config constraints (exact fields are Zig-0.15.x-specific — see `TODO(phase2)`):

```
target:  wasm32-freestanding
backend: self-hosted (no LLVM)
source:  <workspace_path>/src/compiled.zig  (written by workspace_mod.writeEmittedSource)
output:  <workspace_path>/zig-out/...       (must match finalize_mod.copyOutput expectations)
```

`main.zig` call site after the swap:

```zig
// before (Phase 1 and earlier):
var run_result = try subprocess_mod.runCommand(
    allocator,
    &.{ "zig", "build", "wasm", "-Doptimize=Debug" },
    workspace.path,
    workspace.path,
    stderr_writer,
);
defer run_result.deinit(allocator);
if (run_result.exit_code != 0) return error.ZigBuildFailed;

// after (Phase 2):
try inprocess.compile(allocator, workspace.path, stderr_writer);
```

## Execution & Concurrency Model

This phase is fully blocking from `circ-compile`'s perspective. `inprocess.compile` does not return until compilation is complete. Any internal threading within `Compilation.create()` is entirely its own concern and is not managed by the CLI. No background goroutines, workers, or async constructs are introduced.

## Persistence & I/O

- **Workspace reads:** `inprocess.compile` reads emitted Zig source from `<workspace_path>/src/compiled.zig` — written before this call by `workspace_mod.writeEmittedSource`. No change to the workspace write step.
- **Workspace writes:** `Compilation.create()` writes its `.wasm` output into the workspace. It must be configured to write to the same path `finalize_mod.copyOutput` expects (currently `<workspace_path>/zig-out/bin/compiled.wasm` per `tests/helpers/wasm_run.zig:92`). If the in-process compiler defaults to a different path, configure it explicitly.
- **`finalize_mod.copyOutput` is untouched** — it reads from the same workspace path it always has.
- **`--build-dir` behaviour preserved** — workspace cleanup logic in `main.zig` is unaffected by the call site swap.
- No external APIs, network I/O, or database operations introduced.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Scaffold `inprocess.zig` | `lib/orchestrator/inprocess.zig` with `compile` stub that accepts the correct signature and returns `error.NotImplemented`; wired into `build.zig` so it compiles against `zig-compiler` module | `zig build` exits 0; `lib/orchestrator/inprocess.zig` imports `@import("zig-compiler")` without error |
| 2 | Implement `Compilation.create()` | Full implementation in `inprocess.zig`; calls `Compilation.create()` with `wasm32-freestanding` target, writes output to workspace path; tested in isolation | `tests/orchestrator/inprocess_test.zig` compiles a fixture via `inprocess.compile` directly; output file exists with WASM magic bytes (`\0asm`) |
| 3 | Swap call site and validate | `lib/orchestrator/main.zig` updated to call `inprocess.compile`; byte-for-byte equality test added; full suite passes | `zig build test` exits 0; byte-for-byte integration test passes (or fallback behaviour documented per `TODO(phase2)`) |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| — | — | No isolated unit tests; `inprocess.compile` requires a workspace on disk — tested at integration level |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `inprocess compiles fixture to valid WASM` | `tests/orchestrator/inprocess_test.zig` | `inprocess.compile` on a known `.circ` fixture produces a file beginning with `\0asm` |
| `inprocess output matches subprocess output` | `tests/orchestrator/inprocess_test.zig` | Byte-for-byte equality between subprocess and in-process `.wasm` for the same fixture (see `TODO(phase2)`) |
| Full existing CLI suite | `tests/cli/integration_test.zig` | All pre-existing exit code, file-existence, and content assertions pass after call site swap |
| Full existing behavior suite | `tests/helpers/wasm_run.zig` consumers | Compiled WASM runs correctly via Node.js harness for all behavior fixtures |

Run command: `zig build test`

## Open Questions / Spikes

```
TODO(phase2): Confirm the exact output path Compilation.create() writes its .wasm to
              for a wasm32-freestanding target. Must match what finalize_mod.copyOutput
              expects: currently <workspace_path>/zig-out/bin/compiled.wasm per
              tests/helpers/wasm_run.zig:92. Configure explicitly if the default differs.

TODO(phase2): Audit Compilation.create() for global state mutations, signal handler
              registration, and std.process.exit() calls. Any of these make in-process
              use unsafe. If found, they must be neutralised before Slice 2 is complete.

TODO(phase2): Confirm whether Compilation.create() requires a pre-seeded Zig cache
              (~/.cache/zig/) for builtin module resolution. If so, document the
              cache-seeding contract here before Phase 3 (no-Zig-in-PATH test).

TODO(phase2): If the Zig self-hosted compiler produces non-deterministic WASM output
              (e.g. embedded timestamps, non-deterministic symbol ordering), byte-for-byte
              equality is not achievable. In that case, replace the equality test with
              functional equivalence validated by the wasm_run.zig behavior harness, and
              document this decision in DOCS/decisions/compiler-pipeline.md.
```
