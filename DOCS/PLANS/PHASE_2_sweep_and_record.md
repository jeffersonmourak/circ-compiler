# Phase 2 — Sweep and record

> **Dependencies:** Phases 0–1 shipped and committed.
> **Warnings:** No new behaviour lands here. A defect the sweep finds is a slice of this phase only if it regresses a Phase 0–1 test, the driver plan's tests or the protocol goldens; anything else is a follow-up. `DOCS/prompts/ARCHIVE.md` runs only when the human asks.

## Goal

The console has been driven from every face on every shipped example that has something to drive, in both themes; a copied script has replayed through the CLI; the eager graph's growth is known; the decisions doc holds every locked decision the phases exercised; the plan is ready to archive with its follow-ups named.

## Scope

**In scope:**
- The human's walk of `/playground` in both themes: `four-bit-adder` driven from the canvas, the Data tab and the console with every line in the log in order; `ram-write-read` clocked from the console, a cell written and cleared in the Memory tab, the log copied as a script and replayed through `circ-compile tests/fixtures/circuits/sim_ram_write_read.circ --sim`; `rom-lookup` with an image edited and loaded in the Memory tab (the comment), a `poke`, a `reset`; `sr-latch` from the Data tab's toggles; a recompile mid-session (`# session ended`, the handshake, the title); a theme flip with the terminal's colours in both; the scroll lock on a long log.
- The machine half: every shipped example compiled and driven through the executor as the driver plan's sweep did, now with page events echoed through `commandFor` over a session, so the log of a scripted scenario is asserted against the same scenario typed.
- `bun run bundle` against the plan's start (104.9 KB raw / 37.3 KB gzip).
- `DOCS/decisions/playground.md` reread against decisions 1–11; missing entries added.
- Follow-ups in the completion entry.

**Explicitly deferred:**
- The archive itself.

## File & Module Topology

**New files:** None.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `DOCS/decisions/playground.md` | Completed for this initiative. |
| site | `DOCS/STATUS.md` | The sweep, measurement, reread and completion entries. |

**New dependencies:** None.

## Data & State

None introduced. The sweep's record is prose in STATUS: one row per example with what was driven from where and what the log showed.

## Execution & Concurrency Model

Not applicable.

## Persistence & I/O

None.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The walk | STATUS table of example × face, both themes, plus the machine half. | Every row "ok", or a defect with its fix slice. |
| 2 | The measurement | The eager graph's raw and gzip before and after, in STATUS. | Numbers recorded; the lazy chunks unchanged. |
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
