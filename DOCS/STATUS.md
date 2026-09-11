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
