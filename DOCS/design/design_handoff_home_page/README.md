# Handoff: circ home page (proposal 4a)

## Overview

A reorder of `site/src/pages/index.astro`. Same components, same copy where copy
survives, same tokens. The live circuit moves into the first screen beside a
headline; the three "What it is / isn't / Where it runs" paragraphs collapse into
one card (vocabulary + pipeline); three gallery cards are added; the
--preview figure gets its own section.

Design file: `Home Page Proposal.dc.html` — 4a is the left board (1100 wide),
the right board is today's page rebuilt for comparison. Open it in a browser to
see both in light and dark. Every value below is read from the 4a board's inline
styles.

Fidelity: **high** for structure, spacing, type sizes and token roles. Live
values in the mock (a=1, b=1 → sum 0 carry 1) come from the real simulation.

## Page order (top to bottom)

1. Nav — unchanged `Nav.astro`.
2. Hero — headline + tagline + two calls + download line · live half-adder card.
3. The whole language — heading + lede · vocabulary card + pipeline card.
4. --preview — heading · CodePreview (source | ascii) with a status row.
5. From the gallery — three ExampleCard-style tiles with live thumbnails.
6. Install — InstallLine on the code surface with a heading.
7. Lineage — unchanged `Lineage.astro`, verbatim text.
8. Footer — unchanged `Footer.astro` (signature included).

`main` keeps SiteShell's 1100px cap and 40px side padding. Sections are
separated by `border-top: 1px solid var(--border)` and padded `56px 40px`
(hero `72px 40px 56px`, install `40px`, lineage `48px 40px 40px`).

## 2 · Hero

`display:grid; grid-template-columns: minmax(0,5fr) minmax(0,6fr); gap:56px; align-items:center`.

Left column (`gap 22px`):
- `h1` **"Logic circuits, written down."** — 52px / 1.02, weight 600,
  letter-spacing −0.015em, `text-wrap: balance`. (Today the page has no h1.)
- Tagline — verbatim from index.astro, 21px / 1.45, `--muted`, max-width 32ch.
  Use `Tagline` and override nothing but max-width.
- Calls (`gap 14px`, padding-top 6px):
  - **Open the playground →** — filled: `background --accent; color --bg;
    padding 11px 18px; radius 6px; --font-mono 14px`. Links to /playground.
  - **Read the reference** — outline: `border 1px --border; color --fg;
    padding 11px 16px`, same type. Links to /reference.
