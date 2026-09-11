# Phase 2 — The canvas region and the Live view

> **Dependencies:** Phase 0 (the frame, the two regions, the terminal line always present), Phase 1 (the envelope at version 2 with `view` in place of `tab`, decision 5).
> **Warnings:** Decisions 8, 9, 12 and 15 of the plan prompt. The renderer is read-only and already pinned at what this phase needs (`site/package.json` `circ-renderer#2d973b4`, `RENDERER_PIN_VERSION = '2.3.0-alpha.4'`, `site/src/utils/renderer-versions.ts:13`). Two facts the code fixes that the plan prompt states loosely: a theme flip does **not** rebuild the canvas — it calls `setTheme` in place (`Playground.astro:3508-3517`) and `renderer-pin.test.ts` forbids a rebuild ("a theme flip changes a live canvas in place") — so there is no refit on a theme flip, and none is needed since the view survives; and under `viewport: 'parent'` the renderer fits the circuit itself on the first measurement (`circ-renderer/src/render/canvas.ts:446-467`), so "fit once per artifact" is the renderer's, not a call the site makes. The design file draws the bottom-right line as `cell 14 · fit` (board 2a); decision 9 adds the zoom percentage and a reset. Per decision 2 the file's words are kept and the renderer README's toolbar idiom supplies the rest: `cell 14 · 100% · fit`, where `100%` is both the zoom label and the reset button.

## Goal

The output pane is gone. In its place the canvas region of board 2a sits on `--bg` under a dot grid: a segmented view switch `Schematic · Live · Truth` at its top-left, a `Data` button carrying `N → M` at its top-right, a hint line bottom-left, and `cell 14 · 100% · fit` bottom-right. The Live view fills the inset `60px 16px 40px` with the renderer's canvas sized to it, and a reader can zoom with the modifier wheel or a pinch, pan with a drag, press `fit` or `100%`, and still click a pin or type a bus value; the percentage follows every view change. The Schematic and Truth views show today's `<pre>` and table, unstyled beyond the region's surface (Phase 3 dresses them); the Truth view's gate is the same sentence as today, parked in the region's toolbar until Phase 3 makes it a chip. The Data button opens today's rows in a plain card (Phase 5 makes it the floating panel). `state.view` is `'schematic' | 'live' | 'truth'`, persisted; `dataOpen` is persisted beside it. `bun run bundle` reports the eager chunk unchanged within the two new pure modules.

## Scope

**In scope:**
- The region's markup in `Playground.astro`: the view switch (`role="tablist"`, three `role="tab"` buttons, `data-view`), the Data button, the hint line, the zoom line, and three view panels `[data-view-panel]` plus the Data card `.pg-data-card[hidden]`.
- The removal of `.pg-tabs`, the four `.pg-panel[data-panel]` wrappers, the tooltip `#pg-tab-tip-truth` and its `aria-describedby` wiring (`Playground.astro:194-227`, `:636-652`; `global.css:654-721`).
- `showTab` → `showView`, `state.tab` → `state.view` at every site (`:483`, `:648`, `:655`, `:2442`, `:2922-2923`, `:3240`, `:3250`, `:3339`, `:3487-3488`, `:2489`); the Data face keyed on `state.dataOpen` instead of `state.tab === 'data'`.
- The Live view on `viewport: 'parent'`, `navigation: { wheel: 'modifier', drag: true, touch: 'own' }`, `onViewChange` (`buildCanvas`, `:3270-3336`); `.pg-sim-mount` sized by the region's inset; the site-side refit rule when the inset changes (Data card open or closed, drawer grown) and the reader has not navigated.
- `site/src/scripts/zoom-label.ts` (`formatZoom`) and `site/src/scripts/pin-count.ts` (`pinCountLabel`), with tests.
- `renderer-pin.test.ts` probes for `fit`, `resetView`, `getView`, `setView`, `zoomBy`, `setViewport`, and the `navigation`/`viewport`/`onViewChange` option keys.
- `bench-tokens.test.ts` (Phase 0) holding over the new `.pg-view-*`, `.pg-zoom`, `.pg-hint`, `.pg-data-btn` rules; `app-layout.test.ts` unchanged (no rule touches `.lc-mount`; the mount keeps its `.lc-mount` class only if Phase 0 kept it — see TODO).
- `DOCS/sim-protocol.md:230-235` reworded: "the Live view or the Data panel" for "the Simulate or Data tab"; "in the Data panel" for "on the Data tab".
- `island-smoke.test.ts`: the output-strip walk (`:272-289`) and the drawer test (`:350-372`) rewritten for the switch, the card and the always-present terminal line.
- `DOCS/decisions/playground-bench.md`: decisions 8 and 9 appended.

