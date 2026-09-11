# Phase 6 — The drawer

> **Dependencies:** Phase 0 (the frame's third row as the closed 40px terminal line, `terminal-line.ts` with `summaryOf(transcript)`, `--danger` guarded by `bench-tokens.test.ts`); Phase 1 (the envelope at version 2, `normalize` filling a missing field from `defaultEnvelope()`); Phase 2 (the drawer no longer follows an output tab: the third row is always on screen, so `setDrawerShown` and `showTab`'s `setDrawerShown(tab === 'simulate' || tab === 'data')` at `Playground.astro:659` are already gone).
> **Warnings:** Decisions 4, 5 and 6 of the plan prompt are authoritative. Every console decision in `DOCS/decisions/playground.md` (`:304`, `:312`, `:376`, `:384`, `:392`, `:400`, `:264`) survives this phase unchanged; the phase restyles the drawer and moves no behaviour. The design file wins over the README (decision 2): the board's drawer row is `320px` (`Playground Upgrade.dc.html`, `grid-template-rows: 48px minmax(0, 1fr) 320px 24px`), its console header `34px`, its caret `7px × 14px`, its split `minmax(0, 1fr) 1px 560px`. Copy in the board (`peek lut 0x4`, `lut.hex · 5 words`, `12 ms`) is illustrative.

## Goal

A reader who focuses or clicks the one-line terminal sees it grow to a 320px drawer without the bench above it reflowing anywhere but in height: the console on the left is the same terminal, dressed as board 3c draws it, with its tab, its command title, its three ghost actions and a `▾` that shrinks it back; when the program declares a `rom` or a `ram`, a hairline splits the drawer and a 560px memory panel sits on the right, headed by the memory's name and shape, a `live` chip and the value base, with one toolbar of paging, jump, Refresh, Clear, Load image… and Save above an eight-column grid whose address column sits on `--pane-label-bg`, whose unknown words read as `?`, whose addressed word is picked out in the accent colour, and whose cell under edit carries the accent underline. The drawer's height is the reader's, dragged on the drawer splitter and remembered per envelope. Every reply, echo and comment is the executor's text, coloured by the stylesheet and nothing more; every write and clear still goes through the session and lands in the log as the line that would have done it.

## Scope

