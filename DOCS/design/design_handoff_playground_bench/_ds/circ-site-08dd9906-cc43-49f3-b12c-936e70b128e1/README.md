## Building with circ

The visual language of the circ site — a documentation system for a small
hardware-description language. It reads as quiet, typographic and purple: one
accent hue, generous measure, mono for anything a compiler produced.

### Setup

**No provider or context is required.** Every component styles itself from
plain CSS classes, so a component works the moment `styles.css` is loaded.

Start whole pages with `SiteShell` — it supplies `Nav`, a centred `<main>`
(1100px cap) and `Footer`, which is the measure everything else assumes.

Dark mode is **not** a separate palette to write: set `data-theme="dark"` on
the root element and every token re-points. `ThemeToggle` does exactly this.
Never hand-write a dark variant.

### The styling idiom: semantic classes + tokens

There are **no utility classes** here — no `bg-*`, no `p-4`, no `flex`. Two
rules cover everything:

1. **Components own their classes.** Don't pass `className` to restyle a
   component or reproduce its markup by hand; use its props.
2. **For your own layout glue, use the CSS custom properties**, never literal
   colours or fonts:

| Surfaces | `--bg` `--pane-bg` `--code-bg` `--pane-label-bg` |
|---|---|
| Ink | `--fg` `--muted` `--accent` `--accent-soft` |
| Line | `--border` |
| Type | `--font-prose` `--font-mono` `--font-mono-strict` |
| Measure | `--measure` (36rem body measure) `--line` (1.65) |

`--font-mono-strict` exists for one reason: ASCII schematics. Necto Mono is
stylized and its box-drawing glyphs don't hold the character grid, so any
`circ-compile --preview` output must use the strict stack. `CodePreview`
already does.

A few genuinely reusable classes: `.muted` (small secondary text),
`.lede` (summary under a heading), `.visually-hidden`, `.link-soon` (a
disabled-looking nav item).

### Bare elements are already styled

`body`, `main`, `h1`–`h4`, `p`, `a`, `ul`/`ol`, `pre`, `code`, `hr` all carry
site styling from the stylesheet. Write plain HTML inside components and it
will look right — restyling it is how designs drift off-brand. Long-form
content belongs in `Prose`, which additionally styles tables, blockquotes and
heading rules.

### Where the truth is

Read `_ds/<folder>/styles.css` and its `@import` closure (`_ds_bundle.css`
holds the whole stylesheet; `fonts/fonts.css` the two faces) before styling
anything. Each component has a `.prompt.md` next to it with its own usage
notes.

### An idiomatic page

```jsx
<SiteShell>
  <h1>Download</h1>
  <Tagline>One command puts circ-compile on your PATH.</Tagline>
  <AlphaWarning>
    <p>Expect rough edges and breaking changes between builds.</p>
  </AlphaWarning>
  <CommandSnippet code="curl -fsSL https://circ-lang.org/install.sh | sh" />
  <div style={{ maxWidth: 'var(--measure)', color: 'var(--muted)' }}>
    Prefer building from source? See the getting-started guide.
  </div>
</SiteShell>
```

Note the glue: a bare `<div>` with `var(--measure)` and `var(--muted)` — not a
utility class, not a hex code.

# CircDS (circ-ds@0.1.0)

This design system is the published circ-ds React library, bundled as a single
browser global. All 17 components are the real upstream code.

## Where things are

- `_ds_bundle.js` — the whole-DS bundle at the project root; loads every component to `window.CircDS`. First line is a `/* @ds-bundle: … */` metadata header.
- `styles.css` — the single stylesheet entry: it `@import`s the tokens, fonts, and component styles (`_ds_bundle.css`). Link this one file.
- `components/<group>/<Name>/<Name>.prompt.md` (example JSX + variants), `<Name>.d.ts` (types), `<Name>.html` (variant grid).
- `tokens/*.css` — CSS custom properties, names verbatim from upstream.
- `fonts/` — `@font-face` files + `fonts.css` (when the package ships fonts).

For a specific component, `read_file("components/<group>/<Name>/<Name>.prompt.md")`.

## Loading

Add these two lines to your page once (React must be on the page first):

```html
<link rel="stylesheet" href="styles.css">
<script src="_ds_bundle.js"></script>
```

Components are then available at `window.CircDS.*`. Mount into a dedicated child node (e.g. `<div id="ds-root">`), not the host page's own React root, so the two trees don't collide:

```jsx
const { AlphaWarning } = window.CircDS;
ReactDOM.createRoot(document.getElementById('ds-root')).render(<AlphaWarning />);
```

## Tokens

14 CSS custom properties from circ-ds. Names are
preserved verbatim from upstream. They are declared inside `_ds_bundle.css` (this DS ships one compiled stylesheet rather than separate token files).

- **typography** (3): `--font-prose`, `--font-mono`, `--font-mono-strict`
- **other** (11): `--bg`, `--fg`, `--muted`, …

## Components

### content
- `AlphaWarning` — The loudest note in the system: a full accent border around the pane
- `ExampleCard` — One entry in the examples gallery. Cards are separated by a rule rather
- `Lineage` — Italic aside on an accent left-rule  used at the foot of the landing page
- `StatusNote` — Inline callout on the pane surface with a thick accent left-border. Any
- `Tagline` — The one-sentence pitch under a landing h1. Set larger than body copy
- `TourStep` — One numbered step in the tour. Steps are separated by a rule the first

### code
- `CodePreview` — The site's signature figure: circ source on the left, the --preview ASCII
- `CommandSnippet` — A copyable shell command. The Copy button is pinned to a relative wrapper
- `LiveCanvas` — Frame for an interactive circuit simulation: a mono header strip, a launch

### layout
- `DocsPage` — Reference-page layout: header, a sticky 14rem table of contents, and the
- `Prose` — Long-form body copy container. Gives headings their rules, tables their
- `SiteShell` — The page frame every circ page uses: Nav, a centred main column, and

### download
- `DownloadTable` — The release manifest on the download page. Cells never wrap and the table
- `InstallLine` — Full-width mono call-to-action on the code surface  the landing page's

### navigation
- `Footer` — Page footer: link row plus the small-text byline cluster (licence,
- `Nav` — Site header: wordmark, primary links, and the theme toggle. Below 600px the
- `ThemeToggle` — Light/dark switch. Flips data-theme on html, which is the single