- Download line — the existing InstallLine text ("↓ Download circ-compile for
  Linux, macOS, or Windows") as a small mono chip: `--font-mono 12.5px;
  padding 6px 12px; background --code-bg; border 1px --border; radius 4px`,
  padding-top 10px. Links to /download.

Right column — a `LiveCanvas` frame (`border --border; radius 6px; --pane-bg`):
- Header strip: `padding 7px 14px; --pane-label-bg; --font-mono 12px;
  letter-spacing .04em; --muted` — left `half_adder.circ · live simulation`,
  right *click input pins to toggle* (italic).
- Body `grid-template-columns: 236px minmax(0,1fr)`:
  - Source pane: `heroSource` from index.astro, `--font-mono-strict 12.5px /
    1.75`, 22px right-aligned gutter at 55% opacity, `border-right --border`.
  - Canvas pane: `min-height 210px`, dot grid (`radial-gradient(<fg @ 14–18%>
    1px, transparent 1px) 16px 16px`), canvas centred. Cell size = floor of
    what fits the pane (the mock computes it; cap 14).
- Footer row: `padding 8px 14px; border-top; --font-mono 11.5px; --muted` —
  left `a = 1 · b = 1 → sum = 0 · carry = 1` (names in `--fg`, live), right
  *edit this in the playground →* (link).

This is today's `LiveCanvas` + `CodePreview` merged into one frame. The
renderer call is the same `mountLiveCanvas` with the site theme; the new v2
assets (other handoff) are what the mock draws but are not required.

## 3 · The whole language

`grid-template-columns: minmax(0,7fr) minmax(0,4fr); gap 48px; align-items:start`
— **cards left, text right** (user's final choice).

Text column (`gap 14px`):
- kicker `THE WHOLE LANGUAGE` — `--font-mono 11.5px; letter-spacing .08em;
  uppercase; --accent`.
- `h2` **"Six primitives. Five macros. One import."** — 30px / 1.15, 600, balance.
- lede, 15.5px / `--line`, `--muted`:
  "A program is a flat list of declarations — name a pin, place a gate, bind
  its ports. It stops where the early Nand2Tetris hardware chapters stop:
  enough to build a CPU from NAND, nothing you'd need a datasheet for."

Cards: one bordered grid, two equal columns, `gap 1px; background --border;
border 1px --border; radius 6px; overflow hidden`; each card `--pane-bg` with
a header strip (`padding 7px 14px; --pane-label-bg; --font-mono 11px;
uppercase; .06em; --muted`).

**vocabulary** — rows `grid-template-columns: 74px 1fr; gap 10px; padding 9px 0;
border-bottom --border`; key `--font-mono 11.5px --muted`; values are chips
(`--font-mono 12.5px; padding 1px 7px; radius 4px; border 1px --border;
background --code-bg; color --fg`) with trailing notes in `--muted`:

| key | chips | note |
|---|---|---|
| primitives | and · not · led · wire · rom · ram | |
| macros | or · nand · nor · xor · xnor | expand to primitives |
| signals | 1–64 bits · input[4] a · a[0:2] · {a, b} | |
| files | import "adder.circ" | one circuit each |

**from file to running chip** — three steps, `padding 14px`; each row
`grid-template-columns: 22px 1fr; gap 12px`; number in a 22px accent disc
(`--bg` glyph, mono 11px 700); a 1px `--border` connector between discs;
title 15px 600 `--fg`; body `--font-mono 12px / 1.55 --muted`:
1. **Write a .circ file** — Plain text. Any editor — or the playground, which checks the wiring as you type.
2. **circ-compile it** — Out comes one self-contained .wasm. Add --preview to print the schematic in your terminal first.
3. **Run it anywhere WebAssembly runs** — Set input pins from JavaScript, read outputs back. Browser, Node, or the playground's live canvas.

Delete the three prose sections and their headings from index.astro; this card
replaces them.

## 4 · --preview

`grid-template-columns: minmax(0,4fr) minmax(0,7fr); gap 48px`.
Text: kicker `--PREVIEW`, `h2` **"Source on the left. What the compiler saw on
the right."** (30px), lede: "A half-adder. Two inputs, an XOR macro for the sum,
an AND for the carry. Every program can print itself like this from the
terminal — the same picture the live card above is animating.", link
*Open it in the playground →* (mono 13.5px, `--accent`).
Figure: `CodePreview` as shipped (`heroSource` / `heroPreview`), plus a
full-width status row under both panes: `--pane-bg; padding 8px 14px;
--font-mono 11.5px; --muted` — `source` left, `circ-compile --preview` right.

## 5 · From the gallery

Header row: kicker `FROM THE GALLERY` left, *All examples →* right (mono 13px).
Grid: three equal columns, same bordered-grid treatment as §3. Each tile:
- thumbnail area `height 150px; overflow hidden; border-bottom --border`,
  dot grid, canvas left-aligned with `padding-left 12px` and **cropped**, not
  scaled — cell floor 5 (adder) / 6 (alu, rom), cap 8.
- body `padding 14px 16px 16px`: name (`--font-mono 14px 600`) with meta
  right (`11px --muted`), then a one-line description (14px / 1.5 `--muted`).
Tiles: `adder2 · 16 parts`, `hack-alu · 8 in · 3 out`, `rom-lut · 16 words`.
Thumbnails come from the same renderer with the gallery's `.circ` files;
reuse `ExampleCard` for the body if its slots fit, otherwise plain markup.

## 6 · Install

Section on `--code-bg`, `padding 40px`, `gap 18px`.
Header row: kicker `INSTALL` + `h2` **"Run it on your own machine."** (26px)
left; `Linux · macOS · Windows · GPL v3` right (mono 12.5px `--muted`).
Then `InstallLine` as shipped, restyled as a single bordered row:
`padding 16px 20px; border --border; radius 6px; background --bg; --font-mono
17px` — text left, `/download →` right in `--muted` 14px. Whole row links.

## 7–8 · Lineage, Footer

Unchanged components, unchanged text. Lineage keeps its accent left rule,
max-width 62ch, 17px italic.

## Copy changes (complete list)

- New: h1 "Logic circuits, written down."
- New: the two call buttons, the §3 heading + lede + vocabulary + pipeline,
  the §4 heading/lede, the §5 tile descriptions, the §6 heading.
- Removed: the three prose sections (What it is / What it isn't / Where it runs)
  and the "the reference covers… / gallery… / playground…" pointer sentence
  (the calls and gallery section replace it).
- Kept verbatim: tagline, heroSource/heroPreview, install line text, lineage,
  footer.

## Tokens

All from `styles.css`: `--bg --pane-bg --code-bg --pane-label-bg --fg --muted
--accent --border --font-prose --font-mono --font-mono-strict --line`. No new
tokens. Dot grid uses `--fg` at 14% (light) / 18% (dark) — color-mix or two
literal rgba values as the site does elsewhere.

## Files

- `Home Page Proposal.dc.html` — the boards (needs `support.js` + `_ds/`).
- `circ-scenes.js`, `circ-skins.js`, `circ-site-theme.js`,
  `site/src/utils/circ-assets.mjs` — harness drawing the canvases; not part of
  this change.
- `github.md` — source map.
