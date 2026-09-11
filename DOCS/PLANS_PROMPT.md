# Plan Prompt — Console polish (the log of every face, in a terminal)

## What Is Being Built

The playground's console (`DOCS/archive/plan-playground-driver.md`) prints exactly what `circ-compile --sim` prints, for lines the reader types. Two things are missing. First, the console is blind to the other faces: a pin clicked on the canvas, a value typed on the Data tab, a cell written in the Memory tab, a Reset pressed, all drive the same session and leave no line in the log, so the log is not the story of what the reader did and cannot be replayed as one. Second, the Console tab is a plain `<pre>` and an `<input>`: it reads as a form, not as the terminal an editor puts under its editing surface.

This initiative makes the console the record of every face and dresses it as a terminal. Every drive that reaches the session from a face other than the console is echoed as the protocol line that would have done the same thing, with the reply the session gave: a canvas click on `a` prints `> set a 0x1` then `ok`; a Data-tab edit of a bus prints `> set a 0xa`; a partly-unknown value prints its mask, `> set a 0x5 0x3`; a cell written in the Memory tab's grid prints `> poke data 0x2 0x5a`; its Clear prints `> clear data`; the Data tab's Reset prints `> reset`, `ok` and the handshake, as the console's own `reset` does; a ROM image edited or loaded in the Memory tab, which the browser applies as a `--mem` preload rather than a `load`, prints a `#` comment naming the memory and the word count, so the log stays honest about what a script would need. The lines are the same text a reader would have typed, marked only for the stylesheet as the page's rather than the prompt's. To make that possible with one owner of the runtime, the Memory panel's RAM writes and clears go through the session (they still call the runtime directly, a leftover of the panel's move), and the session's events carry what was driven, not just which names. The terminal look is a surface in the site's code-block colour with a small toolbar an editor's terminal has — Clear, Copy script, Copy log — a shell-style prompt glyph on the input line, click-anywhere focus, autoscroll that holds still while the reader is scrolled up, and line colours by kind; `Copy script` copies the commands and comments only, without the `> ` marks and without replies, which is what `--sim` accepts, and `DOCS/sim-protocol.md`'s browser section is corrected to say so (today it claims the echoes are ignored, and they are not: `--sim` answers `> set a 1` with `err E_PROTO malformed command`).

The compiler, the renderer and the executor do not change: the four transcript goldens still replay byte for byte, because a typed line's reply is still the executor's. **Definition of done:** on `/playground` with `four-bit-adder`, clicking `a` on the canvas, toggling `b` on the Data tab and typing `0xa` into `a` each print their `set` line and `ok` in the console in the order they happened; on `ram-write-read`, writing a cell in the Memory tab prints `> poke data …` and `ok`, its Clear prints `> clear data`; pressing the Data tab's Reset prints `> reset`, `ok` and the handshake; on `rom-lookup`, editing the image prints a `# code …` comment; `Copy script` on that log, saved as a `.script` and fed to `circ-compile --sim`, replays every command without an `E_PROTO`; the console reads as an editor's terminal in both themes; `bun test`, `bun --bun run typecheck`, `bun --bun run build` and `bun run bundle` are green with no ceiling raised; `zig build test-all` is untouched; the human has reviewed each phase on the page.

## Tech Stack

- **Site:** Astro 5 island `site/src/components/Playground.astro` (3,400 lines; every behaviour a test can reach lives in a `.ts` module under `site/src/scripts/` or `site/src/utils/`), TypeScript, bun (`bun test` with happy-dom; no canvas, no worker). Gates: `bun test`, `bun --bun run typecheck`, `bun --bun run build`, `bun run bundle` (`/playground` at 104.9 KB raw / 37.3 KB gzip of a 120 KB gzip ceiling; lazy chunks measured but not gated).
- **The console today:** `site/src/scripts/console.ts` (`HistoryRing`, `Transcript`, `MemoryTabFiles`, `promptEcho`, `helpLines`, `HELP_VERB`), `site/src/scripts/sim-executor.ts` (`handshake`, `execute`), `site/src/scripts/sim-protocol.ts` (`parseLine`, `parseValue`, `writeHex`); in the island the `// ---- the console ----` section (`consoleState { transcript, history, files, busy, rebuilt }`, `consoleAppend`, `consoleKind`, `consoleClear`, `refreshConsoleGate`, `consoleHandshake`, `consoleSubmit`) and the session listener in `ensureSession` (`drive`/`memory` → refresh the faces; `rebuilt` → `# reset` and the handshake, deferred while a line runs; `destroyed` → `# session ended`). Markup: `.pg-console` with `.pg-console-note`, `.pg-console-log` (spans `.pg-console-line[data-kind=reply|err|echo|note]`), `.pg-console-form` with `.pg-console-prompt` and `.pg-console-in`; styles under `/* The console */` in `site/src/styles/global.css`.
- **The session:** `site/src/scripts/sim-session.ts`; `SessionEvent` is `drive { names }`, `memory { name }`, `rebuilt`, `destroyed`; `set`/`eval`/`poke`/`clear`/`loadImage`/`applyPreloads`/`reset` emit them; `notifyExternal(names)` is the canvas's path (`onPinChange` in `buildCanvas`, which records `sim.pins` first).
- **The other faces:** the Data tab (`data-view.ts`: `editRow`/`toggleRow` → `session.set`; the island's `dataReset` → `session.reset()`); the Memory panel in the drawer (`writeLiveWord` → `host.writeMemWord`, `clearMemory` → `host.clearMem` for a RAM, `setImage` → `applyToView` → `session.applyPreloads()` for a ROM).
- **Colour tokens:** `site/src/styles/global.css` `:root` and `[data-theme="dark"]`: `--bg`, `--fg`, `--muted`, `--border`, `--accent`, `--accent-soft`, `--code-bg`, `--pane-bg`, `--pane-label-bg`, `--danger`; fonts `--font-mono`, `--font-mono-strict`.
- **Protocol reference:** `DOCS/sim-protocol.md` (the CLI's grammar and its browser section), `lib/sim/protocol.zig`, `tests/fixtures/sim/*.script` → `tests/fixtures/expected-sim/*.txt` replayed by `site/test/sim-transcripts.test.ts`.

## Architectural Constraints

- **The log is what the CLI would have printed for what the reader did.** A page-originated line is spelled by one pure function over the session's event (`commandFor` in `console.ts`), in the protocol's grammar (`writeHex`, a mask only when the value is not wholly known), and its reply is the session's actual outcome — `ok` for a drive the session accepted; nothing is invented. The executor is not re-run for a face's action: the drive already happened, and a second `set clk 1` is not a second edge but is a second line.
- **One owner of the runtime, still.** Every write from a face goes through the session (`set`, `poke`, `clear`, `applyPreloads`, `reset`); the Memory panel's two direct runtime calls move to `session.poke`/`session.clear` in this initiative. The session's events carry the details a face needs to spell the command; no face reads another face's state to reconstruct it.
- **A console-typed line is echoed once.** The console's own drives also emit session events; the island distinguishes them by the `consoleState.busy` flag that already defers `rebuilt`, never by a tag on the session's API.
- **The executor, the protocol and the goldens do not change.** `sim-executor.ts`, `sim-protocol.ts` and `site/test/sim-transcripts.test.ts` are read-only in this plan; a change there is out of scope.
- **The terminal is the site's palette.** Surface `--code-bg`, text `--fg`, dim `--muted`, prompt `--accent`, errors `--danger`, plus at most two new tokens (`--term-ok`, `--term-echo`) defined in both `:root` and `[data-theme="dark"]`; no hard-coded colour in the console's rules; reduced motion respected.
- **Values are spelled the protocol's way in the log** (`0x` hex), whatever base the Data tab or the canvas showed the reader; the log is a transcript, not a view.
- **The per-page JavaScript budget is the gate** (`DOCS/decisions/playground.md`); the console's additions ride in the eager bundle as the console does; the number is recorded per phase.
- **Nothing new is persisted.** Transcript, history and the scroll lock are session state.
- **Git conduct per `CLAUDE.md`:** stage by path, Conventional Commits under 70 characters (scope `site`), no phase or slice prefixes, no trailers, never push; this plan lives on the `playground-driver` branch, after its first archive, by the human's ask.

**Locked decisions.** Routine calls made at plan time so no slice reopens them. Each phase appends the ones it exercises to `DOCS/decisions/playground.md`.

1. **Session events carry what was driven.** `drive` becomes `{ kind: 'drive'; assigns: { name: string; value: bigint; defined: bigint }[] }` (`names` derived, kept for the faces that only refresh); `memory` becomes `{ kind: 'memory'; name: string; op: 'poke' | 'clear' | 'load'; addr?: bigint; value?: bigint; defined?: bigint; words?: number }`; `applyPreloads` emits one `load` per image it applied (and a `clear` for an emptied one); `notifyExternal(assigns)` takes the values the canvas drove, which `onPinChange` already has. `rebuilt` and `destroyed` are unchanged.
2. **`commandFor(event, session)` is the one spelling.** In `console.ts`: `drive` → one `set <name> <hex>` per assign, with ` <mask>` appended only when `defined` is not the full width mask (a wholly unknown pin is `set a 0x0 0x0`); `memory` `poke` → `poke <mem> <hexaddr> <hex>[ <mask>]`; `clear` → `clear <mem>`; `load` → the comment `# <mem>: image from the Memory tab, <n> words` (the browser refuses `load`, so no command is claimed); `rebuilt` → `reset`. Each line is returned with the reply the session gave: `ok` for every accepted drive and memory op, none for a comment, and for `reset` the handshake follows as it does for the typed verb.
3. **A page line looks like a typed line and is marked for the stylesheet only.** The echo is `promptEcho(command)` (`> …`); the span carries `data-origin="page"`; the text is byte-identical to what typing it would have shown. The `# reset` comment the Phase 3 console printed on `rebuilt` goes away: `> reset` says it.
4. **The Memory panel writes through the session.** `writeLiveWord` → `session.poke(name, addr, value, defined)`, `clearMemory` (RAM) → `session.clear(name)`; the panel's status sentences stay; `memHost()` remains the read path. A ROM edit stays an image edit (`setImage` → `applyPreloads`), which is why it logs as a comment.
5. **`Copy script` is the commands only.** `scriptOf(transcript)` in `console.ts` keeps the echo lines with their `> ` stripped and the `#` comments, and drops every reply (`ok…`, `err…`, counted blocks, `ready`/`pin`/`diag`); `Copy log` is `transcript.text`. Both copy through `navigator.clipboard.writeText`, with the status span announcing the line count; a clipboard refusal is a status sentence, never a throw.
6. **The toolbar is the drawer strip's, not the log's.** Clear, Copy script and Copy log are small buttons at the right of the Console panel's own top edge (a `.pg-console-bar` above the log), styled as the dock's toggle is, so the log keeps its full width; `Ctrl+L` stays.
7. **Autoscroll holds while the reader reads.** The log scrolls to the end on a new line only when it was already at the end (within one line); a reader scrolled up stays put, and a `▼` affordance is not built — pressing End in the prompt or submitting a line scrolls to the end.
8. **The prompt is one line in the terminal.** The input has no border or background of its own; a `>` glyph in `--accent` precedes it on the same baseline; the whole `.pg-console` focuses the input on click unless the click is a selection; `Escape` clears the line; the caret is the browser's.
9. **Line kinds are the stylesheet's.** `consoleKind` stays the classifier (`err`, `echo`, `note`, `reply`); the terminal colours `ok…` replies and counted-block records in `--fg`, `err` in `--danger`, echoes in `--term-echo` with the `>` glyph in `--accent`, notes in `--muted`; page-originated echoes are the same colour at reduced opacity. No line gets an icon or a prefix beyond its text.
10. **The document says what a script can take.** `DOCS/sim-protocol.md`'s browser section replaces "the echoes and comments are ignored" with the truth: `Copy script` gives the lines `--sim` accepts; the log as copied whole is a transcript, not a script.
11. **Documentation lands with the code.** The decisions each phase exercises go into `DOCS/decisions/playground.md` at the phase's close; the archive is produced per `DOCS/prompts/ARCHIVE.md` when the human asks, as `DOCS/archive/plan-console-polish.md`.

## Phase Index

| Phase | Name | What Ships |
|-------|------|-----------|
| 0 | The log of every face | Session events with their details (decision 1) and `notifyExternal(assigns)`; the Memory panel's RAM write and clear through the session (decision 4); `commandFor` and its tests (decision 2); the island echoing page-originated events with their replies, `data-origin="page"`, the console's own lines once, `> reset` in place of `# reset` (decision 3) — proof is `console.test.ts` covering every event shape, `sim-session.test.ts` asserting the new event payloads, the four transcripts unchanged, and the definition of done's canvas, Data-tab, Memory-tab and Reset lines on the page. |
| 1 | The terminal | The `.pg-console-bar` with Clear, Copy script and Copy log (decisions 5, 6), `scriptOf` and its tests, the surface and tokens, the prompt line and click-to-focus, the scroll lock, line colours (decisions 7, 8, 9), the document's correction (decision 10) — proof is `console.test.ts` for `scriptOf`, `island-smoke.test.ts` asserting the bar and its three buttons, the bundle within budget, and the human's look in both themes with a copied script replayed through `circ-compile --sim`. |
| 2 | Sweep and record | The human's walk of the definition of done on `four-bit-adder`, `ram-write-read`, `rom-lookup` and `sr-latch` in both themes; the bundle measured against the plan's start; the decisions entries checked; the completion entry with follow-ups — proof is a STATUS entry naming what the review found. |

Phases are ordered by dependency, not by priority. Each phase must be fully shippable before the next begins.

**Explicitly deferred, and not to be smuggled into a slice:** tab completion of verbs or pin names; a `▼ jump to end` affordance; persisting the transcript or the history; a `load` that reads the Memory tab's image (files stay the Memory tab's); logging hover, selection or tab switches (not drives); ANSI colour sequences in the log text; a multi-line prompt; changing any executor reply; a renderer or compiler change.

**Sequencing notes for the execution agent.** Phase 0 first because the terminal's `Copy script` is worth having only once the log holds every face's commands, and because moving the Memory panel onto the session is a correctness change the look must not hide. Phase 1 is CSS, three buttons and one pure function, and lands second so its review is about the look. Phase 2 is the review of the whole.

**Slice seams handed to the deep planner.** `DOCS/prompts/PHASE_DEEP_PLANNER.md` owns each phase's `## Slices` table; once `DOCS/PLANS/PHASE_<N>_<name>.md` exists its table is authoritative. Pre-agreed seams:

- **Phase 0:** (1) the session's event payloads and `notifyExternal(assigns)`, with `sim-session.test.ts` updated and the island's `onPinChange` passing values; (2) the Memory panel through `session.poke`/`session.clear`, `memory-panel` behaviour unchanged on the page; (3) `commandFor` in `console.ts` with tests over every event shape and mask case; (4) the island echoing page events with replies and `data-origin`, `> reset` replacing `# reset`, the human's check.
- **Phase 1:** (1) `scriptOf` with tests; (2) the bar, the copies and the clipboard sentences; (3) the terminal surface, the prompt line, the scroll lock and the line colours; (4) the document's correction and the decisions entries.

## Working Loop

The execution agent follows this loop every session without exception:

### On Cold Start

1. Read this file (`DOCS/PLANS_PROMPT.md`) in full.
2. Read `DOCS/STATUS.md` (if it exists). The latest entry defines what was last shipped and what comes next.
3. Run `git log --oneline -10` and `git status`. If STATUS claims a slice is committed but it does not appear in `git log`, the human has not committed yet — **do not begin a new slice**. Stop and say so.
4. Read the active phase plan (`DOCS/PLANS/PHASE_<N>_<name>.md`) for the current phase.
5. Implement the next slice per the phase plan. Do not start a second slice until the first is reviewed and committed.

### Each Slice

1. Implement the full slice as specified. Do not stop mid-slice.
2. Run the gates for what the slice touched: `bun test`, `bun --bun run typecheck`, `bun --bun run build`, `bun run bundle` in `site/`. Do not ship a slice that breaks a suite.
3. Append a STATUS entry (template below).
4. Stage the slice's files (`git add <files>`), by path.
5. Display the proposed commit message and **stop**. Wait for explicit human approval before running `git commit`. Do not begin the next slice until the commit is confirmed and made.

### Git Rules

- Read-only git commands (`status`, `log`, `diff`) are encouraged for situational awareness.
- **Committing:** At the end of a slice — and only at the end of a slice — the agent stages the slice's files (`git add <files>`), then displays the full proposed commit message to the human and waits for explicit approval before running `git commit`. Staging first lets the human inspect the diff in any git client before approving. Do not commit without that confirmation.
- Do **not** push, force-push, amend, rebase, reset, delete branches, or run any other write `git` or `gh` command under any circumstances.

## STATUS Entry Template

Append to `DOCS/STATUS.md` at the end of every slice. Never overwrite or edit prior entries.

```
## YYYY-MM-DD — Phase N — <slice title>

**What shipped:** <one or two sentences>
**Files touched:** `<file>`, `<file>`
**Tests:** added <names>, ran `<command>`, result <pass/fail>
**Next slice:** <one sentence>
**Notes:** <anything the next session needs that isn't obvious from the code>
```

## Recurring Traps

Add an entry here during execution whenever a non-obvious constraint surfaces — in the same slice that hit it, under the group it belongs to — and name it in that slice's STATUS entry `Notes:` line.

**The session and its faces**

- The canvas drives the runtime itself before `onPinChange` fires; `notifyExternal` must carry the value the canvas drove (`PinValue { value, defined }` as `sim.pins` records it), never re-drive it.
- A console-typed `set` emits a `drive` event too; the island's listener must check `consoleState.busy` before echoing, or every typed line appears twice.
- `eval` emits one `drive` with several assigns; only the console types `eval`, so a page-originated `drive` has one assign per pin changed — spell each as its own `set` all the same.
- `applyPreloads` runs at build and at `reset` as well as after an image edit; the handshake, not a comment, is what the reader expects at build and after `reset`, so the island echoes `load` comments only outside those two moments (the `rebuilt` handler and `ensureSession` know when they run).
- The Memory panel's ROM edits reach the runtime through `applyPreloads` → `loadMemImage`, never through `session.loadImage`; the comment, not a `load` line, is the honest record.

**The console**

- `Transcript` caps at 2,000 lines and `consoleAppend` trims the DOM to match; `scriptOf` reads the transcript, so a very long session's script is its newest lines only — say so in the status sentence when the cap was hit.
- happy-dom has no `navigator.clipboard`; the copy handlers must guard its absence, and the smoke test asserts the buttons exist, not that they copy.
- `scrollTop`/`scrollHeight` are zero in happy-dom; the scroll lock's arithmetic must tolerate a zero-height log.

**Tests**

- `site/test/sim-transcripts.test.ts` must stay byte for byte green through every slice: the executor's replies are the goldens', and nothing here may touch them.
- `island-smoke.test.ts` asserts the console's note text and an empty log on a fresh page; a handshake or a comment printed at mount would break it.
