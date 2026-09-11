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
