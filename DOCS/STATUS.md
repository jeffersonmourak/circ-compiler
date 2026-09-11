# STATUS — playground bench

Rolling log of shipped slices. Newest at the bottom. The plan is `DOCS/PLANS_PROMPT.md`; the phase specs are under `DOCS/PLANS/`.

## 2026-09-11 — Phase 0 — Trim and commit the handoff

**What shipped:** The design handoff tracked under `DOCS/design/design_handoff_playground_bench/` per decision 3 (25 files, 408 KB): the README, the source map, the design file, `support.js`, `circ-scenes.js`, the CircDS bundle with its two `woff2` faces. Removed from the tree: `circ-site-theme.js`, `circ-skins.js`, `site/src/utils/circ-assets.mjs`, 32 JetBrains Mono `.ttf` files. The plan prompt, the eight phase specs, and a row in `DOCS/index.md`. Commit `3fb1953`.
**Files touched:** `DOCS/design/**`, `DOCS/PLANS_PROMPT.md`, `DOCS/PLANS/PHASE_0..7_*.md`, `DOCS/index.md`
**Tests:** none added; `find DOCS/design -name '*.ttf'` empty; `git diff --cached --stat` 6,755 insertions
**Next slice:** the chrome yields and the guards land.
**Notes:** The handoff carries 32 TTFs, not the 36 the plan prompt said. `support.js` is byte-identical to the archived canvas-theme copy but the design file needs it beside it, so it stays.

## 2026-09-11 — Phase 0 — The chrome yields and the guards land

**What shipped:** `Base.astro` renders `<Nav />` and `<Footer />` for the default layout only; the app block is one viewport row (`100vh` then `100dvh`), `main` has no padding, the `.site-footer` app rules are gone. `site/test/bench-tokens.test.ts` (decision 12) holds every colour and face in a `.pg-` rule to a token and passed on the existing rules without a fix. `app-layout.test.ts` gained the `Base.astro` guard. Commit `9a7e380`.
**Files touched:** `site/src/layouts/Base.astro`, `site/src/styles/global.css`, `site/test/app-layout.test.ts`, `site/test/bench-tokens.test.ts`
**Tests:** added `bench tokens › the guard sees the rules`, `› every colour in a .pg- rule is a token`, `› every face in a .pg- rule is a token`, `› the allowances are what they say`, `app layout › Base renders the site chrome for the default layout only`; ran `bun --bun run build && bun test && bun --bun run typecheck && bun run bundle`, 537 pass
**Next slice:** the frame and the nav.
**Notes:** `dist/playground/index.html` contains no `site-nav` and no `site-footer`; `dist/index.html` still does. The narrow block's `overflow: visible` still releases the lock below 800px.

## 2026-09-11 — Phase 0 — The frame and the nav

**What shipped:** `.pg` is a row grid (`48px minmax(0, 1fr) 24px` this slice). `.pg-nav`: the wordmark, the breadcrumb (`<group> / <name> ▾`, rendered with the tree by `renderCrumb`), the status cluster, Download (label = artifact file name, `.pg-action-meta` = size) and Share restyled per the design file, `ThemeToggle`. `.pg-statusline`: identity, the footer's signature verbatim, the announcement channel, the promise. `.pg-statusbar` deleted; the banner moved into the editor pane so the frame's tracks always match its children. Commit `c08cfb2`.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/test/island-smoke.test.ts`, `site/test/app-layout.test.ts`
**Tests:** `island-smoke › the playground mounts…` extended (no site chrome, nav, crumb, status line, banner placement, Download label and meta); `app layout › the frame is the bench rows`; the rows branch in `the app shell hands its height down`; 538 pass
**Next slice:** the two regions and the bridges.
**Notes:** Deviation from the spec: the banner moved in this slice rather than slice 4, because `.pg` became a grid here and a shown banner would have been a fifth item in three tracks. In the harness the status word is `Error` (no worker), so the smoke test asserts the cluster's presence, not `Idle`.

## 2026-09-11 — Phase 0 — The two regions and the bridges

**What shipped:** `.pg-panes` is `.pg-body` on `var(--pg-source-w, 480px) 1px minmax(0, 1fr)`; the source region on `--pane-bg`, the canvas region on `--bg` with the dot grid (`--pg-dot`, under the content through `isolation: isolate` and `z-index: -1`), no border or radius on either; the hairline is the splitter (1px, a 9px hit band). `splitter.ts` grew the pixel unit (`clampPx`, `pxBounds`, `pxFromPointer`, `stepPx`; `unit: 'px'`), and the main splitter runs on it, unpersisted. The tree is a card under the breadcrumb (`aria-expanded`, `aria-controls`, `Escape`, outside click, focus return; `.pg-ws-toggle` gone, `.pg-ws-new` as the card's footer). Today's tabs stay inside the canvas region. The narrow block stacks `.pg-body` and spans the card. Commit `3211415`.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/src/scripts/splitter.ts`, `site/test/splitter.test.ts`, `site/test/island-smoke.test.ts`, `site/test/app-layout.test.ts`
**Tests:** added `splitter › clampPx holds the bounds and rounds to whole pixels`, `› pixel bounds reserve the far pane`, `› pxFromPointer is the distance from the near edge, never negative`, `› the keyboard contract, pixels`, `island-smoke › the breadcrumb opens the tree and gives focus back`; 543 pass
**Next slice:** the terminal line.
**Notes:** `pxBounds(0)` leaves the maximum unbounded: happy-dom reports no width, and a real browser paints once before the observer fires, so the first paint is 480, not the 320 minimum. The rename input's own `Escape` is left to it; the card closes on the next one.

