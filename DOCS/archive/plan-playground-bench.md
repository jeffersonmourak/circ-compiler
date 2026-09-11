# Archived plan: playground-bench

**Canonical commit:** `f9298263f6e7ba794e10808a9f360442989c8d62` (`f929826 fix(site): preserve source ROM images across imported circuits`)
**Archived on:** 2026-09-11
**Plan duration:** 2026-09-11 → 2026-09-11

> This file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the commit referenced above. Use `git show f9298263f6e7ba794e10808a9f360442989c8d62:DOCS/PLANS_PROMPT.md`, or the corresponding path under `DOCS/PLANS/` or `DOCS/STATUS.md`, for the unabridged source.

**Closure:** The human requested archival, deletion of the design handoff artifacts, and publication after the implementation and review fixes. Phases 0–6 shipped. The final Phase 7 visual, keyboard and redraw-timing sweep was not performed; its unresolved checks are carried forward below. The handoff remains in the canonical commit at `DOCS/design/design_handoff_playground_bench/`, not in the archive tree.

## Goal & scope

Redraw `/playground` as a canvas-first workbench: source and canvas on one sheet, a project switcher in the nav, diagnostics beneath the editor, Schematic/Live/Truth views, a floating Data panel, and a console/memory drawer. The work stayed within the site's Astro/TypeScript layer: `Base.astro` retains its app variant, bench styles remain scoped to `[data-layout='app']`, every face drives one `SimSession`, persistence uses one versioned envelope, and JavaScript stays within the existing page budget. The compiler and `circ-renderer` remained unchanged; the renderer stayed pinned at `2d973b4` (`2.3.0-alpha.4`).

## Phase-by-phase highlights

### Phase 0 — The handoff and the frame

Give the playground its own viewport frame while retaining the editor, compiler outputs and session controls.

- Tracked the design reference, removing duplicate theme files, stale asset code and 32 unshipped TTFs.
- `Base.astro` yields site nav/footer only for the app layout; `bench-tokens.test.ts` guards bench colors and fonts.
- Added the 48px nav, source/canvas regions, one-pixel divider, 40px terminal line and 24px status line.
- Extended `splitter.ts` with pixel sizing; the source column defaults to 480px and clamps without overwriting intent.
- `terminal-line.ts` derives the last command and reply from the existing console transcript.
- Updated `island-smoke.test.ts` and layout guards; captured the initial frame in both themes.

The banner moved into the source region when the frame first became a grid. Existing `--danger` values were retained. Zero-width initial measurements preserve the intended source width until the observer reports a real size.

### Phase 1 — The source region

Add file tabs, editor metrics and a diagnostics footer, and migrate saved projects to the new layout.

- `footer-summary.ts` counts project lines/components and selects memories, chips or pins as its contextual third count.
- Migrated `circ.playground.v1` to envelope version 2 using `site/test/fixtures/store/envelope-v1.json`; scratch projects survive.
- Added a 36px file strip with roving focus, arrow/Home/End navigation and `+ file` over the existing file model.
- Set editor padding to `16px 0`, text to 14px/1.7, and the transparent 32px gutter to 55% opacity.
- Replaced the dock with a 30px footer, linked diagnostic positions and settings behind a gear; saved footer state.
- Recorded the source-region decisions and captured the expanded diagnostics footer.

The analysis reply has no net count, so the footer reports a noun supported by symbols. Footer and settings moved together because removing the dock required an immediate home for the form.

### Phase 2 — The canvas region and Live

Replace output tabs with three views and expose the pinned renderer's zoom, pan and fit controls.

- Added `zoom-label.ts`, `pin-count.ts`, `View` and `dataOpen`; migrating an old Data tab also opens the new panel.
- Added the view switch, Data button, hint and zoom lines; the playground mount no longer uses `.lc-mount`.
- Enabled `viewport: 'parent'`, modifier-wheel zoom, drag navigation and the renderer's existing view methods.
- Coalesced idle refits after resize; a recent gesture distinguishes reader navigation from the renderer's initial fit.
- Deferred Live restoration through `hooks.onLive` to avoid reading the simulator before initialization.
- Drew dots in world space through the renderer's background hook so they follow pan and zoom.
- Updated renderer-pin tests and browser protocol vocabulary; captured Live and Data-open states.

Theme changes use `setTheme` in place. The final Live mount fills the region, with renderer padding reserving toolbar space. A later human override leaves the dot grid on Live alone.

### Phase 3 — Schematic and Truth

Style the compiled views and make Truth rows drive the live session, including filtered enumeration over the cap.

- Added `truth-view.ts` for parsing, cell spelling, row matching/driving, scratch enumeration, Markdown and CSV.
- Pinned table requests to JSON; copy actions choose their own output format.
- Added Schematic's preview toggles, Copy and character dimensions on the code surface.
- Added the Truth card, first-output rule, live-row tint, keyboard/click activation and count/refusal chip.
- Enumerated unknown pins on a scratch session above the cap, holding known pins without writing the live session.
- Made Truth headers highlight source declarations before any canvas exists.
- Recorded the views and real compiler comparisons in `truth-view.test.ts`.

