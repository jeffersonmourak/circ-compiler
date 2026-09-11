# Phase 3 — Schematic and Truth

> **Dependencies:** Phase 2 (the canvas region with the view switch, `View = 'schematic' | 'live' | 'truth'` in the envelope, the region's top-right toolbar slot and bottom-right line; the Live view on the session). Phase 1 (the footer that hosts the settings form this phase edits).
> **Warnings:** Decisions 2, 7, 10 and 11 of the plan prompt. Two premises of the handoff fail against the code and are settled below, not reopened in a slice: (a) there is no `unicode | ascii` setting — `--preview` renders box-drawing glyphs only (`lib/preview/render.zig:16-25`, `RenderOptions { color, stdout_handle, no_color_value, expand_display }`; `optionsFor('preview')` sends `color`, `expand_macros`, `expand_display`, `warnings_as_errors`, `settings-drawer.ts:48-55`); (b) the `format` setting (`table | markdown | csv`, `Playground.astro:162-166`) is sent on every truth request (`settings-drawer.ts:58`) while `runTruth` always `JSON.parse`s the reply (`Playground.astro:2973`), and `libcirc.wasm` does return markdown or CSV text for those values (probed through `callOp`), so the Truth tab throws today under either setting. This phase pins the table request to `json` and makes the copy buttons the format choice.

## Goal

The canvas region has two more faces beside Live. On Schematic, the region turns to `--code-bg` with no dot grid and shows `--preview`'s text centred in the strict mono at 20px, with the two preview settings and a Copy button in the top-right and the text's `rows × cols chars` in the bottom-right. On Truth, the compiler's table sits in a card on the dot grid, its header cells still lighting the schematic and the editor, the row that matches the session's pins tinted, a click on any row driving every root input through the session (and so echoed in the console), a chip in the toolbar carrying the input-bit count, the row count, the cap and, when the reader is blocked, why; `Copy as markdown` and `CSV` put the compiler's own spelling on the clipboard. Over the cap the table still opens: the site enumerates the unknown input bits on a scratch session, holds the known pins, and says so in the chip. Every cell, from either path, is spelled by the renderer's `formatPinValue` in the reader's base, so the table and the Data panel never disagree about a value.

## Scope

**In scope:**
- The Schematic view: surface swap, the `<pre>`, the toolbar (Expand macros · Expand display as a toggle pair, Copy), the size line; `.pg-preview` restyled; `runPreview` unchanged in what it requests (`Playground.astro:2926-2939`).
- The Truth view: `truth-view.ts` (parse, spell, match, enumerate, render to text); the card and its rules; the live-row tint; the row click of decision 11; the chip; the two copy buttons; the request pinned to `format: 'json'`; the `format` select removed from the settings form.
- The over-cap path of decision 10 on a scratch `SimSession`.
- `island-smoke.test.ts` updated for the two views; `DOCS/decisions/playground-bench.md` entries for decisions 7 (as amended here), 10 and 11.

**Explicitly deferred:**
- An ASCII charset for `--preview`. It needs a `RenderOptions` field and a documented libcirc option key; that is a compiler slice in another initiative. The toolbar carries the two preview settings that exist (`TODO(phase3)` below).
- A fixed-input option in `lib/truth_table/builder.zig` (`build`, `:136-200`, enumerates every root input bit). The site path of decision 10 stands in for it.
- A truth table for a circuit with a `ram`: the compiler refuses it (`lib/libcirc/modes.zig:104`, `truthTablePreflight :149`), and so does the site path.
- Dropping `format` from `PlaygroundSettings` and the store's normaliser. The field stays, unread, until the sweep; only its control and its use in the request go.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/truth-view.ts` | The Truth view as a pure module: `parseTruthTable`, `cellText`, `liveRowIndex`, `unknownInputs`, `rowsForPins`, `chipText`, `toMarkdown`, `toCsv`. Imports `formatPinValue`/`widthMask` from `circ-renderer`, so it enters the graph beside `data-view.ts`, behind the island's dynamic import (`data-view.ts:12-14`). |
| site | `site/test/truth-view.test.ts` | Unit cases on a stub session (`sim-stub.ts`) and one integration case through `libcirc.wasm`, skipped under `SKIP_LIBCIRC_TEST=1` like `sim-session-artifact.test.ts:12`. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/components/Playground.astro` | Markup: the Schematic toolbar and size line, the Truth toolbar (chip, copy buttons), the table card; `#pg-tab-tip-truth` and its tooltip rules gone (the chip carries the gate). Script: `runTruth` (`:2952-3004`) rewritten on `truth-view.ts`; `applyTruthGate` (`:636-652`) writes the chip and the switch's `aria-disabled`; `truthBlock` (`:613-626`) unchanged; the over-cap branch; the row click; the copy handlers on `copyText` (`:1647`) and `flash` (`:1666`); `runPreview` writes the size line. The `format` select (`:160-166`) removed. |
| site | `site/src/scripts/settings-drawer.ts` | `optionsFor('truth_table', s, preloads, format = 'json')`: the table always asks for `json`; a copy asks for `markdown` or `csv`. `DOCUMENTED_OPTION_KEYS` unchanged. `capRefusal` (`:77-83`) keeps its sentence; the chip shortens it (see Data & State). |
| site | `site/src/styles/global.css` | `.pg-preview` (`:1263-1269`) and `.pg-table*` (`:1270-1273`) replaced by the bench rules; `.pg-tab-tip` (`:690-720`) deleted; the `.pg-th-linked` rule (`:1259-1266`) kept, restated on the card. Every colour a token (Phase 0's `bench-tokens.test.ts`). |
| site | `site/test/island-smoke.test.ts` | `:284-288` (the tooltip) replaced by the chip; the view walk of Phase 2 gains Schematic and Truth. |
| site | `site/test/settings-drawer.test.ts` | `optionsFor` cases for the pinned `json` and the two copy formats. |
| site | `DOCS/decisions/playground-bench.md` | Decisions 7 (amended), 10, 11, and the `format` finding. |

**New dependencies:** None.

## Data & State

```ts
// site/src/scripts/truth-view.ts
import { formatPinValue, type BitValue, type ValueFormat } from 'circ-renderer';
import type { SessionLike } from './data-view.ts';   // pins, get, set — data-view.ts:20-24

/** A column as the compiler names it: `name` or `name[W]` (lib/truth_table/json.zig:31). */
export interface Column { name: string; width: number; }
/** One cell: fully defined as a bigint, else null (json.zig:58-71 emits null for any undefined bit). */
export type Cell = bigint | null;
export interface TruthRows {
  inputs: Column[];
  outputs: Column[];
  rows: { in: Cell[]; out: Cell[] }[];
}

/** The compiler's JSON (`{inputs, outputs, rows:[{in,out}]}`, Playground.astro:490) parsed:
 *  a number becomes a bigint; a hex string (json.zig:44-56, uppercase, sent under
 *  value_format 'hex') is read with BigInt('0x' + s). The width is the header suffix. */
export function parseTruthTable(text: string): TruthRows;
export function columnOf(header: string): Column;          // headerSymbolName + the suffix

/** The renderer's spelling: `formatPinValue({ value, defined: widthMask(w), width: w }, format)`,
 *  `?` for null. The compiler's JSON prints decimal under 'binary' (json.zig:74), which is
 *  why the site spells every cell itself. */
export function cellText(cell: Cell, width: number, format: ValueFormat): string;

/** The row whose input cells equal the session's input pins, or -1 when any input
 *  pin is not fully defined or no row matches. Columns and pins line up by position:
 *  both are the root inputs in declaration order (lib/engine_session.zig via
 *  builder.zig `session.inputs`; sim-session.ts:153-163 `collectPins`). */
export function liveRowIndex(table: TruthRows, pins: readonly { name: string; value: BitValue }[]): number;

/** The input pins with any undefined bit, in declaration order, with their widths. */
export function unknownInputs(session: SessionLike): { name: string; width: number }[];

export type ScratchOutcome =
  | { ok: true; table: TruthRows; filtered: true; unknownBits: number }
  | { ok: false; reason: 'over-cap' | 'stateful'; unknownBits: number };

/** Decision 10. Enumerate 2^k assignments over the unknown input bits (k = the sum of
 *  their widths) on `scratch`, holding every known pin at the live session's value;
 *  refuse with 'over-cap' when k > cap and 'stateful' when the scratch has a ram.
 *  Rows come back in the compiler's order (low pin first, json.zig:79-90). */
export function rowsForPins(
  scratch: SessionLike & { mems: readonly { kind: 'rom' | 'ram' }[] },
  live: SessionLike,
  cap: number,
): ScratchOutcome;

export interface ChipInput {
  bits: number | null;           // rootInputBits(), Playground.astro:2941-2950
  rows: number | null;           // rows on screen
  cap: number;                   // settings().truthTableCap
  blocked: string | null;        // truthBlock(), or null
  filtered: boolean;             // the over-cap path is on screen
  unknownBits?: number;
}
/** `N input bits · R rows · cap C`, then ` · filtered to the current pins` or
 *  ` · over the cap: K unknown bits` or the blocked sentence's first clause. */
export function chipText(c: ChipInput): string;

/** The compiler's shapes, for the over-cap rows only: lib/truth_table/markdown.zig and
 *  csv.zig (`| a[4] | b[4] | r[4] |` with a dash rule; `a[4],b[4],r[4]` then values). */
export function toMarkdown(table: TruthRows, format: ValueFormat): string;
export function toCsv(table: TruthRows, format: ValueFormat): string;
```

The island's `runTruth` becomes:

```
refusal = truthBlock()                       // errors first, then the cap (settings-drawer.ts:107-118)
if refusal is an error refusal → card shows it, chip blocked
else if bits > cap → scratch path: ensure the live session; build a scratch
      SimSession over sim.bytes with the same roms/images (no bootLow); rowsForPins;
      render; chip filtered; the scratch is destroyed after the rows are read
else → client.call('truth_table', requestFor(files, optionsFor('truth_table', settings(), preloads())))
      → parseTruthTable → render; chip
```

Rendering is one `<table>` inside `.pg-truth-card`: `th[data-symbol-name]` as today (`Playground.astro:2976-2990`, the hover/focus links kept); `tr[data-row]` with `tabindex="0"`, `Enter` and click driving; `td` classes `pg-truth-high`/`pg-truth-low`/`pg-truth-unknown` from the cell; the live row `aria-current="true"`. The tint follows the session: on every `drive` event (`Playground.astro:3228-3239`) the view recomputes `liveRowIndex` and moves `aria-current`; no click sets it directly (decision 11).

The row click drives through the session: for each input column `i`, `session.set(inputs[i].name, cell, widthMask(width))` (`sim-session.ts:290-296`, which emits `drive` and so reaches the canvas, the Data panel and the console through `commandFor`). A `set` refusal is shown in the status line through `describeError` (`data-view.ts:50-63`). `sim.pins` is updated for each, as `onPinChange` does (`Playground.astro:3292-3300`), so a rebuilt session replays the row.

The Schematic size line is `${lines} × ${maxWidth} chars` from `previewEl.textContent` split on `\n`. The toolbar's two toggles are bound through `mountSettingsDrawer`'s `set` (`settings-drawer.ts:142-180`, `Playground.astro:2428-2447`) with `data-setting="expandMacros"` and `expandDisplay` on the toolbar controls — the same attribute the footer form uses, so one binding serves both.

Persistence: the view is the envelope's `view` field (Phase 2). Nothing new is stored; the scratch outcome is not cached (a new artifact or a new pin recomputes it).

## Execution & Concurrency Model

The compiler path is the worker call it is today, guarded by `buildStage.isCurrent(seq)` after the await (`Playground.astro:2966`); the reply is dropped when stale. The scratch path runs on the main thread: `CircRuntime` is instantiated on the page by the renderer (`ensureSession`, `Playground.astro:3204-3211`; `libcirc.worker.ts` hosts the front end only and has no runtime), and `SimSession.set`/`get` are synchronous (`sim-session.ts:290-303`). `SimSession.build` is one await for `load`; the enumeration after it is a synchronous loop of at most `2^cap` `set`+`run` calls, the same bound the compiler runs under, with the same warning the settings form already gives (`Playground.astro:175`). The loop is guarded like the reply: if `sim.bytes` moved during the await, the scratch is destroyed and nothing renders. The scratch session subscribes nothing and is destroyed as soon as its rows are read, so it never emits into the console. The live session is read (`get`) and never written by the scratch path; a test asserts it.

## Persistence & I/O

Clipboard through `copyText` (`Playground.astro:1647-1662`: `navigator.clipboard`, else the selected fallback input). Copy as markdown and CSV under the cap are one worker call each with `format` overridden (`optionsFor(…, 'markdown' | 'csv')`), so the bytes are the compiler's; over the cap they are `toMarkdown`/`toCsv` of the rows on screen. The Schematic Copy is `previewEl.textContent`. No other I/O beyond what prior phases established.

## Slices

The execution agent implements this phase one slice at a time. Phase 3 onward commits per slice and asks before the next phase (plan prompt, Working Loop).

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | `truth-view.ts`: parse, spell, match | `parseTruthTable`, `columnOf`, `cellText`, `liveRowIndex`, `chipText`, `toMarkdown`, `toCsv`; `optionsFor`'s `format` parameter pinned to `json` by default; the `format` select removed from the form. | `truth-view.test.ts` cases 1–7; `settings-drawer.test.ts` `truth_table asks for json unless told the copy format`; the libcirc case `toMarkdown of the parsed json equals the compiler's markdown` on `and_gate.circ` and `and_2bit`. |
| 2 | The Schematic view | The region on `--code-bg` without the grid under `[data-view="schematic"]`; `.pg-preview` at `--font-mono-strict 20px / 1.35` centred; the toolbar (two toggles on `data-setting`, Copy); the size line. | `island-smoke`: switching to Schematic marks the region, the toolbar's toggles carry `data-setting`, the size line reads `0 × 0 chars` with no preview; `bench-tokens` green. |
| 3 | The Truth view under the cap | The card, header and cell classes, `th` links as before, the live-row tint moved by `drive` events, the row click of decision 11, the chip with the gate (`applyTruthGate` rewritten; tooltip gone), the two copy buttons. | `island-smoke`: the chip exists and reads `cap 12` with no analysis; a click on a fake row with a stub session drives `set` per input column (the `__playground` seam hands the smoke a `SimSession` over `sim-stub`); `truth-view.test.ts` case 8. |
| 4 | Over the cap | The scratch path: `unknownInputs`, `rowsForPins`, the branch in `runTruth`, the `stateful` refusal, the filtered chip, copy from the rows on screen. | `truth-view.test.ts` cases 9–13, including `the scratch never writes the live session`; a manual walk on the Hack ALU example at cap 4 recorded in STATUS with the row count and the time of the loop. |
| 5 | Record | `DOCS/decisions/playground-bench.md` (7 amended, 10, 11, the `format` finding); `bun run bundle` numbers in STATUS; `DOCS/sim-protocol.md` reread for a Truth mention. | The four gates green; STATUS names the `/playground` raw and gzip before and after. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `parseTruthTable reads numbers and hex strings into bigints` | `truth-view.test.ts` | `{"inputs":["a[4]"],"outputs":["o[4]"],"rows":[{"in":[10],"out":["A"]}]}` yields `10n` and `10n`; `null` stays `null`; `columnOf('a[4]')` is `{ a, 4 }`, `columnOf('a')` is `{ a, 1 }`. |
| `cellText spells in the reader's base` | `truth-view.test.ts` | `10n` at width 4 is `1010` (binary), `A` (hex), `10` (decimal); `null` is `?`. |
| `liveRowIndex matches the compiler's row order` | `truth-view.test.ts` | Two one-bit inputs `a`, `b` with pins `a=1, b=0` select row 1 (low pin first, `json.zig:79-90`); an unknown pin gives -1. |
| `liveRowIndex on a bus` | `truth-view.test.ts` | `a[4]=0b0110` selects the row whose first cell is `6n`. |
| `chipText composes the four parts` | `truth-view.test.ts` | `3 input bits · 8 rows · cap 12`; blocked prefixes the first clause of the refusal; filtered appends ` · filtered to the current pins`. |
| `toMarkdown and toCsv match the compiler's shape` | `truth-view.test.ts` | The header line and rule of `tests/fixtures/truth_table/and_4bit_truth.binary.md.golden`; the CSV header of `and_4bit_truth.hex.csv.golden`. |
| `truth_table asks for json unless told the copy format` | `settings-drawer.test.ts` | `optionsFor('truth_table', s, p).format === 'json'` for every stored `format`; `optionsFor(…, 'csv').format === 'csv'`. |
| `a row click drives every input column through the session` | `truth-view.test.ts` | On `AND_GATE` from `sim-stub.ts`, driving row 3 calls `set:0`, `run`, `set:1`, `run` and `get('out')` reads `1`. |
| `unknownInputs lists the pins with an undefined bit` | `truth-view.test.ts` | A session with `a` low and `b` unknown returns `[b]`; a half-known bus counts as unknown. |
| `rowsForPins enumerates only the unknown bits` | `truth-view.test.ts` | `a=1` known, `b` unknown on `AND_GATE` yields two rows, `in` = `[1,0]`, `[1,1]`, out `0`, `1`. |
| `rowsForPins refuses over the cap and on a ram` | `truth-view.test.ts` | `cap 1` with two unknown bits is `{ ok: false, reason: 'over-cap', unknownBits: 2 }`; a scratch with a `ram` mem is `'stateful'`. |
| `the scratch never writes the live session` | `truth-view.test.ts` | The live stub's `calls` contain no `set:` after `rowsForPins`; the scratch's do. |
| `rowsForPins leaves the scratch as it found it` | `truth-view.test.ts` | Not required: the scratch is destroyed after; the test asserts `destroyed` is set by the island helper. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `toMarkdown of the parsed json equals the compiler's markdown` | `truth-view.test.ts` through `libcirc.wasm` (`callOp`) | For `and_gate.circ` under `binary` and `hex`, `toMarkdown(parseTruthTable(json))` is byte-equal to the `markdown` reply, and `toCsv` to the `csv` reply. |
| `the bench's two compiled views` | `island-smoke.test.ts` | Schematic marks the region `data-view="schematic"`, its toolbar carries `[data-setting="expandMacros"]` and `[data-setting="expandDisplay"]`, the size line exists; Truth shows the chip, no `#pg-tab-tip-truth` remains, `.pg-truth-card` exists. |

Run command: `cd site && bun test truth-view settings-drawer && bun --bun run build && bun test island-smoke && bun --bun run typecheck && bun run bundle`

## Open Questions / Spikes

- `TODO(phase3)`: the `unicode | ascii` control of board 3e. There is no such setting in the compiler or the site (see Warnings). The toolbar ships with the two preview settings that exist; when `--preview` grows a charset option, its libcirc key joins `DOCUMENTED_OPTION_KEYS` and the segmented control takes the slot. Record the gap in `DOCS/decisions/playground-bench.md` under decision 7.
- `TODO(phase3)`: the loop's cost on the main thread at `cap 12` (4,096 `set`+`run` pairs on the ALU). Slice 4 records the time in STATUS; if it passes 100 ms, the deep planner of Phase 7 decides between a `requestIdleCallback` chunking of the loop and a lower default cap for the scratch path. Nothing moves to the worker: it has no runtime.
- `TODO(phase3)`: the `format` field of `PlaygroundSettings` stays in the envelope, unread. Phase 7 drops it, or leaves it as the copy buttons' remembered choice.
