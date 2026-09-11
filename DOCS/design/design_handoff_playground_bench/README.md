# Handoff: circ playground — the bench (proposal 2a + states 3a–3f)

## Overview

A canvas-first redesign of `site/src/pages/playground`. The four bordered panes
become two regions on one sheet; the workspace tree becomes a switcher; the Data
tab becomes a floating panel; dock and drawer collapse to one line each until
asked for. Same tokens, same fonts, same runtime — every change is CSS and a
small amount of DOM restructuring in `Playground.astro`.

Boards, in the order they appear in the design file (pan right):

| id | board | what it shows |
|---|---|---|
| 3a | Workspace switcher | the tree as a popover from the breadcrumb |
| 3b | A wider program | 2-bit adder, diagnostics footer expanded |
| 3e | Schematic view | `--preview` text on `--code-bg` |
| 3f | Truth view | live row tinted, cap as a toolbar chip |
| 3d | Many pins | Hack ALU, Data panel open |
| 3c | Console & Memory | drawer grown to 320px and split |
| 2a | The bench | the base state: nand, Live view, everything closed |
| 1a | (rejected) | first pass — same geometry with unified headers; kept for the record, do not build |

## About the design file

`Playground Upgrade.dc.html` is an HTML mock, not a component. It renders with
inline styles and the CircDS tokens (`--bg`, `--pane-bg`, `--code-bg`,
`--pane-label-bg`, `--fg`, `--muted`, `--accent`, `--border`, `--font-prose`,
`--font-mono`, `--font-mono-strict`). Read the inline `style="…"` attributes for
exact values; every number below comes from them. The canvases inside it are
drawn by the site-theme v2 assets (`circ-site-theme.js`, the other handoff) —
that renderer work is a separate PR and this proposal does not depend on it.

Fidelity: **high** for layout, spacing, type sizes and colour roles. Copy in the
boards (compile times, byte sizes, warning text) is illustrative.

## Frame

```
grid-template-rows: 48px  minmax(0,1fr)  40px  24px      /* nav · body · terminal line · status line */
body: grid-template-columns: 480px 1px minmax(0,1fr)     /* source · hairline · canvas */
      (440px for 3b, 400px for 3d — the source column is the user's splitter, default 480)
```

The app is locked to the viewport as today (`.pg-app`). No borders on panes:
source region is `--pane-bg`, canvas region is `--bg` with a dot grid
(`radial-gradient(<fg at 14–18%> 1px, transparent 1px)`, `18px 18px`), and a
single `1px --border` column between them.

### Nav (48px)
Left: wordmark (mono 17px 700) · **project switcher** (see 3a) · status
(`8px` accent dot, state word in `--fg`, detail in `--muted`, mono 11.5px).
Right: **Download** (outline button: `name.wasm` + size in `--muted`) ·
**Share** (filled `--accent`, text `--bg`) · theme toggle.
Buttons: `padding 5px 10px; border-radius 6px; mono 11.5px`.
This replaces `.pg-statusbar`'s Download/Share and the compiler identity in it.

### Source region
- File tabs strip: `36px`, `border-bottom --border`, mono 11.5px; active tab
  `--fg` with `2px --accent` underline; `+ file` in `--muted`.
- Editor: CodeMirror as today. Mock uses `--font-mono-strict` 14px / 1.7 with
  a 32px gutter; keep `circ-editor-theme.ts`, just match the padding
  (`16px 0`) and gutter opacity (`0.55`).
