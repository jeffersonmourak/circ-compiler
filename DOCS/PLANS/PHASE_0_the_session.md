# Phase 0 — The session

> **Dependencies:** None
> **Warnings:** Invisible by definition. The page must behave exactly as before this phase: pins clicked, values typed into a bus dialog, ROM images loaded from the dock, hover links into the editor, theme flips, and a recompile that replays the reader's pins by name. Any visible change is a bug in the rewiring. Read `DOCS/PLANS_PROMPT.md` decisions 1, 3, 8 and 9 first, and the island's `// ---- simulate ----` section (`Playground.astro`, from `const sim = {`) and its memory dock (`memHost`, `memIdOf`, `applyToView`, `renderMemory`).

## Goal

The island owns one `SimSession` per compiled artifact, built from the artifact's bytes with the Memory dock's ROM images as preloads. The Simulate canvas is a `CircCanvas` over the session's runtime; a click on it is reported into the session; the Memory dock reads and writes the session's runtime; a new artifact builds a new session and replays the reader's pins by name through it; a cleared artifact destroys it. A test can build a session over a stub runtime and prove every drive, read, width check, preload and notification without a browser, and one test builds it over a real `CircRuntime` from an artifact compiled by the committed `libcirc.wasm`.

## Scope

**In scope:**
- `site/src/scripts/sim-session.ts`: `RuntimeLike`, `PinRef`, `MemRef`, `SimError`, `SimResult<T>`, `SessionInit`, `SimSession` (decision 1), `collectPins`, `collectMems`.
- The session's drive and read surface: `set(name, value, defined)`, `get(name)`, `dump('in' | 'out' | 'all')`, `eval(assigns, queries)`, `run()`, `reset()`, `applyPreloads()`; the memory verbs `mems()`, `peek(mem, addr)`, `poke(mem, addr, value, defined)`, `dumpMem(mem, start?, count?)`, `clear(mem)`, `loadImage(mem, bytes)`, `storeImage(mem)`; `subscribe(listener)`; `destroy()`.
- `Playground.astro` rewired: `sim.session`, the canvas over `session.runtime`, `onPinChange` → `session.notifyExternal(name)`, pin replay through `session.set`, `memHost()` → `session.runtime`, `applyToView()` → `session.applyPreloads()`, artifact hook builds/destroys the session.
- `site/test/sim-session.test.ts` (stub runtime) and the artifact case inside it (real runtime, `SKIP_LIBCIRC_TEST` honoured).

