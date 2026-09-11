# Phase 3 — The console

> **Dependencies:** Phase 1 (the Data tab exists to dock under), Phase 2 (the executor).
> **Warnings:** Decisions 3, 4, 5, 6 and 12. The console prints the executor's lines and nothing of its own except its prompt echo and its help; anything it adds to the transcript would be a line a reader cannot paste into a test.

## Goal

Under the Simulate tab and under the Data tab, one console shows the session's handshake the moment the session is built, takes a protocol line at its prompt, prints the exact reply, keeps a hundred lines of history on ↑/↓, clears on `Ctrl+L`, and lets a reader drop a `.bin` on it so `load code prog.bin` reads it and `save data out.bin` downloads it. `quit` prints `ok bye` and resets the session. Switching between the two tabs keeps the transcript and the history. `DOCS/sim-protocol.md` says what the browser does differently.

## Scope

**In scope:**
- `Playground.astro`: the `.pg-console` region below the panels (header with a title, a drop hint, a toggle; a `<pre class="pg-console-out">` scrollback; an `<input class="pg-console-in">` prompt), shown only while `state.tab` is `simulate` or `data`; the drop and pick handlers; wiring to the session's `rebuilt`/`destroyed` events (a new handshake, a `# session ended` comment line respectively).
- `site/src/scripts/console.ts` (pure): `HistoryRing`, `Transcript` (a bounded line buffer, 2,000 lines), `DropBox implements FileSource` (a `Map<string, Uint8Array>` with the 16 MiB cap, `write` handing bytes to an injected `download(name, bytes)`), `promptLine(line)` (the echo format `> <line>`), `helpLines()`.
- `site/test/console.test.ts`.
- `DOCS/sim-protocol.md`: the section "The protocol in the browser".
- CSS in `global.css` for the console (monospace, the pane colours, the scrollback's height, the app-layout rule that keeps it inside the output pane).

**Explicitly deferred:**
- Persisting history or transcripts; scripting; a file picker for `save` (it downloads).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/console.ts` | History, transcript buffer, the drop box, the echo and help text. |
| site | `site/test/console.test.ts` | Over plain values; the drop box over an injected download. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/components/Playground.astro` | The region, its handlers, the session wiring, `showTab` toggling visibility. |
| site | `site/src/styles/global.css` | Console styles. |
| site | `site/test/island-smoke.test.ts` | The console region exists, is hidden on `preview`, and has the prompt and scrollback. |
| site | `DOCS/sim-protocol.md` | The browser section. |
| site | `DOCS/decisions/playground.md` | Entries for decisions 3, 5, 6 (and 4 if not written in Phase 2). |

**New dependencies:** None.

## Data & State

```ts
// console.ts
export class HistoryRing { constructor(cap = 100); push(line: string): void; up(): string | null; down(): string | null; reset(): void; }
export class Transcript { constructor(cap = 2000); append(lines: readonly string[]): void; clear(): void; readonly text: string; }
export class DropBox implements FileSource {
  constructor(download: (name: string, bytes: Uint8Array) => void, cap = 16 * 1024 * 1024);
  add(name: string, bytes: Uint8Array): void;      // a dropped or picked file
  names(): string[];
  read(path: string): FileSource['read'] extends (p: string) => infer R ? R : never; // FileNotFound | FileTooBig
  write(path: string, bytes: Uint8Array): { ok: true };  // hands to download
}
export const promptEcho = (line: string) => `> ${line}`;
export function helpLines(): string[];   // the command table, one line per verb, printed for `help` — a browser-only verb, echoed as a comment block
```

Island: the console holds one `Transcript`, one `HistoryRing`, one `DropBox`; on `Enter` it appends the echo, runs `execute(session, dropBox, line)`, appends the replies, scrolls to the end and announces the last reply through the existing `role="status"` span. `help` and a bare `load <mem>` (which opens a file picker and then runs `load <mem> <chosen name>`) are the two browser-only forms, both documented. With no session (no artifact) the prompt is disabled and the scrollback shows the gating sentence. On `rebuilt` the console prints the handshake again, preceded by `# reset`.

Visibility: `showTab` sets `console.hidden = !(tab === 'simulate' || tab === 'data')`; the region is a sibling of the panels inside `.pg-output`, so it stays put when the tab changes. Its own toggle collapses it to its header; the state is a field on the island, not the envelope.

## Execution & Concurrency Model

`execute` is awaited per line; the prompt is disabled while a line runs (a `reset` rebuilds the canvas) and re-enabled after. A file drop is synchronous into the drop box; a file pick resolves asynchronously and then runs the `load`.

## Persistence & I/O

The drop box is memory; `save` downloads through an `<a download>` Blob URL revoked after the click, as the `.wasm` download button does (`pg-download`). Nothing is stored.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The pure parts | `console.ts` and its tests. | History wraps at 100 and `up` past the oldest stays; `down` past the newest yields the empty line; `Transcript` drops its oldest lines at the cap; `DropBox.read` of a missing name is `FileNotFound`, over the cap is `FileTooBig`; `write` calls `download` once with the name. |
| 2 | The region | Markup, CSS, visibility by tab, the prompt loop over the executor, the handshake on build, the gating. | `island-smoke.test.ts`: the region exists, hidden on `preview`; typecheck, build, bundle; the human runs the definition of done's `eval` on `four-bit-adder`. |
| 3 | Files and reset | Drop and pick into the drop box, `save` as a download, `quit`/`reset` re-handshake. | The human drops `rom_pc_walk.bin` on `rom-lookup` and runs `load code rom_pc_walk.bin`, `mem code 0 4`, `save code out.bin`; `reset` returns the canvas to unknowns. |
| 4 | The document | `DOCS/sim-protocol.md`'s browser section: the drop box, the bare `load`, `help`, `quit`, preloads from the dock, no line-length cap, the handshake's file name. | `bun run sync` regenerates the reference page; the human reads it. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `history is a ring of a hundred lines` | `console.test.ts` | Cap, up/down bounds, reset after a submit. |
| `the transcript keeps its newest lines` | same | Cap behaviour, `clear`. |
| `the drop box is a file source` | same | `FileNotFound`, `FileTooBig`, `write` → download. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `island-smoke.test.ts` | built page | The console's region, prompt and scrollback exist; hidden on `preview`. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- `TODO(phase3)`: whether the console's scrollback should mark `err` lines visually (a class per line kind) — a colour, never a change to the text. Slice 2 adds a `data-kind` attribute per line for CSS; the text stays the transcript.
- `TODO(phase3)`: the picker for a bare `load <mem>` uses an `<input type="file">` the island creates on demand; happy-dom cannot exercise it, so it is the human's to try in slice 3.
