# Plan Prompt — Test Suite Speed-Up

## What Is Being Built

The `zig build test` suite currently takes ~3 minutes to complete. The dominant cost is `wasm_run.compileAndRun` in `tests/helpers/wasm_run.zig`, which is called once per behavior-test fixture. Every call creates a fresh `std.testing.TmpDir` — a randomly-named temporary directory with an empty `.zig-cache` — then runs `zig build wasm` inside it. Because the directory is new each time, Zig has no cached objects to reuse and recompiles all engine sources (`circuit.zig`, `memory.zig`, `transport.zig`, `log.zig`) from scratch for every fixture. There are ~32 such calls per full test run (13 in `tests/emit/behavior_test.zig`, 19 in `tests/emit/project_behavior_test.zig`), yet the engine files never change between calls — only `compiled.zig` differs.

The fix is to replace the per-call `TmpDir` with a single persistent workspace at a fixed path (`.zig-cache/test-wasm-workspace`). Because the path is stable, Zig's content-addressed cache accumulates compiled objects across calls. After the first build populates the cache, every subsequent call only needs to recompile the changed `compiled.zig` and re-link — the engine objects are cache-hits. No test assertions, fixture files, or build interfaces change; only the workspace management inside `wasm_run.zig` is touched.

The observable definition of done: `zig build test` completes in under 60 seconds on a warm machine (after one initial cold run populates the workspace cache), and every existing test continues to pass.

## Tech Stack

- **Language**: Zig 0.15.x (compiler pipeline, test harness, WASM target)
- **C**: vendored parser (`lib/parser.c` / `lib/parser.h`) — unchanged
- **Node.js**: WASM execution harness (`tests/harness/loader.js`) — unchanged
- **Build system**: `zig build` with named steps; test entry point is `zig build test`
- **WASM harness build**: `tests/harness/build.zig` — produces `compiled.wasm` from a single `compiled.zig` + engine files
- **Deployment target**: local developer machine and CI (Linux / macOS)

## Architectural Constraints

- **No mocking of WASM builds.** Behavior tests must compile and execute real WASM binaries via `zig build wasm` + Node.js. Replacing the subprocess with an in-process evaluator is out of scope. (Implicit project convention.)
- **No new runtime or build-time dependencies.** The project's tooling decision (`DOCS/decisions/tooling.md`) mandates Zig-only runtime with minimal external tools. The optimization must work with existing tools.
- **Test isolation preserved.** Each behavior fixture must still compile its own `compiled.zig`; no sharing of compiled WASM artifacts between different fixture tests.
- **`zig build test` interface unchanged.** The command, step name, and per-test output must remain identical from the developer's perspective.
- **Workspace lives inside `.zig-cache/`.** This directory is already Zig's conventional ephemeral cache location and is gitignored by default. No new gitignore entries should be needed.

## Phase Index

| Phase | Name | What Ships |
|-------|------|-----------|
| 0 | Baseline | A timing baseline recorded in `DOCS/STATUS.md`: total `zig build test` wall time and per-binary breakdown, confirming `behavior_test` and `project_behavior_test` are the bottleneck. |
| 1 | Shared Workspace | `tests/helpers/wasm_run.zig` rewritten to use `.zig-cache/test-wasm-workspace` instead of a fresh `TmpDir`; all 32 behavior fixtures pass; `zig build test` measured to complete in under 60 s on a warm run. |
| 2 | Close-out | `DOCS/STATUS.md` final entry with before/after times; plan declared complete. |

Phases are ordered by dependency, not by priority. Each phase must be fully shippable before the next begins.

## Working Loop

The execution agent follows this loop every session without exception:

### On Cold Start

1. Read this file (`DOCS/PLANS_PROMPT.md`) in full.
2. Read `DOCS/STATUS.md` (if it exists). The latest entry defines what was last shipped and what comes next.
3. Run `git log --oneline -10` and `git status`. If STATUS claims a slice is committed but it does not appear in `git log`, the human has not committed yet — **do not begin a new slice**. Stop and say so.
4. Read the active phase plan (`DOCS/PLANS/PHASE_<N>_<name>.md`) for the current phase.
5. Implement the next slice per the phase plan. Do not start a second slice until the first is reviewed and committed.

### Each Slice

1. Implement the full slice as specified. Do not stop mid-slice.
2. Run the project's test command for the affected modules. Do not ship a slice that breaks the suite.
3. Append a STATUS entry (template below).
4. **Stop.** Wait for human review and commit before beginning the next slice.

### Git Rules

- Do **not** commit, push, or run any write `git` or `gh` command on the human's behalf.
- Read-only git commands (`status`, `log`, `diff`) are encouraged for situational awareness.

## STATUS Entry Template

Append to `DOCS/STATUS.md` at the end of every slice. Never overwrite or edit prior entries.

```
## YYYY-MM-DD — Phase N — <slice title>

**What shipped:** <one or two sentences>
**Files touched:** `<file>`, `<file>`
**Tests:** added <names>, ran `<command>`, result <pass/fail>
**Next slice:** <one sentence>
**Notes:** <anything the next session needs that isn't obvious from the code>
```

## Recurring Traps

- **Concurrent test binary execution.** `behavior_test` and `project_behavior_test` are separate test binaries. If the `test_step` dependency chain ever allows them to run in parallel, both would write `compiled.zig` to the same workspace simultaneously and corrupt each other's build. Verify they remain sequential (each `run_*` step is a direct dependency in `test_step.dependOn`) before relying on a shared single workspace path; if parallelism is ever added, each binary needs its own workspace subdirectory.
- **Workspace left in bad state.** If a prior run crashed mid-build, the `.zig-cache/test-wasm-workspace` may contain a partial or stale build. The implementation must tolerate a pre-existing workspace (do not error on `makeDir` returning `PathAlreadyExists`). Zig's cache is content-addressed and self-healing, so partial caches are safe to keep.
- **Engine file staleness.** If engine sources are updated (e.g., `lib/circuit.zig` changes), the shared workspace will automatically pick up the change because `wasm_run.zig` copies the engine files fresh on each call before invoking `zig build wasm`. Do not skip the copy step as a "performance optimization" — the copy is what keeps the workspace in sync.
- **WASM output overwritten before Node reads it.** After `zig build wasm` the output lands at a fixed path inside the workspace (`zig-out/bin/compiled.wasm`). If a second test starts before the first test's Node process finishes reading that file, the file gets overwritten. Since tests run sequentially this is safe today, but any future parallelization of within-binary tests would require per-test output paths.
