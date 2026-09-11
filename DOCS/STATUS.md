# Implementation Status

## 2026-09-11 — Phase 0 — Trim and commit the handoff

**What shipped:** Trimmed the home-page design handoff to its reproducible reference files and indexed the active plan bundle.
**Files touched:** `DOCS/design/design_handoff_home_page/`, `DOCS/PLANS_PROMPT.md`, `DOCS/PLANS/`, `DOCS/index.md`, `DOCS/STATUS.md`
**Tests:** no site code changed; verified the retained file set and the absence of `.ttf` and `.DS_Store` files; `git diff --cached --check` passed
**Next slice:** Add the renderer-free pin-line formatter and extend the token guard to `.home-` and `.lc-` rules.
**Notes:** The stale handoff copy at `site/src/utils/circ-assets.mjs` was removed with the font payload. The required retained files total 455,497 bytes, so the plan's 400 KB estimate was recorded as inaccurate in Recurring Traps.

## 2026-09-11 — Phase 0 — The line and the guard

**What shipped:** Added a renderer-free pin-line formatter and root-pin collector, with token checks covering playground, home-page and live-canvas selectors.
**Files touched:** `site/src/scripts/pin-line.ts`, `site/test/pin-line.test.ts`, `site/test/bench-tokens.test.ts`, `DOCS/PLANS_PROMPT.md`, `DOCS/STATUS.md`
**Tests:** added five pin-line cases; ran `bun test test/pin-line.test.ts test/bench-tokens.test.ts`, result 9 pass, 0 fail
**Next slice:** Add the optional source, values, link and fitted-viewport surfaces to `LiveCanvas` without changing gallery output.
**Notes:** `rootPins` receives kind values from the dynamically loaded renderer; this keeps renderer code out of the eager helper and avoids hand-copied wire bytes.

## 2026-09-11 — Phase 0 — LiveCanvas grows, and the gallery does not move

**What shipped:** Added optional source, values, link and parent-fit surfaces to `LiveCanvas`; cards that request none retain the gallery's original attributes and opening child order.
**Files touched:** `site/src/components/LiveCanvas.astro`, `site/src/styles/global.css`, `site/test/app-layout.test.ts`, `site/test/canvas-memory.test.ts`, `site/test/renderer-pin.test.ts`, `DOCS/PLANS_PROMPT.md`, `DOCS/STATUS.md`
**Tests:** ran `bun --bun run build` and `bun test test/canvas-memory.test.ts test/island-smoke.test.ts test/renderer-pin.test.ts test/app-layout.test.ts test/bench-tokens.test.ts`, result 65 pass, 0 fail
**Next slice:** Replace the landing page's tagline, preview and standalone canvas with the complete interactive hero.
**Notes:** The fitted variant keeps its mount hidden until ready and overrides the shared canvas height to `100% !important`, as the renderer's parent viewport requires. `app-layout.test.ts` now freezes those exact non-app selectors too.

## 2026-09-11 — Phase 0 — The hero

**What shipped:** Replaced the landing page's introductory tagline, preview and standalone canvas with the designed headline, calls, download chip and source-backed live half-adder card.
**Files touched:** `site/src/components/LiveCanvas.astro`, `site/src/components/OpenInPlayground.astro`, `site/src/pages/index.astro`, `site/src/styles/global.css`, `site/test/island-smoke.test.ts`, `DOCS/STATUS.md`
**Tests:** ran `bun --bun run build` and `bun test test/island-smoke.test.ts test/content-artifacts.test.ts test/site-labels.test.ts test/bench-tokens.test.ts test/canvas-memory.test.ts`, result 58 pass, 0 fail
**Next slice:** Run every site gate, record route sizes and add the exercised home-page decisions.
**Notes:** The hero's checked example link uses `OpenInPlayground` through a named values-line slot; its optional class prop preserves the gallery's default `.oip` output.

## 2026-09-11 — Phase 0 — The walk, the numbers, the record

**What shipped:** Reconciled the landing and gallery assertions, recorded the five exercised decisions, and completed every Phase 0 gate.
**Files touched:** `DOCS/decisions/home-page.md`, `DOCS/decisions/index.md`, `DOCS/PLANS/PHASE_0_handoff_hero.md`, `DOCS/STATUS.md`
**Tests:** ran `bun test test/pin-line.test.ts test/bench-tokens.test.ts` (9 pass), `bun --bun run build`, `bun test` (622 pass), `bun --bun run typecheck` (0 errors, 0 warnings, 21 hints), and `bun run bundle` (pass)
**Next slice:** None in Phase 0; stop before Phase 1.
**Notes:** At baseline commit `56eb8fd`, `/` and `/gallery` each loaded 2 files, 3,869 B raw and 2,006 B gzip. After Phase 0 each loads 2 files, 5,242 B raw and 2,627 B gzip; both remain below the 10,240 B gzip ceiling. The hero keeps `cell=14`; visual scale review remains in Phase 3's one browser pass.

## 2026-09-11 — Phase 0 — Correct the rendered hero after review

