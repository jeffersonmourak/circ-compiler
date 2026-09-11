# Archived plan: playground-driver

**Canonical commit:** `8afb9e6d3677e81cf1da3685c06bcc690d622aad` (`8afb9e6 docs: sign off the playground driver plan`)
**Archived on:** 2026-09-11
**Plan duration:** 2026-09-11 → 2026-09-11

> This file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the commit referenced above. Check that commit out (`git show 8afb9e6d3677e81cf1da3685c06bcc690d622aad:DOCS/PLANS_PROMPT.md`, `…:DOCS/PLANS/PHASE_2_the_protocol.md`, `…:DOCS/STATUS.md`, etc.) when you need the unabridged source.

## Goal & scope

The playground's Simulate tab drew a circuit and let a reader click pins, and nothing else could drive the circuit: `renderCircuit` created the `CircRuntime` inside the canvas, the memory dock reached it through the picture, and the reader's pin values lived in a name-keyed map replayed onto each rebuilt canvas. For a circuit whose point is a number — an adder, an ALU — the reader wanted to type `a = 0x2A` and read `sum`, and to script a scenario the way `circ-compile --sim` lets a test runner do it. This initiative gave the playground one simulation session and three faces on it. `site/src/scripts/sim-session.ts` owns the `CircRuntime` built from the compiled artifact, holds the root pins and memories by name in declaration order (the collection `lib/engine_session.zig` makes: `origin.length === 0`, inputs then outputs), applies the Memory tab's images as preloads at build and at `reset`, refuses what `--sim` refuses before touching the runtime, settles after every drive and notifies its faces. The **Simulate** canvas is `new CircCanvas(session.runtime, …)` over it and reports its clicks back; the **Data** tab is one row per root pin, inputs editable in the reader's base; the **console**, in a drawer under both tabs beside the Memory panel that moved out of the editor's dock, accepts every `--sim` verb and prints exactly the reply `--sim` prints. The proof that the browser cannot drift from the CLI is `site/test/sim-transcripts.test.ts`, which replays every `tests/fixtures/sim/*.script` through the executor over artifacts compiled by the committed `libcirc.wasm` and matches `tests/fixtures/expected-sim/*.txt` byte for byte. Anchors that held: the compiler and the worker unchanged (`--sim` stays out of `libcirc`; the browser drives the artifact's own runtime, onto which the verbs map one to one); the renderer unchanged (everything needed was exported at the pin, `2d973b4`, `2.3.0-alpha.4`); values spelled one way per face (the site's `parsePinValue`/`formatPinValue` on the Data tab, the protocol's `parseInt`/`writeHex` on the console); the envelope changed by values, never a version; the per-page JavaScript budget never raised.

## Phase-by-phase highlights

### Phase 0 — The session

One `SimSession` per compiled artifact, and the page behaving exactly as before.

- `sim-session.ts`: `SimSession.build({ bytes, load, roms, images, warnings, bootLow })` over an injected `RuntimeLike`; `collectPins`, `collectMems`; `set`/`get`/`dump`/`eval`/`run` with `E_NOPIN`/`E_NOTIN`/`E_WIDTH` decided before the runtime is touched; `peek`/`poke`/`dumpMem`/`clear`/`loadImage`/`storeImage` with `E_NOMEM`/`E_ADDR`/`E_WIDTH`; `applyPreloads` over `romPlan`/`applyRomImages`; `reset` as a fresh runtime with the old destroyed and `rebuilt` emitted; `subscribe`/`notifyExternal`/`destroy`.
- `site/test/sim-stub.ts` (a recording `RuntimeLike` with `AND_GATE` and `MEMORIES` fixtures) and `site/test/sim-session.test.ts`; `site/test/sim-session-artifact.test.ts` over a real `CircRuntime` from `and_gate.circ` and `sim_rom_pc_walk.circ` compiled by `libcirc.wasm`, with the preload from `tests/fixtures/mem/rom_pc_walk.bin`.
- Finding: `CircRuntime.loadFromBytes` drives every input low unless `noInitialPinDrive`; `--sim` leaves pins floating. The session loads floating and `SessionInit.bootLow` is the page's boot, applied at build by the island, never by `reset`, never by a transcript test.
- `Playground.astro`: `ensureSession()`, `buildCanvas()` as `new CircCanvas(session.runtime, …)` with `onPinChange` → `session.notifyExternal`; `memHost()` reads `session.runtime`; `applyToView()` is `session.applyPreloads()`; `hooks.onArtifact` drops the session on a new or absent artifact. `View = Pick<CircView, 'view' | 'canvas' | 'destroy'>`.
- The renderer pin moved to `2d973b4` (`2.3.0-alpha.4`, the viewport release) by the human mid-phase; `renderer-pin.test.ts` and `circ-skins.test.ts` retargeted (`setTransform(dpr * scale, …)`, `BackgroundContext.view`/`viewport`).
- Deviation: spec slices 1–2 and 3–4 landed as one commit each; the eager graph grew 85.1 → 90.4 KB raw with the session imported statically.

