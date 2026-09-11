# Handoff: circ-renderer — site theme v2 assets

## Overview

An upgraded visual asset set for the circ-renderer canvas as themed by the circ-lang.org site
(`circ-compiler/site/src/utils/circ-theme.mjs`). It keeps the site's language — orange is HIGH,
green is LOW, blue is output, purple is macro — and fixes ten documented gaps in the shipped theme,
then extends the set to the full ANSI gate family, bit-field slice/concat, two-faced subcircuits,
and the ROM/RAM parts from circ-compiler PR #79.

## About the design files

Everything in this bundle is a **design reference written in HTML + Canvas 2D**. The interactive
sheet (`Circ Renderer Assets - Site Theme.dc.html`) is a preview harness; do **not** ship it.

The thing to port is `circ-site-theme.js`. It is already Canvas 2D — the same API the renderer
uses — so most of it transfers to `circ-theme.mjs` (site) or `skins.ts` (library) with signature
changes only. The harness-specific bits are called out under **What is harness-only** below.

## Fidelity

**High-fidelity.** Colors, geometry, stroke weights and text are final. Everything is expressed in
`cell` units so it scales; `cell = 14` is the site's default, `cell = 16` is what the sheet shows.

## Source of truth

| What | File | Notes |
|---|---|---|
| Upgraded skins + palettes | `circ-site-theme.js` | Sections marked `/* ── proposed … */`. Export `nextSiteSkins`, `nextSiteDark`, `nextSiteLight`. |
| Verbatim port of today's theme | `circ-site-theme.js` (top half) | `siteSkins`, `siteDark`, `siteLight`, `drawWireSite` — 1:1 with `circ-theme.mjs`; useful as a diff base. |
| Library-level marks | `circ-skins.js` | `drawWireNextSite`, `fanOutDots` (`style === "site-next"` branch), `portMarkersNext`, `busBadges`. |
| Layout fixtures | `circ-scenes.js` | Footprints and port slots reproduced from `layout/sizing.ts` + PR #79 `memorySize`. Reference only — the renderer already has these. |
| Sprites | `site/src/utils/circ-assets.mjs` | Unchanged from the site. Only `AND`, `OR` are still needed (see below). |

## Palettes (proposed)

Both palettes keep the 24 site keys and add three. Full values are in `nextSiteDark` / `nextSiteLight`.

New keys:

- `surface` — fill behind chips, pin cores, knock-outs. Dark `#160b26`, light `#ffffff`.
- `spriteInk` — the gate silhouette color at LOW/undefined. Dark `#e8ddff`, light `#8672b5`.
- `wireBus` / `busLabel` — added (site theme lacked them; the library fell back to `#1971c2`).

Changed semantics:

- `labelOnComponent` is dark ink in dark mode (was white) because the pin fill is now the theme's
  bright HIGH color and the pill sits on `surface`.
- `wireIdle` in dark mode is dimmed so active wires out-shout idle ones (was `#dee2e6` — the
  brightest thing on the pane).
- `grid` is dead: defined in both palettes, never read by `canvas.ts`. Delete it.

## Geometry constants

All in `circ-site-theme.js`, all in cells:

```
NS_INSET     0.4    box edge → first container / chip edge
NS_SLOT      0.55   exclusive and negate container width
NS_BUBBLE_R  0.24   negate bubble radius
tail gap     0.4    container edge → terminal dot centre
terminal dot 0.22   radius (nsDot)
wire         max(2, cell × 0.16)  lineWidth, cell-relative (was fixed 4px)
corner       cell × 0.4           rounded-corner radius (drawWireNextSite)
crossing arc cell × 0.4           unchanged from the site
fan-out ring 0.3 outer / 0.13 knock-out (destination-out, not background fill)
```

The layout rule for every part: `port [0.4 gap] [inset] [containers] [inset] [0.4 gap] port`.
Ports, box sizes and footprints are **unchanged** from `layout/sizing.ts`.

## Parts

### Input / output pin
- Circle inscribed in the box, radius `min(w,h)/2 − 0.08 cell`.
- HIGH: solid disc in `inputOn` / `outputOn`. LOW: hollow ring, stroke `lw × 1.2`. Undefined: dashed.
- **Name in the centre**, in `labelOnComponent` (HIGH) or `label` (LOW).
- **Value pill above**: `nsValuePill` — height `0.92 cell`, seated at `cy − r − 0.5 cell`
  (clear of the hover ring). Single-bit shows `0/1/?`; bus shows `0xNN` in `busLabel` on `wireBus`.
- Hover (input only): ring at `r + 0.32 cell`, stroke `inputHover`, drawn **last**.
- Requires `ROW_GUTTER = 2` (pill needs two rows of clearance above the box).

### LED
- Radius `min(w,h) × cell × 0.4`, stroke `max(2, cell × 0.28)`.
- HIGH: fill `outputOn` + halo (`nsVecHalo`, blur `cell × 0.9`, alpha 0.55) — replaces the 0.4-alpha ring.

### Gates — three-container recipe
Every gate is authored as `[exclusive?][gate][negate?]` inside the inset box (`nsGateLayout`):

| Gate | Recipe |
|---|---|
| BUFFER | `{ vector: 'triangle' }` |
| NOT | `{ vector: 'triangle', negate: true }` |
| AND | `{ sprite: 'AND', qualifier: '&' }` |
| NAND | `{ sprite: 'AND', negate: true, qualifier: '&' }` |
| OR | `{ sprite: 'OR', qualifier: '≥1', qx: .44, qy: .18 }` |
| NOR | `{ sprite: 'OR', negate: true, … }` |
| XOR | `{ sprite: 'OR', exclusive: true, qualifier: '=1', … }` |
| XNOR | `{ sprite: 'OR', exclusive: true, negate: true, … }` |

