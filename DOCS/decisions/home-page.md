# home-page

The entries below record the decisions exercised while redrawing the site's landing page around a live circuit. The active plan and implementation record are in `DOCS/PLANS_PROMPT.md` and `DOCS/STATUS.md` until the initiative is archived.

### The handoff is tracked without its unused payload

**Decision.** The repository tracks the home-page board, its source map, harness modules, CircDS bundle and two WOFF2 faces under `DOCS/design/design_handoff_home_page/`. The 32 JetBrains Mono TTF files, `.DS_Store` files and the handoff's stale `circ-assets.mjs` copy are removed. Where its README and board disagree, the board is authoritative.

**Rationale.** The retained files make the design reproducible and citable. The removed files added 7.6 MB without changing the mock or the shipped site.

**Alternatives.** Commit the zip verbatim; leave the handoff outside the repository; put design-only files under the shipped site.

### LiveCanvas adds only requested surfaces

**Decision.** `LiveCanvas.astro` accepts optional label, source, values, link and parent-fit inputs. Source-backed cards render a highlighted source pane and stage; values-backed cards render root pin values and a checked playground-link slot. Parent fit gives the renderer a parent viewport with navigation disabled. Calls that pass none of these inputs keep the gallery's original attributes and child order.

**Rationale.** The hero and gallery use the same renderer lifecycle, lazy imports, memory loading and in-place theme changes. Conditional markup prevents a landing-page design from silently changing every gallery card.

**Alternatives.** A separate hero renderer; unconditional wrappers around every card; CSS scaling of the fitted canvas.

### Home and live-canvas rules join the token guard

**Decision.** The source-text guard in `site/test/bench-tokens.test.ts` checks selectors containing `.home-` and `.lc-` beside `.pg-`. Their colour and font declarations must use the site's tokens, with the existing transparent, inherited and black-shadow allowances.

**Rationale.** A literal colour or face can look correct in one mode while drifting in the other. The guard catches that without a browser or a new lint dependency.

**Alternatives.** Review convention alone; a second test with different allowances; a stylelint dependency.

### The values line is pure text before it is DOM

**Decision.** `site/src/scripts/pin-line.ts` collects root pins as inputs then outputs and formats them as `name = value`, with a middle dot within a side and an arrow between sides. One-bit pins use a digit, buses use the selected base, and any undefined bit makes the pin `?`. The module imports no renderer code; `LiveCanvas` supplies kind values from the renderer module it has already loaded and turns the returned parts into marked name spans.

**Rationale.** The spelling is unit-testable without a canvas, WASM or browser. Passing kind values avoids both an eager renderer import and copied topology bytes.

**Alternatives.** Build the sentence directly in the island; import `ComponentKind` eagerly; copy numeric kind values into the helper.

### The hero shows the renderer's real boot state

**Decision.** The hero does not seed its inputs. The renderer drives them low and settles during startup, so the initial line is `a = 0 · b = 0 → sum = 0 · carry = 0`; a reader's pin click updates the line from that state.

**Rationale.** A fresh simulation should report what the runtime actually holds. A fixture state chosen for a static board is not an additional boot protocol.

**Alternatives.** Drive both inputs high after mount; hard-code the board's values until the first click; leave the values line blank after mount.

### The preview section frames the existing figure

**Decision.** The landing page reuses `CodePreview` without a caption and adds its heading, lede, checked playground link and status row outside the component. The language section uses four vocabulary rows and three numbered steps. Example syntax follows the compiler: `a[0..2]` and `import adder "adder.circ"` correct the board's illustrative spellings.

**Rationale.** The shared figure continues to serve the gallery while the landing page owns its surrounding presentation. Source examples must be valid language syntax.

**Alternatives.** Fork the figure; change the gallery's component to accommodate one page; copy invalid syntax from the board.

### The landing twin follows the visible sections

**Decision.** `emitLandingTwin` mirrors the hero, language vocabulary and pipeline, preview section and download link in page order. Its section headings match the page's headings. The `llms.txt` description names these sections. Gallery content waits until the page actually contains gallery tiles.

**Rationale.** Readers of Markdown should encounter the same content as browser readers. A heading comparison guards against stale prose surviving a redesign.

**Alternatives.** Leave the previous three prose sections in the twin; describe planned tiles before they ship; generate Markdown by scraping the page.

### Gallery tiles use shipped sources and images

