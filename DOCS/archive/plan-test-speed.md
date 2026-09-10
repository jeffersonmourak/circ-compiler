# Archived plan: test-speed

**Canonical commit:** `06fdc4f6b13b3d0df68ff596e9fae2ad968eddda` (pre-squash, not in history; the work landed as `acad4f7`) (`06fdc4f Document completion of Phase 2 of the test suite speed-up initiative in \`DOCS/STATUS.md\`. Confirmed significant performance improvements with final warm run time of 25.33s, achieving a speedup factor of ~3.8× compared to the baseline. No new tests added; initiative is now complete.`)
**Archived on:** 2026-05-04
**Plan duration:** 2026-05-04 → 2026-05-04

> This file is a highlight view. The plan bundle (plan prompt, phase plans, STATUS log) lived on a branch that was squash-merged as `acad4f7` (`Plan: speed up test suite (~3 min → <60 s) (#2)`); the pre-squash commit named above is not in this repository's history, so the unabridged source is not recoverable from git.

## Goal & scope

`zig build test` was taking ~96 s (warm) because `compileAndRun` in `tests/helpers/wasm_run.zig` created a fresh `std.testing.TmpDir` for every behavior-test fixture call. Each new directory had an empty `.zig-cache`, so Zig recompiled all engine sources (`circuit.zig`, `memory.zig`, `transport.zig`, `log.zig`) from scratch ~32 times per run even though those files never change between fixtures. The fix replaced the per-call `TmpDir` with a persistent workspace under `.zig-cache/` so Zig's content-addressed cache accumulated compiled objects across calls.

Architectural constraints that shaped the implementation: no mocking of WASM builds (all 32 behavior fixtures must compile and execute real WASM via `zig build wasm` + Node.js); no new runtime or build-time dependencies; each fixture still compiles its own `compiled.zig` (no sharing of compiled WASM artifacts); the `zig build test` interface and per-test output are unchanged; the workspace lives inside `.zig-cache/` (already gitignored).

## Phase-by-phase highlights

### Phase 0 — Baseline

Recorded a timing baseline for `zig build test` before any code changes.

- Warm full-suite wall time (Zig cache already populated): **95.93 s** (`/usr/bin/time -p zig build test`). Cold run was not timed to avoid wiping the project cache.
- Per-binary isolation timing was not collected separately; the planning doc had already identified the per-call WASM compile subprocesses as the bottleneck.

### Phase 1 — Shared Workspace

Rewrote `compileAndRun` in `tests/helpers/wasm_run.zig` to use a persistent workspace instead of `std.testing.TmpDir`.

- Workspace path is `.zig-cache/test-wasm-workspace-<pid>` (PID suffix, not a fixed basename). A single fixed basename caused cross-process clobbering of `compiled.zig` / `compiled.wasm` when the two test executables (`emit_behavior_tests`, `project_behavior_test`) ran in parallel.
- Engine sources (`circuit.zig`, `memory.zig`, `transport.zig`, `log.zig`) and `tests/harness/build.zig` are still copied into the workspace on every `compileAndRun` call to keep the workspace in sync with source changes.
- `copyTextFile` helper signature changed from `*std.testing.TmpDir` to `std.fs.Dir`; `compileAndRun` public signature is unchanged.
- Warm full-suite wall time after the change: **26.36 s**.

Deviation from phase plan: the plan specified a single fixed workspace path (`.zig-cache/test-wasm-workspace`); the implementation uses a PID-suffixed path to handle the parallelism trap documented in `DOCS/PLANS_PROMPT.md`.

### Phase 2 — Close-out

Final confirmation run of `zig build test`: **25.33 s** (warm). Speedup factor baseline ÷ final: **~3.8×**. All existing tests pass. Initiative declared complete.

## API surface

This plan introduced no new diagnostic codes, CLI flags, runtime WASM exports, or public Zig API. The only externally visible change is test-suite wall time. The `compileAndRun` signature in `tests/helpers/wasm_run.zig` is unchanged.

## Known papercuts carried forward

- **Two cold WASM caches after a fresh run.** Because each test binary gets its own PID-suffixed workspace, the first full `zig build test` after a `.zig-cache` wipe populates two separate workspace caches (one per binary). Subsequent warm runs reuse both. Acceptable tradeoff to avoid the single-path clobbering problem; no action needed unless disk space is a concern.
- **Future parallelism within a test binary is unsafe with the current fixed wasm output path.** `compiled.wasm` lands at `<workspace>/zig-out/bin/compiled.wasm`. If `--test-threads N` is ever used, within-binary tests would race on that path. Per-test output subdirectories would be needed at that point.

## Decisions & specs that survived the plan

Living specs are unchanged and remain authoritative:

- [`DOCS/architecture.md`](architecture.md)
- [`DOCS/simulation-engine.md`](simulation-engine.md)
- [`DOCS/wasm-api.md`](wasm-api.md)
- [`DOCS/circuit-format.md`](circuit-format.md)
- [`DOCS/decisions/`](decisions/index.md)
