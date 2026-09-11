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

**Decision.** `nsValuePill` is a 0.92-cell chip, solid for HIGH or a bus, outlined for LOW, dashed for undefined, seated with its bottom 0.5 cells above a pin's circle or 0.5 cells above a box's top edge. A single-bit pin draws its own `0`/`1`/`?` pill; every multi-bit component's pill is drawn by the `busValue` hook with the canvas's `text`, solid in `wireBus` with `busLabel` ink; `rom` and `ram` get none. The pill's top is 1.34 cells above a 3-row pin box, so both islands pass `layoutOptions: { rowGutter: 2 }` and pad by `Math.ceil(cell * 2)` (1.5 cells fit the chip to the pixel and a reader saw it cut); `island-canvas-options.test.ts` guards both.

**Rationale.** The canvas spells a bus in the reader's chosen base (`setValueFormat`), and only the hook is handed that text; a pill drawn from a skin would ignore the setting. The renderer's default badge was the library's blue text, off-palette on both panes. The gutter and padding follow from the pill's geometry, measured, not chosen.

**Alternatives.** Drawing every pill from the skins (loses the base setting); shrinking the pill to fit one row (the design seats it clear of the hover ring, and the ring needs the room); changing `ROW_GUTTER` in the compiler (every layout golden moves for a site-only need).

### Hover is a ring outside the pin, through the highlight hook

**Decision.** `drawHighlight` is the `highlight` hook: for `input_pin` and `output_pin` a circle 0.38 cells outside the pin's own, in `inputHover`; for every other kind the rounded box the site drew before. No skin reads `hovered` or `inputHover`; `circ-theme-hover.test.ts` guards both, and that `nsHoverRing` has exactly one caller.

**Rationale.** Hover used to swap the input pin's fill and border for yellow and so hid the value the reader was about to toggle; the design keeps the state visible under the mark. Drawing it from the hook keeps the playground's decision that one hook marks every kind, so an editor cursor on a `rom` still lights it.

**Alternatives.** The design's own placement, a ring drawn from the pin skin (two rings for a hovered pin, or none for a highlighted rom); a fill change with the state kept in the border (a colour-only cue again).

### No new component kinds: a builtin gate is the macro it already is

**Decision.** The six two-input builtins and `not` reach the canvas as collapsed subcircuit boxes (the site lays out in opaque mode; the playground's "Expand macros" setting reaches the compiler's preview, not the canvas), and the `subcircuit` skin draws any name in the recipe table through `nsGate` on a virtual 5-wide box centred in the macro box, its tails running to the real ports. No kind byte is added to `lib/topology/format.zig`, no `ComponentKind` to the renderer, no footprint or port slot anywhere; `buffer` has no source form and is not drawn. The handoff's "new kinds needed in the library" paragraph is superseded by this entry.

**Rationale.** The language locks `or`, `nand`, `nor`, `xor` and `xnor` as auto-imported macros of `and` and `not` (`DOCS/decisions/language.md`); a primitive kind for each would be an engine evaluator, a topology version, a runtime bump and a renderer change, for a picture the macro box already gives. NOR and XNOR, which the site never drew before, come free from the recipe.

