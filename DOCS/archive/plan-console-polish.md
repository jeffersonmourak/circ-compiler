# Archived plan: console-polish

**Canonical commit:** `5663a837d87a7ca8c409fd09522ef9106195b37e` (`5663a83 docs: sign off the console polish plan`)
**Archived on:** 2026-09-11
**Plan duration:** 2026-09-11 → 2026-09-11

> This file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the commit referenced above. Check that commit out (`git show 5663a837d87a7ca8c409fd09522ef9106195b37e:DOCS/PLANS_PROMPT.md`, `…:DOCS/PLANS/PHASE_1_the_terminal.md`, `…:DOCS/STATUS.md`, etc.) when you need the unabridged source.

## Goal & scope

The playground's console (`DOCS/archive/plan-playground-driver.md`) printed exactly what `circ-compile --sim` prints, for lines the reader typed, and nothing for what the other faces did: a pin clicked on the canvas, a value typed on the Data tab, a cell written in the Memory tab or a Reset pressed drove the same session and left no line, so the log was not the story of the reader's session and could not be replayed as one. It also read as a form — a `<pre>` and an `<input>` — not as the terminal an editor puts under its editing surface. This initiative, on the same `playground-driver` branch after the driver plan's archive, made the console the record of every face and dressed it as a terminal. Every drive that reaches the session from another face is echoed as the protocol line that would have done the same thing, byte-identical to a typed line, with the session's reply after it; a ROM image applied from the Memory tab, which the browser applies as a `--mem` preload and refuses as `load`, is a `#` comment naming the memory and its word count. The Memory panel's RAM writes and clears, which still called the runtime directly, moved onto the session, so one owner of the runtime holds again. The terminal is a surface in the site's code-block colour with a bar naming the command it runs (`circ-compile <root>.circ --sim`) and Clear, Copy script and Copy log; a shell-style prompt line; click-anywhere focus; an autoscroll that holds while the reader is scrolled up; line colours by kind; and a fresh log on every project switch. `Copy script` gives only the lines `--sim` accepts, and `DOCS/sim-protocol.md` was corrected to say so: it had claimed the echoes are ignored, and `--sim` answers `> set a 1` with `err E_PROTO malformed command`. Anchors that held: the executor, the grammar and the four transcript goldens untouched; the compiler and the renderer untouched; the console's own lines told apart from a face's by the busy flag it already had, never by a tag on the session's API; every colour a token in both themes.

## Phase-by-phase highlights

### Phase 0 — The log of every face

Every drive from another face leaves the line typing it would have left, with the session's reply.

- `sim-session.ts`: `DriveAssign`; a `drive` event carries `assigns` (name, value, the mask the runtime received); a `memory` event carries its `op` — `poke` with `addr`/`value`/`defined`, `clear`, `load` with `words`; `notifyExternal(assigns)` takes what the canvas drove; `applyPreloads({ silent })` reports a `load` or a `clear` per image unless silent, and the build and `reset` apply silently so the handshake stays the record of those moments.
- The Memory panel's `writeLiveWord` and RAM `clearMemory` call `session.poke`/`session.clear`; no `host.writeMemWord` or `host.clearMem` is left in the island.
- `console.ts`: `commandFor(event, session)` — one `> set <pin> <hex>` per assign with the mask only when the pin is not wholly known, `> poke`, `> clear`, each followed by `ok`; `# <mem>: image from the Memory tab, <n> word(s)`; `> reset`, `ok`; nothing for `destroyed`. Values canonical (`value & defined`). `WidthSource` is what it reads of a session.
- The island's listener appends `commandFor` lines with `data-origin="page"` for `drive`/`memory` events when the console is not running a line, and `> reset`, `ok` and the handshake on a `rebuilt` from another face; the console's own `reset`/`quit` print only the handshake after their reply. The `# reset` comment is gone.
- `site/test/sim-session.test.ts` asserts the payloads and the silent/loud preloads; `site/test/console.test.ts` covers `commandFor` over every event shape, every echo re-parsing once its mark is stripped.

### Phase 1 — The terminal

Three buttons, one pure function, and the stylesheet.

