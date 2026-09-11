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
