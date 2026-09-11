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

## 2026-09-11 — Phase 1 — the bar

**What shipped:** the `.pg-console-bar` above the log in `Playground.astro`: a title reading `circ-compile <root>.circ --sim`, refreshed with every handshake, and at the right Clear (`consoleClear`, then focus), Copy script (`scriptOf` over the transcript) and Copy log (the whole text). Copies go through `navigator.clipboard.writeText`, guarded: the status span says `Copied <n> command line(s).` or `Copied the log, <n> line(s).`, with the 2,000-line cap named when it was hit, or `Clipboard unavailable; select the log and copy it.`; never a throw.
**Files touched:** `site/src/components/Playground.astro`, `site/test/island-smoke.test.ts`, `DOCS/STATUS.md`
**Tests:** smoke asserts the title's shape and the three buttons in order, and a drive case (Clear on an empty log is harmless; Copy script answers in the status span after the clipboard's microtask); ran `bun test` (532 pass), `bun --bun run typecheck` (0 errors), `bun --bun run build`, result pass
**Next slice:** the surface.
**Notes:** happy-dom has a `navigator.clipboard` whose `writeText` resolves, so the smoke case waits a tick and accepts either sentence.

## 2026-09-11 — Phase 1 — the surface

**What shipped:** the terminal look: `--term-ok` (`#3f7d5c` light, `#8fd3a8` dark) and `--term-echo` (`#2d2140` light, `#ece4f8` dark) beside the other tokens; `.pg-console` on `--code-bg` with a rounded edge and an inset accent ring while focused; the bar's title in `--muted` and its buttons styled as the dock's toggle; the log wrapping and selectable with a thin scrollbar; `ok` replies in `--term-ok` (`data-ok` on the span), errors in `--danger`, echoes in `--term-echo` with the `>` in `--accent`, comments in `--muted`, page-originated lines at 0.8 opacity; the prompt one line with a bold accent glyph and a borderless transparent input whose caret is the accent. Behaviour: the log follows a new line only when it was at the end (a line and a half's slack), and always on a submit or a handshake; a click anywhere in the panel that is not a button, an input or a selection focuses the prompt; `Escape` clears the line and resets the history cursor.
**Files touched:** `site/src/styles/global.css`, `site/src/components/Playground.astro`, `DOCS/STATUS.md`
**Tests:** ran `bun test` (532 pass), `bun --bun run typecheck` (0 errors), `bun --bun run build`, `bun run bundle` (`/playground` 107.6 KB raw / 38.2 KB gzip, ok; +1.5 KB raw over Phase 0 for the bar's handlers, the scroll lock and the focus), result pass
**Next slice:** the document and the decisions.
**Notes:** the scroll lock reads `scrollHeight`, `scrollTop` and `clientHeight`, all zero in happy-dom, so the log counts as at its end there and the smoke cases see every line. The colours are the human's to judge in both themes.

## 2026-09-11 — Phase 1 — the document and the decisions

**What shipped:** `DOCS/sim-protocol.md`'s browser section: the handshake bullet no longer names a `# reset` comment; a new bullet says the log records every face and how each is spelled, and that a ROM image is a comment; the `help` bullet says the CLI refuses it; the last bullet replaces "the echoes and comments are ignored" with the truth — the CLI refuses an echo as written, `Copy script` gives the lines it accepts, `Copy log` the whole scrollback. `DOCS/decisions/playground.md` gains the entries for decisions 5–10.
**Files touched:** `DOCS/sim-protocol.md`, `DOCS/decisions/playground.md`, `DOCS/STATUS.md`
**Tests:** none (documents)
**Next slice:** the human's review of Phase 1 on the page, in both themes, with a script copied from `ram-write-read` and replayed through `zig-out/bin/circ-compile tests/fixtures/circuits/sim_ram_write_read.circ --sim`.
**Notes:** none.

## 2026-09-11 — Phase 1 — a new project is a new terminal

**What shipped:** the human's review asked that the console start over when the file changes. `loadProject` on a different project id calls `consoleNewSession`: the log and the history are cleared and the log is marked fresh, so the old session's `# session ended`, which the pipeline's file-set change would print into the new log, is skipped; the next handshake clears the mark. Edits to the same project keep the log, with `# session ended` and the new handshake as before.
**Files touched:** `site/src/components/Playground.astro`, `DOCS/STATUS.md`, `DOCS/decisions/playground.md`
**Tests:** ran `bun --bun run build`, `bun test` (532 pass), `bun --bun run typecheck` (0 errors), result pass
**Next slice:** the human's review of Phase 1.
**Notes:** the project id, not the file set, is the trigger: renaming or adding a file inside a project is the same project's session, and only opening another card or scratch project is a new terminal.

## 2026-09-11 — Phase 1 — review

**What shipped:** the human reviewed the terminal in both themes and approved ("great go for phase 2"). Phase 1 complete.
**Files touched:** `DOCS/STATUS.md`
**Tests:** none (review)
**Next slice:** Phase 2 slice 1: the walk.
**Notes:** none.

## 2026-09-11 — Phase 2 — the walk, the machine half

**What shipped:** the four examples the plan names, compiled through the committed `libcirc.wasm`, loaded into the real `CircRuntime` with their own images and `bootLow`, and driven as the other faces drive them — `session.set` for a canvas click and a Data-tab edit, `poke`/`clear` for the Memory tab's grid and Clear, `applyPreloads()` for its hex box, `reset` for the Data tab's Reset — with every event logged through `commandFor` and each `rebuilt` followed by the handshake; then `scriptOf` over that log replayed through the executor on a fresh session of the same circuit, and the page's replies and end state compared with the replay's (a scratch script, not committed).

| Example | What the faces did | Log | Replay |
|---|---|---|---|
| four-bit-adder | `a`=3, `b`=5, `a`=`0x5/0x3`, `a`=`?`, Reset, `a`=0xf, `b`=1 | `> set a 0x3`, `> set b 0x5`, `> set a 0x1 0x3`, `> set a 0x0 0x0`, `> reset` + handshake, `> set a 0xf`, `> set b 0x1`, each with `ok` | 7 script lines; replies equal; end state equal |
| ram-write-read | `a`=2, `d`=0x5a, `we`=1, clock pulse, cell 3 ← 0x77, cell 0 ← unknown, Clear | the five `set`s, `> poke data 0x3 0x77`, `> poke data 0x0 0x0 0x0`, `> clear data` | 8 lines; equal; equal |
| rom-lookup | `pc`=1, image `aa bb` in the hex box, `pc`=0, image emptied, Reset | `> set pc 0x1`, `# code: image from the Memory tab, 2 words`, `> set pc 0x0`, `> clear code`, `> reset` + handshake | 5 lines; equal; equal (an emptied image is a `clear`, which is a command) |
| sr-latch | `s` on, off; `r` on, off (the toggles) | four `set`s with `ok` | 4 lines; equal; equal |

**Files touched:** `DOCS/STATUS.md`
**Tests:** `zig build test-all` on `b60ac03`, result pass (no Zig file touched); the full site gate on the same tree (`bun test` 532 pass, typecheck 0 errors, build, bundle ok), result pass
**Next slice:** the measurement.
**Notes:** no defect. The one end state a replay cannot reproduce is an image that was loaded and then left loaded (the comment names it, a replay's `--mem` would supply it); no example's scenario ends there. The human's browser rows (both themes, the terminal's colours, a copied script through the CLI, the scroll lock, a project switch) are recorded in the completion entry from the human's report.

## 2026-09-11 — Phase 2 — the measurement

**What shipped:** the `/playground` route measured with `bun run bundle` against the plan's start.

| Point | Eager graph (raw / gzip) | Lazy chunks |
|---|---|---|
| Plan start (`46d12c6`) | 104.9 KB / 37.3 KB | unchanged throughout |
| Phase 0, events and the echo | 106.1 KB / 37.7 KB | |
| Phase 1, the bar and the surface | 107.6 KB / 38.2 KB | |
| Final tree (`b60ac03`) | 107.7 KB / 38.2 KB, ceiling 120 KB gzip | |

**Files touched:** `DOCS/STATUS.md`
**Tests:** none (measurement)
**Next slice:** the decisions reread.
**Notes:** the initiative's cost on the eager graph is 2.8 KB raw / 0.9 KB gzip: `commandFor`, `scriptOf`, the richer events, the bar's handlers, the scroll lock and the new-project reset. The stylesheet is not in the budget.

## 2026-09-11 — Phase 2 — the decisions reread

**What shipped:** `DOCS/decisions/playground.md` reread against the plan's eleven locked decisions. Present: 1 (events carry what was driven), 2 (`commandFor`), 3 (a page line looks like a typed line), 4 (the Memory panel through the session), 5 (Copy script), 6 (the toolbar), 7 (autoscroll), 8 (the prompt), 9 (line kinds), 10 (the document), plus the review's addition (a new project is a new terminal). Decision 11 (documentation lands with the code) is the driver plan's entry of that name, which this plan followed; it is not repeated.
**Files touched:** `DOCS/STATUS.md`
**Tests:** `grep -c '^### ' DOCS/decisions/playground.md` → 51, from 40 at the plan's start: eleven entries for ten decisions and one finding.
**Next slice:** the completion entry, once the human has walked the page.
**Notes:** none.

## 2026-09-11 — Phase 2 — completion

**What shipped:** the human walked `/playground` in both themes and approved ("great push and merge"): every face's action in the console in order, the copied script through the CLI, the image comment, the scroll lock, a fresh terminal on a project switch. With the machine half of the walk, the measurement and the decisions reread above, the plan is complete: every phase shipped, every slice committed, nothing left to dispatch.
**Files touched:** `DOCS/STATUS.md`
**Tests:** the full site gate and `zig build test-all` on the final tree, result pass
**Next slice:** none; plan complete. Archive per `DOCS/prompts/ARCHIVE.md` on the human's ask.
**Notes:** follow-ups, none blocking: (1) a replay cannot reproduce an image that was loaded from the Memory tab and left loaded — the comment names it, and `--mem=<mem>=<file>` supplies it on the CLI; a `Copy script` that also offered the images as files would close that. (2) Tab completion of verbs and pin names at the prompt stayed deferred. (3) The console's prompt loop still has no headless test; `commandFor`, `scriptOf` and the executor are the tested core, the loop is the human's walk. (4) `DOCS/sim-protocol.md` is still not synced into the site's reference pages.
