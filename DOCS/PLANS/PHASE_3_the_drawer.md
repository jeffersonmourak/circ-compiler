# Phase 3 — The drawer

> **Dependencies:** Phase 1 (the Data tab exists to dock under), Phase 2 (the executor).
> **Warnings:** Decisions 3, 4, 5, 6, 8 and 12. The console prints the executor's lines and nothing of its own except its prompt echo and its help; anything it adds to the transcript would be a line a reader cannot paste into a test. The Memory panel moves; it does not change what it does, except for one new button.

## Goal

Under the Simulate tab and under the Data tab there is a drawer with two tabs. **Console** shows the session's handshake the moment the session is built, takes a protocol line at its prompt, prints the exact reply, keeps a hundred lines of history on ↑/↓, clears on `Ctrl+L`, and answers `load` and `save` with a reply that points at the other tab. **Memory** is the panel that used to live in the editor's dock, with its grid, its image box, its file load, and now a save button that downloads the image the circuit holds. The drawer's height follows a splitter and is remembered; the editor's dock has two tabs left. `quit` prints `ok bye` and resets the session. Switching between Simulate and Data keeps the drawer, its tab, the transcript and the history. `DOCS/sim-protocol.md` says what the browser does differently.

## Scope

**In scope:**
- `Playground.astro`: the `.pg-drawer` region below the panels (a strip with the two tabs and a collapse toggle; one body), shown only while `state.tab` is `simulate` or `data`; the Memory panel's markup and handlers moved into the Memory tab; the memory dock tab and its deferred logic removed from the editor dock; the console's markup and its prompt loop; the session wiring (`rebuilt` → a fresh handshake after a `# reset` line; `destroyed` → `# session ended`).
- `site/src/scripts/splitter.ts` reused for the drawer's height (`layout.ratios.drawer`), vertical.
- `site/src/scripts/console.ts` (pure): `HistoryRing`, `Transcript`, `MemoryTabFiles implements FileSource` (refuses every read and write with the tab's message), `promptEcho`, `helpLines`.
- `site/src/utils/playground-store.ts`: `DockTab` becomes `'diagnostics' | 'settings'`; `DOCK_TABS` follows; the `ratios.drawer` key needs no change (the record accepts any key, clamped like the others).
- The Memory tab's save button: `session.storeImage(name)` → a download named `<mem>.bin`, through the same Blob path `pg-download` uses.
- `site/test/console.test.ts`; `island-smoke.test.ts` (dock two tabs, drawer two tabs, drawer hidden on `preview`); `playground-store.test.ts` (`dock.tab: 'memory'` falls back to `diagnostics`); `memory-panel.test.ts` unchanged.
- `DOCS/sim-protocol.md`: the section "The protocol in the browser".
- CSS in `global.css`: the drawer, its strip, the console; the app-layout rule that gives the output pane a vertical split.

**Explicitly deferred:**
- Files through the console; persisting history, transcripts or the drawer's tab.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/console.ts` | History, transcript buffer, the refusing file source, the echo and help text. |
| site | `site/test/console.test.ts` | Over plain values. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/components/Playground.astro` | The drawer, the Memory panel's move, the console, the second splitter, the dock's memory tab removed. |
| site | `site/src/utils/playground-store.ts` | `DockTab` without `memory`. |
| site | `site/src/styles/global.css` | Drawer and console styles; the output pane's vertical split. |
| site | `site/test/island-smoke.test.ts` | Dock strip `['diagnostics', 'settings']`; drawer strip `['console', 'memory']`; drawer hidden on `preview`. |
| site | `site/test/playground-store.test.ts` | The dock fallback. |
| site | `DOCS/sim-protocol.md` | The browser section. |
| site | `DOCS/decisions/playground.md` | Entries for decisions 3, 5, 6, 8 (and 4 if not written in Phase 2). |

**New dependencies:** None.

## Data & State

```ts
// console.ts
export class HistoryRing { constructor(cap = 100); push(line: string): void; up(): string | null; down(): string | null; reset(): void; }
export class Transcript { constructor(cap = 2000); append(lines: readonly string[]): void; clear(): void; readonly text: string; }
/** The page's FileSource: every path is the Memory tab's business. */
export class MemoryTabFiles implements FileSource {
  read(path: string): { ok: false; error: 'load images in the Memory tab' };
  write(path: string, bytes: Uint8Array): { ok: false; error: 'save images from the Memory tab' };
}
export const promptEcho = (line: string) => `> ${line}`;
export function helpLines(): string[];   // the command table, one `# ` comment line per verb; `help` is a browser-only verb
```

The executor formats a refused read as `err E_IO <path>: load images in the Memory tab` and a refused write as `err E_IO <path>: save images from the Memory tab`, the same `E_IO <path>: <error>` shape the CLI uses for a file it cannot open, so the line is still one a reader can read as protocol.

Island: the drawer holds one `Transcript`, one `HistoryRing`, one `MemoryTabFiles`; on `Enter` the console appends the echo, runs `execute(session, files, line)`, appends the replies, scrolls to the end and announces the last reply through the existing `role="status"` span. With no session the prompt is disabled and the scrollback shows the gating sentence. On `rebuilt` the console prints `# reset` and the handshake again. The Memory tab's visibility follows `currentRoms().length > 0` as the dock tab's did; when it hides while selected, the strip falls back to Console without writing anything.

Envelope: `dock.tab` of `'memory'` in a stored envelope normalises to `'diagnostics'`; `layout.ratios.drawer` is the drawer's fraction of the output pane, defaulting to the CSS's initial height when absent.

## Execution & Concurrency Model

`execute` is awaited per line; the prompt is disabled while a line runs (a `reset` rebuilds the canvas) and re-enabled after. The Memory tab's file load is the existing async `FileReader` path; its save is synchronous.

## Persistence & I/O

`layout.ratios.drawer` persists through the store's existing ratio path. The save button downloads through an `<a download>` Blob URL revoked after the click, as `pg-download` does. Nothing else is stored.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The pure parts | `console.ts` and its tests. | History wraps at 100 and `up` past the oldest stays; `down` past the newest yields the empty line; `Transcript` drops its oldest lines at the cap; `MemoryTabFiles` refuses both ways with the two messages; the executor formats them as `err E_IO <path>: …` (one executor test over a stub session). |
| 2 | The drawer and the Memory tab's move | The region, its strip, the second splitter, the panel moved, the dock tab removed, `DockTab` narrowed, the save button, CSS. | `island-smoke.test.ts` and `playground-store.test.ts` updated and green; typecheck, build, bundle; the human loads and saves an image on `rom-lookup` from the drawer. |
| 3 | The console | Prompt loop over the executor, the handshake on build, history, clear, `quit`, the gating, `# reset`. | `island-smoke.test.ts`: the console's prompt and scrollback exist; the human runs the definition of done's `eval` on `four-bit-adder` and `load code x.bin` and reads the pointer to the tab. |
| 4 | The document | `DOCS/sim-protocol.md`'s browser section: `load`/`save` as the Memory tab's, `help`, `quit`, preloads from the Memory tab, no line-length cap, the handshake's file name. | `bun run sync` regenerates the reference page; the human reads it. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `history is a ring of a hundred lines` | `console.test.ts` | Cap, up/down bounds, reset after a submit. |
| `the transcript keeps its newest lines` | same | Cap behaviour, `clear`. |
| `the page's file source points at the Memory tab, protocol-shaped` | `sim-executor.test.ts` | `load code x.bin` → `err E_IO x.bin: load images in the Memory tab`; `save` likewise. |
| `a stored memory dock tab falls back` | `playground-store.test.ts` | `dock.tab: 'memory'` → `'diagnostics'`. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `island-smoke.test.ts` | built page | Dock strip two tabs; drawer strip two tabs; drawer hidden on `preview`; the prompt and scrollback exist. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- `TODO(phase3)`: whether the console's scrollback should mark `err` lines visually — a `data-kind` per line for CSS, never a change to the text. Slice 3 adds the attribute.
- `TODO(phase3)`: the vertical splitter. `splitter.ts` was written for the horizontal editor/output divider; slice 2's first task is to confirm its axis is a parameter or to add one, keeping its keyboard and `ResizeObserver` behaviour.
