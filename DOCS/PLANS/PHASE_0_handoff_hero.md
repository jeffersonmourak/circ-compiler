# Phase 0 — The handoff and the hero

> **Dependencies:** None.
> **Warnings:** Decisions 1, 2, 4, 6, 7, 8, 10, 11 and 15 of `DOCS/PLANS_PROMPT.md` are authoritative. Three facts the handoff states loosely and the tree fixes: (1) the hero already auto-runs (`index.astro:41`, `autoRun`), and `island-smoke.test.ts:1497-1505` reads the built landing page for `class="lc"` and `data-circ-autorun`; (2) `renderCircuit` boots every input low (`circ-renderer/src/wasm/runtime.ts:233`, no `noInitialPinDrive`), so the values line starts at zeros, not the mock's `a = 1 · b = 1`; (3) the `island-smoke` harness imports each island chunk once per process (`:141-164`) and already runs `LiveCanvas.astro`'s chunk against `dist/gallery/index.html` (`:1465`), so the landing page's own proof is the built HTML read as text and a happy-dom parse, never a second import of the chunk. Slices 3–5 need a fresh `bun --bun run build` before `bun test`, or the smoke and the gallery memory test skip and prove nothing.

## Goal

A reader opens `/` and sees, above the fold at 1100px: a headline (`Logic circuits, written down.`), the tagline word for word, `Open the playground →` filled and `Read the reference` outlined, the download chip, and beside them one card headed `half_adder.circ · live simulation` whose left pane is the half-adder's source with line numbers and whose right pane is the circuit running on the dot grid, fitted to the pane, with `a = 0 · b = 0 → sum = 0 · carry = 0` under it and `edit this in the playground →` at the right of that line. Clicking `a` flips the line to `a = 1 · b = 0 → sum = 1 · carry = 0`. Below the hero the page is today's: the `CodePreview` figure is gone from the top (the card carries the source now) and lands in its own section in Phase 1, and the install line, the three prose sections and the lineage line stay where they are until their phases. The gallery renders the same `LiveCanvas` with markup byte-identical to today's. The handoff is tracked under `DOCS/design/` without its noise; every colour and face in a `.home-` rule is a token; every gate is green and `/` is under its ceiling.

## Scope

**In scope:**
- The handoff committed per decision 2; the plan bundle (`DOCS/PLANS_PROMPT.md`, `DOCS/PLANS/PHASE_0..3_*.md`) committed; a row in `DOCS/index.md` under *Documents* pointing at `PLANS_PROMPT.md`, as the archive prompt expects to remove later.
- `site/src/scripts/pin-line.ts` (`pinLine`, `rootPins`) and its test (decision 7).
- `site/test/bench-tokens.test.ts` reading `.home-` rules beside `.pg-` rules (decision 6).
- `LiveCanvas.astro`: optional `label`, `source`, `values`, `link` and `fit` props; the hoisted script honouring `data-circ-fit` and `data-circ-values`; the gallery's markup unchanged.
- The hero section in `index.astro` replacing `.landing-tagline`, `.landing-hero` and the top-of-page `CodePreview`; the `.home-hero*` rules; `.landing-tagline`/`.landing-hero` rules deleted.
- `DOCS/decisions/home-page.md` created and registered in `DOCS/decisions/index.md` with the entries for decisions 2, 4, 6, 7 and 8.

