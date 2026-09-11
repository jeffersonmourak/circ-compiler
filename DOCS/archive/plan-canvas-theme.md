# Archived plan: canvas-theme

**Canonical commit:** `68b52f52a8a0ef78ac049d80438df07a64da90df` (`68b52f5 docs: close phase 5 and sign off the canvas theme plan`)
**Archived on:** 2026-09-10
**Plan duration:** 2026-09-10 → 2026-09-10

> This file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the commit referenced above. Check that commit out (`git show 68b52f52a8a0ef78ac049d80438df07a64da90df:DOCS/PLANS_PROMPT.md`, `…:DOCS/PLANS/PHASE_3_gates.md`, `…:DOCS/STATUS.md`, etc.) when you need the unabridged source.

## Goal & scope

The docs site draws every live circuit through one theme handed to the pinned `circ-renderer` (`site/src/utils/circ-theme.mjs`, consumed by `LiveCanvas.astro` and `Playground.astro` at `cell = 14`). A design handoff (now `DOCS/archive/design/canvas-theme/`, port target `circ-site-theme.js`) audited it and named ten gaps, nine of them defects: a bus drew in plain green because the site never defined `wireBus`/`busLabel`; every stroke was a hardcoded `lineWidth = 4`; the NOT label sat inside its sprite; gate PNGs were static and dark in both palettes; dark-mode idle wires out-shouted active ones; the renderer stamped a fan-out dot nobody could see; hover hid a pin's value under a yellow fill. The plan ported the handoff's palettes, skins, wire and marker treatment into the site — state carried by shape as well as colour, buses with a colour and a bit-count slash, the full ANSI gate family composed from two tinted sprites plus a bubble and a curve, a slice ruler and concat bands, a two-faced subcircuit chip, ROM/RAM chips showing the addressed word — and grew the renderer the three things a theme cannot supply from outside: a `fanOutMarker` hook, corner rounding in `traceWire`, and a `rowGutter` layout option. Anchors that held throughout: the renderer's hook model (the site fills `skins`, `wire`, `portMarker`, `busValue`, `highlight`, `background`, `fanOutMarker`, never repainting over the canvas's own marks); the `LayoutGrid` contract, footprints and port tables frozen, so the parity harness and the ASCII preview did not move; the compiler read-only (no kind byte, no `buffer`, no runtime export — builtins reach the canvas as collapsed macro boxes and are drawn through a recipe); one ring, drawn by the canvas through the `highlight` hook, for every kind; every stroke and font cell-relative; the design file's values over its README's where they disagreed; the per-page JavaScript budget never raised.

## Phase-by-phase highlights

### Phase 0 — Hooks, harness and the handoff

The renderer grew its three additions and the site split its theme into testable modules, with no visible change on any page.

- `circ-renderer` `86469f0`: `CircTheme.fanOutMarker` with `FanOutMarkerContext { ctx, theme, cell, x, y, value, signal }`, called per junction in place of the default dot; `test/fan-out-marker.test.ts`.
- `circ-renderer` `a46bdb1`: `TraceOptions { arcRadius?, cornerRadius? }` on `traceWire`/`wirePath`; with a `cornerRadius` one continuous subpath, `arcTo` corners clamped to half the shorter run, hops spliced in travel order; the positional call unchanged.
- `circ-renderer` `f882353`: `LayoutOptions.rowGutter` (default `ROW_GUTTER = 1`) threaded into `coords.assign`; `grid` removed from `ThemeColorKey` and `defaultColors`; version `2.3.0-alpha.1`.
- Site: the handoff committed under `DOCS/design/` (eight files, no `.DS_Store`, no duplicate sprite copy).
- Site: `circ-theme.mjs` split into `circ-palette.mjs` (palettes, `PaletteKey`, `pickPalette`), `circ-skins.mjs` (every drawing function; `makeSkins(assets)` binds an `Assets { sprite, offscreen }` seam) and the `circ-theme.mjs` entry; moved bodies byte-identical except `sprite(name)` lookups.
- Site: `site/test/canvas-record.ts` (a recording 2D context; `measureText` at 0.6 cells per character) and `site/test/circ-skins.test.ts` with op-log goldens under `site/test/fixtures/skins/<kind>.json`, one file per kind keyed by combination (`sprites.sig1.w8.c14`), regenerated with `UPDATE_GOLDENS=1 bun test`; every log must balance `save`/`restore`.
- Site pinned at the pushed sha; `RENDERER_PIN_VERSION` asserted; baseline theme chunk 28.4 KB raw / 17.2 KB gzip.
- Deviation: goldens are one file per kind (13 files), not one per combination (483), argued in STATUS.

