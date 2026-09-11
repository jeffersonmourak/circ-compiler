# Phase 5 — The Data panel

> **Dependencies:** Phase 1 (the envelope at version 2 with `normalize` filling a missing field from `defaultEnvelope()`, decision 5), Phase 2 (the canvas region, the `Data` button at its top-right corner, `View` in the store, the Live view on `viewport: 'parent'` with a refit hook, decisions 8 and 9).
> **Warnings:** Decisions 5, 8, 9, 14 and 15 of the plan prompt. The rows stay `data-view.ts`'s (`rowsFor`, `editRow`, `toggleRow`, `data-view.ts:41-89`) and every edit still reaches the session through `session.set`, so the console keeps echoing each edit as `commandFor` spells it (`Playground.astro:3230-3236`); this phase moves the rows into a card and adds nothing between the field and the session. `data-view.ts` reaches the renderer's index and must stay behind `loadDataView` (`Playground.astro:3167-3172`), never in the eager graph. The design file wins over its README (decision 2); the values below are the file's inline styles.

## Goal

A reader on any view clicks `Data` at the canvas region's top-right and a 312px card opens under it, listing every root input as a toggle knob or a value field and every root output as a read-only value, in the base the header's hex/bin/dec segment selects. Editing a field or clicking a knob settles the circuit, redraws the canvas, and prints the `set` line in the console, as the Data tab does today. The reader drags the card by its grip anywhere inside the canvas region and it stays where it was left, per project, across reloads; the circuit is never under it, because the region keeps a 344px right inset while the card is open and the canvas refits. `✕`, `Escape` or the `Data` button closes it; switching projects closes it and the next open lands where that project left it. Board 3d (the Hack ALU with eight inputs and three outputs) renders in both themes, and the `.pg-panel[data-panel="data"]` markup is gone.

## Scope

