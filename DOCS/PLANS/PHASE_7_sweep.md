# Phase 7 — Sweep and record

> **Dependencies:** Phases 0–6 shipped and committed; `DOCS/STATUS.md`'s latest entry is Phase 6's last slice.
> **Warnings:** No new markup or behaviour lands here. A defect the sweep finds is fixed as a slice of this phase only when it is a regression against a board (2a, 3a–3f), a Phase 0–6 test, or a locked decision; anything else is a follow-up in the final STATUS entry. `DOCS/prompts/ARCHIVE.md` is invoked only when the human asks; this phase prepares for it and stops. Screenshots are the human's to take unless a browser or the `run` skill is available to the agent; the agent never claims a board "matches" it has not seen. Decisions 3, 15 and 16 of `DOCS/PLANS_PROMPT.md` are authoritative here.

## Goal

The bench has been looked at as a reader would see it: every built board in both themes at two desktop widths and the stacked layout at 700, on a named circuit each, with the README's numbers checked against the page; every control reached by keyboard; the one `role="status"` channel heard. The decisions doc maps all sixteen locked decisions; the two documents that name the old surfaces read true against the bench; the handoff is under `DOCS/archive/design/playground-bench/`; the budget is recorded; the archive file is drafted and waiting for the human's review with the plan bundle still in place.

## Scope

**In scope:**
- The walk: boards 2a, 3a, 3b, 3c, 3d, 3e, 3f × `data-theme` light and dark × 1440 and 1024 wide, plus the stacked layout at 700 (decision 15), recorded one row per board × mode × width in STATUS.
- The redraw timing on `example:four-bit-adder`: hover over a gate and one `zoomBy` step, `performance.now()` around the renderer's draw through the browser profiler.
- The accessibility walk: Tab order through the nav, the switcher, the file tabs, the editor, the footer, the view switch, the Data button and panel, the terminal line and drawer; `Escape` out of the popover and the panel; the `role="status"` span the only announcer.
- `DOCS/decisions/playground-bench.md` reread against every STATUS entry and the sixteen decisions; the closing map paragraph written in the shape of `DOCS/decisions/canvas-theme.md:157-165`.
- `DOCS/sim-protocol.md:217-240` ("The protocol in the browser") reread against the bench; `DOCS/decisions/index.md` row for `playground-bench.md` present and complete.
- `DOCS/design/design_handoff_playground_bench/` moved to `DOCS/archive/design/playground-bench/`; `DOCS/archive/index.md` gains a row; `DOCS/index.md`'s pointer at `PLANS_PROMPT.md` (added in Phase 0) repointed at `archive/index.md`.
- `bun run bundle` numbers for `/playground` recorded beside the Phase 0 baseline.
- `DOCS/archive/plan-playground-bench.md` written per `DOCS/prompts/ARCHIVE.md` Step 4; the bundle deletion (Step 5) waits for the human.
- The completion STATUS entry with follow-ups named.

