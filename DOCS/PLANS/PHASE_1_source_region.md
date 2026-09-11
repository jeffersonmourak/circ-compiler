# Phase 1 — The source region

> **Dependencies:** Phase 0 (the frame, the two regions, the source column on `--pg-source-w`, the bench nav carrying the status cluster; `bench-tokens.test.ts` in place).
> **Warnings:** Decisions 5, 6, 7, 8 and 16 of `DOCS/PLANS_PROMPT.md` are authoritative. Three things the plan prompt assumed are not what the code says, and this spec follows the code: (1) there is **no file-tab strip today** — files are rows of the workspace tree (`.pg-tree-file`, `Playground.astro:2595`), `focusFileTab` focuses a tree row (`:1491-1494`), and `role="tabpanel"` on `.pg-editor-wrap` (`:92`) is labelled by a tree row; the strip is new markup over the existing `FileTabsState` model. (2) There is **no `unicode | ascii` setting** to park: the settings form (`:153-181`) holds `expandMacros`, `expandDisplay`, `format`, `valueFormat`, `truthTableCap`, `warningsAsErrors`; `DOCUMENTED_OPTION_KEYS` (`settings-drawer.ts:11-20`) has no charset key and `--preview` takes none (`lib/cli/args.zig:96`). Phase 3 must decide what the board's `unicode | ascii` control is; nothing leaves the form here. (3) `--danger` **already exists** (`global.css:42`, `:74`, read by `.pg-dock-badge` at `:801`); nothing to add. Every value below comes from the design file's inline styles (`Playground Upgrade.dc.html:103-107`, `:115`, `:184-185`) and the README's "Source region"; the file wins where they differ (decision 2).

## Goal

The left region reads as the design's source pane: a 36px strip of file tabs with the open file underlined in `--accent` and `+ file` beside it; the editor below with `16px 0` of padding, 14px strict mono at 1.7, and a 32px gutter at 55% opacity; and a 30px footer under the editor that says `N errors · N warnings` on the left (in `--fg` with a `▾` when either is non-zero) and `N lines · N components · N <noun>` on the right. Clicking the counts expands a list on `--pane-label-bg` — glyph, `file:line:col` in `--accent`, code, message on a `14px 104px 52px 1fr` grid — and clicking a position moves the editor there, switching files first when the compiler blamed another one, exactly as the dock's list does today. A gear at the right end of the footer opens the settings form in the same expanded area. The dock (`.pg-dock`) is gone. A reader who saved a version-1 envelope keeps every scratch project on their first visit to the bench, with their last view and footer state carried over.

## Scope

**In scope:**
- The file-tab strip (`.pg-files`): one `role="tab"` button per `state.tabs.files` entry, the active one `aria-selected`, roving `tabindex` with arrow keys, `+ file` calling `addNewFile` (`Playground.astro:2603`). Rename, delete and reorder stay where they are (the tree until Phase 4, the switcher after); the strip is the switch.
- Editor metrics in `global.css` (`.pg-cm .cm-content`, `.cm-scroller`) and the gutter in `circ-editor.ts`'s theme (`:243-247`) and `circ-editor-theme.ts` palette (`:151-153`).
- `site/src/scripts/footer-summary.ts`: `summarize(files, analysis, mapped)` and `summaryLabels(summary)`, pure and tested.
- The diagnostics footer (`.pg-footer`): bar, expanded list, gestures, position links, hover highlight, the gear and the settings form (decision 7). `mountSettingsDrawer` (`settings-drawer.ts:142`) is re-pointed at the new root and otherwise untouched.
- The store at `STORE_VERSION = 2` with `migrateV1` (decision 5): `view`, `footer`, `layout.sourceWidth`; `tab` and `dock` gone.
- The island bridge until Phase 2: the four-tab output pane reads its tab from `view` and writes `view` back.
- `.pg-dock*` markup, wiring (`:687-718`, `:2490-2491`) and rules (`global.css:740-825`) removed; the smoke test rewritten for the strip and the footer.
- `DOCS/decisions/playground-bench.md`: decisions 5, 7 and the strip recorded.