**In scope:**
- The card: `position: absolute; top: 52px; right: 16px; z-index: 2; width: 312px; background: var(--pane-bg); border: 1px solid var(--border); border-radius: 8px; box-shadow: 0 12px 32px rgba(0,0,0,0.28); font-family: var(--font-mono)` (the file's `3d` board), `role="dialog"`, `aria-label="Data"`, non-modal (focus is not trapped; the canvas and the editor stay reachable).
- Header (`padding: 8px 12px`, 11px): the grip `⋮⋮` (a `button`, `aria-label="Move the panel"`, `cursor: grab`), **Data** at 600, `N in · M out` in `--muted`, the hex/bin/dec segmented control at 10px bound to `settings.valueFormat` through the settings `set` path (`Playground.astro:2428-2447`, which already re-spells the canvas badges and re-renders the rows), and `✕` (`aria-label="Close"`).
- Two sections separated by a `1px --border` rule, each with a column header row (`padding: 2px 12px 4px; font-size: 9.5px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted)`): `input / bits / value`, then `output`. Rows on `grid-template-columns: 1fr 36px 92px; align-items: center; padding: 3px 12px; font-size: 12px`, the name in the first column, the width in `--muted` in the second, the value in the third.
- A 1-bit input is a 22px round knob (`button`, `aria-pressed` as today, `Playground.astro:3430-3434`): HIGH `--accent` fill with the `1` glyph in `--bg`; LOW `--accent` outline (1px) with the `0` glyph in `--fg`; unknown — which the README does not draw — a dashed `--muted` outline with `?` in `--muted`, the state `.pg-data-toggle[data-signal="2"]` already draws (`global.css:1330`), carried into the circle.
- A bus input is a field: `background: var(--code-bg); border: 1px solid var(--border); border-radius: 4px; text-align: right; min-width: 64px`, the commit-on-Enter, restore-on-Escape, commit-on-blur behaviour of today's `.pg-data-in` (`Playground.astro:3396-3417`), `aria-invalid` on a refusal, `?` for unknown, the console's value grammar through `editRow` → `parsePinValue` (`data-view.ts:73`).
- An output is a read-only value: `font-weight: 700; text-align: right`.
- Footer: `edits settle the circuit and echo in the console` in `--muted` · **Reset** in `--accent`, wired to today's reset path (`Playground.astro:3454-3463`: `sim.pins.clear()` then `session.reset()`, disabled while it runs).
- `site/src/scripts/data-panel.ts`: `DEFAULT_POS`, `PANEL_WIDTH = 312`, `clampPanel`, `positionFromDrag`, `DRAG_THRESHOLD = 4`.
- The drag: pointer capture on the grip (the splitter's idiom, `splitter.ts:175-203`), a 4 CSS px threshold before the card moves (a click on the grip that never crosses it does nothing), `Escape` while dragging restores the position the drag started from, `pointercancel` restores, `pointerup` commits through `store.update` (debounced 500 ms, `playground-store.ts:478-485`).
- The envelope: `dataOpen: boolean` and `dataPanel: Record<PickId, { x: number; y: number }>` under version 2, defaults `false` and `{}`; `normalizeDataPanel` drops entries whose id is not a catalogue or scratch shape or whose numbers are not finite; the panel's position is read on open and clamped to the region on every open and every region resize.
- The canvas region takes `padding-right: 344px` while the card is open (`[data-data-open="true"]` on the region), and the Live view refits through the hook Phase 2 leaves (the `fit()` call after a mount resize).
- The `Data` button: filled `--accent` on `--bg` while open (`aria-expanded`), outline otherwise; its count `N → M` unchanged.
- `loadProject` closes the panel when `activeId` changes (`Playground.astro:1080-1105`, beside `consoleNewSession()`), and the next open reads `dataPanel[newId]` or the default.
- Below 800px (decision 15): the card is `position: static; width: auto`, a block under the canvas region's toolbar, the region's `padding-right` not applied; the drag is inert (the grip hidden).
- Removal of the Data tab's markup (`Playground.astro:218-228`), its `dataNote`/`dataHead`/`dataEl`/`dataReset` selectors (`:511-514`) re-pointed at the card's elements, and the `.pg-data-*` rules (`global.css:1281-1331`) rewritten for the card.
- `island-smoke.test.ts` updated: the card's elements found by their new selectors (`:273-280` today).

**Explicitly deferred:**
- Resizing the card; docking it to the left; more than one card.
- Keyboard-moving the card (arrow keys on the grip) — `TODO(phase5)` below.
- Any change to `data-view.ts` and its test.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/data-panel.ts` | Pure geometry: `DEFAULT_POS`, `PANEL_WIDTH`, `DRAG_THRESHOLD`, `clampPanel(pos, size, region)`, `positionFromDrag(start, from, to)`, `crossedThreshold(from, to)`. No DOM. |
| site | `site/test/data-panel.test.ts` | The clamp and drag cases below. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/components/Playground.astro` | The card markup replacing `:218-228`; `renderData` builds the two sections instead of a `<table>` (`:3355-3445`); `showData` becomes `setDataOpen(open)`; the drag handlers on the grip; `loadProject` closes the panel; `hooks.onArtifact` hides the card's body when there is no artifact (`:3466-3483`), keeping the note. |
| site | `site/src/utils/playground-store.ts` | `dataOpen`, `dataPanel` on `PlaygroundEnvelope`; defaults in `defaultEnvelope()`; `normalizeDataPanel`; both read in `normalize`. |
| site | `site/src/styles/global.css` | `.pg-data-*` rewritten for the card (`:1281-1331`); the region's `[data-data-open="true"] { padding-right: 344px }`; the `@media (max-width: 800px)` block (`:2042-2060`) gains the static card. |
| site | `site/test/playground-store.test.ts` | The two fields default, persist, and normalise. |
| site | `site/test/island-smoke.test.ts` | The card's selectors; the Data button's `aria-expanded`. |
| site | `site/test/bench-tokens.test.ts` | Holds unchanged: every colour in the new rules is a token, the shadow is the allowed `rgba(0,0,0,…)`. |
| site | `DOCS/decisions/playground-bench.md` | Decisions 14 and the parts of 5, 8, 9 and 15 this phase exercises. |

**New dependencies:** None.

## Data & State

```ts
// site/src/utils/playground-store.ts — added under STORE_VERSION 2 (decision 5)
export interface PanelPos { x: number; y: number }   // CSS px from the canvas region's top-left
export interface PlaygroundEnvelope {
  // …fields of Phases 1–2 unchanged…
  dataOpen: boolean;                       // default false
  dataPanel: Record<PickId, PanelPos>;     // default {}; one entry per project the reader moved it in
}
```

```ts
// site/src/scripts/data-panel.ts
export const PANEL_WIDTH = 312;
export const DRAG_THRESHOLD = 4;           // CSS px, the renderer's own press-to-pan threshold
export interface Size { width: number; height: number }
export interface Rect extends Size { x: number; y: number }   // the canvas region, in its own coordinates x = y = 0
/** The design's anchor, as a position: right 16px under a 52px top, for a region of the given width. */
export function defaultPos(region: Size): PanelPos;          // { x: region.width - 16 - PANEL_WIDTH, y: 52 }
/** Keep the whole card inside the region; a region narrower or shorter than the card pins the card to the top-left. */
export function clampPanel(pos: PanelPos, size: Size, region: Size): PanelPos;
/** Where the card goes for a pointer that started at `from` and is now at `to`, from the card's position at the press. */
export function positionFromDrag(start: PanelPos, from: PanelPos, to: PanelPos): PanelPos;
export function crossedThreshold(from: PanelPos, to: PanelPos): boolean;   // Chebyshev distance ≥ DRAG_THRESHOLD
```

Island state (module-scope in `init`, not persisted): `dataDrag: { pointerId: number; from: PanelPos; start: PanelPos; moved: boolean } | null`; `dataShape` stays the rows' signature (`Playground.astro:3353`), now over the two sections. The rendered position is `dataPanel[activeId] ?? defaultPos(region)`, clamped; only a committed drag writes the record.

## Execution & Concurrency Model

This phase is synchronous on the main thread. The drag is three pointer listeners and one key listener on the grip, with pointer capture so a fast drag over the canvas never reaches the renderer's own navigation (`splitter.ts:180-182` for the same reason). A `ResizeObserver` on the canvas region re-clamps the rendered position on resize and never commits, the splitter's rule (decision 6 in spirit). Reset stays the one asynchronous path (`session.reset()`, `sim-session.ts:370-382`), guarded by the button's disabled state as today; the `rebuilt` event re-renders the rows (`Playground.astro:3237-3247`). No worker or timer is added; the store's own 500 ms debounce batches the position write.

## Persistence & I/O

Two envelope fields under the one localStorage key (`STORE_KEY`, `playground-store.ts:17`), written through `store.update` and the existing debounce and quota handling; a record for a project that no longer exists is dropped by `normalizeDataPanel` on the next read. Nothing else is read or written; no network.

## Slices

The execution agent implements this phase one slice at a time; from Phase 3 on a slice is committed without asking and the agent stops only before the first slice of a new phase (plan prompt, Working Loop).

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The geometry module and the envelope fields | `data-panel.ts` with `defaultPos`, `clampPanel`, `positionFromDrag`, `crossedThreshold`; `dataOpen` and `dataPanel` in the store with `normalizeDataPanel`; no island change. | `data-panel.test.ts` (all cases); `playground-store.test.ts` gains the fields' default, round-trip, and normalisation cases; `bun test` green. |
| 2 | The card replaces the tab | The card markup and rules; `renderData` builds the sections; the knob, the field and the output as specified; footer hint and Reset; `setDataOpen` on the `Data` button with `aria-expanded` and the filled state; `✕` and `Escape` close; the `.pg-panel[data-panel="data"]` markup and `.pg-data table` rules removed; the region's `padding-right` and refit. | `bun --bun run build` then `island-smoke.test.ts` (card found, tab gone, `aria-expanded` toggles); `sim-transcripts.test.ts` and `data-view.test.ts` unchanged and green; board 3d compared by eye in both themes; `bun run bundle` numbers in STATUS. |
| 3 | The drag and the memory of it | Grip drag with threshold, `Escape`/`pointercancel` restore, commit through the store; per-project position on open; `loadProject` closes the panel; `ResizeObserver` re-clamp; the narrow layout's static card. | `island-smoke.test.ts`: a synthetic `pointerdown`/`pointermove`/`pointerup` on the grip moves the card and the envelope records it; a project switch closes it; `bun test` green. |
| 4 | Record | `DOCS/decisions/playground-bench.md` entries; STATUS with the bundle numbers and the screenshot names. | `bun test`, `bun --bun run typecheck`, `bun --bun run build`, `bun run bundle` all green. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `defaultPos anchors the card 16px from the right under a 52px top` | `data-panel.test.ts` | `defaultPos({ width: 900, height: 600 })` is `{ x: 572, y: 52 }`. |
| `clampPanel leaves a card that fits where it is` | `data-panel.test.ts` | `{ x: 100, y: 80 }` with a 312×400 card in 900×600 is unchanged. |
| `clampPanel pulls a card back from the right and bottom edges` | `data-panel.test.ts` | `{ x: 700, y: 500 }` becomes `{ x: 588, y: 200 }`. |
| `clampPanel pins to the top-left when the region is smaller than the card` | `data-panel.test.ts` | A 200×300 region yields `{ x: 0, y: 0 }`, never a negative. |
| `clampPanel never returns a negative` | `data-panel.test.ts` | `{ x: -40, y: -10 }` becomes `{ x: 0, y: 0 }`. |
| `positionFromDrag adds the pointer delta to the start` | `data-panel.test.ts` | Start `{ 100, 100 }`, from `{ 10, 10 }`, to `{ 25, 5 }` → `{ 115, 95 }`. |
| `crossedThreshold is false under 4px and true at it` | `data-panel.test.ts` | `(0,0)→(3,3)` false; `(0,0)→(4,0)` true. |
| `dataOpen and dataPanel default and round-trip` | `playground-store.test.ts` | `defaultEnvelope()` has `false` and `{}`; a written envelope with `{ 'scratch:abc': { x: 10, y: 20 } }` reads back equal. |
| `dataPanel drops an unknown project and a non-finite number` | `playground-store.test.ts` | `{ 'nope': { x: 1, y: 2 }, 'example:nand': { x: 'a', y: 2 } }` normalises to `{}` — `TODO(phase5)`: decide whether an `example:`/`tour:` id is validated against the catalogue (the store does not hold it; `normalize` today only checks `scratch:` ids against `scratch`, `playground-store.ts:259-262`) or only against the id shape of `idKind` (`:577`). Recommended: the id shape. |
| `a missing field is filled from the default` | `playground-store.test.ts` | A version-2 envelope without `dataOpen`/`dataPanel` normalises with the defaults and no note. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `the Data button opens a card and the tab is gone` | `island-smoke.test.ts` | `.pg-data-card` exists and is `hidden` at boot; `.pg-panel[data-panel="data"]` is null; clicking the `Data` button flips `aria-expanded` and the region's `data-data-open`. |
| `a grip drag moves the card and is remembered` | `island-smoke.test.ts` | Synthetic pointer events across the threshold change the card's `style.left`/`top`; `store.envelope.dataPanel[activeId]` holds the clamped position after `flush()`. |
| `switching projects closes the card` | `island-smoke.test.ts` | Open the card, pick another project: `hidden` is true and `dataOpen` is false. |
| `an edit still echoes in the console` | `sim-transcripts.test.ts` (unchanged) | The executor's transcript is byte-identical; the island's `commandFor` path is untouched. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun test test/island-smoke.test.ts && bun run bundle`

## Open Questions / Spikes

- `TODO(phase5)`: whether the grip takes arrow keys to move the card 8px (and 32px with Shift) for a keyboard reader. The splitter has such steps (`splitter.ts:213-222`); the card can be closed and reopened without moving it, so nothing is unreachable without this. Recommended: add it if slice 3 finishes under budget, else record it as a papercut.
- `TODO(phase5)`: which id shapes `normalizeDataPanel` accepts (see the unit test above).
- `TODO(phase5)`: the `ResizeObserver` and the Live view's refit both fire on the same region resize; confirm in slice 2 that the refit hook Phase 2 shipped debounces to one `fit()` per frame, or coalesce here.