There is no compiler charset option, so the toolbar offers Expand macros/Expand display instead of the mock's `unicode | ascii`. Scalar cells use plain digits; buses use the renderer's spelling. When unknown pins also exceed the cap, the card reports a refusal rather than the proposed single-row fallback.

### Phase 4 — The project switcher

Move the workspace tree into a searchable popover without reflowing the bench.

- Grouped projects as Tour, Examples and Mine, retaining example tier order and scratch recency.
- Added project/file name filtering, ancestor retention and temporary expansion of collapsed groups during search.
- Added the 340px popover, scrim, focus return, ⌘K/Ctrl+K, keyboard row actions and narrow full-width layout.
- Imported one `.circ` file through the existing scratch-project naming, 32 KiB source limit and persistence paths.
- Tested import cancellation, duplicate stems, read failures and concurrent events; measured no source-width reflow.

Tier migration also handles early version-2 envelopes. Filter tests live in `ws-tree.test.ts`, and import tests in the existing workspace/island suites, rather than a separate switcher test file.

### Phase 5 — The Data panel

Show editable circuit values in a draggable card with a saved position per project.

- `data-panel.ts` supplies the anchor, edge clamp, pointer delta and four-pixel drag threshold.
- Added the 312px card, scalar knobs, bus inputs, output values, shared base controls and Reset.
- Shared pending session builds across Live/Data and rebound Data controls when session identity changes.
- Added pointer capture, cancellation and saved positions; arrows move 8px, Shift-arrows 32px.
- Kept saved intent across resize; below 800px the card becomes static and its grip is inert.
- Verified native drag, reload/project restoration, bus/toggle edits and console echoes in both themes.

Keyboard movement shipped despite being optional in the phase plan. Positions validate catalogue ID shapes and surviving scratch IDs. The 344px right reserve remains fixed while the card is open; wide circuits can meet the renderer's minimum zoom before fitting.

### Phase 6 — The drawer and review fixes

Turn the terminal row into a resizable console/memory drawer and retain the session's existing protocol behavior.

- Extended the existing pixel splitter with second-pane sizing and usable-span measurement; callbacks remain numeric.
- Saved `drawerHeight`, default 320px; focus opens the drawer, Escape clears a prompt before closing it.
- Replaced drawer tabs with the 34px console header and the conditional 560px memory column.
- Added memory shape/base controls, paging/jump, Refresh/Clear/Load image/Save, and delegated settings events.
- `addressedWord` follows the topology's addr edge; the sticky address column and eight word tracks scroll for wide values.
- Recorded the browser protocol and verified ROM/RAM writes, load/save, resizing and hidden-read suppression.
- Matched the editor to `--pane-bg`; Schematic hides the terminal row and restores it on return to Live/Truth.
- Consolidated settings by view and added saved editor wrapping, font size and tab/indent size without rebuilding documents.
- Repainted the collapsed console when session readiness changes.
- Made the active file the request root while retaining sibling imports; file switches invalidate both pipeline sequences.
- Preserved ROM images by project/file/declaration and applied independent copies to imported instances by runtime ID.
- Added bounded image persistence and matching scratch Truth/CSV/Markdown results; included the search-field outline adjustment.

The splitter spec predated pixel mode, so the existing API was extended instead of replaced. Memory grids use `minmax(max-content, 1fr)` and subgrids. Imported-file IDs are captured with the exact compile request, and a changed mapping rebuilds an otherwise byte-identical artifact. Console memory commands remain root-only.

### Phase 7 — Sweep and record: closed with checks outstanding

The planned final phase called for a full board/theme/width matrix, keyboard and announcement review, redraw profiling and archival.

- Archived the implementation record and removed the planning bundle on the human's request.
- Deleted the design handoff artifacts rather than moving them into `DOCS/archive/design/`, as the human requested.
- Retained the living decisions, protocol reference, implementation tests and the follow-ups below.

Earlier slices include browser measurements and captures, but no final all-board sweep or redraw profile was recorded. The archive does not treat those checks as passed. At the canonical commit, all 616 site tests, typecheck, build and bundle checks passed; the final CSS adjustment also passed 14 token/layout tests and a fresh build/bundle check. `/playground` grew from 107.7 KB raw / 38.2 KB gzip to 137.2 KB / 47.7 KB; its ceiling stayed 360 KB / 120 KB. The archive session passed `zig build test-all` before and after cleanup, then a fresh site build, all 616 site tests and the bundle check.

## API surface frozen by the plan

