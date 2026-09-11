# Phase 0 — The handoff and the frame

> **Dependencies:** None
> **Warnings:** Read `DOCS/PLANS_PROMPT.md` decisions 1, 2, 3, 4, 6, 12 and 16 before starting, and the handoff's `README.md` sections *Frame*, *Nav*, *Terminal line* and *Status line*. Decision 2 applies from the first slice: where the README and the inline styles of `Playground Upgrade.dc.html` disagree, the file wins. Two facts the plan prompt states loosely and the tree corrects: `--danger` already exists in both token blocks (`global.css:37`, `:70`; `app-layout.test.ts` asserts it), so decision 4 is met before this phase writes a line; and the handoff carries 32 JetBrains Mono `.ttf` files, not 36. Every slice ends with the four gates green in `site/`; slices 3–6 also need a fresh `bun --bun run build` before `bun test`, or `island-smoke` skips and proves nothing.

## Goal

The playground stands in the bench's frame with everything it does today still inside it. A reader opens `/playground` and sees no site nav and no site footer: a 48px bench nav (the wordmark, a breadcrumb naming the open project, the status cluster, Download, Share, the theme toggle), the source on `--pane-bg` and the canvas region on `--bg` with a dot grid, one hairline between them, a 40px terminal line reading `circ-compile nand.circ --sim > set a 1 · ok`, and a 24px status line with the compiler identity, the signature and the promise. The breadcrumb opens today's workspace tree in a card; the canvas region still shows today's four tabs; the terminal line opens today's drawer. The handoff is tracked under `DOCS/design/` without its noise, `bench-tokens.test.ts` holds every colour and face in a `.pg-*` rule to a token, and `island-smoke` walks the new DOM. Board 2a's frame is what the reader sees in both modes; boards 3a–3f are later phases.

## Scope

**In scope:**
- The handoff committed per decision 3 and the noise removed from the working tree; `DOCS/index.md` pointing at the plan.
- `Base.astro`'s `app` variant rendering no `<Nav />` and no `<Footer />` (decision 1); the body's grid reduced to one viewport row; `main` without padding.
- The frame: `.pg` as `grid-template-rows: 48px minmax(0, 1fr) var(--pg-term-h, 40px) 24px`; `.pg-body` as `grid-template-columns: var(--pg-source-w, 480px) 1px minmax(0, 1fr)`; the dot grid; the hairline; no pane borders.
- The bench nav: wordmark, breadcrumb button, status cluster (moved from `.pg-statusbar`), Download and Share (moved, restyled), `ThemeToggle.astro`.
- The status line: identity, `.signature`/`.heart` verbatim, the promise, and the `role="status"` channel.
- The terminal line, closed: the command title, the last command and its reply from a pure `summaryOf`, `Console ▴` and `Memory`; the drawer's body under it when open, at `--pg-term-h: 320px`.
- The source column on `--pg-source-w` in pixels through the existing splitter (decision 6), unpersisted for the length of this phase (see Data & State).
- Two bridges that keep the page shippable: today's `.pg-ws` tree shown as a card under the breadcrumb, and today's `.pg-tabs` and panels inside the canvas region.
- `site/test/bench-tokens.test.ts` (decision 12); `app-layout.test.ts` and `island-smoke.test.ts` updated; `terminal-line.test.ts` and the splitter's pixel helpers tested.
- `DOCS/decisions/playground-bench.md` created and registered, with the entries for decisions 1, 3, 4, 6 and 12.

