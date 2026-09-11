# canvas-theme

The entries below record the decisions of the canvas-theme initiative: the site's circ-renderer theme (`site/src/utils/circ-theme.mjs` and the modules it split into) ported to the design handoff under `DOCS/design/`, and the three additions the renderer grew for it. The sixteen decisions locked at plan time are in `DOCS/PLANS_PROMPT.md`; each phase appends the ones it exercised here as it ships them.

### The renderer grows three hooks, and the site fills them

**Decision.** `circ-renderer` gains `CircTheme.fanOutMarker` (called once per junction cell with the group's value, in place of the default dot), a `TraceOptions` object on `traceWire`/`wirePath` whose `cornerRadius` makes the wire one continuous subpath with `arcTo` corners and the crossing hops spliced in travel order, and `LayoutOptions.rowGutter` (default `1`) threaded into the coordinate stage. The dead `grid` colour key leaves `ThemeColorKey`. The three ship together as `2.3.0-alpha.1`; the site pins that sha and asserts it in `RENDERER_PIN_VERSION`.

**Rationale.** The design needs a ring with the pane showing through at a junction, rounded corners that survive a crossing, and a value chip above a pin that reaches 1.34 cells over its box. None of those can be drawn from outside the canvas without repainting over its own marks, and each is a few lines inside it. The gutter is an option rather than a constant change so the parity goldens and the ASCII preview, both pinned at one row, do not move.

**Alternatives.** A second path builder on the site (the property that the site cannot draw a jump the renderer would not is lost); changing `ROW_GUTTER` in Zig and TypeScript (every layout and render golden moves for a site-only need); leaving `grid` in place (a key nothing reads, in a table a host copies).

### The theme is three modules, and the skins take their sprites by injection

**Decision.** `site/src/utils/circ-palette.mjs` holds the two palettes and `PaletteKey`; `circ-skins.mjs` holds every drawing function and exports `makeSkins(assets)`, which binds an `Assets` object (`sprite(name)`, `offscreen(w, h)`) and returns the theme pieces; `circ-theme.mjs` stays the entry the islands import, decoding the PNGs and building `blogTheme`, `blogThemeLight` and `pickTheme` from the other two. The moved functions are byte-identical except that a sprite is read through `sprite(name)` instead of a module variable the loader assigned.

**Rationale.** The one-file theme called `loadAssets()` at import, which needs `new Image()`, so `bun test` could not load it and its only test was a source-text guard. With sprites and offscreen canvases injected, a test hands in a stub and drives every skin; the page hands in a live lookup so a canvas that mounted before the PNGs decoded still draws the vector fallback and the sprite-ready retheme still picks the art up.

**Alternatives.** Mocking `Image` and `document` globally in the test runner (fragile, and the module would still decode five PNGs per test file); keeping one file and testing through the built site (no per-skin assertion possible).

### What a skin draws is pinned as an op log

**Decision.** `site/test/canvas-record.ts` is a 2D context that records every method call as `[name, ...args]` (numbers rounded to three decimals, an image as `sprite:<name>`) and every property assignment as `["set", name, value]`, with `measureText` answering 0.6 cells per character. `site/test/circ-skins.test.ts` runs every registered skin over a fixed component at cell 10, 14 and 24, signals 0, 1 and 2, widths 1 and 8, with and without sprites, and the wire hook over three wire shapes and the highlight hook over every kind, and compares each log to `site/test/fixtures/skins/<kind>.json`, one file per kind keyed by combination. `UPDATE_GOLDENS=1 bun test` rewrites them. Every log must balance `save` and `restore`.

**Rationale.** There is no pixel to look at under `bun test`, but the sequence of calls a skin makes is exactly what a reviewer needs to see change: a stroke width, a colour key, a missing `restore`. One file per kind keeps the fixture set to thirteen files a diff can be read in, rather than one per combination.

**Alternatives.** Image snapshots through a headless browser (a second toolchain, and a diff nobody reads); no drawing tests (the state before this initiative).

### The handoff is tracked beside the plan

**Decision.** `DOCS/design/` is committed as the design reference — the two `.dc.html` sheets, `circ-site-theme.js` (the port target), `circ-skins.js`, `circ-scenes.js`, `support.js`, `README.md` and `github.md` — without `.DS_Store` files and without its copy of `site/src/utils/circ-assets.mjs`, which is byte-identical to the site's. When the initiative archives, the directory moves to `DOCS/archive/design/canvas-theme/`.

**Rationale.** Every phase cites the design file by line; a reference that is not in the tree cannot be cited. The sprite copy would be a second source of truth for the same bytes.

**Alternatives.** Keeping the handoff outside the repository (uncitable); committing it under `site/` (it is not shipped and must not be).

### The design file wins over its README

**Decision.** Where `DOCS/design/README.md` and `DOCS/design/circ-site-theme.js` disagree, the code is the value ported, and STATUS names it. Four disagreements found: the wire corner radius (README `cell × 0.4`, code `cornerR = cell * 0.6`, taken 0.6), the wire weight (README `max(2, cell × 0.16)`, code `nsWire = max(2, cell × 0.2)`, taken 0.2), the hover ring offset (README `r + 0.32`, code `r + cell * 0.38`), and the sprite halo padding (README `HALO_PAD = 0.18`, code `0.14`). The last two land in Phases 2 and 3.

**Rationale.** The README says the JS file is the source of truth and the sheet was rendered from it; the values a reviewer approved on the sheet are the code's. A number copied from prose would be a value nobody saw drawn.

**Alternatives.** Taking the README's numbers (unrendered); asking per value (four questions for one rule).

### The palettes are the handoff's, verbatim, minus one key

**Decision.** `circ-palette.mjs` holds `nextSiteDark` and `nextSiteLight` from the design file as `colorsDark` and `colorsLight`, 27 keys each: the site's 24 plus `surface`, `spriteInk`, `wireBus` and `busLabel`, minus `grid`. Two semantics moved with them: dark `labelOnComponent` is the pane's ink (`#0c0517`) rather than white, and dark `wireIdle` is `#4c3a6b` rather than `#dee2e6`. A test holds both palettes to the same key set and asserts dark `wireIdle` is darker than `label`.

**Rationale.** `wireBus` and `busLabel` were always read by the renderer and never defined by the site, so every bus badge fell back to the library's `#1971c2`; `surface` and `spriteInk` are what the hollow pins and tinted sprites of the later phases fill with. White on the new HIGH orange is 2.9:1 and the pane's ink is 7.6:1. Idle wires were the brightest thing on the dark pane.

**Alternatives.** Adding only the four keys to the old palettes (keeps the idle-over-active inversion); keeping `grid` for a future background (five initiatives have not wanted one).

### Every stroke follows the cell, and a skin's colour is a palette value

**Decision.** `nsWire(cell) = max(2, cell × 0.2)` is the wire and tail weight, 1.5× for a bus; the terminal dot is 0.24 cells; a name sits 0.16 cells under its box; fonts come from `nsFont(cell, weight)`, 0.6 cells and never under 9px. Two source guards in `circ-skins.test.ts` hold this: no `lineWidth = <digit>` in `circ-skins.mjs`, and every `fillStyle` or `strokeStyle` a skin sets during the golden run is a value of one of the two palettes.

**Rationale.** The site drew every wire and tail at 4px whatever the cell, so they were hairlines at cell 24 and swamped the sprites at cell 10; the NOT label's `−cell × 15` offset was the same class of literal. A colour literal in a skin is a colour the theme flip cannot reach.

**Alternatives.** A per-cell lookup table (three cell sizes today, any tomorrow); guarding by review (the 4px lasted four initiatives).

### The wire hook traces through the renderer, corners included

**Decision.** `drawWire` strokes `traceWire(ctx, wire, cell, { arcRadius: cell * 0.4, cornerRadius: cell * 0.6 })` in `theme.colors[wireColorKey(wireStyleOf(value))]` at `nsWire` weight; an active single bit is stroked twice, first at `+0.5 cell` width and alpha 0.22 as a glow under the colour; a bus gets `nsBusTick`, the slash and bit count on its first horizontal run of two cells or more. A fan-out junction is `drawFanOut` through `fanOutMarker`: a 0.3-cell disc in the wire colour, a 0.13-cell centre cut with `destination-out`, inside `save`/`restore`.

**Rationale.** The renderer's tracer is the one place a jump or a corner is decided; a copy of that loop on the site is what the playground carried before and what silently drifted. The glow as two explicit strokes, not the design harness's patched `ctx.fill`, keeps every context change inside a `save`/`restore` the op-log test can see. The knock-out rather than a background fill is what a transparent canvas needs.

**Alternatives.** Porting `drawWireNextSite` as written (a second tracer); `shadowBlur` per frame for the glow (the design's own performance note rules it out).

### A pin's shape carries its state, and its name owns the centre

**Decision.** `nsPinCircle` draws HIGH as a solid disc under a halo (a translucent disc 0.7 cells wider, alpha 0.22), LOW as a hollow ring on `surface` with the border at 1.2× the line weight, and undefined as a dashed outline in `labelMuted`; the name is always in the centre in `labelOnComponent` (HIGH) or `label`. The old rule that a short name goes below and the circle shows `0`/`1` is gone. An LED follows the same rule: lit is a disc under a 1.3-cell halo with a glint of `background`, unlit a hollow ring with a small `outputOff` core, undefined dashed.

**Rationale.** A HIGH and a LOW pin used to differ by colour alone, which a greyscale screenshot and a colourblind reader both lose. With the state in the silhouette and the name fixed, a diagram reads the same at every width.

**Alternatives.** Keeping the `0`/`1` inside and the name below for short names (two layouts for one part); a colour-only design with a stronger contrast (still colour-only).

### The value pill is one shape, drawn by whoever knows the text

**Decision.** `nsValuePill` is a 0.92-cell chip, solid for HIGH or a bus, outlined for LOW, dashed for undefined, seated with its bottom 0.5 cells above a pin's circle or 0.5 cells above a box's top edge. A single-bit pin draws its own `0`/`1`/`?` pill; every multi-bit component's pill is drawn by the `busValue` hook with the canvas's `text`, solid in `wireBus` with `busLabel` ink; `rom` and `ram` get none. The pill's top is 1.34 cells above a 3-row pin box, so both islands pass `layoutOptions: { rowGutter: 2 }` and pad by `Math.ceil(cell * 1.5)`; `island-canvas-options.test.ts` guards both.

**Rationale.** The canvas spells a bus in the reader's chosen base (`setValueFormat`), and only the hook is handed that text; a pill drawn from a skin would ignore the setting. The renderer's default badge was the library's blue text, off-palette on both panes. The gutter and padding follow from the pill's geometry, measured, not chosen.

**Alternatives.** Drawing every pill from the skins (loses the base setting); shrinking the pill to fit one row (the design seats it clear of the hover ring, and the ring needs the room); changing `ROW_GUTTER` in the compiler (every layout golden moves for a site-only need).

### Hover is a ring outside the pin, through the highlight hook

**Decision.** `drawHighlight` is the `highlight` hook: for `input_pin` and `output_pin` a circle 0.38 cells outside the pin's own, in `inputHover`; for every other kind the rounded box the site drew before. No skin reads `hovered` or `inputHover`; `circ-theme-hover.test.ts` guards both, and that `nsHoverRing` has exactly one caller.

**Rationale.** Hover used to swap the input pin's fill and border for yellow and so hid the value the reader was about to toggle; the design keeps the state visible under the mark. Drawing it from the hook keeps the playground's decision that one hook marks every kind, so an editor cursor on a `rom` still lights it.

**Alternatives.** The design's own placement, a ring drawn from the pin skin (two rings for a hovered pin, or none for a highlighted rom); a fill change with the state kept in the border (a colour-only cue again).
