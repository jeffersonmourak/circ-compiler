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

## 2026-09-11 — Phase 1 — The summary module

**What shipped:** `site/src/scripts/footer-summary.ts`: `lineCount`, `projectSymbols`, `summarize(files, analysis, mapped)` and `summaryLabels`, with the boards' noun rule (memories, else chips, else pins) over the project's own symbols; nothing wired. Commit `6fe7c3f`.
**Files touched:** `site/src/scripts/footer-summary.ts`, `site/test/footer-summary.test.ts`
**Tests:** added `footer-summary › lines count a trailing newline once`, `› counts and words`, `› before an analysis`, `› the third slot`, `› a builtin file never counts`; `bun test test/footer-summary.test.ts`, 5 pass
**Next slice:** the envelope at version 2.
**Notes:** The analyze reply has no nets; the right-hand string is lines, components and the contextual noun.

## 2026-09-11 — Phase 1 — The envelope at version 2

**What shipped:** `STORE_VERSION = 2`; `View`/`VIEWS`, `FooterState`/`FooterTab`/`DEFAULT_FOOTER`, `LayoutState.sourceWidth` (`DEFAULT_SOURCE_WIDTH = 480`); `migrateV1` run by `normalize` before the version check; `normalizeFooter`, `normalizeSourceWidth`; `OutputTab`, `DockTab`, `DockState`, `DEFAULT_DOCK` gone. The island bridges the four output tabs to `view` (`viewOfTab`/`tabOfView`), the dock functions to `footer`, and the main splitter reads and commits `sourceWidth`. Commit `a79bfb1`.
**Files touched:** `site/src/utils/playground-store.ts`, `site/src/components/Playground.astro`, `site/test/playground-store.test.ts`, `site/test/fixtures/store/envelope-v1.json`, `site/test/footer-summary.test.ts`
**Tests:** added `playground store › a version-1 envelope migrates, and keeps every project`; the mismatch case moved to version 3; `view`, `footer` and `sourceWidth` normalisation cases; 553 pass
**Next slice:** the file-tab strip.
**Notes:** The island's own `type View` (the canvas face) clashed with the store's; the store's is imported as `StoredView`. Phase 0's in-memory width is now the envelope's.

## 2026-09-11 — Phase 1 — The file-tab strip