**Decision.** The landing page selects `two-bit-adder`, `four-bit-adder` and `rom-lookup` explicitly and fails the build if an artifact is missing. A pure `tileMeta` helper counts declared pins, not bits, and derives memory capacity from address width. The ROM receives the same source-owned image as its gallery card. Markdown links go to `gallery.md` without fragments because its title-derived anchors differ from the HTML slugs.

**Rationale.** Tile labels and simulations should describe the examples actually shipped. The design's illustrative names and counts are not source data.

**Alternatives.** Copy the board's counts; select examples by tier order; generate duplicate artifacts for the landing page.

### Thumbnails are fixed-cell crops inside links

**Decision.** `LiveCanvas`'s thumbnail variant suppresses the header and disables renderer interaction and navigation. The tile is one anchor; its loading indicator is an inert span rather than a nested button. The existing 200px observer margin defers mounting. Slots are 150px tall, with native-width canvases at cells 5, 6 and 6. Safe vertical centering centers short circuits while oversized circuits retain their top edge.

**Rationale.** Native sizing keeps small circuit details crisp. A single link makes pointer and keyboard navigation unambiguous; the gallery is where pins become interactive.

**Alternatives.** Scale each circuit into its tile; put a button inside the link; make thumbnail pins compete with the tile's navigation.

### Sections stack without changing the simulation

**Decision.** Home-page sections use scoped grids and token-based surfaces, with 40px desktop side padding and 24px below 800px. The hero, language, preview and tiles become single columns on narrow screens. The install row stacks its text and target. Renderer viewport and thumbnail crop rules remain scoped to their component variants.

**Rationale.** The same source and controls must remain reachable when the available width changes. Responsive presentation must not rebuild a simulation or restyle the gallery's shared mount.

**Alternatives.** Hide content on narrow screens; scale the entire page; let app-layout rules reach the landing canvas.

### Navigation stays in ordinary links

**Decision.** The filled playground call precedes the outlined reference call. The download chip and install row link to `/download`. Example-specific playground links use `OpenInPlayground`'s catalogue check. Gallery tiles link to the shipped HTML anchors.

**Rationale.** These actions navigate to existing destinations and need no additional client-side state or handlers.

**Alternatives.** Scripted buttons for navigation; unchecked example fragments; another download mechanism on the home page.

### Rendered checks complement structural tests

**Decision.** Tests enforce source-derived metadata, page structure, token use, memory attributes and bundle limits. Chrome checks cover both themes at 1100, 1440 and 700px, including pin clicks, deferred thumbnails and install-row layout. Browser review was brought forward after Phase 0's tests missed inherited code-block styles and a collapsed narrow canvas.

**Rationale.** A structurally correct DOM does not prove computed geometry or typography. Actual rendering caught defects that source checks could not see.

**Alternatives.** Treat a successful build as visual sign-off; wait until the end to inspect all layout changes.

### Copy and reviewed design changes stay explicit

**Decision.** Labels and ledes follow the handoff, with syntax corrected to the actual language and counts derived from sources. During review the user widened main to 1500px, moved Playground first in the nav, right-aligned navigation, separated gallery tiles by 2rem with individual hover borders, and removed the lineage paragraph. The Markdown twin follows that final removal. The preview retains the user's two-panel presentation.

**Rationale.** The handoff guides the implementation, but subsequent user edits are part of the accepted design. Documentation must record departures rather than claim pixel identity with the original board.

**Alternatives.** Overwrite reviewed changes to recover the original mock; preserve removed prose only in Markdown; silently change example syntax or counts.

## Locked-decision map

| Plan decision | Recorded under |
| --- | --- |
| 1, 2 | The handoff is tracked without its unused payload; Copy and reviewed design changes stay explicit |
| 3 | Gallery tiles use shipped sources and images |
| 4 | LiveCanvas adds only requested surfaces |
| 5 | Thumbnails are fixed-cell crops inside links |
| 6 | Home and live-canvas rules join the token guard |
| 7 | The values line is pure text before it is DOM |
| 8 | The hero shows the renderer's real boot state |
| 9, 10 | Sections stack without changing the simulation |
| 11 | Navigation stays in ordinary links |
| 12 | The preview section frames the existing figure |
| 13 | The landing twin follows the visible sections |
| 14 | Rendered checks complement structural tests |
| 15 | Copy and reviewed design changes stay explicit |
