# Phase 4 — The project switcher

> **Dependencies:** Phase 0 (the bench nav with the breadcrumb button and the parked `.pg-ws` overlay; `bench-tokens.test.ts`), Phase 1 (the envelope at version 2 and its migrator, decision 5).
> **Warnings:** Decision 13 is the spec; decision 15 governs the narrow layout; decision 2 makes the design file win over `README.md`. The tree's data, its keyboard contract and its persisted expansion set are kept whole — this phase moves the tree into a popover and re-skins its rows; it does not redesign it. `island-smoke.test.ts:172-207` and `:385-503` walk the tree by class name and must be rewritten in the same slice that renames a class, never after.

## Goal

A reader clicks the breadcrumb in the nav (`Examples / nand ▾`) and a 340px popover opens under it over a dimmed bench: a search row on top, the projects beneath it in three groups — `Tour`, `Examples`, `Mine` — with the open project expanded one level to its files, and `+ New circuit` and `Import .circ` at the foot. Typing filters the list; the arrow keys walk it as they walk the tree today; `Enter` loads a project or opens a file; `Escape` closes the popover and returns focus to the breadcrumb. `⌘K` (`Ctrl+K` elsewhere) opens it from anywhere on the page. A scratch project can still be renamed, duplicated and deleted from its row, and a `.circ` file on disk can be imported as a new scratch project. The bench behind does not move when the popover opens or closes: the source column's width is the same before and after, measured. `.pg-ws` and every `.pg-tree-*` rule are gone from `global.css`; `ws.expanded` still persists what the reader has open.

## Scope

