# Phase 0 — Hooks, harness and the handoff

> **Dependencies:** None
> **Warnings:** Two repositories. Slices 1–3 land in `~/circus/circ-renderer` on a branch off `main` (`0889785`); slice 3 ends at the human's push, and slices 4–6 land here in `worktrees/v0.0.3/canvas-theme`. `CLAUDE.md`'s git rules apply to both. Read `DOCS/PLANS_PROMPT.md` decisions 3, 14, 15 and 16 before starting; this phase must be pixel-neutral on the site.

## Goal

The renderer exposes the three things the design cannot draw from outside — a `fanOutMarker` theme hook, corner rounding in `traceWire`, and a `rowGutter` layout option — with tests and README text for each, and the site pins the sha that carries them. On the site, the handoff is tracked under `DOCS/design/`, today's theme is split into a palette module, a skins module that takes its sprites and offscreen canvases by injection, and the entry the islands import, and a recording-context test pins every skin's draw calls as op-log goldens. A reader sees no change on any page: the goldens are today's drawing, and the gallery looks as it did.

## Scope

**In scope:**
- Renderer: `FanOutMarkerContext` and `CircTheme.fanOutMarker`, called from `drawFanOutMarkers` with the group's value; the default dot unchanged when the hook is absent.
- Renderer: `traceWire(path, wire, cell, opts)` and `wirePath(wire, cell, opts)` accept `{ arcRadius?, cornerRadius? }` as well as the positional number; with a `cornerRadius` the wire is one continuous subpath whose corners round through `arcTo` and whose crossing hops are spliced in place.
- Renderer: `LayoutOptions.rowGutter` (default `1`) read by `coords.ts` at both sites that use `ROW_GUTTER`; `buildLayout` threads it.
- Renderer: `grid` removed from `ThemeColorKey`, `defaultColors` and the README table; README gains the hook, the options and the gutter.
- Renderer: `package.json` version bumped (`2.3.0-alpha.1`), `bun test` and `bunx tsc --noEmit` green.
- Site: `DOCS/design/` committed per decision 16.
- Site: `circ-theme.mjs` split into `circ-palette.mjs`, `circ-skins.mjs` and the `circ-theme.mjs` entry, moving today's code without changing what it draws.
- Site: `site/test/canvas-record.ts` (a recording 2D context and stub assets) and `site/test/circ-skins.test.ts` with op-log goldens under `site/test/fixtures/skins/`.
- Site: pin bump (`package.json`, `bun.lock`, `RENDERER_PIN_VERSION`), `renderer-pin.test.ts` extended for the new hook, `bun run bundle` numbers recorded.