### Phase 1 — The Data tab

The circuit as values, driving the same session the canvas draws.

- `OutputTab`/`OUTPUT_TABS` gain `'data'`; an older envelope needs no migration.
- `site/src/scripts/data-view.ts` (pure): `rowsFor`, `editRow` (`parsePinValue` then `session.set`), `toggleRow` (unknown → 1 → 0 → 1), `describeError` (a sentence per code); `site/test/data-view.test.ts`. It imports the renderer's index, so the island loads it through a dynamic `import()` (`data-view` a 1.6 KB lazy chunk).
- The panel: a table with a field per bus input (Enter or blur commits, Escape restores, `aria-invalid` on a refusal), a toggle per one-bit input, text per output; rebuilt on a shape change, updated in place otherwise; rows follow `drive`/`memory`/`rebuilt` and the base setting; a Reset button that clears the remembered pins and runs `session.reset()`; Simulate's own gating sentences.
- Deviation: the renderer's `parsePinValue` refuses `x` bits (a typed value is wholly known) and writes a half-known value as `10xx` with no prefix; the spec's "`x` bits become mask bits" does not hold.

### Phase 2 — The protocol

A line in, the CLI's reply out, and four goldens byte for byte.

- `site/src/scripts/sim-protocol.ts`: `parseValue` is `std.fmt.parseInt(u64, text, 0)` over `bigint` (a leading sign, prefix only past two characters, no underscore at either end, interior underscores skipped, sixty-four bits); `parseLine` copies `protocol.zig`'s per-verb checks in order so `badval` wins over a later `malformed` exactly where the CLI's does; `writeHex`; the `Command` union; `ParseOutcome`.
- `site/src/scripts/sim-executor.ts`: `handshake(session, fileName)`, `execute(session, files, line)` for every verb with `lib/sim/loop.zig`'s strings (`ok`, `ok bye`, `ok <hex> <hex>`, `ok pin=v/d …`, `ok words=<n>`, `pins`/`vals`/`mems`/`cells` blocks, every `err` arm in the loop's order; `load` resolves the memory before reading; `FileTooBig` is `E_MEMFMT …: image exceeds 16 MiB`); reads masked to `value & defined & widthMask` as `readPin` does; `FileSource`; `MemoryFileSource`. `quit` prints `ok bye` and resets.
- `site/src/utils/rom-image.ts`: `validateImageBytes` (the three checks of `lib/memimage.zig` in its order, now shared with `parseRomImage`) and `imageErrorReason` with `writeImageError`'s wording; the session's `loadImage` validates first.
- `site/test/sim-executor.test.ts` (every verb and error arm over the stub) and `site/test/sim-transcripts.test.ts`: `sim_and_gate` (`and_gate.circ`), `sim_rom_pc_walk` (`--mem=code=tests/fixtures/mem/rom_pc_walk.bin`), `sim_ram_write_read`, `sim_mem_errors` (over `sim_ram_write_read.circ`), the repository root as the file source (`ENOENT` → `FileNotFound`), each golden byte for byte, handshake included. The three memory and error goldens passed on their first run.
- Deviation: spec slices 2 and 3 merged (an executor with half its verbs would be a commit that lies); `parseInt` accepts `+10` and `-0`, against the spec's "no sign".