- `console.ts`: `scriptOf(lines)` keeps an echo without its `> ` and a `#` comment, and drops every reply; `Transcript.lines`.
- The `.pg-console-bar`: a title following the root file with every handshake, and Clear, Copy script, Copy log (`data-console` `clear|script|log`); copies through `navigator.clipboard.writeText`, guarded, with the status span saying `Copied <n> command line(s).`, `Copied the log, <n> line(s).`, the 2,000-line cap named when hit, or `Clipboard unavailable; select the log and copy it.`.
- Tokens `--term-ok` (`#3f7d5c` light, `#8fd3a8` dark) and `--term-echo` (`#2d2140` light, `#ece4f8` dark); `.pg-console` on `--code-bg` with an inset accent ring while focused; `ok` replies in `--term-ok` (`data-ok`), errors in `--danger`, echoes in `--term-echo` with the `>` in `--accent`, comments in `--muted`, page-originated lines at 0.8 opacity; the prompt one line with a bold accent glyph and a borderless transparent input.
- Behaviour: the log follows a new line only when at its end (a line and a half's slack), always on a submit or a handshake; a click in the panel that is not a button, an input or a selection focuses the prompt; `Escape` clears the line; `Ctrl+L` stays.
- Review addition: `loadProject` on a different project id calls `consoleNewSession` — log and history cleared, the dropped session's `# session ended` skipped, the next handshake the first line. Edits within a project keep the log.
- `DOCS/sim-protocol.md`'s browser section: the log records every face; `help` is refused by the CLI; `Copy script` is the script, the log a transcript.
- `island-smoke.test.ts`: the title's shape, the three buttons in order, Clear on an empty log harmless, Copy script's sentence after the clipboard's microtask.

### Phase 2 — Sweep and record

- The machine walk: `four-bit-adder`, `ram-write-read`, `rom-lookup` and `sr-latch` driven as the other faces drive them, every event logged through `commandFor`, the log's script replayed on a fresh session; replies and end states equal in all four. The human's walk in both themes: every action in the log in order, a copied script through the CLI, the image comment, the scroll lock, a fresh terminal on a project switch. No defect.
- The measurement: the eager `/playground` graph 104.9 → 107.7 KB raw, 37.3 → 38.2 KB gzip of a 120 KB ceiling; lazy chunks unchanged.
- `DOCS/decisions/playground.md` grew eleven entries; `zig build test-all` green and untouched.

## API surface frozen by the plan

No diagnostic code, runtime export or CLI flag changed; the compiler, the renderer, the executor and the grammar are untouched. The surfaces this plan added or changed:

| Surface | Where | Contract |
| --- | --- | --- |
| `DriveAssign` | `site/src/scripts/sim-session.ts` | `{ name, value, defined }`, the values as driven. |
| `SessionEvent` | same | `drive { names, assigns }`; `memory { name, op: 'poke', addr, value, defined } \| { op: 'clear' } \| { op: 'load', words }`; `rebuilt`; `destroyed`. |
| `notifyExternal(assigns)` | same | The canvas's path, with the values it drove. |
| `applyPreloads({ silent? })` | same | Loud from a face (`load`/`clear` per image); silent at build and `reset`. |
| `commandFor(event, session)`, `WidthSource` | `site/src/scripts/console.ts` | A face's event as the console's lines. |
| `scriptOf(lines)`, `Transcript.lines` | same | The lines `--sim` accepts from a log. |
| The console's markup | `Playground.astro` | `.pg-console-bar` with `.pg-console-title` and `.pg-console-btn[data-console=clear\|script\|log]`; `.pg-console-line[data-kind][data-ok][data-origin="page"]`. |
| Tokens | `site/src/styles/global.css` | `--term-ok`, `--term-echo`, in `:root` and `[data-theme="dark"]`. |
| The browser's protocol differences | `DOCS/sim-protocol.md` | The log records every face; `help` refused by the CLI; `Copy script` is the script. |

## Known papercuts carried forward

- **An image loaded from the Memory tab and left loaded cannot be reproduced by a replay**; the comment names it, and `--mem=<mem>=<file>` supplies it on the CLI. A `Copy script` that also offered the images as files would close that.
- **Tab completion** of verbs and pin names at the prompt stayed deferred.
- **The console's prompt loop has no headless test**; `commandFor`, `scriptOf` and the executor are the tested core, the loop is the human's walk.
- **`DOCS/sim-protocol.md` is still not synced** into the site's reference pages.
- **A copied `help`** prints one `E_PROTO` when replayed; the document says so.

## Decisions & specs that survived the plan

- `DOCS/decisions/playground.md` — eleven entries appended: session events carry what was driven; `commandFor` is the one spelling; a page line looks like a typed line; the Memory panel writes through the session; `Copy script` is the commands only; the toolbar is the console's own top edge; autoscroll holds while the reader reads; the prompt is one line in the terminal; line kinds are the stylesheet's; the document says what a script can take; a new project is a new terminal.
- `DOCS/sim-protocol.md` — "The protocol in the browser", corrected.
- `site/test/console.test.ts`, `site/test/sim-session.test.ts`, `site/test/island-smoke.test.ts`, `site/test/sim-transcripts.test.ts` — the guards that hold the decisions above.
