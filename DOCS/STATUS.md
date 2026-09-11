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

## 2026-09-11 — Phase 2 — The dot grid moves with the circuit

**What shipped:** While a canvas is showing, the Live view covers the whole region (`.pg-live { inset: 0 }`, the fit keeping `BENCH_INSET = 60` clear through the renderer's `padding`) and the canvas draws the dot grid itself: `benchTheme(pickTheme())` wraps the site theme's `background` with one that clears the visible world and draws the dots in world space, 18 world px apart (doubled until 12px on screen when zoomed out), one pixel wide at any zoom, in the region's own `--pg-dot`. The region's static `::before` dots yield under `[data-canvas='true']` (written by `syncZoom`). The hover note sits over the canvas at `top: 60px`, out of the mount's flow. The theme flip wraps the same way, and the pin test's guard accepts the wrapper.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/test/island-canvas-options.test.ts`, `site/test/renderer-pin.test.ts`
**Tests:** the padding guard reads `BENCH_INSET`; the flip guard accepts `setTheme(benchTheme(pickTheme()))`; 561 pass
**Next slice:** Phase 3, on the human's word.
**Notes:** Reported by the human from their walk: "the grid dot in the background of the canvas do not move or zoom with the contents, it feels weird". A CSS layer on the region cannot follow the view; the renderer's `background` hook receives `view` and `viewport` for exactly this. Decision 9's entry should be read with this: the canvas theme's "the canvas stays transparent" holds (the hook still clears, it fills nothing), and the dots are marks, not a fill. The site's own `background` cleared only the grid's rectangle, which under a zoom-out is smaller than the element; the wrapper clears the whole visible world. The gallery keeps the plain theme.

## 2026-09-11 — Phase 3 — truth-view.ts: parse, spell, match

**What shipped:** `site/src/scripts/truth-view.ts` (`parseTruthTable`, `columnOf`, `cellText`, `liveRowIndex`, `compilerCell`, `toMarkdown`, `toCsv`, `driveRow`, `unknownInputs`, `rowsForPins`); `optionsFor('truth_table', s, preloads, format = 'json')`; the `format` select removed from the settings form. Commit `ff08903`.
**Files touched:** `site/src/scripts/truth-view.ts`, `site/test/truth-view.test.ts`, `site/src/scripts/settings-drawer.ts`, `site/test/settings-drawer.test.ts`, `site/src/components/Playground.astro`
**Tests:** added `truth view › parseTruthTable reads numbers and hex strings into bigints`, `› cellText spells in the reader's base`, `› liveRowIndex matches the compiler's row order`, `› liveRowIndex on a bus`, `› chipText composes the parts`, `› toMarkdown and toCsv match the compiler's shape` (byte-equal to three goldens), `› a row click drives every input column through the session`, `› unknownInputs lists the pins with an undefined bit`, `› rowsForPins enumerates only the unknown bits`, `› rowsForPins refuses over the cap and on a ram`, `› the scratch never writes the live session`, `› toMarkdown of the parsed json equals the compiler's markdown` (through `libcirc.wasm`, `and_gate.circ` and `and_2bit.circ` in all three bases); `settings-drawer › truth_table asks for json unless told the copy format`
**Next slice:** the Schematic view.
**Notes:** `cellText` spells a one-bit column as its digit, whatever the base: the renderer's `formatPinValue` gives `0b1` for a bit, and a truth table of `0b1`s is not one. The spec's `1010` for a 4-bit binary cell is the renderer's `0b1010`; the renderer won.

## 2026-09-11 — Phase 3 — The Schematic view

**What shipped:** Each view's tools in the bar and its own bottom-right line, shown by the region's `data-view`: the Schematic's two toggles (`expandMacros`, `expandDisplay`, bound by the footer's own `mountSettingsDrawer` call), `Copy`, the `rows × cols chars` size line; the region on `--code-bg` without the grid; `.pg-preview` at `--font-mono-strict 20px / 1.35` centred by a grid's `margin: auto`; the Truth chip replacing the view note; the copy buttons' handler on `copyText` and `flash`, with `hooks.copySource` for the Truth view. Commit `7bb1437`.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/test/island-smoke.test.ts`
**Tests:** the mount walk's region assertions (`data-view`, the size line, the two toggles as the region's only settings); 574 pass
**Next slice:** the Truth view under the cap.
**Notes:** Board 3e captured on the two-bit adder: `23 × 65 chars`.

## 2026-09-11 — Phase 3 — The Truth view under the cap

