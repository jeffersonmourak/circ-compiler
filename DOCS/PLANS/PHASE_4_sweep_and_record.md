# Phase 4 — Sweep and record

> **Dependencies:** Phases 0–3 shipped and committed.
> **Warnings:** No new behaviour lands here. A defect the sweep finds is a slice of this phase only if it regresses a Phase 0–3 test or the protocol goldens; anything else is a follow-up. `DOCS/prompts/ARCHIVE.md` runs only when the human asks.

## Goal

The three faces have been driven together on every shipped example that has something to drive, the lazy chunk's growth is known, the decisions doc holds every locked decision the phases exercised, and the plan is ready to archive with its follow-ups named.

## Scope

**In scope:**
- The human's walk of `/playground` in both themes: `four-bit-adder` driven from the Data tab, the console (`eval`) and a canvas click, each face showing the same values; `ram-write-read` clocked from the console (`set we 1`, `set clk 0`, `set clk 1`) with the dock and the Data tab following; `rom-lookup` with an image loaded from the dock and read through `peek` and the table; `sr-latch` driven from the Data tab's toggles; a recompile mid-session, a theme flip, a `reset`.
- The `/playground` lazy chunk measured with `bun run bundle` against the Phase 0 baseline.
- `DOCS/decisions/playground.md` reread against decisions 1–12; missing entries added.
- Follow-ups in the final STATUS entry.

**Explicitly deferred:**
- The archive itself.

## File & Module Topology

**New files:** None.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `DOCS/decisions/playground.md` | Completed for this initiative; a closing paragraph naming the follow-ups. |
| site | `DOCS/STATUS.md` | The sweep entry and the completion entry. |

**New dependencies:** None.

## Data & State

None introduced. The sweep's record is prose in STATUS: one line per example × face with "ok" or the defect.

## Execution & Concurrency Model

Not applicable.

## Persistence & I/O

None.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The walk | STATUS table of example × face, both themes. | Every row "ok", or a defect with its fix slice. |
| 2 | The measurement | The lazy chunk's raw and gzip before and after, in STATUS. | Numbers recorded; the eager graph unchanged. |
| 3 | Decisions reread | Every locked decision has an entry or a line saying it was not exercised. | `grep -c '^### ' DOCS/decisions/playground.md` grew by the entries the phases promised. |
| 4 | Completion entry | STATUS declares the plan complete with follow-ups. | The entry satisfies `DOCS/prompts/ARCHIVE.md`'s "when to invoke" conditions. |

## Tests

**Unit tests:** None new.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| Full site gate | `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle` | Green on the final tree. |
| Compiler gate | `zig build test-all` | Green and unchanged (no Zig file touched). |

Run command: the two lines above.

## Open Questions / Spikes

None — phase is fully specified.
