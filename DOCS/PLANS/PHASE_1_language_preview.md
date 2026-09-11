# Phase 1 — The language card and the `--preview` figure

> **Dependencies:** Phase 0 (the hero in place, the top `CodePreview` removed, the `.home-` prefix under the token guard).
> **Warnings:** Decisions 1, 10, 11, 12, 13 and 15 of `DOCS/PLANS_PROMPT.md` are authoritative. The three prose sections this phase deletes (`index.astro:46-85`) are mirrored word for word in `build-llm-mirror.ts:148-158` and summarised in `llms.txt` (`:254-260`, `:264`); the twin moves in this phase, not later. `site-labels.test.ts:113-125` reads the mirror script's literal strings for the gallery only, so the landing rewrite is free of that test but must keep `'Gallery'` and `label: 'Gallery'` intact. Every value below comes from the design file's inline styles (`Home Page Proposal.dc.html:105-163`); the README's numbers agree at plan time.

## Goal

Under the hero the reader finds two sections, each under a hairline. The first shows a bordered two-column card on the left — `vocabulary`, four rows of chips (primitives, macros, signals, files), and `from file to running chip`, three numbered steps joined by a rule — and on the right the kicker `THE WHOLE LANGUAGE`, the heading `Six primitives. Five macros. One import.` and its lede. The second shows the kicker `--PREVIEW`, the heading `Source on the left. What the compiler saw on the right.`, a lede, and `Open it in the playground →` on the left, and on the right the `CodePreview` figure as shipped with a status row under both panes (`source` · `circ-compile --preview`). The three prose sections and their headings are gone; every fact they carried is in the card. `site/public/index.md` says what the page says, in the page's order, and `llms.txt` describes the landing page the same way.

## Scope

**In scope:**
- The language section (`Home Page Proposal.dc.html:105-143`): the card grid, the vocabulary rows, the pipeline steps, the text column; `.home-lang*`, `.home-card*`, `.home-vocab*`, `.home-steps*` rules.
- The `--preview` section (`:145-163`): the text column with its link through `OpenInPlayground` (`example:half-adder`), the figure, the status row; `.home-preview*` rules.
- Deleting `.landing-prose` markup and rules (`index.astro:46-85`, `global.css:1552-1556`).
- `emitLandingTwin` rewritten per decision 13; the `llms.txt` landing line reworded.
- `DOCS/decisions/home-page.md` gains the entries for decisions 12 and 13.

**Explicitly deferred:**
- The tiles (Phase 2); the install section, the stacked layout, and Lineage's spacing (Phase 3).
- Any change to `CodePreview.astro`'s markup or rules; the landing page styles the figure from outside through `.home-preview .cp`.
- A generated twin: the script keeps hand-mirroring the page, as its comment at `:97-101` records.

## File & Module Topology

**New files:** None.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/pages/index.astro` | Two `<section>`s after the hero: `.home-lang` (the card and the text column) and `.home-preview` (the text column and the figure with its status row); `.landing-prose` removed; `CodePreview` re-imported for the figure, without `caption`. The vocabulary rows and pipeline steps are two constant arrays in the frontmatter, rendered by `.map`, so the copy lives in one place. |
| site | `site/src/styles/global.css` | `.home-section` (the shared `border-top` and `56px 40px` padding), `.home-kicker`, `.home-h2`, `.home-lede`, `.home-lang`, `.home-card`, `.home-card-head`, `.home-vocab*`, `.home-chip`, `.home-steps*`, `.home-preview*`, `.home-status-row`; `.landing-prose*` deleted. |
| site | `site/scripts/build-llm-mirror.ts` | `emitLandingTwin` (`:123-165`) rewritten; `emitLlmsTxt`'s landing entry (`:264`) reworded; `HERO_SOURCE`/`HERO_PREVIEW` untouched. |
| site | `site/test/island-smoke.test.ts` | The landing assertions gain: section order (`.home-hero`, `.home-lang`, `.home-preview`, then today's `.install-line`), no `.landing-prose`, four `.home-vocab-row`s, three `.home-step`s, one `.cp` inside `.home-preview`, the status row's two strings. |
| site | `site/test/site-labels.test.ts` | One added case: the built twin `public/index.md` (written by `bun --bun run build`) contains every `.home-h2` text of `index.astro` as a `##` heading, and none of the three deleted headings. |
| docs | `DOCS/decisions/home-page.md`, `DOCS/decisions/index.md` | Decisions 12 and 13 recorded. |

