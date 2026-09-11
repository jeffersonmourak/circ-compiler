# Phase 1 — Palette, wires and marks

> **Dependencies:** Phase 0 (the split, the op-log harness, the pinned renderer with `fanOutMarker` and `TraceOptions`).
> **Warnings:** Decision 1 of the plan prompt: `DOCS/design/circ-site-theme.js` wins over its README. Values taken here are the file's: wire width `nsWire = max(2, cell × 0.2)` (`:469`), corner radius `cell × 0.6` (`:1476`), bus `1.5×`, terminal dot `cell × 0.24` (`:619-625`). Every golden this phase regenerates is named in STATUS.

## Goal

Every wire, tail and terminal dot on the site is drawn in the new palettes at a weight that scales with `cell`, with rounded corners, a crossing hop that keeps those corners, a bus in `wireBus` at `1.5×` weight with the bit-count slash, an active single-bit wire under a soft glow, and a fan-out junction that reads as a ring with the pane showing through its centre. Idle wires in dark mode are quieter than active ones. The gates, pins and boxes still draw with today's shapes; only what they share (tails, dots, colours) has changed.

## Scope

**In scope:**
- `circ-palette.mjs`: `colorsDark`/`colorsLight` replaced by `nextSiteDark`/`nextSiteLight` verbatim (`circ-site-theme.js:395-455`), `grid` deleted, `PaletteKey` follows.
- `circ-skins.mjs`: `nsFont`, `nsWire`, `nsHex` (over `bigint`, see Data & State), `nsTail`, `nsDot`, `nsName` (with `yOffset` removed: every caller passes none), replacing `drawTailLine`, `drawTailDot`, `drawNameBelow` in every existing skin; the NOT label bug closes here as a consequence.
- The `wire` hook rewritten on `traceWire(ctx, wire, cell, { arcRadius: cell*0.4, cornerRadius: cell*0.6 })`, colour by `wireStyleOf(value)`, width `nsWire(cell) × (bus ? 1.5 : 1)`, `nsGlow` under an active single-bit wire, `nsBusTick` on a bus.
- The `fanOutMarker` hook: `0.3 cell` disc in the wire colour, `0.13 cell` knock-out with `destination-out`, inside `save`/`restore`.
- `busValue` hook: **unchanged this phase** (still the renderer's default badge, now in the new `busLabel`); Phase 2 takes it over.
- Goldens for every kind regenerated (tails and dots changed under all of them).

**Explicitly deferred:**
- Pin, LED, gate, slice, concat, subcircuit and memory shapes (Phases 2–4).
- Padding and `rowGutter` on the islands (Phase 2).

## File & Module Topology

**New files:** None.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/utils/circ-palette.mjs` | The two 28-key palettes; `grid` gone. |
| site | `site/src/utils/circ-skins.mjs` | Shared helpers added; every skin's tail/dot/name calls swapped; `wireRenderer` → `drawWire`; `fanOutMarker` added to the returned theme pieces. |
| site | `site/src/utils/circ-theme.mjs` | Wires `fanOutMarker` into `sharedRenderers`. |
| site | `site/test/circ-skins.test.ts` | New cases for the wire hook (three wire shapes) and the fan-out hook; `no literal lineWidth` source guard; palette guard (every `strokeStyle`/`fillStyle` value in an op log is a palette value or `'transparent'`). |
| site | `site/test/fixtures/skins/*.json` | Regenerated. |
| site | `site/test/circ-theme-hover.test.ts` | `inputHover:` count still 2 (both palettes) — unchanged. |
| site | `DOCS/decisions/canvas-theme.md` | Decisions 1 and 2 recorded with the two README/file disagreements and the values taken. |

**New dependencies:** None.

## Data & State

Palette keys (both modes define every key):

```
background surface grid⁻ stroke fillIdle fillActive fillUndefined
wireIdle wireActive wireUndefined wireBus busLabel
label labelMuted labelOnComponent macro
inputOn inputOff inputBorderOn inputBorderOff inputHover
outputOn outputOff outputBorderOn outputBorderOff
portOn portOff spriteInk
```

`nsHex` is not ported as written: the harness's values are JS numbers masked to 32 bits (`circ-site-theme.js:458-463`), the renderer's `BitValue` has `bigint` `value`/`defined` and widths to 64. The site helper is:

```js
/** Hex for a fully defined bus, '?' otherwise. Masks are bigint (renderer's BitValue). */
export function nsHex(v) {
  if (!v) return '?';
  const mask = widthMask(v.width);                 // from 'circ-renderer'
  if ((v.defined & mask) !== mask) return '?';
  return '0x' + (v.value & mask).toString(16).toUpperCase().padStart(Math.ceil(v.width / 4), '0');
}
```

It is used only where the canvas gives no `text` (Phase 4's memory body); pills take the canvas's `text`.

Wire hook context (renderer, unchanged): `{ ctx, theme, cell, wire, signal, value, conflictTier }`. `nsBusTick` picks the first horizontal segment of length ≥ 2 cells (`circ-site-theme.js:1510-1530`) and draws the slash and `String(value.width)` in `wireBus`.

## Execution & Concurrency Model

Fully synchronous. No caches are introduced this phase (`nsGlow` is a second stroke pass, not an offscreen render).

## Persistence & I/O

Op-log goldens only.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The new palettes | `circ-palette.mjs` swapped to `nextSiteDark`/`nextSiteLight`; `PaletteKey` updated. | Palette test: both objects have the same 28 keys, none named `grid`; typecheck green (islands compile against the new `PaletteKey`). |
| 2 | Shared helpers and tails | `nsFont`, `nsWire`, `nsTail`, `nsDot`, `nsName`; every skin's tails, dots and names on them. | Goldens regenerated; the `no literal lineWidth` guard passes; the NOT golden shows the name `fillText` at `y0 + h + cell*0.16` (below the box). |
| 3 | The wire hook | `drawWire` on `traceWire` with corners, bus width and colour, glow, `nsBusTick`. | Wire cases: straight (no `arcTo`), corner (one `arcTo`), crossing plus corner (one `arc`, one `arcTo`, single `moveTo`); bus at width 8 strokes in `wireBus` at `1.5 × nsWire(cell)` and draws the tick; active width-1 strokes twice (glow then colour). |
| 4 | The fan-out ring | `fanOutMarker` hook wired. | Fan-out case: `arc(…, cell*0.3)` fill in the wire colour, then `globalCompositeOperation = 'destination-out'`, `arc(…, cell*0.13)`, then `restore`; the op log ends with the composite mode restored. |
| 5 | Gallery review | The human reviews `slice-and-concat`, `four-bit-adder`, `sr-latch`, `fan-out` in both modes at `cell` 10, 14, 24. | STATUS records the review and any value the human changed. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `both palettes define the same keys and none is grid` | `circ-skins.test.ts` (palette section) | Key sets equal; `grid` absent; every value is a string. |
| `no skin sets a literal lineWidth` | `circ-skins.test.ts` (source guard) | `circ-skins.mjs` has no match for `/lineWidth\s*=\s*\d/`. |
| `every op-log colour comes from the palette` | `circ-skins.test.ts` | Each `["set","fillStyle"|"strokeStyle", v]` has `v` in the palette values. |
| `the wire hook keeps corners with a crossing` | `circ-skins.test.ts` (wire section) | Op counts as in slice 3. |
| `a bus is 1.5× and ticked` | same | `lineWidth` equals `1.5 × max(2, cell*0.2)`; a `fillText` with `"8"`. |
| `fan-out draws a ring and restores the composite mode` | same | Sequence as in slice 4. |
| `every skin's op log matches its golden` | `circ-skins.test.ts` | Regenerated this phase. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `bun --bun run typecheck` | site | `CircView<PaletteKey>` compiles with the new key set in both islands. |
| `bun run bundle` | site | No route over budget. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- `TODO(phase1)`: `nsGlow` (`circ-site-theme.js:567-586`) monkey-patches `ctx.fill`/`ctx.stroke` during the callback. Port it as two explicit strokes of the traced path instead (trace once into a `Path2D` via `wirePath` in the browser, into the context on the recorder), so the op log is honest and nothing patches the context.
- `TODO(phase1)`: `traceWire`'s hop arc is drawn *above* the line (`arc(…, π, 0, false)`); `drawWireNextSite` flips the sweep for a right-to-left run (`dir < 0`). Slice 3 verifies the Phase 0 renderer branch already does this (it should — the plan copied the loop) and adds the right-to-left case to the site test if the renderer test lacks it.
