# STATUS — Playground driver

One entry per shipped slice, newest last. The plan is `DOCS/PLANS_PROMPT.md`; the phase specs are under `DOCS/PLANS/`.

## 2026-09-11 — Phase 0 — the session over a stub runtime

**What shipped:** `site/src/scripts/sim-session.ts`: `SimSession` over an injected `RuntimeLike` — `collectPins` (root pins, inputs then outputs, declaration order) and `collectMems`; `set`/`get`/`dump`/`eval`/`run` with the protocol's refusals (`E_NOPIN`, `E_NOTIN`, `E_WIDTH`) decided before the runtime is touched; `applyPreloads` over `romPlan`/`applyRomImages`; `reset` as a fresh runtime with the old destroyed and `rebuilt` emitted; the memory verbs (`peek`, `poke`, `dumpMem`, `clear`, `loadImage`, `storeImage`) with `E_NOMEM`/`E_ADDR`/`E_WIDTH`; `subscribe`/`notifyExternal`/`destroy`. `site/test/sim-stub.ts` (a recording runtime with an `and_gate` and a rom/ram fixture) and `site/test/sim-session.test.ts`.
**Files touched:** `site/src/scripts/sim-session.ts`, `site/test/sim-stub.ts`, `site/test/sim-session.test.ts`, `DOCS/STATUS.md`
**Tests:** added fourteen (pins and memories collected; set drives and settles; refusals before the runtime; masks; get/dump; eval validates all first; a throwing listener; external notify; peek/poke/dump/clear; load/store; preloads at build and reset; destroy once; 64-bit widths); ran `bun test` (463 pass, 1 fail — see Notes), `bun --bun run typecheck` (1 error — see Notes), result pass for this slice's files
**Next slice:** the integration test over a real `CircRuntime` from an artifact compiled by `libcirc.wasm`.
**Notes:** the spec's slice 1 and slice 2 module work landed together (the class is one piece; splitting it would have meant a half-built session on `main`'s history); slice 2 keeps only the real-artifact test. The worktree carries an uncommitted change this session did not make and does not stage: `site/package.json` and `site/bun.lock` pin `circ-renderer` at `ef63ddb` (a renderer commit, "a view that zooms and pans the circuit by API", version string still `2.3.0-alpha.3`), and the installed package is that source. It fails `renderer-pin.test.ts` ("the host hooks this site depends on are present") and the typecheck in `test/circ-skins.test.ts` (`BackgroundContext` gained `view` and `viewport`). Both are the other session's to land or revert; this plan assumes `7ca8593` until told otherwise.

## 2026-09-11 — Phase 0 — the session over a compiled artifact

**What shipped:** `site/test/sim-session-artifact.test.ts`: `and_gate.circ` and `sim_rom_pc_walk.circ` compiled by the committed `libcirc.wasm`, loaded into the renderer's `CircRuntime`, driven through the session — the transcript scenarios, the preload from `tests/fixtures/mem/rom_pc_walk.bin`, a poke dropped by `reset` while the preload survives, the image stored back. `SessionInit.bootLow` added, with stub and artifact cases.
**Files touched:** `site/src/scripts/sim-session.ts`, `site/test/sim-session.test.ts`, `site/test/sim-session-artifact.test.ts`, `DOCS/STATUS.md`
**Tests:** added three (`and_gate` through `CircRuntime`, `sim_rom_pc_walk` preload/poke/reset/store, `bootLow` is the page's boot and reset is the protocol's) plus the stub `bootLow` case; ran `bun test test/sim-session*.test.ts` (18 pass), result pass
**Next slice:** the canvas over the session in `Playground.astro`.
**Notes:** a finding that changes a locked decision's wording: `CircRuntime.loadFromBytes` drives every input low and settles after `init()` unless `noInitialPinDrive` is set, while `--sim` leaves every pin floating after `init()`. The RAM transcript depends on the difference — its first `set clk 1` must not be an edge, and it would be if `clk` had been driven low first. So the session loads with `noInitialPinDrive: true` (the page's `load` passes it), and the page's boot-low behaviour, which the canvas has always had, becomes `SessionInit.bootLow`: applied at build by the island, never by `reset`, never by a transcript test. After a console `reset` the page's session is exactly a fresh `--sim` process; before one, a first `set clk 1` on a freshly compiled circuit IS an edge, because the page booted low. Goes into `DOCS/sim-protocol.md`'s browser section and `DOCS/decisions/playground.md` at the end of the phase. `storeMemImage` returns the whole memory (`2^A` words, unknown as zero), not the loaded prefix — the test asserts that shape.