**In scope:**
- The drawer as row 3 of the frame, open: the row's track becomes `var(--pg-drawer-h)` clamped, the closed line's `40px` otherwise; `data-open` on `.pg-drawer` decides which. Grow on focus within or click on the closed line; shrink on the console header's `▾`, on `Escape` from the prompt when the line is empty (`Playground.astro:944-948` already clears the line on `Escape`; a second `Escape` on an empty line closes), and on the closed line's `Console ▴` toggle.
- The drawer splitter converted from a share of the output pane (`--pg-split-drawer`, `Playground.astro:2530-2542`, `global.css:1050`) to pixels of the drawer: `createSplitter` gains a pixel mode writing `--pg-drawer-h`, clamped `[160, region − 200]` on render and never on commit; `drawerHeight` persisted under version 2 (decision 5).
- The `minmax(0, 1fr) 1px 560px` split of the open drawer only while `currentRoms()` (`Playground.astro:1780`) is non-empty; otherwise the console is the whole row. `memVisible()` (`:1852`) is rewritten to read the open state and the declared set, not a selected tab.
- The console header at `34px`: the `Console` tab label with the accent underline (decorative now — one panel, not a tablist), the command title (`.pg-console-title`, `:544`, `consoleHandshake` at `:853`), Clear · Copy script · Copy log as ghost text (`.pg-console-btn`, unchanged `data-console` values and handlers at `:874-892`), and the `▾`. The log at `--font-mono-strict 12.5px / 1.5`, the prompt row with a `7px × 14px` accent caret block beside the `>` glyph.
- The memory panel restyled on `--pane-bg`: header (`Memory` label, name in `--fg`, `rom[8,4] · 16 words` in `--muted`, `live` outline chip in `--accent` while `cellsFor(mem).live`, hex/bin/dec segmented writing `settings.valueFormat` through the settings `set` at `:2425`); toolbar (`◂ 0x0 – 0xf ▸` from `pageNav` `:2102`, `jump 0x__` from the same, Refresh = `renderMemory({ force: true })` `:2003`, Clear = `clearMemory` `:2366`, Load image… = today's hex escape hatch `hexEditor` `:2054` opened by a button rather than a checkbox, Save = `saveMemoryImage` `:2354`); the grid at `40px repeat(8, 1fr)` with a `+0 … +7` header row, the address column on `--pane-label-bg` with a right rule, cells `3px 8px` centred; the legend line and the image line under it.
- The addressed word: `addressedWord(runtime, memId)` in `memory-panel.ts`, the value on the memory's `addr` port, read as `runtime.readValue(source)` (`circ-renderer/src/wasm/runtime.ts:293`) of the component the topology wires into that port (`runtime.topology`, `:243`); the matching cell gets `data-addressed`.
- The `.pg-drawer-bar`, `.pg-drawer-tabs`, `.pg-drawer-tab`, `.pg-drawer-count`, `.pg-drawer-toggle` markup (`Playground.astro:244-277`) and rules (`global.css:1052-1108`) removed; `DrawerTab`, `currentDrawerTab`, `selectDrawerTab`, `drawerTabs`, `drawerPanels`, `drawerToggle`, `memTab`, `memCount` (`:538-552`, `:725-770`) removed with them.
- `island-smoke.test.ts` rewritten where it walks the strip (`:223-257`, `:350-362`); `terminal-line.test.ts` extended; `playground-store.test.ts` extended; `splitter.test.ts` extended.
- `DOCS/decisions/playground-bench.md` entries for the drawer; `DOCS/sim-protocol.md:230-235` reread (the Memory tab is now the memory panel).

**Explicitly deferred:**
- Files through the console (`LOAD_REFUSAL`, `SAVE_REFUSAL`, `console.ts:100-101`) stay refused; the panel is the file surface, and the refusal wording is retouched only to name the panel.
- A memory panel for more than one declared memory beside the console: the board draws one. Two or more stack inside the 560px column as `.pg-mem-item` does today (`global.css:891-892`), each with its own header and toolbar; no tabs, no picker.
- Any change to `formatWord`, `dumpRows`, `parseWord`, `parseAddress`, or `MEM_PER_ROW` (`Playground.astro:1796`, already 8).
- The narrow layout (decision 15): below 800px the drawer opens in place and the split becomes a stack; nothing else.

## File & Module Topology

**New files:** None. (`terminal-line.ts` is Phase 0's; this phase extends it.)

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/components/Playground.astro` | Drawer markup: the strip (`:244-277`) replaced by the console header inside `.pg-console` and a `.pg-drawer-mem` column; `.pg-drawer-panel` wrappers gone; `role="tabpanel"` and `aria-labelledby` gone. Island: `setDrawerOpen` keeps `data-open` and the separator's `hidden`; `memVisible` reads `drawer.dataset.open === 'true' && currentRoms().length > 0`; `updateMemTab` becomes `updateMemColumn` (sets `data-mem` on `.pg-drawer` and rebuilds the panel); `renderOneMemory` rebuilt in the board's order (header, toolbar, grid, legend, image line, error line); the drawer splitter created in pixel mode with `initial: store.envelope.drawerHeight`, `onCommit` writing `draft.drawerHeight`. The closed line's `Console ▴` toggle and the header's `▾` both call `setDrawerOpen`. |
| site | `site/src/scripts/splitter.ts` | `SplitterOptions.minPanePx: number \| [number, number]` (per pane); `SplitterOptions.pixels?: { property: string; pane: 'first' \| 'second' }` — render writes the chosen pane's size in CSS px to that property instead of the ratio; `effectiveBounds` takes the pair; `onCommit` and `onChange` receive `{ ratio, px }`. The ratio path is byte-for-byte what it was (the main splitter of Phase 0 keeps using it). |
| site | `site/src/scripts/terminal-line.ts` | `summaryOf` unchanged; add `memoryHeader(mem, total)` (`rom[8,4] · 16 words`), `legendFor(mem, addr)` (the legend line's three clauses), `imageLine(mem, meta)` (`image · <file> · N words`, or `no image · the rom starts undefined`, or for a ram `contents live in the circuit`). Pure strings the island writes. |
| site | `site/src/scripts/memory-panel.ts` | `addressedWord(runtime: RuntimeLike, memId: number): number \| null` — `null` while the `addr` value is not fully defined, else the address as a number. `RuntimeLike` is `Pick<CircRuntime, 'topology' \| 'readValue'>` so the test passes a stub. |
| site | `site/src/utils/playground-store.ts` | `PlaygroundEnvelope.drawerHeight: number` (default `320`); `defaultEnvelope()` and `normalize` fill it; `layout.ratios.drawer` dropped by the version-2 reader (it was the share; a stored share has no pixel meaning). |
| site | `site/src/styles/global.css` | `.pg-drawer*` (`:1035-1150`) rewritten: the row's track, the open split (`grid-template-columns: minmax(0, 1fr) 1px 560px` under `[data-mem]`), the console header, the caret, the memory column; `.pg-mem*` (`:887-1032`) rewritten to the board: header, chip, segmented base, toolbar, `40px repeat(8, 1fr)` grid, `data-addressed`, `data-editing`, legend and image lines. The console line kinds (`:1224-1230`) untouched. |
| site | `site/test/island-smoke.test.ts` | The strip walk (`:223-257`) rewritten to the header and the memory column; `:350-362` (the drawer follows the output tab) replaced by "the drawer grows on focus and shrinks on `▾`, and the memory column appears with a declared memory". |
| site | `site/test/splitter.test.ts` | `effectiveBounds` with a `[160, 200]` pair; pixel mode writes `px`, clamps, and never commits on resize. |
| site | `site/test/terminal-line.test.ts` | The three new string helpers. |
| site | `site/test/memory-panel.test.ts` | `addressedWord` on a stub topology: a pin driving `addr` directly, a slice between, an undefined address. |
| site | `site/test/playground-store.test.ts` | `drawerHeight` defaulted, kept, clamped by nothing (the splitter clamps on render), and a version-1 `ratios.drawer` dropped without a note. |
| docs | `DOCS/decisions/playground-bench.md`, `DOCS/sim-protocol.md` | The drawer's entries; "Memory tab" reworded. |

**New dependencies:** None.

## Data & State

```ts
// playground-store.ts — version 2, this phase's field
export interface PlaygroundEnvelope {
  // …Phase 1's fields…
  /** The open drawer's height in CSS px, the reader's last drag. Clamped on
   *  render by the splitter, never here: a small window borrows, it does not
   *  overwrite. */
  drawerHeight: number; // default 320
}

// splitter.ts
export interface SplitterOptions {
  // …
  /** One minimum for both panes, or `[first, second]`. */
  minPanePx?: number | [number, number];
  /** Write the pane's size in px to `property` instead of the ratio. */
  pixels?: { property: string; pane: 'first' | 'second' };
  onChange?: (v: { ratio: number; px: number }) => void;
  onCommit?: (v: { ratio: number; px: number }) => void;
}

// memory-panel.ts
export type RuntimeLike = Pick<CircRuntime, 'topology' | 'readValue'>;
/** The address the memory is reading now, or null while any bit of it is unknown. */
export function addressedWord(runtime: RuntimeLike, memId: number): number | null;

// terminal-line.ts
export function memoryHeader(mem: MemorySymbol, total: number): string; // `rom[8,4] · 16 words`
export function legendFor(mem: MemorySymbol, addressed: number | null): string;
export function imageLine(mem: MemorySymbol, meta: { file: string | null; words: number } | null): string;
```

Island state that stays: `MEM_PAGE = 64`, `MEM_PER_ROW = 8`, `memWindows`, `romImplied`, `hexOpen` (`Playground.astro:1795-1804`); `consoleState` (`:773-786`). The drawer's `data-open` is the open flag; `[data-mem]` on `.pg-drawer` is the split flag, written by `updateMemColumn` on every analysis, as `updateMemTab` is called today (`:1831`).

DOM contract, open drawer (the smoke test's map):

```
.pg-drawer[data-open][data-mem?]
  .pg-console                       (--code-bg)
    .pg-console-head                (34px)  .pg-console-tab · .pg-console-title · .pg-console-actions[data-console=clear|script|log] · .pg-drawer-close (▾)
    .pg-console-note  .pg-console-log[aria-live=polite]  .pg-console-form (.pg-console-prompt › .pg-console-caret · .pg-console-in)
  .pg-drawer-rule                   (1px, --border; only with [data-mem])
  .pg-drawer-mem > .pg-mem > .pg-mem-item*   (--pane-bg; only with [data-mem])
    .pg-mem-head    .pg-mem-tab · .pg-mem-name · .pg-mem-shape · .pg-mem-live[data-live] · .pg-mem-base[role=radiogroup]
    .pg-mem-tools   .pg-mem-nav (◂ range ▸ jump) · .pg-mem-btn[data-mem=refresh|clear|load|save]
    .pg-mem-table   thead (addr, +0…+7) · tbody (th.pg-mem-addr · td.pg-mem-cell[data-unknown|data-implied|data-addressed|data-editing])
    .pg-mem-error[role=alert]  .pg-mem-legend  .pg-mem-image  (.pg-mem-hex when Load image… is open)
```

## Execution & Concurrency Model

This phase is fully synchronous. No worker, timer or observer is introduced beyond the splitter's existing `ResizeObserver` (`splitter.ts:274`), which re-clamps `--pg-drawer-h` and never commits. The console's `busy` gate (`Playground.astro:896-917`) and the session's event listeners are untouched; `renderMemory`'s typing guard (`:1867-1883`) still decides whether a session event may rebuild the grid, and `memVisible()` still keeps every word read off the wasm boundary while the drawer is closed. Growing the drawer calls `renderMemory()` once, as `setDrawerOpen` does today (`:749`).

## Persistence & I/O

`drawerHeight` joins the envelope under `STORE_KEY` (`circ.playground.v1`, version 2), written through `store.update` on the splitter's commit and read at mount; no other storage. `Save` still downloads `<mem>.bin` through `downloadBytes` (`:1747`); `Load image…` still reads a chosen file through `imageFromBytes` (`:2083-2097`) and the hex area through `setImage` (`:2209`). The clipboard actions are unchanged (`consoleCopy`, `:865`). No network.

## Slices

The execution agent implements this phase one slice at a time, committing each per the Working Loop (Phase 3 onward: commit per slice, ask per phase).

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The splitter learns pixels | `splitter.ts`: `minPanePx` pair, `pixels` mode, `{ ratio, px }` callbacks; the ratio path unchanged. | `splitter.test.ts`: `effectiveBounds(600, { minPanePx: [200, 160], … })` yields `min = 200/600`, `max = 1 − 160/600`; pixel mode on a 800px container at ratio 0.6 writes `320px` for the second pane; a resize to 400px renders `200px` (the `region − 200` clamp) and fires no commit; the existing ratio tests byte-identical. |
| 2 | The drawer grows and shrinks | The row-3 track on `--pg-drawer-h`; `setDrawerOpen` on focus within the closed line, click, `Console ▴`, `▾`, empty-line `Escape`; the drawer splitter in pixel mode writing `--pg-drawer-h`; `drawerHeight` in the envelope, `ratios.drawer` dropped. | `playground-store.test.ts`: default `320`; a version-1 envelope with `layout.ratios.drawer: 0.62` normalizes to `drawerHeight: 320` with no note. Smoke: after `focus()` on the prompt the drawer has `data-open="true"` and the separator is not hidden; after clicking `.pg-drawer-close` it is closed and the separator hidden. |
| 3 | The console dressed as the board | `.pg-console-head` at 34px with tab, title, ghost actions, `▾`; the log at 12.5px / 1.5; the caret block; the strip markup and rules removed with `DrawerTab` and its functions. | Smoke `:223-257` rewritten: no `.pg-drawer-tabs`; `.pg-console-head .pg-console-btn` data values still `['clear', 'script', 'log']`; the title still matches `/^circ-compile \S+\.circ --sim$/`; `console.test.ts` untouched and green. `bench-tokens.test.ts` green over the new rules. |
| 4 | The memory column | `[data-mem]` split; `updateMemColumn`; `memVisible` rewritten; the header (name, `memoryHeader`, `live` chip, base segmented) and the toolbar mapped one control to one existing function. | `terminal-line.test.ts`: `memoryHeader({ kind: 'rom', width: 8, addrWidth: 4 }, 16)` is `rom[8,4] · 16 words`. Smoke: with the shipped rom example picked, `.pg-drawer` has `data-mem` and one `.pg-mem-item`; with `nand`, neither. `memory-panel.test.ts` "reading and writing a running memory" green through the same `poke`/`clear`. |
| 5 | The grid, the addressed word, the two lines | The `40px repeat(8, 1fr)` grid with its header row; `data-addressed` from `addressedWord`; `data-editing` on the cell `editCell` opens; the legend and image lines from `legendFor`/`imageLine`; `Load image…` opening `hexEditor` below the grid. | `memory-panel.test.ts`: `addressedWord` with a pin wired to `addr` returns its value; through a slice returns the slice's output; an undefined address returns `null`. `terminal-line.test.ts`: `legendFor` names `0x3` when addressed and omits the clause when `null`; `imageLine` for the three cases. Smoke: the `+0 … +7` header row; a rom example's `th.pg-mem-addr` texts are `0`, `8`; after an edit through the cell the `.pg-mem-error` is empty. |
| 6 | Record | `DOCS/decisions/playground-bench.md` entries (the drawer is a row, not a tab strip; the splitter's pixel mode; the addressed word from the topology; the image line), `DOCS/sim-protocol.md:230-235` reworded, STATUS with `bun run bundle` numbers for `/playground`. | All four gates green: `bun test`, `bun --bun run typecheck`, `bun --bun run build`, `bun run bundle`. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `a pair of minimums bounds each pane by its own` | `site/test/splitter.test.ts` | `effectiveBounds` with `[first, second]`; a container too small for both collapses to `{0.5, 0.5}` as today. |
| `pixel mode writes the pane in px and re-clamps on resize without committing` | `site/test/splitter.test.ts` | The property holds `Npx`; `onChange` carries `px`; a resize fires no `onCommit`. |
| `the ratio path is what it was` | `site/test/splitter.test.ts` | Every existing assertion, unchanged. |
| `drawerHeight defaults, keeps, and replaces the share` | `site/test/playground-store.test.ts` | Default `320`; a stored `480` survives `normalize`; a version-1 `ratios.drawer` is dropped without a note. |
| `memoryHeader, legendFor, imageLine` | `site/test/terminal-line.test.ts` | The three strings for a rom and a ram, addressed and not, with and without an image. |
| `addressedWord reads the addr port's source` | `site/test/memory-panel.test.ts` | Direct pin, through a slice, undefined → `null`; never reads a memory word. |
| `formatWord/dumpRows/parseWord` | `site/test/memory-panel.test.ts` | Unchanged; the eight-per-row layout is `dumpRows(read, win, 8, …)` as today. |
| `every colour in a .pg-drawer or .pg-mem rule is a token` | `site/test/bench-tokens.test.ts` | Phase 0's guard, over this phase's rules. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `the drawer grows on focus and shrinks on ▾` | `site/test/island-smoke.test.ts` | `data-open` and the separator's `hidden` flip; the source column's width is the same before and after (no reflow above the row). |
| `the console header carries the three actions and the title` | `site/test/island-smoke.test.ts` | Data values, title pattern, the note and the disabled prompt before a session. |
| `a declared memory splits the drawer; none leaves the console whole` | `site/test/island-smoke.test.ts` | `[data-mem]` present for the rom example and absent for `nand`; the header, toolbar buttons (`refresh`, `clear`, `load`, `save`), the `+0 … +7` row. |
| `the transcript goldens replay` | `site/test/sim-transcripts.test.ts` | Unchanged and green: nothing in this phase touches the executor or the session. |
| `reading and writing a running memory` | `site/test/memory-panel.test.ts` (libcirc) | Unchanged and green. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle` (the smoke needs the build first; `SKIP_LIBCIRC_TEST=1` skips the wasm-backed groups).

## Open Questions / Spikes

- `TODO(phase6):` `--danger` already exists in `global.css:42` (light `#a83737`) and `:74` (dark `#ff6b8a`) and is read by `.pg-mem-error`, `.pg-rom-error`, `.pg-dock-badge`, `.pg-mem-input[aria-invalid]`. Decision 4's "`--danger` joins them (`#e5484d`, both modes)" is therefore a change of value, not an addition; the Phase 0 slice that touches the token must choose the existing pair or the handoff's one and say so in STATUS. This phase reads whichever Phase 0 left.
- `TODO(phase6):` the board's memory header has hex/bin/dec beside the `live` chip and the Data panel (Phase 5) has the same segmented control; both write `settings.valueFormat`, so the two must stay in step through the settings `set` path (`Playground.astro:2425-2445`, which already re-runs the preview and the table and re-spells the canvas). The slice confirms the memory grid re-renders from that path (`renderMemory` is not called there today; `applyToView` is not the right hook) and adds the call.
- `TODO(phase6):` a 64-bit word in binary is 64 characters; eight across in a 560px column overflow. Today's table scrolls on its own axis (`global.css:970-979`); the board's grid is `1fr` columns. The slice keeps the horizontal scroll inside `.pg-drawer-mem` and lets the `1fr` columns take `min-content`, so the address column stays sticky (`:980-988`) and the drawer never widens. If the board's look cannot survive that at width 64, STATUS records the fallback: `repeat(8, minmax(max-content, 1fr))`.
- `TODO(phase6):` whether `Escape` on an empty prompt should close the drawer, or only the header's `▾` and the closed line's toggle. The decision at `DOCS/decisions/playground.md:392` gives `Escape` to clearing the line; a second `Escape` closing is an addition. Ship it only if the smoke test can show the first `Escape` still clears and resets the history cursor.