**Explicitly deferred:**
- Any new tab, the console, the protocol text (Phases 1–3).
- Changing what the canvas draws or how the dock renders.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/sim-session.ts` | The session: root pins and memories by name, drives and reads over an injected runtime, preloads, reset, listeners. |
| site | `site/test/sim-session.test.ts` | Stub-runtime unit tests; one integration test over a `CircRuntime` from a compiled artifact. |
| site | `site/test/sim-stub.ts` | `stubRuntime(topology)`: a `RuntimeLike` over a plain map of values, with a `calls` log, for the session and the later executor tests. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/components/Playground.astro` | `sim.view: CircCanvas` over `sim.session.runtime`; `buildSim` → `ensureSession()` + `buildCanvas()`; `rootInputs` deleted (the session's `pins`); `memHost()`, `applyToView()`, `hooks.onArtifact`, the theme observer and `setValueFormat` reach the session or its canvas. |
| site | `site/test/renderer-pin.test.ts` | Assert `CircCanvas` is constructible over a runtime (already exported) and `CircRuntime.loadFromBytes` exists — the two building blocks the session stands on. |
| site | `DOCS/decisions/playground.md` | Entries for decisions 1, 3, 8, 9. |
| site | `DOCS/STATUS.md` (new), `DOCS/PLANS_PROMPT.md` traps | Per slice. |

**New dependencies:** None.

## Data & State

```ts
// sim-session.ts
export type PinKind = 'in' | 'out';
export interface PinRef { name: string; id: number; width: number; kind: PinKind }
export interface MemRef { name: string; id: number; kind: 'rom' | 'ram'; width: number; addrWidth: number }

/** The ten codes of lib/sim/protocol.zig, as the session reports them. */
export type SimError =
  | 'E_PROTO' | 'E_NOPIN' | 'E_NOTIN' | 'E_WIDTH' | 'E_BADVAL'
  | 'E_NOSETTLE' | 'E_NOMEM' | 'E_IO' | 'E_MEMFMT' | 'E_ADDR';
export type SimResult<T = void> =
  | ({ ok: true } & T)
  | { ok: false; code: SimError; arg: string };

/** The slice of CircRuntime the session uses; a test stubs it. */
export interface RuntimeLike {
  readonly topology: { components: readonly { id: number; kind: number; name: string; width: number; origin: readonly unknown[]; memory?: { addrWidth: number } }[] };
  setValue(id: number, value: bigint, defined: bigint): void;
  run(): void;
  readValue(id: number): BitValue;
  readonly hasMemory: boolean;
  memories(): readonly { id: number; name: string; info: { kind: 'rom' | 'ram'; width: number; addrWidth: number } }[];
  readMemWord(id: number, addr: number): BitValue;
  writeMemWord(id: number, addr: number, value: bigint, defined: bigint): number;
  loadMemImage(id: number, bytes: Uint8Array): number;
  storeMemImage(id: number): Uint8Array | null;
  clearMem(id: number): number;
  destroy(): void;
}

export interface SessionInit {
  bytes: Uint8Array;
  /** `CircRuntime.loadFromBytes` on the page; a stub factory in a test. */
  load: (bytes: Uint8Array) => Promise<RuntimeLike>;
  /** Declared roms and their images from the dock, applied at build and at reset. */
  roms: readonly MemorySymbol[];
  images: RomImageMap;
  /** Analysis warnings, for the handshake (Phase 3 reads them). */
  warnings: readonly { code: string; file: string; line: number; col: number; message: string }[];
}

export type SessionEvent =
  | { kind: 'drive'; names: readonly string[] }   // pins driven (by any face)
  | { kind: 'memory'; name: string }               // a memory's contents changed
  | { kind: 'rebuilt' }                            // reset: a new runtime, faces rebuild
  | { kind: 'destroyed' };

export class SimSession {
  static async build(init: SessionInit): Promise<SimSession>;
  readonly runtime: RuntimeLike;           // the current one; replaced by reset()
  readonly pins: readonly PinRef[];        // inputs then outputs, declaration order, origin.length === 0
  readonly mems: readonly MemRef[];        // root memories, declaration order
  readonly warnings: SessionInit['warnings'];
  set(name: string, value: bigint, defined?: bigint): SimResult;          // E_NOPIN | E_NOTIN | E_WIDTH; settles
  get(name: string): SimResult<{ value: BitValue }>;                     // outputs then inputs, as doGet
  dump(which: 'in' | 'out' | 'all'): { name: string; value: BitValue }[];
  eval(assigns: readonly { pin: string; value: bigint; defined?: bigint }[], queries: readonly string[]): SimResult<{ values: { name: string; value: BitValue }[] }>; // validate all, then drive in order
  run(): void;
  reset(): Promise<void>;                  // new runtime, preloads, 'rebuilt'
  applyPreloads(): ApplyResult;            // romPlan + applyRomImages over the runtime
  mems(): readonly MemRef[];
  peek(mem: string, addr: bigint): SimResult<{ value: BitValue }>;       // E_NOMEM | E_ADDR
  poke(mem: string, addr: bigint, value: bigint, defined?: bigint): SimResult; // + E_WIDTH; settles
  dumpMem(mem: string, start?: bigint, count?: bigint): SimResult<{ cells: { addr: bigint; value: BitValue }[] }>;
  clear(mem: string): SimResult;
  loadImage(mem: string, bytes: Uint8Array): SimResult<{ words: number }>; // E_NOMEM | E_MEMFMT (validated before the call, Phase 2 supplies the wording)
  storeImage(mem: string): SimResult<{ bytes: Uint8Array; words: number }>;
  /** A face drove the runtime around the session (the canvas's click): notify the others. */
  notifyExternal(names: readonly string[]): void;
  subscribe(listener: (e: SessionEvent) => void): () => void;
  destroy(): void;
}
```

Rules the class holds: `set` masks nothing silently — a value or mask with bits above the pin's width is `E_WIDTH <pin>`, as `resolveDrive` does; an omitted `defined` is the full mask; `get` on an output or an input reads `runtime.readValue(id)`; `eval` validates every assignment and query before driving any (a malformed eval is inert); every mutator ends in `runtime.run()` and a `drive`/`memory` event; `reset` destroys the old runtime, loads a new one from the same bytes, re-applies preloads, keeps `pins`/`mems` (same topology), emits `rebuilt`.

Island state after this phase:

```ts
const sim = {
  session: null as SimSession | null,
  view: null as CircCanvas<PaletteKey> | null,   // the canvas face, over session.runtime
  bytes: null as Uint8Array | null,
  renderedHash: -1,
  pins: new Map<string, BitValue>(),             // as today, replayed through session.set on a new artifact
  …
};
```

## Execution & Concurrency Model

`SimSession.build` and `reset` are async (a wasm instantiation); every other method is synchronous. The island guards `build` with the artifact hash as `buildSim` does today (`sim.renderedHash`), and a `reset` in flight is awaited before any face drives. Listeners are called synchronously after each mutation, in subscription order; a listener that throws is caught and logged so one face cannot silence the others.

## Persistence & I/O

None new. ROM images stay in the island's `romImages` map and `settings.romImages` as today; the session reads them through `SessionInit.images`.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Pins and drives | `sim-session.ts` with `collectPins`, `collectMems`, `set`/`get`/`dump`/`eval`/`run`, errors, listeners; `sim-stub.ts`. | `sim-session.test.ts`: pins in declaration order and root only (a stub topology with a macro's inner pin excluded); `set` on an output → `E_NOTIN`, unknown → `E_NOPIN`, `0x10` on a 4-bit pin → `E_WIDTH`, mask omitted → full; `eval` with a bad query drives nothing; every drive calls `run` once and emits one `drive` event. |
| 2 | Preloads, reset, memories | `applyPreloads`, `reset`, the memory verbs; the integration test. | Stub: `poke` past `2^A` → `E_ADDR`, a word over the width → `E_WIDTH`, `dumpMem` clips `count`, `clear` emits `memory`; `reset` loads a new runtime, re-applies preloads, emits `rebuilt`, and the old runtime's `destroy` was called. Real: `and_gate.circ` compiled through `libcirc.wasm`, `set a 1`, `set b 1`, `get out` → `0x1/0x1`. |
| 3 | The canvas over the session | `Playground.astro`: `ensureSession`, `buildCanvas` with `new CircCanvas(session.runtime, …)`, `onPinChange` → `sim.pins` + `session.notifyExternal`, pin replay through `session.set`, `hooks.onArtifact` builds/destroys the session, theme observer and `setValueFormat` unchanged in effect. | `bun test` green (`island-smoke`, `renderer-pin` with its two new assertions), typecheck, build, bundle; the human clicks pins, types a bus value, recompiles, flips the theme. |
| 4 | The dock over the session | `memHost()` returns `session.runtime`; `applyToView()` → `session.applyPreloads()` + `view.refreshState()`; `renderMemory` on `memory` and `drive` events. | `memory-panel.test.ts` and `canvas-memory.test.ts` green; the human loads a ROM image on `rom-lookup` and clocks `ram-write-read`. |
| 5 | Review | The human's walk of the unchanged page. | STATUS records it; the lazy chunk's size recorded as this initiative's baseline. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `pins are the root pins, inputs then outputs, in declaration order` | `sim-session.test.ts` | Over a stub topology with a nested-origin pin. |
| `set refuses what --sim refuses, before touching the runtime` | same | `E_NOPIN`, `E_NOTIN`, `E_WIDTH` each with no `setValue` call logged. |
| `every drive settles once and notifies once` | same | `calls.run` count and event list. |
| `eval validates everything before driving anything` | same | A bad query leaves `calls` empty. |
| `the memory verbs map to the runtime as the protocol says` | same | `peek`/`poke`/`dumpMem`/`clear` calls and errors. |
| `reset is a new runtime with the preloads re-applied` | same | Old `destroy` called, new runtime loaded, `loadMemImage` called for each planned image, `rebuilt` emitted. |
| `an artifact from libcirc drives through a real CircRuntime` | same (skippable) | The `and_gate` scenario. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `island-smoke.test.ts` | the built page | Unchanged: the strip is still three tabs this phase. |
| Site gates | `bun test`, typecheck, build, bundle | Green; chunk size recorded. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- `TODO(phase0)`: `CircCanvas`'s `onPinChange` fires after the canvas drove the runtime itself (`setValueAndRun` inside the canvas); confirm at slice 3 that `session.notifyExternal` after it is enough for the dock (`renderMemory`) and does not double-settle.
- `TODO(phase0)`: whether `E_MEMFMT` wording belongs in the session (`loadImage`) or the executor. Slice 2 puts the *validation* in the session (`validateImageBytes` from `rom-image.ts`, to be added in Phase 2 if absent) and returns the error kind; the wording is the executor's (decision 4).