## 2026-09-11 — Phase 0 — the canvas and the dock over the session

**What shipped:** `Playground.astro` rewired: `ensureSession()` builds one `SimSession` per artifact on first need (loading with `noInitialPinDrive`, `bootLow`, the Memory dock's images as preloads, the reader's pins replayed by name through `session.set`); `buildCanvas()` is `new CircCanvas(session.runtime, …)` over it, its `onPinChange` recording the pin and calling `session.notifyExternal`; a session listener refreshes the canvas and, when visible, the memory dump on `drive`/`memory`, and rebuilds the canvas on `rebuilt`; `hooks.onArtifact` drops the session on a new or absent artifact; `memHost()` reads `session.runtime` and `applyToView()` is `session.applyPreloads()`, so the dock works whenever a session exists. `View` is `Pick<CircView, 'view' | 'canvas' | 'destroy'>` — the renderer's shape, not a restated one. `renderer-pin.test.ts`'s one-render-call guard now holds the gallery to one `renderCircuit` and the playground to one `new Canvas<PaletteKey>(session.runtime …)`.
**Files touched:** `site/src/components/Playground.astro`, `site/test/renderer-pin.test.ts`, `DOCS/STATUS.md`
**Tests:** ran `bun test` (466 pass, 2 fail — both the foreign pin, see Notes), `bun --bun run typecheck` (1 error, foreign — see Notes), `bun --bun run build`, `bun run bundle` (every route ok; `/playground`'s eager graph 85.1 → 90.4 KB raw, 31.1 → 32.8 KB gzip with the session module static-imported into the island, under the 120 KB ceiling; the renderer's lazy chunk 41.3 → 48.0 KB raw is the foreign renderer source, not this slice), result pass for this slice's files
**Next slice:** the human's review of the unchanged page (spec slice 5); spec slice 4 (the dock over the session) landed here, since `memHost` and `applyToView` were the same edit as the canvas.
**Notes:** **another session is editing this worktree.** Since slice 1 the uncommitted `site/package.json` and `site/bun.lock` have moved the renderer pin twice (`ef63ddb`, then `2d973b4`, version `2.3.0-alpha.4`, "a viewport the element takes instead of the grid's size"), and `node_modules` was reinstalled under this session at 00:13. The `canvas-theme` worktree still pins `7ca8593` and has no new commits, so the other session's target is this checkout, not that one. This session commits only its own paths and has not staged the manifest; the two pin tests and the `circ-skins.test.ts` typecheck error are the other session's to land or revert. Until the two sessions are separated, no further slice here is safe: a `bun install` mid-test or a manifest commit from either side would sweep the other's work. Decisions 1, 3, 8 and 9 are exercised and await the phase's decisions entry.

## 2026-09-11 — Phase 0 — pin bump to the renderer's viewport release

