# Phase 1 — The terminal

> **Dependencies:** Phase 0 (the log holds every face; `data-origin` marks page lines).
> **Warnings:** Decisions 5–10. Nothing in this phase changes a line's text: the terminal is colour, layout, three buttons and one pure function. `island-smoke.test.ts` asserts the console's note and an empty log on a fresh page; keep that true. No hard-coded colour in the console's rules.

## Goal

The Console tab reads as the terminal an editor puts under its editing surface. The panel is a dark-or-light surface in the site's code-block colour with a thin bar along its top: a title reading `circ-compile <root>.circ --sim`, and at the right Clear, Copy script and Copy log. The log fills the panel, wraps, and scrolls to the end on a new line unless the reader has scrolled up to read; the prompt is one line at the bottom with a `>` glyph in the accent colour and a borderless input on the same baseline, and clicking anywhere in the panel that is not a selection puts the caret there. Replies are in the text colour, errors in the danger colour, echoes bright with page-originated ones slightly dimmer, comments muted. Copy script puts on the clipboard exactly the lines `--sim` accepts — the commands without their `> ` and the `#` comments — so a log of a session on `ram-write-read` copied, saved as `session.script` and fed to `circ-compile sim_ram_write_read.circ --sim < session.script` replays without an `E_PROTO`. `DOCS/sim-protocol.md` says so, in place of the sentence that claimed the echoes are ignored.

## Scope

**In scope:**
- `site/src/scripts/console.ts`: `scriptOf(lines)`, `Transcript.lines`.
- `Playground.astro`: the `.pg-console-bar` (title, Clear, Copy script, Copy log), the copy handlers and their status sentences, the scroll lock in `consoleAppend`, click-to-focus, `Escape`, the title following the root file.
- `site/src/styles/global.css`: `--term-ok`, `--term-echo` in both themes; the terminal's rules.
- `site/test/console.test.ts` (`scriptOf`), `site/test/island-smoke.test.ts` (the bar and its buttons, the title).
- `DOCS/sim-protocol.md`: the browser section's last bullet corrected.
- `DOCS/decisions/playground.md`: entries for decisions 5–10.

**Explicitly deferred:**
- Tab completion; a jump-to-end affordance; ANSI sequences; a multi-line prompt; persisting anything.

## File & Module Topology

**New files:** None.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/scripts/console.ts` | `scriptOf`; `Transcript.lines`. |
| site | `site/src/components/Playground.astro` | The bar's markup and handlers; the scroll lock; focus; `Escape`; the title. |
| site | `site/src/styles/global.css` | Two tokens; the terminal's rules replacing the Phase 3 console rules. |
| site | `site/test/console.test.ts` | `scriptOf`. |
| site | `site/test/island-smoke.test.ts` | The bar, three buttons, the title's text. |
| site | `DOCS/sim-protocol.md` | The corrected bullet. |
| site | `DOCS/decisions/playground.md` | Decisions 5–10. |

**New dependencies:** None.

## Data & State

```ts
// console.ts
/** The lines `--sim` accepts from a log: echoes without their `> `, comments as they are, replies dropped. */
export function scriptOf(lines: readonly string[]): string[];
// Transcript
get lines(): readonly string[];
```

`scriptOf`: a line starting with `> ` contributes the rest; a line starting with `# ` contributes itself; every other line (`ok…`, `err…`, `ready…`, `pin …`, `diag …`, `vals …`, `mems …`, `mem …`, `cells …`, a hex record, a `pins N` header) contributes nothing. Order kept. A `help` echo contributes `help`, which `--sim` answers with `err E_PROTO malformed command`; the status sentence names the count of lines copied and nothing more, and the document says `help` is the browser's.

Markup, inside `.pg-console` above the log:

```html
<div class="pg-console-bar">
  <span class="pg-console-title">circ-compile main.circ --sim</span>
  <span class="pg-console-actions">
    <button type="button" class="pg-console-btn" data-console="clear" title="Clear the log (Ctrl+L)">Clear</button>
    <button type="button" class="pg-console-btn" data-console="script" title="Copy the commands, as a --sim script">Copy script</button>
    <button type="button" class="pg-console-btn" data-console="log" title="Copy the whole log">Copy log</button>
  </span>
</div>
```