## 2026-09-11 — Phase 0 — The terminal line

**What shipped:** `.pg` is the four rows (`48px minmax(0, 1fr) var(--pg-term-h, 40px) 24px`). `.pg-term` is row 3: the closed line (`.pg-term-title` mirroring the console title, `>` in accent, the last command, `·`, the reply in the line's kind colour, `Console ▴`, `Memory` at half opacity with `aria-disabled` until a memory is declared) and the drawer moved in from the output pane. `setDrawerOpen` writes `data-open` on the row and `--pg-term-h: 320px` on the frame together; `setDrawerShown` is gone and the row is always on screen; the drawer's divider is hidden until Phase 6 gives it the height. `terminal-line.ts` `summaryOf` reads the transcript; the line re-renders on every `consoleAppend` and `consoleClear`. Commit `4a58e61`.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/src/scripts/terminal-line.ts`, `site/test/terminal-line.test.ts`, `site/test/island-smoke.test.ts`, `site/test/app-layout.test.ts`
**Tests:** added `terminal line › no echo yields nulls`, `› the last echo and its reply`, `› a pending command has no reply`, `› notes after the echo are skipped, and an error is a reply`, `island-smoke › the terminal line opens the drawer and follows the transcript` (replacing `the drawer follows the output tab…`); 547 pass
**Next slice:** the walk, the numbers, the record.
**Notes:** The line reads liveness off the console note's `hidden` flag, not the session record: `renderTermLine` runs from `consoleNewSession` during boot, before `sim` is declared, and the first build of this slice threw `Cannot access before initialization` in the island. A full `bun test` once hung for six minutes while the human's `astro dev` was starting in the same worktree; it did not recur.

## 2026-09-11 — Phase 0 — The walk, the numbers, the record

**What shipped:** Every `island-smoke` selector reconciled with the frame (done slice by slice; the shell chain is `['main', '.pg'], ['.pg', '.pg-body']` on the rows branch). `DOCS/decisions/playground-bench.md` with the entries for decisions 1, 3, 4, 6 and 12, registered in `DOCS/decisions/index.md`. This log. Board 2a's frame captured in both modes through headless Chrome against the dev server (`bench-2a-light.png`, `bench-2a-dark.png`, in the session's scratchpad and handed to the human; not committed).
**Files touched:** `DOCS/decisions/playground-bench.md`, `DOCS/decisions/index.md`, `DOCS/STATUS.md`
**Tests:** none added; the four gates green at `4a58e61`
**Next slice:** Phase 1 — the source region (`DOCS/PLANS/PHASE_1_source_region.md`), on the human's word.
**Notes:** `bun run bundle`, `/playground`: baseline at `59e884c` 4 files, 107.7 KB raw, 38.2 KB gzip; after Phase 0 4 files, 110.5 KB raw, 39.0 KB gzip (ceiling 120.0 KB gzip). The growth is the terminal line, the card handling and the splitter's second unit. Seen in the walk: with no session the line reads `Compile a circuit first.` even while the status cluster says Live, because the console note says the same until a Simulate or Data tab builds a session — consistent, and Phase 2's always-live canvas region will change when the first session is built.