| Surface | Contract |
| --- | --- |
| Storage | `STORE_KEY = 'circ.playground.v1'`, `STORE_VERSION = 2`; `migrateV1` preserves projects and translates the former tabs/dock. |
| Bench state | `view: 'schematic' \| 'live' \| 'truth'`, `footer`, `layout.sourceWidth`, `dataOpen`, `dataPanel`, `drawerHeight`, `editor`, `activeFile`, `sourceImages`. New fields default without another schema bump. |
| File requests | `requestFor(files, options?, rootName?)` keeps every sibling in `/playground/`; the optional root selects an independent circuit. The last file remains the interchange default. |
| ROM ownership | `sourceImageKey(project, file)`, `normalizeSourceImages`, `ImportedImages`, `applyImportedImages`; image text is validated against each compiled ROM's shape. |
| Session preloads | `SessionInit.importedImages` joins root `roms`/`images`; build, reset and `applyPreloads` use the same source images. `hasRam` includes nested RAM. |
| Truth | `parseTruthTable`, `columnOf`, `cellText`, `liveRowIndex`, `driveRow`, `unknownInputs`, `rowsForPins`, `toMarkdown`, `toCsv`; scratch tables never drive the live session. |
| Geometry | `createSplitter` supports `unit: 'px'`, `pane` and `measure`; `clampPanel`, `positionFromDrag`, `crossedThreshold` keep panel geometry pure. |
| Editor | `normalizeEditorPreferences` and `EditorHandle.setPreferences`; 10–24px font size, 1–8-space indentation, default 14px/two spaces/wrapping on. |
| Renderer integration | Existing `navigation`, `viewport`, `onViewChange`, `fit`, `resetView`, `getView`, `setView`, `zoomBy`, `setViewport`, `setTheme` and background hook. |
| Compiler modes | Existing `--analyze`, `--preview`, `--truth-table`, `--format=markdown\|csv\|json`, `--sim`, `--mem=<name>=<path>`, `--warnings-as-errors`/`-Werror` retain their contracts. No CLI flag was added. |
| Diagnostics | `E001`–`E018` and `W001`–`W003` remain unchanged; browser session errors retain `E_PROTO`, `E_NOPIN`, `E_NOTIN`, `E_WIDTH`, `E_BADVAL`, `E_NOSETTLE`, `E_NOMEM`, `E_IO`, `E_MEMFMT`, `E_ADDR`. |
| Runtime exports | Unchanged: `topology_alloc`, `init`, `run`, `setPin`, `getOutputValue`, `getOutputDefined`, `getMemInfo`, `memBuffer`, `memLoad`, `memStore`, `memClear`, `setMemWord`, `getMemValue`, `getMemDefined`. |

## Known papercuts carried forward

- **Final verification:** the complete 1440/1024 light/dark matrix, 700px stack review, keyboard/announcement sweep and `four_bit_adder` hover/zoom timing remain unperformed.
- **Truth cost:** `rowsForPins` enumerates synchronously on the main thread. Sixteen rows took 1.9ms on the four-bit adder; the recorded 0.5s estimate for 4,096 rows is an extrapolation. Consider chunking or a lower scratch cap.
- **Partly known buses:** any undefined bit makes the entire input pin unknown for enumeration. Preserve known bits if bit-level filtering is added.
- **Fit floor:** at 1024px with Data open, the four-bit adder reaches the renderer's 25% minimum zoom and clips. Review the renderer limit in its own worktree.
- **Canvas chrome:** the Live hint and zoom line overlap at 1024px. Review their layout independently of circuit fitting.
- **Touch breakpoint:** gesture ownership is selected at canvas construction. Crossing 800px keeps the old touch behavior until a canvas rebuild.
- **Small source pane:** footer statistics truncate below roughly 440px; the default 480px column fits them.
- **Image persistence:** images too large for the space left in the envelope remain session-only, with a reload notice. Share links and artifacts do not include image contents.
- **Compatibility fields:** the old `PlaygroundSettings.format` field remains stored although copy buttons select the format.
- **Deferred scope:** ASCII preview charset, a compiler fixed-input Truth option, multi-file/folder picking, content search, resizable/dockable Data cards, board 1a and a designed mobile layout were not implemented.
- **Historical captures:** screenshot names and measurements are preserved in the canonical STATUS log; the captures were temporary session files, not repository assets.

## Decisions & specs that survived the plan

- [Playground bench decisions](../decisions/playground-bench.md): layout, migration, source/footer, renderer navigation, Truth, switcher, Data, drawer, preferences and source-owned images.
- [Earlier playground decisions](../decisions/playground.md): shared session, protocol transcript, source interchange, persistence and lazy-module foundations.
- [Canvas theme decisions](../decisions/canvas-theme.md): renderer hooks, token palette, gate shapes and drawing contracts.
- [Browser and CLI simulation protocol](../sim-protocol.md): console grammar, replies, memory operations and browser-specific behavior.
- [libcirc API](../libcirc-api.md), [analysis API](../analyze-api.md), [runtime WASM API](../wasm-api.md), [preview](../preview.md), [language](../language.md) and [architecture](../architecture.md): authoritative compiler/runtime contracts.
- `site/test/island-smoke.test.ts`, `site/test/source-images.test.ts`, `site/test/truth-view.test.ts`, `site/test/sim-transcripts.test.ts`, `site/test/playground-store.test.ts` and `site/bundle-budget.json`: executable behavior and size limits.