The title follows `rootOf(state.tabs.files).name` wherever `consoleHandshake` reads it, and is refreshed on every session build. Copy handlers: `navigator.clipboard?.writeText(text)`; on success `status.textContent` is `Copied <n> command line(s).` or `Copied the log, <n> line(s).`, with `; the log is capped at 2,000 lines` appended when `transcript.length === transcript.cap`; on absence or refusal, `Clipboard unavailable; select the log and copy it.`; never a throw.

Tokens: `--term-ok` (a green that sits with each palette: muted sage in light, soft mint in dark) and `--term-echo` (the brightest text in each theme: near `--fg` in light, lighter than `--fg` in dark). Rules: `.pg-console` background `--code-bg`, radius 4px, padding 0.5rem 0.65rem, `--font-mono-strict` 0.8rem, line height 1.5; `.pg-console-bar` a flex row, title in `--muted` at 0.72rem, buttons styled as `.pg-dock-toggle`; `.pg-console-log` `flex: 1`, wrapping, `user-select: text`; `.pg-console-line[data-kind="reply"]` `--fg`, `[data-kind="err"]` `--danger`, `[data-kind="echo"]` `--term-echo`, `[data-kind="note"]` `--muted`, `[data-origin="page"]` opacity 0.8; `ok` replies (`consoleKind` stays; the rule matches `[data-kind="reply"]` and a new `data-ok` set when the line starts with `ok`) in `--term-ok`; the prompt line a flex row with `.pg-console-prompt` in `--accent` and `.pg-console-in` transparent, borderless, `caret-color: var(--accent)`, no outline on focus (the panel's own focus ring instead: `.pg-console:focus-within` a 1px `--accent` inset); reduced motion respected.

Scroll lock in `consoleAppend`: `atEnd = log.scrollHeight - log.scrollTop - log.clientHeight <= threshold` measured before appending, with `threshold = 1.5 × the computed line height` (or 24 when unmeasurable); scroll to the end after appending only when `atEnd` or when the call says `{ force: true }` (a submit, `consoleClear`, the handshake at build). Focus: a `click` on `.pg-console` whose target is not a button and whose `window.getSelection()` is collapsed focuses `consoleIn`. `Escape` in the input clears it and resets the history cursor.

## Execution & Concurrency Model

Synchronous, except the clipboard promise, which only sets a status sentence.

## Persistence & I/O

The clipboard, through `navigator.clipboard.writeText`, guarded. Nothing stored.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | `scriptOf` | The function, `Transcript.lines`, tests. | Echoes stripped, comments kept, replies and counted blocks dropped, order kept, an empty log gives `[]`; `Transcript.lines` matches `text.split('\n')`. |
| 2 | The bar | Markup, the three handlers, the title, status sentences, the clipboard guard; `Clear` shares `consoleClear`. | `island-smoke.test.ts`: `.pg-console-bar` with buttons `data-console` `['clear', 'script', 'log']` and a title ending in ` --sim`; clicking Clear on an empty log is harmless; typecheck, build. |
| 3 | The surface | Tokens, rules, the prompt line, focus, `Escape`, the scroll lock, `data-ok`. | `bun test`, typecheck, build, bundle (CSS is not in the JS budget; the JS delta is the handlers); the human's look in both themes: the prompt glyph, the colours, a long log that stays put while scrolled up and follows when at the end. |
| 4 | The document and the decisions | The corrected bullet in `DOCS/sim-protocol.md`; decisions 5–10 in `DOCS/decisions/playground.md`. | The human copies a script from `ram-write-read` and replays it through `circ-compile tests/fixtures/circuits/sim_ram_write_read.circ --sim` with no `E_PROTO`. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `a script is the commands and the comments, nothing else` | `console.test.ts` | The `scriptOf` table above. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `island-smoke.test.ts` | built page | The bar, its three buttons, the title; the note and the empty log as before. |
| `sim-transcripts.test.ts` | | Unchanged and green. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- `TODO(phase1)`: whether `Copy script` should drop the `help` echo. Decision 5 says commands and comments only, and `help` is a command the reader typed; it stays, and the document says the CLI refuses it. Reopen only if the human's replay finds it a nuisance.
- `TODO(phase1)`: the two greens. Slice 3 picks them against the palette in both themes and records the hexes in STATUS; the plan fixes only that they are tokens.