**New dependencies:** None.

## Data & State

The copy, as frontmatter constants in `index.astro` (from `README.md:95-108` and `Home Page Proposal.dc.html:362-374`; the chips are the language's own nouns, not illustrative numbers):

```ts
const vocabulary: { key: string; chips: string[]; note?: string }[] = [
  { key: 'primitives', chips: ['and', 'not', 'led', 'wire', 'rom', 'ram'] },
  { key: 'macros', chips: ['or', 'nand', 'nor', 'xor', 'xnor'], note: 'expand to primitives' },
  { key: 'signals', chips: ['1–64 bits', 'input[4] a', 'a[0:2]', '{a, b}'] },
  { key: 'files', chips: ['import "adder.circ"'], note: 'one circuit each' },
];
const pipeline: { title: string; body: string }[] = [
  { title: 'Write a .circ file', body: 'Plain text. Any editor — or the playground, which checks the wiring as you type.' },
  { title: 'circ-compile it', body: 'Out comes one self-contained .wasm. Add --preview to print the schematic in your terminal first.' },
  { title: 'Run it anywhere WebAssembly runs', body: 'Set input pins from JavaScript, read outputs back. Browser, Node, or the playground\'s live canvas.' },
];
```

`TODO(phase1):` the `signals` row's `a[0:2]` is the board's spelling; the language writes a slice `a[0..2]` (`examples.ts:109`, `slice-and-concat`). The chip must be the language's, `a[0..2]`, and STATUS names the correction; decision 1 says the board's copy is illustrative where it is wrong about the language.

The two sections' geometry (the file's values):

```text
.home-section        border-top 1px --border; padding 56px 40px
.home-lang           grid minmax(0,7fr) minmax(0,4fr); gap 48px; align-items start     (:105)
  .home-card         grid 1fr 1fr; gap 1px; background --border; border 1px --border; radius 6px; overflow hidden   (:106)
    .home-card-pane  background --pane-bg; flex column
    .home-card-head  padding 7px 14px; border-bottom --border; --pane-label-bg; --font-mono 11px; uppercase; .06em; --muted   (:108, :121)
    .home-vocab      padding 4px 14px 6px
      .home-vocab-row   grid 74px minmax(0,1fr); gap 10px; align-items baseline; padding 9px 0; border-bottom --border   (:111)
      .home-vocab-key   --font-mono 11.5px; .04em; --muted
      .home-chip        --font-mono 12.5px; padding 1px 7px; radius 4px; border 1px --border; --code-bg; --fg; nowrap   (:358)
      .home-vocab-note  --muted
    .home-steps      padding 14px
      .home-step        grid 22px minmax(0,1fr); gap 12px                              (:124)
      .home-step-n      22px disc; --accent on --bg; mono 11px 700                     (:369)
      .home-step-rule   flex 1; width 1px; min-height 14px; --border; margin 4px 0     (:127; absent on the last step)
      .home-step-title  15px 600 --fg;  .home-step-body  --font-mono 12px / 1.55 --muted
  .home-text         flex column; gap 14px
    .home-kicker     --font-mono 11.5px; .08em; uppercase; --accent
    .home-h2         30px / 1.15; 600; text-wrap balance; margin 0
    .home-lede       15.5px / var(--line); --muted; text-wrap pretty; max-width none
.home-preview        grid minmax(0,4fr) minmax(0,7fr); gap 48px; align-items start   (:145)
  .home-preview-link --font-mono 13.5px; --accent; no underline; margin-top 4px      (:150)
  .home-figure       the CodePreview as shipped; .cp margin 0
  .home-status-row   --pane-bg; padding 8px 14px; --font-mono 11.5px; --muted; flex space-between   (:161)
```