**What shipped:** `truth-chip.ts` (eager; `chipText`, re-exported by `truth-view.ts`); the table in `.pg-truth-card` on the dot grid, headers lighting the schematic and the editor, cells classed `pg-truth-high | low | unknown` and spelled by `cellText` in the reader's base, a left rule on the first output column, rows with `tabindex` that drive through `driveTruthRow` (`ensureSession` → `driveRow` → the page's pin memory), the tint moved by `refreshTruthTint` on every `drive` event, the chip from `applyTruthGate` with the counts, the two copies (the compiler's markdown or CSV through `optionsFor(…, what)`; the module's over the cap); `renderTruth` on the seam. Commit `25f27e2`.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/src/scripts/truth-chip.ts`, `site/src/scripts/truth-view.ts`, `site/test/island-smoke.test.ts`
**Tests:** added `island-smoke › the truth table renders as a card of rows that drive`; 575 pass
**Next slice:** over the cap.
**Notes:** Two harness lessons. The gate reads the Truth record at boot, so the record is declared beside the island's state (the third boot-order slip of this plan; the rule in Phase 2's note stands). happy-dom's table sections have no `insertRow`/`insertCell`, so the rows are built with `createElement`, which is the same DOM. A dynamic import's preload helper reads `document`, so a smoke test that awaits one runs inside `driveAsync`. Board 3f captured on the two-bit adder after a row click: the row tinted, the terminal line reading `set b 0x1 · ok`.

## 2026-09-11 — Phase 3 — Over the cap

**What shipped:** `runTruthOverCap`: the live session ensured, a scratch `SimSession` over the same bytes, roms and images (no boot-low), `rowsForPins`, the scratch destroyed, the filtered table or the card's note (`K unknown input bits are over the cap of C…`, `A truth table needs a circuit without ram.`); `truthBlock` blocks for errors only; a `drive` re-enumerates a filtered table; `truth.lastMs` and `truth` on the seam. Commit `95d2cb4`.
**Files touched:** `site/src/components/Playground.astro`
**Tests:** none added (the module's cases cover the enumeration; no harness builds a session); 575 pass
**Next slice:** the record.
**Notes:** The walk on the four-bit adder (8 input bits) at cap 7 through the console: with the session as it boots (low), every pin is known and the filtered table is the single live row; after `reset` and `set a 0x3`, `b`'s 4 unknown bits give 16 rows in 1.9 ms; `set a 0x1 0x1` (half-known) counts `a` whole, 8 unknown over 7, and the card says so. Extrapolated, 4,096 rows at the default cap of 12 would take about 0.5 s on the main thread, over the spec's 100 ms; the sweep (Phase 7) decides between chunking the loop through `requestIdleCallback` and a lower cap for the site path. Not enumerating the unknown *bits* of a half-known bus is a papercut of the same size.

## 2026-09-11 — Phase 3 — The record

**What shipped:** `DOCS/decisions/playground-bench.md`: decision 7 amended (the Schematic toolbar, the `format` finding), decisions 10 and 11; the index; this log. `DOCS/sim-protocol.md` reread: it names `--truth-table` twice as the CLI mode and never the tab, so nothing changed.
**Files touched:** `DOCS/decisions/playground-bench.md`, `DOCS/decisions/index.md`, `DOCS/STATUS.md`
**Tests:** none added; the four gates green at `95d2cb4`
**Next slice:** Phase 4 — the project switcher (`DOCS/PLANS/PHASE_4_switcher.md`), on the human's word.
**Notes:** `bun run bundle`, `/playground`: after Phase 2 115.3 KB raw / 40.5 KB gzip; after Phase 3 120.1 KB raw / 42.1 KB gzip (ceiling 120.0 KB gzip). The eager growth is the chip module and the view's wiring; `truth-view.ts` rides behind the renderer's dynamic import beside `data-view.ts`.

## 2026-09-11 — Phase 3 — A header lights the editor before any canvas, and Truth keeps its grid

**What shipped:** `highlightByName` marks the editor from the declaration when the layout table has no entry (`markInEditor` takes the name and kind only), so a page refreshed onto the Truth view lights the source from a header without a Live visit first. The region's static dots now hide only under the Live view with a canvas (`[data-view='live'][data-canvas='true']`), so the Truth card sits on the grid whether or not Live was visited.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`
**Tests:** none added (no analysis lands in the harness); 575 pass. Walked on the dev server: a reload onto Truth, hover `a` → one `.cm-circ-linked` span, dots shown; Live then Truth, hover `b` → one span, dots shown.
**Next slice:** Phase 4, on the human's word.
**Notes:** Reported by the human: after a refresh on the Truth view the grid showed and the header hover no longer highlighted the code. The grid was the design's (board 3f); what had changed was that a Live visit's `data-canvas` flag hid the static dots on every view after it. The hover went through `link.table`, which `buildCanvas` fills from the layout, so it worked only after a canvas existed; the declaration list from the analysis has the span and is enough.

## 2026-09-11 — Phase 4 — The tree's new data

**What shipped:** The tree and breadcrumb use Tour, Examples and Mine. Catalogue tiers keep their order inside Examples; scratch projects keep newest-first order. Project nodes carry file counts or an age from an injected clock, alongside diagnostic badges. Catalogue file counts are computed once at boot.
**Files touched:** `site/src/scripts/ws-tree.ts`, `site/src/utils/playground-store.ts`, `site/src/components/Playground.astro`, `site/test/{ws-tree,workspace,playground-store,island-smoke}.test.ts`, `DOCS/STATUS.md`
**Tests:** Added group-order, file-count and age-band cases; extended migration coverage. Ran `bun --bun run typecheck`, `bun --bun run build`, `bun test`, then the corrected `bun test test/island-smoke.test.ts`: all 578 cases pass across those runs. `bun run bundle`: `/playground` 120.8 KB raw / 42.4 KB gzip, within the unchanged ceiling.
**Next slice:** Name filtering and the search field.
**Notes:** Rechecked the clean handoff at `0d4c232`: the human's override leaves dots on Live alone. Tier-id migration belongs in workspace normalization, covering both version 1 and the early version-2 envelopes already written by this branch; restricting it to `migrateV1` would lose those readers' expansion choices. The schema stays at version 2.

