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
