# Phase 5 — Sweep and record

> **Dependencies:** Phases 0–4 shipped and committed.
> **Warnings:** No new drawing lands here. A defect the sweep finds is fixed as a slice of this phase only if it is a regression against a Phase 1–4 golden or the design file; anything else is recorded as a follow-up. `DOCS/prompts/ARCHIVE.md` is invoked only when the human asks.

## Goal

The whole site has been looked at as a reader would see it: every page with a canvas, both themes, three cell sizes, sprites resolved and unresolved, and the playground under hover. The decisions doc is complete, the renderer README matches what shipped, the handoff bundle is where the archive expects it, and the plan is ready to archive with its follow-ups named.

## Scope

**In scope:**
- A recorded walk of `/`, `/gallery`, `/tour`, `/playground` (and any reference page embedding `<LiveCanvas>`) in light and dark at `cell` 10, 14, 24, with the sprite-ready retheme observed (throttle the network so the vector fallback is visible first).
- A timing of the playground's hover redraw on `four-bit-adder` (the largest shipped example): `performance.now()` around `draw()` through the browser profiler, recorded in STATUS; the design's claim that no `shadowBlur` runs per frame verified by a profiler search for it.
- `DOCS/decisions/canvas-theme.md` reread against every phase's STATUS entries; missing decisions added.
- `circ-renderer/README.md` theme section reread against `src/utils/theme.ts` and `wire-path.ts` as pinned.
- `DOCS/design/` moved to `DOCS/archive/design/canvas-theme/` and `DOCS/archive/index.md` gains a row; `.gitignore` unchanged.
- Follow-ups listed in the final STATUS entry: decision 11 (write stamp), the range bar design, and anything the sweep found.

**Explicitly deferred:**
- The archive itself (`plan-canvas-theme.md`) — produced by the archive prompt on the human's request.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `DOCS/archive/design/canvas-theme/*` | The handoff, moved. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `DOCS/decisions/canvas-theme.md` | Completed; a closing paragraph names the follow-ups. |
| site | `DOCS/archive/index.md` | Row for the design bundle. |
| site | `DOCS/STATUS.md` | The sweep entry and the completion entry. |
| circ-renderer | `README.md` | Only if the reread finds a gap; then a renderer slice with its own commit and the human's push. |

**New dependencies:** None.

## Data & State

None introduced. The sweep's record is prose in STATUS: one line per page × mode × cell with "ok" or the defect.

## Execution & Concurrency Model

Not applicable; this phase runs no code of its own beyond the site's dev server and the existing test gates.

## Persistence & I/O

`git mv DOCS/design DOCS/archive/design/canvas-theme` staged by path. Nothing else.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The walk | STATUS table of every page × mode × cell, with sprite fallback observed. | Every row "ok", or a defect with its fix slice number. |
| 2 | Hover redraw timing | Profiler numbers for `four-bit-adder` at `cell 14`; `shadowBlur` absent from per-frame calls. | Numbers in STATUS; a redraw under one frame at 60 Hz (16 ms) on the human's machine, or the cause named. |
| 3 | Decisions and README reread | `canvas-theme.md` complete; renderer README consistent. | Each locked decision 1–16 has an entry or a line saying it was not exercised; `grep -n grid README.md` empty. |
| 4 | Move the handoff | `DOCS/archive/design/canvas-theme/`, index row. | `bun test` and `zig build test` untouched (no code moved); `git status` shows only the move and the index. |
| 5 | Completion entry | STATUS declares the plan complete with follow-ups. | The entry satisfies `DOCS/prompts/ARCHIVE.md`'s "when to invoke" conditions. |

## Tests

**Unit tests:** None new.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| Full site gate | `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle` | Green on the final tree. |
| Renderer gate | `cd ~/circus/circ-renderer && bun test && bunx tsc --noEmit` | Green at the pinned sha. |
| Compiler gate | `zig build test-all` | Green and unchanged (no Zig file touched in this initiative; the run proves the tree still builds before archiving). |

Run command: the three lines above.

## Open Questions / Spikes

- `TODO(phase5)`: whether the reference page `site/src/pages/reference/preview.md` embeds a canvas (it references `circ-renderer` by name); include it in the walk if it does.