Rules that make the containers consistent:
- **Symbol sized by painted bounds, not the PNG square.** `spriteBounds()` scans the sprite alpha
  once (cached) so the art spans exactly the port rows (a at y+1, b at y+3 → 4-cell painted height).
  The PNGs carry ~28% transparent padding; sizing by the square misaligns the lobes.
- **Unused slots lend their width** to the symbol; used ones keep it (`availW` in `nsGate`).
- **Negate bubble** is tangent to the *measured* output tip (`rect.artR + 0.14 cell`), clamped to its slot.
- **Exclusive curve** is a stroked arc nested in the OR's *measured* concave back (`bounds.apex`),
  same depth, apex `gapToGate + lw/2` left of the back apex.
- **Sprites only for AND and OR.** NOT, NAND, XOR PNGs are no longer used — delete them from
  `circ-assets.mjs` once this lands.
- Sprites are **tinted**, not drawn raw: `tintSprite(img, color)` recolors to `spriteInk`
  (LOW/undef) or `inputOn` (HIGH), cached per (sprite, color). Light mode no longer shows dark art.
- HIGH halo: `haloSprite()` — a blurred copy of the tinted sprite drawn under it at alpha 0.55,
  padded `HALO_PAD = 0.18`. Silhouette-shaped, so the gate outline survives.
- Qualifier text (`&`, `≥1`, `=1`) in `labelOnComponent`, positioned by `qx/qy` fractions of the symbol square.

New kinds needed in the library: `buffer`, `or_gate`, `nand_gate`, `nor_gate`, `xor_gate`,
`xnor_gate` — kind byte in `format.zig`, `ComponentKind` entry, footprint (`5×5` like AND, BUFFER
`5×3` like NOT), port slots (`a` at y+1, `b` at y+3, out y+2).

### Slice
`nsSliceAsset` — shell (`nsShell`, `wireBus` stroke, `surface` fill, radius `0.16 cell`) holding a
**ruler** of the incoming word, MSB left. Tapped bits filled `wireBus`; discarded bits `labelMuted`
at alpha 0.38. Label `[lo:hi]` (or `[n]` for one bit) under the ruler. Reads input width from
`inputValues[0].width`. Above ~16 bits the ruler should collapse to a range bar — not designed yet.

### Concat
`nsConcatAsset` — one band per operand stacked on the output side (`barW 0.5 cell`), a numbered lane
from each port to its band (`arcTo`, radius `0.3 cell`), alpha fading `1 → 0.45` down the stack.
Index glyph on the lane baseline at `bx + 0.42 cell`.

### Subcircuit — two faces
- **Builtin macros** (and/nand/or/nor/xor/xnor/not) reuse the gate recipe via a virtual 5-wide box
  centred in the macro box (`portsFrom` in `nsGate`); tails run to the real ports.
- **User subcircuits** (`nsUserSubcircuit`): chip with `macro` stroke, `surface` fill, radius
  `0.18 cell`; header band `1 cell` tall filled `macro` at alpha 0.18 with a 0.5-alpha rule;
  subcircuit name UPPERCASE in `macro` (700); instance name in body in `label` (500).

### ROM / RAM (PR #79)
`nsMemory` — user-subcircuit chip. Header: mode left (700), `W×2^A` right (500).
Body: `addr → word`, addr in `label`, arrow in `labelMuted`, word in `wireBus`; `?` when undefined.
RAM labels `addr din we clk` inside the left edge on their port rows and adds a `wr ●` indicator
bottom-right (`r 0.2 cell`) that fills `inputOn` + halo on the `we·clk` edge.
Footprints from the PR's `memorySize`: ROM `max(5, label+4) × 3`, RAM `× 9`, out at the middle row.
**Runtime ask:** the write flash needs one bit from WASM — "last step committed a write".
Suppress the library bus badge on memories (word is already in the body).

### Wires & marks (`circ-skins.js`, `site-next` branches)
- `drawWireNextSite`: cell-relative width, rounded corners **including on segments with crossings**
  (the earlier fallback to hard corners is fixed), tri-state + bus color via `wireStyleOf`.
- Fan-out: ring `0.3` outer, knocked out at `0.13` with `globalCompositeOperation = 'destination-out'`
  (the canvas is transparent — never fill with `background`).
- Terminal dots via each skin's `nsDot`; `portMarker` stays a no-op.

## What is harness-only (do not port)

- `circ-scenes.js` entirely (layout fixtures).
- The `.dc.html` sheet and its logic class.
- `?v=N` cache-busting in imports.
- `renderScene()` in `circ-skins.js` — a stand-in for `canvas.ts`'s `draw()`.

## Interaction & state

- Hover: only `input_pin` responds (site convention, kept).
- Theme: light/dark via the two palette objects; the site flips them on `data-theme`.
- Every draw is stateless except the three caches (`tintCache`, `haloCache`, `boundsCache`) keyed by
  sprite id — key on a stable id, not `img.src.slice(-20)`.

## Performance notes

- `shadowBlur` is no longer used per-frame; halos are pre-rendered offscreen once per (sprite, color).
- `spriteBounds` does one 128×128 `getImageData` per sprite, once.

## Files in this bundle

- `Circ Renderer Assets - Site Theme.dc.html` — interactive sheet (open in a browser; needs `support.js` next to it).
- `Circ Renderer Assets.dc.html` — the library default-theme sheet (context only).
- `circ-site-theme.js` — **the port target**.
- `circ-skins.js`, `circ-scenes.js`, `support.js` — harness.
- `site/src/utils/circ-assets.mjs` — sprites, copied from the site.
- `github.md` — source map back to the repos.