### Phase 3 — The drawer

Console and Memory under the session's two tabs.

- `site/src/scripts/console.ts`: `HistoryRing` (a hundred lines), `Transcript`, `MemoryTabFiles` (`load images in the Memory tab` / `save images from the Memory tab`, which the executor prints as `err E_IO <path>: …`), `promptEcho` (`> …`, which the grammar refuses), `helpLines` (the command table as `#` comment lines), `HELP_VERB`; `site/test/console.test.ts`.
- The `.pg-drawer` under the output panels: Console and Memory tabs with the dock's collapse gesture, shown only on Simulate and Data; the `.pg-drawer-splitter`, a horizontal `createSplitter` over the output pane writing `--pg-split-drawer` and persisting `layout.ratios.drawer` (the output panels' share; the drawer takes the rest); the drawer's tab and open state are island fields.
- The Memory panel moved into the drawer with its handlers repointed; the dock's memory tab, panel and deferred-restore bookkeeping removed; `DockTab` is `'diagnostics' | 'settings'` and a stored `memory` falls back; a `Save image` button per memory downloads `<mem>.bin` from `session.storeImage` through the `downloadBytes` helper the artifact button shares.
- The console: a scrollback of `.pg-console-line` spans (`data-kind` `reply`/`err`/`echo`/`note`) and a prompt; Enter echoes, runs `execute`, prints, scrolls, announces the last reply through the status span; `help`; ↑/↓; `Ctrl+L`; disabled while a line runs or with no session, when the note carries Simulate's gating sentence. The handshake prints when the session is built, with the root file's name and the analysis's warnings; `rebuilt` prints `# reset` and the handshake after the reply that caused it (or at once when the Data tab's Reset did); `destroyed` prints `# session ended`. The three modules ride in the eager bundle.
- `DOCS/sim-protocol.md` gained "The protocol in the browser".
- `island-smoke.test.ts`: the dock's two tabs, the drawer's two tabs inside the output pane, hidden on Preview, the console's prompt and scrollback, a drive case for the drawer following the output tab and collapsing.

### Phase 4 — Sweep and record

- The machine walk: all fourteen shipped examples compiled through `libcirc.wasm`, loaded into `CircRuntime` with their own `memory` images and `bootLow`, driven through the executor; every reply what `--sim` prints. The human's walk in both themes: `four-bit-adder` from the Data tab, the console and a canvas click; `ram-write-read` clocked from the console; `rom-lookup` loaded and saved from the Memory tab; `sr-latch` from the toggles; a recompile, a theme flip, a `reset`. No defect.
- The measurement: the eager `/playground` graph 85.1 → 104.9 KB raw, 31.1 → 37.3 KB gzip of a 120 KB ceiling (the session 5.3 KB, the Data tab 3.1 KB, the drawer 2.3 KB, the console with the grammar and the executor 9.1 KB raw); the lazy renderer chunk's growth belongs to the viewport pin.
- `DOCS/decisions/playground.md` grew thirteen entries for the twelve locked decisions and one finding; `zig build test-all` green and untouched.

## API surface frozen by the plan

No diagnostic code, runtime export or CLI flag changed; the compiler and the renderer are untouched. The surfaces this plan added:

| Surface | Where | Contract |
| --- | --- | --- |
| `SimSession` | `site/src/scripts/sim-session.ts` | `build(init)`, `runtime`, `pins`, `mems`, `warnings`, `set`, `get`, `dump`, `eval`, `run`, `reset`, `applyPreloads`, `peek`, `poke`, `dumpMem`, `clear`, `loadImage`, `storeImage`, `subscribe`, `notifyExternal`, `destroy`, `isAlive`; results as `SimResult<T>` with `SimError` the ten protocol codes and `arg` the protocol's argument. |
| `SessionInit.bootLow` | same | The page's boot (every root input low, one settle), never `reset`'s. |
| `SessionEvent` | same | `drive { names }`, `memory { name }`, `rebuilt`, `destroyed`. |
| `parseLine`, `parseValue`, `writeHex`, `Command`, `ParseOutcome` | `site/src/scripts/sim-protocol.ts` | `lib/sim/protocol.zig`'s grammar; `empty` / `malformed` / `badval`. |
| `handshake`, `execute`, `FileSource`, `MemoryFileSource`, `PROTO_VERSION` | `site/src/scripts/sim-executor.ts` | `lib/sim/loop.zig`'s reply strings; one array of lines per request. |
| `HistoryRing`, `Transcript`, `MemoryTabFiles`, `promptEcho`, `helpLines`, `HELP_VERB` | `site/src/scripts/console.ts` | The console's pure parts. |
| `rowsFor`, `editRow`, `toggleRow`, `describeError` | `site/src/scripts/data-view.ts` | The Data tab's rows, spelled with the renderer's helpers. |
| `validateImageBytes`, `imageErrorReason`, `ImageByteError` | `site/src/utils/rom-image.ts` | `lib/memimage.zig`'s order and `writeImageError`'s wording. |
| `OutputTab` | `site/utils/playground-store.ts` | `'preview' \| 'truth' \| 'simulate' \| 'data'`. |
| `DockTab` | same | `'diagnostics' \| 'settings'`. |
| `layout.ratios.drawer` | same | The output panels' share above the drawer, clamped like `main`. |
| The drawer | `Playground.astro` | `.pg-drawer` with `.pg-drawer-tab[data-drawer="console" \| "memory"]`, `.pg-drawer-splitter`, `.pg-console-log`, `.pg-console-in`, `.pg-mem-save`. |
| The browser's protocol differences | `DOCS/sim-protocol.md` | The handshake at build and after `# reset`; the low boot; `quit` as `reset`; `load`/`save` refused toward the Memory tab; `help`; no line-length cap. |
| Renderer pin | `site/package.json`, `renderer-versions.ts` | `github:jeffersonmourak/circ-renderer#2d973b4`, `RENDERER_PIN_VERSION = '2.3.0-alpha.4'`. |

## Known papercuts carried forward

- **`DOCS/sim-protocol.md` is not synced into the site's reference pages** (`site/scripts/lib/site-config.ts` lists five documents); the browser section is read from the repository, where the getting-started page already points readers. A row in that list would publish it.
- **The console's prompt loop has no headless test**: `island-smoke.test.ts` cannot build a session (no worker, no canvas), so the loop is proved by the human's walk while the executor beneath it is proved byte for byte.
- **`E_PROTO command line exceeds limit` is never printed** in the browser; recorded in the document.
- **Files through the console stayed deferred**; the Memory tab is the file surface, and `load`/`save` say so.
- **`Save image` is disabled until the circuit runs**; saving a rom's pending image without a session would need the panel's own bytes rather than the session's.
- **The renderer's `canvas-theme` branch PR** into circ-renderer's `main` is still the human's to open; this plan changed no renderer file.
- **The page boots low, `reset` boots floating**: a first `set clk 1` on a freshly compiled circuit is an edge, and the same line after `reset` is not. A script that depends on floating pins begins with `reset`.

## Decisions & specs that survived the plan

- `DOCS/decisions/playground.md` — thirteen entries appended: one session and every face through it; loads floating, boots low; the Data tab is rows; errors as values; files are the Memory tab's; the transcript test compiles in the test; the console's spelling is the protocol's; `reset` and a new artifact; the handshake at build; the drawer; the Memory panel in the drawer; a session lives as long as its artifact; documentation lands with the code.
- `DOCS/sim-protocol.md` — "The protocol in the browser".
- `site/test/sim-transcripts.test.ts`, `site/test/sim-executor.test.ts`, `site/test/sim-protocol.test.ts`, `site/test/sim-session.test.ts`, `site/test/sim-session-artifact.test.ts`, `site/test/data-view.test.ts`, `site/test/console.test.ts`, `site/test/island-smoke.test.ts` — the guards that hold the decisions above.
- `tests/fixtures/sim/*.script` and `tests/fixtures/expected-sim/*.txt` — the CLI's goldens, now also the browser's; regenerated only by `UPDATE_GOLDENS=1 zig build test`.