**Explicitly deferred:**
- Any palette value, stroke width, or skin shape change (Phases 1–4).
- Using `rowGutter` or `cornerRadius` from the site (Phases 1 and 2).
- Removing sprites (Phase 3).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| circ-renderer | `test/fan-out-marker.test.ts` | Drives a fan-out fixture (`fan_out.wasm`) through `CircCanvas` with a theme whose `fanOutMarker` records its context; asserts the hook fires once per junction cell with the group's `value` and that the default dot is not drawn when the hook is present. |
| site | `site/src/utils/circ-palette.mjs` | `colorsDark`, `colorsLight`, the `PaletteKey` typedef, `pickPalette()` (reads `document.documentElement.dataset.theme`). |
| site | `site/src/utils/circ-skins.mjs` | Every drawing function from today's `circ-theme.mjs` (`drawTailLine` … `drawMemory`, `wireRenderer`, `drawHoverRing`, `nameFitsInside`, `spriteRect`, `drawSprite`, `spriteForSubcircuit`), exported as `makeSkins(assets)` returning `{ skins, wire, background, portMarker, highlight, font }`. No module-scope side effects. |
| site | `site/test/canvas-record.ts` | `recordingContext(cell)`: a Proxy whose method calls append `[name, ...args]` (numbers rounded to 3 decimals) to `ops`, whose property sets append `["set", prop, value]`, with `measureText(t)` returning `{ width: t.length * cell * 0.6 }`; `stubAssets()`: an `Assets` object whose `sprite(name)` returns `{ width: 100, height: 100, name }` for the five sprite names and whose `offscreen(w, h)` returns a stub canvas with its own recorder. |
| site | `site/test/circ-skins.test.ts` | For every registered skin × signal (0, 1, 2) × width (1, 8) × cell (10, 14, 24): builds a `PlacedComponent` from `sizing.ts`'s footprints, calls the skin, and compares `ops` to `site/test/fixtures/skins/<kind>.<sig>.w<width>.c<cell>.json`; regenerates under `UPDATE_GOLDENS=1`. Also asserts `save`/`restore` balance on every op log. |
| site | `site/test/fixtures/skins/*.json` | The op-log goldens of today's drawing. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| circ-renderer | `src/utils/theme.ts` | Add `FanOutMarkerContext { ctx, theme, cell, x, y, value: BitValue, signal: Signal }` and `CircTheme.fanOutMarker?`; remove `"grid"` from `ThemeColorKey` and `defaultColors`. |
| circ-renderer | `src/render/canvas.ts` | `drawFanOutMarkers`: when `theme.fanOutMarker` exists, call it per junction cell instead of stamping the dot. |
| circ-renderer | `src/render/wire-path.ts` | `TraceOptions { arcRadius?: number; cornerRadius?: number }`; `traceWire`/`wirePath` accept `number | TraceOptions`; a continuous-path branch when `cornerRadius > 0`. |
| circ-renderer | `src/layout/types.ts` | `LayoutOptions.rowGutter?: number`. |
| circ-renderer | `src/layout/coords.ts` | `assign(...)` takes the gutter; `ROW_GUTTER` stays exported as the default. |
| circ-renderer | `src/layout/index.ts` | `buildLayout` passes `opts.rowGutter ?? ROW_GUTTER`. |
| circ-renderer | `src/index.ts` | Export `FanOutMarkerContext`, `TraceOptions`. |
| circ-renderer | `README.md` | Colour table without `grid`; "Drawing a wire yourself" shows the options object; new "Fan-out junctions" and "Row gutter" paragraphs. |
| circ-renderer | `package.json` | `"version": "2.3.0-alpha.1"`. |
| circ-renderer | `test/wire-path.test.ts`, `test/layout.test.ts` | New cases (see Tests). |
| site | `site/src/utils/circ-theme.mjs` | Becomes the entry: `loadAssets()`, `onAssetsReady`, `blogAssetsReady`, the browser `Assets` implementation, `blogTheme`, `blogThemeLight`, `pickTheme` built from `makeSkins(assets)` and the palettes. |
| site | `site/test/circ-theme-hover.test.ts` | Reads `circ-skins.mjs` for skin bodies and `circ-theme.mjs`/`circ-palette.mjs` where the guarded text moved; assertions unchanged in meaning. |
| site | `site/package.json`, `site/bun.lock` | `circ-renderer` at the pushed sha. |
| site | `site/src/utils/renderer-versions.ts` | `RENDERER_PIN_VERSION = '2.3.0-alpha.1'`. |
| site | `site/test/renderer-pin.test.ts` | Assert `traceWire` accepts an options object (call with `{ cornerRadius: 0 }` on a recorder) and `buildLayout` accepts `rowGutter`. |
| site | `DOCS/decisions/canvas-theme.md` (new), `DOCS/decisions/index.md` | Entries for decisions 3, 14, 15 and 16. |

**New dependencies:** None.

## Data & State

Renderer additions:

```ts
// src/utils/theme.ts
export interface FanOutMarkerContext<C extends string = ThemeColorKey> {
  ctx: CanvasRenderingContext2D;
  theme: CircTheme<C>;
  cell: number;
  /** Junction cell, in CELL coordinates (centre at x+0.5, y+0.5). */
  x: number;
  y: number;
  /** The fan-out group's source value and its collapsed signal. */
  value: BitValue;
  signal: Signal;
}
export interface CircTheme<C> { /* … */ fanOutMarker?: (args: FanOutMarkerContext<C>) => void; }

// src/render/wire-path.ts
export interface TraceOptions { arcRadius?: number; cornerRadius?: number }
export function traceWire(path: CanvasPath, wire: RoutedWire, cell: number, opts?: number | TraceOptions): void;

// src/layout/types.ts
export interface LayoutOptions { expandMacros?: boolean; rowGutter?: number }
```

The continuous-path branch: points are the segment endpoints in order (`from` of the first, then every `to`); for each horizontal run the crossings on it are spliced as `lineTo(hx − arcRadius) ; arc(hx, y, arcRadius, π, 0, dir < 0)` in travel order; at every interior point `arcTo(b, c, cornerRadius)` instead of `lineTo(b)`; the last point is `lineTo`. This is `drawWireNextSite`'s loop (`DOCS/design/circ-site-theme.js:1458-1508`) with `cornerR` a parameter. `cornerRadius` is clamped to half the shorter adjacent segment so a one-cell jog cannot overshoot.

Site injection boundary (decision 14):

```js
/** @typedef {{
 *   sprite(name: string): CanvasImageSource | null,   // 'AND' | 'OR' | … as loaded by loadAssets
 *   offscreen(w: number, h: number): HTMLCanvasElement,
 * }} Assets */
export function makeSkins(assets) { /* returns { skins, wire, background, portMarker, highlight, font } */ }
```

Phase 3 extends `Assets` with `bounds`, `tinted` and `halo`; this phase adds only what today's code needs (`sprite` for `drawSprite`/`spriteForSubcircuit`; `offscreen` is declared now so Phase 2's halo has a home and the stub is stable).

## Execution & Concurrency Model

This phase is fully synchronous. `loadAssets()` remains the one promise, in `circ-theme.mjs` as today; `makeSkins` is called once per palette after it resolves and once before (sprites null) exactly as the current `sprites` module variable behaves, so vector fallbacks and the `onAssetsReady` retheme keep their timing.

