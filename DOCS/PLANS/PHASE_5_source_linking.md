# Phase 5 — Source Linking

> **Dependencies:** Phase 0 (`bun run bundle` + `site/bundle-budget.json`, the regenerated `libcirc.wasm`), Phase 1 (the CodeMirror island `site/src/scripts/circ-editor.ts`, and the widened `Analysis` interface that keeps `symbols[].range` — decision 5 notes `Playground.astro:77-81` drops it today), Phase 2 (`joinFiles`, `site/src/scripts/file-tabs.ts` — a highlight must be able to switch tabs), Phase 3 (`site/src/utils/playground-store.ts`, the splitter, the status bar, and the two-stage debounce). Phase 4 is not a dependency. **Ordering constraint from decision 4** (`DOCS/PLANS_PROMPT.md:42`): the `circ-theme.mjs` skin branches are bound to the `setHighlight` change — without them the highlight is invisible for everything that is not a root input pin — so the skin ring is **slice 3**, ahead of every editor→canvas and canvas→editor slice, and no highlight slice has a browser-visible proof before it lands.
> **Warnings:** Read `DOCS/PLANS_PROMPT.md` decisions **4** and **5** and its whole **Renderer and canvas** trap group before starting. Slice 1 commits in a **second repository** (`/Users/jeffersonmourak/circus/circ-renderer`, branch `host-pin-api`) and ends in a **hard stop**: the agent may not push, and slice 2 cannot begin until the human confirms the push and names the sha (`DOCS/PLANS_PROMPT.md` Git Rules). Never read `/Users/jeffersonmourak/circus/circ-compiler/site/node_modules/circ-renderer` — it is a stale `2.0.0-alpha.1` copy. `compile` transfers `bytes.buffer` (`site/src/workers/libcirc.worker.ts:63-65`): this phase must not become a second consumer of the artifact bytes — it reads the layout from the canvas instead (see Execution). No browser has ever been available in a session on this branch; every in-browser check below is recorded in STATUS as *unrun*.

## Goal

A reader who has a compiled circuit on screen can move between the source and the picture without hunting. Putting the cursor on `and c(a=a, b=b)` in the editor lights up that exact AND box on the Simulate canvas; hovering that box lights up its declaration line back in the editor, or — when the reader is editing a sibling file — names it in the status note without stealing their buffer; hovering a truth-table column header lights up the input or output it names, in the editor and on the canvas; hovering a diagnostics row lights up the span it points at. The join is by declared name — never by span, because artifacts carry no spans — computed once per artifact by a pure function that `bun test` drives headlessly over a committed example, with no canvas, no DOM and no jsdom. Getting there costs `circ-renderer` three additions on branch `host-pin-api` (`RenderOptions.onHover`, `CircCanvas.setHighlight`, `CircCanvas.getLayout`), pushed by the human as this phase's first act, and consumed through the one pin bump that Phases 6 and 7 then build on.

## Scope

**In scope:**

- `circ-renderer` @ `host-pin-api`: `onHover?: (id: number | null) => void` on `RenderOptions`; `CircCanvas.setHighlight(id: number | null)` feeding the existing `SkinContext.hovered` flag through a private `highlightId`; `CircCanvas.getLayout(): LayoutGrid` as the public read accessor; a headless canvas test; version `2.1.0-alpha.1` → `2.1.0-alpha.2`; README rows. Committed on that branch, **not** pushed, **no** PR.
- The site's single pin bump to the new sha, with `site/src/utils/renderer-versions.ts` growing a `RENDERER_PIN_VERSION` constant and `site/test/renderer-pin.test.ts` gaining the drift assertions.
- `site/src/scripts/source-link.ts`: the pure name join over `analyze.symbols` × `LayoutGrid.components`, restricted to symbols whose `file_id` is the root file's and to boxes with `origin.length === 0`; plus cursor→declaration resolution and truth-table header-name normalisation.
- Editor → canvas: cursor lands in a declaration ⇒ `view.view.setHighlight(componentId)`.
- Editor → truth-table header: the cursor's declaration also marks the matching column, by comparing `link.current.name` against each `<th>`'s `data-symbol-name` (produced by `headerSymbolName`); the `<th>` gains `.pg-th-linked` and loses it when `link.current` is `null`. This is the fourth direction of the definition-of-done bullet at `DOCS/PLANS_PROMPT.md:9` ("and vice versa from the cursor"), which the canvas half alone does not satisfy.
- Canvas → editor: `onHover(id)` ⇒ mark the declaration's range in the editor when it is in the active file, and announce it in `.pg-sim-note` when it is not. A hover never switches tabs and never scrolls (see **Execution**); only a keyboard/click activation does.
- Truth-table column headers and diagnostics rows as two more highlight sources, keyboard-operable, not pointer-only.
- `site/src/utils/circ-theme.mjs`: a `hovered` branch in the five skins that lack one (`drawOutputPin`, `drawLed`, `drawNot`, `drawAnd`, `drawSubcircuit`), so the highlight is visible for something other than a root input pin. **`rom` and `ram` are the known gap.** `TOPOLOGY_KIND_OF` maps them (8, 9) and `SymbolKind` includes them, so a cursor on `rom code[8, 4](…)` does reach `setHighlight` — but `circ-theme.mjs`'s `skins` object (`:578-585`) has no `Rom`/`Ram` entry, so `pickSkin` (`circ-renderer src/render/skins.ts:249-253`) falls through to the package's own `defaultSkins[ComponentKind.Rom] = drawMemory` (`:239-240`), and `hovered` appears nowhere in that file (exhaustive grep, exit 1). Pointing at a memory therefore highlights nothing. Left to Phase 6 — the phase that gives a reader a reason to point at one — and recorded as a known no-op in slice 3's STATUS entry rather than discovered in a browser later.

**Explicitly deferred:**