**What shipped:** Corrected defects missed by the structural tests: inherited pre padding, border and code font; doubled source-line spacing; the dark Shiki background; compounded main/hero padding; header spacing; and the unusable narrow canvas. Basic hero stacking was brought forward from Phase 3 after the user's design review.
**Files touched:** `site/src/styles/global.css`, `DOCS/STATUS.md`
**Tests:** Fresh `bun --bun run build`; 43 passing token, app-layout and built-island tests; `bun run bundle` passed. Browser captures at 1100, 1440 and 700 in both themes; no runtime exceptions. A native click on input a produced `a = 1 · b = 0 → sum = 1 · carry = 0`; flipping the theme retained that text and the identical canvas node.
**Next slice:** Await review of corrected Phase 0; Phase 1 has not begun.
**Notes:** The previous completion entry established test success, not visual fidelity. The corrected hero occupies the full 1100px capped column with 40px side padding; its stage is 210px tall and source lines are 21.875px apart. At 700px the canvas is 626px wide rather than 19px. Screenshots and the CDP verification script are under `/var/folders/91/0hwz8chx0d12hz5x00f53vrm0000gn/T/opencode/`, named `home-review-{light,dark}-{1100,1440,700}.png` and `home-review.ts`. JavaScript sizes remain 5,242 B raw / 2,627 B gzip on both landing and gallery routes.

## 2026-09-11 — Phase 1 — The language card

**What shipped:** Replaced the three prose sections with the handoff's vocabulary and three-step pipeline card, heading and lede. Added token-based section styling and usable narrow stacking.
**Files touched:** `site/src/pages/index.astro`, `site/src/styles/global.css`
**Tests:** Fresh build and built-island assertions verify four vocabulary rows, three steps and removal of the former prose.
**Next slice:** The preview section.
**Notes:** Corrected the board's slice and import spellings to `a[0..2]` and `import adder "adder.circ"`. The import chip wraps to keep its complete syntax visible.

## 2026-09-11 — Phase 1 — The preview section

**What shipped:** Restored the half-adder source and schematic through `CodePreview`, framed with the handoff's heading, lede, checked playground link and status row. Landing-scoped rules join the existing panes into one frame.
**Files touched:** `site/src/pages/index.astro`, `site/src/styles/global.css`, `site/test/island-smoke.test.ts`
**Tests:** Built-island checks confirm section order, one preview figure, both status labels and the checked example target.
**Next slice:** The twin and record.
**Notes:** `CodePreview.astro` itself is unchanged.

## 2026-09-11 — Phase 1 — The twin and record

**What shipped:** Rewrote the landing Markdown twin and llms.txt description; recorded the preview and mirror decisions. The twin follows visible sections, without a premature gallery heading.
**Files touched:** `site/scripts/build-llm-mirror.ts`, `site/test/site-labels.test.ts`, `DOCS/decisions/home-page.md`, `DOCS/decisions/index.md`, `DOCS/STATUS.md`
**Tests:** `bun --bun run build`, `bun test` (623 pass), `bun --bun run typecheck` (0 errors, 0 warnings, 21 hints), and `bun run bundle` passed. After the final figure CSS adjustment, a fresh build and 40 relevant tests passed. Chrome captures cover light/dark at 1100, 1440 and 700px; section and figure scroll widths match their client widths, with no runtime exceptions. Screenshots: `home-phase1-{light,dark}-{1100,1440,700}.png` in the same scratch directory as the Phase 0 captures.
**Next slice:** Stop before Phase 2.
**Notes:** Eager JavaScript remains 5,242 B raw / 2,627 B gzip for `/` and `/gallery`. Shared main width/padding and nav-width edits appeared concurrently in global.css and were preserved. Phase 1 changes remain uncommitted, alongside the staged Phase 0 implementation; the shared stylesheet is not restaged wholesale.

## 2026-09-11 — Phase 2 — The metadata module

**What shipped:** Added source-derived pin counts and memory capacity for single-file tiles, with rejection of file markers and multiple memories.
**Files touched:** `site/src/scripts/tile-meta.ts`, `site/test/tile-meta.test.ts`
**Tests:** Four metadata tests pass, including all three shipped examples and concat commas inside output bindings.
**Next slice:** The thumbnail variant.
**Notes:** The approved Phase 0–1 implementation and user layout/nav edits were committed together as `aef1cbd` before Phase 2 began.

## 2026-09-11 — Phase 2 — The thumbnail

**What shipped:** Added the optional noninteractive thumbnail variant, native-width cropping, safe vertical centering and an inert loading indicator inside the tile link.
**Files touched:** `site/src/components/LiveCanvas.astro`, `site/src/styles/global.css`, `site/test/app-layout.test.ts`, `site/test/renderer-pin.test.ts`
**Tests:** Gallery markup guards pass; browser measurements confirm 150px outer slots and native canvas widths of 400, 840 and 300px at cells 5, 6 and 6.
**Next slice:** The tiles and twin.
**Notes:** The plan's nested button was replaced with a span to keep each tile a single interactive anchor. Short circuits center vertically; oversized ones crop from the top.