**Explicitly deferred:**
- Deleting `DOCS/PLANS_PROMPT.md`, `DOCS/PLANS/`, `DOCS/STATUS.md` (the archive prompt's Step 5, after the human reviews the archive file).
- Any polish of the stacked layout beyond "every control reachable" (decision 15).
- Board 1a, and every item in the plan prompt's deferred list.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| docs | `DOCS/archive/design/playground-bench/*` | The handoff, moved by `git mv` from `DOCS/design/design_handoff_playground_bench/`. |
| docs | `DOCS/archive/plan-playground-bench.md` | The highlight view of this plan, drafted for review. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| docs | `DOCS/decisions/playground-bench.md` | Completed; the closing map of decisions 1–16 and the follow-ups paragraph. |
| docs | `DOCS/decisions/index.md` | The `playground-bench.md` topic's bullet list completed. |
| docs | `DOCS/archive/index.md` | One row for `plan-playground-bench.md`. |
| docs | `DOCS/index.md` | The plan pointer repointed at `archive/index.md`. |
| docs | `DOCS/sim-protocol.md` | Only if the reread finds a surface still named the old way. |
| docs | `DOCS/STATUS.md` | The walk table, the timing entry, the completion entry. |
| site | `site/src/**` | Only for a regression fix under the Warnings rule; each such fix is its own slice. |

**New dependencies:** None.

## Data & State

None introduced. The walk's record is a table in STATUS:

```
| board | circuit | mode | width | result |
| 2a | scratch `nand` (board 2a's source, typed) | dark | 1440 | ok |
| 3b | example:two-bit-adder | light | 1024 | footer expands to 4 rows; `file:line:col` drives the editor |
```

`result` is `ok` or the defect and the slice number that fixes it.

## Execution & Concurrency Model

Not applicable. The phase runs the site's dev server (`bun run dev` in `site/`), the browser, and the existing gates; it introduces no code of its own.

## Persistence & I/O

`git mv DOCS/design/design_handoff_playground_bench DOCS/archive/design/playground-bench`, staged by path. `DOCS/design/` is then empty and disappears from the tree. Nothing else.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The walk | The STATUS table: 7 boards × 2 modes × 2 widths, plus 7 boards at 700, each on the circuit and with the checks of the board list below. Screenshots named `bench-<board>-<mode>-<width>.png` where the human or a browser produces them; a row without one says "not seen". | Every row `ok`, or a defect with its fix slice; no row missing. |
| 2 | Redraw timing | Profiler numbers on `example:four-bit-adder` at `cell 14`: one hover redraw and one `zoomBy` redraw, in STATUS. | Each under one frame at 60 Hz (16 ms) on the human's machine, or the cause named as a follow-up. |
| 3 | The keyboard and the announcer | The a11y walk recorded in STATUS: the Tab order as a list, `Escape` from popover and panel with focus returned to the opener, and the `role="status"` text after Share, after a file rename, after a store note. | The smoke test's a11y assertions (Phase 0–6) green; the walk finds no control unreachable. |
| 4 | Decisions and documents | `playground-bench.md` complete with its closing map; `sim-protocol.md` "The protocol in the browser" reread; `decisions/index.md` bullets complete. | Each decision 1–16 has an entry or a line saying it was not exercised; `grep -n 'Simulate tab\|Data tab\|Diagnostics tab\|status bar' DOCS/*.md site/src` finds nothing outside `DOCS/archive/`. |
| 5 | Move the handoff and record the budget | `DOCS/archive/design/playground-bench/`, the archive index row, the `DOCS/index.md` pointer, `bun run bundle` numbers in STATUS beside Phase 0's. | `git status` shows only the move and the three index files; `bun test` untouched (no code moved); `/playground` under its ceiling. |
| 6 | Draft the archive | `DOCS/archive/plan-playground-bench.md` per `ARCHIVE.md` Step 4 (header with the full SHA of the Phase 7 sign-off commit to come, goal, phase highlights, API surface, papercuts, decisions pointers). | The file reviewed by the human; the bundle still present; `ARCHIVE.md`'s "when to invoke" conditions all true except the human's ask. |
| 7 | Completion entry | STATUS declares the plan complete with the follow-ups and no next slice. | The entry's `Next slice:` line reads "none — plan complete; archive on request". |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

### The board list for slice 1

The circuit is the catalogue id (`site/src/utils/playground-store.ts:556`, `:566`); board 2a's `nand` is not a shipped project, so it is typed as a scratch project from the board's editor text. The numbers are the handoff's (`DOCS/design/design_handoff_playground_bench/README.md`), and decision 2 makes the design file's inline styles the tie-breaker.

| Board | Circuit | State | Checks |
|-------|---------|-------|--------|
| 2a | scratch `nand` (typed) | Live view, everything closed | Rows `48px · 1fr · 40px · 24px`; source column `480px`, one `1px --border` hairline; dot grid `18px`; nav: wordmark mono 17px 700, breadcrumb, `8px` accent dot, Download outline with `name.wasm` and size in `--muted`, Share filled, theme toggle; view switch at `14px 16px`, active segment `--accent` on `--bg`; hint bottom-left and zoom bottom-right `16px` in, `12px` up; terminal line `--code-bg`, `>` in `--accent`; status line `1fr auto 1fr`, signature with the beating heart; no `.pg-statusbar`, no `.pg-tabs`, no `.pg-ws` sidebar. |
| 3a | `example:half-adder` open, switcher open | Popover open | Breadcrumb border `--accent` with the `3px` ring at 18%, chevron `▴`; popover `340px` at `top 56px`, radius `8px`, shadow `0 12px 32px`; search row with `⌘K`; groups uppercase `10.5px 0.08em`; open project in `--accent`, its files one level in with the active file on `--pane-label-bg` and a `2px` left rule; `+ New circuit` and `Import .circ`; scrim; the source column width unchanged before and after (decision 13). |
| 3b | `example:two-bit-adder` | Footer expanded | Source column at `440px` by the splitter; footer `30px` with counts left and `N lines · N components · N nets` right; expanded list on `--pane-label-bg`, grid `14px 104px 52px 1fr`, `file:line:col` in `--accent` and a click moves the editor's cursor; the gear opens the settings in place of the list (decision 7). |
| 3e | `example:two-bit-adder` | Schematic view | Region on `--code-bg`, no grid; `<pre>` in `--font-mono-strict 20px / 1.35`, centred; `unicode | ascii` and Copy top-right; `rows × cols chars` bottom-right; the box-drawing glyphs hold the grid in both faces. |
| 3f | `example:half-adder` | Truth view | Card on `--pane-bg`, radius `8px`; cells `7px 14px` mono 12.5px; header uppercase `10.5px`; a `1px` rule before the first output column; HIGH `--fg` 700, LOW `--muted` 500; the row matching the session's pins tinted `--accent` at 14%; a row click drives the pins and the console echoes each `set` (decision 11); chip `N input bits · R rows · cap C`; `Copy as markdown · CSV`. Then `example:four-bit-adder` with cap 6 (over the cap): the filtered rows of decision 10 and the chip's reason. |
| 3d | `example:four-bit-adder` (stands in for the Hack ALU; 2 × 4-bit inputs, `s[4]` and `cout` out) | Data panel open | Card `312px` at `top 52px; right 16px`; header with grip, `Data` 600, `N in · M out`, base segmented, `✕`; sections on `1fr 36px 92px`; bus fields on `--code-bg`, right-aligned, accepting `0x`, `0b`, `_`; outputs read-only 700; footer hint and Reset; region `padding-right: 344px` and the canvas refit; Data button filled while open; drag by the grip, clamped to the region; the position kept per project after a switch away and back. Also `example:half-adder` for the `22px` toggle knobs (HIGH filled, LOW outlined). |
| 3c | `example:rom-lookup` | Drawer open | Terminal line grows to `320px` on click and on focus; split `minmax(0,1fr) 1px 560px`; console header `34px` with the accent underline, Clear · Copy script · Copy log, `▾`; log `12.5px / 1.5` with `note`, `echo`, ok kinds in their tokens; prompt caret `7×14px`; memory header with `code`, `rom[8,4] · 16 words`, `live` chip, base; toolbar `◂ 0x0 – 0xf ▸`, `jump`, Refresh · Clear · Load image… · Save; grid `40px repeat(8, 1fr)` with the address column on `--pane-label-bg`; unknown `?` at 55% dotted, addressed word in `--accent`, the edited cell underlined `2px --accent`; the height kept across a reload. Then `example:ram-write-read` for a RAM. |
| 700 (all) | each board's circuit | Stacked | Regions stack in order source, canvas, terminal line, status line; the nav wraps its two clusters; popover and panel are full-width cards under the nav; the drawer opens in place; every control reachable by pointer and keyboard; the page scrolls, the body does not clip (`global.css:2042-2059`). |

Each board is checked with `data-theme="dark"` and `"light"` (the `ThemeToggle` in the bench nav) and at 1440 and 1024 CSS pixels wide.

## Tests

**Unit tests:** None new. A regression fix under the Warnings rule brings its own test in its own slice.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| Full site gate | `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle` | Green on the final tree; `island-smoke.test.ts` runs against the fresh `dist/`; `/playground` under `site/bundle-budget.json`'s ceiling. |
| Compiler gate | `zig build test-all` | Green and unchanged (no Zig file touched in this initiative; `ARCHIVE.md` requires it before archiving). |
| Tree gate | `git status --porcelain` after slice 5 | Only the move and the three index files; after slice 6, only the archive file. |

Run command: the two gate lines above, from the worktree root and from `site/`.

## Open Questions / Spikes

- `TODO(phase7)`: `DOCS/PLANS_PROMPT.md` Phase 7 names "`DOCS/getting-started.md`'s browser section"; that file has no playground or browser section (`grep -in 'playground\|browser' DOCS/getting-started.md` is empty). The browser document is `DOCS/sim-protocol.md:217` ("The protocol in the browser"), and slice 4 rereads that. If a getting-started paragraph on the playground is wanted, it is a follow-up, not a reread.
- `TODO(phase7)`: whether a browser is available to the agent for slice 1 (the `run` skill or a headless browser). If not, the agent fills the table's structure, runs the smoke and layout tests, and marks every visual row "not seen" for the human to take.
- `TODO(phase7)`: the archive's canonical SHA is the sign-off commit of slice 7, which does not exist when slice 6 drafts the file; the header is written with a placeholder and the human's archive session fills it, as `ARCHIVE.md` Step 2 describes.
