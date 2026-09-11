# Phase 0 — The log of every face

> **Dependencies:** None (the playground driver is archived and in the tree).
> **Warnings:** Decisions 1, 2, 3 and 4. `sim-executor.ts`, `sim-protocol.ts` and `site/test/sim-transcripts.test.ts` are read-only; every slice must leave the four goldens byte for byte. Read the island's `// ---- the console ----` section, `ensureSession`'s listener, `buildCanvas`'s `onPinChange`, and the Memory panel's `writeLiveWord`, `clearMemory`, `setImage` and `applyToView` before writing a line. The page must behave exactly as before except for the new lines in the console.

## Goal

Every drive that reaches the session from a face other than the console leaves the line in the console that typing it would have left, with the reply the session gave. On `four-bit-adder`, clicking `a` on the canvas prints `> set a 0x1` and `ok`; toggling `b` on the Data tab prints `> set b 0x1` and `ok`; typing `0xa` into `a` prints `> set a 0xa` and `ok`; a value typed as `?` prints `> set a 0x0 0x0`. On `ram-write-read`, writing `0x5a` at address 2 in the Memory tab's grid prints `> poke data 0x2 0x5a` and `ok`, and its Clear prints `> clear data` and `ok`. On `rom-lookup`, editing the image prints `# code: image from the Memory tab, 4 words`. Pressing the Data tab's Reset prints `> reset`, `ok` and the handshake, exactly as typing `reset` does; the `# reset` comment is gone. A line typed at the prompt still appears once. The Memory panel no longer touches the runtime directly.

## Scope

**In scope:**
- `site/src/scripts/sim-session.ts`: `DriveAssign`; `SessionEvent.drive` gains `assigns`; `SessionEvent.memory` gains `op`, `addr`, `value`, `defined`, `words`; `notifyExternal(assigns)`; `applyPreloads({ silent })` emitting a `load` or `clear` per applied image only when not silent (`build` and `reset` apply silently); `loadImage` emits `load` with `words`.
- `site/src/scripts/console.ts`: `commandFor(event, session)`.
- `Playground.astro`: `onPinChange` passes the value; the listener echoes page events with `data-origin="page"` unless `consoleState.busy`; `> reset` replaces `# reset`; `writeLiveWord` → `session.poke`, RAM `clearMemory` → `session.clear`; `applyToView` calls `applyPreloads()` loud.
- `site/test/sim-session.test.ts` (event payloads, silent preloads at build and reset, loud from a face), `site/test/console.test.ts` (`commandFor`), `site/test/sim-session-artifact.test.ts` if an assertion on events exists there (none today).
- `DOCS/decisions/playground.md`: entries for decisions 1–4 at the phase's close.

**Explicitly deferred:**
- The terminal look, `Copy script`, the document (Phase 1).
- Logging anything that is not a drive (hover, tab switches, selection).

## File & Module Topology

**New files:** None.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/scripts/sim-session.ts` | `DriveAssign`; richer `drive` and `memory` events; `notifyExternal(assigns)`; `applyPreloads({ silent })`; `loadImage` words in the event. |
| site | `site/src/scripts/console.ts` | `commandFor`. |
| site | `site/src/components/Playground.astro` | `onPinChange` values; the listener's echo; `> reset`; the Memory panel through the session; `applyToView` loud. |
| site | `site/test/sim-session.test.ts` | Event shapes; preload events silent at build and reset, loud from `applyPreloads()`. |
| site | `site/test/console.test.ts` | `commandFor` over every event shape and mask case. |
| site | `DOCS/decisions/playground.md` | Decisions 1–4. |

**New dependencies:** None.

## Data & State

```ts
// sim-session.ts
export interface DriveAssign { name: string; value: bigint; defined: bigint }

export type SessionEvent =
  /** Pins were driven, by any face; `names` is `assigns.map(a => a.name)`. */
  | { kind: 'drive'; names: readonly string[]; assigns: readonly DriveAssign[] }
  /** A memory's contents changed. `poke`: one cell; `clear`: every cell; `load`: an image of `words` words. */
  | { kind: 'memory'; name: string; op: 'poke'; addr: bigint; value: bigint; defined: bigint }
  | { kind: 'memory'; name: string; op: 'clear' }
  | { kind: 'memory'; name: string; op: 'load'; words: number }
  | { kind: 'rebuilt' }
  | { kind: 'destroyed' };

notifyExternal(assigns: readonly DriveAssign[]): void;   // the canvas's path; values as the canvas drove them
applyPreloads(opts?: { silent?: boolean }): ApplyResult;  // build and reset pass { silent: true }; a face's call is loud

