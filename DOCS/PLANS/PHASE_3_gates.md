# Phase 3 — Gates

> **Dependencies:** Phase 2 (pill and ring policies settled; `assets.offscreen` in place).
> **Warnings:** Decisions 4, 5 and 6. Values from the file, not the README (decision 1): `HALO_PAD = 0.14` (`circ-site-theme.js:499`; README says 0.18), `NS_INSET = 0.4`, `NS_SLOT = 0.55`, `NS_BUBBLE_R = 0.24` (`:1177-1179`). The site always lays out in opaque mode (`LiveCanvas.astro` passes no `layoutOptions`; the playground's "Expand macros" setting reaches the compiler's preview, not the canvas), so every builtin gate arrives as a `subcircuit` node.

## Goal

Every gate on the site is authored from three containers inside its box — `[exclusive][gate][negate]` — so AND, NAND, OR, NOR, XOR, XNOR and NOT share one symbol size and one x position, the negate bubble is tangent to the measured tip of the art, and the exclusive curve nests in the OR's measured back. The two surviving sprites are tinted to the palette's ink at LOW, warmed to orange with a silhouette-shaped halo at HIGH, and dimmed at undefined; light mode no longer shows dark art. Builtin macros read as the gate they wrap, with the instance name below. The NAND, XOR and NOT PNGs are gone from the site.

## Scope

**In scope:**
- `Assets` extended: `bounds(name)`, `tinted(name, color, alpha)`, `halo(name, color)`; browser implementations in `circ-theme.mjs` (`tintedSprite`, `haloSprite`, `spriteBounds` ported from `:473-531`, `:1237-1262`); stub implementations in `canvas-record.ts` returning fixed bounds `{ l: 0.2, r: 0.84, t: 0.2, b: 0.8, apex: 0.2 }` and tagged stub images.
- `nsGateLayout`, `nsFitSymbol`, `nsNegate`, `nsExclusive`, `nsTriangle`, `nsSpriteRect`, `nsGate` (`:1181-1435`); `nsAnatomy` is **not** ported (debug overlay, harness only).
- `and_gate` and `not_gate` skins on the recipe; the `subcircuit` skin's builtin branch with the recipe table and `portsFrom`; qualifiers `&`, `≥1`, `=1` at their `qx/qy`.
- `spriteForSubcircuit`, `drawSprite`, `spriteRect` (the old sprite path) deleted; `circ-assets.mjs` reduced to `AND` and `OR`.
- Goldens for `and_gate`, `not_gate`, `subcircuit` regenerated.

**Explicitly deferred:**
- `nsUserSubcircuit` (Phase 4) — this phase keeps today's labelled box for non-builtin subcircuits.
- `buffer` and any new `ComponentKind` (deferred for good, decision 4).
- `spriteRightExtent` (`:1264-1286`): unused by `nsGate` in the file; not ported unless slice 2 finds a caller.

## File & Module Topology

**New files:** None.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/utils/circ-assets.mjs` | `NAND`, `XOR`, `NOT` exports and their entries in `assetsList` removed. |
| site | `site/src/utils/circ-theme.mjs` | Browser `Assets`: `bounds`/`tinted`/`halo` with their caches (`tintCache: WeakMap<img, Map<string, canvas>>`, `haloCache` likewise, `boundsCache: Map<name, Bounds>`), keyed on the sprite **name** the site passes, never on `img.src`. |
| site | `site/src/utils/circ-skins.mjs` | Gate anatomy functions; `RECIPES` table; `drawAnd`, `drawNot`, `drawSubcircuit` rewritten; old sprite helpers removed. |
| site | `site/test/canvas-record.ts` | Stub `bounds`/`tinted`/`halo`. |
| site | `site/test/circ-skins.test.ts` | Recipe and anatomy cases; goldens regenerated for the three kinds. |
| site | `site/test/circ-theme-hover.test.ts` | Registered skin list unchanged (`drawAnd`, `drawNot`, `drawSubcircuit` keep their names). |
| site | `DOCS/decisions/canvas-theme.md` | Decisions 4, 5, 6. |

**New dependencies:** None.

## Data & State

```js
/** Recipe per gate; keys are the lowercase subcircuit names collapse.ts reports. */
const RECIPES = {
  and:  { sprite: 'AND', qualifier: '&' },
  nand: { sprite: 'AND', negate: true, qualifier: '&' },
  or:   { sprite: 'OR',  qualifier: '≥1', qx: 0.44, qy: 0.18 },
  nor:  { sprite: 'OR',  negate: true, qualifier: '≥1', qx: 0.44, qy: 0.18 },
  xor:  { sprite: 'OR',  exclusive: true, qualifier: '=1', qx: 0.44, qy: 0.18 },
  xnor: { sprite: 'OR',  exclusive: true, negate: true, qualifier: '=1', qx: 0.44, qy: 0.18 },
  not:  { vector: 'triangle', negate: true },
};
// and_gate primitive → RECIPES.and; not_gate primitive → RECIPES.not.