## 2026-09-11 — Phase 4 — Name filtering

**What shipped:** `filterNodes` matches project and open-file names, trims the query and ignores case, keeps ancestors, and returns the original array for an empty query. The bridge has a search field; ArrowDown enters the tree and Enter loads a sole project match. No matches shows `No circuits found.`
**Files touched:** `site/src/scripts/ws-tree.ts`, `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/test/{ws-tree,island-smoke}.test.ts`, `DOCS/STATUS.md`
**Tests:** Five filter cases and a built-island search through a collapsed group. Typecheck, build, all 583 existing tests and the new smoke case pass (584 total). `bun run bundle`: `/playground` 121.6 KB raw / 42.6 KB gzip.
**Next slice:** The popover, breadcrumb and keyboard/focus handling.
**Notes:** Search temporarily expands the tree's input, so collapsed groups remain searchable. It never writes those expansions to the envelope; clearing the query restores the reader's tree. A project match retains its visible files; a file-only match retains only matching files and their ancestors.

## 2026-09-11 — Phase 4 — The popover and the breadcrumb

**What shipped:** The tree is a 340px `.pg-switch` under the breadcrumb, with the board's spacing, metadata, diagnostic pills, accent ring and scrim. All `.pg-ws*` and `.pg-tree*` markup and rules are gone. Search receives focus on open; both search shortcuts work from the editor; Escape and the scrim close with focus return. Selecting another project or a file closes the card. Tree actions are reachable by Tab from their row, and their Enter/Space events reach the button. Below 800px the card spans the width beneath the wrapping nav.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/test/island-smoke.test.ts`, `DOCS/STATUS.md`
**Tests:** Rewrote the tree walk; added both shortcuts, sole/multiple search matches, collapse while searching, and scratch rename/duplicate/delete. All four gates pass: 587 tests; `/playground` 123.3 KB raw / 43.1 KB gzip. A headless Chrome walk against the fresh build measured the source at 480px before, during and after opening at 1440 and 1024; at 700 it stayed 700px. No runtime exceptions.
**Next slice:** Single-file import and the footer's second action; decisions and final record.
**Notes:** Captured `bench-3a-{light,dark}-{1440,1024,700}.png` under the session's `/T/opencode/` scratch directory; reviewed light/1440 and dark/700. Desktop geometry is 340px wide at (82, 56); the narrow nav measured 93px and the card follows it at 101px. Search expansion is session-only and independently collapsible. Group chevrons sit in the right-hand slot, retaining a visible counterpart to ArrowLeft/Right. The smoke's layout numbers are zero in happy-dom; the Chrome measurement supplies the real no-reflow proof.

## 2026-09-11 — Phase 4 — Import and the footer

**What shipped:** `+ New circuit` creates and opens a project, then closes the switcher. `Import .circ` reads one file, names the scratch project after its stem, and uses `createScratch` for unique names, the UTF-8 size cap and eviction. The read is guarded until it settles; success, oversize refusal and read failure use the status channel. Decision 13 and the import behavior are recorded and indexed.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/src/utils/playground-store.ts`, `site/test/{workspace,island-smoke}.test.ts`, `DOCS/decisions/{playground-bench,index}.md`, `DOCS/PLANS_PROMPT.md`, `DOCS/STATUS.md`
**Tests:** Added import coverage for source preservation, duplicate stems, UTF-8 byte limits, read failure, cancellation, concurrent change events and envelope persistence. All four gates pass: 589 tests, typecheck with no errors, fresh build, bundle within its unchanged ceiling. `/playground`: 124.2 KB raw / 43.4 KB gzip, versus 120.1 / 42.1 after Phase 3.
**Next slice:** Phase 5 — the Data panel (`DOCS/PLANS/PHASE_5_data_panel.md`), on the human's word.
**Notes:** Refreshed all six board-3a captures with the Import action at `/var/folders/91/0hwz8chx0d12hz5x00f53vrm0000gn/T/opencode/bench-3a-{light,dark}-{1440,1024,700}.png`. Reviewed dark/1440, light/1024 and light/700 in this slice. Chrome confirmed the unchanged source width in every mode/width, native ⌘K and Escape, an actual disk-file import and restoration after reload, with no runtime exceptions. The browser probe waits for the debounced envelope write; a fixed 800ms delay proved too short under headless Chrome/Rosetta. Recurring traps now record v2 tier migration, search-only expansion and the import-specific skipped note. Seen outside the switcher at 1024: the Live hint and zoom line overlap; carry that existing canvas-layout issue into Phase 7's sweep.