**What shipped:** the human moved the site's `circ-renderer` pin to `2d973b4` (`2.3.0-alpha.4`: a view that zooms and pans by API, drag/pinch/wheel moving the view, a viewport the element takes instead of the grid's size) and `RENDERER_PIN_VERSION` with it; the two guards the new source broke are retargeted, not weakened — the device-pixel padding guard now matches `setTransform(dpr * scale, 0, 0, dpr * scale, x * dpr, y * dpr)` (the offset still scaled by the ratio, now with the view's scale), and the theme's background test passes the `view` and `viewport` the hook now receives.
**Files touched:** `site/package.json`, `site/bun.lock`, `site/src/utils/renderer-versions.ts`, `site/test/renderer-pin.test.ts`, `site/test/circ-skins.test.ts`, `DOCS/STATUS.md`
**Tests:** ran `bun test` (479 pass), `bun --bun run typecheck` (0 errors), `bun --bun run build`, `bun run bundle` (`/playground` 90.4 KB raw / 32.8 KB gzip, ok), result pass
**Next slice:** the human's review of the unchanged page (Phase 0 slice 5), then Phase 1.
**Notes:** the previous entry's blocker is resolved: the pin moves were the human's, made in this worktree on purpose. The plan prompt's Tech Stack names `7ca8593`; the pin is now `2d973b4` and every later slice builds on it. The `/playground` eager graph's growth to 90.4 KB is the session module; the lazy renderer chunk's growth is the viewport code.

## 2026-09-11 — Phase 0 — review

**What shipped:** the human reviewed the rewired page and approved it ("go for phase 1"). Phase 0 complete.
**Files touched:** `DOCS/STATUS.md`
**Tests:** none (review)
**Next slice:** Phase 1 slice 1: the tab value.
**Notes:** decisions 1, 3, 8 and 9 go into `DOCS/decisions/playground.md` with Phase 1's entry, so the doc is written once per phase pair rather than mid-phase.

## 2026-09-11 — Phase 1 — the tab value

**What shipped:** `OutputTab` and `OUTPUT_TABS` gain `'data'`; `normalize` keeps it and still falls an unknown tab back to `preview`.
**Files touched:** `site/src/utils/playground-store.ts`, `site/test/playground-store.test.ts`, `DOCS/STATUS.md`
**Tests:** extended the fallback case (`'data'` survives, `'console'` falls back); ran `bun test test/playground-store.test.ts`, result pass
**Next slice:** rows and edits.
**Notes:** none.

## 2026-09-11 — Phase 1 — rows and edits

**What shipped:** `site/src/scripts/data-view.ts`: `rowsFor` (one row per root pin, `formatPinValue` in the reader's base, a one-bit signal for the toggle), `editRow` (`parsePinValue` then `session.set`; a parse failure is the renderer's reason and drives nothing), `toggleRow` (unknown → 1 → 0 → 1 on a one-bit input; a bus is told to type), `describeError` (a sentence per protocol code). `site/test/data-view.test.ts` over the session on the stub runtime.
**Files touched:** `site/src/scripts/data-view.ts`, `site/test/data-view.test.ts`, `DOCS/STATUS.md`
**Tests:** added five (rows before any drive; the three bases and a half-known value; edits in each base and `?`; refusals drive nothing; the toggle; every code has a sentence); ran `bun test test/data-view.test.ts` (10 pass), typecheck (0 errors), result pass
**Next slice:** the panel.
**Notes:** two corrections to the spec, from the renderer's own parser: a typed value is wholly known — `parsePinValue` refuses `x` bits, as the bus dialog always has — so the spec's "`x` bits become mask bits" does not hold and the test asserts the refusal instead; and a half-known value is written `10xx` with no prefix. `data-view.ts` imports the renderer's index for the two value helpers, so the island must import it dynamically (slice 3), never statically.

## 2026-09-11 — Phase 1 — the panel

**What shipped:** the `Data` tab and panel in `Playground.astro`: `showData()` builds the session on first need and loads `data-view.ts` dynamically; `renderData()` draws one table row per root pin — a field for a bus input (commit on Enter or blur, Escape restores, `aria-invalid` on a refusal with the reason in the status span), a toggle for a one-bit input, text for an output — rebuilding on a shape change and updating in place otherwise so a field being typed into keeps its text; rows follow `drive`, `memory` and `rebuilt` events and a base change in the settings; the reset button clears the remembered pins and runs the session's `reset`; the note carries Simulate's own sentences (`Compile a circuit first.`, `Fix the errors to simulate.`, the version-skew one). Styles in `global.css`; `island-smoke.test.ts` asserts four tabs and the panel's parts.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/test/island-smoke.test.ts`, `DOCS/STATUS.md`
**Tests:** ran `bun test` (485 pass), `bun --bun run typecheck` (0 errors), `bun --bun run build`, `bun run bundle` (`/playground` 93.5 KB raw / 33.6 KB gzip, ok; `data-view` a 1.6 KB lazy chunk), result pass
**Next slice:** the dock on the tab (spec slice 4) needs no code — `memHost()` reads the session since Phase 0 — so it is the human's check alongside the review of this slice.
**Notes:** `renderData` is synchronous over the loaded module handle; `showData` awaits the import once. The reset drops `sim.pins` so a recompile after a reset does not replay stale values, which is what a reader who pressed Reset would expect.

## 2026-09-11 — Phase 1 — review

**What shipped:** the human reviewed the Data tab and the dock on it and approved ("go"). Phase 1 complete.
**Files touched:** `DOCS/STATUS.md`
**Tests:** none (review)
**Next slice:** Phase 2 slice 1: the grammar.
**Notes:** none.

## 2026-09-11 — Phase 2 — the grammar

**What shipped:** `site/src/scripts/sim-protocol.ts`: `parseValue` (`std.fmt.parseInt(u64, text, 0)` over `bigint`, the standard library's rules copied: sign, prefix only past two characters, no underscore at either end, interior underscores skipped, sixty-four bits), `parseLine` (every verb's argument checks in `protocol.zig`'s order, so a bad literal wins over a later shape error exactly where the CLI's does), `writeHex`, the `Command` union and `ParseOutcome`.
**Files touched:** `site/src/scripts/sim-protocol.ts`, `site/test/sim-protocol.test.ts`, `DOCS/STATUS.md`
**Tests:** added thirteen (radixes and case, underscores, signs, prefixes without digits, the 64-bit edge, `writeHex`; blank and comment lines, the four bare verbs and `mems`, `set`, `get`/`dump`/`clear`, `eval`, the memory verbs, unknown verbs and tabs); ran `bun test test/sim-protocol.test.ts` (13 pass), `bun --bun run typecheck` (0 errors), result pass
**Next slice:** the executor.
**Notes:** one correction to the spec, from the standard library: `parseInt` accepts a leading `+` or `-` (a negative literal overflows an unsigned type, except `-0`), so the console accepts `+10` and `-0` as the CLI does; the spec's "no sign" does not hold. The spec's `ErrorCode` is not a second type: the session's `SimError['code']` already names the ten codes and the executor spells them.

## 2026-09-11 — Phase 2 — the executor

**What shipped:** `site/src/scripts/sim-executor.ts`: `handshake` (`ready proto=1 pins=N warnings=W`, a `pin` line per root pin, a `diag warning` line per warning spelled with the file the CLI was given) and `execute` (one line in, the loop's reply lines out) for every verb, with `lib/sim/loop.zig`'s strings copied: parse failures, `ok`, `ok <hex> <hex>` canonical as `readPin` has it, `vals`/`pins`/`mems`/`cells` blocks, `ok pin=v/d` for `eval`, `ok words=<n>`, and each `err` arm in the loop's order (`load` resolves the memory before reading; `FileTooBig` is `E_MEMFMT … image exceeds 16 MiB`). `quit` prints `ok bye` and resets. The `FileSource` interface and `MemoryFileSource` over a map. `site/src/utils/rom-image.ts`: the three byte checks moved out of `parseRomImage` into `validateImageBytes`, plus `imageErrorReason` with `writeImageError`'s wording; the session's `loadImage` validates first so its `E_MEMFMT` carries that reason. `site/test/sim-transcripts.test.ts` with `sim_and_gate`.
**Files touched:** `site/src/scripts/sim-executor.ts`, `site/src/utils/rom-image.ts`, `site/src/scripts/sim-session.ts`, `site/test/sim-executor.test.ts`, `site/test/sim-transcripts.test.ts`, `DOCS/STATUS.md`
**Tests:** added fourteen (the handshake with and without a warning; blank lines, comments and parse failures; the pin verbs and `dump`; the pin error arms; `eval` inert on a bad line; `reset` and `quit`; `mems` empty and populated; `peek`/`poke`/`mem`/`clear`; the memory error arms; `load`/`save` round trip; their error arms in the loop's order; a replayed script) and the `sim_and_gate` transcript byte for byte; ran `bun test` (512 pass), `bun --bun run typecheck` (0 errors), result pass
**Next slice:** the remaining transcripts (`sim_rom_pc_walk`, `sim_ram_write_read`, `sim_mem_errors`).
**Notes:** slices 2 and 3 of the spec merged here: writing `execute` with half its verbs answering would have left a commit that lies, and the memory verbs are one line each over the session. Slice 3 is now the two memory transcripts and slice 4 the error transcript, each with whatever the real artifact turns up. The executor masks a read to `value & defined & widthMask` itself rather than trusting the runtime's planes to be canonical, as `readPin` does in the loop.

## 2026-09-11 — Phase 2 — the transcripts

**What shipped:** `site/test/sim-transcripts.test.ts` replays all four rows of `tests/sim/golden_test.zig`'s table — `sim_and_gate` over `and_gate.circ`, `sim_rom_pc_walk` with its `--mem=code=tests/fixtures/mem/rom_pc_walk.bin` preload, `sim_ram_write_read`, and `sim_mem_errors` over `sim_ram_write_read.circ` — through the executor over artifacts compiled by the committed `libcirc.wasm`, with the repository root as the file source (`ENOENT` spelled `FileNotFound`), and matches each golden byte for byte, handshake included.
**Files touched:** `site/test/sim-transcripts.test.ts`, `DOCS/STATUS.md`
**Tests:** added three transcript cases; ran `bun test test/sim-transcripts.test.ts` (4 pass), result pass
**Next slice:** the phase's documents (decisions 2, 4, 10 and 11; the spec's stale line about a drop box), then the human's review.
**Notes:** the three goldens passed on the first run — the session's memory verbs already matched the loop, and the executor's canonical masking covered the rest — so the spec's slices 3 and 4 close in one commit with nothing to fix. The `sim_mem_errors` transcript proves the loop's order end to end: `E_NOMEM` before the file is read, `E_IO … FileNotFound`, `E_MEMFMT … 17 words exceed capacity 16` with the compiler's wording, `E_ADDR data 0x10`, `E_WIDTH data`, `E_NOPIN data` twice, `E_PROTO malformed command`.

## 2026-09-11 — Phase 2 — review

**What shipped:** the human reviewed the grammar, the executor and the four transcripts and approved ("go"). Phase 2 complete.
**Files touched:** `DOCS/STATUS.md`
**Tests:** none (review)
**Next slice:** Phase 3 slice 1: the drawer.
**Notes:** none.

## 2026-09-11 — Phase 3 — the pure parts

**What shipped:** `site/src/scripts/console.ts`: `HistoryRing` (a hundred lines, `up` stays on the oldest, `down` past the newest is the empty prompt, a submit resets the cursor, blank and repeated lines are not kept twice), `Transcript` (the newest lines up to a cap, `text`, `last`, `clear`), `MemoryTabFiles` (refuses every read with `load images in the Memory tab` and every write with `save images from the Memory tab`), `promptEcho` (`> <line>`, which the grammar refuses, so an echo cannot read as a reply), `helpLines` (the command table as `#` comment lines the protocol ignores, plus the browser's `help` and the two refused file verbs).
**Files touched:** `site/src/scripts/console.ts`, `site/test/console.test.ts`, `site/test/sim-executor.test.ts`, `DOCS/STATUS.md`
**Tests:** added seven (history bounds, reset and cap; the transcript's cap, `clear` and `last`; both refusals; the echo; help lines one per verb) and one executor case (`load code x.bin` → `err E_IO x.bin: load images in the Memory tab`, `save` likewise, `E_NOMEM` still first); ran `bun test test/console.test.ts test/sim-executor.test.ts` (21 pass), result pass
**Next slice:** the drawer and the Memory tab's move.
**Notes:** `HistoryRing.push` skips a line equal to the newest, as a shell does, so ↑ after two identical submits reaches the earlier command in one step.

## 2026-09-11 — Phase 3 — the drawer and the Memory tab's move

**What shipped:** the `.pg-drawer` under the output panels in `Playground.astro`: a strip with Console and Memory tabs and a Hide/Show toggle over one body, shown only while the output tab is Simulate or Data, collapsing to its strip with the dock's gesture (the selected tab collapses, any tab reopens); the `.pg-drawer-splitter` above it, a horizontal `createSplitter` over the output pane writing `--pg-split-drawer` and persisting `layout.ratios.drawer`, hidden with the drawer or while it is collapsed; the Memory panel's markup moved into the drawer's Memory tab and its handlers repointed (`memVisible` reads the drawer), the dock's memory tab, panel and deferred-restore bookkeeping removed, `DockTab` narrowed to `'diagnostics' | 'settings'` so a stored `memory` falls back; a `Save image` button per memory (enabled while the circuit runs) downloading `<mem>.bin` from `session.storeImage` through one `downloadBytes` helper the artifact button now shares; drawer styles in `global.css`.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/src/utils/playground-store.ts`, `site/test/island-smoke.test.ts`, `site/test/playground-store.test.ts`, `DOCS/STATUS.md`
**Tests:** smoke asserts the dock's two tabs, the drawer's two tabs inside the output pane, the drawer hidden on Preview, the memory tab and panel hidden and the save button disabled with nothing running, and a new drive case (the drawer follows Simulate/Data, hides on Truth table, collapses and reopens with its divider); the store test adds `dock.tab: 'memory'` → `diagnostics`; ran `bun test` (524 pass), `bun --bun run typecheck` (0 errors), `bun --bun run build`, `bun run bundle` (`/playground` 95.8 KB raw / 34.2 KB gzip, ok), result pass
**Next slice:** the console.
**Notes:** `splitter.ts` already took `orientation: 'horizontal'`, so the spec's open question closed without a change to it. The drawer's stored ratio is the splitter's convention — the first pane's share, the output panels' — and the drawer takes the rest through `flex-basis: calc((1 - ratio) * 100%)`; the spec's "the drawer's fraction" reads the other way round, and `LayoutState`'s comment now says which. The drawer's tab and open state are island fields, never stored, as decision 6 has it. The human's check for this slice: load and save an image on `rom-lookup` from the drawer.

## 2026-09-11 — Phase 3 — the console

**What shipped:** the Console tab in `Playground.astro`: a scrollback `<pre>` of `.pg-console-line` spans (a `data-kind` of `reply`, `err`, `echo` or `note` for the stylesheet; the text is the executor's) and a one-line prompt. Enter echoes the line as `> …`, runs `execute` over the session and the page's `MemoryTabFiles`, prints the replies, scrolls to the end and announces the last reply through the status span; `help` prints the command table as comment lines; ↑/↓ walk a hundred lines of history; `Ctrl+L` clears. The prompt is disabled while a line runs and whenever there is no session, when the note carries Simulate's gating sentence. The session prints its handshake the moment it is built, with the root file as the name and the analysis's warnings as `diag warning` lines; a `rebuilt` prints `# reset` and the handshake again, after the `ok`/`ok bye` that caused it when the console did, at once when the Data tab's Reset did; `destroyed` prints `# session ended`. `sim-executor.ts`, `sim-protocol.ts` and `console.ts` ride in the eager bundle.
**Files touched:** `site/src/components/Playground.astro`, `site/src/styles/global.css`, `site/test/island-smoke.test.ts`, `DOCS/STATUS.md`
**Tests:** smoke asserts the scrollback and the prompt exist, the prompt is disabled and the note shows `Compile a circuit first.` with an empty log; ran `bun test` (524 pass), `bun --bun run typecheck` (0 errors), `bun --bun run build`, `bun run bundle` (`/playground` 104.9 KB raw / 37.3 KB gzip, ok), result pass
**Next slice:** the document.
**Notes:** the `rebuilt` ordering is the one thing the console adds to the executor's stream: a `# reset` that landed between `> reset` and its `ok` would break the "paste the log into a script" promise, so the listener only flags it while a line runs and the submit prints it after the reply. The human's check for this slice: `eval a=3 b=5 => sum cout` on `four-bit-adder`, `load code x.bin` and the pointer to the Memory tab, `quit`, and the Data tab's Reset printing `# reset` in the console.