**Alternatives.** Six primitive kinds and `buffer` in the compiler (the handoff's ask; out of proportion, and it would make the flattened `.min` blob carry gates the engine does not evaluate); drawing the builtins with the old sprite path (the NAND and XOR PNGs, with a bubble baked in at a different spacing from the vector one).

### Two sprites, tinted and measured, behind the assets seam

**Decision.** `circ-assets.mjs` exports `AND` and `OR` only. A sprite is never drawn raw: `tintedSprite(name, colour, alpha)` recolours it inside its own alpha (`spriteInk` at 0.94 for LOW, `inputOn` at 0.92 for HIGH, `labelMuted` at 0.5 for undefined), `haloSprite(name, colour)` blurs a tinted copy once on a canvas padded by `HALO_PAD = 0.14` and knocks its core out, and the page's `Assets.bounds(name)` measures the painted extent with one 128×128 `getImageData` on the decoded image in the drawn rotation. Each is built once per name and colour into an offscreen canvas from `assets.offscreen` and cached by name; `makeSkins` empties every cache when it rebinds. The symbol is sized from those bounds to span the port rows and fit the gate slot, so the transparent padding in the PNGs no longer misaligns the lobes. Before the PNGs decode an AND or OR is a vector stand-in in the same painted bounds.

**Rationale.** The PNGs have dark interiors that composited unchanged onto the light pane, and a HIGH gate differed from a LOW one by tail colour alone. Tinting inside the alpha keeps the art and gives it the palette; a pre-rendered halo keeps `shadowBlur` out of every frame. Measured bounds are what make one symbol size hold across AND/NAND, OR/NOR and XOR/XNOR.

**Alternatives.** Drawing all seven gates as vectors (throws away art the site's readers know); tinting per frame with `source-atop` on the main canvas (a full-box composite per gate per frame); keying caches on `img.src` (a 20 KB string per key).

### The gate anatomy is three containers, and the geometry is a tested seam

**Decision.** Every gate is laid out from `[exclusive][gate][negate]` inside its box: `NS_INSET = 0.4` cells from the box edge, side slots of `NS_SLOT = 0.55` cells, the gate container between. The symbol is fitted by `nsFitSymbol` to the smaller of the port spread's height (`2(n−1) + 2` cells for `n` inputs) and the gate slot's width, centred on a span an unused slot lends its width to; the negate bubble (`NS_BUBBLE_R = 0.24`) is tangent to the measured tip and clamped inside its slot; the exclusive curve's apex sits `0.14` cells plus half its stroke left of the OR back's apex. `gateGeometry(cell, component, bounds, opts)` returns that layout and is exported so the anatomy tests read it without drawing.

**Rationale.** With the slots always reserved, the symbol is the same size at the same x across the family, and the box, ports and tails never move; NOT and NAND stop relying on a bubble baked into their own PNG at a spacing that differed from NOR and XNOR. A geometry the tests can read is what lets the op-log goldens stay the drawing's contract while the layout is asserted directly.

**Alternatives.** Per-gate hand placement (the spacing drift the handoff named); sizing by the PNG square (the ~28% transparent padding misaligns the lobes).

### Slice and concat draw the bit field, not a box around a label

**Decision.** A slice is a ruler of the incoming word, MSB left so it reads like the hex chip above it, the tapped bits `[lo, hi)` filled in `wireBus` (alpha 1, 0.7 or 0.4 for HIGH, LOW, undefined output) and the discarded bits in `labelMuted` at 0.38, with `[lo:hi]` or `[n]` under it; above `RULER_MAX_BITS = 16` bits it is one muted bar with the tapped span filled at `(inWidth − hi) / inWidth` from the left, `(hi − lo) / inWidth` wide. A concat is one band per operand stacked on the output side with a numbered lane from each port, operand 0 on top, alpha `max(0.45, 1 − 0.2 i)` down the stack. Both sit in `nsShell`, a `wireBus`-stroked shell on `surface`, with the gates' tail and dot rule. Footprints are unchanged.

**Rationale.** A labelled box says a slice exists; it does not say which bits it takes, and `[0:4]` had to be decoded. With the picture, the low nibble is visible at a glance and the concat's operand order is drawn rather than implied. The handoff left the wide case undesigned; a bar with the span filled is the smallest thing that keeps the direction and the proportion.

**Alternatives.** Keeping the label-only box (the state before); a ruler at any width (33 ticks in a 5-cell box at cell 10 are 1px each).

### A user subcircuit and a memory share one chip

**Decision.** `nsChip` draws a `macro`-stroked shell on `surface` inset `NS_INSET` from the box, a one-cell header band in `macro` at alpha 0.18 clipped to the shell, and a rule at 0.5; `nsChipPart` puts the gates' tails and dots around it. A user subcircuit carries its name in capitals in the header (`macro`, 700) and the instance name in the body (`label`, 500). A memory carries its declaration in the header, `MODE` left and `W×2^A` right, and `addr → word` in the body from `inputValues[0]` and `outputValue` through `nsHex` (bigint masks; `?` when not fully defined); a RAM labels its four ports inside the left edge on their rows and puts the instance name under the word, a ROM below the box. The renderer's `memoryLabel` is no longer imported.

**Rationale.** The header is what separates "a box I wrote" from the gate family at a glance, and a memory is a box the reader wrote whose one interesting fact mid-simulation is the word at the address. Contents are runtime configuration, so the declaration is all the source knows and all the header claims. Reads are asynchronous, so the word is the output already.

**Alternatives.** The preview's `rom code[8,4]` label on a box (says nothing a reader wants while clocking); reading the word through the runtime from the skin (a skin has no runtime handle, and the output is the same value).

### The RAM write indicator mirrors the engine's edge rule on the canvas

**Decision.** `ramWriting` keeps the last `clk` value per canvas element (a `WeakMap` on `ctx.canvas`) and per component id, and lights the `wr` dot for the draw in which `clk` is high and was low, `we` is high, and `addr` is fully defined — the predicate of `lib/circuit.zig`'s memory arm, whose initial `prev_clk` is undefined so the first defined-high clock is not an edge. A `we` that settles low in the same step the clock rises can differ from the engine; the runtime stamp of decision 11 stays the follow-up.

**Rationale.** The moment a RAM does something a ROM cannot is the one worth a mark, and the port values the canvas already hands the skin are the values the engine reads. Keying on the canvas element keeps the state across a theme flip (the element survives `setTheme`) and drops it with a rebuild.

**Alternatives.** A runtime export for the last write (four layers for one dot; deferred, not refused); diffing the addressed word between draws (a write of the same value is invisible).
