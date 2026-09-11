# STATUS — Canvas theme

One entry per shipped slice, newest last. The plan is `DOCS/PLANS_PROMPT.md`; the phase specs are under `DOCS/PLANS/`. Renderer slices land in `~/circus/circ-renderer` on branch `canvas-theme`; site slices land here.

## 2026-09-10 — Phase 0 — renderer: fan-out marker hook

**What shipped:** `CircTheme.fanOutMarker` with `FanOutMarkerContext { ctx, theme, cell, x, y, value, signal }`, called from `drawFanOutMarkers` once per junction cell in place of the default dot; the README's new "Fan-out junctions" section. Renderer commit `86469f0`.
**Files touched:** `circ-renderer/src/utils/theme.ts`, `src/render/canvas.ts`, `src/index.ts`, `README.md`, `test/fan-out-marker.test.ts`
**Tests:** added `the hook fires once per junction cell with the group's value`, `the default dot is drawn only without the hook`; ran `bun test` (192 pass) and `bunx tsc --noEmit`, result pass
**Next slice:** renderer: rounded corners in `traceWire`.
**Notes:** the test wraps the stub document's `createElement` so the canvas's context records `arc` calls. A trunk that splits at its own out port makes that port cell a junction, and the default source marker is a circle of the same radius there, so the "no dot with the hook" assertion excludes port cells.

## 2026-09-10 — Phase 0 — renderer: rounded corners in `traceWire`

**What shipped:** `TraceOptions { arcRadius?, cornerRadius? }` accepted by `traceWire` and `wirePath` beside the bare radius; with a `cornerRadius` the wire is one continuous subpath, corners through `arcTo` clamped to half the shorter adjacent run, hops spliced in travel order and always above the line; the positional call traces byte for byte as before. README example updated. Renderer commit `a46bdb1`.
**Files touched:** `circ-renderer/src/render/wire-path.ts`, `src/index.ts`, `README.md`, `test/wire-path.test.ts`
**Tests:** added six cases (options-object equivalence, continuous subpath with spliced hop, right-to-left rounded run, clamp on a one-cell jog, hop on a corner cell left to the corner, every wire of `rom_lookup` rounded as one subpath); ran `bun test` (198 pass) and `bunx tsc --noEmit`, result pass
**Next slice:** renderer: `rowGutter`, drop `grid`, bump.
**Notes:** a hop on a corner cell is skipped in the rounded branch (strictly inside the run only), so the corner's own arc wins; the design file's `drawWireNextSite` had the same rule.

## 2026-09-10 — Phase 0 — renderer: row gutter option, no grid colour, version bump

**What shipped:** `LayoutOptions.rowGutter` (default `ROW_GUTTER = 1`) threaded from `buildLayout` into `coords.assign` at both sites that read the gutter; `grid` removed from `ThemeColorKey`, `defaultColors` and the README table; README's `layoutOptions` row updated; version `2.3.0-alpha.1`. Renderer commit `f882353`. **Hard stop: the human pushes `canvas-theme` in `circ-renderer` before slice 6.**
**Files touched:** `circ-renderer/src/layout/coords.ts`, `src/layout/index.ts`, `src/layout/types.ts`, `src/utils/theme.ts`, `README.md`, `package.json`, `test/coords-channels.test.ts`, `test/layout.test.ts`
**Tests:** added `coords: the row gutter is the caller's, and stacked boxes keep it` (gutters 1, 2, 3 and the default) and `layoutOptions.rowGutter spaces stacked boxes, and the default is one row` (on `half_adder.wasm`); ran `bun test` (200 pass, parity and invariants unchanged) and `bunx tsc --noEmit`, result pass
**Next slice:** site: track the handoff.
**Notes:** removing `grid` is a type-level break for a host that spread `defaultColors` and set `grid`, which the README's own dark example did; the example no longer does. The bump to a new minor marks it.

## 2026-09-10 — Phase 0 — site: track the handoff and the plan

**What shipped:** `DOCS/design/` committed per decision 16 (eight files; no `.DS_Store`, no `site/` sprite copy), and the plan bundle (`DOCS/PLANS_PROMPT.md`, `DOCS/PLANS/PHASE_0…5`). Commits `df09577`, `3d0b9cc`.
**Files touched:** `DOCS/design/*`, `DOCS/PLANS_PROMPT.md`, `DOCS/PLANS/*.md`
**Tests:** none (documents); `git status` showed only the listed paths staged
**Next slice:** site: theme split and op-log goldens.
**Notes:** `DOCS/design/site/src/utils/circ-assets.mjs` stays untracked on disk; it is byte-identical to `site/src/utils/circ-assets.mjs` (checked with `diff`).

