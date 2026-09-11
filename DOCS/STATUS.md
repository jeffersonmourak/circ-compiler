# STATUS — Console polish

One entry per shipped slice, newest last. The plan is `DOCS/PLANS_PROMPT.md`; the phase specs are under `DOCS/PLANS/`. This plan follows the archived playground driver (`DOCS/archive/plan-playground-driver.md`) on the same branch, by the human's ask.

## 2026-09-11 — Phase 0 — events with their details

**What shipped:** `sim-session.ts`: `DriveAssign`; a `drive` event carries `assigns` (name, value, the mask the runtime received) beside `names`; a `memory` event says its `op` — `poke` with `addr`, `value`, `defined`; `clear`; `load` with `words`; `notifyExternal(assigns)` takes what the canvas drove, which `onPinChange` in the island now passes; `applyPreloads({ silent })` emits a `load` or a `clear` per image it applied unless silent, and the build and `reset` apply silently so the handshake stays the record of those moments.
**Files touched:** `site/src/scripts/sim-session.ts`, `site/src/components/Playground.astro`, `site/test/sim-session.test.ts`, `DOCS/STATUS.md`
**Tests:** the drive, eval, external-notify, memory and load cases assert the new payloads; added one (a face's `applyPreloads` reports a `load` of two words, an emptied image a `clear`, `silent` nothing); ran `bun test` over the session, artifact, executor, transcript and data-view files (43 pass), `bun --bun run typecheck` (0 errors), result pass
**Next slice:** the Memory panel through the session.
**Notes:** the `load` word count in a preload event is `bytes.length / bytesPerWord`, from the plan the session applied, not from the runtime.

## 2026-09-11 — Phase 0 — the Memory panel through the session

**What shipped:** the Memory panel's RAM write (`writeLiveWord`) and clear (`clearMemory`) go through `session.poke` and `session.clear`; the session settles, tells the other faces and, from slice 4 on, logs the line, so the panel no longer calls `refreshState` itself. A refusal's status sentence carries the protocol code and argument. No `host.writeMemWord` or `host.clearMem` call is left in the island; `memHost()` remains the read path.
**Files touched:** `site/src/components/Playground.astro`, `DOCS/STATUS.md`
**Tests:** `grep -c 'host.writeMemWord\|host.clearMem' Playground.astro` → 0; ran `bun --bun run build`, `bun test` (528 pass, the memory-grid smoke case among them), `bun --bun run typecheck` (0 errors), result pass
**Next slice:** `commandFor`.
**Notes:** a ROM edit is still an image edit (`setImage` → `applyPreloads`), as decision 4 has it; only a RAM's cells are written live.

## 2026-09-11 — Phase 0 — `commandFor`

**What shipped:** `console.ts`: `commandFor(event, session)` — a drive is one `> set <pin> <hex>` per assign, each followed by `ok`, with the mask written only when the pin is not wholly known (a name the session does not list keeps its mask); a `poke` likewise with its address; a `clear`; an image applied from the Memory tab is `# <mem>: image from the Memory tab, <n> word(s)`; a rebuild is `> reset`, `ok`; an end is nothing. Values are canonical (`value & defined`) as the executor's are. `WidthSource` names what it reads of a session.
**Files touched:** `site/src/scripts/console.ts`, `site/test/console.test.ts`, `DOCS/STATUS.md`
**Tests:** added three (a drive's spellings and masks, every echo re-parsing once its mark is stripped; the three memory shapes; rebuilt and destroyed); ran `bun test test/console.test.ts` (10 pass), `bun --bun run typecheck` (0 errors), result pass
**Next slice:** the echo on the page.
**Notes:** `console.ts` now imports `widthMask` from the topology entry point and `writeHex` from the grammar, both already in the eager bundle.

## 2026-09-11 — Phase 0 — the echo on the page

**What shipped:** the island's session listener logs what another face did: on `drive` and `memory`, when the console is not running a line of its own, it appends `commandFor(event, session)` with `data-origin="page"` on each span; on `rebuilt` from another face it appends `> reset`, `ok` and the handshake; a `rebuilt` caused by the console's own `reset` or `quit` prints only the handshake after the reply, since the echo and its `ok` are already there. The `# reset` comment is gone. `consoleAppend` takes an origin. `applyToView` calls the loud `applyPreloads`, so a ROM edited in the Memory tab logs its comment.
**Files touched:** `site/src/components/Playground.astro`, `DOCS/STATUS.md`
**Tests:** ran `bun --bun run build`, `bun test` (528 pass; `island-smoke` unchanged, nothing prints at mount), `bun --bun run typecheck` (0 errors), `bun run bundle` (`/playground` 106.1 KB raw / 37.7 KB gzip, ok; +1.2 KB raw for `commandFor` and the echo), result pass
**Next slice:** the human's review of Phase 0 on the page: a canvas click, a Data-tab toggle and edit, a Memory-tab cell write and clear on `ram-write-read`, an image edit on `rom-lookup`, the Data tab's Reset; each typed line once.
**Notes:** the handshake after a console-typed `reset` follows the `ok` as it did, so the executor's reply order is untouched and the transcript test's replies are not what the page logs around them.

## 2026-09-11 — Phase 0 — review

**What shipped:** the human reviewed the log of every face on the page and approved ("go for phase 1"). Phase 0 complete.
**Files touched:** `DOCS/STATUS.md`
**Tests:** none (review)
**Next slice:** Phase 1 slice 1: `scriptOf`.
**Notes:** none.

## 2026-09-11 — Phase 1 — `scriptOf`

**What shipped:** `console.ts`: `scriptOf(lines)` keeps an echo without its `> ` and a `#` comment as it is, and drops every reply — `ok…`, `err…`, the handshake, a counted block's header and records; `Transcript.lines` exposes the buffer for it (the field is now `buf`).
**Files touched:** `site/src/scripts/console.ts`, `site/test/console.test.ts`, `DOCS/STATUS.md`
**Tests:** added three (a whole session's log → its script, every line parsing as a command or a comment but the `help` echo; an empty log; `Transcript.lines` is `text` split); ran `bun test test/console.test.ts` (13 pass), `bun --bun run typecheck` (0 errors), result pass
**Next slice:** the bar.
**Notes:** none.