`h2` on the site is `1.5rem` with `margin: 2.5rem 0 0.75rem` (`global.css:110-117`) and `p` caps at `--measure` (`:120-123`); `.home-h2` and `.home-lede` restate size, margin and width, which is why they are classes and not bare tags.

The twin, in the page's order (decision 13):

```md
# circ
> Logic circuits, written down. A small language for building and simulating logic circuits, made for people learning how computers work.
## Hero example: half-adder            (as today: the source and the --preview, then the playground link)
## The whole language                  (the h2 as a sentence, the lede, the four vocabulary rows as a list, the three steps numbered)
## --preview                           (the h2, the lede)
## From the gallery                    (Phase 2 fills it; this phase writes the heading and the `All examples` link to gallery.md)
## Install                             (the install line, as today's download sentence)
(the lineage line)
```

## Execution & Concurrency Model

This phase is fully synchronous and adds no script. The two sections are static markup; the figure is `CodePreview`'s server-rendered shiki output; the link is an anchor.

## Persistence & I/O

`bun --bun run build` and `bun run dev` run `build-llm-mirror.ts`, which writes `public/index.md`, `public/llms.txt` and `public/llms-full.txt`; those are committed outputs, so the rewrite lands as a diff in `site/public/`. No other I/O.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The language card | `.home-section`/`.home-text` rules shared by both sections; the `.home-lang` section with the card and the text column; `.landing-prose` markup and rules deleted; the `a[0..2]` correction. | `bun --bun run build`; `island-smoke`: four vocabulary rows, three steps, no `.landing-prose`, the kicker and `h2` texts; `bench-tokens` green. |
| 2 | The `--preview` section | `.home-preview` with the text column, the `OpenInPlayground` link, the figure without caption, the status row. | `island-smoke`: one `.cp` inside `.home-preview`, `.home-status-row` reading `source` and `circ-compile --preview`, the link's href ending `#pick=example:half-adder`. |
| 3 | The twin and the record | `emitLandingTwin` and the `llms.txt` line rewritten; the `site-labels` case; decisions 12 and 13; STATUS with the bundle numbers (unchanged eager graph expected). | `bun --bun run build` writes a twin whose `##` headings equal the page's `.home-h2` texts in order; `site-labels` green; all four gates green. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `every colour in a .pg-, .home- or .lc- rule is a token` (held) | `site/test/bench-tokens.test.ts` | The new rules pass. |
| `the landing twin is headed the way the page is` | `site/test/site-labels.test.ts` | Reads `src/pages/index.astro` for every `.home-h2` text and `public/index.md` for `## ` headings: each `h2` appears as a heading, in the same order; `What it is`, `What it isn't`, `Where it runs` appear in neither. Skipped when `public/index.md` is absent. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `every canvas that asks to auto-run is watched, and nothing else is` (extended) | `site/test/island-smoke.test.ts` | `dist/index.html`: `main`'s children in order `.home-hero`, `.home-lang`, `.home-preview`, then `.install-line`, `.lineage`; the vocabulary rows' keys `['primitives', 'macros', 'signals', 'files']`; the step titles; the status row's strings. |

Run command: `cd site && bun --bun run build && bun test && bun --bun run typecheck && bun run bundle`

## Open Questions / Spikes

- `TODO(phase1):` the `a[0:2]` chip (see Data & State) — the slice writes `a[0..2]`.
- `TODO(phase1):` the `--preview` section's lede says "the same picture the live card above is animating"; the card is above, so the sentence holds. If Phase 3's stacked layout moves the card, the sentence still holds (the card is still above).