**Explicitly deferred:**
- The language card, the `--preview` section and the twin (Phase 1); the tiles and the thumbnail variant (Phase 2); the install section, the stacked layout and the browser pass (Phase 3).
- Any change to `CodePreview.astro`, `gallery.astro`, `Nav.astro`, `Footer.astro`.
- Seeding the hero's pins (decision 8).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/pin-line.ts` | `rootPins(topology)` and `pinLine(pins, format)`: the values line as a string, renderer-free. |
| site | `site/test/pin-line.test.ts` | The spelling cases below over hand-built pin records and a stub topology. |
| docs | `DOCS/decisions/home-page.md` | The initiative's decisions, appended per phase; registered in `DOCS/decisions/index.md`. |
| docs | `DOCS/design/design_handoff_home_page/**` | The handoff, tracked per decision 2 (already on disk, untracked; slice 1 trims and stages it). |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/components/LiveCanvas.astro` | Props `label?: string`, `source?: string`, `values?: boolean`, `link?: { href: string; label: string }`, `fit?: 'parent'`. Markup: the header's left text from `label`; a `.lc-body` wrapper holding an optional `.lc-source` pane (shiki `Code` as `CodePreview.astro:41`) beside `.lc-launch`/`.lc-mount`/`.lc-error`; an optional `.lc-values` footer with `.lc-pins` and the link. Attributes `data-circ-fit="parent"` and `data-circ-values` on `.lc`. Script: `fit` → `viewport: 'parent', navigation: false` in `renderCircuit`'s options (`:129-138`); `values` → `onPinChange` writes `.lc-pins` and the mount writes it once after `applyMemory`; the text comes from `pinLine(rootPins(view.runtime.topology), 'hex')`. |
| site | `site/src/pages/index.astro` | The hero section (markup below) replacing lines 30–42; `heroSource` passed to the card's `source`; the top `CodePreview` removed (it returns in Phase 1's section). |
| site | `site/src/styles/global.css` | `.home-hero*`, `.home-call*`, `.home-chip`, `.lc-body`, `.lc-source`, `.lc-values` rules; `.landing-tagline` and `.landing-hero` (`:1522-1529`) deleted. The shared `.lc-mount` block (`:493-547`) untouched. |
| site | `site/test/bench-tokens.test.ts` | `benchRules` becomes rules whose selector includes `.pg-` or `.home-` or `.lc-`; the three assertions and the guard count unchanged. |
| site | `site/test/island-smoke.test.ts` | The landing assertions at `:1497-1505` extended: the hero card carries `data-circ-fit="parent"` and `data-circ-values`, exactly one `.lc` on the page, `.lc-source` present with seven `.line` spans, `.lc-pins` present and empty. |
| site | `site/test/canvas-memory.test.ts` | One added case on `dist/gallery/index.html`: no `data-circ-fit`, `data-circ-values`, `.lc-source` or `.lc-values` in the gallery. |
| docs | `DOCS/index.md` | A row for `PLANS_PROMPT.md` under *Documents*. |
| docs | `DOCS/decisions/index.md` | The new file registered. |

**New dependencies:** None.

## Data & State

The hero card as `LiveCanvas` renders it (the smoke test's map; every existing class kept where it is):

```html
<div class="lc" data-circ-wasm data-circ-cell="14" data-circ-padding="28"
     data-circ-autorun data-circ-fit="parent" data-circ-values>
  <div class="lc-header"><span class="lc-label">half_adder.circ · live simulation</span><span class="lc-hint">click input pins to toggle</span></div>
  <div class="lc-body">
    <div class="lc-source"><pre class="astro-code"><code><span class="line">…</span>…</code></pre></div>
    <div class="lc-stage">
      <button class="lc-launch" type="button">▶ Run interactively</button>
      <div class="lc-mount" hidden></div>
      <div class="lc-error" hidden></div>
    </div>
  </div>
  <div class="lc-values"><span class="lc-pins"></span><a class="lc-values-link" href="…">edit this in the playground →</a></div>
</div>
```

Without `source`, `.lc-body` and `.lc-stage` are not emitted and `.lc-launch`/`.lc-mount`/`.lc-error` stay direct children of `.lc`, as today (`LiveCanvas.astro:38-53`); without `values`, no `.lc-values`. That is what keeps the gallery byte-identical.

The source pane's line numbers are CSS counters over shiki's `.line` spans (`.lc-source .line::before { counter-increment: line; content: counter(line); … }`), a 22px right-aligned gutter at 55% opacity; the pane is `--font-mono-strict 12.5px / 1.75`, `padding: 16px 0 16px 4px`, `border-right: 1px solid var(--border)`; the body is `grid-template-columns: 236px minmax(0, 1fr)` (`Home Page Proposal.dc.html:84-85`). The stage is `position: relative; min-height: 210px; padding: 12px` with the dot grid `radial-gradient(var(--pg-dot) 1px, transparent 1px) 16px 16px` (`:93-94`, `README.md:60`). Under `fit`, `.lc-mount` fills the stage (`position: absolute; inset: 12px; padding: 0; display: block`) so the renderer's `'parent'` measurement is the pane; the canvas is `display: block; max-width: none; height: auto` inside that scope only. Header and values line per `README.md:54-56` and `:63-65`.

```ts
// site/src/scripts/pin-line.ts
export interface PinRecord { name: string; kind: 'in' | 'out'; value: { value: bigint; defined: bigint; width: number } }
/** The root pins of a decoded topology, inputs then outputs, in declaration
 *  order — `collectPins` of sim-session.ts:154-163 without that module's
 *  imports. `kinds` are the two numbers the topology uses (InputPin 0,
 *  OutputPin 5, lib/topology/format.zig); a stub in a test passes any. */