- **Diagnostics footer** (replaces the dock's Diagnostics tab): `30px`,
  `border-top --border`, mono 11px `--muted`. Left `N errors · N warnings`
  (in `--fg` when non-zero, with a `▾`), right `N lines · N components · N nets`.
  Click expands a list below it on `--pane-label-bg`: grid
  `14px 104px 52px 1fr`, gap 10px — severity glyph · `file:line:col` in
  `--accent` (clickable, drives the editor) · code in `--muted` · message.
- Settings: move to a gear in the nav or keep as a second footer tab — not drawn.

### Canvas region
- **View switch**, top-left at `14px 16px`: segmented control
  `Schematic · Live · Truth` (Data is gone — see panel). Container
  `padding 2px; border 1px --border; radius 6px; background --pane-bg`;
  segments `padding 4px 12px; mono 11.5px`; active `background --accent;
  color --bg; radius 4px`; inactive `--muted`.
- **Data button**, top-right at `14px 16px`: outline button (same as nav
  buttons, 11.5px) with a list glyph, `Data` and the pin count `N → M`
  in `--muted`. Filled accent while the panel is open.
- Hint line bottom-left, zoom/fit bottom-right: mono 11px `--muted`, `16px`
  in from the edges, `12px` up.
- The canvas itself is centred in the remaining inset (`60px 16px 40px`),
  `max-width: 100%`, transparent background.

### Terminal line (40px) — the drawer, closed
`background --code-bg; border-top --border; --font-mono-strict 12.5px`.
Left to right: command title (`circ-compile <file> --sim`, mono 11px `--muted`) ·
`>` in `--accent` 600 · last command · `·` · last reply in `--term-ok`.
Right: `Console ▴` and `Memory` (mono 11px, `--muted`; Memory at 50% when
the program declares none). Focus or click grows it to the drawer (3c).

### Status line (24px)
Grid `1fr auto 1fr`, mono 10.5px `--muted` at 80%: compiler identity left ·
**signature** centred (reuse `.signature`/`.heart` from `Footer.astro` verbatim)
· `runs in your browser · nothing leaves the page` right.

## 3a — Project switcher

Nav breadcrumb `Examples / nand ▾` is a button (`border --border; radius 6px;
background --pane-bg; mono 12px`; group in `--muted`). Open state: border
`--accent` + `0 0 0 3px` accent ring at 18%, chevron flips to `▴`.

Popover: anchored under it (`top 56px; left 82px` in the mock), `340px` wide,
`--pane-bg`, `border --border`, `radius 8px`, `shadow 0 12px 32px rgba(0,0,0,.28)`.
- Search row: `⌕ Find a circuit…` with a `⌘K` kbd chip, `border-bottom`.
- List (`max-height 460px`): groups (`Tour`, `Examples`, `Mine`) as
  `10.5px uppercase 0.08em --muted` rows with `10px` top padding; projects at
  `padding-left 26px`, mono 12px `--fg`, meta right-aligned in `--muted`
  (`1 file`, `yesterday`) or an accent pill for a warning count; the open
  project in `--accent`, expanded one level to its files (`padding-left 40px`,
  active file on `--pane-label-bg` with a `2px --accent` left rule).
- Footer: `+ New circuit` (`--accent`) · `Import .circ` (`--muted`).
A scrim (`--bg` at 45% dark / `--fg` at 18% light) covers everything below the
nav. The bench behind must not reflow when it opens or closes.

Data model is the existing `ws-tree.ts` tree; this is a re-skin of
`renderTree()`'s output inside a popover instead of `.pg-ws`.

## 3d — Data panel (replaces the Data tab)

Draggable card anchored top-right under the Data button (`top 52px; right 16px`),
`312px` wide, same surface/shadow as the popover. Header (`8px 12px`, mono 11px):
drag grip `⋮⋮` · **Data** 600 · `N in · M out` `--muted` · hex/bin/dec segmented
(10px) · `✕`. Two sections separated by a rule, each with a column header row
(`9.5px uppercase 0.08em --muted`: `input / bits / value`, then `output`):
grid `1fr 36px 92px`, rows `3px 12px`, mono 12px.
- 1-bit input → toggle knob `22px` circle: HIGH `--accent` fill / `--bg` glyph,
  LOW `--accent` outline / `--fg` glyph.
- Bus input → field: `--code-bg`, `border --border`, `radius 4px`, right-aligned,
  `min-width 64px`; accepts the console's value grammar (decimal, 0x, 0o, 0b, `_`).
- Output → read-only, 700, right-aligned.
Footer: `edits settle the circuit and echo in the console` · **Reset** (`--accent`).
Position persists per project (store envelope). While open, the canvas region
takes `padding-right: 344px` so the circuit is never under it.

Single-bit inputs still toggle by clicking the pin on the canvas (`hovered`
handling stays); the panel is for buses and for reading many outputs at once.

## 3e — Schematic

The canvas region switches to `--code-bg` (no dot grid). `--preview` output in a
`<pre>`: `--font-mono-strict 20px / 1.35`, centred. Top-right: `unicode | ascii`
segmented (moved out of the Settings dock; same setting) and a **Copy** button.
Bottom-right: `rows × cols chars`.

## 3f — Truth

Table centred on the dot grid: `--pane-bg`, `border --border`, `radius 8px`;
cells `7px 14px`, mono 12.5px, centred; header row `10.5px uppercase 0.08em
--muted` with a bottom rule; a `1px --border` left rule on the first output
column; HIGH digits `--fg` 700, LOW `--muted` 500; the row matching the live
pins tinted `--accent` at 14%. Clicking a row drives the inputs (same path as
the Data panel). Top-right chip: `N input bits · R rows · cap C` — replaces the
tab tooltip. Over the cap the table still opens, filtered to rows matching the
current pins, and the chip says why. Bottom-right: `Copy as markdown · CSV`.

## 3c — Console & Memory (drawer open)

The 40px line grows to `320px` (row 3 of the frame). With a memory declared it
splits `minmax(0,1fr) 1px 560px`.
- Console (`--code-bg`): header `34px` — `Console` tab (accent underline) ·
  command title · Clear / Copy script / Copy log as ghost text · `▾` to close.
  Log: `--font-mono-strict 12.5px / 1.5`, kinds as today (`note` `--muted`,
  `echo` `--term-echo`, ok replies `--term-ok`). Prompt row with a `7×14px`
  accent caret.
- Memory (`--pane-bg`): header — `Memory` tab · mem name `--fg` · `rom[8,4] ·
  16 words` `--muted` · `live` outline chip in `--accent` · hex/bin/dec.
  Toolbar: `◂ 0x0 – 0xf ▸`, `jump 0x__`, Refresh · Clear · **Load image…**
  (`--accent`) · Save. Grid `40px repeat(8, 1fr)`, mono 11px: address column
  on `--pane-label-bg` with a right rule; cells `3px 8px` centred; unknown
  word `?` in `--muted` at 55% with a dotted bottom rule; addressed word in
  `--accent`; cell under edit on `--pane-label-bg` with a `2px --accent`
  underline. Legend line below; image/footer line at the bottom.
Values follow `memory-panel.ts` (`formatWord`, `formatAddress`, `dumpRows`) —
addresses always hex, binary with `x` for a half-known word.

## Tokens this needs that CircDS does not yet export

`--term-ok`, `--term-echo`, `--danger`. They exist in `site/src/styles/global.css`;
the mock falls back to `#8fd3a8 / #ece4f8` (dark), `#3f7d5c / #2d2140` (light),
`#e5484d`. Promote them to the DS or keep them site-local — either works.

## Out of scope / not drawn

Settings dock placement; mobile (< 900px) layout; the Or16Way/Mux16 chip
library the ALU board assumes (`use "chips/*.circ"` is not shipped grammar);
Schematic text is hand-drawn, not captured from `--preview`.

## Files in this bundle

- `Playground Upgrade.dc.html` — the boards (open in a browser; needs `support.js`
  and the `_ds/` bundle beside it).
- `circ-scenes.js`, `circ-skins.js`, `circ-site-theme.js`, `site/src/utils/circ-assets.mjs`
  — harness that draws the canvases; not part of this proposal.
- `github.md` — source map back to the repo.