**Explicitly deferred:**
- The view switch itself and `dataOpen` (Phase 2); `drawerHeight` and the drawer splitter's move off `ratios.drawer` (Phase 6); the switcher's file rows (Phase 4).
- Nets in the right-hand summary: the analyze reply carries `files`, `diagnostics`, `symbols`, `references` (`circ-diagnostics.ts:57-62`, `DOCS/analyze-api.md:49-57`) and no nets; `FullTopology.connections` (`circ-renderer/src/wasm/topology.ts:152-155`) exists only once a session is built. The third slot is chosen from the symbols (see Data & State). `TODO(phase1):` a later phase may swap in `connections.length` when a session exists.
- Any change to `file-tabs.ts`: the model is complete and its purity case scans the file's source (`file-tabs.test.ts:101-102`).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/footer-summary.ts` | The footer's two strings from the tab bodies, the analysis and the mapped diagnostics. No DOM. |
| site | `site/test/footer-summary.test.ts` | Counts, pluralisation, the noun rule, the pre-analysis state. |
| site | `site/test/fixtures/store/envelope-v1.json` | A literal version-1 envelope as `writeEnvelope` wrote it on `main` at `59e884c`: two scratch projects, `activeId` on one, `tab: 'data'`, `dock: { open: true, tab: 'settings' }`, `layout.ratios: { main: 0.42, drawer: 0.7 }`, `ws.expanded`. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/utils/playground-store.ts` | `STORE_VERSION = 2`; `View`, `VIEWS`, `FooterState`, `DEFAULT_FOOTER`; `LayoutState { sourceWidth, ratios }`; `PlaygroundEnvelope { view, footer }` replacing `tab`, `dock`; `migrateV1`; `normalizeFooter`, `normalizeSourceWidth`; `OUTPUT_TABS`, `DOCK_TABS`, `DEFAULT_DOCK`, `OutputTab`, `DockTab`, `DockState` deleted. |
| site | `site/src/components/Playground.astro` | Markup: `.pg-files` above `.pg-editor-wrap`; `.pg-footer` replacing `.pg-dock` (the settings form moves inside it unchanged). Script: `renderFileTabs`, `focusFileTab` retargeted; `showFooter`, `setFooterOpen` replacing the four dock functions; `renderDiagnostics` writes the footer bar and the grid list; `showTab` bridges `view`; bootstrap restores `footer` and `view`. |
| site | `site/src/scripts/circ-editor.ts` | `.cm-gutters` opacity and the line-number cell's `minWidth`; `.cm-content` padding is CSS, not theme. |
| site | `site/src/utils/circ-editor-theme.ts` | `gutterBackground` and `gutterBorder` become `'transparent'` in both modes (the mock's gutter has no band). |
| site | `site/src/styles/global.css` | `.pg-files*`, `.pg-footer*`, `.pg-diag` as a grid; editor metrics; `.pg-dock*` rules deleted; `.pg-diag-ok`, `.pg-diag-counts` deleted. |
| site | `site/test/playground-store.test.ts` | The migration test on the fixture; the mismatch test moves to version 3; `footer`, `view`, `sourceWidth` normalisation. |
| site | `site/test/island-smoke.test.ts` | Strip and footer walks replace the dock walks (`:209-221`, `:265-270`, `:302-333`). |
| site | `site/test/circ-editor-theme.test.ts` | The gutter is transparent in both modes. |
| site | `DOCS/decisions/playground-bench.md` | Entries for the migration, the footer, the strip. |

**New dependencies:** None.

## Data & State

The envelope at version 2 (`playground-store.ts`); unchanged fields elided:

```ts
export const STORE_VERSION = 2;

export type View = 'schematic' | 'live' | 'truth';
export const VIEWS: readonly View[] = ['schematic', 'live', 'truth'];

/** The footer under the editor: open or not, and which panel it was left on. */
export interface FooterState {
  open: boolean;
  tab: 'diagnostics' | 'settings';
}
export const DEFAULT_FOOTER: FooterState = { open: false, tab: 'diagnostics' };

export interface LayoutState {
  /** The source column, in CSS pixels. Clamped on render, never on commit. */
  sourceWidth: number;
  /** `drawer` only, until Phase 6. `main` left with version 1. */
  ratios: Record<string, number>;
}
export const DEFAULT_SOURCE_WIDTH = 480;