/** @typedef {{ l:number, r:number, t:number, b:number, apex:number }} Bounds  // fractions of the sprite square, rotated as drawn */
/** Assets, extended: */
//   bounds(name): Bounds
//   tinted(name, color, alpha): CanvasImageSource
//   halo(name, color): CanvasImageSource     // padded by HALO_PAD on every side
```

Gate layout (`nsGateLayout`): `innerL = x0 + 0.4 cell`, `innerR = x0 + w − 0.4 cell`, slots `0.55 cell` at each inner edge, the gate container between them; `rect` centred on the span `[spanL, spanR]` where an unused slot lends its width (`nsGate`, `:1387-1388`). Symbol size: `min(targetH / paintedH, gateW / paintedW)` with `targetH = min(boxH, (2(n−1) + 2) cell)` for `n` inputs. Bubble x: `min(slot.right − r, max(slot.left + r, artR + 0.14 cell + r))`. Exclusive tip: `apexX − 0.14 cell − lw/2`.

Builtin macro: `virt = { ...c, x: c.x + (c.width − 5) / 2, width: 5 }`, drawn through `nsGate(virt, …, { ...recipe, portsFrom: c })` so tails run from the real ports to the virtual box's inner edges.

Signal ink: HIGH `inputOn` at alpha `0.92` plus halo at `0.55`; LOW `spriteInk` at `0.94`; undefined `labelMuted` at `0.5`.

## Execution & Concurrency Model

Fully synchronous. The three caches are filled on first use and never evicted; the `WeakMap`s keyed on the decoded image release with it. The bounds pass runs once per sprite name on the decoded image, before any tint (trap in the plan prompt).

## Persistence & I/O

`spriteBounds` reads pixels through `getImageData` on a 128×128 offscreen canvas (`:1240-1248`); the data-URI images are same-origin so this does not taint. No other I/O.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Sprite assets: tint, halo, bounds | Browser `Assets` methods and caches; stub counterparts. | Cache test through the stub: two `tinted('AND', ink, 0.94)` calls yield one `offscreen`; `bounds('AND')` computed once; keys never contain `data:`. |
| 2 | Gate anatomy | `nsGateLayout`, `nsFitSymbol`, `nsNegate`, `nsExclusive`, `nsTriangle`. | Geometry test with the stub bounds at `cell 14` on a `5×5` box: `rect.size` equals `min(4 cell / 0.6, gateW / 0.64)`; bubble x is tangent (`artR + 0.14 cell + r`) and inside its slot; exclusive `xTip < artL`. |
| 3 | Primitives on the recipe | `drawAnd`, `drawNot`; old sprite path removed; NOT label below the box. | Goldens: AND HIGH log contains `drawImage` twice (halo, art) after two tails; NOT shows the triangle `moveTo/lineTo ×2/closePath` and one bubble `arc`; name `fillText` at `y0 + h + 0.16 cell`. |
| 4 | Builtins through the recipe | `drawSubcircuit` builtin branch with `portsFrom`; user subcircuits keep today's box. | For each of the seven names on a `macroSize` box the log's tails start at the real port x and end at `vx + 0.4 cell − 0.4 cell`; symbol `rect.cx` equals the box centre; an unknown name falls to the box path. |
| 5 | Delete the three sprites, measure, review | `circ-assets.mjs` trimmed; bundle numbers; gallery review. | `bun run bundle` theme-chunk bytes before/after in STATUS; source guard: `circ-assets.mjs` exports exactly `AND`, `OR`, `loadAssets`; the human reviews `builtin-xor`, `full-adder`, `mux-2to1`, `inverter-chain` at `cell` 10 and 24, both modes. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `tint, halo and bounds are cached per name and colour` | `circ-skins.test.ts` | Offscreen-call counts as in slice 1. |
| `the symbol is the same size across a negated pair` | same | `rect.size` equal for `and`/`nand`, `or`/`nor`, `xor`/`xnor`. |
| `the bubble is tangent to the measured tip` | same | Bubble centre x = `artR + 0.14 cell + r`, clamped inside the negate slot. |
| `the exclusive curve stays left of the art` | same | `xTip + depth < artL`. |
| `a builtin macro draws through the recipe on a virtual box` | same | Tail endpoints and symbol centre as in slice 4. |
| `only AND and OR remain` | same (source guard) | Export list of `circ-assets.mjs`. |
| `every skin's op log matches its golden` | same | Regenerated for `and_gate`, `not_gate`, `subcircuit`. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `bun run bundle` | site | Theme chunk smaller than the Phase 0 baseline; no route over budget. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- `TODO(phase3)`: the site's `subcircuit` boxes for builtins carry `inPorts` named `a`, `b` (two-input) or `in` (`not`) after `collapse.ts`'s `remappedPort`; confirm at slice 4 that `not`'s single port is `in` at `y+1` on a 3-row macro box so the virtual box's `cy` matches the port row.
- `TODO(phase3)`: `nsSpriteRect` rotates by `π/2` because the PNGs point up (`circ-theme.mjs:222-232` today). `spriteBounds` measures in the rotated frame (`:1244-1246`). Keep both; a test asserts the rotation precedes the `drawImage` in the log.
