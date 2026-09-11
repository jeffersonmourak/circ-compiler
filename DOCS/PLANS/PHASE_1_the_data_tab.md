# Phase 1 — The Data tab

> **Dependencies:** Phase 0 (the session, its events, `pins`).
> **Warnings:** Decisions 7, 8 and 11. Values on this tab are spelled the site's way, through the renderer's `parsePinValue`/`formatPinValue` in `settings.valueFormat`; the console's protocol spelling is Phase 2's and does not appear here. `island-smoke.test.ts` asserts the tab strip's exact list; it changes in this phase.

## Goal

A reader opens the Data tab on `four-bit-adder` and sees `a`, `b`, `cin` as editable values and `sum`, `cout` as read values, in the base the settings drawer says. Typing `0xA` into `a` and pressing Enter drives the circuit; `sum` updates in the same tick, and the Simulate tab's canvas, if built, shows the same pins. A width-1 input toggles with one click. A value too wide for its pin, or not a value, is refused with a sentence and the field keeps the reader's text. A reset button returns every pin to unknown with the ROM images re-applied. The tab shows the same two sentences Simulate shows when there is no artifact, and the Memory dock works on it.

## Scope

**In scope:**
- `site/src/utils/playground-store.ts`: `OutputTab` gains `'data'`; `OUTPUT_TABS` follows; `normalize` unchanged in shape.
- `Playground.astro`: the `Data` tab button and panel (`data-tab="data"`, `data-panel="data"`), a `.pg-data-note` for the gating sentences, a `.pg-data` table region, a reset button; `showTab('data')` ensures the session (not the canvas) and renders; session events re-render.
- `site/src/scripts/data-view.ts` (pure): `rowsFor`, `editRow`, `toggleRow`, `describeError`.
- `site/test/data-view.test.ts`; `island-smoke.test.ts` updated for four tabs; `playground-store.test.ts` updated for the tab value.
- CSS for the table in the `[data-layout='app']` block and the general block, following the truth-table's `.pg-table`.

**Explicitly deferred:**
- The drawer (Phase 3): the console and the Memory panel's move under this tab.
- A per-bit editor, a history of values, a waveform.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/data-view.ts` | Rows from a session, edits into it, errors as sentences. |
| site | `site/test/data-view.test.ts` | Over the Phase 0 stub session. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/utils/playground-store.ts` | `'data'` in `OutputTab` and `OUTPUT_TABS`. |
| site | `site/src/components/Playground.astro` | Tab, panel, render on events, reset, gating. |
| site | `site/src/styles/global.css` | `.pg-data` table styles. |
| site | `site/test/island-smoke.test.ts` | `['preview', 'truth', 'simulate', 'data']`. |
| site | `site/test/playground-store.test.ts` | `tab: 'data'` round-trips; an unknown tab still falls back to `preview`. |
| site | `DOCS/decisions/playground.md` | Entry for decision 7 (and 8 if not written in Phase 0). |

**New dependencies:** None.

## Data & State

```ts
// data-view.ts
export interface DataRow {
  name: string;
  kind: 'in' | 'out';
  width: number;
  /** formatPinValue(value, format): '?' unknown, 'x' per unknown bit, else the base. */
  text: string;
  /** For a width-1 input: 0, 1 or 2 (unknown), for the toggle. */
  signal: 0 | 1 | 2;
}
export function rowsFor(session: SessionLike, format: ValueFormat): DataRow[];
/** Parse the reader's text for the pin and drive it. */
export function editRow(session: SessionLike, name: string, text: string, format: ValueFormat): { ok: true } | { ok: false; message: string };
/** A width-1 input: unknown → 1, 1 → 0, 0 → 1. */
export function toggleRow(session: SessionLike, name: string): { ok: true } | { ok: false; message: string };
export function describeError(code: SimError, arg: string): string;
```

`SessionLike` is the subset of `SimSession` the view uses (`pins`, `get`, `set`), so the test drives it with the Phase 0 stub. `editRow` parses with `parsePinValue(text, width, format)` (the renderer's; `?` and empty mean unknown, `x` bits are unknown bits, `0x`/`0b` override the base) and refuses a parse failure with the renderer's reason before touching the session; a session refusal (`E_WIDTH` cannot happen after parsing to the width, but `E_NOTIN`/`E_NOPIN` can if the artifact drifted) becomes a sentence through `describeError`.

Island: the panel renders one `<table class="pg-data">` with a row per pin: name, width badge, and either an `<input>` (bus input), a toggle `<button>` (width-1 input) or a `<span>` (output). Inputs commit on `Enter` and on `blur`; `Escape` restores the current value. Rendering is a full rebuild except when a field inside the table has focus and nothing structural changed, the same rule `renderMemory` applies.

Gating: the note reads `Compile a circuit first.` (no artifact after a file-set change) or `Fix the errors to simulate.` (a failing build), taken from the same branch that sets `simNote`; when `state.simulateEnabled` is false the note carries the same version-skew sentence.

## Execution & Concurrency Model

Synchronous rendering on session events (`drive`, `memory`, `rebuilt`) and on `settings.valueFormat` changes. `showTab('data')` calls `ensureSession()` (async, guarded by the artifact hash as Simulate is) and renders when it resolves; a tab switch away during the await leaves the built session in place for the other faces.

## Persistence & I/O

`tab: 'data'` persists in the envelope like the other tabs. Nothing else.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The tab value | `OutputTab`, `OUTPUT_TABS`, store test. | `playground-store.test.ts`: `'data'` survives `normalize`; `'console'` falls back to `preview`. |
| 2 | Rows and edits | `data-view.ts` and its tests. | Rows in pin order with `?` before any drive; `0xA` into a 4-bit pin drives `0xa/0xf`; `x` bits become mask bits; `0x1F` into a 4-bit pin is refused with the renderer's reason and no drive; toggle cycles `? → 1 → 0 → 1`; outputs are read-only. In all three bases. |
| 3 | The panel | Tab, panel, table, reset, gating, CSS; render on events. | `island-smoke.test.ts` with four tabs; typecheck, build, bundle; the human drives `four-bit-adder` from the tab and watches the canvas follow. |
| 4 | The dock on the tab | The Memory dock (still in the editor dock until Phase 3) renders whenever a session exists, from either tab. | The human loads `rom-lookup`'s image from the dock while on Data and reads `out` in the table. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `rows follow the pins, inputs then outputs, in the reader's base` | `data-view.test.ts` | Order, kinds, widths, `?` at start, `0b1010` / `0xA` / `10` per base. |
| `an edit parses the site's way and drives the session` | same | `set` called with `(0xan, 0xfn)`; `x` bits → mask. |
| `a refused edit drives nothing and says why` | same | Parse failure message; `calls` empty. |
| `a width-1 input toggles` | same | The three transitions. |
| `the store accepts the data tab` | `playground-store.test.ts` | Round trip and fallback. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `island-smoke.test.ts` | built page | Four tabs, `data` last, not selected by default. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- `TODO(phase1)`: whether the Data tab should also list memories (name, shape, addressed word). The dock already shows them; the tab lists pins only unless the review asks.
- `TODO(phase1)`: the tab's name. The plan says **Data**; the button reads `Data`, the panel's heading is none (the other panels have none).