export interface PlaygroundEnvelope {
  version: number;
  scratch: ScratchProject[];
  activeId: PickId | null;
  activeFile: string | null;
  layout: LayoutState;
  settings: PlaygroundSettings;
  view: View;
  footer: FooterState;
  ws: WorkspaceState;
}
```

The migration, called from `normalize` before the version check rejects anything:

```ts
/** A version-1 envelope reshaped for version 2. Field by field, so a key the
 *  old writer never produced is simply absent and `normalize` defaults it. */
export function migrateV1(raw: Record<string, unknown>): Record<string, unknown> {
  const tab = raw.tab;
  const view: View =
    tab === 'truth' ? 'truth' : tab === 'simulate' || tab === 'data' ? 'live' : 'schematic';
  const dock = isObject(raw.dock) ? raw.dock : {};
  const layout = isObject(raw.layout) ? raw.layout : {};
  const ratios = isObject(layout.ratios) ? { ...layout.ratios } : {};
  delete ratios.main;
  return {
    ...raw,
    version: 2,
    view,
    footer: { open: dock.open, tab: dock.tab },
    layout: { sourceWidth: DEFAULT_SOURCE_WIDTH, ratios },
    tab: undefined,
    dock: undefined,
  };
}
```

`normalize(raw)`: `version === 1` → `migrateV1`, then the version-2 path; `version !== 2` after that → the reset note, as today (`:252-255`). `normalizeSourceWidth`: a finite integer in `[320, 8192]`, else the default. `normalizeFooter`: the shape of `normalizeDock` (`:171-177`) over the new names. `TODO(phase1):` Phase 0 stores the pixel width somewhere until this migration lands (`normalizeRatios` refuses anything outside `(0, 1)`, `:233-242`); its STATUS entry names the field, and the migrator reads that field instead of defaulting when it is present.

The footer summary (`footer-summary.ts`):

```ts
export interface FooterSummary {
  errors: number;
  warnings: number;
  /** Lines over every file of the project, counting a trailing newline once. */
  lines: number;
  /** Symbols in the project's files whose kind is not `input` or `output`; null before an analysis. */
  components: number | null;
  /** The third slot: what the circuit is made of, in the design's contextual noun. */
  extra: { count: number; noun: 'memory' | 'chip' | 'pin' } | null;
}

export function summarize(
  files: readonly { name: string; body: string }[],
  analysis: Analysis | null,
  mapped: readonly { severity: 'error' | 'warning' }[],
): FooterSummary;

/** `['0 errors · 1 warning', '16 lines · 16 components · 22 pins']`; the right
 *  string is `'16 lines'` alone before an analysis. */
export function summaryLabels(s: FooterSummary): [left: string, right: string];
```

The noun rule, from the boards (`:367` "6 chips", `:448` "1 memory", `:115` "4 nets"): `memory` when any project symbol is `rom` or `ram` (counting those), else `chip` when any is `instance` (counting those), else `pin` counting `input` and `output` symbols. Project symbols are those whose `file_id` maps to a path under `PLAYGROUND_DIR` (the rule `countsByFile` uses, `file-tabs.ts:184-196`); builtin files are excluded. `errors`/`warnings` come from `state.mapped` (`Playground.astro:3055-3058`), so the bar and the list agree.

The footer element:

```html
<div class="pg-footer" data-open="false" data-tab="diagnostics">
  <div class="pg-footer-bar">
    <button type="button" class="pg-footer-counts" aria-expanded="false" aria-controls="pg-footer-body">
      <span class="pg-footer-counts-text">0 errors · 0 warnings</span><span class="pg-footer-caret" aria-hidden="true">▾</span>
    </button>
    <span class="pg-footer-stats">5 lines</span>
    <button type="button" class="pg-footer-gear" aria-label="Settings" aria-expanded="false" aria-controls="pg-footer-body">⚙</button>
  </div>
  <div class="pg-footer-body" id="pg-footer-body" hidden>
    <ul class="pg-diag" data-footer-panel="diagnostics"></ul>
    <div class="pg-settings" data-footer-panel="settings" hidden>…the form, unchanged…</div>
  </div>
