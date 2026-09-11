# Phase 3 — Install, the narrow layout and the record

> **Dependencies:** Phases 0–2 shipped and committed; `DOCS/STATUS.md`'s latest entry is Phase 2's last slice.
> **Warnings:** Decisions 9, 10, 14 and 15 of `DOCS/PLANS_PROMPT.md` are authoritative. This is the phase with the browser: the human asked that small fixes not restart the Chrome setup, and the pass here is the one place it is spent. A defect the pass finds is fixed as a slice of this phase only when it is a regression against board 4a, a Phase 0–2 test, or a locked decision; anything else is a follow-up in the final STATUS entry. `DOCS/prompts/ARCHIVE.md` is invoked only when the human asks; this phase prepares for it and stops. Per the Working Loop, Phase 3 commits per slice and asks once before its first slice.

## Goal

The page's tail is the board's: a section on `--code-bg` headed `INSTALL` / `Run it on your own machine.` with `Linux · macOS · Windows · GPL v3` at the right and the install line as one bordered row that links whole to `/download`; then the lineage line with its accent rule; then the footer. Below 800px every section stacks in the order the README gives and every control is reachable. The page has been looked at as a reader would see it — 1100 and 1440 wide in both themes, and 700 stacked — and the STATUS entry says what was seen. `DOCS/decisions/home-page.md` maps all fifteen locked decisions; the archive file is drafted and waiting for the human's review with the plan bundle still in place.

## Scope

**In scope:**
- The install section (`Home Page Proposal.dc.html:186-198`): `.home-install*` rules; the `.install-line` anchor restyled as the row (`padding 16px 20px; border 1px --border; radius 6px; background --bg; --font-mono 17px`, text left, `/download →` right in `--muted` 14px); the old `.install-line` rules (`global.css:1531-1550`) replaced.
- Lineage spacing (`48px 40px 40px`, the accent rule, `max-width 62ch`, `17px` italic; the text untouched, `index.astro:87-90`); the `.lineage` rule (`:1558-1565`) restated under `.home-lineage` or kept.
- The stacked layout of decision 9 under the site's `@media (max-width: 800px)`.
- The browser pass of decision 14, recorded in STATUS as a table.
- `DOCS/decisions/home-page.md` completed with decisions 9, 10, 11, 14 and 15 and a closing map of 1–15 in the shape of `DOCS/decisions/canvas-theme.md:157-165`; `DOCS/decisions/index.md`'s bullets complete.
- The twin's `Install` section checked against the page; `DOCS/archive/plan-home-page.md` drafted per `DOCS/prompts/ARCHIVE.md` Step 4; the completion STATUS entry.