**In scope:**
- The breadcrumb button in the nav: group label in `--muted`, project label in `--fg`, a `▾` that flips to `▴` while open; open state `border --accent` with a `0 0 0 3px` ring of the accent at 18% (`Playground Upgrade.dc.html` at the 3a board: `box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 18%, transparent)`).
- The popover (`.pg-switch`): `position: absolute` under the nav, `width: 340px`, `--pane-bg`, `border --border`, `radius 8px`, `box-shadow: 0 12px 32px rgba(0,0,0,.28)`, `overflow: hidden`; a search row (`⌕`, the input, a `⌘K` kbd chip; `padding 10px 12px; border-bottom --border; mono 12px`); the list (`max-height: 460px; overflow: auto; padding: 2px 0 6px`); the footer (`+ New circuit` in `--accent`, `Import .circ` in `--muted`; `padding 10px 12px; border-top --border; mono 11.5px`).
- The rows, from the design's `wsRow` factory: group `padding 10px 12px 4px; 10.5px uppercase 0.08em --muted`; project `padding 6px 12px; padding-left 26px; mono 12px --fg`, the open project in `--accent`; file `padding-left 40px`, the active file on `--pane-label-bg` with a `2px --accent` left rule; meta right-aligned (`margin-left: auto; 10.5px --muted`), or an accent pill (`--accent` on `--bg`, `padding 1px 6px`, `radius 999px`) carrying the project's `rollUp` badge, `--danger` when the severity is `error`.
- The display groups of decision 13: `Tour`, `Examples` (the three catalogue tiers merged, in `CATALOGUE_GROUPS` order), `Mine` (the envelope's scratch list, id `yours` kept).
- `filterNodes` and `relativeTime` in `ws-tree.ts`, pure and tested.
- The scrim (`inset: 48px 0 0 0`; `rgba(12,5,23,.45)` dark, `rgba(68,56,86,.18)` light, written as `color-mix` over `--bg` / `--fg` so `bench-tokens.test.ts` holds).
- Import: a hidden `<input type="file" accept=".circ">` behind `Import .circ`, read as text, made a scratch project through `createScratch` (`playground-store.ts:625`).
- The narrow layout: below 800px the popover is a full-width card under the nav (`left: 0; right: 0; width: auto`), the scrim the same.
- The removal of the Phase 0 bridge (`.pg-ws` as an overlay) and of every `.pg-ws*`/`.pg-tree*` rule (`global.css:1739-1935`), replaced by `.pg-switch*`.

**Explicitly deferred:**
- Multi-file import (a folder, or several `.circ` files at once): the marker format joins siblings (`split-files.ts:53`), but a picker for a set of files is undesigned.
- Tier headings inside `Examples` (`Introduction`, `Building blocks`, `Advanced`): decision 13 names three groups; the tiers survive only as the order of the rows.
- Search over file *contents*; the filter matches names only.
- The `4 · Memory · soon` row the board draws: illustrative copy, per decision 2.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/test/switcher.test.ts` | Unit tests for `filterNodes`, `relativeTime`, `displayGroups` and the `.pg-switch` token guard cases that need a fixture beyond `bench-tokens.test.ts`. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/scripts/ws-tree.ts` | `ProjectInput.fileCount`, `ProjectInput.updatedAt?`, `ProjectNode.meta`; `filterNodes(nodes, query)`; `relativeTime(updatedAt, now)`; `displayGroups(catalogue, scratch)` building the three groups of decision 13. `visibleNodes`, `moveFor`, `toggle`, `reveal`, `groupOf`, `rollUp` unchanged. |
| site | `site/src/components/Playground.astro` | The `.pg-ws` markup (`:57-90`) replaced by the breadcrumb button in the nav and the `.pg-switch` popover plus scrim as siblings of the frame; `treeInput()` (`:1209-1238`) built on `displayGroups`; `renderTree()` (`:1294-1478`) rendering into the popover's list with the new classes and the meta column; the open/close state machine (`openSwitcher`, `closeSwitcher`); the `⌘K` listener on `document`; the search input's `input` and `keydown` handlers; `importProject()`; the `activeLabel()`/`groupOf` pair feeding the breadcrumb text on every `renderTree`; `wsToggle`/`wsRoot` wiring (`:1636-1642`) removed. |
| site | `site/src/styles/global.css` | `.pg-ws*` and `.pg-tree*` rules (`:1739-1935`) and the `--pg-ws-w` tracks (`:1996-2004`) removed; `.pg-switch*`, `.pg-crumb*`, `.pg-scrim` added; the `@media (max-width: 800px)` block (`:2042-2060`) loses its `.pg-ws` rules and gains the full-width card. |
| site | `site/src/utils/playground-store.ts` | `DEFAULT_WS.expanded` becomes `['tour', 'examples', 'yours']` (`:129`); the version-1 migrator of decision 5 maps `introduction`/`building-blocks`/`advanced` in a stored `ws.expanded` to `examples`. |
| site | `site/test/ws-tree.test.ts` | Cases for `filterNodes` and `relativeTime`; `visibleNodes` cases updated for `meta`. |
| site | `site/test/workspace.test.ts` | `displayGroups` order and membership; import through `createScratch` with the stem as name; the migrator's group mapping. |
| site | `site/test/island-smoke.test.ts` | The tree walk (`:172-207`, `:385-503`) rewritten against `.pg-switch-row` and friends, opened through the breadcrumb first; a no-reflow measurement; `⌘K` opens and `Escape` closes. |
| site | `site/test/app-layout.test.ts` | `panes` assertion (`:299`, `['pg-ws','pg-editor','pg-splitter','pg-output']`) updated to the bench's region order without `pg-ws`. |
| site | `DOCS/decisions/playground-bench.md` | Decision 13 as exercised, with the group merge and the import cap recorded. |

**New dependencies:** None.

## Data & State

```ts
// ws-tree.ts
export interface ProjectInput {
  id: string;
  label: string;
  editable: boolean;
  /** Files in the project's combined source: `splitFiles(source).length`.
   *  Computed once for the catalogue at island init; per render for scratch. */
  fileCount: number;
  /** Epoch ms, scratch only (`ScratchProject.updatedAt`, playground-store.ts:60). */
  updatedAt?: number;
}

export interface ProjectNode {
  // …as today (ws-tree.ts:33-51), plus:
  /** What the row's right column says when it carries no badge:
   *  `N file(s)` for a shipped project, `relativeTime(updatedAt)` for scratch. */
  meta: string;
}

/** The three display groups of decision 13, in this order. Ids are the
 *  persisted expansion keys; `yours` keeps its id so a stored set survives. */
export type DisplayGroupId = 'tour' | 'examples' | 'yours';
export function displayGroups(
  catalogue: readonly { id: string; label: string; group: CatalogueGroup; source: string }[],
  scratch: readonly ScratchProject[],
): TreeInput['groups'];

/** Rows matching `query`, case-insensitive substring on project and file labels.
 *  A group survives when any of its projects survives; a project survives when
 *  it or any of its files matches; the open project stays expanded. An empty
 *  query returns `nodes` unchanged (same reference). */
export function filterNodes(nodes: readonly TreeNode[], query: string): TreeNode[];

/** `just now` under a minute; `N min ago`; `N h ago`; `yesterday`; `N days ago`
 *  to 30; then the ISO date. `now` injected so the test is deterministic. */
export function relativeTime(updatedAt: number, now: number): string;
```

Island state (module-scoped in `init`, as `expanded`, `treeFocus`, `treeNodes` are today, `Playground.astro:1188-1203`):

```ts
let switcherOpen = false;   // mirrored on the breadcrumb's aria-expanded and .pg-switch[hidden]
let query = '';             // the search input's value; never persisted
// treeNodes = filterNodes(visibleNodes(treeInput()), query) on every render
```

The envelope changes only in its default and its migration (decision 5): `ws.expanded` keeps its type (`string[]`, `playground-store.ts:39-43`).

## Execution & Concurrency Model

This phase is fully synchronous. The one asynchronous edge is `Import .circ`: the picked `File` is read with `file.text()`, and the `createScratch` call runs in its continuation; a second pick before the first resolves is not possible because the input is re-armed only after the continuation runs. No worker or renderer call is added. Rendering stays where it is: `renderTree` rebuilds the list from data on every call, exactly as it rebuilds the sidebar now (`Playground.astro:1294`).

## Persistence & I/O

- `ws.expanded` is written on every deliberate toggle through `persistExpanded()` (`Playground.astro:1240-1243`), unchanged; `reveal` on `loadProject` (`:1097-1102`) unchanged.
- The query, the open state and the scroll position of the list are session-only.
- Import reads one file from the reader's disk through the file input; nothing is uploaded. Over `MAX_SOURCE_BYTES` (`32 * 1024`, `playground-store.ts:20`) `createScratch` returns `created: null` with the project in `skipped`; the island posts the store's `skipped` note through the existing `status` channel (`:1075`, `describeNote`) and creates nothing. Past `MAX_SCRATCH` the oldest scratch project is evicted by `createScratch` itself, never the active one.

## Slices

The execution agent implements this phase one slice at a time. Per the Working Loop, from this phase on a slice is committed without asking, and the agent stops only before the first slice of a new phase.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The tree's new data | `displayGroups`, `fileCount`, `meta`, `relativeTime` in `ws-tree.ts`; `treeInput()` on them; the migrator's group mapping and the new `DEFAULT_WS`; the sidebar bridge still rendering, now under three groups. | `ws-tree.test.ts` (`meta` cases), `workspace.test.ts` (`displayGroups`, migration), `playground-store.test.ts` green; `bun test`. |
| 2 | `filterNodes` | The pure filter and its tests; the bridge gains a search input above the tree wired to it, so the filter is driven by hand before the popover exists. | `ws-tree.test.ts` filter cases (below). |
| 3 | The popover and the breadcrumb | `.pg-switch` markup, `.pg-crumb` button, the scrim, open/close, focus in and out, `⌘K`/`Ctrl+K`, `Escape`; `renderTree` into the list with the new row classes and the meta column; the bridge and every `.pg-ws*`/`.pg-tree*` rule removed; the narrow card. | `island-smoke.test.ts` rewritten: open through the breadcrumb, the tree walk, the group collapse, rename and delete flows, `Escape` returning focus, the no-reflow measurement; `app-layout.test.ts` and `bench-tokens.test.ts` green; `bun --bun run build` then `bun test`. |
| 4 | Import and the footer | `+ New circuit` on `newProject`; `Import .circ` through the file input and `createScratch`; the over-size refusal; the decisions entry; STATUS with the `bun run bundle` numbers. | `workspace.test.ts` import cases; the smoke test's import stub (a `File` from a string through happy-dom); `bun run bundle` within the ceiling. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `displayGroups yields Tour, Examples, Mine in that order` | `workspace.test.ts` | Three groups with ids `tour`, `examples`, `yours`; `Examples` holds every example in tier order; `Tour` holds the tour steps; `Mine` holds scratch sorted by `updatedAt` descending (as `treeInput` sorts today, `Playground.astro:1225`). |
| `a project row carries its file count, or its age when scratch` | `ws-tree.test.ts` | Shipped: `1 file` / `3 files`; scratch: `relativeTime` output; a project with a badge keeps `meta` too (the renderer decides which to show). |
| `relativeTime steps through its bands` | `ws-tree.test.ts` | 30 s → `just now`; 5 min → `5 min ago`; 3 h → `3 h ago`; 26 h → `yesterday`; 3 d → `3 days ago`; 40 d → the ISO date. |
| `filterNodes keeps a group when a child matches` | `ws-tree.test.ts` | Query `add` keeps `Examples`, the projects whose label contains `add`, drops the rest; group rows survive with their `expanded` flag. |
| `filterNodes matches a file and keeps its project and group` | `ws-tree.test.ts` | Query on an open project's file name keeps the group, the project and only the matching files. |
| `filterNodes is case-insensitive and trims` | `ws-tree.test.ts` | `  NAND ` matches `nand`. |
| `an empty query returns the same array` | `ws-tree.test.ts` | Reference equality, so the unfiltered path costs nothing. |
| `moveFor walks the filtered list` | `ws-tree.test.ts` | `moveFor(filterNodes(nodes, q), i, 'ArrowDown')` steps within the filtered rows only. |
| `the v1 migrator maps the tier ids to examples` | `playground-store.test.ts` | A recorded v1 envelope with `ws.expanded: ['building-blocks','yours']` becomes `['examples','yours']`, once, with no duplicate. |
| `import creates a scratch project named after the file stem` | `workspace.test.ts` | `createScratch(list, { name: uniqueName('half-adder', taken), source })` with `half-adder.circ`'s stem; a second import of the same name yields `half-adder 2`. |
| `import refuses an over-size file` | `workspace.test.ts` | A 32 KiB + 1 source yields `created: null` and one `skipped` entry. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `the breadcrumb opens the switcher and Escape closes it` | `island-smoke.test.ts` | `aria-expanded` flips on the button; `.pg-switch` loses `hidden`; the search input holds focus; `Escape` hides it and focus returns to the button. |
| `⌘K opens the switcher from the editor` | `island-smoke.test.ts` | A `keydown` with `metaKey` (and one with `ctrlKey`) on `document` opens it and focuses the search. |
| `the bench does not reflow when the switcher opens` | `island-smoke.test.ts` | The `--pg-source-w` property and the source region's `offsetWidth` are equal before, while open, and after. |
| `the tree walk` | `island-smoke.test.ts` | The existing cases at `:172-207` and `:385-503` (group collapse, add file, root chip, delete arming, rename with conflict) pass against `.pg-switch-row`, `.pg-switch-group`, `.pg-switch-project`, `.pg-switch-file`, `.pg-switch-label`, `.pg-switch-action`, `.pg-switch-input`. |
| `typing filters and ArrowDown enters the list` | `island-smoke.test.ts` | Input `xor` leaves only matching rows; `ArrowDown` from the search focuses the first row; `Enter` on a project loads it and closes the popover. |
| `Import .circ makes a project` | `island-smoke.test.ts` | Dispatching `change` on the file input with a `File` named `blink.circ` yields a `Mine` row `blink` marked open. |
| `every .pg-switch colour is a token` | `bench-tokens.test.ts` | The Phase 0 guard, unchanged, holds over the new rules, including the scrim and the ring written as `color-mix` over tokens. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun test test/island-smoke.test.ts && bun run bundle`

## Open Questions / Spikes

- `TODO(phase4)`: the board draws no twisty on group rows; the keyboard contract keeps groups collapsible (`moveFor` `ArrowLeft`/`ArrowRight`, `ws-tree.ts:267-274`). The spec takes a `▾`/`▸` in the group's meta slot, `--muted` 10px, and the deep review of slice 3 confirms or drops it against the file.
- `TODO(phase4)`: `Ctrl+K` on Linux and Windows is unbound in the editor's own keymap (`circ-editor.ts:80`, hand-rolled, no `defaultKeymap`) and in the console (`Playground.astro:938` binds only `Ctrl+L`); the listener on `document` must still yield when the target is a text input other than the search, so a reader typing `Ctrl+K` in a rename input keeps it.
- `TODO(phase4)`: whether `Enter` in the search with several matches loads the first project match or only moves focus into the list. The spec takes: one project match loads it; otherwise focus moves into the list.
