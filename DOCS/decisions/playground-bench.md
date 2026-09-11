# playground-bench

The entries below record the decisions of the playground-bench initiative: the site's `/playground` redrawn as the bench of the design handoff under `DOCS/design/design_handoff_playground_bench/` — two regions on one sheet under a 48px nav, over a terminal line and a status line. The sixteen decisions locked at plan time are in `DOCS/PLANS_PROMPT.md`; each phase appends the ones it exercised here as it ships them.

### The bench owns its chrome

**Decision.** `Base.astro`'s `app` variant renders neither `<Nav />` nor `<Footer />`; the body is one viewport row (`grid-template-rows: 100dvh`, with the `100vh` fallback first) and `main` has no padding. The playground, the variant's only user, draws its own 48px nav — the wordmark as a link home, a breadcrumb naming the open project, the status cluster, Download, Share and `ThemeToggle.astro` reused as is — and a 24px status line carrying the compiler identity, the site footer's `.signature`/`.heart` markup verbatim, and the promise `runs in your browser · nothing leaves the page`. The `role="status"` channel shares the line's right cell with the promise and hides it while it holds a sentence. `app-layout.test.ts` holds the two conditionals in `Base.astro` and refuses any app-scoped rule that names `.site-nav` or `.site-footer`.

**Rationale.** The design's frame is the whole viewport, `48px · minmax(0, 1fr) · 40px · 24px`, and no board draws the site's nav above it. Keeping both would put two wordmarks and 113px of chrome on a page that wants every pixel for the source and the canvas. The variant already existed to give one page a different body; yielding the chrome is one more thing it gives.