- Hover on the Preview pane. `circ_preview` returns text with no spans (decision 5, and the Phase Index's deferred list).
- Highlighting from a **sibling or `<builtin>/…`** file's symbols. Those are asserted *excluded*, not resolved, and stay excluded for the life of this initiative. They are unresolvable because the canvas draws one collapsed box per macro instance and never draws its internals; expanding them is the **renderer's** `layoutOptions.expandMacros` (`circ-renderer src/layout/types.ts:118-120`, consumed at `src/layout/collapse.ts:42`), which **no phase of this plan wires** — `Playground.astro:369-380` passes no `layoutOptions`, and a grep for `layoutOptions` across `DOCS/` hits only `DOCS/PLANS_PROMPT.md:17` and this file. Phase 6's `expand_macros` is a different surface with a coincident name: libcirc's **preview-only** request option (`DOCS/libcirc-api.md:48`, `DOCS/PLANS/PHASE_6_settings_and_rom_images.md:73,112,265`). `linkLayout` returns these declarations in `unlinked` until then, so the signature is stable — but a later initiative that turns `expandMacros` on must also **relax the `origin.length === 0` filter**, because expand mode materialises inner components with `origin: c.origin` preserved (`collapse.ts:165-180`, the field at `:173`), which is exactly what this phase's join drops. That extension is a behaviour change, not merely a wider signature.
- Go-to-definition, rename, and any use of `analyze.references` (the reference table stays unread this phase).
- A click handler on canvas boxes. The renderer exposes no `onComponentClick` and this phase does not add one; hover plus the editor cursor are the whole interaction surface.
- Persisting the highlight. It is ephemeral state and never enters the `circ.playground.v1` envelope (decision 7).
- Any second decode of the artifact bytes. See Execution.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| circ-renderer | `/Users/jeffersonmourak/circus/circ-renderer/test/canvas-stub.ts` | Minimal `document.createElement("canvas")` + recording 2D-context stub so `bun test` can construct a `CircCanvas` with no DOM. The element must carry the whole surface `CircCanvas` touches, not just a context: `style` (written at `canvas.ts:176`, `:182`), `width`/`height`, `remove()` (`destroy()`, `:168`), `addEventListener` / `removeEventListener` / `dispatchEvent` (`attach()` registers three, `:192-194`), and a `getBoundingClientRect()` returning the **intended** extent so `componentAtEvent`'s `intendedW / rect.width` rescale (`:228-231`) is identity. Installs/uninstalls `globalThis.document`. |
| circ-renderer | `/Users/jeffersonmourak/circus/circ-renderer/test/canvas.test.ts` | Behavioural proof that `setHighlight` reaches `SkinContext.hovered`, that `getLayout()` returns the grid the canvas drew, and that `onHover` fires only on change. |
| circ-renderer | `/Users/jeffersonmourak/circus/circ-renderer/test/fixtures/half_adder.wasm` | **A fixture the repo does not have.** All eight committed fixtures (`and_4bit`, `and_v01`, `bit_index_a2`, `concat_four_bits`, `inverter`, `ram_write_read`, `rom_lookup`, `slice_then_concat`) decode to components with `origin = []` — verified by decoding every `circ.topology.v0.full` section — so `collapse()` allocates no group (`src/layout/collapse.ts:92-97`) and `buildLayout` produces **zero** `{ tag: "subcircuit" }` nodes and zero synthetic ids for any of them; `test/layout.test.ts` and `test/topology.test.ts` never mention `origin` or `subcircuit` (grep, exit 1). This fixture is a byte-for-byte copy of this repo's committed `site/public/wasm/half-adder.wasm` — no compiler run, no new toolchain step. Decoded: `full_version` 3 (accepted by `SUPPORTED_TOPOLOGY_VERSIONS`, `topology.ts:168`), 21 components, max real id 20, 16 carrying `origin`, one outer group `('s','xor')` → one synthetic node `{ id: 21, name: "s", kind: { tag: "subcircuit", subcircuit: "xor" } }` and a 6-box layout. That synthetic id is what the `getLayout` assertion needs. |
| site | `site/src/scripts/source-link.ts` | The pure join (decision 15 names this phase's only new site module). No DOM, no `circ-renderer` import; type-only imports from `circ-diagnostics.ts` and nothing else. |
| site | `site/test/source-link.test.ts` | Unit tests over a committed artifact + an integration test through the committed `libcirc.wasm`. |
| site | `site/test/circ-theme-hover.test.ts` | Source-text guard over `site/src/utils/circ-theme.mjs`: reads the file with `readFileSync` and asserts each of the six functions named by the `skins` object (`:578-585`) destructures `hovered` and references `theme.colors.inputHover` (`:74` light, `:109` dark). Read as **text**, not imported: `circ-theme.mjs:29` calls `loadAssets()` at module scope and `circ-assets.mjs:28` needs `new Image()`, so the module cannot be imported under `bun test`. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| circ-renderer | `src/render/canvas.ts` | `+ onHover` on `RenderOptions` (beside `onPinToggle`, `:38`); `+ private highlightId` (beside `hoverId`, `:49`); `+ private setHover(id)` folding `:172-179` and `:180-184`; `+ setHighlight(id)` mirroring `setInputSignal` (`:208-213`); `+ getLayout()`; `:292` becomes an OR of the two ids. |
| circ-renderer | `package.json` | `"version": "2.1.0-alpha.1"` → `"2.1.0-alpha.2"` (line 3), matching the bump 74f595d made. |
| circ-renderer | `README.md` | An `onHover` row in the `renderCircuit` table (after the `onPinToggle` row at `:40`); `setHighlight` / `getLayout` in **Lower-level building blocks** (`:44-56`); a sentence under **Skin functions** (`:116-135`) saying `hovered` is now true for a pointer hover *or* a host highlight. |
| site | `site/package.json` | `:17` `circ-renderer` specifier → `github:jeffersonmourak/circ-renderer#<newsha>` (written by `bun add`, never by hand). |
| site | `site/bun.lock` | `:8` and `:272` rewritten by the same `bun add`; lock key becomes `jeffersonmourak-circ-renderer-<newsha>`. |
| site | `site/src/utils/renderer-versions.ts` | `+ export const RENDERER_PIN_VERSION = '2.1.0-alpha.2'`, so a half-applied `bun add` fails a test instead of shipping. |
| site | `site/test/renderer-pin.test.ts` | Three assertions added to the existing `describe('renderer pin')` (`:16-34`); they need no wasm, so they sit **outside** the `skipIf(skip)` guard at `:21`. |
| site | `site/src/scripts/circ-editor.ts` | `+ export const setLinkHighlight = StateEffect.define<{ from: number; to: number } \| null>()` and `+ linkHighlightField`, added to the **shared** extension array every `EditorState.create` uses (`DOCS/PLANS/PHASE_2_file_tabs.md:220`); `+ EditorHandle.setLinkHighlight(span)`, re-applied by `showDocument(index)` (`PHASE_2_file_tabs.md:233`) because the decoration lives in the state being swapped away; `+ an onCursor?(index, line1, col1, lineText)` option on `createEditor`, dispatched from `EditorView.updateListener` when `update.selectionSet`. Nothing playground-specific: Phase 7's `<LiveEditor>` mounts the same module (decision 15). This file, not the island, because `PHASE_1_editor.md:46` makes it "the only file in the tree that imports `@codemirror/*` … never imported statically by anything — only through `import()`". |
| site | `site/src/components/Playground.astro` | Build the link table inside `buildSim()` (`:359-416`) from `view.view.getLayout()`; pass `onHover` alongside `onPinToggle` (`:369-380`); clear it in `hooks.onArtifact`'s null branch (`:421-431`); cursor listener on the Phase 1 editor; `data-symbol-*` + handlers on the truth-table `<th>`s (`:250-256`); handlers on the diagnostics buttons (`:299-316`); reuse `rootFileId` from `source-link.ts` in `rootInputBits()` (`:229-230`). |
| site | `site/src/utils/circ-theme.mjs` | A `hovered` branch in `drawOutputPin` (`:273`), `drawLed` (`:308`), `drawNot` (`:350`), `drawAnd` (`:403`), `drawSubcircuit` (`:465`) — the five entries of the `skins` object at `:578-585` that lack one; `drawInputPin` (`:238`, branch at `:254-257`) is untouched. **Shared module, not playground-scoped:** `LiveCanvas.astro:42,46` imports it and `/` (`src/pages/index.astro:41`) and `/examples` (`src/pages/examples.astro:30`) both render `<LiveCanvas>`, so the ring appears on pointer hover there too. That is intended — hover feedback should be uniform across the site — but it must be *checked* on those two pages, not only in the playground. This is the `.lc-mount` cross-page trap reached through the theme module instead of the stylesheet. |
| site | `site/src/styles/global.css` | `.cm-circ-linked` inside the `.pg*` block (`:528-656`), and a focus/hover rule plus the cursor-driven `.pg-th-linked` rule on `.pg-table th[data-symbol-name]` beside `:653`. Nothing outside that block; `.lc-mount` (`:477-525`) is shared with `/` and `/examples` and stays untouched. |
| repo | `DOCS/PLANS_PROMPT.md` | Slice 1 deletes the resolved `TODO(phase5)` entry from *Open items* (`:192`), per the rule at `:186`, once the signature answer is in that slice's STATUS entry. Nothing else in that file is edited. |
| repo | `DOCS/decisions/playground.md` | Two `###` entries (decision 4's renderer surface, decision 5's name join), per the plan prompt's Locked-decisions preamble. |
| repo | `DOCS/STATUS.md` | One entry per slice, per the Working Loop. |

**New dependencies:** None. No package is added to `site/package.json`; the `circ-renderer` line is re-pinned, not added.

## Data & State

### 1. The `circ-renderer` addition (slice 1)

```ts
// src/render/canvas.ts
export interface RenderOptions<C extends string = ThemeColorKey> {
  cell?: number;
  theme?: CircTheme<C>;
  layoutOptions?: LayoutOptions;
  padding?: number;
  interactive?: boolean;
  onPinToggle?: (id: number, signal: Signal) => void;
  /**
   * Called when the pointer moves onto a different component box, and with
   * `null` when it leaves the canvas. Fires only on a change, so a host can
   * drive an editor highlight straight from it. Ids are layout ids: a
   * collapsed subcircuit box carries a synthetic id that does not exist in
   * `runtime.topology.components` (see `getLayout`).
   */
  onHover?: (id: number | null) => void;
}

export class CircCanvas<C extends string = ThemeColorKey> {
  private hoverId: number | null = null;
  /** Host-driven highlight, kept apart from `hoverId` so the canvas's own
   *  pointer bookkeeping can never clobber it. */
  private highlightId: number | null = null;

  /** The grid this canvas drew. Live and read-only by contract — the host
   *  needs it to map a declared name to a box, which the topology alone
   *  cannot do for collapsed subcircuits (`src/layout/collapse.ts:113-118`). */
  getLayout(): LayoutGrid { return this.layout; }

  /** Highlight one component from the host (an editor cursor, a table header).
   *  Feeds the same `SkinContext.hovered` flag the pointer does; `null` clears.
   *  An id with no box is a no-op. */
  setHighlight(id: number | null): void {
    if (id === this.highlightId) return;
    this.highlightId = id;
    this.draw();
  }

  /** Single funnel for hover changes: keeps the cursor, the redraw and the
   *  callback in one place and makes `pointerleave` idempotent. */
  private setHover(id: number | null): void {
    if (id === this.hoverId) return;
    this.hoverId = id;
    this.canvas.style.cursor = id !== null && this.isToggleable(id) ? "pointer" : "default";
    this.draw();
    this.options.onHover?.(id);
  }
}
```

`attach()` (`canvas.ts:171-200`) becomes `onMove = (e) => this.setHover(this.componentAtEvent(e))` and `onLeave = () => this.setHover(null)`; the click handler at `:185-191` is untouched. The one line at `canvas.ts:292` becomes:

```ts
hovered: this.hoverId === comp.id || this.highlightId === comp.id,
```

`SkinContext.hovered` (`src/utils/theme.ts:79`) keeps its type and its name; no `highlighted` field is added, and the package's own `src/render/skins.ts` — where no skin reads `hovered` — is not touched.

### 2. `site/src/scripts/source-link.ts` (slice 4)

This module imports **types only, from one place**, and values from nothing.

```ts
/** The analyze contract has exactly one definition, and Phase 1 owns it:
 *  `AnalyzeRange` (PHASE_1_editor.md:285), `AnalyzeSymbol` with `kind` as the
 *  eight-member union (:297-304) and `Analysis` (:311-316). Re-declaring them
 *  here would fork it and lose the compiler's help on `rootDeclarations`.
 *  There is no bundle reason to fork: circ-diagnostics.ts is pure and DOM-free
 *  (PHASE_1_editor.md:354), already in the playground's eager graph, and an
 *  `import type` is erased anyway.
 *
 *  Range convention, restated once so no reader has to chase it: 1-based line,
 *  1-based BYTE column, END EXCLUSIVE. The contract is DOCS/analyze-api.md:60-70,
 *  which states the 1-based line and byte column but is silent on exclusivity;
 *  exclusivity is proven by tests/fixtures/expected-analyze/clean.json, where
 *  the symbol `a` of `input a` is {start_line:1,start_col:7,end_line:1,end_col:8}
 *  and `a` is the 7th byte of a 7-byte line — the same proof PHASE_1_editor.md:281-284
 *  cites. */
import type { AnalyzeRange, AnalyzeSymbol, Analysis } from './circ-diagnostics.ts';

/** Kinds `--analyze` emits for a declaration (DOCS/analyze-api.md:57;
 *  `symbolKind`, lib/analyze/analyze.zig:263-273). `wire`, `slice` and
 *  `concat` are deliberately absent — they are not symbols. Derived, never
 *  restated, so it cannot drift from Phase 1's union. */
export type SymbolKind = AnalyzeSymbol['kind'];
type AnalyzeFile = Analysis['files'][number];

/** Structural subset of `PlacedComponent` (circ-renderer src/layout/types.ts:73-91).
 *  Declared here, not imported, so this module never pulls `circ-renderer`
 *  into the playground's EAGER bundle (decision 14). */
export interface PlacedLike {
  id: number;
  name: string;
  origin: readonly unknown[];
  kind: { tag: 'primitive'; kind: number } | { tag: 'subcircuit'; subcircuit: string };
}
export interface LayoutLike { components: readonly PlacedLike[] }

/** Topology kind byte per symbol kind (circ-renderer src/wasm/topology.ts:27-39).
 *  Hard-coded for the same reason `Playground.astro:349` hard-codes
 *  `INPUT_PIN = 0`; `source-link.test.ts` asserts it equals `ComponentKind`. */
const TOPOLOGY_KIND_OF: Record<SymbolKind, number | 'subcircuit'> = {
  input: 0, not: 1, and: 2, led: 4, output: 5, rom: 8, ram: 9,
  instance: 'subcircuit',
};

/** A root-file declaration the host can navigate to. */
export interface Declaration {
  name: string; kind: SymbolKind; fileId: number; range: AnalyzeRange;
}
/** A declaration joined to the box that draws it. **Carries no `range`.**
 *  Ranges come from the CURRENT `link.decls` at use time, because decision 9
 *  (DOCS/PLANS_PROMPT.md:50) keeps the last good canvas — and therefore this
 *  table — on screen, dimmed, across an unbounded number of failing edits,
 *  while the 120 ms analyze stage keeps refreshing `link.decls`. A snapshot
 *  range would mark whatever text had since moved into those columns. */
export interface SourceLink {
  name: string; kind: SymbolKind; fileId: number; componentId: number;
}

export interface LinkTable {
  byComponentId: Map<number, SourceLink>;
  byName: Map<string, SourceLink>;
  /** Root declarations with no box: an `instance` under `expandMacros`,
   *  or a declaration the compiler dropped. Empty for every committed example. */
  unlinked: Declaration[];
}

/** `file_id` of `rootPath` in `analyze.files`, or `null`. Replaces the inline
 *  lookup at `Playground.astro:229-230`, which defaulted to `?? 0`. When
 *  `rootInputBits()` is re-pointed at this, a `null` must map back to `null`,
 *  NOT to `0`: the cap pre-flight at `:237` is `bits !== null && bits > CAP`,
 *  so a 0 would silently stop guarding, and decision 13 calls that pre-flight
 *  "the only real defence" against an unstoppable enumeration — `LibcircClient`
 *  has no abort and no timeout (`DOCS/PLANS_PROMPT.md:158`). */
export function rootFileId(files: readonly AnalyzeFile[], rootPath: string): number | null;

/** Symbols of the root file only, in analyze order, with a known kind and a
 *  non-empty name (an anonymous instance has neither — analyze.zig:341). */
export function rootDeclarations(
  symbols: readonly AnalyzeSymbol[], rootId: number | null,
): Declaration[];

/** `rootDeclarations(analysis.symbols, rootFileId(analysis.files, rootPath))`,
 *  and `[]` for a null analysis. The EXACT call the island makes on every
 *  successful analyze, exported so slice 5's rebuild has a `bun test` proof:
 *  the island's `__playground` handle (`Playground.astro:117`) is a DOM
 *  property assigned at browser runtime and `bun test` cannot import an
 *  `.astro` file (decision 15, DOCS/PLANS_PROMPT.md:56). */
export function declsFor(analysis: Analysis | null, rootPath: string): Declaration[];

/** Join on (name, kind). Boxes must have `origin.length === 0` — the rule
 *  `Playground.astro:354` already uses. First declaration wins on a duplicate
 *  name (E005 makes that a broken source, not a normal one). */
export function linkLayout(
  decls: readonly Declaration[], layout: LayoutLike,
): LinkTable;

/** The declaration under a cursor. `col` is a 1-based UTF-16 column and
 *  `lineText` the editor's text for that line: symbol byte columns are
 *  converted with `byteColToUtf16` (site/src/utils/columns.ts:6-17) before the
 *  half-open containment test. Falls back to the leftmost declaration starting
 *  on the line when no column matches, so a cursor on the `input ` keyword of
 *  `input a, b` still resolves (those two carry per-name spans —
 *  lib/ir/resolver.zig:334 — while every other kind spans its whole
 *  declaration: resolver.zig:144 for components and :363 for outputs, the two
 *  spans analyze actually reads at analyze.zig:339-352 and :330-337. The
 *  shapes are pinned by tests/fixtures/expected-analyze/clean.json, where
 *  `input a` gives `a` {1,7,1,8} but `and g(...)` gives {3,1,3,16} and
 *  `output out(...)` gives {4,1,4,21}.) */
export function declarationAt(
  decls: readonly Declaration[], line: number, col: number, lineText: string,
): Declaration | null;

/** Truth-table headers are `name` or `name[W]` for width > 1
 *  (lib/truth_table/json.zig:31). Strip the suffix to get the join key. */
export function headerSymbolName(header: string): string;
```

### 3. The editor highlight (slice 6), against `@codemirror/state` 6.7.4 and `@codemirror/view` 6.43.11

Every name below was read from the installed `.d.ts` under the locked package set, so none of it is provisional: `StateEffect.define` (`state/dist/index.d.ts:836`), `StateField.define` with `provide` (`:661`, `:636`), `Facet.from(field)` (`:592`), `EditorView.decorations` (`view/dist/index.d.ts:1322`), `Decoration.mark` (`:331`) with its `class` shorthand (`:86`), `Decoration.set` (`:352`), `Decoration.none` (`:356`), `EditorView.scrollIntoView(pos, { y })` (`:1130`), `EditorView.updateListener` (`:1275`), `ViewUpdate.selectionSet` (`:601`), `Text.line(n) → Line { from, to, number, text }` (`state:47`, `:119-141`).

```ts
// site/src/scripts/circ-editor.ts — Phase 1's module owns the EditorView and is
// the only file that may import @codemirror/* (PHASE_1_editor.md:46). NOT the
// island: Playground.astro's <script> is /playground's EAGER bundle, so a static
// `import { StateEffect, StateField } from '@codemirror/state'` there would drag
// CodeMirror in front of first interaction and break both decision 14's 120 KB
// gzip ceiling (PLANS_PROMPT.md:55) and "Nothing heavy loads before interaction"
// (:32) — the very reason Phase 1 routes the editor through a dynamic import()
// (decision 15, :56). Decision 15 also forbids bun-test-reachable behaviour
// living in an .astro island. One field, one effect, no plugin. The field joins
// the SHARED extension array every EditorState.create uses
// (PHASE_2_file_tabs.md:220); the island reaches it only through EditorHandle.
export const setLinkHighlight = StateEffect.define<{ from: number; to: number } | null>();

const linkHighlightField = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(deco, tr) {
    deco = deco.map(tr.changes);
    for (const e of tr.effects) {
      if (!e.is(setLinkHighlight)) continue;
      deco = e.value === null
        ? Decoration.none
        : Decoration.set([Decoration.mark({ class: 'cm-circ-linked' }).range(e.value.from, e.value.to)]);
    }
    return deco;
  },
  provide: (f) => EditorView.decorations.from(f),
});
```

Because Phase 2 swaps a whole `EditorState` per tab (`PHASE_2_file_tabs.md:18`), the decoration is lost with the state that is swapped away — so `showDocument(index)` (`:233`) re-applies the current span after the swap.

### 4. The island's link state (slices 5-7)

```ts
const link = {
  /** Root declarations from the latest successful analyze. Present with or
   *  without a canvas — the truth-table and diagnostics sources need only this.
   *  This is also the ONLY place ranges are read from, at use time. */
  decls: [] as Declaration[],
  /** Present only while a Simulate canvas exists; rebuilt with it. */
  table: null as LinkTable | null,
  /** What is highlighted, by NAME — canvas-instance-independent, so it can be
   *  replayed onto a rebuilt canvas exactly as pins are (Playground.astro:385-398). */
  current: null as { name: string; kind: SymbolKind } | null,
  /** PER-CANVAS cache of the last id pushed, to skip redundant dispatches.
   *  Reset to null with the canvas: a fresh CircCanvas starts at
   *  `highlightId = null`, so a surviving `pinned` would make the redundancy
   *  guard swallow the re-application. */
  pinned: null as number | null,
};
```

## Execution & Concurrency Model

This phase is fully synchronous and event-driven. **No worker, no timer, no debounce and no background task is introduced**, and Phase 3's `ANALYZE_DEBOUNCE_MS` / `BUILD_DEBOUNCE_MS` and their per-stage sequence counters are neither touched nor extended.

Three details bound the concurrency that already exists:

1. **The link table is built where the canvas is built, and replayed by name when the canvas is rebuilt.** `buildSim()` (`Playground.astro:359-416`) already awaits two dynamic `import()`s and re-checks `if (sim.bytes !== bytes) return;` at `:363` before touching the DOM. `link.table = linkLayout(link.decls, view.view.getLayout())` goes after that guard, so a table can never outlive the artifact it was computed from. `buildSim()` **then resets `link.pinned = null` and, if `link.current` is set, re-resolves it through the new `link.table.byName` and calls `view.view.setHighlight(id)` on the fresh instance.** The canvas is destroyed and reconstructed on every theme flip (`:452-455` → `rebuildSim()` → `buildSim()`, `sim.view?.destroy()` at `:365`, fresh `CircCanvas` at `:369`) and on every artifact-hash change (`:433-436`, `:442-444`); `highlightId` does not survive that, and a stale `link.pinned` would make the redundancy guard skip the re-application, so the highlight would silently vanish until the cursor moved to a *different* declaration. This is the same replay-by-name the pin map already does at `:385-398`, for the same reason. `hooks.onArtifact(null)` (`:421-431`) clears `link.table`, `link.pinned` and `link.current`.

   **Ranges are resolved at use time, never snapshotted.** Canvas → editor resolves `onHover(id)` to a `SourceLink` (name + kind + fileId + componentId), then re-looks-up `(name, kind)` in the **live** `link.decls` for the range; if that name is no longer declared, the mark is cleared instead of placed. Decision 9 (`DOCS/PLANS_PROMPT.md:50`) keeps the last good canvas on screen, dimmed, across arbitrarily many failing edits while `link.decls` keeps refreshing, so a dimmed stale canvas would otherwise mark whatever text had moved into the old columns.

   **Both highlight directions convert a `Declaration.range` to `{ from, to }` through `rangeToSpan` from Phase 1's `site/src/scripts/circ-diagnostics.ts`, called as `rangeToSpan(indexOf(tabIndex), [{ name: files[tabIndex].name, body: files[tabIndex].body, startLine: 0 }], state.analysis, decl.fileId, decl.range)`** — Phase 1's exact signature (`PHASE_1_editor.md:397-400`), fed the per-tab `DocIndex` Phase 2 already recomputes on `setBody` (`PHASE_2_file_tabs.md:50`) and the live `state.analysis`, so the line is `range.start_line` verbatim and the column conversion stays inside `circ-diagnostics.ts`. A `null` return clears the mark instead of placing one. `source-link.ts` never computes document offsets and the island never re-implements `byteColToUtf16` — that is exactly where the byte-vs-UTF-16 trap bites, and decision 15 forbids test-reachable behaviour living in the island.
2. **The artifact bytes get no second consumer.** `compile` transfers `bytes.buffer` (`libcirc.worker.ts:63-65`) and `Playground.astro` keeps exactly one reference. Reading the layout through `getLayout()` instead of re-running `decodeFullTopology` + `buildLayout` over `state.artifact.bytes` is why the accessor is required rather than merely convenient (decision 4), and it is also what keeps this phase clear of the detach trap. `source-link.test.ts` may decode a committed `.wasm` from disk freely — that path owns its own bytes.
3. **Hover fires only on change.** `setHover` early-returns when the id is unchanged, so a pointer sweeping inside one box produces zero callbacks and zero redraws (this also removes the unconditional redraw `pointerleave` performs today at `canvas.ts:180-184`). Each surviving event costs one `Map.get` and one `EditorView.dispatch` with a single effect. `setHighlight` early-returns the same way, so an editor cursor moving within one declaration does not redraw the canvas.

Ownership of shared state: the island owns `link`; the canvas owns `highlightId`; the editor's `StateField` owns the decoration. Nothing is shared across threads, so nothing needs guarding.

Two interaction rules, decided here so no slice reopens them:

- **Hover never scrolls the editor.** A pointer moving over the canvas may not yank the editor's viewport. `EditorView.scrollIntoView` is dispatched only when the highlight comes from a keyboard/click activation — a diagnostics row, a focused table header.
- **A canvas hover never changes the active tab.** Every box the canvas draws in the default (opaque) mode has `origin.length === 0` (`collapse.ts:92-97`, `:181-193`), so its declaration is always in the **root** file — the last file (`rootOf`, `split-files.ts:34`). Under Phase 2's locked model a tab switch is an `EditorView.setState` (`PHASE_2_file_tabs.md:18`), which replaces the whole visible buffer; idempotence would stop the switch *repeating*, but not the *first* one. So a reader typing in `half_adder.circ` who merely sweeps the pointer across the canvas on the way to the splitter would lose their buffer with no click and no keypress — and since this phase adds no click path on canvas boxes, hover is the only canvas→editor direction, which makes the theft unavoidable rather than justified. Therefore: when the hovered declaration is not in the active file, the highlight is **announced** in `.pg-sim-note` (markup at `Playground.astro:61`, handle at `:98` — the element that already carries "Click input pins to toggle them.") as `<file>:<line> <name>`, and no `setState` is dispatched. A tab switch — `showDocument(index)` (`PHASE_2_file_tabs.md:233`) followed by re-applying the mark and `scrollIntoView` — happens only from a keyboard/click activation: a diagnostics row, or a focused table header.

## Persistence & I/O

This phase adds no persistence and no network I/O. Nothing is written to `localStorage`: the highlight is ephemeral and the `circ.playground.v1` envelope (decision 7) is neither read nor written here, and its `version` stays 1.

Three I/O facts that do apply:

- **A second git repository is written, and slice 1 therefore produces two commits.** It is the one slice that touches both repos, and the order matters: (1) in `/Users/jeffersonmourak/circus/circ-renderer` on branch `host-pin-api`, staged by path, the renderer change plus `test/canvas-stub.ts`, `test/canvas.test.ts` and `test/fixtures/half_adder.wasm` (the single bounded exception in the plan prompt's Git Rules — no push, no PR); (2) in **this** repo, `DOCS/STATUS.md` alone, as a `docs:` commit whose entry's *Files touched* names **only** the `circ-renderer` paths. That second commit is not bookkeeping: without it the slice ends with an uncommitted `DOCS/STATUS.md` in the worktree, and the next session's cold-start check (`DOCS/PLANS_PROMPT.md:91` — "STATUS claims a slice that `git log` does not show") fires on a slice that actually landed. Naming only `circ-renderer` paths in *Files touched* is what puts the entry inside that step's own exception. Only then does the slice print `git -C /Users/jeffersonmourak/circus/circ-renderer push origin host-pin-api` and stop.
- **`bun add` reaches the network once.** Slice 2's `bun add circ-renderer@github:jeffersonmourak/circ-renderer#<sha>` resolves from GitHub — a local commit is invisible to it, which is exactly why slice 1's stop is hard. It rewrites `site/package.json:17` and `site/bun.lock` (`:8`, `:272`), and re-installs `site/node_modules/circ-renderer`.
- **Tests read committed files.** `source-link.test.ts` reads `site/public/wasm/half-adder.wasm` (and `full-adder.wasm`) from disk, `circ-theme-hover.test.ts` reads `site/src/utils/circ-theme.mjs` as text, `renderer-pin.test.ts` reads `site/node_modules/circ-renderer/package.json`, and in the renderer repo `canvas.test.ts` reads the new `test/fixtures/half_adder.wasm`. No test writes anything.

No compiler artifact is regenerated: this phase touches no Zig, so `libcirc.wasm`, `libcirc.manifest.json` and the 11 committed example `.wasm` files are byte-identical before and after it, and `bun run scripts/compile-content.ts` is not run (which also means the 7 untracked `tour-<N>.wasm` files never appear).

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each. Every slice also appends its `DOCS/STATUS.md` entry per the Working Loop template; that is not repeated in the table.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Host hover and highlight hooks on `circ-renderer` | In `/Users/jeffersonmourak/circus/circ-renderer` on `host-pin-api`: `RenderOptions.onHover`, `private highlightId`, `private setHover`, `setHighlight(id)`, `getLayout()`, the `hovered` OR at `canvas.ts:292`; `test/canvas-stub.ts` + `test/canvas.test.ts` + **`test/fixtures/half_adder.wasm`** (a byte-for-byte copy of this repo's `site/public/wasm/half-adder.wasm` — the repo's eight existing fixtures all decode to `origin = []`, so none can produce the subcircuit node `getLayout`'s test needs; copy it **before** writing the test, not after discovering the gap mid-slice); `package.json` → `2.1.0-alpha.2`; three README edits. Committed on that branch, **not pushed**. *Files touched* in the STATUS entry names those `circ-renderer` paths **and nothing else**, and the entry lands as its own `docs:` commit in this repo (see **Persistence & I/O**). The signature spike runs first, inside this slice: draft the site-side join in the scratchpad against this local checkout and let it choose between a bare id and a `PlacedComponent` payload (see Open Questions), and deletes `DOCS/PLANS_PROMPT.md:192`'s `TODO(phase5)` entry from *Open items*, recording the answer (`onHover(id: number | null)` plus `getLayout(): LayoutGrid`) verbatim in the STATUS entry, as the rule at `DOCS/PLANS_PROMPT.md:186` requires. Ends by printing the human's push command and **stopping**. | `bun test` and `bun run typecheck`, both run in `/Users/jeffersonmourak/circus/circ-renderer`: `canvas.test.ts` asserts `hovered` is true for exactly the highlighted id, that `getLayout().components` matches `buildLayout(rt.topology)`, and that `onHover` fires once per change and not at all for a repeat. The site is still on the old pin, so `cd site && bun test` and `bun --bun run build` also stay green, unchanged. |
| 2 | Bump the pin to the pushed sha | After the human confirms the push and names `<sha>`: `bun add circ-renderer@github:jeffersonmourak/circ-renderer#<sha>` in `site/`; `RENDERER_PIN_VERSION` in `site/src/utils/renderer-versions.ts`; three assertions added to `site/test/renderer-pin.test.ts`, outside its `skipIf(skip)` guard. | `cd site && bun test` — `renderer pin` gains *the pinned package is the version this site expects* (reads `node_modules/circ-renderer/package.json`), *the pinned canvas exposes the host highlight API* (`typeof CircCanvas.prototype.setHighlight === 'function'` and `typeof CircCanvas.prototype.getLayout === 'function'`), and *the pinned canvas declares onHover* (the only runtime-invisible half of the addition, so it is asserted against the pinned `src/render/canvas.ts` text). Plus `bun --bun run build` and `bun run bundle`. |
| 3 | Make the highlight visible for every skin the site draws | A `hovered` branch in `drawOutputPin` (`:273`), `drawLed` (`:308`), `drawNot` (`:350`), `drawAnd` (`:403`) and `drawSubcircuit` (`:465`) in `site/src/utils/circ-theme.mjs`, drawn as a rounded-rect ring in `theme.colors.inputHover` (`:74` light, `:109` dark) around the component's cell box — a ring rather than a fill because **three** of the five (`drawNot` `:377`, `drawAnd` `:431`, `drawSubcircuit` `:498`) draw untintable PNG sprites through `drawSprite` (`:210-217`), and one ring keeps the highlight identical across all five rather than splitting into a fill for `drawOutputPin` / `drawLed` (which are vector, `drawPinCircle` `:173` and `ctx.arc`) and a ring for the rest. `drawInputPin` (`:238`, branch at `:254`) is untouched. **This slice is third, not last, because decision 4 (`DOCS/PLANS_PROMPT.md:42`) binds it to `setHighlight`**: without it every later slice's only browser-visible proof — a cursor on `and c(...)`, a hovered AND box, a focused table header — is dead. Its STATUS entry records the `rom`/`ram` no-op (see **Scope**) as known, not discovered. | `cd site && bun test` — the new `site/test/circ-theme-hover.test.ts`, a source-text guard asserting all six entries of the `skins` object (`:578-585`) destructure `hovered` and reference `theme.colors.inputHover` (`circ-theme.mjs` cannot be imported under `bun test`: `:29` calls `loadAssets()` at module scope, which needs `new Image()` — `site/src/utils/circ-assets.mjs:28`). `bun --bun run build`, `bun run bundle`. In-browser: the ring reads clearly in light and dark on an AND, a LED and a macro box, **in the playground and on `/` and `/examples`** — the module is shared with `<LiveCanvas>` — **manual, unrun**. |
| 4 | The name join as a pure module | `site/src/scripts/source-link.ts` with `rootFileId`, `rootDeclarations`, `declsFor`, `linkLayout`, `declarationAt`, `headerSymbolName` and the `TOPOLOGY_KIND_OF` table — `declsFor` ships with the pure module here and its cases land in slice 5, the slice that wires it and that has no other `bun test` reach; `site/test/source-link.test.ts`. Nothing is wired to the DOM yet. Also appends the two `###` entries to `DOCS/decisions/playground.md`. | `cd site && bun test` — the headless `buildLayout(decodeFullTopology(section))` path over the committed `half-adder.wasm` and `full-adder.wasm`, asserting every root declaration resolves to a box with `origin.length === 0`, `unlinked` is empty, `<builtin>/…` symbols are excluded rather than resolved, and (through the committed `libcirc.wasm`, `skipIf(skip)`) that tour step 6's sibling `half_adder.circ` symbols are excluded too — **plus `declarationAt` over `input a, b`** (a cursor in `a`'s columns, in `b`'s columns, on the `input ` keyword, and after a multi-byte character earlier on the line) **and the five `headerSymbolName` cases**; both functions ship here, so both are proved here rather than leaving this slice with two untested exports. `bun run bundle` is unchanged — the module is not yet imported by any island. |
| 5 | Editor cursor drives the canvas | `Playground.astro` imports `source-link.ts`, builds `link.decls` with `declsFor(state.analysis, rootPath)` after each successful analyze and `link.table` inside `buildSim()` from `view.view.getLayout()`, and adds the `onCursor` callback on `createEditor` (dispatched from `EditorView.updateListener` when `update.selectionSet`) that maps the cursor to a declaration and calls `view.view.setHighlight(id)` (or `null`), recording `link.current`. `buildSim()` resets `link.pinned` and replays `link.current` by name; `hooks.onArtifact(null)` clears `table`, `pinned` and `current`. `rootInputBits()` (`:226-232`) is re-pointed at `rootFileId`, mapping `null` to `null`. | `cd site && bun test` — pure cases in `site/test/source-link.test.ts` only, since `bun test` cannot import an `.astro` island (decision 15, `DOCS/PLANS_PROMPT.md:56`; the `__playground` handle at `Playground.astro:117` is a DOM property assigned inside `init(el)` at browser runtime, and there is no `document` under `bun test`): (a) `declsFor(analysis, rootPath)` — the exact function the island calls on every successful analyze, composing `rootFileId` + `rootDeclarations` — rebuilds exactly the root file's named declarations for a fixed `Analysis`, returns `[]` when `rootFileId` is `null` (the root path names no entry of `analysis.files`), and `[]` for a `null` analysis; (b) `rootFileId(files, rootPath)` returns `null` — never `0` — when the root path is absent, so the value `rootInputBits()` maps back to `null` and the `:237` cap pre-flight still refuses. The island wiring itself (`link.decls` rebuilt per analyze, and `link.table` / `link.pinned` / `link.current` cleared by `hooks.onArtifact(null)`) has no `bun test` reach and is recorded in the manual checklist as **unrun** alongside the cursor→box check. `bun --bun run build`, and `bun run bundle` — `/playground` must stay under its committed raw/gzip ceilings with `source-link.ts` now in the eager graph. In-browser: cursor on `and c(...)` lights that box (visible because slice 3 shipped the ring), and `link.decls` is rebuilt on each analyze and cleared by `hooks.onArtifact(null)` — **manual, recorded in STATUS as unrun**. |
| 6 | Canvas hover drives the editor | In `circ-editor.ts`: the `setLinkHighlight` effect, `linkHighlightField` in the shared extension array, `EditorHandle.setLinkHighlight`, and its re-application inside `showDocument`. In the island: `onHover` passed to `renderCircuit` beside `onPinToggle`, and the handler that maps an id to a `SourceLink`, re-looks-up its range in the live `link.decls` through `rangeToSpan`, marks it, and clears on `null` — announcing `<file>:<line> <name>` in `.pg-sim-note` instead of switching tabs when the declaration is not in the active file. `.cm-circ-linked` added to the `.pg*` block in `global.css`. | `cd site && bun test` (a case asserting the id→declaration direction of `linkLayout` for a collapsed subcircuit box, whose synthetic id is absent from the topology; and one asserting a `SourceLink` whose name is no longer in `link.decls` clears the mark instead of placing one). `bun --bun run build`, `bun run bundle`. In-browser: hovering an AND box lights its declaration line in both themes, and hovering while `half_adder.circ` is the active tab leaves that tab alone and writes the note — **manual, unrun**. |
| 7 | Truth-table headers and diagnostics as highlight sources | `<th>`s gain `data-symbol-name` / `data-symbol-kind` (via `headerSymbolName`) plus `tabindex="0"` and `pointerenter`/`pointerleave`/`focus`/`blur` handlers; the diagnostics buttons gain the same on their own range, reusing the per-tab mapped diagnostics Phase 2 slice 6 leaves in the island — entries tagged with their tab index, offsets file-local (`PHASE_2_file_tabs.md:51,382`), not Phase 1's combined-document `state.mapped`. A hover marks only when the row's tab index is the active tab; a keyboard/click activation is the one path allowed to `showDocument(tabIndex)` first and then mark and `scrollIntoView`. Both sources drive the editor mark and, when `link.table` exists, `setHighlight` — and the cursor direction into the table: an `onCursor`-driven update marks the `<th>` whose `data-symbol-name` equals `link.current.name`, so the DoD's "and vice versa from the cursor" (`DOCS/PLANS_PROMPT.md:9`) holds for the truth-table half as well as for the canvas. Focus/hover styling on `.pg-table th[data-symbol-name]`, plus `.pg-th-linked` for the cursor-driven mark. | `cd site && bun test` — the `skipIf(skip)` integration case *truth-table headers name root declarations*: for a real `truth_table` reply over the half-adder, every entry of `inputs` and `outputs`, passed through `headerSymbolName`, is a key of `byName`; and, for the cursor direction, `headerSymbolName(header) === decl.name` selects exactly one column for each root declaration and none for a sibling-file symbol. (`headerSymbolName`'s own cases landed in slice 4.) `bun --bun run build`, `bun run bundle`. In-browser: tabbing to a column header lights the declaration — **manual, unrun**. |

Slices are ordered by dependency, and by decision 4's requirement that the highlight be *visible* before anything claims to drive it. Each is fully reviewable on its own: 1 lands only in the renderer repo; 2 is the pin and its gates; 3 is presentation only, and needs nothing from 2 but ships after it so the sequence reads in one direction; 4 is a pure module with tests and no UI; 5, 6 and 7 each add one highlight direction or source, and each has a browser-visible proof because 3 already landed.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `setHighlight marks exactly one component as hovered` | `circ-renderer test/canvas.test.ts` | With a stub theme whose skins record `component.id → hovered`, `setHighlight(id)` makes that id the only `hovered: true` entry on the next draw, and `setHighlight(null)` clears it. Uses `interactive: false` so no listeners attach. |
| `setHighlight ignores a repeat and an unknown id` | `circ-renderer test/canvas.test.ts` | A second `setHighlight(sameId)` triggers no redraw (the recorder sees no new frame); an id with no box draws with nothing hovered and does not throw. |
| `getLayout returns the grid the canvas drew` | `circ-renderer test/canvas.test.ts` | Over the **new** `test/fixtures/half_adder.wasm`: `view.getLayout()` deep-equals `buildLayout(rt.topology, {})`, and contains a `{ tag: "subcircuit", subcircuit: "xor" }` node named `"s"` whose id (21) is absent from `rt.topology.components` (max real id 20 — synthetic ids start at `max(id)+1`, `src/layout/collapse.ts:113-118`). None of the eight pre-existing fixtures can carry this assertion: every component in all eight decodes to `origin = []`. |
| `onHover fires only on a change` | `circ-renderer test/canvas.test.ts` | Driving synthetic pointer coordinates through the stub's `dispatchEvent` records one call per distinct box and none for a repeat; leaving after a `null` hover records nothing. Constructed with `interactive: true` (the default) so `attach()` actually runs (`canvas.ts:86`) and the three listeners exist (`:192-194`) — unlike the two `setHighlight` rows, which use `interactive: false`. |
| `the pinned package is the version this site expects` | `site/test/renderer-pin.test.ts` | `node_modules/circ-renderer/package.json`'s `version` equals `RENDERER_PIN_VERSION`. |
| `the pinned canvas exposes the host highlight API` | `site/test/renderer-pin.test.ts` | `typeof CircCanvas.prototype.setHighlight === 'function'` and `typeof CircCanvas.prototype.getLayout === 'function'`. |
| `the pinned canvas declares onHover` | `site/test/renderer-pin.test.ts` | The pinned `src/render/canvas.ts` declares `onHover?:` — the one half of the addition with no runtime witness (the site has no `typecheck` script; `astro build` does not type-check). |
| `the topology kind table matches ComponentKind` | `site/test/source-link.test.ts` | `TOPOLOGY_KIND_OF` equals the `ComponentKind` members imported from `circ-renderer` **in the test**, so hard-coding the bytes in `source-link.ts` (to keep the renderer out of the eager bundle) cannot drift. |
| `rootDeclarations keeps only the root file's named symbols` | `site/test/source-link.test.ts` | Over a hand-written `symbols` array in the `DOCS/analyze-api.md:49-50` shape: sibling and `<builtin>/…` `file_id`s are dropped, an unknown `kind` is dropped, and an empty `name` (an anonymous instance — `analyze.zig:341`) is dropped. |
| `declsFor rebuilds the root file's declarations` | `site/test/source-link.test.ts` | `declsFor(analysis, rootPath)` — the exact composition the island runs on every successful analyze — returns the root file's named declarations for a fixed `Analysis`, `[]` when the root path names no entry of `analysis.files` (`rootFileId` is `null`), and `[]` for a `null` analysis. This is slice 5's only runnable proof: `bun test` cannot import the island (decision 15). |
| `linkLayout joins on name and kind` | `site/test/source-link.test.ts` | An `input a` symbol does not join an `and`-kind box named `a`; an `instance` symbol joins only a `{ tag: 'subcircuit' }` box; a box with `origin.length > 0` is never joined; a duplicate name keeps the first declaration. |
| `declarationAt resolves a column on a shared line` | `site/test/source-link.test.ts` | For `input a, b`, a cursor inside `a`'s columns returns `a` and inside `b`'s returns `b`; a cursor on the `input ` keyword falls back to the leftmost declaration; a multi-byte character earlier on the line does not shift the result (the `byteColToUtf16` boundary, `columns.ts:6-17`). |
| `headerSymbolName strips the width suffix` | `site/test/source-link.test.ts` | `'a' → 'a'`, `'a[4]' → 'a'`, `'sum' → 'sum'`, `'r[64]' → 'r'`, and a name that merely contains a digit is untouched (`lib/truth_table/json.zig:31`). |
| `every playground skin branches on hovered` | `site/test/circ-theme-hover.test.ts` | The six functions named by the `skins` object in `site/src/utils/circ-theme.mjs` (`:578-585`) each destructure `hovered` and reference the hover colour — a source-text guard, because the module cannot be imported headlessly. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `every root symbol of the half-adder resolves to a box` | `site/test/source-link.test.ts` — committed `half-adder.wasm` + committed `libcirc.wasm` (`skipIf(skip)`) | `callOp(w, 'analyze', …)` for the half-adder source, `WebAssembly.compile` → `customSections(mod, 'circ.topology.v0.full')[0]` → `decodeFullTopology` → `buildLayout` (the sequence `renderer-pin.test.ts:25-28` uses), then `linkLayout`: `a`, `b`, `s`, `c`, `sum` and `carry` all resolve, `unlinked` is empty, and `s` resolves to a `{ tag: 'subcircuit', subcircuit: 'xor' }` box. |
| `builtin-file symbols are excluded, not resolved` | same | The `<builtin>/xor.circ` file contributes symbols named `a` and `b` that collide with the root's; `byName.get('a')!.fileId` is the root's `file_id`, and no link's `fileId` is a builtin's. |
| `a sibling file's symbols are excluded` | `site/test/source-link.test.ts` — tour step 6 compiled at test time (`skipIf(skip)`) | Over `splitFiles(tour[5].source)` (`half_adder.circ` + `root.circ`): every `root.circ` symbol resolves — `a`, `b`, `cin`, `ha1`, `ha2`, `cout_or`, `sum`, `cout`, with `ha1`/`ha2` on `{ tag: 'subcircuit', subcircuit: 'half_adder' }` boxes and `cout_or` on `{ subcircuit: 'or' }` — `unlinked` is empty, and **no entry of `byName` or `byComponentId` carries a `fileId` other than the root's**. The last clause is how the exclusion is stated: `byName` is keyed by bare name, and the sibling declares `a`, `b` and `sum` too (`site/src/content/tour.ts:131,134` vs `:139,143`), so those keys are always present — sourced from the root. Asserting their *absence* would fail a correct implementation. |
| `the full-adder's five instances and gates all resolve` | `site/test/source-link.test.ts` — committed `full-adder.wasm` | The wider shape: three `instance` symbols (`s1`, `s2`, `c3`) join subcircuit boxes with synthetic ids, two `and` symbols join primitives, `unlinked` is empty. |
| `truth-table headers name root declarations` | `site/test/source-link.test.ts` (`skipIf(skip)`) | For a real `truth_table` reply over the half-adder, every entry of `inputs` and `outputs`, passed through `headerSymbolName`, is a key of `byName`, and for each root declaration exactly one header satisfies `headerSymbolName(header) === decl.name` — the selector the cursor→header direction uses — while no header selects a sibling-file symbol. |

Run command (slice 1 only, in the renderer repo):

```sh
cd /Users/jeffersonmourak/circus/circ-renderer && bun test && bun run typecheck
```

Run command (every slice, in this repo):

```sh
cd /Users/jeffersonmourak/circus/worktrees/v0.0.3/playground/site && bun test && bun --bun run build && bun run bundle
```

`SKIP_LIBCIRC_TEST=1` is never used to make a slice pass; a green run under it proves nothing about the four `skipIf(skip)` cases above.

## Open Questions / Spikes

- **`TODO(phase5)`: should `onHover` emit a `PlacedComponent` or a bare id plus a layout accessor?** — carried from `DOCS/PLANS_PROMPT.md`'s Open items. **Recommendation: a bare `id: number | null`, plus `getLayout(): LayoutGrid`.** Four things in the code argue for it. (1) The reverse direction is already id-shaped and cannot be anything else — `setHighlight(id)` mirrors `setInputSignal(id, signal)` (`canvas.ts:208-213`) and `onPinToggle(id, signal)` (`:38`), the shape decision 4 asks this change to copy. (2) The host must read the layout anyway, and not only on a pointer event: the editor-cursor direction, the truth-table headers and the diagnostics rows all need a name→id table built once per artifact, with no `PointerEvent` in sight. (3) Given the accessor exists, a `PlacedComponent` in the callback is redundant payload handed out at pointer rate, and it leaks a live entry of the canvas's own `layout.components` array on every move rather than at one documented boundary. (4) The accessor is required regardless of the callback's shape, because a collapsed subcircuit box's synthetic id (`src/layout/collapse.ts:113-118`) exists in no `runtime.topology.components`. **Spike that confirms it, run inside slice 1 before the renderer is committed:** draft `source-link.ts` and its half-adder test in the scratchpad, importing `buildLayout` and `decodeFullTopology` from the *local* `/Users/jeffersonmourak/circus/circ-renderer` checkout, and check that the consumer needs nothing from a hover event beyond the id. If the draft turns out to want geometry (a tooltip anchored to the box, say), widen `onHover` to `(id, component)` **in the same commit** — the point of running the spike before the push is that the signature is locked once and the pin is bumped once. Slice 1 records this in STATUS and deletes the entry from `DOCS/PLANS_PROMPT.md`'s Open items (`:192`), per the rule at `:186`.
- **RESOLVED — the accessor is `getLayout()`, a method. No spike.** A `get layout()` accessor is a duplicate identifier against the existing `private layout: LayoutGrid` (`canvas.ts:46`) and can never pass `bun run typecheck` (`tsc --noEmit`, `circ-renderer package.json:14`); renaming the field to free the name churns the **twelve** `this.layout` references at `canvas.ts:74,81,101,102,141,142,158,159,216,228,229,236` for no behavioural gain, in a slice whose value is five lines. `getLayout()` is final, and Scope, the Modified-files table, §1, the test rows and slices 5-6 already code against it — the pin is bumped exactly once, so this is the one name the phase cannot leave conditional.
- **RESOLVED — `TODO(phase5)`: per-file `EditorState`, not a combined document. No spike.** `DOCS/PLANS/PHASE_2_file_tabs.md` exists in this tree (438 lines) and decides it: `:18` and `:201` lock "one `EditorState` per file, swapped with `EditorView.setState`", argued at `:215-220` (undo history is a `StateField` — `historyField`, `@codemirror/commands/dist/index.d.ts:110` — so state-per-file *is* per-file undo by construction), with the registry surface including `showDocument(index)` at `:229-238` (`:233`), and Phase 2's own slice 3 (`PHASE_2_file_tabs.md:333`) mapping diagnostics per file at `startLine = 0`. Consequences, so no slice re-litigates the seam: the editor line for a declaration is **`range.start_line` verbatim** — the `SplitFile.startLine` offset (`split-files.ts:10-11`, the mapping `Playground.astro:286` performs today) is *not* added, and the combined-document branch never appears; a cross-file jump switches tabs with `EditorHandle.showDocument(index)` **before** dispatching the mark, because the effect applies to one state only, and `showDocument` re-applies the current span for the same reason. Slice 5 opens by confirming the shipped `site/src/scripts/circ-editor.ts` matches that model and records the confirmation in STATUS; if it does not, stop rather than adapt. Either way `source-link.ts` stays pure over file-local 1-based lines, and `declarationAt` and its tests are unaffected.
- Everything else this phase touches is settled. The two interaction rules that could have been left open — hover never scrolls, and hover never switches tabs (it announces the cross-file declaration in `.pg-sim-note` instead; every opaque-mode box has `origin.length === 0`, so its declaration is always in the root file, and under Phase 2's `setState` model the first switch would take a reader's sibling buffer away for a stray pointer move) — are decided in **Execution & Concurrency Model** above and need no spike.