**What shipped:** `.pg-files` over the editor: one `role="tab"` per file, roving tabindex, arrows and Home/End through `showFile`, `+ file` through `addNewFile`; `renderFileTabs` runs with `renderTree`; the editor panel is labelled by the strip's current tab; `focusFileTab` prefers the tree's row while the card is open. Commits `d01b5ea`, `53dc91f` (a test's type).
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/test/island-smoke.test.ts`
**Tests:** added `island-smoke › the strip switches files and adds one`; the mount walk's strip and label assertions; 554 pass
**Next slice:** editor metrics.
**Notes:** The smoke tests share one window, so the strip test deletes the file it adds; the tree test after it expects one file. `d01b5ea` was committed with a type error in the new test (`string | undefined` into `toBe`), fixed in `53dc91f`; the gate order in the run command puts `bun test` before `typecheck`, and the error was in a test file `bun test` does not type.

## 2026-09-11 — Phase 1 — Editor metrics

**What shipped:** `.pg-cm .cm-scroller` at 14px / 1.7, `.cm-content` at `16px 0`; the gutter transparent in both palettes (`circ-editor-theme.ts`) with the theme's `opacity: 0.55` and a 32px minimum on the line-number cell (`circ-editor.ts`). Commit `b03f4a4`.
**Files touched:** `site/src/styles/global.css`, `site/src/scripts/circ-editor.ts`, `site/src/utils/circ-editor-theme.ts`, `site/test/circ-editor-theme.test.ts`
**Tests:** added `circ editor theme › the gutter is a band no more`; 555 pass
**Next slice:** the diagnostics footer.
**Notes:** None.

## 2026-09-11 — Phase 1 — The diagnostics footer, settings behind its gear

**What shipped:** `.pg-footer` replacing the dock: the 30px bar (`renderFooterBar` from `summarize`/`summaryLabels`, `data-severity` colouring the counts and showing the caret), the body on `--pane-label-bg` with the diagnostics grid (`.pg-diag` on `14px 104px 52px minmax(0, 1fr)`; a position button that jumps and highlights, a span for a placeless row, `No diagnostics.` when empty) and the settings form moved in unchanged; `showFooterTab`, `setFooterOpen`, `toggleFooter`, `Escape` with focus return; `footer` persisted; `renderDiagnostics` on the seam. Every `.pg-dock*` rule and function gone. Slices 5 and 6 of the spec shipped as one commit, `4504885`: the form needed a home the moment the dock went.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/test/island-smoke.test.ts`
**Tests:** added `island-smoke › the footer opens on the counts and on the gear, and remembers which`, `› diagnostics render as grid rows` (replacing `the dock collapses and reopens…`); 556 pass
**Next slice:** the record.
**Notes:** The first markup edit's end marker matched the output pane's closing tag, so the splitter and the whole output pane were cut with the dock and the built island threw at boot (`null is not an object (evaluating 'i.setAttribute')` in `createSplitter`); the stretch was restored from `HEAD` before the commit. A `renderDockBadge()` call at bootstrap, outside the diagnostics block, was the one reference the first pass missed.

## 2026-09-11 — Phase 1 — The record

**What shipped:** `DOCS/decisions/playground-bench.md` gained the migration, the footer and the strip; `DOCS/decisions/index.md` the three rows; this log. Board 3b captured in light mode on the two-bit adder with the footer open (`bench-3b-light.png`, in the session's scratchpad and handed to the human; not committed).
**Files touched:** `DOCS/decisions/playground-bench.md`, `DOCS/decisions/index.md`, `DOCS/STATUS.md`
**Tests:** none added; the four gates green at `4504885`
**Next slice:** Phase 2 — the canvas region and the Live view (`DOCS/PLANS/PHASE_2_canvas_live.md`), on the human's word.
**Notes:** `bun run bundle`, `/playground`: after Phase 0 110.5 KB raw / 39.0 KB gzip; after Phase 1 113.3 KB raw / 40.0 KB gzip (ceiling 120.0 KB gzip). Seen in the walk: at a source column narrower than about 440px the right-hand stats truncate with an ellipsis (`4 ch…`); at the default 480 they fit. With no session the footer's stats show the lines, components and pins from the analysis while the terminal line still says `Compile a circuit first.`, as in Phase 0.

## 2026-09-11 — Phase 2 — Two pure modules

**What shipped:** `zoom-label.ts` (`formatZoom`, `zoomLine`) and `pin-count.ts` (`pinCountLabel`, pins not bits), free of the renderer so they ride in the eager bundle; `dataOpen` in the envelope with its normalisation, and the migration opening the panel for a reader who left the old Data tab open. Commit `37e47d0`.
**Files touched:** `site/src/scripts/zoom-label.ts`, `site/src/scripts/pin-count.ts`, `site/src/utils/playground-store.ts`, `site/test/zoom-label.test.ts`, `site/test/pin-count.test.ts`, `site/test/playground-store.test.ts`
**Tests:** added `zoom label › formatZoom rounds to a whole percent`, `› formatZoom's bounds are the renderer's`, `› zoomLine spells the design's line`, `pin count › pinCountLabel counts root pins, not bits`; `dataOpen` cases in the store's defaults, migration and normalisation
**Next slice:** the region's furniture.
**Notes:** None.

## 2026-09-11 — Phase 2 — The region's furniture

**What shipped:** The output pane's markup replaced by the canvas region's: the view switch (`.pg-view-switch`, three `role="tab"` buttons, one tab stop, arrows and Home/End), the note beside it carrying the Truth gate's reason, the Data button with its `N → M` count, three `[data-view-panel]` panels in the inset `60px 16px 40px`, the Data rows in a fixed card under the button, the hint line and the zoom line. `showView`/`setDataOpen` replace `showTab`; every `state.tab` site reads `state.view` or `state.dataOpen`; the Simulate tab's build-on-click folded into `showView('live')`. `.pg-tabs`, the tooltip and `.pg-panel` gone from markup and rules; the mount no longer carries `.lc-mount`. Commit `85abf49`.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/test/island-smoke.test.ts`, `site/test/app-layout.test.ts`
**Tests:** added `island-smoke › the view switch shows one view, and the Data button opens the card`; the mount walk's region assertions; `app-layout`'s mount and panel assertions moved to the new rules; 561 pass
**Next slice:** the Live view fills the inset.
**Notes:** The edit script died on a malformed regex in its own leftover check after writing the island but before the CSS and tests; the second pass finished them. The region keeps Phase 0's `.pg-output` class (the plan's `.pg-canvas-region` was never introduced).

## 2026-09-11 — Phase 2 — The Live view fills the inset

**What shipped:** `buildCanvas` with `viewport: 'parent'`, `navigation: { wheel: 'modifier', drag: true, touch: narrow ? 'page' : 'own' }` and `onViewChange`; `sim.cell` as the one cell size; the zoom line live (`syncZoom`, the `100%` and `fit` buttons, inert without a canvas); `refitIfIdle` one frame after the mount's ResizeObserver; `renderer-pin.test.ts` probing the six view methods, the option shape and the island's source. Commits `1996ea6`, then `28136ba` for the fix below.
**Files touched:** `site/src/components/Playground.astro`, `site/test/renderer-pin.test.ts`, `site/test/island-canvas-options.test.ts`
**Tests:** the pin test's Bench, Phase 2 probes; the padding guard now reads `sim.cell`; 561 pass
**Next slice:** the record.
**Notes:** The first capture with the Data card open showed the wires under the card: the renderer reports its own first-measurement fit through `onViewChange`, so `navigated` was set before any gesture and the refit never ran. Fixed by counting a view change as the reader's only within 500 ms of a wheel, a drag or a touch move on the canvas (`sim.gestureAt`). After the fix the two-bit adder refits to 51% beside the card, and to 82% in the full inset.

## 2026-09-11 — Phase 2 — The record

**What shipped:** `DOCS/sim-protocol.md` says "the Live view or the Data panel" and "in the Data panel"; decisions 8 and 9 in `DOCS/decisions/playground-bench.md` and the index; this log. The Live view captured on the two-bit adder in light mode and, with the Data card open, in dark mode (`bench-2a-live-light.png`, `bench-2a-live-data-dark.png`; handed to the human, not committed).
**Files touched:** `DOCS/sim-protocol.md`, `DOCS/decisions/playground-bench.md`, `DOCS/decisions/index.md`, `DOCS/STATUS.md`
**Tests:** none added; the four gates green
**Next slice:** Phase 3 — Schematic and Truth (`DOCS/PLANS/PHASE_3_schematic_truth.md`), on the human's word.
**Notes:** `bun run bundle`, `/playground`: after Phase 1 113.3 KB raw / 40.0 KB gzip; after Phase 2 115.3 KB raw / 40.5 KB gzip (ceiling 120.0 KB gzip). Not walked by hand: the modifier wheel, the drag, a pinch, and a pin click after a zoom; the smoke test cannot build a canvas, so those are the human's. `touch: 'own'` is read at construction, so a resize across 800px keeps the old gesture until the next artifact (the spec's TODO, left as a papercut).

## 2026-09-11 — Phase 2 — A restore onto Live no longer reaches the simulator early

**What shipped:** `showView('live')` goes through `hooks.onLive`, assigned beside `hooks.onArtifact` after the simulator's record exists; the restore from the envelope at boot therefore never touches `sim`. The smoke's mount test now boots from a seeded envelope saved on the Live view (`runIsland(page, chunk, seed)` writes `STORE_KEY` before the chunk runs), which is the path that failed.
**Files touched:** `site/src/components/Playground.astro`, `site/test/island-smoke.test.ts`
**Tests:** the mount walk restores onto Live with no error and switches back; 561 pass
**Next slice:** Phase 3, on the human's word.
**Notes:** Reported by the human from their browser: `Uncaught (in promise) ReferenceError: Cannot access 'sim' before initialization at showView … at bootstrap`, and the editor's highlighting gone with it — the CodeMirror mount is scheduled after the restore in `bootstrap`, so the throw left the plain textarea on screen. Phase 2's `showView` had folded the Simulate tab's click-time build into the restore path; the harness's fresh envelope restores Schematic and never reached it. The same class as Phase 0's `renderTermLine` note: anything a restore can call must not read a record declared later in `init`.
