# playground-bench

The entries below record the decisions of the playground-bench initiative: the site's `/playground` redrawn as the bench of the design handoff under `DOCS/design/design_handoff_playground_bench/` — two regions on one sheet under a 48px nav, over a terminal line and a status line. The sixteen decisions locked at plan time are in `DOCS/PLANS_PROMPT.md`; each phase appends the ones it exercised here as it ships them.

### The bench owns its chrome

**Decision.** `Base.astro`'s `app` variant renders neither `<Nav />` nor `<Footer />`; the body is one viewport row (`grid-template-rows: 100dvh`, with the `100vh` fallback first) and `main` has no padding. The playground, the variant's only user, draws its own 48px nav — the wordmark as a link home, a breadcrumb naming the open project, the status cluster, Download, Share and `ThemeToggle.astro` reused as is — and a 24px status line carrying the compiler identity, the site footer's `.signature`/`.heart` markup verbatim, and the promise `runs in your browser · nothing leaves the page`. The `role="status"` channel shares the line's right cell with the promise and hides it while it holds a sentence. `app-layout.test.ts` holds the two conditionals in `Base.astro` and refuses any app-scoped rule that names `.site-nav` or `.site-footer`.

**Rationale.** The design's frame is the whole viewport, `48px · minmax(0, 1fr) · 40px · 24px`, and no board draws the site's nav above it. Keeping both would put two wordmarks and 113px of chrome on a page that wants every pixel for the source and the canvas. The variant already existed to give one page a different body; yielding the chrome is one more thing it gives.

**Alternatives.** The site nav above the bench nav (two wordmarks, and the frame no longer the design's); a second layout file (forks the head, the theme script and the analytics mount for one page).

### The handoff is tracked, minus the noise

**Decision.** `DOCS/design/design_handoff_playground_bench/` is committed as the design reference: `README.md`, `github.md`, `Playground Upgrade.dc.html`, `support.js`, `circ-scenes.js`, and the CircDS bundle under `_ds/<id>/` with its two `woff2` faces and its two font stylesheets. Not committed, and removed from the working tree: `circ-site-theme.js` and `circ-skins.js` (byte-identical to `02e56f4:DOCS/archive/design/canvas-theme/`), `site/src/utils/circ-assets.mjs` (a stale copy of a file the site has since reduced to two sprites), and the 32 JetBrains Mono `.ttf` files (7.6 MB; the family sits in `--font-mono-strict` behind `ui-monospace`, and the site does not ship it). `support.js` is also identical to the archived copy but stays, because the design file needs it beside it to open. The design file wins over its README where the two disagree. At archive time the directory moves to `DOCS/archive/design/playground-bench/`.

**Rationale.** A handoff outside the repository cannot be cited by a slice; a handoff with 7.6 MB of fonts that render nothing the site renders is weight every clone pays forever. The mock's strict stack is the site's, so dropping the fonts changes nothing about how the mock reads on the machines that matter.

**Alternatives.** Committing the whole zip (8 MB, three duplicate files); keeping the handoff out of the tree (uncitable); committing it under `site/` (it is not shipped and must not be).

### The three terminal tokens stay site-local, and all three already exist

**Decision.** `--term-ok`, `--term-echo` and `--danger` are defined in both token blocks of `global.css` and are read by the console, the tree and the status dot; the handoff's fallback values (`#8fd3a8 / #ece4f8`, `#e5484d`) are not adopted, and the tokens are not promoted to CircDS. The canvas region's dot grid is a fourth site-local token, `--pg-dot`: `--fg` at the design file's alpha (`0.14` light, `0.18` dark), declared with the others so the token guard reads it as one.

**Rationale.** The site's `--danger` (`#a83737` / `#ff6b8a`) was chosen against the site's own palette; the mock's `#e5484d` is a fallback the DS author wrote for a mock without the site's stylesheet. CircDS is another package with its own release; a site page's terminal colours are not its concern.

**Alternatives.** Promoting the tokens (a DS release for three colours one page reads); a literal in the dot grid's gradient (the one colour the token guard would have to except).

### The source column is the splitter, in pixels

**Decision.** The main splitter keeps its `role="separator"` element and its one custom property, but in a pixel unit: `--pg-source-w` on `.pg-body`, read by `grid-template-columns: var(--pg-source-w, 480px) 1px minmax(0, 1fr)`. `createSplitter` takes `unit: 'px'` with `minPx 320`, `maxReservePx 480`, `stepPx 16` and `coarseStepPx 64`; `pxBounds` reserves the far pane and never inverts, and a container with no size yet (nothing laid out; happy-dom) leaves the intent unclamped so the first paint is the reader's width. `aria-valuenow` stays a percentage of the container in either unit. The hairline is the divider: one pixel in the grid, a nine-pixel invisible hit band. Until Phase 1 moves the envelope, the width lives in memory only, default 480; `normalizeRatios` accepts only a fraction, and the schema moves once.

**Rationale.** The design gives the source column as a width (480, and 440 or 400 on the wider boards), which is what a reader adjusts; a share of the container drifts as the window does. The splitter's contract — intent separate from the rendered value, no commit on resize, a nullable key handler — carries over unchanged, so the pixel unit is a second arithmetic behind the same element rather than a second mechanism.

**Alternatives.** Encoding the width as a fraction of a width the migrator cannot know (lossy, and undone by the first resize); a second splitter implementation (200 lines for one unit).

### The token guard is a source-text test

**Decision.** `site/test/bench-tokens.test.ts` parses every rule of `global.css` whose selector contains `.pg-` and holds each `color`, `background`, `border`, `outline`, `fill`, `stroke`, `box-shadow` and `caret-color` value to a `var(--…)` token, `transparent`, `currentColor`, `inherit` or `none`; a `box-shadow` may add a black at some alpha, and `color-mix(in srgb, var(--…) N%, transparent)` is a token expression. Every `font-family` and `font` shorthand names only the three font tokens or `inherit`. The guard asserts it saw more than a hundred rules, so a regex that matched nothing cannot pass, and it tests its own allowances on literal rules.

**Rationale.** A literal hex in a `.pg-` rule is a colour that stops following the theme, and nothing in a build says so; `circ-skins.test.ts` holds the canvas the same way and caught the last drift. Reading the stylesheet is the only gate `bun test` can run without a browser.

**Alternatives.** A stylelint rule (a dependency and a config for one file); a review habit (the thing the guard replaces).