**Explicitly deferred:**
- Schematic and Truth styling, the `unicode | ascii` toggle, Copy buttons, the live row, the row click, the over-cap rows (Phase 3).
- The Data panel as a draggable card with a per-project position (Phase 5); here it is a fixed card under the button.
- The drawer growing on focus (Phase 6). The terminal line is Phase 0's and stays one line here.
- Any renderer change. `wheel: 'always'` is not chosen: the region is under a page that scrolls below 800px (decision 15), and the modifier wheel is what a trackpad pinch arrives as (`canvas.ts:150-160`).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/zoom-label.ts` | `formatZoom(scale: number): string` — `100%` at 1, rounded to the nearest whole percent, `25%`…`800%` at the clamps (`DEFAULT_ZOOM` from `circ-renderer` is not imported: the module stays free of the renderer so it rides in the eager bundle; the bounds are asserted against `DEFAULT_ZOOM` in the test). `zoomLine(scale, cell): string` → `cell 14 · 100% · fit` split into its three spans by the island. |
| site | `site/src/scripts/pin-count.ts` | `pinCountLabel(symbols, rootId): string` — `N → M` counting root `input` and `output` symbols (pins, not bits; `rootInputBits` at `:2941-2950` counts bits and stays for the cap). Empty string when `rootId` is null. |
| site | `site/test/zoom-label.test.ts` | See Tests. |
| site | `site/test/pin-count.test.ts` | See Tests. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/components/Playground.astro` | Region markup; `Tab` → `View`; `showView`, `setDataOpen`; `applyTruthGate` writes the toolbar note instead of the tooltip; `buildCanvas` options; `refitIfIdle`; the mount observer; the Data button count from `pinCountLabel` after each analysis (`publishDiagnostics`, `:3021`) and from `session.pins` once a session exists. |
| site | `site/src/styles/global.css` | `.pg-tabs`, `.pg-tab-tip`, `.pg-panel` rules removed (`:654-723`); `.pg-view-switch`, `.pg-view-tab`, `.pg-data-btn`, `.pg-hint`, `.pg-zoom`, `.pg-live`, `.pg-sim-mount` (rewritten from `:1333-1340`: the mount fills `.pg-live`, `overflow: hidden`, no auto margins — the renderer centres by `fit`), `.pg-data-card`. |
| site | `site/src/utils/playground-store.ts` | `OutputTab` gone (Phase 1 introduced `View`); `dataOpen: boolean` default `false` in `defaultEnvelope`, read in `normalize` with a boolean check; `OUTPUT_TABS` → `VIEWS` if Phase 1 has not already. |
| site | `site/test/playground-store.test.ts` | `dataOpen` default and normalisation; the version-1 migration case gains `tab: 'data'` → `view: 'live', dataOpen: true` (decision 5 maps `data → live`; opening the card as well is this phase's refinement, so a reader who left the Data tab open finds their rows). |
| site | `site/test/renderer-pin.test.ts` | The probes above, in the "host hooks" test under a "Bench, Phase 2" comment. |
| site | `site/test/island-smoke.test.ts` | The walks above. |
| site | `DOCS/sim-protocol.md` | Two sentences. |
| site | `DOCS/decisions/playground-bench.md` | Decisions 8, 9. |

**New dependencies:** None.

## Data & State

```ts
// playground-store.ts (Phase 1 shape, extended)
export type View = 'schematic' | 'live' | 'truth';
export const VIEWS: readonly View[] = ['schematic', 'live', 'truth'];
export interface PlaygroundEnvelope {
  // …
  view: View;        // Phase 1
  dataOpen: boolean; // this phase; default false
}
```

```ts
// Playground.astro, the island's state
type View = import('../utils/playground-store.ts').View;
state.view: View;          // was state.tab
state.dataOpen: boolean;   // the card; Phase 5 keeps the field and moves the card
sim.navigated: boolean;    // set by onViewChange, cleared by fit()/resetView(); gates refitIfIdle
sim.cell: 14;              // the one cell size, so the zoom line and the canvas agree
```

Canvas options at `buildCanvas` (`:3279-3313`), the additions in full:

```ts
new Canvas<PaletteKey>(session.runtime as CircRuntime, {
  cell: sim.cell,
  padding: Math.ceil(sim.cell * 2),
  interactive: true,
  theme: pickTheme(),
  layoutOptions: { rowGutter: 2 },
  viewport: 'parent',                                   // canvas.ts:143
  navigation: { wheel: 'modifier', drag: true, touch: 'own' }, // canvas.ts:150-165
  onViewChange: (view) => { sim.navigated = true; zoomPct.textContent = formatZoom(view.scale); },
  onPinChange, valueFormat, onHover,                    // unchanged
});
```

`onViewChange` is "never for the view a canvas is built with" (`canvas.ts:124`, README options table), so `zoomPct` is written to `formatZoom(canvas.getView().scale)` once after construction and after every `fit()`/`resetView()` the site calls, since those go through `changeView` and do fire it (`canvas.ts:473-481`) — the explicit write covers the no-op case where the view did not change.

The zoom line's three controls: `100%` is a `<button>` calling `view.resetView()` (README: "A toolbar with −, +, Fit and 100% is those four calls"), `fit` a `<button>` calling `view.fit()`; both clear `sim.navigated`. `cell 14` is text. Disabled (`aria-disabled`, not `disabled`, as the truth tab was, `:633-637`) while there is no canvas.

The hint line: board 2a's `click a pin to toggle · hover a part to find it in the source` for Live; Schematic and Truth keep the region's line empty this phase (Phase 3 fills them). `simNoteBase` (`:3146`) is replaced by this line; `simNote` keeps the failure messages (`Compile a circuit first.`, `Fix the errors to simulate.`, `Could not render the circuit: …`, `:3474-3476`, `:3331`) and sits inside `.pg-live` above the mount.

The Data button label: `Data` + `<span class="pg-data-count">N → M</span>`; `aria-pressed` follows `state.dataOpen`; the count from `pinCountLabel(state.analysis.symbols, rootId)` after each `publishDiagnostics`, empty when no analysis. `aria-controls` names the card.

## Execution & Concurrency Model

Synchronous apart from what exists: the two dynamic imports (`loadRenderer`, `loadThemes`, `:3165-3166`) and the session build guarded by bytes (`ensureSession`, `:3200-3268`). One new asynchronous edge, the refit:

- The renderer's own `ResizeObserver` on the canvas element fits on the first measurement and keeps the view on later ones (`canvas.ts:455-467`).
- The site adds one `ResizeObserver` on `.pg-sim-mount`, created once in `init`, calling `refitIfIdle()`. ResizeObserver delivers a batch shallowest-first, so the mount's callback runs **before** the canvas's in the same pass; `refitIfIdle` therefore defers by one `requestAnimationFrame` and only then calls `sim.view.view.fit()` when `sim.navigated` is false. A reader who zoomed keeps their view when the card opens; one who never touched it sees the circuit refit into the narrower inset. This is the plan prompt's trap "fit() after a rebuild must run after the mount has its size", made a rule: the site never calls `fit()` synchronously from a layout change.
- `sim.navigated` is owned by the island; `onViewChange` sets it, the two buttons and `buildCanvas` clear it (a new canvas starts fitted).

## Persistence & I/O

`view` and `dataOpen` in the envelope (one key, decision 5; `writeEnvelope` debounce unchanged). No other I/O. The view's zoom and pan are **not** persisted: a canvas starts fitted, and a saved view is measured in pixels of an inset that may have changed.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Two pure modules | `zoom-label.ts`, `pin-count.ts`, their tests; `dataOpen` in the store with its normalisation and the migration case. | `zoom-label.test.ts`, `pin-count.test.ts`, `playground-store.test.ts` green; `bun run bundle` before/after in STATUS. |
| 2 | The region's furniture | Markup and CSS for the switch, the Data button, the hint and zoom lines, the three view panels and the card; `.pg-tabs`, the tooltip and `.pg-panel` removed; `showView`/`setDataOpen`; `applyTruthGate` writes `.pg-view-note` (the toolbar's right slot, mono 11px `--muted`) and keeps `aria-disabled` on the Truth tab; `setDrawerShown`'s tab coupling (`:753`) removed if Phase 0 left it. Board 2a's geometry from the file: switch `padding 2px; border 1px --border; radius 6px; --pane-bg`, segments `4px 12px` mono 11.5px, active `--accent` on `--bg` radius 4px; lines mono 11px `--muted`, 16px in, 12px up. | Smoke walk rewritten: tabs `['schematic','live','truth']`, `aria-selected` on `schematic`, the Truth tab `aria-disabled="false"` and `.pg-view-note` empty, the card `hidden`, `.pg-data-btn[aria-pressed="false"]`; `bench-tokens.test.ts` green; the keyboard: `ArrowLeft`/`ArrowRight` move between tabs and `Home`/`End` to the ends (today's strip has no arrow handling, `Playground.astro` has no `keydown` on `.pg-tabs`; this is the tablist's due). |
| 3 | The Live view fills the inset | `.pg-live { position: absolute; inset: 60px 16px 40px }`, `.pg-sim-mount { height: 100%; overflow: hidden }`, `.pg-data-card` open → `.pg-canvas-region[data-data-open] .pg-live { right: 344px }`; `buildCanvas` with `viewport`, `navigation`, `onViewChange`; the zoom line live; `sim.navigated`; the mount observer and `refitIfIdle`. | Smoke: after `live` is shown the mount has a computed height (happy-dom: assert the class and the inset rule are present in the built CSS, and that `buildCanvas`'s source passes `viewport: 'parent'` — a source-text check in `renderer-pin.test.ts`, since no canvas exists headless); `renderer-pin.test.ts` probes green; the human's walk: zoom with ⌘-wheel, pan by drag, click a pin, type a bus value, `fit`, `100%`, open the Data card and watch the refit, zoom then open the card and watch the view hold. |
| 4 | The record | `DOCS/sim-protocol.md` reworded; decisions 8 and 9 appended; STATUS with the bundle numbers and the walk's findings. | `bun test` whole; `bun --bun run typecheck`; `bun --bun run build`; `bun run bundle`. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `formatZoom rounds to a whole percent` | `zoom-label.ts` | `1 → '100%'`, `0.25 → '25%'`, `8 → '800%'`, `1.004 → '100%'`, `1.005 → '101%'`, `0.333 → '33%'`. |
| `formatZoom's bounds are the renderer's` | `zoom-label.ts` | `formatZoom(DEFAULT_ZOOM.min) === '25%'` and `.max === '800%'`, importing `DEFAULT_ZOOM` from `circ-renderer` in the test only. |
| `zoomLine spells the design's line` | `zoom-label.ts` | `zoomLine(1, 14) === 'cell 14 · 100% · fit'`. |
| `pinCountLabel counts root pins, not bits` | `pin-count.ts` | Symbols `{a: input w1, b: input w4, out: output w4}` at the root and an `x: input` in another file → `'2 → 1'`; null root → `''`; no outputs → `'2 → 0'`. |
| `dataOpen defaults and normalises` | `playground-store.ts` | `defaultEnvelope().dataOpen === false`; `normalize({…, dataOpen: 'yes'})` → `false`; a recorded version-1 envelope with `tab: 'data'` → `view: 'live'`, `dataOpen: true`, scratch kept. |
| `the host hooks this site depends on are present` (extended) | `renderer-pin.test.ts` | `fit`, `resetView`, `getView`, `setView`, `zoomBy`, `setViewport` on `CircCanvas.prototype`; `({ viewport: 'parent', navigation: { wheel: 'modifier', drag: true, touch: 'own' }, onViewChange: () => {} } satisfies Partial<RenderOptions>)`; the island's source passes `viewport: 'parent'` and never `wheel: 'always'`. |
| `every .pg- colour is a token` (Phase 0, held) | `bench-tokens.test.ts` | The new rules pass. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `the island mounts on the built page` (rewritten walk) | `island-smoke.test.ts` | The switch's three tabs in order, `schematic` selected, Truth `aria-disabled="false"` with an empty `.pg-view-note`, the card hidden, the button's `aria-pressed="false"`, the hint and zoom lines present, no `.pg-tabs`, no `#pg-tab-tip-truth`. |
| `the terminal line stays whichever view is shown` (replaces "the drawer follows the output tab") | `island-smoke.test.ts` | Clicking `live`, `truth`, `schematic` never sets `hidden` on the drawer; the Data button toggles the card's `hidden` and its `aria-pressed`; clicking `live` sets `data-view-panel="live"` visible and the two others `hidden`. |
| `the value dialog the site styles…`, `a theme flip changes a live canvas in place` | `renderer-pin.test.ts` | Unchanged and still green: one `new Canvas<PaletteKey>(session.runtime as CircRuntime, {` call, `setTheme(pickTheme()` present, no rebuild. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle && bun test test/island-smoke.test.ts`

## Open Questions / Spikes

- `TODO(phase2):` the region and panel class names are Phase 0's to fix (the region is Phase 0's `.pg-canvas-region`; `.pg-live` and `[data-view-panel]` are this spec's proposal); align any other name to Phase 0's before slice 2, and keep `.lc-mount` off the mount if Phase 0 dropped it (the shared LiveCanvas rules at `global.css:513-545` give it `display: block` and a mobile `max-width: none` the bench does not want).
- `TODO(phase2):` `touch: 'own'` below 800px: the stacked page scrolls (decision 15), and a one-finger pan on the canvas would trap the scroll. Slice 3 sets `touch: 'own'` only when `matchMedia('(min-width: 800px)')` matches (the `narrow` query at `:2519` is the same breakpoint) and rebuilds nothing on a change — the option is read at construction, so a resize across the breakpoint keeps the old gesture until the next artifact. Record it as a papercut if the human's walk finds it.
- `TODO(phase2):` the `100%` button's name for a screen reader: `aria-label="Reset zoom to 100%"`, text `100%` updated live; confirm the announcement channel (`role="status"`, `:1061`) is not fed by zoom changes — it must not be.