**Alternatives.** The site nav above the bench nav (two wordmarks, and the frame no longer the design's); a second layout file (forks the head, the theme script and the analytics mount for one page).

### The handoff is tracked, minus the noise

**Decision.** `DOCS/design/design_handoff_playground_bench/` is committed as the design reference: `README.md`, `github.md`, `Playground Upgrade.dc.html`, `support.js`, `circ-scenes.js`, and the CircDS bundle under `_ds/<id>/` with its two `woff2` faces and its two font stylesheets. Not committed, and removed from the working tree: `circ-site-theme.js` and `circ-skins.js` (byte-identical to `02e56f4:DOCS/archive/design/canvas-theme/`), `site/src/utils/circ-assets.mjs` (a stale copy of a file the site has since reduced to two sprites), and the 32 JetBrains Mono `.ttf` files (7.6 MB; the family sits in `--font-mono-strict` behind `ui-monospace`, and the site does not ship it). `support.js` is also identical to the archived copy but stays, because the design file needs it beside it to open. The design file wins over its README where the two disagree. At archive time the directory moves to `DOCS/archive/design/playground-bench/`.

**Rationale.** A handoff outside the repository cannot be cited by a slice; a handoff with 7.6 MB of fonts that render nothing the site renders is weight every clone pays forever. The mock's strict stack is the site's, so dropping the fonts changes nothing about how the mock reads on the machines that matter.

**Alternatives.** Committing the whole zip (8 MB, three duplicate files); keeping the handoff out of the tree (uncitable); committing it under `site/` (it is not shipped and must not be).

### The three terminal tokens stay site-local, and all three already exist

**Decision.** `--term-ok`, `--term-echo` and `--danger` are defined in both token blocks of `global.css` and are read by the console, the tree and the status dot; the handoff's fallback values (`#8fd3a8 / #ece4f8`, `#e5484d`) are not adopted, and the tokens are not promoted to CircDS. The canvas region's dot grid is a fourth site-local token, `--pg-dot`: `--fg` at the design file's alpha (`0.14` light, `0.18` dark), declared with the others so the token guard reads it as one.

**Rationale.** The site's `--danger` (`#a83737` / `#ff6b8a`) was chosen against the site's own palette; the mock's `#e5484d` is a fallback the DS author wrote for a mock without the site's stylesheet. CircDS is another package with its own release; a site page's terminal colours are not its concern.

**Alternatives.** Promoting the tokens (a DS release for three colours one page reads); a literal in the dot grid's gradient (the one colour the token guard would have to except).

### The source column is the splitter, in pixels

**Decision.** The main splitter keeps its `role="separator"` element and its one custom property, but in a pixel unit: `--pg-source-w` on `.pg-body`, read by `grid-template-columns: var(--pg-source-w, 480px) 1px minmax(0, 1fr)`. `createSplitter` takes `unit: 'px'` with `minPx 320`, `maxReservePx 480`, `stepPx 16` and `coarseStepPx 64`; `pxBounds` reserves the far pane and never inverts, and a container with no size yet (nothing laid out; happy-dom) leaves the intent unclamped so the first paint is the reader's width. `aria-valuenow` stays a percentage of the container in either unit. The hairline is the divider: one pixel in the grid, a nine-pixel invisible hit band. Until Phase 1 moves the envelope, the width lives in memory only, default 480; `normalizeRatios` accepts only a fraction, and the schema moves once.

**Rationale.** The design gives the source column as a width (480, and 440 or 400 on the wider boards), which is what a reader adjusts; a share of the container drifts as the window does. The splitter's contract — intent separate from the rendered value, no commit on resize, a nullable key handler — carries over unchanged, so the pixel unit is a second arithmetic behind the same element rather than a second mechanism.

**Alternatives.** Encoding the width as a fraction of a width the migrator cannot know (lossy, and undone by the first resize); a second splitter implementation (200 lines for one unit).

### The token guard is a source-text test

**Decision.** `site/test/bench-tokens.test.ts` parses every rule of `global.css` whose selector contains `.pg-` and holds each `color`, `background`, `border`, `outline`, `fill`, `stroke`, `box-shadow` and `caret-color` value to a `var(--…)` token, `transparent`, `currentColor`, `inherit` or `none`; a `box-shadow` may add a black at some alpha, and `color-mix(in srgb, var(--…) N%, transparent)` is a token expression. Every `font-family` and `font` shorthand names only the three font tokens or `inherit`. The guard asserts it saw more than a hundred rules, so a regex that matched nothing cannot pass, and it tests its own allowances on literal rules.

**Rationale.** A literal hex in a `.pg-` rule is a colour that stops following the theme, and nothing in a build says so; `circ-skins.test.ts` holds the canvas the same way and caught the last drift. Reading the stylesheet is the only gate `bun test` can run without a browser.

**Alternatives.** A stylelint rule (a dependency and a config for one file); a review habit (the thing the guard replaces).

### The envelope moves to version 2 by migration, once

**Decision.** `STORE_VERSION` is `2`. `normalize` runs a version-1 body through `migrateV1` before the version check: `scratch`, `activeId`, `activeFile`, `settings` and `ws` ride through untouched; the output tab becomes a view (`preview → schematic`, `simulate` and `data → live`, `truth → truth`); the dock's `{ open, tab }` becomes the footer's; `layout.ratios.main` is dropped for `layout.sourceWidth` (default 480, whole pixels in `[320, 8192]`); `tab` and `dock` are deleted. The reset note is reserved for corruption and for a version this code does not know. The migration is proved on `site/test/fixtures/store/envelope-v1.json`, a literal envelope as the version-1 writer produced it, never on one built from today's defaults. Later phases add fields with defaults under version 2, and `normalize` fills a missing field from `defaultEnvelope()`.

**Rationale.** `normalize` resets the whole envelope on a version mismatch, scratch projects included; version 1 is the one schema a reader's browser can hold from before the bench, so bumping without a migrator would cost every reader their projects on their first visit. Moving once, with every rename in one function, keeps the schema readable: a field is either version 1's or version 2's, never a mix.

**Alternatives.** Keeping version 1 and adding optional fields (`tab` and `dock` would keep their old meaning beside fields that replace them); a version byte per field (a decoder that must parse before it can reject).

### Settings live in the diagnostics footer

**Decision.** The editor's dock is gone. Under the editor sits a 30px footer whose bar says `N errors · N warnings` on the left (in `--fg` with a caret when either is non-zero, else `--muted`) and what the source is made of on the right — `N lines · N components · N <memories | chips | pins>`, the noun chosen by what the project declares, from `footer-summary.ts` over the tab bodies, the last analysis and the mapped diagnostics. The counts open the body on the diagnostics list, a grid of glyph · `file:line:col` · code · message on `14px 104px 52px 1fr`, where a position with a span is a button that jumps (switching files first) and lights the declaration on hover, and a placeless one (`<builtin>/…`) is a span. A gear at the right end opens the same body on the settings form, unchanged, bound through `mountSettingsDrawer` as before. The gestures are the dock's: a button on its own open panel closes the body, the other button while open switches panels, `Escape` in the body closes it and hands focus back to whichever button opened it. `footer: { open, tab }` persists both. The board's `unicode | ascii` control corresponds to no setting on the site and no option in the compiler (`--preview` has no charset), so nothing leaves the form; Phase 3 owns that control.

**Rationale.** The README leaves settings undrawn between "a gear in the nav" and "a second footer tab"; the nav is drawn full, and the settings change what the source compiles to, so they belong beside the source. The bar replaces the dock's badge with the counts themselves, so a reader sees how many without opening anything, and the list's grid puts the position first, where a click goes. The analyze reply carries symbols and no nets, so the boards' `4 nets` has no source; the noun rule takes the boards' other three stats instead.

**Alternatives.** A gear in the nav (crowds the drawn nav; settings far from what they change); keeping the dock's tab strip (a second strip under a strip, when the bar already says how many); a nets count from the renderer's topology (exists only once a session is built, and the footer is about the source).

**Amended in Phase 3.** The Schematic view's toolbar carries the two preview settings that exist, `Expand macros` and `Expand display`, as toggles on the same `data-setting` attribute the footer's form binds, so one binding paints both; a `Copy` beside them copies the schematic's text, and the bottom-right line says its `rows × cols chars`. The board's `unicode | ascii` control corresponds to no option in `--preview` (`lib/preview/render.zig` renders box-drawing glyphs only) and waits on a compiler slice. The `format` select (`table | markdown | csv`) left the form: it was sent on every truth-table request while the page always parsed the reply as JSON, so a stored `markdown` or `csv` threw at `JSON.parse`; the request is pinned to `json` (`optionsFor`'s fourth argument) and the two copy buttons name their own format. The field stays in the envelope, unread, until the sweep.

### The file strip is a switch, over the tree's state

**Decision.** A 36px strip over the editor lists the open project's files as `role="tab"` buttons, in order, the active one selected under a 2px accent rule and the only tab stop; `ArrowLeft`/`ArrowRight`/`Home`/`End` move the selection, and `+ file` adds a file before the root and selects it. The strip is rebuilt from `state.tabs` whenever the tree renders, and the editor panel is labelled by its current tab. Rename, delete and reorder stay in the tree (the switcher, after Phase 4); the strip carries none of them. Focus follows the file into the tree's row while the card is open, else onto the strip's tab.

**Rationale.** The board draws a strip of names and one `+ file`; today files are rows of the tree only, and the tree is a card that is shut most of the time. A switch is what a strip is for, and one state feeding both keeps them from disagreeing.

**Alternatives.** Rename and delete on the strip too (two places to arm a delete, and the tree's keyboard model duplicated); the tree as the only file surface (a card the reader has to open to see which file is showing).

**Surface correction after the drawer walk.** The bench's CodeMirror base uses `--pane-bg`, matching the file strip and diagnostics/status bar beneath it. An app-scoped rule sets that surface; syntax and interaction colors remain the editor theme's. The theme's code-block background had painted over the intended source-pane surface.

### The view switch is three views and one panel

**Decision.** The output pane's four tabs are a segmented switch of three views, `Schematic · Live · Truth` (`role="tablist"`, one tab stop, arrows and Home/End between them), persisted as `view: 'schematic' | 'live' | 'truth'`; the Data face is a panel, `dataOpen`, that can be open over any view and whose rows are still `data-view.ts`'s over the one session. The Truth view keeps its gate (`truthTableRefusal`) and shows the reason in the toolbar's note beside the switch, where the tab tooltip used to hold it; a blocked Truth view is refused on click and still restorable from the envelope. The region's hint line under the view and the zoom line at its bottom right are part of the switch's furniture: the hint is the view's own sentence, empty for a view that has none yet.

**Rationale.** The boards draw three views and a Data button, not four tabs: the rows are a face of the live session that a reader wants beside the picture, not instead of it. A view and a panel are two fields because they vary independently, and a reader who left the page on the old Data tab lands on the live view with the panel open, which is the nearest thing to where they were.

**Alternatives.** Four views with Data among them (the rows would hide the picture they describe); the Data rows in the drawer (the drawer is the session's log and memory, and the rows want the canvas's height).

### The Live view adopts the renderer's zoom and pan

**Decision.** The canvas is built with `viewport: 'parent'` on a mount that fills the view's inset (`60px 16px 40px`, and `344px` on the right while the Data card is open), `navigation: { wheel: 'modifier', drag: true, touch }` where `touch` is `'own'` above 800px and `'page'` below it (read at construction), and `onViewChange` writing the zoom line's percentage. The first fit is the renderer's own, on its first measurement; a theme flip is `setTheme` in place and the view survives it. The zoom line is `cell 14 · 100% · fit`: the percentage is a button that calls `resetView`, `fit` calls `fit`, both inert until a canvas exists. When the inset changes, the site refits one frame later (`refitIfIdle`), and only when the reader has not zoomed or panned: a view change counts as the reader's only when a wheel, a drag or a touch move on the canvas preceded it within half a second, because the renderer reports its own fits through the same callback. The view is not persisted: a canvas starts fitted, and a saved view is in pixels of an inset that may have changed. The gallery keeps the renderer's defaults.

**Rationale.** The renderer shipped these options for this page (`2.3.0-alpha.4`), and a canvas that fills its region needs to be navigable or a wide circuit is cut off. The modifier wheel rather than `always` keeps the page's own scroll below 800px, where the page scrolls. The gesture window is what keeps the refit from stealing a view the reader chose while still refitting one they never touched; the first screenshot of the walk showed the wires under the card before it existed.

**Alternatives.** Persisting the view (pixels of a stale inset); a synchronous `fit()` on resize (measures the old size, since the mount's observer runs before the renderer's); `wheel: 'always'` (traps the page's scroll on a phone).

### Over the cap, the Truth view shows the rows the pins select

**Decision.** The compiler enumerates every input bit or none, so over the cap the Truth view no longer refuses: the table is computed on the site. The live session's input pins with any undefined bit are the unknown ones (a half-known bus counts whole); their bits are enumerated on a scratch `SimSession` built from the same artifact bytes, roms and images, with no boot-low, while every known pin is held at the live session's value; the rows come in the compiler's order, the first unknown pin varying fastest, and each output is read after each assignment. The live session is read and never written; the scratch subscribes nothing and is destroyed as soon as its rows are read. The chip says `N input bits · R rows · cap C · filtered to the current pins`. When the unknown bits exceed the cap too, the card says how many are over and how to set more; a circuit with a `ram` is refused as the compiler refuses it. A drive from any face re-enumerates the filtered table. Since the page boots its session low, a reader who set nothing sees the single live row; `reset` in the console, or `?` in the Data panel, makes pins unknown again. The truth gate blocks the tab for errors only; the cap is the chip's to say.

**Rationale.** The board says the table still opens over the cap, filtered to the current pins, and the compiler has no fixed-input option (`lib/truth_table/builder.zig` `build`). The runtime lives on the page, so a scratch session costs one instantiation and a synchronous loop bounded by `2^cap`, the same bound the compiler runs under; the worker has no runtime, so nothing moves there. Measured on the four-bit adder with `a` set and `b` unknown: 16 rows in 1.9 ms; extrapolated, 4,096 rows at the default cap would take about half a second on the main thread, over the 100 ms the spec set, so the sweep decides between chunking the loop and a lower cap for the site path.

**Alternatives.** A fixed-input option in the compiler (a compiler slice in another initiative); enumerating on the live session (every assignment would echo in the console and move the canvas); refusing over the cap as before (the board's table stays shut).

### A truth row drives the pins through the session

**Decision.** Clicking a row, or pressing Enter or Space on it, drives every input column through `session.set`, one column at a time, with the column's full mask; each `set` is a `drive` event, so the canvas repaints, the Data panel re-reads, and the console logs `> set a 0x3 · ok` as it does for any face. The page's memory of the pins is updated from the session after the row, so a rebuilt session replays it. A refusal from `set` goes to the status line through `describeError`. The tinted row follows the session, never the click: after every `drive` event the view finds the row whose input cells equal the session's input pins, by name, and moves `aria-current`; an unknown pin selects no row. Every cell is spelled by the renderer's `formatPinValue` in the reader's base, so the table and the Data panel never disagree about a value; a one-bit column is its digit in any base; the compiler's JSON, which prints decimal under `value_format: binary`, is parsed into bigints and never shown as sent.

**Rationale.** A truth table is a map from inputs to outputs; a row is the shortest way to say "show me this case", and the session is the one place every face drives through, so the click cannot bypass the console's record. The tint that follows the session rather than the click is what keeps it honest when a `set` is refused or another face moves a pin.

**Alternatives.** The tint set by the click (lies after a refusal); driving the runtime directly (bypasses the console and the Data panel); the compiler's own spelling in the cells (decimal under a setting that says binary).

**Amended after the walk.** Board 3f draws the card on the dot grid; the human preferred the Truth view without it, so the grid is the Live view's alone: the region's static dots show only under Live before its canvas exists, and the canvas draws its own after. The Schematic and Truth views sit on plain surfaces.

### The switcher is the tree, re-homed

**Decision.** The breadcrumb opens a 340px popover with search, the tree and two footer actions. The source column keeps its width: the card and scrim are absolutely positioned siblings of the bench's rows. The card follows the nav's measured height; below 800px it spans the page under the wrapping nav. Every new rule is scoped to the app layout and uses the site's tokens. Group chevrons occupy the right-hand slot; the open project's files keep their root marker, diagnostics and editing controls.

`displayGroups` yields Tour, Examples and Mine. Examples merges the three catalogue tiers in tier order; Mine keeps the persisted id `yours` and sorts scratch projects newest first. Project metadata is a file count or an age from an injected clock; a diagnostic pill takes its place when needed. Workspace normalization maps old tier ids to `examples` for both v1 and early v2 envelopes, without another schema bump or a reset.

`filterNodes` matches project and open-file names, case-insensitively, and retains their ancestors. Search reaches collapsed groups through a temporary expansion set; collapsing a result changes only that set, and clearing or closing restores the saved tree. Enter loads a sole project match; otherwise it enters the tree. Arrow keys retain `moveFor`'s contract. Tab reaches the focused row's buttons, which own Enter and Space. Both ⌘K and Ctrl+K open search from the editor; other text fields retain those keys. Escape, the scrim and a selection close the card and return focus to the breadcrumb. Tabbing out closes it without moving focus back.

**Rationale.** The existing tree already owns project and file operations. Reusing its flat nodes and keyboard model keeps those operations together, while the popover returns their permanent column to the source and canvas. Search expansion must be separate from saved expansion or a query would rewrite the reader's workspace.

**Alternatives.** A second project picker beside the tree (two keyboard models); filtering only expanded groups (hidden projects become unfindable); mapping tier ids only in `migrateV1` (early v2 envelopes already carry those ids).

### A file import creates a scratch project

**Decision.** `Import .circ` reads one file through `File.text()` and calls `createScratch` with its stem as the project name. The store numbers duplicate names, enforces the 32 KiB UTF-8 source cap and evicts the oldest scratch project when necessary, keeping the previously active project. Success opens the new project, closes the switcher and reports the import; refusals and read failures leave the current project intact. The picker and button remain disabled until the read settles, and the picker clears afterward so the same file can be chosen again. Source and selection persist through the existing envelope.

**Rationale.** An import is another way to create a project, so it uses the same limits and persistence path. `describeNote` accepts an import context for a skipped source: its save-time sentence says the source stays open, which would be false for an import that created nothing. The import sentence names the refusal and the cap.

**Alternatives.** A separate import store (two limits and two persistence paths); reusing the save refusal verbatim (promises an open project that does not exist); a multi-file picker (outside this handoff).

### The Data panel keeps a position per project

**Decision.** Data opens a non-modal 312px card over any view, anchored 52px down and 16px from the region's right edge. Its header carries the grip, pin counts, native hex/bin/dec radios and Close; its input/output sections use `1fr 36px 92px` rows. Scalar inputs are 22px knobs, buses are fields, outputs are read-only, and Reset sits beside the footer hint. The radios and the settings select use one binding. An edited field owns the first Escape to restore its value; the next closes the card and returns focus to Data.

The grip captures one pointer and waits for a four-pixel move. Release commits the clamped position; Escape, pointer cancellation, lost capture and a project switch abandon it. Arrow keys commit 8px steps, or 32px with Shift. `dataPanel[activeId]` stores the last committed position in the version-2 envelope. Opening and resizing clamp the rendering without overwriting that intent; changing projects closes the panel. Normalization accepts nonempty catalogue id shapes and surviving scratch ids with finite coordinates, dropping bad entries without resetting projects.

**Rationale.** A card's position is the reader's arrangement of that project's bench. A smaller window may borrow space but must not erase that arrangement. Pointer cancellation and resize therefore render from saved intent; only a deliberate move writes it.

**Alternatives.** One position for every project (different circuits need different space); a second storage key (splits the envelope's quota and migration handling); persisting each resize (forgets the larger window); pointer-only movement (the same steps are inexpensive to expose on the grip).

### The Data card and canvas share the session being built

**Decision.** `ensureSession` shares its pending promise for an artifact's bytes, so simultaneous Live and Data requests produce one session. Data controls rebuild on session identity as well as pin shape; their handlers therefore drive the current session after recompilation. Restoring `dataOpen` uses the deferred `onDataOpen` hook, and artifact delivery fills the card after the simulator record exists. Rows and edits still come from the dynamically loaded `data-view.ts`, and every edit and reset reaches the console through the session's events.

**Rationale.** The two faces can become visible together. Without a shared pending build they could create separate runtimes; without session identity in the rows' rebuild key, a same-shaped circuit could leave its controls bound to the destroyed session. A real-artifact island test covers both paths, along with edits, refusals, base changes and reset.

**Alternatives.** One runtime per face (values and the console could disagree); rebuilding rows on every drive (loses a field being edited); reading the simulator from the boot-time restore (the same initialization-order failure Live already fixed).

### The narrow Data panel joins the page flow

**Decision.** Above 800px the open panel reserves 344px at the view's right, and an idle canvas refits after measurement, at most once per frame. Below that width the card is a static block above the selected view, the grip is hidden and disabled, and the right reserve is removed. The app frame's narrow tracks grow with the stacked source and canvas, so the terminal follows them and the page scrolls. Stored panel positions survive this layout unchanged.

**Rationale.** The design stops at desktop widths. Putting a floating card into the narrow page's flow keeps its fields and the view reachable without inventing another docking mechanism. The previous fixed viewport row let the terminal overlap the stacked canvas; automatic narrow tracks remove that conflict.

**Alternatives.** Keeping the right reserve on a narrow screen (leaves too little view); dragging a static card (has no visible meaning); persisting a new narrow position (overwrites the desktop arrangement).

**Follow-up.** With the panel open at 1024px, the four-bit adder reaches the pinned renderer's default 25% zoom floor and clips in the remaining viewport. The sweep should review that default; the panel's refit preserves the existing zoom range.

### The drawer is a resizable row with two columns

**Decision.** The terminal's closed 40px line grows into a drawer, default 320px. Its height lives in the version-2 envelope as `drawerHeight`; the old ratio is dropped on read. The existing pixel splitter sizes the second pane, measures the frame without nav/status chrome, and clamps on render to a 160px minimum while reserving 200px above. Resizing the viewport does not overwrite saved intent. Its handle is centered on the terminal's bordered edge, so pointer movement and height changes agree pixel for pixel.

The console fills the drawer when no memory is declared. Otherwise a hairline separates it from a 560px memory column; below 800px the two stack. The old drawer tabs and their state are gone. A 34px console header holds the label, command title, Clear, Copy script, Copy log and Close; the log remains strict mono at 12.5px/1.5 and keeps its line-kind colors. Focus or a click on the terminal line opens it. Escape clears a nonempty prompt and resets its history cursor; on an empty prompt it closes the drawer. Closing returns focus to the Console button, not the focus-to-open line.

**Rationale.** Console and memory describe the same session and should be visible together. A height expresses the reader's choice directly, while a share of the canvas pane changed meaning when the drawer became a frame row. Returning focus to the opener button avoids reopening the drawer as soon as it closes.

**Alternatives.** Another pixel-splitter implementation (Phase 0 already supplied the unit); changing callbacks to a new object shape (existing callers already speak the configured unit); a tab strip above the columns (another control with no panel to switch).

### The memory grid marks the address net's value

**Decision.** Each memory keeps its own header, paging/jump toolbar, grid and image controls. The grid has a 40px sticky address column and eight shared word tracks, with +0…+7 headers. Tracks use `minmax(max-content, 1fr)` and row-group subgrids: ordinary words spread across the column, and wide binary values scroll within the table. The table, groups and rows remain elements, rather than `display: contents`. Unknown words, implied zeros, the addressed word and the word under edit have distinct marks.

`addressedWord` follows the topology connection whose destination is that memory and whose port is the renderer's `PortName.Addr`, then reads the source component's value. A slice or wire is read directly; a partly defined address selects no word. The legend names the current address. An image line names a loaded file and word count, or typed hex, or the absence of an image; a RAM says its contents live in the circuit. A changed image drops a stale filename. Memory words are read only while the drawer is open.

**Rationale.** The topology says what actually drives addr; the source declaration alone cannot follow a slice or intermediate wire. The address marker must be independent of whether the selected memory word has been written. Shared tracks preserve the board's geometry without truncating a 64-bit value or widening the drawer.

**Alternatives.** Reading the input pin by name (fails through intermediate components); choosing address zero when undefined (claims a read the circuit did not make); fixed-width cells (clip wide values); reading every memory on every drive while closed (work that paints nothing).

### Memory controls reuse the settings and session paths

**Decision.** Memory base radios, Data radios and the settings select write one `valueFormat`. The settings binding delegates native change events so rebuilt memory controls remain bound, and a base change redraws the grid. Refresh, Clear, ROM Load image and Save call the existing memory functions. Jump forces a redraw so its focused input does not suppress paging through the typing guard. Console file refusals, help and preload comments name the memory panel; the grammar, execution and transcript ordering remain the protocol's.

**Rationale.** Rebuilding a small memory view is inexpensive, but binding only the controls present at boot would leave every later radio inert. Keeping the session's existing write and image paths also keeps canvas values, memory values and the console record in agreement.

**Alternatives.** A private base for memory (different faces would spell the same value differently); attaching another settings controller on every redraw (duplicate listeners); bypassing the session for grid writes (loses console echoes).