// console.ts
/** The lines the console prints for a page-originated event: echoes with their replies, or a comment. */
export function commandFor(event: SessionEvent, session: Pick<SimSession, 'pins' | 'mems'>): string[];
```

`commandFor`'s spelling, per decision 2: `drive` → for each assign, `> set <name> <writeHex(value)>` followed by `ok`, with ` <writeHex(defined)>` appended to the `set` when `defined !== widthMask(width)` (width from `session.pins`; a name not among the pins is spelled with the mask always, never dropped); `memory` `poke` → `> poke <mem> <writeHex(addr)> <writeHex(value)>[ <writeHex(defined)>]` then `ok` (width from `session.mems`); `clear` → `> clear <mem>`, `ok`; `load` → `# <mem>: image from the Memory tab, <words> word(s)`; `rebuilt` → `> reset`, `ok` (the island appends the handshake); `destroyed` → `[]` (the island prints `# session ended` as today). Values are canonical: `value & defined` before spelling, as `readPin` and the executor do.

`applyPreloads` derives its events from the plan it applied: for each name in `ApplyResult.applied`, the plan's write with `bytes === null` is a `clear`, otherwise a `load` of `bytes.length / bytesPerWord(width)` words.

Island: the session listener, on `drive` or `memory` with `!consoleState.busy`, appends `commandFor(event, session)` with `data-origin="page"` on each span; on `rebuilt` with `!consoleState.busy`, appends `commandFor` (`> reset`, `ok`) then the handshake; while busy, `rebuilt` is deferred as today and only the handshake is printed after the reply (the `> reset` and its `ok` came from the executor). `consoleAppend` gains an `origin` argument (`'prompt' | 'page'`, default `'prompt'`).

## Execution & Concurrency Model

Synchronous. Session events are emitted synchronously inside the mutator, so a page echo lands in the log before the mutator returns; the console's own `execute` sets `busy` before the mutator runs, so its events are not echoed twice. `reset` stays async and deferred as in Phase 3 of the driver plan.

## Persistence & I/O

None beyond what prior phases established.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Events with their details | `DriveAssign`, the event shapes, `notifyExternal(assigns)`, `applyPreloads({ silent })`, `loadImage` words; the island's `onPinChange` passing values; `sim-session.test.ts` updated. | `set a 1` emits `drive { names: ['a'], assigns: [{ a, 1n, 1n }] }`; `eval` one event with two assigns; `poke` emits `{ op: 'poke', addr, value, defined }`; `clear` `{ op: 'clear' }`; `loadImage` `{ op: 'load', words: 4 }`; `build` and `reset` emit no `load`; a face's `applyPreloads()` emits one `load` per image and a `clear` for an emptied one; the four transcripts unchanged. |
| 2 | The Memory panel through the session | `writeLiveWord` → `session.poke`, RAM `clearMemory` → `session.clear`; status sentences kept; no `host.writeMemWord`/`host.clearMem` left in the island. | `grep -c 'host.writeMemWord\|host.clearMem' Playground.astro` → 0; `island-smoke.test.ts`'s memory-grid case green (it writes a rom, which stays an image edit); the human writes a RAM cell and clears it on `ram-write-read`. |
| 3 | `commandFor` | The function and its tests. | Every event shape; a full mask omitted, a partial mask kept, an unknown pin `0x0 0x0`; `value & defined` canonical; a `load` comment; `rebuilt` → `> reset`, `ok`; `destroyed` → `[]`. |
| 4 | The echo on the page | The listener's echo with `data-origin="page"`, `> reset` for `# reset`, `applyToView` loud. | `island-smoke.test.ts` unchanged and green (nothing prints at mount); the human sees the definition of done's lines on the page, each typed line once. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `every drive carries what was driven` | `sim-session.test.ts` | `set`, `eval`, `notifyExternal` payloads. |
| `memory events say what changed` | same | `poke`/`clear`/`loadImage` payloads. |
| `preloads are silent at build and reset, loud from a face` | same | No `load` at build or reset; one per image from `applyPreloads()`. |
| `commandFor spells the protocol line and its reply` | `console.test.ts` | The table in Data & State. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `the four --sim transcripts replay byte for byte` | `sim-transcripts.test.ts` | Unchanged and green. |
| `island-smoke.test.ts` | built page | Unchanged and green. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- `TODO(phase0)`: the canvas's `onPinChange` reports one component id; `rootInputs(session)` maps names to ids one to one for root pins, so one assign per event. Confirm at slice 1 that a bus pin's drive from the bus dialog also arrives through `onPinChange` with the full `PinValue` (it did in the driver plan's Phase 0 review).
- `TODO(phase0)`: whether a page `drive` of a pin already at that value (a canvas click that toggled and toggled back within one event is not possible; a Data-tab commit of the same text is) should still log. It should: the reader did it, and the CLI would have printed `ok`.
