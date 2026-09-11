# Plan Prompt — Home page (the landing page redrawn with the circuit first)

## What Is Being Built

The site's `/` opens on a tagline, then the `CodePreview` figure, then the live half-adder below the fold, an install line, three prose sections and the lineage line (`site/src/pages/index.astro`, 91 lines; the `.landing-*`, `.install-line` and `.lineage` rules of `site/src/styles/global.css` at 1521–1565). There is no `h1`. A design handoff under `DOCS/design/design_handoff_home_page/` (`README.md` and board 4a in `Home Page Proposal.dc.html`, lines 52–211) reorders the page so the thing a reader can touch is the first thing they see: a hero with a headline, the tagline verbatim, two calls and a download chip on the left, and a card on the right that merges today's `LiveCanvas` and source pane into one frame with a live values line under it; then one bordered card that replaces the three prose sections with a vocabulary table and a three-step pipeline; then the `--preview` figure in its own section with a heading; then three gallery tiles drawn live at small cell sizes; then the install line restyled as a section on the code surface; then Lineage and Footer unchanged. Same tokens, same fonts, same components, same renderer: the change is markup and CSS in `index.astro` and `global.css`, one small extension of `LiveCanvas.astro` (a source pane, a values line and thumbnail sizing), and the markdown twin the page mirrors.

Motivation: the playground bench just shipped and the home page still leads with a static figure. The `--preview` picture and the running circuit are the same half-adder, and the page should show the one that moves first.

**Definition of done.** Board 4a renders at 1100px in both `data-theme` modes with the geometry, spacing, type sizes and colour roles the design file's inline styles give; below 800px the page stacks and every control is reachable. Nothing the page does today is lost: the hero still auto-runs, a click still toggles a pin, a theme flip still re-themes in place, and every `site/test` case that reads the landing page still passes. `bun test`, `bun --bun run typecheck`, `bun --bun run build` and `bun run bundle` are green with `/` under the default 10 KB gzip ceiling; `site/public/index.md` and `llms.txt` say what the page says; `DOCS/decisions/home-page.md` records every decision below that a phase exercised; one browser check of the finished page in both modes is recorded in STATUS; the handoff and the plan bundle are archived per `DOCS/prompts/ARCHIVE.md` before the branch merges.

## Tech Stack