### Phase 1 — Palette, wires and marks

Every wire, tail and dot in the new palettes at a cell-relative weight, rounded corners that survive a crossing, a real bus treatment, and a fan-out ring.

- `colorsDark`/`colorsLight` are the handoff's `nextSiteDark`/`nextSiteLight`, 27 keys: `surface`, `spriteInk`, `wireBus`, `busLabel` added; `grid` gone; dark `labelOnComponent` → `#0c0517`, dark `wireIdle` → `#4c3a6b`.
- `nsFont(cell, w)` (0.6 cells, floor 9px), `nsWire(cell) = max(2, cell × 0.2)`, `nsTail` (1.5× and `wireBus` for a bus port), `nsDot` (0.24 cells), `nsName` (0.16 cells below the box) replaced `drawTailLine`/`drawTailDot`/`drawNameBelow` in every skin; the NOT label came out of its sprite.
- `drawWire` on `traceWire(ctx, wire, cell, { arcRadius: 0.4 cell, cornerRadius: 0.6 cell })`, `nsBusTick` (slash and bit count on the first horizontal run ≥ 2 cells), an active single bit stroked twice (a `+0.5 cell` translucent pass under the colour, as two explicit strokes rather than the harness's patched `ctx.fill`).
- `drawFanOut` as `fanOutMarker`: 0.3-cell disc in the wire colour, 0.13-cell centre cut with `destination-out`.
- Source guards from here on: `no skin sets a literal stroke width`, `every colour a skin sets comes from the palette`.
- Four README/file disagreements in the handoff, the file taken each time: corner radius 0.6 (not 0.4), wire weight 0.2 (not 0.16), hover ring `r + 0.38` (not 0.32), `HALO_PAD = 0.14` (not 0.18).

### Phase 2 — Pins and LEDs

State by shape, a value chip, the ring policy, and the room for both.

- `nsPinCircle`: HIGH a solid disc under `nsHalo` (a translucent disc 0.7 cells wider, alpha 0.22), LOW a hollow ring on `surface` with the border at 1.2×, undefined a dashed outline in `labelMuted`; the name always in the centre.
- `nsValuePill` (0.92 cells tall, solid / outline / dashed): a single-bit pin draws its own `0`/`1`/`?`; every multi-bit component's chip is drawn by `drawBusValue` through the `busValue` hook with the canvas's `text` (the reader's base setting), seated above a pin's circle or a box's edge; `rom`/`ram` get none.
- `drawHighlight` as the `highlight` hook: `nsHoverRing` at `r + 0.38 cell` for pins, the rounded box for every other kind; no skin reads `hovered`; `circ-theme-hover.test.ts` rewritten to hold it.
- `drawLed`: lit a disc under a 1.3-cell halo with a `background` glint, unlit a hollow ring with an `outputOff` core, undefined dashed (the design's `nsGlow`, not the spec's `nsVecHalo`; the code won).
- Both islands pass `layoutOptions: { rowGutter: 2 }`; padding raised in the review from `1.5` to `2` cells; `site/test/island-canvas-options.test.ts` guards both.

### Phase 3 — Gates

Every gate authored from three containers, two tinted sprites, and the builtins drawn as the gates they are.

- `Assets.bounds(name)` (the page measures painted bounds with one 128×128 `getImageData` on the decoded image, rotated as drawn); `tintedSprite`, `haloSprite` (`HALO_PAD = 0.14`), `spriteBounds`, `nsVecHalo` with caches keyed on the sprite name, built from `assets.offscreen`, emptied by `makeSkins`; `spriteArt` exported as the cache test's seam.
- `nsGateLayout` (`NS_INSET = 0.4`, `NS_SLOT = 0.55`), `nsFitSymbol` (sized by the port spread and the gate slot, whichever binds; an unused slot lends its width, the symbol recentres and never resizes), `nsNegate` (`NS_BUBBLE_R = 0.24`, tangent to the measured tip, clamped inside its slot), `nsExclusive` (apex `0.14 cell + lw/2` left of the OR back's apex), `nsTriangle`, `nsVectorGate` (stand-ins before the PNGs decode); `gateGeometry` exported for the anatomy tests.
- `RECIPES` (and, nand, or, nor, xor, xnor, not) and `nsGate`; `drawAnd`/`drawNot` on it; `drawSubcircuit` draws any recipe name on a virtual 5-wide box centred in the macro box with `portsFrom` the real component. NOR and XNOR drew on the site for the first time.
- `circ-assets.mjs` reduced to `AND` and `OR` (19,940 → 7,594 bytes); theme chunk 31.7 KB / 18.3 KB → 23.6 KB / 11.5 KB gzip.

### Phase 4 — Bit parts, chips and memories

The last four kinds drawn as what they are, and two renderer defects the theme made visible.

- `nsShell`, `nsSliceAsset` (ruler to `RULER_MAX_BITS = 16`, MSB left, tapped bits in `wireBus`; a range bar above), `nsBitPart`; `nsConcatAsset` (bands and numbered lanes, alpha `max(0.45, 1 − 0.2 i)`).
- `nsChip` (macro shell, one-cell header at alpha 0.18), `nsChipPart`, `nsUserSubcircuit` (name in capitals, instance in the body).
- `nsHex` (bigint masks), `nsMemory`: `MODE` and `W×2^A` in the header, `addr → word` from `inputValues[0]` and `outputValue`, RAM port labels on their rows; the renderer's `memoryLabel` no longer imported.
- `ramWriting`: the engine's predicate (`clk` rising, `we` high, `addr` fully defined, first defined-high clock not an edge) over the port values, last `clk` kept per canvas and per component in a `WeakMap`; `the RAM write indicator lights on the engine's edge, and only then`.
- Review finding 1 → `circ-renderer` `0087d0c` (`2.3.0-alpha.2`): `junctionCells` marks a fan-out where the net leaves a cell in three or more directions, not on every cell of a shared trunk; exported.
- Review finding 2 → `circ-renderer` `7ca8593` (`2.3.0-alpha.3`): `resize()` scales the transform's translation by the device pixel ratio (`setTransform(dpr, 0, 0, dpr, pad * dpr, pad * dpr)`); on a 2x display the padding had drawn at half and the hit-test half a padding off since the renderer's first release; `test/padding-dpr.test.ts`.

### Phase 5 — Sweep and record

- The human walked `/`, `/gallery`, `/tour`, `/playground` in both themes and approved; the hover frame time was not taken.
- `DOCS/decisions/canvas-theme.md` closed with nineteen entries and a map of the sixteen locked decisions; the renderer README reread against `7ca8593`.
- `DOCS/design/` moved to `DOCS/archive/design/canvas-theme/`.

## API surface frozen by the plan

No diagnostic code, runtime export or CLI flag changed; the compiler is untouched. The surfaces this plan added or changed:

| Surface | Where | Contract |
| --- | --- | --- |
| `CircTheme.fanOutMarker` | `circ-renderer/src/utils/theme.ts` | Called once per junction cell with `{ ctx, theme, cell, x, y, value, signal }`; absent → the 0.18-cell dot. |
| `junctionCells(wires)` | `circ-renderer/src/render/canvas.ts` | Cells the union of a group's segments leaves in ≥ 3 directions, sorted `"x,y"`. |
| `traceWire(path, wire, cell, opts)`, `wirePath` | `circ-renderer/src/render/wire-path.ts` | `opts` a number (arc radius) or `TraceOptions { arcRadius?, cornerRadius? }`. |
| `LayoutOptions.rowGutter` | `circ-renderer/src/layout/types.ts` | Free rows between stacked boxes, default 1; the parity goldens are pinned at the default. |
| `ThemeColorKey` | `circ-renderer/src/utils/theme.ts` | `grid` removed. |
| Padding | `CircCanvas.resize()` | CSS pixels at any device pixel ratio. |
| `makeSkins(assets)`, `Assets { sprite, bounds, offscreen }` | `site/src/utils/circ-skins.mjs` | The page binds live sprites; a test binds `stubAssets(loaded)`. |
| `spriteArt`, `gateGeometry` | `site/src/utils/circ-skins.mjs` | Test seams: the cache producers and the fitted gate layout. |
| `PaletteKey` (27 keys) | `site/src/utils/circ-palette.mjs` | The 24 site keys minus `grid` plus `surface`, `spriteInk`, `wireBus`, `busLabel`. |
| Sprites | `site/src/utils/circ-assets.mjs` | `AND`, `OR`, `loadAssets` only. |
| Islands | `LiveCanvas.astro`, `Playground.astro` | `layoutOptions: { rowGutter: 2 }`, `padding = Math.ceil(cell * 2)`. |
| Renderer pin | `site/package.json`, `renderer-versions.ts` | `github:jeffersonmourak/circ-renderer#7ca8593`, `RENDERER_PIN_VERSION = '2.3.0-alpha.3'`. |

## Known papercuts carried forward

- **The runtime write stamp** (plan decision 11): the RAM `wr` dot mirrors the engine's edge rule over port values; a `we` that settles low in the same step the clock rises can differ. The exact signal is a `last_write_time` on `MemoryState`, one export beside `getMemInfo`, a `CircRuntime` accessor. Open only if the mirrored rule misleads.
- **The range bar** for a slice of a word wider than 16 bits is the plan's rule (`nsSliceAsset`'s bar branch), not the designer's; no shipped example exercises it.
- **The tint, halo and bounds caches never evict.** Sizes are cell-derived and colours palette values, so a page holds a bounded set; a host that changed cell sizes freely would grow `vecHaloCache`.
- **The hover frame time on `four-bit-adder`** was the one measurement Phase 5 asked for and did not get.
- **A pin bump can leave `node_modules/vite/node_modules/esbuild` without a working binary** (`astro check`/`astro build`: "The service was stopped"); `bun install --force` restores it with no lockfile change.
- **The renderer's `canvas-theme` branch** (`86469f0` … `7ca8593`) is on its remote and not merged into its `main`; the site pins the sha.
- **`renderer-pin.test.ts` still asserts the renderer exports `memoryLabel`**: that is the package's surface, not the site's use of it.

## Decisions & specs that survived the plan

- `DOCS/decisions/canvas-theme.md` — nineteen entries: the three renderer hooks; the theme split and the assets seam; op-log goldens; the handoff tracked; the design file over its README; the palettes; cell-relative strokes and palette-only colours; the wire hook; pins by shape; the value pill and who draws it; the hover ring; no new component kinds; two sprites tinted and measured; the gate anatomy; slice and concat; the shared chip; the write indicator; the junction rule; padding in CSS pixels — and the map of the plan's sixteen locked decisions onto them.
- `DOCS/decisions/index.md` — the `canvas-theme.md` topic.
- `DOCS/archive/design/canvas-theme/` — the handoff: `README.md` (what to port), `circ-site-theme.js` (the port target), the two `.dc.html` sheets, the harness files.
- `circ-renderer/README.md` — the theme colour table, "Drawing a wire yourself" (`TraceOptions`), "Fan-out junctions", the `layoutOptions` row.
- `site/test/circ-skins.test.ts`, `site/test/circ-theme-hover.test.ts`, `site/test/island-canvas-options.test.ts`, `site/test/renderer-pin.test.ts` — the guards that hold the decisions above.
