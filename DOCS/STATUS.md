# Plan execution status

## 2026-05-04 — Phase 0 — Baseline measurement

**What shipped:** Timing baseline for `zig build test` before the shared WASM workspace change (per-call `TmpDir` still in use for that run).
**Files touched:** `DOCS/STATUS.md`
**Tests:** no new tests; ran `zig build test`, result pass
**Next slice:** Phase 1 — shared workspace in `wasm_run.zig` (landed in the same session immediately after this entry).
**Notes:**
- Cold run (after `rm -rf .zig-cache`) was not timed in this session to avoid wiping the whole project cache.
- Warm full-suite wall time (machine already had Zig caches): **real 95.93s** (`/usr/bin/time -p zig build test`).
- Per-binary isolation timings for `emit_behavior_tests` / `project_behavior_test` were not collected separately; the planning doc already identifies WASM compile subprocesses as the bottleneck.

## 2026-05-04 — Phase 1 — Shared WASM workspace

**What shipped:** `compileAndRun` now uses a persistent directory under `.zig-cache/` instead of `std.testing.TmpDir`, so Zig reuses cached engine objects across fixtures. Workspace path is `.zig-cache/test-wasm-workspace-<pid>` (not a single fixed basename) because `zig build test` can run the behavior and project_behavior test executables in parallel; a single shared path caused cross-process clobbering of `compiled.zig` / `compiled.wasm`. Engine sources and `build.zig` are still copied on every call.
**Files touched:** `tests/helpers/wasm_run.zig`, `DOCS/STATUS.md`
**Tests:** no new tests; ran `zig build test`, result pass
**Next slice:** Phase 2 — close-out in `DOCS/STATUS.md` with final before/after summary if desired.
**Notes:**
- Warm full-suite wall time after the change: **real 26.36s** (`/usr/bin/time -p zig build test`).
- Recurring trap from `DOCS/PLANS_PROMPT.md`: verified `test_step` can overlap slow test binaries; PID suffix is the mitigation without touching `build.zig`.

## 2026-05-04 — Phase 2 — Close-out

**What shipped:** Initiative complete. `zig build test` confirmed green with warm wall time well under 60 s.
**Files touched:** `DOCS/STATUS.md`
**Tests:** no new tests; ran `zig build test`, result pass
**Next slice:** None — initiative is complete.
**Notes:**
- Baseline warm run (Phase 0): **95.93s** (`/usr/bin/time -p zig build test`).
- Post-fix warm run (Phase 1): **26.36s** (same command).
- Final confirmation run: **25.33s** (`/usr/bin/time -p zig build test`).
- Speedup factor (baseline ÷ final): **~3.8×**.
- Residual caveat: workspace path is `.zig-cache/test-wasm-workspace-<pid>` so parallel test binaries stay isolated; two cold WASM caches exist after both have run (acceptable trade-off).