**Explicitly deferred:**
- The file-tab strip, the editor padding, the diagnostics footer, settings, the store migration (Phase 1).
- The view switch, the Data button, the hint and zoom lines, `viewport: 'parent'` (Phase 2).
- The switcher card's own markup, search and scrim (Phase 4); the terminal line's grown state and the console and memory restyle (Phase 6); the drawer splitter on `--pg-drawer-h` (Phase 6).
- Persisting the source width (Phase 1, decision 5).
- The stacked layout below 800px beyond "the regions stack and every control is reachable" (decision 15; Phase 7 checks it).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/terminal-line.ts` | `summaryOf(lines)`: the last echo and the reply that followed it, for the closed terminal line. Pure; no DOM. |
| site | `site/test/terminal-line.test.ts` | Drives `summaryOf` over transcripts built from `promptEcho` and the protocol's reply spellings. |
| site | `site/test/bench-tokens.test.ts` | Parses every `.pg-` rule of `global.css` and holds each colour and face to a token (decision 12). |
| docs | `DOCS/decisions/playground-bench.md` | The initiative's decisions, appended per phase; registered in `DOCS/decisions/index.md`. |
| docs | `DOCS/design/design_handoff_playground_bench/**` | The handoff, tracked per decision 3 (already on disk; slice 1 trims and stages it). |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/layouts/Base.astro` | `{layout !== 'app' && <Nav />}` and `{layout !== 'app' && <Footer />}` around `Base.astro:84` and `:88`; the prop doc at `:15-21` says the app variant brings its own chrome. |
| site | `site/src/components/Playground.astro` | Markup: `.pg-banner` moves into the source region above the editor; `.pg-panes` becomes `.pg-body`; the `<nav class="pg-ws">` becomes the card under a new `.pg-nav`; `.pg-statusbar` (`:331-356`) is split into `.pg-nav` (status cluster, actions, theme toggle) and `.pg-statusline`; `.pg-drawer` and `.pg-drawer-splitter` leave `.pg-output` (`:234-329`) for `.pg-term`, row 3. Script: `init`'s selectors (`:497-556`) follow the moves; `wsToggle` (`:520`, `:1638-1642`) becomes the breadcrumb; `refreshActions` (`:1734-1745`) writes the name and size into the Download button; the terminal line is rendered from `consoleAppend`/`consoleClear`/`consoleNewSession` (`:812-845`); `setDrawerShown` (`:753`) goes, the line is always shown; the main splitter (`:2506-2514`) runs in pixel mode on `.pg-body`. |
| site | `site/src/scripts/splitter.ts` | A `unit: 'ratio' \| 'px'` option: in `'px'` the intent is pixels, `render()` writes `${clamped}px`, bounds are `minPanePx` on both sides, keys step `16` and `64` px, `Home`/`End` hit the bounds, `aria-valuenow` is the percentage of the container as today. Pure helpers `clampPx`, `pxFromPointer`, `stepPx`. |
| site | `site/src/styles/global.css` | `[data-layout='app']` block (`:1683-1717`): one viewport row, `main` at `padding: 0`; `.pg` rules (`:547-556`, `:1720-1733`) become the frame; `.pg-panes` (`:557-565`, `:1988-2004`) becomes `.pg-body`; `.pg-editor, .pg-output` (`:566-574`) lose border, radius and `min-height`; `.pg-ws` (`:1739-1764`, `:2006`) becomes the card; `.pg-statusbar` (`:1921-1931`), `.pg-status-spacer`, `.pg-status-actions`, `.pg-action*` (`:1932-1972`) are replaced by `.pg-nav*` and `.pg-statusline*`; `.pg-drawer` height rules (`:1035-1150`) are reached through `.pg-term`; the 800px block (`:2042-2060`) stacks `.pg-body` and releases the lock as today. |
| site | `site/test/app-layout.test.ts` | Chain `['.pg', '.pg-body']`; the rows branch; `Base.astro` guards for decision 1; the frame's four tracks. |
| site | `site/test/island-smoke.test.ts` | Selectors follow the moves (`:291-300`, `:350-383`, `:734-793`); new assertions for the nav, the breadcrumb, the terminal line. |
| site | `site/test/splitter.test.ts` | The pixel helpers. |
| docs | `DOCS/index.md` | A row for `PLANS_PROMPT.md` under *Documents*, as the archive prompt expects to remove later. |
| docs | `DOCS/decisions/index.md` | The new file registered. |

**New dependencies:** None.

## Data & State

The frame, as CSS custom properties on the island root, all read by exactly one rule each:

```css
/* global.css — the bench frame (every rule scoped to [data-layout='app']) */
[data-layout='app'] { height: 100vh; height: 100dvh; display: grid; grid-template-rows: 100vh; grid-template-rows: 100dvh; overflow: hidden; }
[data-layout='app'] main { padding: 0; max-width: none; margin: 0; min-height: 0; display: flex; flex-direction: column; }
[data-layout='app'] .pg {
  flex: 1; min-height: 0; margin: 0;
  display: grid;
  grid-template-rows: 48px minmax(0, 1fr) var(--pg-term-h, 40px) 24px;   /* nav · body · terminal line · status line */
}
[data-layout='app'] .pg-term[data-open='true'] { --pg-term-h: 320px; }      /* set on .pg, see below */
[data-layout='app'] .pg-body {
  min-height: 0;
  display: grid;
  grid-template-columns: var(--pg-source-w, 480px) 1px minmax(0, 1fr);   /* source · hairline · canvas */
}
.pg-source-region { background: var(--pane-bg); display: flex; flex-direction: column; min-height: 0; }
.pg-hairline { background: var(--border); }
.pg-canvas-region { position: relative; min-height: 0; overflow: hidden; background: var(--bg); }
.pg-canvas-region::before {                                                 /* the dot grid, file :1066 */
  content: ''; position: absolute; inset: 0; pointer-events: none;
  background-image: radial-gradient(var(--pg-dot) 1px, transparent 1px);
  background-size: 18px 18px;
}
:root { --pg-dot: rgba(68, 56, 86, 0.14); }            /* --fg light at 14% */
[data-theme='dark'] { --pg-dot: rgba(192, 171, 218, 0.18); }  /* --fg dark at 18% */
```

`--pg-term-h` is written on `.pg` by the drawer toggle (`setDrawerOpen`), not by a `:has()` rule, so the row height and `data-open` cannot disagree. `--pg-dot` is a token by construction: its two values are `--fg` at the file's alpha, and the token guard (decision 12) accepts `var(--pg-dot)` because it is declared in the token blocks.

The nav, the terminal line and the status line, as the file draws them (`Playground Upgrade.dc.html:86-101`, `:126-130`, `:131`):

```text
.pg-nav            height 48px; padding 0 20px; border-bottom 1px --border; two clusters, gap 22px left, 8px right
  .pg-brand        mono 17px 700, a link to url('/')
  .pg-crumb        button: border 1px --border; radius 6px; background --pane-bg; mono 12px; padding 5px 10px 5px 12px;
                   `<group> /` in --muted, the project in --fg, `▾` in --accent 10px; [aria-expanded=true]: border --accent,
                   box-shadow 0 0 0 3px color-mix(in srgb, var(--accent) 18%, transparent), chevron `▴`
  .pg-status-cluster  mono 11.5px --muted: .pg-dot 8px (data-state as today) · .pg-status-label in --fg · .pg-status-detail
  .pg-download     outline button: padding 5px 10px; radius 6px; border 1px --border; mono 11.5px;
                   label = artifact name, .pg-action-meta = size in --muted; disabled with no artifact; data-stale as today
  .pg-share        filled: background --accent; color --bg; same padding and radius
  .theme-toggle    ThemeToggle.astro, unchanged