## 2026-09-10 — Phase 0 — site: theme split and op-log goldens

**What shipped:** `circ-theme.mjs` split into `circ-palette.mjs` (palettes, `PaletteKey`, `pickPalette`), `circ-skins.mjs` (every drawing function; `makeSkins(assets)` binds an `Assets { sprite, offscreen }` and returns the theme pieces) and the `circ-theme.mjs` entry (sprite loading, the page's `Assets`, `blogTheme`/`blogThemeLight`/`pickTheme`); `site/test/canvas-record.ts` (recording context, stub assets) and `site/test/circ-skins.test.ts` with goldens under `site/test/fixtures/skins/` (thirteen files: eleven kinds, `wire`, `highlight`; 396 skin logs, 54 wire logs, 33 highlight logs); `circ-theme-hover.test.ts` and `renderer-pin.test.ts` read the new files.
**Files touched:** `site/src/utils/circ-palette.mjs`, `site/src/utils/circ-skins.mjs`, `site/src/utils/circ-theme.mjs`, `site/test/canvas-record.ts`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/*.json`, `site/test/circ-theme-hover.test.ts`, `site/test/renderer-pin.test.ts`, `DOCS/decisions/canvas-theme.md`, `DOCS/decisions/index.md`, `DOCS/STATUS.md`
**Tests:** added `circ-skins.test.ts` (fourteen tests); ran `bun test` (417 pass, 11 skip), `bun --bun run typecheck` (0 errors), `bun --bun run build`, `bun run bundle` (every route ok; the lazy theme chunk `circ-theme.*.js` measures 28.4 KB raw / 17.2 KB gzip — the Phase 3 baseline), result pass
**Next slice:** site: pin bump to the pushed renderer sha, `RENDERER_PIN_VERSION`, `renderer-pin.test.ts` additions.
**Notes:** the one-off diff of every moved definition against `git show HEAD:site/src/utils/circ-theme.mjs` (whitespace folded) showed exactly the planned edits and nothing else: `sprites?.AND`/`sprites.AND` → `sprite('AND')` in `drawAnd`, the same for `NOT` in `drawNot`, and `spriteForSubcircuit` reading `sprite(name)` with its `if (!sprites) return undefined` guard gone (`sprite()` returns null before load, which the callers already treat as "no sprite"). Deviation from the Phase 0 spec, argued here: goldens are one file per kind keyed by combination (`sprites.sig1.w8.c14`) rather than one file per combination — 13 files instead of 483. The `pickPalette` export is unused until Phase 1 and exists so the palette module has an entry a test can call without `document`; it is not called by the islands.

## 2026-09-10 — Phase 0 — site: pin the renderer at the Phase 0 sha

**What shipped:** `circ-renderer` pinned at `github:jeffersonmourak/circ-renderer#f882353` (`2.3.0-alpha.1`) in `package.json` and `bun.lock`; `RENDERER_PIN_VERSION` bumped; `renderer-pin.test.ts` asserts the three Phase 0 additions through the installed package (`traceWire` with `{ cornerRadius }` rounds a corner, `LayoutOptions.rowGutter` and `CircTheme.fanOutMarker` type-check, `grid` is gone from `defaultColors`). Phase 0 complete.
**Files touched:** `site/package.json`, `site/bun.lock`, `site/src/utils/renderer-versions.ts`, `site/test/renderer-pin.test.ts`, `DOCS/STATUS.md`
**Tests:** ran `bun test` (428 pass, 0 skip), `bun --bun run typecheck` (0 errors), `bun --bun run build`, `bun run bundle` (every route ok; the lazy theme chunk unchanged at 28.4 KB raw / 17.2 KB gzip), result pass
**Next slice:** Phase 1 slice 1: the new palettes in `circ-palette.mjs`.
**Notes:** the `bun add` left the nested `node_modules/vite/node_modules/esbuild` without a working platform binary (its `bin/esbuild` died with signal 9 and `astro check` and `astro build` reported "The service was stopped"); `bun install --force` restored it with no lockfile change. If a gate fails that way after a pin bump, that is the fix. The eleven island-smoke tests that were skipped in earlier runs ran this time because `dist/` existed from the build.

## 2026-09-10 — Phase 1 — the new palettes

**What shipped:** `circ-palette.mjs` swapped to the handoff's `nextSiteDark`/`nextSiteLight` (27 keys, `grid` gone; `surface`, `spriteInk`, `wireBus`, `busLabel` added; dark `labelOnComponent` and `wireIdle` moved). Commit `875558c`.
**Files touched:** `site/src/utils/circ-palette.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/*.json`
**Tests:** added `both palettes define the same keys, and none of them is grid`, `idle wires are quieter than active ones in dark mode`; ran `bun test` (430 pass), `bun --bun run typecheck` (0 errors), result pass
**Next slice:** shared helpers and tails.
**Notes:** every skin golden changed by colour strings only (checked: the diff's changed lines are all hex or hsl values).

## 2026-09-10 — Phase 1 — cell-relative tails, dots and names

**What shipped:** `nsFont`, `nsWire`, `wireColour`, `nsTail` (1.5× and `wireBus` for a bus port), `nsDot` (0.24 cell), `nsName` replacing `drawTailLine`, `drawTailDot`, `drawNameBelow` in every skin; the NOT label below its box; every skin destructures `inputValues` for its input tails' widths. Commit `bced638`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/*.json`
**Tests:** added `no skin sets a literal stroke width`, `every colour a skin sets comes from the palette`, `a bus tail is heavier and in the bus colour`, `the NOT gate names itself below its box, like every other part`; ran `bun test` (434 pass), typecheck (0 errors), result pass
**Next slice:** the wire hook.
**Notes:** the remaining fonts inside pins, gates and boxes are still the old per-skin strings; they go with each skin's rewrite in Phases 2–4.

## 2026-09-10 — Phase 1 — the wire hook

**What shipped:** `drawWire` on `traceWire` with `{ arcRadius: 0.4 cell, cornerRadius: 0.6 cell }`, `nsWire` weight, 1.5× `wireBus` for a bus with `nsBusTick`, a two-stroke glow under an active single bit; `renderer-pin.test.ts` matches the options-object call. Commit `a46e4df`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/wire.json`, `site/test/renderer-pin.test.ts`
**Tests:** added `the wire hook rounds corners, keeps them across a crossing, and strokes a bus heavier` (idle, crossed, active, bus, half-defined bus); ran `bun test` (435 pass), typecheck (0 errors), result pass
**Next slice:** the fan-out ring.
**Notes:** the Phase 1 spec's `TODO(phase1)` on `nsGlow` is resolved as two explicit strokes; the right-to-left hop case is covered by the renderer's own tracer test from Phase 0, so no site case was added.

## 2026-09-10 — Phase 1 — the fan-out ring

**What shipped:** `drawFanOut` wired as `fanOutMarker`: 0.3-cell disc in the wire colour, 0.13-cell `destination-out` knock-out, inside `save`/`restore`. Commit (see `git log`, "a fan-out junction is a ring the pane shows through").
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/fanout.json`
**Tests:** added `fan-out: a ring in the wire colour with the centre knocked out to alpha` (three cells × three signals × two widths, colour per case, composite mode restored last); ran `bun test` (436 pass), typecheck (0 errors), `bun --bun run build`, `bun run bundle` (every route ok; theme chunk 29.9 KB raw / 17.8 KB gzip, up 1.5 KB raw on the wire and junction code), result pass
**Next slice:** gallery review (the human): `slice-and-concat`, `four-bit-adder`, `sr-latch`, `fan-out` in both modes at `cell` 10, 14, 24.
**Notes:** the first `UPDATE_GOLDENS` run of the fan-out test died on a float-rounding assertion halfway through the loop and left `fanout.json` partial; the recorder rounds to three decimals and an expectation must round the same way. Decisions 1 and 2 recorded in `DOCS/decisions/canvas-theme.md`, with the four README/file disagreements now known.

## 2026-09-10 — Phase 1 — gallery review

**What shipped:** the human reviewed the Phase 1 tree and approved it ("great"); no value changed. Phase 1 complete.
**Files touched:** `DOCS/STATUS.md`
**Tests:** none (review)
**Next slice:** Phase 2 slice 1: pin circle and single-bit pill.
**Notes:** none.

## 2026-09-10 — Phase 2 — pin circle and single-bit pill

**What shipped:** `nsHalo`, `nsPinCircle`, `nsValuePill`, `pinRadius`; `drawInputPin`/`drawOutputPin` rewritten on them (state by shape, name in the centre, `0`/`1`/`?` pill at width 1, no pill at width > 1); `nameFitsInside` and `drawPinCircle` gone. Commit `776790b`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/{input_pin,output_pin}.json`
**Tests:** added `a pin's shape says its state, and its name owns the centre`, `the single-bit pill sits above the circle, clear of the ring`, `a bus pin draws no pill of its own`; ran `bun test` (439 pass), typecheck (0 errors), result pass
**Next slice:** the bus pill through `busValue`.
**Notes:** the design's `nsGlow` under a HIGH pin (a patched `ctx.fill`) is ported as `nsHalo`, one translucent disc a spread wider inside `save`/`restore`. The input pin kept its hover fill swap for this slice so the hover guard stayed green; slice 3 removed it.

## 2026-09-10 — Phase 2 — the bus pill through `busValue`

**What shipped:** `drawBusValue` as the `busValue` hook: `nsValuePill` solid in `wireBus`/`busLabel` with the canvas's `text`, above a pin's circle or a box's edge, nothing for `rom`/`ram`. Commit `0e0a76b`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/busvalue.json`
**Tests:** added `busValue: the chip for every multi-bit kind draws as the golden says, and a memory gets none` (text verbatim, colours, seat per kind); ran `bun test` (440 pass), typecheck (0 errors), result pass
**Next slice:** the ring policy.
**Notes:** none.

## 2026-09-10 — Phase 2 — the ring policy

**What shipped:** `drawHighlight` (circle for pins via `nsHoverRing` at `r + 0.38 cell`, rounded box otherwise) as the `highlight` hook; the input pin's hover fill swap removed; `circ-theme-hover.test.ts` rewritten (no skin reads `hovered` or `inputHover`; one caller of the pin ring). Commit `7b9b830`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/circ-theme-hover.test.ts`, `site/test/fixtures/skins/highlight.json`
**Tests:** rewrote three hover guards, extended `highlight: a circle for a pin, a rounded box for every other kind, as the golden says`; ran `bun test` (440 pass), typecheck (0 errors), result pass
**Next slice:** the LED.
**Notes:** the Phase 2 spec's `TODO(phase2)` on a highlighted memory is covered by the golden test: `rom` and `ram` draw the rounded box through the same hook.

## 2026-09-10 — Phase 2 — the LED

**What shipped:** `drawLed` rewritten: lit is a disc under `nsHalo` (spread 1.3 cell) with a `background` glint, unlit a hollow `surface` ring with an `outputOff` core, undefined dashed in `labelMuted`. Commit (see `git log`, "an LED lit glows…").
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/led.json`
**Tests:** added `an LED lit is a disc under a halo, unlit a hollow ring, unknown a dashed one`; ran `bun test` (443 pass), typecheck (0 errors), result pass
**Next slice:** islands: gutter and padding.
**Notes:** deviation from the Phase 2 spec, per decision 1: the spec named `nsVecHalo` (an offscreen, cached blur) for the LED, but the design file's `led` skin uses `nsGlow`, the translucent pass; the code wins, so the LED shares `nsHalo` with the pins and `assets.offscreen` stays unused until Phase 3. `vecHaloCache` therefore does not exist yet.

## 2026-09-10 — Phase 2 — islands: gutter and padding

**What shipped:** `LiveCanvas.astro` defaults `padding` to `Math.ceil(cell * 1.5)` (prop and script fallback) and passes `layoutOptions: { rowGutter: 2 }`; `Playground.astro` the same at cell 14 (padding 21); `island-canvas-options.test.ts` guards both. Commit (see `git log`, "two rows between boxes…").
**Files touched:** `site/src/components/LiveCanvas.astro`, `site/src/components/Playground.astro`, `site/test/island-canvas-options.test.ts`
**Tests:** added `both islands lay out with a row gutter of two`, `both islands pad the canvas by 1.5 cells`; ran `bun test` (443 pass), typecheck (0 errors), `bun --bun run build`, `bun run bundle` (every route ok; theme chunk 31.7 KB raw / 18.3 KB gzip), result pass
**Next slice:** gallery review (the human): `hero-half-adder`, `wide-not`, `two-bit-adder`, and a memory highlighted from the playground editor, both modes, `cell` 10, 14, 24.
**Notes:** no gallery card passes an explicit `padding` (grep over `src/pages` and `src/content`), so the new default reaches every card. Decisions 7, 8 and 9 recorded.

## 2026-09-10 — Phase 2 — gallery review

**What shipped:** the human reviewed the Phase 2 tree and approved it ("nice"); no value changed. Phase 2 complete.
**Files touched:** `DOCS/STATUS.md`
**Tests:** none (review)
**Next slice:** Phase 3 slice 1: sprite assets — tint, halo, bounds.
**Notes:** none.

## 2026-09-10 — Phase 3 — sprite assets: tint, halo, bounds

**What shipped:** `Assets` grows `bounds(name)` (the page measures it with one `getImageData` on the decoded image, rotated as drawn); `tintedSprite`, `haloSprite` (`HALO_PAD = 0.14`), `spriteBounds` and `nsVecHalo` with their caches in `circ-skins.mjs`, built from `assets.offscreen` and emptied by `makeSkins`; `spriteArt` exported as the cache test's seam; the stub counts calls and names offscreen canvases in the log. Commit `d748419`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/src/utils/circ-theme.mjs`, `site/test/canvas-record.ts`, `site/test/circ-skins.test.ts`
**Tests:** added `a tint, a halo and the bounds are each built once per name and colour`, `before the sprites decode nothing is built, and nothing is cached as missing`; ran `bun test` (446 pass), typecheck (0 errors), result pass
**Next slice:** gate anatomy.
**Notes:** the tint and halo producers moved from the page into the skins module (the spec had them in `circ-theme.mjs`) because they need only a canvas to draw into, which the seam provides, and that is what lets the cache test count them; only `bounds` stays with the page, since it needs `getImageData`.

## 2026-09-10 — Phase 3 — gate anatomy

**What shipped:** `nsGateLayout`, `nsFitSymbol`, `gateGeometry` (exported), `symbolInk`/`symbolAlpha`, `nsSpriteRect`, `nsNegate`, `nsExclusive`, `nsTriangle`, `nsVectorGate`; six anatomy tests over the exported geometry. Commit `17924ab`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`
**Tests:** added `the three containers are inset and never touch`, `the symbol is sized by the port spread and the gate slot, whichever binds`, `a negated pair, and an exclusive pair, share one symbol size`, `an unused slot lends its width: the symbol recentres, never resizes`, `the negate bubble is tangent to the measured tip, clamped inside its slot`, `the exclusive curve nests in the OR's back, apex just left of the back's own`; ran `bun test` (452 pass), typecheck (0 errors), result pass
**Next slice:** primitives on the recipe.
**Notes:** with the stub bounds (painted width 0.64 of the square) on a 5×5 box the art is bound by the gate slot's width and ends inside it, so the bubble sits clamped at the slot's left rather than tangent; the design's clamp is the rule, and the test asserts it. `nsAnatomy` (the sheet's debug overlay) is not ported. The `assets.offscreen` from Phase 0 has its first callers here.

## 2026-09-10 — Phase 3 — primitives on the recipe

**What shipped:** `RECIPES` (seven entries), `nsGate` (tails, containers, qualifier, dots, name; `portsFrom` for a virtual box), `drawAnd` and `drawNot` on it; the NOT PNG no longer read; a vector D-shape or OR stand-in before the sprites decode. Commit `dcab03c`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/{and_gate,not_gate}.json`
**Tests:** added `an AND is the tinted sprite, haloed when HIGH, and a D-shape before the sprites decode`, `a NOT is the triangle plus the one standard bubble, no PNG`; ran `bun test` (454 pass), typecheck (0 errors), result pass
**Next slice:** builtins through the recipe.
**Notes:** the terminal dot and the negate bubble share a radius (0.24 cells), so a test that counts bubbles filters by the negate slot's x range. The vector stand-ins are an addition the design does not have (its gate drew nothing without a sprite); recorded here, not as a decision.

## 2026-09-10 — Phase 3 — builtins through the recipe

**What shipped:** `drawSubcircuit` draws any recipe name on a virtual 5-wide box centred in the macro box with `portsFrom` the real component; `spriteRect`, `drawSprite` and `spriteForSubcircuit` deleted; user subcircuits keep the labelled box until Phase 4. Commit `ff8ca29`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/subcircuit_builtin.json`
**Tests:** added `a builtin macro draws through the recipe on a virtual box, tails to the real ports` (seven names: tail endpoints, art or triangle, bubble and curve per recipe, name centred on the real box), `a user subcircuit still takes the labelled box`; ran `bun test` (456 pass), typecheck (0 errors), result pass
**Next slice:** delete the three sprites, measure, review.
**Notes:** NOR and XNOR draw on the site for the first time. The Phase 3 spec's `TODO(phase3)` on `not`'s single port is covered by the test's `not` case (port `in` at `y+1`, out at `y+1` on a 3-row box).

## 2026-09-10 — Phase 3 — delete the three sprites, measure

**What shipped:** `circ-assets.mjs` exports `AND`, `OR` and `loadAssets` only; the stub's sprite names follow; a source guard holds that no recipe names a sprite that is gone. Commit (see `git log`, "drop the NAND, XOR and NOT sprites").
**Files touched:** `site/src/utils/circ-assets.mjs`, `site/test/canvas-record.ts`, `site/test/circ-skins.test.ts`
**Tests:** replaced the sprite-module guard with `only the AND and OR sprites remain`; ran `bun test` (456 pass), typecheck (0 errors), `bun --bun run build`, `bun run bundle` (every route ok), result pass
**Next slice:** gallery review (the human): `builtin-xor`, `full-adder`, `mux-2to1`, `inverter-chain` at `cell` 10 and 24, both modes; then Phase 4.
**Notes:** measured: `circ-assets.mjs` 19,940 → 7,594 bytes; the lazy theme chunk 31.7 KB raw / 18.3 KB gzip (end of Phase 2) → 23.6 KB / 11.5 KB, against the Phase 0 baseline of 28.4 KB / 17.2 KB. Decisions 4, 5 and 6 recorded.

## 2026-09-10 — Phase 3 — gallery review

**What shipped:** the human reviewed the Phase 3 tree and approved it ("looks great"); no value changed. Phase 3 complete.
**Files touched:** `DOCS/STATUS.md`
**Tests:** none (review)
**Next slice:** Phase 4 slice 1: slice ruler and range bar.
**Notes:** none.

## 2026-09-10 — Phase 4 — slice ruler and range bar

**What shipped:** `nsShell`, `nsSliceAsset` (ruler to 16 bits, range bar above), `nsBitPart`, `drawSlice` on them. Commit `9209292`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/slice.json`
**Tests:** added `a slice is a ruler of the incoming word, MSB left, the tapped bits filled` (widths 4, 8, 16), `a slice of a word wider than sixteen bits is a range bar` (32); ran `bun test` (458 pass), typecheck (0 errors), result pass
**Next slice:** concat bands.
**Notes:** none.

## 2026-09-10 — Phase 4 — concat bands

**What shipped:** `nsConcatAsset`, `drawConcat` on `nsBitPart`. Commit `a2800be`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/concat.json`
**Tests:** added `a concat is one band and one numbered lane per operand, fading down the stack` (2, 3, 4 operands); ran `bun test` (459 pass), typecheck (0 errors), result pass
**Next slice:** user-subcircuit chip.
**Notes:** none.

## 2026-09-10 — Phase 4 — user-subcircuit chip

**What shipped:** `nsChip`, `nsChipPart`, `nsUserSubcircuit`; `drawSubcircuit`'s non-builtin branch on them; the labelled box gone. Commit `e70e5fc`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/fixtures/skins/subcircuit_user.json`
**Tests:** replaced the labelled-box case with `a user subcircuit is a chip: purple shell, tinted header with its name in capitals, the instance in the body`; ran `bun test` (459 pass), typecheck (0 errors), result pass
**Next slice:** ROM and RAM chips.
**Notes:** none.

## 2026-09-10 — Phase 4 — ROM and RAM chips

**What shipped:** `nsHex` (bigint), `nsMemory` (header, port labels, `addr → word`, unlit `wr` dot), `drawMemory` on `nsChipPart`; `drawBox` and the `memoryLabel` import gone; the hover guard's "labelled by the renderer" case replaced by one that asserts the import is gone. Commit `834ffad`.
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`, `site/test/circ-theme-hover.test.ts`, `site/test/fixtures/skins/{rom,ram}.json`
**Tests:** added `a memory chip shows its declaration in the header and addr → word in the body` (ROM loaded, ROM unloaded, RAM); ran `bun test` (460 pass), typecheck (0 errors), result pass
**Next slice:** the write indicator.
**Notes:** the first cut of this slice deleted the bit-part functions along with `drawBox` (they sat between it and the theme objects); the load error showed it at once and the block was restored byte for byte from the previous commit — the slice and concat goldens did not move, which is the proof. `nsHex`, which the Phase 1 spec placed in Phase 1, lands here with its first caller. `renderer-pin.test.ts` still asserts the renderer exports `memoryLabel`; that is the package's surface, not the site's use of it, and stays.

## 2026-09-10 — Phase 4 — the write indicator

**What shipped:** `ramWriting` with `ramEdgeState` keyed on `ctx.canvas`, the engine's predicate over `addr`, `we`, `clk`. Commit (see `git log`, "the RAM write indicator lights…").
**Files touched:** `site/src/utils/circ-skins.mjs`, `site/test/circ-skins.test.ts`
**Tests:** added `the RAM write indicator lights on the engine's edge, and only then` (eleven draws on one canvas: first defined-high clock, a real edge, a held high, we low, a partly unknown address, a second edge); ran `bun test` (461 pass), typecheck (0 errors), `bun --bun run build`, `bun run bundle` (every route ok; theme chunk 27.3 KB raw / 12.8 KB gzip), result pass
**Next slice:** gallery review (the human): `rom-lookup`, `ram-write-read`, `demux-1to2`, `slice-and-concat`, `two-bit-adder`, both modes; then Phase 5.
**Notes:** the test drives one component through a proxy that answers `canvas` with one stable object across fresh recorders, which is what a live canvas does. Decisions 10, 12 and 13 recorded, with decision 11 (the runtime stamp) named as the follow-up if the review finds the indicator misleading.

## 2026-09-10 — Phase 4 — gallery review, and the junction rule

**What shipped:** the human's review found rings along every cell of a shared trunk in `slice-and-concat`: the renderer marked a junction wherever three or more segments of one source's wires touched, which is every cell of a trunk four wires share — invisible while the default dot was the wire's own colour, a ring per cell once the site drew one. Fixed in the renderer: `junctionCells` folds a group's segments into one graph of adjacent cells and marks the cells the net leaves in three or more directions (a shared trunk and a shared bend are degree two, a tap is three); exported, README updated, version `2.3.0-alpha.2`, renderer commit `0087d0c` (pushed by the human). The site pins it; `RENDERER_PIN_VERSION` bumped; `renderer-pin.test.ts` asserts the four-wire trunk case through the installed package. With that, the human approved the rest of the Phase 4 tree ("Awesome"). Phase 4 complete.
**Files touched:** `circ-renderer/src/render/canvas.ts`, `src/index.ts`, `README.md`, `package.json`, `test/fan-out-marker.test.ts`; `site/package.json`, `site/bun.lock`, `site/src/utils/renderer-versions.ts`, `site/test/renderer-pin.test.ts`, `DOCS/STATUS.md`
**Tests:** renderer: added `a trunk that several wires share is not a run of junctions`, the hook test's rule restated as a degree property; ran `bun test` (201 pass) and `bunx tsc --noEmit`, result pass. Site: ran `bun test` (461 pass), typecheck (0 errors), `bun --bun run build`, `bun run bundle` (every route ok; theme chunk unchanged at 27.3 KB / 12.8 KB), result pass
**Next slice:** Phase 5 slice 1: the walk.
**Notes:** `bun install --force` was run right after the `bun add` this time, before any gate, per the trap recorded after Phase 0. The site's `fanOutMarker` hook did not change: the rule for where it is called is the renderer's, which is where it belongs.

## 2026-09-10 — Phase 4 — review nit: the top-row chip

**What shipped:** both islands pad the canvas by two cells (28px at cell 14) instead of 1.5; the guard test follows. The human saw a top-row pin's value chip cut at the canvas edge: at 1.5 cells the chip's top, stroke included, sat 1.42 cells over the box and fit to the pixel, which a device-pixel rounding or a stroke's half width could cut. Two cells leave it half a cell of air.
**Files touched:** `site/src/components/LiveCanvas.astro`, `site/src/components/Playground.astro`, `site/test/island-canvas-options.test.ts`, `DOCS/STATUS.md`
**Tests:** `both islands pad the canvas by two cells` (renamed, re-targeted); ran `bun test` (461 pass), typecheck (0 errors), `bun --bun run build` (every gallery card carries `data-circ-padding="28"`), `bun run bundle` (ok), result pass
**Next slice:** Phase 5 slice 1: the walk.
**Notes:** the renderer's padding is one number for all four sides; a top-only offset would be a renderer change. Two cells all round reads as balanced on a card, and is what decision 8 in `DOCS/decisions/canvas-theme.md` now says (updated in place, since the value was measured, not chosen).

## 2026-09-10 — Phase 4 — review nit, second finding: padding halved on a 2x display

**What shipped:** the chip was still tight at two cells, and the cause was the renderer's: `resize()` set the transform's translation to the padding as given, but a translation is in device pixels, so a 2x display drew the grid half a padding up and left of where `componentAtEvent` and `boxOf` looked for it. Fixed in the renderer (`setTransform(dpr, 0, 0, dpr, pad * dpr, pad * dpr)`), version `2.3.0-alpha.3`, renderer commit `7ca8593` (pushed by the human), with `test/padding-dpr.test.ts` at ratios 1, 2 and 3. The site pins it, `RENDERER_PIN_VERSION` bumped, the pin test reads the fix's shape from the installed source. The islands stay at two cells: that is now 28 real pixels, twice what the reader was seeing.
**Files touched:** `circ-renderer/src/render/canvas.ts`, `test/canvas-stub.ts`, `test/padding-dpr.test.ts`, `package.json`; `site/package.json`, `site/bun.lock`, `site/src/utils/renderer-versions.ts`, `site/test/renderer-pin.test.ts`, `DOCS/STATUS.md`
**Tests:** renderer `bun test` (203 pass), `bunx tsc --noEmit`; site `bun test` (461 pass), typecheck (0 errors), `bun --bun run build`, `bun run bundle` (ok), result pass
**Next slice:** Phase 5 slice 1: the walk.
**Notes:** the same half also shifted clicks on every high-density display since the renderer's first release; a click near a pin's edge landed half a padding off. Nobody noticed at the old 4px default. Both Phase 4 nits were renderer defects the site's theme made visible; neither was in the design.

## 2026-09-10 — Phase 5 — decisions and README reread

**What shipped:** `DOCS/decisions/canvas-theme.md` gains the two entries the Phase 4 review's renderer fixes earned (the junction rule, padding in CSS pixels) and a closing section mapping the plan's sixteen locked decisions onto its entries and naming the follow-ups (the runtime write stamp, the range bar's unjudged design, the caches that never evict). The renderer README reread against the pinned `7ca8593`: `grid` absent, the wire options, `rowGutter`, the fan-out section and `junctionCells` all present and as shipped; nothing to change.
**Files touched:** `DOCS/decisions/canvas-theme.md`, `DOCS/STATUS.md`
**Tests:** none (documents); `grep -n grid ~/circus/circ-renderer/README.md` matches only the `padding` row's "canvas grid" and the memory grid, neither a colour key
**Next slice:** move the handoff.
**Notes:** every locked decision has an entry; the three unplanned entries and the two renderer fixes are named as such.

## 2026-09-10 — Phase 5 — move the handoff

**What shipped:** `DOCS/design/` moved to `DOCS/archive/design/canvas-theme/` with `git mv`; a row in `DOCS/archive/index.md`; the one source comment that named the old path (`circ-palette.mjs`) updated. The untracked sprite copy under `site/` moved with the directory on disk and stays untracked.
**Files touched:** `DOCS/archive/design/canvas-theme/*` (renamed), `DOCS/archive/index.md`, `site/src/utils/circ-palette.mjs`, `DOCS/STATUS.md`
**Tests:** ran `bun test` in `site/` (461 pass) — no test read the handoff path
**Next slice:** Phase 5 slices 1 and 2, the walk and the hover redraw timing, are the human's; the completion entry follows their notes.
**Notes:** `DOCS/PLANS_PROMPT.md`, the phase specs and earlier STATUS entries still cite `DOCS/design/...` by line; they are the record of what was read where, and the archive prompt's highlight view will point at the new path.