export function rootPins(
  topology: { components: readonly { id: number; kind: number; name: string; width: number; origin: readonly unknown[] }[] },
  read: (id: number) => PinRecord['value'],
): PinRecord[];
/** `a = 1 · b = 0 → sum = 1 · carry = 0`. A one-bit pin is its digit; a bus
 *  is spelled in `format` (`0x…` for hex, `0b…` for binary, plain decimal);
 *  any undefined bit makes the pin `?`. No inputs or no outputs drops that
 *  side and the arrow. */
export function pinLine(pins: readonly PinRecord[], format: 'hex' | 'binary' | 'decimal'): string;
```

The island writes the line as two kinds of span so the board's colours hold (`:99`): names in `--fg`, the rest in `--muted`. `pinLine` returns plain text; a sibling `pinLineParts(pins, format)` returns `{ text: string; name?: true }[]` for the markup, and `pinLine` is `parts.map((p) => p.text).join('')`, so the test covers both.

The hoisted script's per-card record (`LiveCanvas.astro:77`) grows nothing: the values element is found by `container.querySelector('.lc-pins')` when `data-circ-values` is present, and written from `onPinChange` and once after `applyMemory`. `rethemeAll` (`:178-185`) and `onAssetsReady` (`:152`) repaint only and never rebuild the line.

## Execution & Concurrency Model

This phase is synchronous apart from what exists: the renderer and theme dynamic imports (`LiveCanvas.astro:71-74`) and the `IntersectionObserver` (`:198-215`). Under `viewport: 'parent'` the renderer's own `ResizeObserver` measures the mount once it is appended (`circ-renderer/src/render/canvas.ts:446-467`: the first measurement fits, later ones keep the view); the site appends the canvas exactly as today (`:140-142`) and calls nothing. `onPinChange` is the renderer's callback after a click; the line is written synchronously inside it. No worker, timer or observer is added.

## Persistence & I/O

None new. The handoff's files are committed to the repository. The page fetches what it fetches today: the renderer chunk, the theme chunk and `hero-half-adder.wasm` when the hero scrolls into view (it is at the top, so on load after the observer fires).

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Trim and commit the handoff | Remove from the working tree the 32 `_ds/*/fonts/JetBrainsMono*.ttf` and `JetBrainsMonoNL*.ttf` files, any `.DS_Store`, and `site/src/utils/circ-assets.mjs`; stage `DOCS/design/design_handoff_home_page/{README.md,github.md,"Home Page Proposal.dc.html",support.js,circ-scenes.js,circ-skins.js,circ-site-theme.js}` and `_ds/circ-site-08dd9906-cc43-49f3-b12c-936e70b128e1/{README.md,_adherence.oxlintrc.json,_ds_bundle.css,_ds_bundle.js,_ds_manifest.json,styles.css,fonts/fonts.css,fonts/jetbrains-mono.css,fonts/NectoMono-Regular.woff2,fonts/Ronzino-Regular.woff2}`; `DOCS/PLANS_PROMPT.md`, `DOCS/PLANS/PHASE_0..3_*.md`; a row in `DOCS/index.md`. | `git status --short` shows only those paths; `find DOCS/design -name '*.ttf' -o -name .DS_Store` is empty; `git diff --cached --stat` under 400 KB. |
| 2 | The line and the guard | `pin-line.ts` with `rootPins`, `pinLineParts`, `pinLine`; `pin-line.test.ts`; `bench-tokens.test.ts` reading `.home-` and `.lc-` rules (the existing `.lc-*` rules pass today: every colour there is a token). | `bun test test/pin-line.test.ts test/bench-tokens.test.ts` green; the guard count still above 100. |
| 3 | `LiveCanvas` grows, and the gallery does not move | The five props, the `.lc-body`/`.lc-source`/`.lc-stage`/`.lc-values` markup emitted only when asked, the two attributes, the script's `fit` and `values` handling, the `.lc-body`/`.lc-source`/`.lc-values` rules and the `fit` scope's mount rules; nothing on the landing page yet. | `bun --bun run build`; `canvas-memory.test.ts`'s new gallery case (no new attribute or class in `dist/gallery/index.html`); `island-smoke` unchanged and green; `renderer-pin.test.ts` "a theme flip changes a live canvas in place, on both pages" green. |
| 4 | The hero | The section: `h1`, the tagline in a `p.home-tagline` with `max-width: 32ch` and the site's `--muted`, the two calls, the download chip, the card with `label`, `source={heroSource}`, `values`, `link` through `OpenInPlayground`'s href shape (`${url('/playground')}#pick=example:half-adder`, built by the same catalogue check) and `fit="parent"`; the top `CodePreview` removed; `.landing-tagline`/`.landing-hero` rules deleted; `.home-hero*` rules at the file's values (`Home Page Proposal.dc.html:66-77`). | `bun --bun run build`; `island-smoke`'s landing assertions extended and green; `content-artifacts` green (the hero still names `hero-half-adder.wasm`); `site-labels` green (`<title>` unchanged); `bench-tokens` green over the new rules. |
| 5 | The walk, the numbers, the record | Every landing assertion reconciled; `bun run bundle` for `/` and `/gallery` before and after in STATUS; `DOCS/decisions/home-page.md` with entries for decisions 2, 4, 6, 7 and 8, registered in `DOCS/decisions/index.md`. | All four gates green; `/` under 10 KB gzip; the STATUS entry names the raw and gzip numbers for both pages. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `rootPins keeps the root pins, inputs then outputs, in declaration order` | `site/test/pin-line.test.ts` | Over a stub topology with an input inside an origin frame, a root output declared before a root input, and a gate: two records, the input first, the framed one absent. |
| `pinLine spells a bit as its digit and a bus in the base` | `site/test/pin-line.test.ts` | `a=1, b=0 → sum=1, carry=0` on one-bit records reads `a = 1 · b = 0 → sum = 1 · carry = 0`; a 4-bit `0b0110` reads `0x6` in hex, `0b0110` in binary, `6` in decimal. |
| `an undefined bit is a question mark` | `site/test/pin-line.test.ts` | `defined` short of the mask on any bit yields `?` for that pin and nothing else changes. |
| `no outputs drops the arrow, no pins is empty` | `site/test/pin-line.test.ts` | Inputs only → `a = 0 · b = 0`; outputs only → `sum = 0`; none → `''`. |
| `pinLineParts marks every name` | `site/test/pin-line.test.ts` | The parts joined equal `pinLine`; exactly one `name: true` part per pin, holding the name. |
| `every colour in a .pg-, .home- or .lc- rule is a token` (extended) | `site/test/bench-tokens.test.ts` | The three prefixes; the guard count above 100; the allowances case unchanged. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `every canvas that asks to auto-run is watched, and nothing else is` (extended) | `site/test/island-smoke.test.ts` | On `dist/index.html`: one `.lc`, with `data-circ-autorun`, `data-circ-fit="parent"` and `data-circ-values`; `.lc-source` holds seven `.line` spans; `.lc-pins` is present and empty; `h1` reads `Logic circuits, written down.`; the tagline's text is `index.astro:31-32`'s verbatim. |
| `the gallery's cards carry none of the hero's additions` | `site/test/canvas-memory.test.ts` | `dist/gallery/index.html` contains no `data-circ-fit`, `data-circ-values`, `lc-source` or `lc-values`; every `.lc` still opens with `.lc-header` then `.lc-launch`. |
| `the host hooks this site depends on are present` (extended) | `site/test/renderer-pin.test.ts` | `LiveCanvas.astro`'s source passes `viewport: 'parent'` and `navigation: false` only under the `fit` branch, and `onPinChange` is wired; the theme-flip guard still finds one `setTheme(pickTheme())` per page. |

Run command: `cd site && bun test test/pin-line.test.ts test/bench-tokens.test.ts && bun --bun run build && bun test && bun --bun run typecheck && bun run bundle`

## Open Questions / Spikes

- `TODO(phase0):` the hero's fitted scale at 1100px. The half-adder at `cell 14` is about 16 cells wide; the pane is roughly 380px after the 236px source column, so the renderer may fit below 100%. If the walk finds it small, the slice may raise `cell` on the hero only (the mock caps at 14 and computes the floor; the renderer computes a scale) and STATUS records the value.
- `TODO(phase0):` whether `OpenInPlayground.astro` should grow a `class` prop so the values-line link reuses its catalogue check, or the hero builds the href with the same `#pick=` shape and a build-time check of its own. Recommended: the prop, one line in the component and no second check.