.pg-term           row 3; background --code-bg; border-top 1px --border; padding 0 16px; --font-mono-strict 12.5px
  .pg-term-line    the closed line: .pg-console-title (mono 11px --muted) · `>` (--accent 600) · command · `·` · reply (--term-ok)
                   · spacer · .pg-term-open (`Console ▴`, mono 11px --muted) · .pg-term-mem (`Memory`, opacity .5 without a memory)
  .pg-drawer       today's element, hidden while data-open='false'
.pg-statusline     grid 1fr auto 1fr; padding 0 16px; mono 10.5px --muted; opacity .8
  .pg-status-identity · .signature (Footer.astro:24-27 verbatim) · .pg-status (role=status) then .pg-promise
```

The `role="status"` span keeps its class, its `aria-live` and its `:empty` rule (`global.css:1976`); while it holds text the promise hides (`.pg-status:not(:empty) + .pg-promise { display: none }`), so the announcement never fights the promise for the cell.

The terminal line's summary, from the transcript the console already keeps (`console.ts:61-92`):

```ts
// site/src/scripts/terminal-line.ts
export interface TermSummary {
  /** The last line the reader (or a face) typed, without its `> `. */
  command: string | null;
  /** The first line the protocol printed after it, or null while it is pending. */
  reply: string | null;
}
export function summaryOf(lines: readonly string[]): TermSummary;
// Scans from the end for the last echo (`> …`, promptEcho); the reply is the first line after it
// that is not an echo and not a note (`# …`). No echo: both null. A note after the echo is skipped.
```

The splitter in pixel mode (decision 6):

```ts
// site/src/scripts/splitter.ts
export interface SplitterOptions { /* … */ unit?: 'ratio' | 'px'; minPx?: number; maxReservePx?: number; stepPx?: number; coarseStepPx?: number }
// unit 'px': intent and rendered value are pixels; bounds are [minPx, containerWidth − maxReservePx];
// the main splitter passes { unit: 'px', property: '--pg-source-w', initial: 480, minPx: 320, maxReservePx: 480, stepPx: 16, coarseStepPx: 64 }.
export function clampPx(px: number, bounds: SplitterBounds): number;
export function pxFromPointer(startPx: number, clientPx: number): number;
export function stepPx(px: number, ev: { key: string; shiftKey?: boolean }, o: { orientation; stepPx; coarseStepPx; bounds }): number | null;
```

**Where the width lives in this phase.** In memory, on the splitter handle, default `480`. It is not persisted: `normalizeRatios` (`playground-store.ts:233-242`) accepts only a fraction strictly between 0 and 1, so a pixel value cannot ride in `layout.ratios` without either a lossy encoding (a fraction of a width the migrator will not know) or a schema move, and decision 5 lands the schema move once, in Phase 1, as `LayoutState.sourceWidth`. A reload during this phase returns the column to 480px; `onCommit` stays wired and writes nothing until Phase 1 gives it a field. The drawer splitter keeps `ratios.drawer` untouched and hidden; Phase 6 moves it.

The store schema is unchanged in this phase (`STORE_VERSION = 1`).

## Execution & Concurrency Model

This phase is fully synchronous. No worker, timer or observer is added. The splitter's existing `ResizeObserver` re-clamps the pixel width on a resize and never commits, as it does for the ratio today (`splitter.ts:126`). The theme toggle's script attaches to every `.theme-toggle` on the page (`ThemeToggle.astro:9`), so the bench's instance needs no wiring of its own.

## Persistence & I/O

No new persistence. The envelope is read and written as today; the source width is not stored (see Data & State). The handoff's files are committed to the repository and nothing else touches disk. `island-smoke` reads `dist/` as it does today.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Trim and commit the handoff | Remove from the working tree: `circ-site-theme.js`, `circ-skins.js` (both byte-identical to `02e56f4:DOCS/archive/design/canvas-theme/`), `site/src/utils/circ-assets.mjs` (a stale copy) and the 32 `_ds/*/fonts/JetBrainsMono*.ttf` and `JetBrainsMonoNL*.ttf` files; stage `DOCS/design/design_handoff_playground_bench/{README.md,github.md,"Playground Upgrade.dc.html",support.js,circ-scenes.js}` and `_ds/circ-site-08dd9906-cc43-49f3-b12c-936e70b128e1/{README.md,_adherence.oxlintrc.json,_ds_bundle.css,_ds_bundle.js,_ds_manifest.json,styles.css,fonts/fonts.css,fonts/jetbrains-mono.css,fonts/NectoMono-Regular.woff2,fonts/Ronzino-Regular.woff2}`; `DOCS/PLANS_PROMPT.md`, `DOCS/PLANS/PHASE_0_handoff_frame.md`; a row in `DOCS/index.md`. | `git status --short` shows only those paths; `find DOCS/design -name '*.ttf' -o -name .DS_Store` is empty; `git diff --cached --stat` under 1 MB. |
| 2 | The chrome yields and the guards land | `Base.astro` renders `Nav`/`Footer` for the default layout only; the body grid is one viewport row and `main` has no padding; `bench-tokens.test.ts` written against today's `.pg-*` rules and green (any literal it finds today is fixed in this slice); `app-layout.test.ts` gains the `Base.astro` guard and keeps every other assertion green on the old markup. | `bun test site/test/app-layout.test.ts site/test/bench-tokens.test.ts`; a build whose `dist/playground/index.html` contains no `site-nav` and no `site-footer`, and whose `dist/index.html` still does. |
| 3 | The frame and the nav | `.pg` on the four rows; `.pg-nav` with the wordmark, the breadcrumb button (text only, no card yet), the status cluster, Download and Share restyled, `ThemeToggle`; `.pg-statusline` with the identity, the signature and the promise; `.pg-statusbar` deleted; `refreshActions` writes the artifact name and size into the button. | `island-smoke`: no `.pg-statusbar`; `.pg-nav .pg-status-label` reads `Idle`; `.pg-crumb` names the default pick's group and label; `.pg-statusline .signature .heart` present; Download and Share tests (`:604-687`) green with the new label shape; the `.pg` rows-branch of the shell test counts four rendered children. |
| 4 | The two regions and the bridges | `.pg-body` with the source region, the hairline and the canvas region; the dot grid; borders and radii gone from both panes; the splitter in pixel mode on `--pg-source-w`; the banner inside the source region; `.pg-ws` as the card under the breadcrumb (`aria-expanded`, `aria-controls`, `Escape`, outside click, focus return; `.pg-ws-toggle` removed, `.pg-ws-new` kept as the card's footer); `.pg-tabs` and the panels inside the canvas region; the 800px block stacks `.pg-body`. | `splitter.test.ts` pixel helpers; `island-smoke`: `.pg-ws` hidden at boot, shown after a click on `.pg-crumb`, hidden after `Escape` with focus on the button; the source column's `getBoundingClientRect` (happy-dom reports 0, so the assertion is on `--pg-source-w` read from `.pg-body.style`) unchanged across open and close; every tree test (`:172-207`, `:384-503`) green unchanged. |
| 5 | The terminal line | `terminal-line.ts` and its test; `.pg-term` as row 3 holding `.pg-term-line` and the moved `.pg-drawer` and `.pg-drawer-splitter` (splitter hidden); the line rendered from `summaryOf` after every `consoleAppend`, `consoleClear` and `consoleNewSession`; `Console ▴` opens the drawer (`--pg-term-h: 320px` on `.pg`, `data-open`), `▾` in the drawer bar closes it; `Memory` at opacity .5 with `aria-disabled` until a memory is declared; `setDrawerShown` removed and the line always visible. | `terminal-line.test.ts`; `island-smoke`: `.pg-term-line` reads the title and `Compile a circuit first.` at boot; after `consoleAppend(['> set a 1', 'ok'])` through the island seam the line reads `set a 1` and `ok`; the drawer test (`:350-383`) rewritten to the toggle and `data-open`; `.pg-output .pg-drawer` is now null and `.pg-term .pg-drawer` is not. |
| 6 | The walk, the numbers, the record | Every `island-smoke` selector reconciled; the shell chain test on the new containers; `bun run bundle` before and after in STATUS; `DOCS/decisions/playground-bench.md` with entries for decisions 1, 3, 4 (already met; the value the site keeps), 6 and 12, registered in `DOCS/decisions/index.md`; a screenshot of board 2a's frame in both modes named in STATUS. | All four gates green; `bun run bundle` within the `/playground` ceiling; the STATUS entry names the raw and gzip numbers and the two screenshots. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `summaryOf: no echo yields nulls` | `site/test/terminal-line.test.ts` | `summaryOf([])` and `summaryOf(['# circ-compile --sim', '# proto=1'])` are `{ command: null, reply: null }`. |
| `summaryOf: the last echo and its reply` | `site/test/terminal-line.test.ts` | `['> set a 1', 'ok', '> get out', 'out 0']` yields `{ command: 'get out', reply: 'out 0' }`; the echo's `> ` is stripped. |
| `summaryOf: a pending command has no reply` | `site/test/terminal-line.test.ts` | `['> set a 1', 'ok', '> run']` yields `{ command: 'run', reply: null }`. |
| `summaryOf: notes after the echo are skipped` | `site/test/terminal-line.test.ts` | `['> reset', '# session rebuilt', 'ok']` yields `reply: 'ok'`; an `err …` line is a reply too. |
| `clampPx holds the bounds` | `site/test/splitter.test.ts` | `clampPx(100, {min: 320, max: 960})` is `320`; `NaN` is the minimum; a value inside is itself. |
| `pixel bounds reserve the far pane` | `site/test/splitter.test.ts` | For a 1440px container with `minPx 320` and `maxReservePx 480` the bounds are `[320, 960]`; a container narrower than their sum collapses both ends to `minPx`. |
| `the keyboard contract, pixels` | `site/test/splitter.test.ts` | `ArrowRight` adds `stepPx`, `Shift+ArrowRight` adds `coarseStepPx`, `Home`/`End` hit the bounds, `ArrowUp` returns `null` on a vertical divider. |
| `every colour in a .pg- rule is a token` | `site/test/bench-tokens.test.ts` | For every rule whose selector contains `.pg-`, each `color`, `background`, `background-color`, `border`, `border-*-color`, `outline`, `fill`, `stroke` value is `var(--…)`, `transparent`, `currentColor`, `inherit` or `none`; `box-shadow` may add `rgba(0, 0, 0, a)` or `rgb(0 0 0 / a)`; `color-mix(in srgb, var(--…) N%, transparent)` is a token expression. Failures list `selector → property: value`. |
| `every face in a .pg- rule is a token` | `site/test/bench-tokens.test.ts` | Every `font-family` and `font` shorthand in a `.pg-` rule is `inherit` or names only `var(--font-prose)`, `var(--font-mono)` or `var(--font-mono-strict)`. |
| `the guard sees the rules` | `site/test/bench-tokens.test.ts` | The parsed `.pg-` rule count is above 100, so a regex that silently matches nothing cannot pass. |
| `Base renders the site chrome for the default layout only` | `site/test/app-layout.test.ts` | `Base.astro` matches `/\{layout !== 'app' && <Nav \/>\}/` and the same for `<Footer />`; the app block has `grid-template-rows: 100vh` before `100dvh`; `[data-layout='app'] main {` declares `padding: 0`. |
| `the frame is four tracks` | `site/test/app-layout.test.ts` | `[data-layout='app'] .pg {` declares `grid-template-rows: 48px minmax(0, 1fr) var(--pg-term-h, 40px) 24px` and `min-height: 0`; `.pg-body {` declares `min-height: 0` and `grid-template-columns: var(--pg-source-w, 480px) 1px minmax(0, 1fr)`. |
| `the app shell hands its height down` (updated) | `site/test/app-layout.test.ts` | Chain `['main', '.pg']` as today; `['.pg', '.pg-body']` takes the rows branch: the container declares `grid-template-rows` and the child declares `min-height: 0`. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `the playground mounts its editor, tabs and workbench` (updated) | `site/test/island-smoke.test.ts` | No `.site-nav` and no `.site-footer` in the document; `.pg-nav .pg-brand[href]`, `.pg-crumb[aria-expanded="false"]`, `.pg-nav .theme-toggle`, `.pg-statusline .signature .heart`, `.pg-statusline .pg-promise` present; `.pg-statusbar` absent; `.pg-ws` has `hidden`; `.pg-term-line .pg-console-title` matches `/^circ-compile \S+\.circ --sim$/`; every existing tree, dock, drawer-content and console assertion unchanged. |
| `the breadcrumb opens the tree and gives focus back` | `site/test/island-smoke.test.ts` | A click on `.pg-crumb` removes `hidden` from `.pg-ws` and sets `aria-expanded="true"`; `Escape` restores both and `document.activeElement` is the button; `--pg-source-w` on `.pg-body` is the same string before and after. |
| `the terminal line follows the transcript` | `site/test/island-smoke.test.ts` | Through the island seam (`__playground`, a new `consoleAppend` entry), `['> set a 1', 'ok']` makes `.pg-term-cmd` read `set a 1` and `.pg-term-reply` read `ok`; `Console ▴` sets `data-open="true"` on `.pg-term` and `--pg-term-h: 320px` on `.pg`; the drawer bar's toggle sets it back. |
| `every app-shell container hands its height to exactly one child` (updated) | `site/test/island-smoke.test.ts` | Chain `['main', '.pg'], ['.pg', '.pg-body']`; `.pg`'s four tracks equal its rendered children (the banner, hidden by default, lives inside the source region and cannot change the count). |
| `Download follows the artifact` / `Share copies a link` (updated) | `site/test/island-smoke.test.ts` | The same outcomes on the moved buttons: the title regexes, `data-state`, the `.pg-status` sentences; the Download label now equals the artifact file name and `.pg-action-meta` the formatted size. |

Run command: `cd site && bun --bun run build && bun test && bun --bun run typecheck && bun run bundle`

## Open Questions / Spikes

- `TODO(phase0):` The status cluster's detail in the mock reads `14 ms · 0 warnings`, which `statusFor` (`pipeline.ts:136-160`) does not produce. This phase shows today's `detail` string unchanged; a compile-time figure is copy, and decision 2 says copy is illustrative. Revisit only if Phase 7's sweep finds the cluster empty in the live state.
- `TODO(phase0):` The breadcrumb's group for a scratch project. `groupOf` (`ws-tree.ts:209`) answers for catalogue picks; for `scratch:` ids the card's group label is `Mine` (the tree's third group). Confirm the label against `CATALOGUE_GROUPS` in slice 3 and use the same string the tree renders.