**Explicitly deferred:**
- Deleting `DOCS/PLANS_PROMPT.md`, `DOCS/PLANS/`, `DOCS/STATUS.md`, and moving or deleting the handoff (the archive prompt's Step 5, after the human reviews the archive file and chooses between the two precedents of decision 2).
- Any polish below 800px beyond "every control reachable".
- The Nand2Tetris chip library, a designed mobile layout, and every item in the plan prompt's deferred list.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| docs | `DOCS/archive/plan-home-page.md` | The highlight view of this plan, drafted for review; the canonical SHA left as a placeholder for the sign-off commit. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/pages/index.astro` | The `.home-install` section around the install anchor; the lineage `p` given `home-lineage` beside `lineage` if its rule moves. |
| site | `site/src/styles/global.css` | `.home-install*`; the install row; `.lineage`; the `@media (max-width: 800px)` block for `.home-*` and the hero card's body; `.home-section` side padding at the breakpoint. |
| site | `site/test/island-smoke.test.ts` | The landing assertions gain: `.home-install` with its kicker, `h2` and the platforms line; the install anchor's `href` ends in `/download` and its text starts with `↓ Download circ-compile`; `.lineage` text verbatim; `main`'s section order complete. |
| site | `site/test/app-layout.test.ts` | One added case: every `.home-` rule inside the 800px block names only `.home-` or `.lc` selectors, and none reaches `.lc-mount` outside a `[data-circ-fit]` or `[data-circ-thumbnail]` scope. |
| docs | `DOCS/decisions/home-page.md`, `DOCS/decisions/index.md` | Completed. |
| docs | `DOCS/STATUS.md` | The walk table, the completion entry. |

**New dependencies:** None.

## Data & State

The install section (`:186-198`):

```text
.home-install        border-top 1px --border; background --code-bg; padding 40px; flex column; gap 18px
.home-install-head   flex; baseline; space-between; gap 24px; wrap
  .home-kicker (Install) · .home-install-h2  26px / 1.15; 600; margin 0   ·  .home-install-platforms  --font-mono 12.5px; --muted
a.install-line       flex; align-items center; space-between; gap 16px; padding 16px 20px; border 1px --border; radius 6px;
                     background --bg; --font-mono 17px; --fg; no underline; max-width none; white-space normal
  .install-line-target   --muted; 14px   ("/download →")
a.install-line:hover   border-color --accent   (the existing hover, :1547-1550)
```

The stacked layout (decision 9), at `@media (max-width: 800px)`:

```text
.home-section            padding-left/right 1.5rem (main's own, global.css:97)
.home-hero               grid-template-columns 1fr; gap 32px; padding-top 40px
.lc-body                 grid-template-columns 1fr   (the source above the stage; .lc-source border-right none, border-bottom --border)
.home-lang, .home-preview   grid-template-columns 1fr; the text column first (`order: -1` on .home-text)
.home-tiles              grid-template-columns 1fr
.home-gallery-head, .home-install-head   wrap (already)
a.install-line           flex-direction column; align-items flex-start; gap 6px
```

Under 600px the site's nav collapses (`global.css:357-377`) and `.lc-mount` becomes a block that scrolls (`:537-547`); the hero's `fit` scope keeps its absolute mount and the thumbnail keeps its crop, both by the scoped rules of Phases 0 and 2, so neither block rule reaches them.

The walk's record, a table in STATUS:

```
| view | mode | width | result |
| hero, values line after a click on `a` | dark | 1100 | ok |
| tiles, the ROM with its squares | light | 1440 | ok |
| stacked | dark | 700 | … |
```

`result` is `ok` or the defect and the slice number that fixes it.

## Execution & Concurrency Model

Not applicable. The phase adds static markup and CSS, runs the site's dev server (`bun run dev` in `site/`), the browser and the existing gates.

## Persistence & I/O

None new. The archive draft is a file under `DOCS/archive/`; the plan bundle stays in place until the human's archive session.

## Slices

The execution agent implements this phase one slice at a time; per the Working Loop it commits each slice and asks once before the first.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Install and lineage | The `.home-install` section, the install row, the lineage spacing; the old `.install-line` rules replaced; the twin's `Install` section checked. | `bun --bun run build`; `island-smoke`'s landing assertions extended; `bench-tokens` green. |
| 2 | The stacked layout | The 800px block for `.home-*`, `.lc-body` and the install row; `app-layout.test.ts`'s scoping case. | `app-layout`, `bench-tokens` green; the built CSS contains the block; the human's or the agent's browser at 700 in slice 3 confirms it. |
| 3 | The pass | Board 4a at 1100 and 1440 in both modes, and the page at 700, on the dev server: the hero fitted and the values line following a click, the card's source gutter, the vocabulary chips and steps, the `--preview` figure and status row, the three tiles cropped with the ROM's squares visible, the install row, the lineage rule, the footer; screenshots named `home-4a-<mode>-<width>.png` in the session scratch directory and named in STATUS; a regression fixed as its own slice. | The table in STATUS with every row `ok` or a fix slice; no runtime exception in the console; `/` under 10 KB gzip. |
| 4 | Decisions and the archive draft | `DOCS/decisions/home-page.md` complete with its closing map; `DOCS/decisions/index.md` bullets complete; `DOCS/archive/plan-home-page.md` drafted per `ARCHIVE.md` Step 4 with the SHA placeholder; the completion STATUS entry with the follow-ups and `Next slice: none — plan complete; archive on request`. | All four gates green; `zig build test-all` green (no Zig file touched; `ARCHIVE.md` requires it); the archive file reviewed by the human; the bundle still present. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `every colour in a .pg-, .home- or .lc- rule is a token` (held) | `site/test/bench-tokens.test.ts` | The install and narrow rules pass. |
| `the landing page's narrow rules stay in their scope` | `site/test/app-layout.test.ts` | Inside every `@media (max-width: 800px)` block, a rule naming `.home-` or `.lc-body`/`.lc-source`/`.lc-values` names nothing else, and no rule in the file names `.lc-mount` under a `.home-` selector without `[data-circ-fit]` or `[data-circ-thumbnail]`. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `every canvas that asks to auto-run is watched, and nothing else is` (extended) | `site/test/island-smoke.test.ts` | `dist/index.html`: `main`'s children in order `.home-hero`, `.home-lang`, `.home-preview`, `.home-gallery`, `.home-install`, `.lineage`; the install anchor's `href` and text; the platforms line; the lineage text verbatim. |
| Full site gate | `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle` | Green on the final tree; `/` and `/gallery` under the default ceiling. |
| Compiler gate | `zig build test-all` | Green and unchanged. |
| Tree gate | `git status --porcelain` after slice 4 | Only the archive draft untracked until its commit; the plan bundle and the handoff present. |

Run command: `cd site && bun --bun run build && bun test && bun --bun run typecheck && bun run bundle` from `site/`, and `zig build test-all` from the worktree root.

## Open Questions / Spikes

- `TODO(phase3):` whether a browser is available to the agent for slice 3 (the session's earlier Chrome CDP scripts under the scratch directory were for the bench and may be reused). If not, the agent fills the table's structure, runs the gates, and marks every visual row "not seen" for the human to take.
- `TODO(phase3):` the archive's canonical SHA is the sign-off commit of slice 4, which does not exist when the file is drafted; the header carries a placeholder and the human's archive session fills it, as `ARCHIVE.md` Step 2 describes.
- `TODO(phase3):` the hero's fitted scale (Phase 0's first TODO) is confirmed or corrected here, in the pass.