## 2026-09-11 — Phase 2 — The tiles, twin and record

**What shipped:** Added the three selected tiles with metadata, ledes, source-owned ROM image and gallery links. Updated the landing twin and llms.txt description and recorded decisions 3 and 5.
**Files touched:** `site/src/pages/index.astro`, `site/scripts/build-llm-mirror.ts`, `site/test/canvas-memory.test.ts`, `site/test/island-smoke.test.ts`, `DOCS/decisions/home-page.md`, `DOCS/decisions/index.md`, `DOCS/STATUS.md`
**Tests:** Full suite: 628 pass. Typecheck: 0 errors, 0 warnings, 21 hints after narrowing the optional artifact field. Fresh build and bundle gate pass; final CSS adjustment passed 62 targeted tests. Chrome at 1100, 1440 and 700px in both themes: zero thumbnails mounted before scrolling; all three mounted after scrolling; no runtime exceptions; a native click over the ROM thumbnail navigated to `/gallery#rom-lookup` at every width. Captures: `home-phase2-{light,dark}-{1100,1440,700}.png` in the session scratch directory.
**Next slice:** Stop before Phase 3.
**Notes:** `/` and `/gallery` each grew from 5,242 B raw / 2,627 B gzip to 5,354 B raw / 2,660 B gzip, below the 10,240 B ceiling. Markdown links omit fragments because Markdown titles do not share the HTML slug anchors. Concurrent user edits gave tiles 2rem spacing, individual borders and hover transitions; those edits are preserved. Phase 2 is implemented but not committed; global.css remains unstaged for combined review.

## 2026-09-11 — Preview code-block correction

**What shipped:** Scoped strict monospace sizing and line height to the landing preview, removed inherited code font shrinkage, and constrained each grid pane so long lines scroll inside it. The two-panel presentation and gallery styles are preserved.
**Files touched:** `site/src/styles/global.css`, `DOCS/STATUS.md`
**Tests:** Fresh build, 33 passing token/island tests, and bundle gate. Browser checks at 1100, 1440 and 700px in both themes confirm 13px source text and 12.5px schematic text in the strict monospace stack; both snippets fit at those widths. Captures: `preview-fixed-{light,dark}-{1100,1440,700}.png` in the session scratch directory.
**Next slice:** Wait for the user's confirmation to commit and begin Phase 3.
**Notes:** No commit or Phase 3 work was performed.

## 2026-09-11 — Phase 3 — Install, lineage and responsive layout

**What shipped:** Added the install heading, platform/license line and full-width download row. Gave lineage its final spacing while retaining its text. Completed the narrow install layout and added a guard for all home-page selector scopes.
**Files touched:** `site/src/pages/index.astro`, `site/src/styles/global.css`, `site/scripts/build-llm-mirror.ts`, `site/test/island-smoke.test.ts`, `site/test/app-layout.test.ts`, `DOCS/STATUS.md`
**Tests:** Fresh build; 629 site tests pass; typecheck reports 0 errors, 0 warnings and 21 existing hints; bundle check passes; `zig build test-all` passes.
**Next slice:** Final browser pass and decision/archive record.
**Notes:** The prior phase and preview fix were committed as `5259b05`. Most stacking rules shipped during earlier visual corrections, so the install and remaining responsive work were verified together. Route sizes stay 5,354 B raw / 2,660 B gzip for both `/` and `/gallery`.

## 2026-09-11 — Phase 3 — Final browser pass

**What shipped:** Verified the finished page and reconciled a concurrent removal of the lineage paragraph in both the page and its Markdown twin. This supersedes the prior entry's retained-lineage description.
**Files touched:** `site/src/pages/index.astro`, `site/scripts/build-llm-mirror.ts`, `site/src/styles/global.css`, `site/test/island-smoke.test.ts`, `DOCS/STATUS.md`
**Tests:** Fresh build, 51 relevant tests and bundle gate pass after lineage removal. Final Chrome run completed without runtime exceptions; input a toggles the settled values line in both themes. All thumbnails defer until near the viewport and retain native pixel widths. The install link fits its container and stacks below 800px.
**Next slice:** Finish decisions and prepare the archive draft for review.
**Notes:** Captures use the production build served locally, not the dev server. Files are `/var/folders/91/0hwz8chx0d12hz5x00f53vrm0000gn/T/opencode/home-4a-<mode>-<width>.png`. An earlier run timed out during an extra gallery navigation after its captures; the final run omitted that already-verified Phase 2 navigation and completed normally.

| View | Mode | Width | Result |
| --- | --- | --- | --- |
| Hero, source, language, preview, tiles, install, footer | light | 1100 | ok; input a produces sum 1, carry 0 |
| Hero, source, language, preview, tiles, install, footer | dark | 1100 | ok; second click restores all-low state |
| Full page and native-size thumbnail crops | light | 1440 | ok; user's wider layout retained |
| Full page and native-size thumbnail crops | dark | 1440 | ok |
| Stacked page and install row | light | 700 | ok; install row uses column layout |
| Stacked page and install row | dark | 700 | ok |
