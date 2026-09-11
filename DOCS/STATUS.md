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