- **Site:** Astro 5 under `site/`, static output, one hoisted script per component (`LiveCanvas.astro:55-238` is the one this plan touches). Gates, in order, from `site/`: `bun test`, `bun --bun run typecheck`, `bun --bun run build`, `bun run bundle`. `site/test/island-smoke.test.ts` reads `dist/` and needs a fresh build (it skips without one); `site/test/canvas-memory.test.ts:138` reads `dist/gallery/index.html`.
- **Budget:** `site/bundle-budget.json`: `default.gzip` 10,240 for every route but the playground; `/` measures 3.8 KB raw / 2.0 KB gzip today (two files). The renderer (`index.*.js`, 46.9 KB raw) and the theme (`circ-theme.*.js`, 27.3 KB) are lazy chunks reached only through `import()` in `LiveCanvas.astro:71-74`, reported and never gated.
- **Renderer:** `circ-renderer` pinned at `2d973b4` (`2.3.0-alpha.4`), read-only. What this plan uses is already exported: `renderCircuit` (README:30-50), `onPinChange` (:40), `viewport: 'parent'` (:46, :144-152), `navigation: false` (:45), `setTheme` (:156). The site's theme is `site/src/utils/circ-theme.mjs` (`pickTheme`, `onAssetsReady`).
- **Compiler:** read-only. Artifacts are committed under `site/public/wasm/`; `hero-half-adder.wasm` (25 KB), `two-bit-adder.wasm` (28 KB), `four-bit-adder.wasm` (34 KB), `rom-lookup.wasm` (24 KB). `site/scripts/compile-content.ts` regenerates them; nothing here needs regenerating.
- **Markdown twin:** `site/scripts/build-llm-mirror.ts` hand-mirrors the landing page (`emitLandingTwin`, :123-165) and names it in `llms.txt` (:264). It runs on every build and dev.
- **Design reference:** `DOCS/design/design_handoff_home_page/` — `README.md` (the spec), `Home Page Proposal.dc.html` (board 4a at 1100 and today's page rebuilt at 640; needs `support.js`, `circ-skins.js`, `circ-scenes.js`, `circ-site-theme.js` and `_ds/` beside it), `github.md` (the source map).
- **Style of every doc and every string the page shows:** Strunk & White (the book is in the books-knowledge library).

## Architectural Constraints

- **`Base.astro` stays as it is.** The page uses the default layout: `Nav`, `main` at `max-width: 1100px` (`global.css:96-100`), `Footer`. The `app` variant is the playground's alone (`app-layout.test.ts:57`), and no rule of this plan is scoped to `[data-layout='app']`.
- **`LiveCanvas` keeps its contract.** The gallery renders the same component (`gallery.astro:56`) and `island-smoke.test.ts:1497-1505` reads the landing page for `class="lc"` and `data-circ-autorun`; `content-artifacts.test.ts:21` names `hero-half-adder.wasm`; `renderer-pin.test.ts` holds "a theme flip changes a live canvas in place, on both pages". Every extension is an optional prop or slot, and a card that passes none of them renders the markup it renders today.
- **`.lc-mount` is shared.** Its rules (`global.css:493-547`) are the gallery's, and `app-layout.test.ts` refuses any app rule that names it. A hero or thumbnail variant adds a `data-` attribute or a class beside `.lc` and scopes its rules to that, never by rewriting the shared block.
- **Nothing heavy loads before the reader asks, except what the page already grants.** The hero opts into `autoRun` today (`index.astro:41`) and keeps that; the tiles opt in too, and the `IntersectionObserver` at `LiveCanvas.astro:198-215` (`rootMargin: 200px`) defers them until scrolled near. No new eager import reaches the renderer, the theme, `circ-renderer/topology` or CodeMirror (`bundle-graph.test.ts` holds the last).
- **Every colour and font in a new rule is a token.** `--bg`, `--pane-bg`, `--code-bg`, `--pane-label-bg`, `--fg`, `--muted`, `--accent`, `--border`, `--font-prose`, `--font-mono`, `--font-mono-strict`, `--line`, and `--pg-dot` for the dot grid (`global.css:44`, `:77`). No new token. The guard of decision 6 enforces it.
- **The twin follows the page** ("the site's other face", `site-labels.test.ts:113-125`): a section removed from `index.astro` is removed from `emitLandingTwin`, and a section added is added, in the same order.
- **Copy is the design's where the design has it, and the site's voice where it does not.** The tagline, `heroSource`/`heroPreview`, the install line, Lineage and Footer are kept verbatim (README "Copy changes"). Numbers in the boards are illustrative (decision 1).
- **The JavaScript budget is per page and never raised silently** (`DOCS/decisions/playground.md`, "The JavaScript budget is per page…"): `/` stays under `default`, and STATUS records the `bun run bundle` numbers for `/` and `/gallery` in every phase that touches the hoisted script.
- **Behaviour a `bun test` can reach lives in a module without module-scope side effects**: the values line's spelling and the tile meta land in `site/src/scripts/` with their tests; `LiveCanvas.astro` and `index.astro` wire them.
- **Documentation lands with the code**: each phase appends its exercised decisions to `DOCS/decisions/home-page.md` (registered in `DOCS/decisions/index.md`).
- **Git conduct per `CLAUDE.md`:** stage by path, Conventional Commits under 70 characters (scope `site`), no phase or slice prefixes, no trailers. The commit and phase gating is the one in Working Loop below. This initiative lands on `playground-bench`, at the human's word; PR #86 will carry both initiatives, and the archive step should say so.

**Locked decisions.** Routine calls made at plan time so no slice reopens them. Each phase appends the ones it exercises to `DOCS/decisions/home-page.md`.

1. **The design file wins over its README.** Where `README.md` and the inline styles of `Home Page Proposal.dc.html` disagree, the file is taken and STATUS names the value. Copy in the boards that names a number (`16 parts`, `8 in · 3 out`, `16 words`) is illustrative and never copied; decision 3 says where the real numbers come from.
2. **The handoff is tracked, minus the noise.** Phase 0 commits `README.md`, `github.md`, `Home Page Proposal.dc.html`, `support.js`, `circ-scenes.js`, `circ-skins.js`, `circ-site-theme.js` (the design file imports the first two harness modules and `circ-skins.js` imports the theme; this `support.js` differs from the archived canvas-theme copy) and `_ds/<id>/{README.md,_adherence.oxlintrc.json,_ds_bundle.css,_ds_bundle.js,_ds_manifest.json,styles.css,fonts/fonts.css,fonts/jetbrains-mono.css,fonts/NectoMono-Regular.woff2,fonts/Ronzino-Regular.woff2}`. Not committed, and removed from the working tree: the 32 JetBrains Mono `.ttf` files (7.6 MB; the family sits in `--font-mono-strict` behind `ui-monospace`, and the site does not ship it), any `.DS_Store`, and `site/src/utils/circ-assets.mjs` (a 19.9 KB stale copy; the site's is 7.6 KB). At archive time the human chooses between the two precedents: moved under `DOCS/archive/design/` (canvas-theme) or deleted with the reference pinned to the canonical commit (playground-bench).
3. **The tiles are `two-bit-adder`, `four-bit-adder` and `rom-lookup`.** The board's `hack-alu` names no shipped example (the ALU chip library was deferred by the bench plan), and the four-bit adder is the bench's own stand-in for it. Each tile's name is the example's slug in mono; its description is a one-line lede written for the tile in the site's voice; its meta is computed at build from the example's source by a pure `tileMeta(source)` in `site/src/scripts/tile-meta.ts`: root pins as `N in · M out` (pins, not bits, as `pin-count.ts` counts them; a comma list counts each name), with `· 2^A words` appended when the source declares a `rom`/`ram`. The three sources are single files; the helper refuses a marker (`// name.circ`) rather than guessing. Thumbnails run the examples' own `wasm` and `memory` (`examples.ts:271` for the ROM's image), so `rom-lookup` draws its squares.
4. **The hero card is `LiveCanvas` with two slots and three attributes.** `LiveCanvas.astro` gains optional props: `label` (the header's left text; default `live simulation`), `source` (a string; when given, the body becomes `grid-template-columns: 236px minmax(0, 1fr)` with the source in `--font-mono-strict 12.5px / 1.75`, a 22px right-aligned gutter at 55% opacity and a right rule, rendered through `astro:components`' `Code` as `CodePreview.astro:41` does, so the tokens are shiki's), `values` (boolean; a footer row with the pin line on the left and a `link` `{ href, label }` on the right), `fit` (`'parent'`; passes `viewport: 'parent'` and `navigation: false` to `renderCircuit`, so the circuit is fitted into the pane the CSS sizes — `min-height: 210px` on the hero — and never zoomed or panned on the landing page) and `thumbnail` (decision 5). The gallery passes none of them and its markup is byte-identical. The mock's "cell = floor of what fits, cap 14" is approximated by the renderer's own fit at `cell = 14`; the fit scales the drawing, never the bitmap, so nothing is blurred.
5. **A thumbnail is cropped, not scaled.** `thumbnail` renders no header, no hint and no launch button text beyond a small centred `▶`; the slot is `height: 150px; overflow: hidden` with the canvas left-aligned at `padding-left: 12px`, drawn at a fixed `cell` (5 for the two-bit adder, 6 for the other two, as the board's `data-min-cell` gives) at its natural size. The shared `.lc-mount canvas { max-width: 100%; height: auto !important }` (`global.css:499-509`) and the 600px block rule (`:537-547`) are overridden inside the thumbnail only, so the bitmap is never CSS-scaled and the overflow is the crop the board draws. A thumbnail is not interactive (`interactive: false`): a click on a tile is the tile's link to `/gallery#<slug>`.
6. **The token guard extends to the new prefix.** New landing rules use the `.home-` prefix (`.home-hero`, `.home-card`, `.home-tiles`, `.home-install`, …); the `.landing-*` rules are deleted with the markup they styled and `.install-line`/`.lineage` are kept or restated under `.home-`. `site/test/bench-tokens.test.ts` learns a second prefix (`.home-` beside `.pg-`) with the same allowances, so every colour and face in a landing rule is a token from Phase 0 on.
7. **The values line is a pure module.** `site/src/scripts/pin-line.ts` exports `pinLine(pins, format)` over `{ name, kind, value: { value, defined, width } }` records in declaration order: inputs joined by ` · `, then ` → `, then outputs; a one-bit pin is its digit, a bus is spelled in `format` (hex by default), an undefined pin is `?`. It imports nothing from the renderer (a `BitValue`-shaped input is enough), so its test needs no renderer and the hoisted script may import it statically. The hoisted script fills the line from the runtime's root pins (`origin.length === 0`, `InputPin` then `OutputPin`, the collection `collectPins` makes in `sim-session.ts:154-163`) after the mount and after every `onPinChange`; the names are written in `--fg`, the values in `--muted`, as the board draws them (`Home Page Proposal.dc.html:99`).
8. **The hero boots as the renderer boots it.** `renderCircuit` drives every input low and settles (the boot `LiveCanvas` has always had, `sim-session.ts:112-117`), so the line reads `a = 0 · b = 0 → sum = 0 · carry = 0` until the reader clicks. The mock's `a = 1 · b = 1` is a fixture state and is not seeded. *Alternative rejected:* driving `a` and `b` high after the mount — a second boot path for one page, and a picture that lies about what a fresh circuit holds.
9. **Below 800px the page stacks, undesigned but usable.** The design is drawn at 1100 only. At the site's existing `@media (max-width: 800px)` breakpoint the hero becomes one column (text, then the card), the card's body stacks the source above the canvas, the language section and the `--preview` section become one column with the text first, the tiles become one column, the gallery header and the install header wrap. Section padding drops to `main`'s side padding. No board is drawn for it and no phase polishes it beyond "every control reachable".
10. **Sections are siblings of `main`'s column, separated by rules.** Each section is `border-top: 1px solid var(--border)` padded `56px 40px` (hero `72px 40px 56px`, install `40px`, lineage `48px 40px 40px`, README "Page order"), inside `main`'s 1100px cap. `main`'s own `padding: 2rem 1.5rem 3rem` (`global.css:96-100`) is not changed for other pages: the landing page sets its sections' side padding so the rules run edge to edge of the column, and STATUS records the value the file gives where the README's `40px` and `main`'s `1.5rem` disagree.
11. **The calls are links, in the design's two weights.** `Open the playground →` is filled (`background --accent; color --bg; padding 11px 18px; radius 6px; --font-mono 14px`) to `url('/playground')`; `Read the reference` is outlined (`border 1px --border; color --fg; padding 11px 16px`) to `url('/reference')`; the download chip is the install line's text in a `--code-bg` chip to `url('/download')`. The `--preview` section's `Open it in the playground →` and the hero's `edit this in the playground →` go through `OpenInPlayground.astro` with `example:half-adder` (checked against the catalogue at build), so a renamed slug fails the build rather than shipping a dead link. `All examples →` goes to `url('/gallery')`.
12. **The `--preview` section is `CodePreview` plus one row.** `CodePreview` renders as shipped with `heroSource`/`heroPreview`; the status row (`source` left, `circ-compile --preview` right, `--pane-bg; padding 8px 14px; --font-mono 11.5px; --muted`) is the section's own markup under the figure, since the component's pane labels already say the same and stay for the gallery. The caption prop is dropped on the landing page; the section's lede carries the sentence.
13. **The twin is rewritten once, in Phase 1.** `emitLandingTwin` becomes: the h1's sentence as the description, the hero example as today, the vocabulary as a list and the pipeline as three numbered lines, the `--preview` sentence, the three tiles as links to `gallery.md` anchors, the install line, the lineage line. `llms.txt`'s landing entry (`build-llm-mirror.ts:264`) is reworded to match. `HERO_SOURCE`/`HERO_PREVIEW` stay duplicated as the script's own comment records.
14. **Verification is by test and build until the last phase.** The human asked that small changes not restart the Chrome setup. Phases 0–2 prove themselves with the gates and the built HTML; Phase 3 makes one browser pass at 1100 and 1440 in both modes and at 700 stacked, records what it saw, and fixes only regressions against board 4a or a locked decision.
15. **Every page string is the site's voice.** Labels come from the boards where the boards have them (`click input pins to toggle`, `from file to running chip`, `Run it on your own machine.`) and follow Strunk & White where they do not; the tile ledes are new and pass that check before they ship.

## Phase Index

| Phase | Name | What Ships |
|-------|------|-----------|
| 0 | The handoff and the hero | The handoff committed per decision 2 and `DOCS/index.md` pointing at the plan; `pin-line.ts` with its test; `LiveCanvas.astro` grown per decisions 4 and 7 with the gallery's markup unchanged; the hero (`h1`, the tagline, the two calls, the download chip, the card with its source pane, fitted canvas and values line) in place of today's tagline, figure and canvas; `.home-` rules under the guard of decision 6; the rest of the page as it is below — proof is the built `dist/index.html` carrying the hero and `class="lc"` with `data-circ-autorun`, `island-smoke`, `content-artifacts` and `renderer-pin` green, and the `/` and `/gallery` budget numbers in STATUS. |
| 1 | The language card and the `--preview` figure | The vocabulary and pipeline card (`Home Page Proposal.dc.html:105-143`) with its heading, kicker and lede; the three prose sections and their headings deleted; the `--preview` section (`:145-163`) with `CodePreview` and the status row of decision 12; the twin rewritten per decision 13 — proof is the built page's section order matching README "Page order" 2–4, `site-labels` green, and `bun --bun run build` emitting a twin whose headings match the page. |
| 2 | From the gallery | `tile-meta.ts` with its test; the three tiles of decision 3 as thumbnails per decision 5, each linking to its gallery anchor, with `rom-lookup`'s image applied — proof is `canvas-memory.test.ts` extended to `dist/index.html` (one `data-circ-memory` on the ROM tile, none elsewhere), the observer watching four cards and no more, and the budget numbers. |
| 3 | Install, the narrow layout and the record | The install section (`:186-198`) on `--code-bg` with the restyled `InstallLine` row; Lineage and Footer spacing; the stacked layout of decision 9; the browser pass of decision 14 recorded in STATUS; `DOCS/decisions/home-page.md` complete and indexed; the archive prepared per `DOCS/prompts/ARCHIVE.md` and stopped before deletion — proof is every gate green, the STATUS entry naming each mode and width it saw, and the archive file reviewed. |

Phases are ordered by dependency, not by priority. Each phase must be fully shippable before the next begins.

**Explicitly deferred, and not to be smuggled into a slice:** a Hack ALU example or chip library; a designed layout below 900px; zoom and pan on the landing page; a `--preview` charset option; any renderer change; any change to `Nav.astro`, `Footer.astro`, `Lineage` text, `CodePreview.astro`'s markup or `gallery.astro`; promoting tokens to CircDS; regenerating any committed artifact.

**Sequencing notes for the execution agent.** Phase 0 goes first because the hero is the only part that changes a shared component, and the gallery's unchanged markup is easiest to prove while the rest of the page is still today's. Phase 1 deletes the prose the twin mirrors, so the twin moves in the same phase. Phase 2 needs the thumbnail variant that Phase 0's `LiveCanvas` extension leaves room for. Phase 3 is the page's tail and the record.

**Slice seams handed to the deep planner.** `DOCS/prompts/PHASE_DEEP_PLANNER.md` owns each phase's `## Slices` table; once `DOCS/PLANS/PHASE_<N>_<name>.md` exists its table is authoritative. Phase 0 has pre-agreed seams to carry over verbatim: (1) trim and commit the handoff per decision 2, `DOCS/index.md` pointing at the plan; (2) `pin-line.ts` and its test, `bench-tokens.test.ts` learning `.home-`; (3) `LiveCanvas.astro`'s props, slots and attributes with the gallery proved unchanged; (4) the hero markup and rules replacing the tagline, figure and canvas; (5) the walk, the numbers, the decisions entry.

## Working Loop

The execution agent follows this loop every session without exception:

### On Cold Start

1. Read this file (`DOCS/PLANS_PROMPT.md`) in full.
2. Read `DOCS/STATUS.md` (if it exists). The latest entry defines what was last shipped and what comes next.
3. Run `git log --oneline -10` and `git status` in this worktree. If STATUS claims a slice is committed but it does not appear in `git log`, it has not been committed — **do not begin a new slice**. Stop and say so.
4. Read the active phase plan (`DOCS/PLANS/PHASE_<N>_<name>.md`) for the current phase.
5. Implement the next slice per the phase plan. Do not start a second slice until the first is reviewed and committed.

### Each Slice

1. Implement the full slice as specified. Do not stop mid-slice.
2. Run the gates for what the slice touched, in `site/`: `bun test`, `bun --bun run typecheck`, `bun --bun run build`, `bun run bundle`. A slice that touches `dist/`-read tests runs `bun --bun run build` before `bun test`. Do not ship a slice that breaks a gate.
3. Append a STATUS entry (template below).
4. Stage the slice's files (`git add <files>`), by path.
5. **Phases 0–2:** display the proposed commit message and **stop**; wait for explicit human approval before running `git commit`. **Phase 3:** commit the slice without asking, one Conventional Commit per slice, and stop before the first slice of the phase to ask whether to begin it. This is the standing gating the human set for this project's plans.

### Git Rules

- Read-only git commands (`status`, `log`, `diff`) are encouraged for situational awareness.
- **Committing:** only at the end of a slice, only the slice's files, staged by path first so the diff can be inspected in any git client. Phases 0–2 wait for approval per slice; Phase 3 commits per slice and asks per phase, as above.
- Do **not** push, force-push, amend, rebase, reset, delete branches, or run any other write `git` or `gh` command unless the human asks for that action in so many words, and an approval covers only the action it named. The PR from `playground-bench` into `main` is the human's, and the plan bundle is archived before it (decision 2 and `DOCS/prompts/ARCHIVE.md`).

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

**The shared component**

- `pin-line.ts` cannot import `ComponentKind` without putting renderer code in the eager island chunk, and it cannot copy the kind bytes without violating `renderer-pin.test.ts`'s invariant. `rootPins` therefore accepts the input and output kind values from the renderer module `LiveCanvas` has already loaded.
- `island-smoke.test.ts:1497-1505` reads `dist/index.html` for `class="lc"` and `data-circ-autorun`, and asserts the observer watches exactly the opted-in cards. Adding tiles changes the count on the gallery page's harness only if the gallery changes; on the landing page it is the hero plus three.
- `content-artifacts.test.ts:21` names `hero-half-adder.wasm` as the landing page's inline artifact and refuses two entries sharing one artifact. The tiles must name the examples' own `wasm`, never a copy.
- `.lc-mount canvas` carries `max-width: 100%` and `height: auto !important` (`global.css:499-509`), and the 600px block swaps the mount to `display: block` (`:537-547`). A thumbnail that wants its natural size must override both inside its own scope, or a wide circuit squashes and the crop becomes a scale.
- `app-layout.test.ts` freezes every selector that mentions `.lc-mount`, not just app-layout selectors. A new `LiveCanvas` variant must add its exact scoped selectors to that set while preserving the separate rule that none may contain `data-layout`.
- The `hidden` attribute loses to any `display` rule of higher specificity; the `.lc-*[hidden]` override idiom at `global.css:516-522` must be kept for any new toggled piece.
- `renderCircuit` builds a canvas as big as the circuit unless `viewport` is given; with `viewport: 'parent'` a mount with no height renders nothing and throws nothing. The hero's pane height comes from CSS (`min-height: 210px`), never from the canvas.
- `onAssetsReady` re-themes every active canvas once the sprites decode (`LiveCanvas.astro:146-152`); a values line must not be rebuilt by that path, only repainted.

**The page and its twin**

- `build-llm-mirror.ts` runs inside `bun run build` and `bun run dev`; a landing section removed from `index.astro` and left in `emitLandingTwin` ships a twin that describes a page that no longer exists, and no test notices except `site-labels`' gallery case. Move both in one slice.
- `site-labels.test.ts:57-70` checks an `h1` only for nav routes; `/` is reached by the brand link, so the headline is free, and `<title>` keeps `circ — a small language for digital circuits`.
- `OpenInPlayground.astro` throws at build for an id outside the catalogue; use it for every playground link that names an example.

**Layout**

- `main` caps at 1100px with `1.5rem` side padding for every page; the landing sections' `40px` is theirs alone, and `p` keeps `max-width: var(--measure)` (`global.css:120-123`), so a lede wider than 36rem needs its own rule.
- Body copy keeps `--measure`; only figures, cards and grids use the full column (the design's last move, `Home Page Proposal.dc.html:382`).

**Verification**

- For small updates and minor fixes the human asked to use the existing tests and build checks rather than restarting the Chrome setup. Reserve browser automation for Phase 3's pass.
- A green `bun test` without a fresh `bun --bun run build` proves nothing about the built page: `island-smoke` and `canvas-memory` skip or read stale HTML.
- The required trimmed handoff and plan bundle are 455,497 bytes together, so Phase 0's 400 KB staged-size estimate was low. The locked retained-file list is the source of truth; do not drop a required reference to meet the estimate.

**Copy**

- The boards' copy is illustrative; take labels and hints, never numbers. Every new string goes past the Strunk & White check before it ships.