</div>
```

`data-open` and `data-tab` mirror `footer`; `[data-severity="none"]` on the counts button when both are zero (then `--muted`, no caret; else `--fg` with the caret). The list is a grid: `.pg-diag { display: grid; grid-template-columns: 14px 104px 52px 1fr; gap: 10px; padding: 6px 16px 10px; align-items: baseline; }`, each diagnostic four cells with `display: contents` on the `li`: glyph `▲` (`--danger` for an error, `--muted` for a warning), a `<button>` with `file:line:col` in `--accent` (the click and hover handlers of `:3096-3143` move onto it), the code in `--muted`, the message in `--fg`. A row without a span (`<builtin>/…`) renders its position as a `<span>` in `--muted`, not a disabled button. With no diagnostics the list is empty and the body, if open on diagnostics, shows one line `No diagnostics.` in `--muted`.

Gestures, the dock's kept (`:704-718`): the counts button opens the body on `diagnostics`, or closes it when it is already open on `diagnostics`; the gear does the same for `settings`; opening on the other panel while open switches panels. `Escape` in the body closes it and returns focus to the button that opened it. The body's height is `max-height: 40%` of the source region with its own vertical scroll (the dock used a fixed `--pg-dock-h`, `global.css:817-819`).

The file-tab strip:

```html
<div class="pg-files" role="tablist" aria-label="Files">
  <button type="button" role="tab" class="pg-file" data-file="0" aria-selected="true" aria-controls="pg-editor-panel" tabindex="0">nand.circ</button>
  <button type="button" class="pg-file-add" aria-label="New file">+ file</button>
