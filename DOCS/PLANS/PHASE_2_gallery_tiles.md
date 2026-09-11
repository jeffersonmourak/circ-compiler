# Phase 2 — From the gallery

> **Dependencies:** Phase 0 (`LiveCanvas` with optional props and the `fit` scope's mount rules), Phase 1 (the section idiom and the twin's `From the gallery` heading).
> **Warnings:** Decisions 1, 3, 5 and 15 of `DOCS/PLANS_PROMPT.md` are authoritative. The board's tiles name `hack-alu`, which does not ship; the tiles are `two-bit-adder`, `four-bit-adder` and `rom-lookup` (`examples.ts:274`, `:332`, `:256`). `content-artifacts.test.ts:39-48` refuses two entries naming one artifact and counts `hero-half-adder.wasm` as the landing page's only inline one, so the tiles name the examples' own `wasm` through the content entries, never a literal. `canvas-memory.test.ts:137-152` asserts `data-circ-memory` on the gallery's cards; this phase adds the same assertion for the landing page (one attribute, the ROM's). The shared `.lc-mount canvas` rules (`global.css:499-509`, `:537-547`) scale a wide canvas down; a cropped thumbnail must win over them inside its own scope or the crop becomes a scale.

## Goal

Under the `--preview` section the reader finds `FROM THE GALLERY` with `All examples →` at the right, and a bordered three-column grid. Each tile shows, in a 150px slot on the dot grid, the top-left of the example's circuit drawn at a small fixed cell and cropped at the slot's edges, then the example's slug in mono with `N in · M out` (and `· 16 words` for the ROM) at the right, then a one-line description. The thumbnails run the examples' own artifacts, the ROM with its image loaded so the squares are in it; they draw when scrolled near and take no clicks. A click anywhere on a tile opens the gallery at that example. The gallery page is unchanged.

## Scope

**In scope:**
- `site/src/scripts/tile-meta.ts` (`tileMeta(source)`) and its test (decision 3).
- `LiveCanvas.astro`: the `thumbnail` prop and `data-circ-thumbnail`; `interactive: false` under it; no header, no hint, a bare `▶` launch; the `.lc[data-circ-thumbnail]` rules (decision 5).
- The gallery section in `index.astro` (`Home Page Proposal.dc.html:165-184`): the header row, the grid, three tiles built from `examples` by slug, each wrapped in a link to `url('/gallery')#<slug>`.
- `canvas-memory.test.ts` and `island-smoke.test.ts` extended to the landing page.
- The twin's `From the gallery` section filled with the three tiles as links to `gallery.md#…` anchors.
- `DOCS/decisions/home-page.md` gains the entries for decisions 3 and 5.

**Explicitly deferred:**
- A fourth tile, a tile picker, or tiles chosen by tier.
- Interactive thumbnails (a tile is a link; the gallery is where a reader clicks pins).
- Any change to `gallery.astro` or its anchors (`gallery.astro:51`, `id={ex.slug}`).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/tile-meta.ts` | `tileMeta(source)`: root pin counts and memory words from a single-file source, as a string. Pure; no DOM, no compiler. |
| site | `site/test/tile-meta.test.ts` | The counting cases below, and the three shipped tiles by name. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/components/LiveCanvas.astro` | `thumbnail?: boolean` → `data-circ-thumbnail` on `.lc`, no `.lc-header`, `.lc-launch` text `▶` with `aria-label="Run the thumbnail"`; the script passes `interactive: false` and `navigation: false` under it. `cell` is the caller's as today (`:31`). |
| site | `site/src/pages/index.astro` | `const tiles = ['two-bit-adder', 'four-bit-adder', 'rom-lookup'].map((slug) => examples.find(…))` with a throw for a missing slug (the same idiom as `OpenInPlayground.astro:19-21`); the `.home-gallery` section; each tile an `<a class="home-tile" href={…}>` holding `<LiveCanvas wasm={ex.wasm} memory={ex.memory} cell={…} thumbnail autoRun />` and the body. |
| site | `site/src/styles/global.css` | `.home-gallery*`, `.home-tile*`, `.lc[data-circ-thumbnail]` and its mount and canvas rules. |
| site | `site/test/canvas-memory.test.ts` | The built-page case runs over `dist/index.html` too: exactly one `data-circ-memory`, equal to `rom-lookup`'s `memory`. |
| site | `site/test/island-smoke.test.ts` | The landing assertions gain: four `.lc[data-circ-autorun]`, three with `data-circ-thumbnail`, their `data-circ-wasm` in tile order, each inside an `a.home-tile[href$="#<slug>"]`, the meta strings from `tileMeta`. |
| site | `site/scripts/build-llm-mirror.ts` | The `From the gallery` section lists the three tiles as `[title](gallery.md#slug)` with their ledes. |
| docs | `DOCS/decisions/home-page.md`, `DOCS/decisions/index.md` | Decisions 3 and 5 recorded. |

**New dependencies:** None.

## Data & State

```ts
// site/src/scripts/tile-meta.ts
export interface TileMeta { inputs: number; outputs: number; words: number | null }
/** Root pin counts and memory words of a SINGLE-FILE source: every `input`
 *  and `output` declaration counts each comma-separated name once (`input[2]
 *  a, b` is two pins, the width is ignored, as pin-count.ts counts pins);
 *  a `rom name[W, A]` or `ram name[W, A]` gives `words = 2 ** A` (one memory
 *  per tile; two is a plan error and throws). Comments (`// …`) are stripped
 *  first. A `// name.circ` marker line — a multi-file source — throws: the
 *  root of such a source is a compiler decision this helper does not make. */
export function tileMeta(source: string): TileMeta;
/** `2 in · 2 out`, or `1 in · 1 out · 16 words`. */
export function tileMetaLabel(meta: TileMeta): string;
```

The three tiles, from `examples.ts`, and what the helper yields for them (asserted by name in the test so a source edit that changes a pin count fails here rather than shipping a wrong number):

| slug | cell | `tileMetaLabel` | lede (new, the site's voice) |
|---|---|---|---|
| `two-bit-adder` | 5 | `2 in · 2 out` | Two 2-bit operands, sliced into lanes, added with a ripple carry, joined back into a bus. |
| `four-bit-adder` | 6 | `2 in · 2 out` | The same adder twice as wide: four lanes, each carrying into the next, 256 rows of truth. |
| `rom-lookup` | 6 | `1 in · 1 out · 16 words` | A lookup table the host fills at load. Drive the address and read the word; the console can peek and poke it. |

The board's `16 parts` and `8 in · 3 out` are not copied (decision 1); the cells are the board's `data-min-cell` values (`Home Page Proposal.dc.html:352-354`), the floor the mock draws at when a slot is narrower than the circuit, which a 150px slot under a cropped tile always is.

The tile (the smoke test's map):

```html
<section class="home-section home-gallery">
  <div class="home-gallery-head"><span class="home-kicker">From the gallery</span><a class="home-gallery-all" href="/gallery">All examples →</a></div>
  <div class="home-tiles">
    <a class="home-tile" href="/gallery#two-bit-adder">
      <div class="lc" data-circ-wasm data-circ-cell="5" data-circ-padding="10" data-circ-autorun data-circ-thumbnail>
        <button class="lc-launch" type="button" aria-label="Run the thumbnail">▶</button>
        <div class="lc-mount" hidden></div><div class="lc-error" hidden></div>
      </div>
      <div class="home-tile-body"><div class="home-tile-row"><span class="home-tile-name">two-bit-adder</span><span class="home-tile-meta">2 in · 2 out</span></div><p class="home-tile-lede">…</p></div>
    </a>
    …
  </div>
</section>
```

The rules (`:165-181`):

```text
.home-gallery-head   flex; align-items baseline; space-between; gap 24px
.home-gallery-all    --font-mono 13px; --accent; no underline
.home-tiles          grid repeat(3, minmax(0,1fr)); gap 1px; background --border; border 1px --border; radius 6px; overflow hidden
.home-tile           background --pane-bg; flex column; color inherit; text-decoration none
.lc[data-circ-thumbnail]        margin 0; border 0; radius 0; background transparent
.lc[data-circ-thumbnail] .lc-mount, .lc-launch   position relative; height 150px; overflow hidden; border-bottom 1px --border;
                                 display flex; align-items center; justify-content flex-start; padding 0 0 0 12px;
                                 background radial-gradient(var(--pg-dot) 1px, transparent 1px) 16px 16px
.lc[data-circ-thumbnail] .lc-mount canvas   max-width none; height auto; flex none; display block   (wins over :499-509 and :542-546 by specificity)
.lc[data-circ-thumbnail] .lc-launch  justify-content center; color --accent; --font-mono 14px
.home-tile-body      padding 14px 16px 16px; flex column; gap 6px
.home-tile-row       flex; baseline; space-between; gap 10px
.home-tile-name      --font-mono 14px 600;  .home-tile-meta  --font-mono 11px --muted
.home-tile-lede      14px / 1.5; --muted; text-wrap pretty; margin 0; max-width none
```

`.lc-launch` and `.lc-mount` under the thumbnail share the 150px slot rule so the tile does not change height when the canvas replaces the button. The `[hidden]` override idiom (`global.css:520-522`) still applies to both.

## Execution & Concurrency Model

Synchronous apart from what exists. The three thumbnails opt into `autoRun`, so the one `IntersectionObserver` of `LiveCanvas.astro:198-215` watches four cards on the landing page and mounts each once it is within 200px of the viewport; the renderer chunk is imported once (`rendererPromise`, `:69-72`) and each tile fetches its own `.wasm` (28, 34 and 24 KB). A thumbnail's runtime still boots low and `applyMemory` (`:91-105`) loads the ROM's image before the canvas is shown. `rethemeAll` re-themes thumbnails as it does cards. Nothing new is added.

## Persistence & I/O

Three more artifact fetches on the landing page, deferred until scrolled near; nothing else. The twin's gallery links point at `gallery.md` anchors, which `emitExamplesTwin` (`build-llm-mirror.ts:87-95`) already emits as `## <title>` headings — `TODO(phase2)` below.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The meta module | `tile-meta.ts` with `tileMeta` and `tileMetaLabel`; `tile-meta.test.ts`. | `bun test test/tile-meta.test.ts`: the counting cases and the three tiles by name. |
| 2 | The thumbnail | `LiveCanvas`'s `thumbnail` prop, attribute, launch button and script branch; the `.lc[data-circ-thumbnail]` rules; the gallery unchanged. | `bun --bun run build`; the gallery case of Phase 0 (no new attribute in `dist/gallery/index.html`) extended with `data-circ-thumbnail`; `renderer-pin.test.ts` green (`interactive: false` only under the thumbnail branch). |
| 3 | The tiles, the twin, the record | The `.home-gallery` section with three tiles; `canvas-memory` and `island-smoke` extended to `dist/index.html`; the twin's gallery section; decisions 3 and 5; STATUS with the bundle numbers. | All four gates green; `canvas-memory`: one `data-circ-memory` on the landing page equal to `rom-lookup`'s; `island-smoke`: four opted-in cards, three thumbnails in order, each inside its link; `/` under 10 KB gzip. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `tileMeta counts pins, not bits, and each name in a list` | `site/test/tile-meta.test.ts` | `input[2] a, b` → 2 inputs; `output[2] s(in=…)\noutput cout(…)` → 2 outputs; a `wire` or gate counts nothing. |
| `tileMeta reads a memory's address width` | `site/test/tile-meta.test.ts` | `rom code[8, 4](addr = pc.out)` → `words: 16`; `ram data[8, 4]…` the same; no memory → `null`; two memories throw. |
| `tileMeta strips comments and refuses a multi-file source` | `site/test/tile-meta.test.ts` | A `// input x` comment counts nothing; a `// half.circ` marker line throws. |
| `the three tiles read as the plan says` | `site/test/tile-meta.test.ts` | Over `examples` by slug: `two-bit-adder` → `2 in · 2 out`, `four-bit-adder` → `2 in · 2 out`, `rom-lookup` → `1 in · 1 out · 16 words`. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `the built pages carry what they declare` (extended) | `site/test/canvas-memory.test.ts` | `dist/index.html` holds exactly one `data-circ-memory`, parsed equal to `rom-lookup`'s `memory`; the gallery case unchanged. |
| `every canvas that asks to auto-run is watched, and nothing else is` (extended) | `site/test/island-smoke.test.ts` | `dist/index.html`: four `.lc[data-circ-autorun]`; three `[data-circ-thumbnail]` whose `data-circ-wasm` end in `two-bit-adder.wasm`, `four-bit-adder.wasm`, `rom-lookup.wasm` in that order; each inside `a.home-tile` whose `href` ends in `#<slug>`; `.home-tile-meta` texts equal to `tileMetaLabel(tileMeta(ex.source))`; no `.lc-header` inside a thumbnail. |

Run command: `cd site && bun test test/tile-meta.test.ts && bun --bun run build && bun test && bun --bun run typecheck && bun run bundle`

## Open Questions / Spikes

- `TODO(phase2):` the twin's gallery anchors. `gallery.md` headings are the examples' titles (`## 2-bit ripple-carry adder`), and a markdown reader slugs them differently from the HTML page's `id={ex.slug}`. The twin links to `gallery.md` without an anchor unless slice 3 finds a reader that resolves them; STATUS records the choice.
- `TODO(phase2):` the four-bit adder at `cell 6` is wider than a 150px-tall slot is tall; the crop shows its top-left corner, which is the two input pins and the first lane — the board's own choice ("cropped here, whole in the gallery", `:353`). If the walk in Phase 3 finds the crop unreadable, the cell may drop to 5; the slot height is the board's and does not move.