## Persistence & I/O

Op-log goldens are JSON files under `site/test/fixtures/skins/`, written under `UPDATE_GOLDENS=1 bun test`, read otherwise. No other I/O beyond what `bun test` and the build already do. The renderer's fixtures (`test/fixtures/*.wasm`) are reused, none added.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | renderer: fan-out marker hook | `FanOutMarkerContext`, `fanOutMarker`, `drawFanOutMarkers` branch, README paragraph. | `test/fan-out-marker.test.ts`: on `fan_out.wasm` the hook is called once per junction cell with `value.width === 1`; with no hook the recorder sees the default `arc(…, cell*0.18, …)`. |
| 2 | renderer: rounded corners in `traceWire` | `TraceOptions`, continuous-path branch, `wirePath` parity, README example. | `test/wire-path.test.ts`: a three-segment wire with one crossing at `{ cornerRadius: 4 }` yields exactly one `moveTo`, two `arcTo`, one `arc`, and no interior `moveTo`; the positional-number call is byte-identical in ops to today. |
| 3 | renderer: `rowGutter`, drop `grid`, bump | `LayoutOptions.rowGutter`, `coords.ts` threaded, `grid` removed, version `2.3.0-alpha.1`. **Hard stop: the human pushes.** | `test/layout.test.ts`: two stacked pins on `fan_in.wasm` are `rowGutter` rows apart at 1 and at 2; `test/layout-parity.test.ts` unchanged and green; `tsc --noEmit` green with `grid` gone. |
| 4 | site: track the handoff | `DOCS/design/` staged by path (no `.DS_Store`, no `site/` copy). | `git status` shows only the listed files staged; `bun test` untouched. |
| 5 | site: theme split and op-log goldens | `circ-palette.mjs`, `circ-skins.mjs`, `circ-theme.mjs` entry, `canvas-record.ts`, `circ-skins.test.ts`, goldens generated. | `bun test` green; a one-off diff (recorded in STATUS, not kept) of each moved function body against `git show HEAD:site/src/utils/circ-theme.mjs` shows whitespace-only changes; `circ-theme-hover.test.ts` green against the new file layout. |
| 6 | site: pin bump | `package.json`, `bun.lock`, `RENDERER_PIN_VERSION`, `renderer-pin.test.ts` additions, `canvas-theme.md` entries. | `bun test`, `bun --bun run typecheck`, `bun --bun run build`, `bun run bundle` green; the theme chunk's reported bytes recorded in STATUS as the Phase 3 baseline. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `fanOutMarker fires once per junction with the group value` | circ-renderer `test/fan-out-marker.test.ts` | On `fan_out.wasm`, the hook's calls equal the set of cells with ≥3 segment touches; `signal` matches `signalOf(value)`. |
| `default fan-out dot is drawn only without the hook` | same | Recorder sees `arc` at `cell*0.18` without the hook and none with it. |
| `cornerRadius yields one continuous subpath` | circ-renderer `test/wire-path.test.ts` | One `moveTo`, `arcTo` at each interior corner, crossing `arc` spliced in travel order, right-to-left run still lays hops correctly. |
| `positional arcRadius is unchanged` | same | Ops identical to the pre-change recording for the existing cases. |
| `rowGutter spaces stacked boxes` | circ-renderer `test/layout.test.ts` | `y` difference between two stacked real nodes equals `h + rowGutter` at 1 and 2; dummies pay none. |
| `every skin's op log matches its golden` | site `test/circ-skins.test.ts` | Per kind/signal/width/cell, `ops` deep-equals the JSON golden. |
| `every skin balances save and restore` | same | Count of `save` equals count of `restore` in each log. |
| `the ring is drawn once through the highlight hook` | site `test/circ-theme-hover.test.ts` | Unchanged assertions, new file paths. |
| `traceWire accepts an options object` | site `test/renderer-pin.test.ts` | Calling with `{ cornerRadius: 0 }` on a recorder does not throw and traces the segments. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `layout parity` | circ-renderer `test/layout-parity.test.ts` | Every vendored fixture-mode still matches at default options. |
| `renderer pin` | site `test/renderer-pin.test.ts` | Installed package version, lockfile specifier and `RENDERER_PIN_VERSION` agree. |
| `bundle budget` | `bun run bundle` after `bun --bun run build` | No route over budget; theme chunk reported. |

Run command: `cd ~/circus/circ-renderer && bun test && bunx tsc --noEmit`; `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- `TODO(phase0)`: confirm under `bun test` that a Proxy-based recorder satisfies every call today's skins make (`roundRect`, `setLineDash`, `measureText`, `createLinearGradient` if any). Slice 5's first task is to run the skins once and list what the recorder had to learn.
- `TODO(phase0)`: the renderer's `README.md` "Theme color keys" table lists `grid` as "reserved for future grid backgrounds"; removing it is a type-level break for any host that spread `defaultColors` and set `grid` (the README's own dark example does). The bump to `2.3.0` marks it; the README example drops the key.