</div>
```

`renderFileTabs()` rebuilds the buttons from `state.tabs` after every operation that calls `renderTree()` today (`:2559`, `:2593`, `:2609`, `:2646`, `:2683`); `focusFileTab(index)` focuses `.pg-file[data-file="<index>"]` and sets the roving `tabindex`; `ArrowLeft`/`ArrowRight`/`Home`/`End` move the selection through `showFile` (`:2551`). `.pg-editor-wrap`'s `aria-labelledby` points at the active strip tab. The tree's file rows keep working; both call `showFile`.

Editor metrics: `.pg-cm .cm-scroller { font-size: 14px; line-height: 1.7 }` (was `0.9rem / 1.5`, `global.css:641-643`), `.pg-cm .cm-content { padding: 16px 0 }` (was `0.75rem 0`, `:646`), `.cm-line` padding unchanged; in `circ-editor.ts:243` `'.cm-gutters': { …, opacity: '0.55' }` and `'.cm-lineNumbers .cm-gutterElement': { minWidth: '32px' }`.

## Execution & Concurrency Model

This phase is fully synchronous. No worker, timer or listener is added; the two pipeline stages and their sequence counters (`Playground.astro:2703-2708`) are untouched, and the footer re-renders from `renderDiagnostics` on the same calls that render the list today (`:3021-3031`). The strip re-renders on the synchronous file operations only.

## Persistence & I/O

The envelope under `circ.playground.v1` (`STORE_KEY`, unchanged: the key names the store, the `version` field names the schema) is read once at boot through `readEnvelope` → `normalize`, which now migrates a version-1 body. `footer.open`, `footer.tab`, `view` and `layout.sourceWidth` are written through `store.update` on the same debounce as everything else (`WRITE_DEBOUNCE_MS`). No other I/O.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The summary module | `footer-summary.ts` with `summarize` and `summaryLabels`; nothing wired. | `footer-summary.test.ts`: counts and pluralisation, the noun rule on a rom project, an instance project and a plain one, `components: null` and a lines-only right string before an analysis, builtin files excluded. |
| 2 | The envelope at version 2 | `View`, `FooterState`, `LayoutState.sourceWidth`, `migrateV1`, the normalisers; the island reads `footer` and `view` (the bridge in `showTab` and bootstrap) and the splitter commits `sourceWidth`; old types deleted. | `playground-store.test.ts`: the fixture migrates with both scratch projects intact, `view: 'live'`, `footer: { open: true, tab: 'settings' }`, `ratios` without `main`; version 3 resets; `sourceWidth` clamps; a `view` outside `VIEWS` falls back to `'schematic'`. `settings-drawer.test.ts` round-trip still green. |
| 3 | The file-tab strip | `.pg-files` markup, rules and `renderFileTabs`; `focusFileTab` retargeted; roving tabindex and arrows; `+ file`. | Smoke: the strip lists the open project's files in order, the active tab `aria-selected`, `.pg-editor-wrap[aria-labelledby]` names it; `+ file` adds a tab before the root and selects it; `file-tabs.test.ts` untouched and green. |
| 4 | Editor metrics | Padding, size, line height in CSS; gutter opacity, width and transparency in the theme. | `circ-editor-theme.test.ts`: gutter background and border are `transparent` in both modes; `app-layout.test.ts` `:792-793` still green; `bench-tokens.test.ts` green. |
| 5 | The diagnostics footer | `.pg-footer` markup and rules; the bar from `summaryLabels`; the grid list with the position buttons carrying the jump and the hover highlight; the gestures; `.pg-dock` markup, functions and rules deleted. | Smoke: the footer is present and closed by default, the counts button opens it on diagnostics and closes it again, `Escape` closes it, `.pg-dock` is absent; a seeded `state.mapped` (the smoke's seam, `:598-604`) renders one grid row per diagnostic with the position in a button; `circ-diagnostics.test.ts` green. |
| 6 | Settings behind the gear | The form inside the footer body, `mountSettingsDrawer` on the new root, the gear gesture, `footer.tab` persisted; decisions recorded; `bun run bundle` numbers in STATUS. | Smoke: the gear opens the body on settings with `[data-setting]` controls inside `.pg-footer` and none elsewhere (`:265-269` rewritten), the counts button switches it to diagnostics while open, a reload restores `footer.tab`; every gate green. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `footer-summary › counts and words` | `footer-summary.ts` | `0 errors · 1 warning`, `1 error · 0 warnings`, `2 errors · 3 warnings`; lines summed over files with a trailing newline counted once. |
| `footer-summary › the third slot` | `footer-summary.ts` | rom → `memory`, instances → `chip`, otherwise `pin`; counts are of that kind only; a builtin-file symbol never counts. |
| `footer-summary › before an analysis` | `footer-summary.ts` | `components: null`, `extra: null`, right string is `N lines`. |
| `playground-store › a version-1 envelope migrates` | `playground-store.ts` | On `fixtures/store/envelope-v1.json`: scratch, activeId, activeFile, settings, `ws` carried; `view`, `footer`, `layout` as specified; `note: null`. |
| `playground-store › version mismatch and corruption reset` | `playground-store.ts` | Version 3 and non-objects reset with the existing notes. |
| `playground-store › footer, view and sourceWidth normalise` | `playground-store.ts` | Unknown `footer.tab` → `diagnostics`; `view: 'data'` → `schematic`; `sourceWidth` 100 → 480, `'x'` → 480, 640 → 640. |
| `circ-editor-theme › the gutter is a band no more` | `circ-editor-theme.ts` | Both palettes: `gutterBackground === 'transparent'`, `gutterBorder === 'transparent'`. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `island-smoke › the strip lists the files` | built island | Tabs match the catalogue project's files; active tab and `aria-labelledby` agree; `+ file` adds and selects. |
| `island-smoke › the footer opens on the counts and on the gear, and remembers which` | built island | Open/close gestures, panel switch while open, `Escape`, `data-tab` persisted through the store seam. |
| `island-smoke › diagnostics render as grid rows` | built island | Seeded `state.mapped` → rows with glyph, position button, code, message; a placeless row has a span, not a button. |
| `app-layout › every app rule is scoped` | `global.css` | Unchanged assertions hold over the new `.pg-footer`/`.pg-files` rules. |
| `bench-tokens › every colour is a token` | `global.css` | Holds over the new rules. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun test test/island-smoke.test.ts && bun run bundle`

## Open Questions / Spikes

- `TODO(phase1):` where Phase 0 parked the pixel width of the source column (see Data & State); the migrator reads it.
- `TODO(phase1):` Phase 3 owns the board's `unicode | ascii` control; it corresponds to no compiler option today and is not a setting this phase removes.
- `TODO(phase1):` the error glyph. The board draws `▲` for a warning only (`:185`); this spec uses `▲` in `--danger` for an error. The deep planner of Phase 7's sweep may pick another glyph if the human prefers one.
