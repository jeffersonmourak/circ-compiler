# Phase 0 — Baseline

> **Dependencies:** None
> **Warnings:** This phase produces no code changes. Its sole output is timing data recorded in `DOCS/STATUS.md`. Do not proceed to Phase 1 until these numbers exist — Phase 1's success criterion is measured against them.

## Goal

After this phase, `DOCS/STATUS.md` contains two timed measurements of `zig build test`: one cold run (empty `.zig-cache`) and one warm run (cache populated from the cold run). The per-binary breakdown from the warm run identifies `behavior_test` and `project_behavior_test` as the dominant cost, and the raw numbers establish the baseline that Phase 1 is measured against.

## Scope

**In scope:**
- Run `zig build test` twice and record wall-clock time for each run.
- Capture per-binary timing by running the two slowest individual test steps in isolation (`zig build test` filtered to a single step, or using `time` on each `run_emit_behavior_tests` / `run_project_behavior_tests` step).
- Record all measurements in `DOCS/STATUS.md` using the standard STATUS entry template.

**Explicitly deferred:**
- No source files are modified.
- No hypotheses about root cause are tested here — the code analysis from the planning session already established the cause; this phase just records the numbers.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|----------------|------|----------------|
| Documentation  | `DOCS/STATUS.md` | Created (if absent) to hold the baseline STATUS entry |

**Modified files:**

| Module/Package | File | Change |
|----------------|------|--------|
| Documentation  | `DOCS/STATUS.md` | Append baseline STATUS entry (or create if absent) |

**New dependencies:** None

## Data & State

The STATUS entry is plain text following the template from `DOCS/PLANS_PROMPT.md`. The measurement fields for this phase are:

```
## YYYY-MM-DD — Phase 0 — Baseline measurement

**What shipped:** Timing baseline for zig build test (cold + warm runs).
**Files touched:** `DOCS/STATUS.md`
**Tests:** no new tests; ran `zig build test`, result pass
**Next slice:** Begin Phase 1 — shared workspace in wasm_run.zig
**Notes:**
  cold run:  <wall time>
  warm run:  <wall time>
  behavior_test isolated:         <wall time>
  project_behavior_test isolated: <wall time>
```

"Cold run" means deleting `.zig-cache` before timing. "Warm run" means running immediately after the cold run without clearing the cache.

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines, threads, or workers are introduced. The agent runs shell commands sequentially and records their output.

## Persistence & I/O

The only I/O is:
- Shell: `rm -rf .zig-cache && time zig build test` (cold)
- Shell: `time zig build test` (warm)
- Shell (optional isolation): `time zig build test 2>&1 | grep -E '^(run_emit_behavior|run_project_behavior)'` or equivalent per-binary timing if the Zig build output surfaces individual step durations
- File write: append the baseline STATUS entry to `DOCS/STATUS.md`

No external APIs, databases, or network I/O are touched.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Cold + warm timing | Two wall-clock measurements of `zig build test` recorded in `DOCS/STATUS.md` | STATUS entry exists with non-zero times; `zig build test` exits 0 on the warm run |
| 2 | Per-binary isolation | Wall-clock time for `behavior_test` and `project_behavior_test` binaries run in isolation appended to the same STATUS entry | Numbers present in STATUS; both binaries exit 0 |

Both slices can be collapsed into one if the Zig build output already surfaces per-step durations during the full run.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|-----------------|
| *(none)* | — | This phase introduces no new test cases |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| `zig build test` (full suite) | All test binaries | Suite exits 0; baseline confirms current state is passing |

Run command: `time zig build test`

## Open Questions / Spikes

- **Per-binary timing granularity.** Zig's default build output may not print per-step wall times. If it does not, isolate the two expensive binaries by temporarily commenting out the other `test_step.dependOn` lines, timing them, then restoring. Record the method used in the STATUS notes so Phase 1 can reproduce the same measurement for comparison.
