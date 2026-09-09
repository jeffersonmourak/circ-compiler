# Phase 7 — Live editors in the docs

> **Dependencies:** Phases 0–6 must all be shipped (`DOCS/PLANS_PROMPT.md:71`, "Each phase must be fully shippable before the next begins"). Three are hard functional dependencies: **Phase 0** (`DOCS/PLANS/PHASE_0_builtins_and_budget.md`) for the usage-aware builtin fast path — without it a reader who deletes `import xor "<builtin>/xor.circ"` from tour step 5 (`site/src/content/tour.ts:101`, invited by the prose at `:98`) gets `E001` from a circuit that previews fine — and for `site/scripts/check-bundle.ts` + `site/bundle-budget.json` + `site/test/bundle-graph.test.ts`, which this phase's ceilings are written against; **Phase 1** (`DOCS/PLANS/PHASE_1_editor.md`) for `site/src/scripts/circ-editor.ts` and its `createEditor(parent, { doc, onChange, readOnly, compact })` (`DOCS/PLANS_PROMPT.md:56`); **Phase 4** (`DOCS/PLANS/PHASE_4_workspace_and_share.md`) for `site/src/utils/share-link.ts` and the `#src=` / `#src0=` / `#pick=` fragment contract (decision 6, `DOCS/PLANS_PROMPT.md:47`). **Phase 3** (`DOCS/PLANS/PHASE_3_workbench.md`) is a fourth hard functional dependency: it ships `getSharedClient(wasmUrl)` on `site/src/scripts/libcirc-client.ts` and `site/test/shared-client.test.ts` (`:24,51,63`), and `site/src/scripts/pipeline.ts`'s `Stage` / `ANALYZE_DEBOUNCE_MS` / `BUILD_DEBOUNCE_MS` / `outputsShouldClear` (`:262-296,319,388`) — decision 9's one implementation — which this phase consumes rather than creates. **Phase 5** is a functional dependency for `output="simulate"` only: its canvases run against the bumped `circ-renderer` pin (`DOCS/PLANS/PHASE_5_source_linking.md:337`). Phases 2 and 6 are ordering dependencies only: nothing here reads file tabs or the settings drawer.
>
> **Warnings:** (1) **`.cp-*` is shared with `/`.** `<LiveEditor>` reuses `CodePreview.astro`'s `.cp-panes` / `.cp-pane` / `.cp-pane-label` markup and CSS (`site/src/styles/global.css:366-430`) so the pages look byte-identical before activation — which means editing a `.cp-*` rule to suit the live editor regresses the landing page, exactly the failure mode the plan prompt records for `.lc-mount` (`DOCS/PLANS_PROMPT.md:178`, `global.css:477-525` shared by `LiveCanvas.astro:26` and `Playground.astro:62`). Every new rule in this phase is `.le-*`; any override of an inherited rule is written `.le .cp-pane`, never `.cp-pane`. Three inherited rules are load-bearing and must be kept **by class**, not re-declared: `.cp` (`global.css:367`, the figure's `margin: 1.5rem 0 2rem`), and `.cp-preview pre` / `.cp-preview pre code` (`:421-425` — `--font-mono-strict`, `line-height: 1`, `white-space: pre`, without which every ASCII schematic on `/tour` and `/examples` falls off the character grid). The root is therefore `class="cp le"` and the output pane `class="cp-pane cp-preview le-out"`. `.cp-pane pre { flex: 1 }` (`:410-418`) stops reaching the source `<pre>` once `<Code>` sits inside `.le-static`, because the div becomes the flex item — so the new block gives `.le .le-static { flex: 1; min-height: 0; }`. (`.cp-source` is the one class safe to drop: it has no rule in `global.css`, verified by grep.) (2) **`/` keeps `<CodePreview>` and `<LiveCanvas>`** (`site/src/pages/index.astro:36-41`); both components survive this phase unchanged, and `/` stays in the ≤ 10 KB gzip tier. (3) **Nothing heavy loads before interaction** (`DOCS/PLANS_PROMPT.md:32`): `circ-editor.ts`, `libcirc-client.ts`, `circ-renderer`, `site/src/utils/circ-theme.mjs` and `share-link.ts` are reached only through dynamic `import()`, the `??=` pattern at `LiveCanvas.astro:41-46` and `Playground.astro:347-348`. A static import of any of them from the island script puts CodeMirror in `/tour`'s eager module graph and fails `bun run bundle`. `libcirc-client.ts` is dynamic **too**, and deliberately so: `getSharedClient` is imported inside the activation path, never at module top level, so `libcirc-client.ts` and the worker chunk that `new URL('../workers/libcirc.worker.ts', import.meta.url)` creates at `libcirc-client.ts:30` appear exactly once, in the dynamic graph. Were it reachable both eagerly from the island and dynamically from the controller, the module-level `shared` map would be duplicated and the page would spawn two workers — the outcome decision 11 (`:52`) exists to prevent. (4) **`compile` transfers `bytes.buffer`** (`site/src/workers/libcirc.worker.ts:63-65`); each instance keeps exactly one reference to its artifact (`DOCS/PLANS_PROMPT.md:159`). (5) **There are no committed `tour-<N>.wasm` files** — `site/scripts/compile-content.ts:93-99` writes them untracked and `site/.gitignore` does not cover them, so `output="simulate"` on `/tour` would have no poster artifact; `/tour` uses `output="preview"`. (6) **Decision 15 lists only `site/src/components/LiveEditor.astro` for this phase** (`DOCS/PLANS_PROMPT.md:56`), but the same decision's first sentence requires that behaviour `bun test` can reach live in a `.ts` module under `site/src/`, and the plan prompt's own trap list says to push as much as possible into pure functions because no browser is ever available (`:136`). This phase therefore adds three small modules alongside the component and no others. (7) **Every internal path goes through `url()`** (`site/src/utils/url.ts:6-9`) — the pattern `LiveCanvas.astro:13`, `Playground.astro:11` and `index.astro:44` already use. A hard-coded `/playground` or `/wasm/…` breaks the `BASE_PATH` deploy the workflow builds (`.github/workflows/deploy-site.yml:62` feeds `astro.config.mjs:5`): the expand link 404s and the worker's `fetch(msg.wasmUrl)` (`libcirc.worker.ts:51`) fails, so every live editor on a project-subpath deploy goes `unavailable`. Phase 4 carries the identical rule (`DOCS/PLANS/PHASE_4_workspace_and_share.md:4`).

## Goal

A reader on `/tour` clicks into the source block under any step, the block becomes a compact, syntax-highlighted, squiggle-annotated circ editor, and the `--preview` pane beside it re-renders from the browser compiler as they type; a reader on `/examples` does the same and watches the interactive canvas rebuild from the artifact their edit just produced. Every one of the seven tour steps and ten example cards on a page shares **one** `libcirc` worker and **one** `libcirc.wasm` instantiation, all of it loaded on the first click and never before. Each editor carries an "Open in playground ↗" link that works with JavaScript disabled (`#pick=tour:1`) and, once the source has been edited, carries the edit itself through Phase 4's `#src=` encoding so the reader lands in `/playground` with their exact bytes. Nothing regresses for a reader who never clicks: the server-rendered page is the page that ships today, and `bun run bundle` shows `/tour` and `/examples` inside the 20 KB gzip live-editor tier while `/`, `/download`, `/reference` and every `/reference/*` page stay under 10 KB gzip with no `@codemirror/*` module anywhere in their eager graph.

## Scope

**In scope:**

- `site/src/components/LiveEditor.astro`: props `source`, `preview`, `output` (`'preview' | 'simulate'`), `height`, `readonly`, `wasm`, `pick`, `label`; server-rendered from the same `<Code>` + `<pre>` panes `CodePreview.astro:36-52` renders today.
- Two independent lazy activations per instance — **edit** (pointerdown/focusin on the source pane, or the pane-label button) and, for `output="simulate"` only, **run** (the `▶ Run interactively` button over the committed `wasm` artifact, today's `LiveCanvas.astro:25,135` behaviour at today's cost).
- One shared worker client per page: `getSharedClient(wasmUrl)`, **shipped by Phase 3 slice 5** on `site/src/scripts/libcirc-client.ts` (decision 11, `DOCS/PLANS_PROMPT.md:52`; `DOCS/PLANS/PHASE_3_workbench.md:24,63,388`) and already adopted by `Playground.astro`. This phase adds only the second consumer — every `<LiveEditor>` on the page — and adds no code to `libcirc-client.ts`.
- Per-instance two-stage pipeline with a debounce and a sequence guard **on both stages** (decision 9, `:50`): `analyze` at 120 ms for squiggles; at 350 ms the build stage runs exactly the one call whose result the instance is displaying — `preview` with `{ color: 'never' }` for `output="preview"`, and for `output="simulate"` `preview` while no canvas is mounted (so the poster ASCII tracks the edit) and `compile` once `▶ Run interactively` has mounted one, at which point `<pre class="le-preview">` is hidden. One round-trip per build, never two: `compile` in front of a `preview` nobody reads would double the latency of the only visible call and transfer a second `bytes.buffer` (`libcirc.worker.ts:63-65`) that is immediately dropped.
- Compact editor mode: the `compact: true` arm of Phase 1's `createEditor`, plus a `--le-height` CSS custom property from the `height` prop.
- Expand to playground: a real `<a href>` seeded at build time with `#pick=<id>`, upgraded on edit to `#src=` through Phase 4's encoder, with the 8192-character refusal path of decision 6.
- Error and degraded states: compiler-load failure, status 1 with the last good output kept and dimmed, status 2/3/5 messages, and (simulate only) the topology-version mismatch guard.
- Rewiring `site/src/pages/tour.astro:26` (7 instances, `output="preview"`) and `site/src/pages/examples.astro:29-30` (10 instances, `output="simulate"`, replacing the `<CodePreview>` + `<LiveCanvas>` pair with one component whose output pane keeps the shipped ASCII as its poster frame).
- Budget: `site/bundle-budget.json` gains `routes["/tour"]` and `routes["/examples"]` = `{ gzip: 20480 }` — both are covered by `default {gzip: 10240}` until now, and Phase 0 deliberately left the 20 KB live-editor ceiling to this phase (`DOCS/PLANS/PHASE_0_builtins_and_budget.md:159`) — and their `baseline` rows are updated with the measured raw/gzip numbers; `/reference/*` proven still under 10 KB.
- `DOCS/decisions/playground.md` gains this phase's `###` entries, and their headings are appended to the `### [playground.md](playground.md)` bullet list that Phase 0 already registered under *Topics* in `DOCS/decisions/index.md` (`DOCS/PLANS/PHASE_0_builtins_and_budget.md:61`, anchoring it after the `libcirc.md` block at `index.md:56-63` and before `## Conventions` at `:65`), following the `###`-heading / reference-by-slug convention stated at `index.md:65-70`.

**Explicitly deferred:**

- `title` and `caption` props. Neither `tour.astro:26` nor `examples.astro:29` passes them; `/` keeps `CodePreview.astro`, which owns them (`CodePreview.astro:22-29`).
- A diagnostics **list** inside the live editor. Squiggles and a count in the status bar only; the clickable list is the playground's (Phase 1).
- Truth table and multi-file tabs inside a live editor. `splitFiles` still runs (tour step 6 is two files), but there is no tab strip — the marker lines stay visible in the one document, as they do on the page today.
- ROM images, settings, source linking, and split dragging inside a live editor.
- `/`, `/download` and `/reference*` gaining a `<LiveEditor>`. `/` is the landing page and stays in the 10 KB tier; the `/reference*` pages are generated from `../DOCS/*.md` by `site/scripts/sync-reference.ts` and have no place to pass props.
- Any change to `LiveCanvas.astro` or `CodePreview.astro`.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site/components | `site/src/components/LiveEditor.astro` | Markup (a `.le` figure wrapping `CodePreview`-shaped panes), the per-instance JSON blob, and the one hoisted island `<script>` that calls `mountLiveEditors()`. |
| site/scripts | `site/src/scripts/live-editor.ts` | The controller: activation, the shared client, the two stages, output rendering, canvas lifecycle, theme observer, expand wiring. Its **only** static imports are `../utils/live-editor-config.ts` and `../utils/artifact-hash.ts` (plus `import type` from `../utils/split-files.ts`, erased by esbuild) — and `live-editor-config.ts` in turn re-exports Phase 3's DOM-free `../scripts/pipeline.ts`, which is therefore the one module that joins the eager graph transitively. `libcirc-client.ts`, `circ-editor.ts`, `circ-diagnostics.ts`, `circ-renderer`, `circ-theme.mjs` and `share-link.ts` are all reached through `??=`-cached dynamic `import()`; `getSharedClient` is imported inside the activation path, never at module top level, so the worker chunk `libcirc-client.ts:30` creates stays off `/tour`'s eager graph and the `shared` map exists once. |
| site/utils | `site/src/utils/live-editor-config.ts` | Pure: `LiveEditorConfig`, `LIVE_EDITOR_DEFAULTS`, `parseLiveEditorConfig`, `clampHeight`, `expandTarget`. **Re-exports** `Stage`, `ANALYZE_DEBOUNCE_MS`, `BUILD_DEBOUNCE_MS` and `outputsShouldClear` from `../scripts/pipeline.ts` (Phase 3, `PHASE_3_workbench.md:262-296,319,388`) rather than declaring them, so decision 9 has one implementation. No DOM. Its only two imports are that module and `SHARE_CAP` from `share-link.ts`; both are pure — `pipeline.ts` is DOM-free and `bun test`-driven (`PHASE_3_workbench.md:50`), and `share-link.ts` is DOM-, `location`- and `localStorage`-free (`DOCS/PLANS/PHASE_4_workspace_and_share.md:39`). |
| site/utils | `site/src/utils/artifact-hash.ts` | Pure: `fnv1a(bytes)`, lifted verbatim from `Playground.astro:319-326` so both consumers key the canvas rebuild on the same number (`DOCS/PLANS_PROMPT.md:160`). |
| site/test | `site/test/artifact-hash.test.ts` | Pins `fnv1a` against a fixed byte vector and the `0x811c9dc5` / `0x01000193` loop of `Playground.astro:319-326`, and proves a one-byte change moves it. |
| site/test | `site/test/live-editor-config.test.ts` | Unit cases for every export of `live-editor-config.ts`. |
| site/test | `site/test/live-editor.test.ts` | Only what is new to this phase: every `ex.wasm` named in `examples.ts` exists on disk, and `examples.astro` names no artifact `examples.ts` does not. The seeded-preview proof is **not** here — it widens the existing loop at `site/test/libcirc.test.ts:99-107` instead, so the phase ships no second wasm-driven pass. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site/components | `site/src/components/Playground.astro` | The local `fnv1a` (`:319-326`) is deleted and imported from `site/src/utils/artifact-hash.ts`. No behaviour change. |
| site/pages | `site/src/pages/tour.astro` | Post-Phase-4 markup — **re-read the file**; `PHASE_4:51-52,247` inserted `<OpenInPlayground id={`tour:${i + 1}`} />` into each `<section class="tour-step">`, so the line numbers this plan was written against are stale. The `<CodePreview source preview />` becomes `<LiveEditor source={step.source} preview={step.preview} output="preview" pick={`tour:${i + 1}`} label={step.title} />`; `<LiveEditor>`'s `.le-expand` supersedes `<OpenInPlayground>` here, so the slice also removes that mount and its import. |
| site/pages | `site/src/pages/examples.astro` | Post-Phase-4 markup — **re-read the file**; `PHASE_4:51-52,247` inserted `<OpenInPlayground id={`example:${ex.slug}`} />` into each `<article class="example-card">`. The `<CodePreview>` + `{ex.wasm && <LiveCanvas …/>}` pair becomes one `<LiveEditor source preview output="simulate" wasm={ex.wasm} pick={`example:${ex.slug}`} label={ex.title} />`; the `<OpenInPlayground>` mount and its import go, superseded by `.le-expand`. After both pages are rewired, `grep -rn OpenInPlayground site/src` decides whether `site/src/components/OpenInPlayground.astro` still has a consumer — delete it only if it does not. |
| site/styles | `site/src/styles/global.css` | A new `/* ---------- LiveEditor ---------- */` block after the `.cp` block (which ends at `:430`), holding only `.le-*` rules plus `.le .cp-pane` / `.le .cp-panes` overrides. `.le-canvas` mirrors `.lc-mount` (`:477-525`) rule for rule, because `.cp-pane` is `overflow: hidden` (`:386`) and none of the canvas handling reaches it: `overflow-x: auto`; `.le-canvas canvas { max-width: 100%; height: auto; display: block }`; `.le-canvas[hidden], .le-run[hidden], .le-mount[hidden] { display: none }` (an explicit `display` beats the UA `[hidden]` rule — the reason `:494-500` exists); and the `@media (max-width: 600px)` block-layout / `max-width: none` / `margin-inline: auto` pair whose rationale is the scrollLeft comment at `:502-514`. Copy those rules; never edit `.lc-*`, which `/` still renders (`index.astro:41`). |
| site/config | `site/bundle-budget.json` | Gains `routes["/tour"]` and `routes["/examples"]` = `{ gzip: 20480 }` — the file has no tier rows, only `default {gzip: 10240}`, per-route overrides and measured `baseline` rows (`DOCS/PLANS/PHASE_0_builtins_and_budget.md:159`) — and their `baseline` rows are updated with the measured raw/gzip numbers. |
| site/test | `site/test/bundle-graph.test.ts` | Phase 0's build-free graph gate gains the `LiveEditor.astro` island-allowlist case, the `live-editor.ts` static-specifier case, and the `DocsLayout.astro` reachability case. |
| DOCS | `DOCS/decisions/playground.md`, `DOCS/decisions/index.md` | Append this phase's `###` entries to `playground.md` (created and registered under *Topics* by Phase 0, `PHASE_0_builtins_and_budget.md:61`) and add their headings to the `### [playground.md](playground.md)` bullet list in `index.md`. |

**New dependencies:** None. CodeMirror arrives with Phase 1; `circ-renderer` is already pinned (`site/package.json:17`).

## Data & State

Pure module — `site/src/utils/live-editor-config.ts`:

```ts
export type LiveEditorOutput = 'preview' | 'simulate';

export interface LiveEditorConfig {
  output: LiveEditorOutput;
  /** A validated CSS length, written to the root as `--le-height`. */
  height: string;
  readonly: boolean;
  /** `example:<slug>` | `tour:<n>` — decision 6's `#pick=` id shape; null when the source is not shipped content. */
  pickId: string | null;
  /** Committed artifact href for the simulate poster frame — already `url()`-prefixed
   *  by the component (read from `data-le-wasm`); null when that attribute is empty. */
  wasmHref: string | null;
  /** aria-label for the editor's content DOM. */
  label: string;
}

export const LIVE_EDITOR_DEFAULTS = { output: 'preview', height: '14rem', readonly: false } as const;

// Decision 9's two stages are Phase 3's, imported and never re-declared —
// `site/src/scripts/pipeline.ts` exports `Stage`, `ANALYZE_DEBOUNCE_MS = 120`
// and `BUILD_DEBOUNCE_MS = 350` (`PHASE_3_workbench.md:262-296`), is DOM-free,
// and is already proved by `site/test/pipeline.test.ts` (`:414`).
export { Stage, ANALYZE_DEBOUNCE_MS, BUILD_DEBOUNCE_MS } from '../scripts/pipeline.ts';

// Decision 6's cap is Phase 4's constant, imported and never re-declared
// (`DOCS/PLANS/PHASE_4_workspace_and_share.md:148`). Two copies of a locked
// number in two modules is the drift decision 2 exists to prevent, and
// `share-link.ts` is pure — no DOM, no `location`, no `localStorage`
// (`PHASE_4:39`) — so this import costs nothing.
export { SHARE_CAP } from './share-link.ts';

const HEIGHT_RE = /^\d{1,4}(\.\d{1,2})?(rem|em|px|ch|vh)$/;

/** Anything that is not a plain CSS length falls back to the default; never throws. */
export function clampHeight(raw: string | undefined | null): string;

/**
 * Reads the `data-le-*` attributes of a `.le` root — including `data-le-height`,
 * which the component emits beside the `--le-height` custom property so the
 * parsed `height` field is reachable and testable rather than dead state.
 * Unknown `output` values fall back to 'preview'; `height` runs through
 * `clampHeight`.
 */
export function parseLiveEditorConfig(d: Record<string, string | undefined>): LiveEditorConfig;

// Decision 9's clear trigger is Phase 3's, imported and never re-implemented:
// `outputsShouldClear(prev, next)` over the file NAME lists
// (`PHASE_3_workbench.md:319`, tested at `:416`).
export { outputsShouldClear } from '../scripts/pipeline.ts';

export type ExpandResult =
  // `#pick=tour:1` — no source in the URL. `note` is set only on the over-cap
  // degrade, where the reader must be told the edit was left behind.
  | { kind: 'pick'; hash: string; note?: string }
  // The encoder's `fragment` verbatim; it already carries its leading `#`.
  | { kind: 'src'; hash: string }
  | { kind: 'refuse'; reason: string };

/**
 * Decision 6's precedence, as a pure function. `encode` is Phase 4's
 * `encodeShare` partially applied with a codec — slice 6's single call site is
 * `const enc = (s: string) => encodeShare(s, webStreamsCodec())` — injected so
 * this module keeps no import edge on `share-link.ts`'s browser half and its
 * tests need no `CompressionStream`. Phase 4's encoder owns `SHARE_CAP` and
 * returns its refusal as a value (`PHASE_4:163-175`), so `expandTarget` never
 * measures a string: it branches on `ok`. Unedited source with a pick id never
 * calls `encode` at all.
 */
export function expandTarget(o: {
  pickId: string | null;
  original: string;
  current: string;
  /** Structurally Phase 4's `EncodeResult` (`PHASE_4:163-175`); `fragment`
   *  already includes its leading `#`, so never write `'#' + fragment`. */
  encode: (source: string) => Promise<
    | { ok: true; key: 'src' | 'src0'; fragment: string; chars: number }
    | { ok: false; reason: 'too-large'; chars: number; cap: number }
  >;
}): Promise<ExpandResult>;
```

Pure module — `site/src/utils/artifact-hash.ts`:

```ts
/** FNV-1a over the artifact bytes; the identity every canvas rebuild is keyed on. */
export function fnv1a(bytes: Uint8Array): number;
```

Shared client — `site/src/scripts/libcirc-client.ts`. **Shipped by Phase 3 slice 5** (`PHASE_3_workbench.md:63,388`); reproduced here only so this plan reads standalone:

```ts
const shared = new Map<string, LibcircClient>();

/** One client (and therefore one worker, one wasm instance) per wasm URL per page. */
export function getSharedClient(wasmUrl: string): LibcircClient {
  let c = shared.get(wasmUrl);
  if (!c) { c = new LibcircClient(wasmUrl); shared.set(wasmUrl, c); }
  return c;
}
```

Controller state — `site/src/scripts/live-editor.ts`, one record per root element, held in a `WeakMap` exactly as `LiveCanvas.astro:49` does (Astro hoists and dedupes the island script across all instances on a page, `LiveCanvas.astro:31-33`).

Every type below comes from a module, never from an island: `EditorHandle` from `site/src/scripts/circ-editor.ts` (`DOCS/PLANS/PHASE_1_editor.md:241-252`), `CircView` from `circ-renderer`, `SplitFile` from `site/src/utils/split-files.ts`, and `Analysis` from `site/src/scripts/circ-diagnostics.ts` (`PHASE_1_editor.md:311-316`) — which is where decision 5's widening of `Playground.astro:77-81` (adding `symbols[].range` and `references`) must land, because a `.ts` module cannot import a type declared inside an `.astro` island (decision 15, `DOCS/PLANS_PROMPT.md:56`). *Spike, in slice 4:* if Phase 1 left those interfaces inside the island, move them into `circ-diagnostics.ts` in this slice and re-point `Playground.astro` at them rather than making a third private copy. All of these are `import type`, spelled with the `type` keyword so esbuild erases them and the bundle-graph gate stays honest.


```ts
type LeStatus = 'idle' | 'loading' | 'compiling' | 'live' | 'error' | 'unavailable';

interface Instance {
  root: HTMLElement;
  cfg: LiveEditorConfig;
  /** The shipped source, for `expandTarget`'s `original` and for the reset path. */
  original: string;
  editor: EditorHandle | null;                          // site/src/scripts/circ-editor.ts, PHASE_1_editor.md:241-252
  analyze: Stage;   // ANALYZE_DEBOUNCE_MS
  build: Stage;     // BUILD_DEBOUNCE_MS
  files: SplitFile[];                                   // site/src/utils/split-files.ts:16
  analysis: Analysis | null;                            // import type { Analysis } from '../scripts/circ-diagnostics.ts' — PHASE_1_editor.md:311-316
  artifact: { bytes: Uint8Array; hash: number } | null;  // exactly one reference; `compile` transferred it
  canvas: CircView | null;                              // circ-renderer src/index.ts:68-73
  renderedHash: number;                                 // -1 until a canvas exists
  /** Root input pins by NAME: ids shift as the source changes (`Playground.astro:341-357`). */
  pins: Map<string, 0 | 1>;
  status: LeStatus;
  /** True while the visible output belongs to an older, still-good build. */
  stale: boolean;
  /** `files.map(f => f.name)` of the build that produced the visible output; the
   *  next build clears — not merely dims — when `outputsShouldClear(renderedFiles,
   *  next)` is true (decision 9, `DOCS/PLANS_PROMPT.md:50`). */
  renderedFiles: string[];
}

const instances = new WeakMap<HTMLElement, Instance>();
```

Astro props — `site/src/components/LiveEditor.astro`:

```ts
interface Props {
  source: string;                        // required; the shipped .circ text, marker lines and all
  preview: string;                       // required; the shipped `--preview` ASCII, the poster frame
  output?: 'preview' | 'simulate';       // default 'preview'
  height?: string;                       // default '14rem'; validated by clampHeight
  readonly?: boolean;                    // default false
  wasm?: string;                         // bare filename under public/wasm/; the component applies `url()`. Simulate only
  pick?: string;                         // 'example:<slug>' | 'tour:<n>'
  label?: string;                        // default 'circ source'
}
```

Frontmatter — `site/src/components/LiveEditor.astro`. Every internal path goes through `url()` (`site/src/utils/url.ts:6-9`), as `LiveCanvas.astro:13` and `Playground.astro:11` already do:

```ts
import { url } from '../utils/url.ts';
const libcircHref = url('/wasm/libcirc.wasm');
const posterHref  = wasm ? url(`/wasm/${wasm}`) : '';
const expandHref  = pick ? `${url('/playground')}#pick=${pick}` : url('/playground');
const leHeight    = clampHeight(height);
```

A bare `/playground` or `/wasm/…` literal anywhere in this component is a bug under `BASE_PATH`. `clampHeight` runs here, once, feeding both `--le-height` and `data-le-height`; `wasmHref` is built with `url()` **in the component**, never inside `parseLiveEditorConfig`, which is pure and knows nothing about `BASE_URL`. When `pick` is set, the frontmatter throws unless the id is in `buildCatalogue(examples, tour)` (`site/src/utils/playground-store.ts`, Phase 4) — the same build-time gate `OpenInPlayground.astro` carried (`PHASE_4:40,247`), which `.le-expand` must not drop.

Server-rendered DOM (abbreviated; the root keeps `.cp` and the output pane keeps `.cp-preview`, and `.cp-panes` / `.cp-pane` / `.cp-pane-label` are `CodePreview.astro:36-49`'s, so the pre-activation page is pixel-identical to today; `{…}` values are the frontmatter constants above):

```html
<figure class="cp le" style={`--le-height: ${leHeight}`}
        data-le-output="preview" data-le-height={leHeight} data-le-readonly="false"
        data-le-pick="tour:1" data-le-wasm={posterHref} data-le-label="A single NOT gate"
        data-libcirc-wasm={libcircHref} data-supported-versions="3">
  <script type="application/json" class="le-src"><!-- {"source": "...", "preview": "..."} --></script>
  <div class="cp-panes">
    <div class="cp-pane le-source">
      <div class="cp-pane-label">source <button type="button" class="le-edit">edit</button></div>
      <div class="le-static"><!-- <Code lang={circLang} …/>, CodePreview.astro:41 --></div>
      <div class="le-mount" hidden></div>
    </div>
    <div class="cp-pane cp-preview le-out">
      <div class="cp-pane-label">circ-compile --preview</div>
      <pre class="le-preview"><code>…</code></pre>
      <button type="button" class="le-run" hidden>▶ Run interactively</button>
      <div class="le-canvas" hidden></div>
    </div>
  </div>
  <div class="le-bar"><span class="le-dot" data-state="idle"></span>
    <span class="le-msg" aria-live="polite"></span>
    <a class="le-expand" href={expandHref}>Open in playground ↗</a></div>
</figure>
```

The source is read from the `le-src` JSON blob, never re-derived from the Shiki-highlighted DOM — the `set:html={JSON.stringify(...)}` pattern already used at `Playground.astro:66`.

## Execution & Concurrency Model

There is no new thread. The single background worker is the one `site/src/workers/libcirc.worker.ts` already owns (`DOCS/decisions/libcirc.md`, "Playground artifacts are committed; the module runs in a Web Worker"), and this phase **reduces** the number of them: `getSharedClient` makes a page with seven or ten live editors spawn one worker and instantiate `libcirc.wasm` once (decision 11). The worker handles messages serially and `circ_result_ptr()` is valid only until the next `circ_*` call (`DOCS/libcirc-api.md:160`), so concurrency is entirely a matter of which replies are still wanted.

Ownership: the worker owns the wasm instance; `LibcircClient` owns the id→promise table (`libcirc-client.ts:22,46-53`); each `Instance` owns its two `Stage`s, its editor view, its artifact reference and its canvas. Nothing is shared between instances except the client itself, and the client is stateless request/response — no handles, no session (decision 11).

Staleness, not cancellation. `LibcircClient` has no abort and no timeout (verified: no such token exists in `site/src/scripts/libcirc-client.ts`), so a superseded request keeps computing in the worker; a `Stage`'s sequence guard only drops its reply (`DOCS/PLANS_PROMPT.md:158`). Both stages guard, on the way in *and* after every `await` — the bug the site must not copy from langlang's `live/useLiveEditor.ts` (compile guarded at `:71,80`, match unguarded at `:99-108`).

Fairness across instances: only the instance being typed in schedules work; an inactive instance holds no timer. If a reader types in one editor while another's build is in flight, the second reply is simply queued behind the first in the worker — acceptable, because the pre-flight input-bit cap that makes long calls possible (decision 13) belongs to the truth table, which this phase never calls.

The canvas is rebuilt only when the artifact hash changes (`fnv1a`, `artifact-hash.ts`), the rule `Playground.astro:198,433` already enforces; a rebuild destroys the old view (`circ-renderer` `src/render/canvas.ts:165`) because the renderer captures its theme at construction (`DOCS/PLANS_PROMPT.md:166`), and pins are replayed by name afterwards (`Playground.astro:386-398`). One page-level `MutationObserver` on `document.documentElement`'s `data-theme` (`Playground.astro:452-455`; `ThemeToggle.astro` dispatches no event, `:9-16`) walks the instance list: editors re-theme in place through Phase 1's `Compartment`, canvases are destroyed and rebuilt. The same page-level walk is registered once against `onAssetsReady` (`site/src/utils/circ-theme.mjs:34`), which both existing canvas consumers use (`LiveCanvas.astro:84-91`, `Playground.astro:408-411`): the dark theme's PNG gate sprites decode asynchronously, and a canvas mounted before they resolve keeps vector fallback until it is rebuilt.

## Persistence & I/O

No new persistence. `<LiveEditor>` deliberately writes **nothing** to `localStorage`: the `circ.playground.v1` envelope is the playground's (decision 7), scratch projects are capped at 16, and a docs page with ten editors would churn that budget for text the reader never asked to keep. An edit survives only until the reader expands into `/playground`, at which point Phase 4's `#src=` load path creates the scratch project.

Network and I/O touched, all lazily and all already present:

- `fetch(wasmUrl)` for `site/public/wasm/libcirc.wasm`, inside the worker (`libcirc.worker.ts:51`), once per page.
- `fetch` of the committed `<slug>.wasm` by `renderCircuit({ url })` for the `output="simulate"` poster frame (`circ-renderer` `src/index.ts:83`), only when the reader presses `▶ Run interactively`.
- Dynamic module fetches for the CodeMirror chunk (`circ-editor.ts` + `circ-diagnostics.ts`), `circ-renderer`, `site/src/utils/circ-theme.mjs`, `site/src/utils/share-link.ts` and `site/src/scripts/libcirc-client.ts` — the last of which pulls in the worker chunk it creates at `:30`. Nothing on this list is statically reachable from the island script.
- `history` is not touched. The expand control is an ordinary link; the fragment scrub on arrival is `/playground`'s job (decision 6).

Recovery contract: every failure degrades to the server-rendered page. If the worker throws or `init()` rejects, the instance goes `unavailable`, the editor is left mounted read-write with no pipeline, the output pane reverts to the shipped `preview` text, and the status bar says so — the message shape of `Playground.astro:155`. If `localStorage` were ever consulted it would be wrapped in `try/catch` per `DOCS/PLANS_PROMPT.md:181`; it is not. Because the client is shared, a rejected `init()` is memoised by `libcirc-client.ts:57`'s `??=` and takes **every** instance on the page to `unavailable` at once; that is accepted — the page still reads exactly as it does today — but no instance may call `dispose()` (`:73-80` terminates the one worker and rejects every sibling's pending promise), and no instance retries `init()`. A reload is the only recovery, and the status bar says so.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Lift `fnv1a` into a shared module | `fnv1a` lifted from `Playground.astro:319-326` into `site/src/utils/artifact-hash.ts`, and `Playground.astro`'s hash call site re-pointed at it. **`getSharedClient(wasmUrl)` and `site/test/shared-client.test.ts` already exist** — Phase 3 slice 5 shipped both and switched `Playground.astro`'s client construction (`:104`) to `getSharedClient` (`PHASE_3_workbench.md:24,51,63,388`); confirm them against the shipped tree and re-state the confirmation in STATUS rather than re-creating them. No behaviour change. | `bun test`: new `site/test/artifact-hash.test.ts` pins `fnv1a` against a fixed byte vector and asserts a one-byte change moves it; the existing `site/test/shared-client.test.ts` (Phase 3's) stays green. `bun --bun run build`, then `bun run bundle` unchanged against the committed budget. |
| 2 | The pure config module | `site/src/utils/live-editor-config.ts` with `LiveEditorConfig`, `LIVE_EDITOR_DEFAULTS`, `clampHeight`, `parseLiveEditorConfig`, plus the re-export line for `Stage`, `ANALYZE_DEBOUNCE_MS`, `BUILD_DEBOUNCE_MS` and `outputsShouldClear` from Phase 3's `site/src/scripts/pipeline.ts` — none of the four is declared anywhere in this phase (`PHASE_3_workbench.md:262-296,319`). Nothing imports it yet. | `bun test`: `site/test/live-editor-config.test.ts` — defaults; an unknown `data-le-output` falls back to `'preview'` without throwing; `clampHeight` accepts `14rem`/`220px`/`30vh` and rejects `expression(…)`, `100`, `''`, `undefined`. The `Stage` and `outputsShouldClear` behaviour is **not** re-tested here — Phase 3's `site/test/pipeline.test.ts` owns it (`PHASE_3_workbench.md:414,416`); the re-export is proved by the module importing cleanly and by those cases still passing. |
| 3 | The `<LiveEditor>` shell, activation, and the compact editor | `site/src/components/LiveEditor.astro` (markup above), `site/src/scripts/live-editor.ts` with edit-activation (`pointerdown`/`focusin` on `.le-source`, plus the `.le-edit` button) mounting Phase 1's `createEditor(parent, { doc, onChange, readOnly, compact: true })` through a dynamic `import()`; `.le-*` CSS in `global.css` after `:430`; `site/src/pages/tour.astro` rewired — post-Phase-4 markup, so re-read it (`PHASE_4:51-52` inserted `<OpenInPlayground>` after the `<CodePreview>`), and remove that mount and its import, superseded by `.le-expand`. The output pane still shows the shipped text — no pipeline yet. | `bun test`: new cases in Phase 0's `site/test/bundle-graph.test.ts` assert that `LiveEditor.astro`'s island `<script>` has no static import outside `{../utils/live-editor-config.ts, ../scripts/live-editor.ts}`; **and** that `live-editor.ts`'s own static import specifiers are a subset of `{../utils/live-editor-config.ts, ../utils/artifact-hash.ts, ../utils/split-files.ts, ../scripts/pipeline.ts}` — every `@codemirror/*`, `circ-renderer`, `circ-theme.mjs`, `circ-editor.ts`, `circ-diagnostics.ts`, `libcirc-client.ts` and `share-link.ts` specifier appears only inside an `import(` expression, and any `import type` is spelled with the `type` keyword so esbuild erases it; **and** that nothing reachable statically from `DocsLayout.astro`, `Base.astro`, `Nav.astro` or `Footer.astro` imports `@codemirror/*` or `LiveEditor.astro`. `bun --bun run build`, then `bun run bundle` with `routes["/tour"] = { gzip: 20480 }` added to `site/bundle-budget.json` (it had no route entry before, only `default {gzip: 10240}`), the measured raw/gzip printed and argued in STATUS, and the per-page chunk list naming `libcirc-client` at most once for `/tour`. STATUS also records that Phase 3's `pipeline.ts` pure helpers (`Stage`, the two debounce constants, `outputsShouldClear`) now enter `/tour`'s **eager** graph through `live-editor-config.ts`'s re-export — DOM-free and small, but counted against the measured 20 KB number rather than assumed free. |
| 4 | The live pipeline and `output="preview"` | Both `Stage`s wired: `analyze` → squiggles via Phase 1's diagnostics helper and `site/src/scripts/circ-diagnostics.ts`, `build` → `preview` with `{ color: 'never' }` (`requestFor`, `split-files.ts:40-48`) and **no** `compile`: `output="preview"` never displays an artifact, so the `compile` half moves to slice 5, where `fnv1a` first has a consumer. Status bar states `idle`/`loading`/`compiling`/`live`/`error`/`unavailable`; on status 1 the previous output stays, dimmed via `.le-out[data-stale]`, and is **cleared** — not merely dimmed — when `outputsShouldClear(renderedFiles, files.map((f) => f.name))` is true, per decision 9 (`DOCS/PLANS_PROMPT.md:50`) and using Phase 3's one implementation (`PHASE_3_workbench.md:319`), never a second encoding of the rule; status 2/3/5 use the `messageOf` shape of `Playground.astro:271-278`. `readonly` suppresses the pipeline after the first run. | `bun test`: `site/test/live-editor.test.ts` (`describe.skipIf(process.env.SKIP_LIBCIRC_TEST === '1')`, the guard at `libcirc.test.ts:12`) carries only what is new to this phase; the seeded-preview proof extends the **existing** loop at `site/test/libcirc.test.ts:99-107` to iterate `[...examples, ...tour]` rather than `examples` alone, so all 17 shipped sources are proved to rtrim-equal what `circ_preview` produces and the pane cannot jump on activation. The status-1 behaviour is already pinned by `libcirc.test.ts:83-93` (same source, and it additionally pins the message and the range) — do not restate it. `bun --bun run build`, `bun run bundle`. Browser walk-through (type in tour step 1, watch the ASCII redraw) recorded in STATUS as **unrun**. |
| 5 | `output="simulate"` | The `▶ Run interactively` poster-frame path over the committed `wasm` (renderer + `circ-theme.mjs` only, no libcirc — today's `LiveCanvas.astro:66-91` cost); the build stage's `compile` half, live only while a canvas is mounted, keyed on `fnv1a`; pin replay by name; the theme `MutationObserver` **and** one `onAssetsReady` registration per page that rebuilds every mounted canvas (`circ-theme.mjs:34`; `LiveCanvas.astro:84-91`, `Playground.astro:408-411`); and the topology-version guard using `SUPPORTED_TOPOLOGY_VERSIONS` (`site/src/utils/renderer-versions.ts:5`) stamped as `data-supported-versions` (`Playground.astro:21,158-165`). Mounting the canvas hides `.le-preview` and drops the `preview` call; destroying it (compile failure, topology-version refusal) restores the pane to the last good preview text, dimmed via `.le-out[data-stale]`. `.le` sets `grid-template-columns: 1fr` on `.le .cp-panes` while a canvas is mounted, so the schematic keeps the full card width it has today (`.cp-panes` is `1fr 1fr` until 800 px, `global.css:373-381`). `site/src/pages/examples.astro` rewired to one `<LiveEditor output="simulate">` — post-Phase-4 markup, so re-read it; the `<OpenInPlayground>` mount and its import go too, and `grep -rn OpenInPlayground site/src` then decides whether `site/src/components/OpenInPlayground.astro` still has a consumer. | `bun test`: a case in `site/test/live-editor.test.ts` asserts every `wasm` named in `site/src/content/examples.ts` exists under `site/public/wasm/` (so no poster frame 404s) and that `examples.astro` names no artifact `examples.ts` does not; `site/test/renderer-pin.test.ts` stays green. `bun --bun run build`, then `bun run bundle` with `routes["/examples"] = { gzip: 20480 }` added to `site/bundle-budget.json` and its `baseline` row remeasured. Browser walk-through (edit the half-adder card, watch the canvas rebuild, click a pin) recorded as **unrun**. |
| 6 | Expand to playground | `expandTarget` added to `site/src/utils/live-editor-config.ts`; `.le-expand` ships with a static `#pick=` href and is rewritten on every accepted build to `#pick=` (unedited) or `#src=`/`#src0=` (edited) through Phase 4's `site/src/utils/share-link.ts`; over the cap — which Phase 4's `encodeShare` enforces and reports as `{ ok:false, reason:'too-large' }`, never re-measured here — it degrades to `#pick=` when one exists **and always writes the status-bar note** ("That edit is too large to carry in a link; opening the original — use Copy source to keep your version.") alongside the same "copy the source" control the no-pick branch offers; with no pick id the link is disabled and only the copy control remains (decision 6). The single call site is `const enc = (s: string) => encodeShare(s, webStreamsCodec())`, and `{kind:'src'}`'s `hash` is the encoder's `fragment` verbatim — it already carries its leading `#`. | `bun test`: `site/test/live-editor-config.test.ts` gains — unedited + pick id → `{kind:'pick', hash:'#pick=tour:1'}` for all 17 shipped sources, with no call to the injected `encode`; edited → `{kind:'src'}` whose `hash` is the encoder's `fragment` verbatim, with exactly one leading `#`; edited + an injected encoder returning `{ ok:false, reason:'too-large', cap:8192, chars:8193 }` + a pick id → `{kind:'pick'}` **with a non-empty `note`**; the same without a pick id → `{kind:'refuse'}`. Browser walk-through (edit tour step 1, expand, land in `/playground` with the edit) recorded as **unrun**. |
| 7 | Budget proof and the decisions entry | The full `bun run bundle` table pasted into STATUS; `site/bundle-budget.json` final, with `routes["/tour"]` and `routes["/examples"]` at `{ gzip: 20480 }` and every `baseline` row remeasured; this phase's `###` entries appended to `DOCS/decisions/playground.md` — created and registered under *Topics* by Phase 0 (`PHASE_0_builtins_and_budget.md:61`), so there is nothing to create here — covering one shared client per page, two independent lazy activations, the docs editor persisting nothing, and `.le-*` never editing `.cp-*`; their headings are added to the `### [playground.md](playground.md)` bullet list in `DOCS/decisions/index.md`, following the `###`-heading / reference-by-slug convention at `:65-70`. | `bun test` and `bun --bun run build` green; `bun run bundle` exits 0 with `/tour` and `/examples` ≤ 20 KB gzip and `/`, `/download`, `/reference`, `/reference/getting-started`, `/reference/circuit-format`, `/reference/wasm-api`, `/reference/preview` ≤ 10 KB gzip. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `getSharedClient returns one client per URL` (Phase 3's, re-run) | `site/test/shared-client.test.ts` | Two calls with the same URL are `===`; two different URLs are `!==`; no `Worker` is constructed (`spawn()` is only reached from `send()`, `libcirc-client.ts:48`). |
| `fnv1a matches the playground's constants` | `site/test/artifact-hash.test.ts` | A fixed `Uint8Array` hashes to the value produced by the seed `0x811c9dc5` / prime `0x01000193` loop of `Playground.astro:319-326`; flipping one byte changes it; the result is `>>> 0`. |
| `parseLiveEditorConfig fills defaults` | `site/test/live-editor-config.test.ts` | An empty dataset yields `output:'preview'`, `height:'14rem'`, `readonly:false`, `pickId:null`, `wasmHref:null`; a `data-le-height` of `220px` overrides the height (the attribute the component emits beside `--le-height`), and `data-le-height="expression(x)"` falls back to `14rem`. |
| `an unknown output value falls back` | `site/test/live-editor-config.test.ts` | `data-le-output="truth"` yields `'preview'` and does not throw. |
| `clampHeight validates CSS lengths` | `site/test/live-editor-config.test.ts` | `14rem`/`220px`/`30vh`/`40ch` pass through; `100`, `''`, `undefined`, `calc(1px)` and `expression(x)` fall back to `14rem`. |
| `expandTarget prefers pick for unedited content` | `site/test/live-editor-config.test.ts` | Over all 10 `examples` and 7 `tour` sources: unedited with a pick id → `{kind:'pick', hash:'#pick=<id>'}` and the injected `encode` is never called. |
| `expandTarget encodes an edit` | `site/test/live-editor-config.test.ts` | Edited source → `{kind:'src'}` whose `hash` is the injected encoder's `fragment` **verbatim** — one leading `#`, never `'#' + fragment`. |
| `expandTarget honours the 8 KB cap` | `site/test/live-editor-config.test.ts` | An injected encoder returning `{ ok:false, reason:'too-large', cap:8192, chars:8193 }` degrades to `{kind:'pick'}` **with a non-empty `note`** when a pick id exists, and to `{kind:'refuse'}` when it does not. `expandTarget` measures no string of its own: Phase 4's `encodeShare` owns the cap. |
| `the live editor island imports nothing heavy` | `site/test/bundle-graph.test.ts` | `LiveEditor.astro`'s island `<script>` has no static import outside `{../utils/live-editor-config.ts, ../scripts/live-editor.ts}`; **and** `live-editor.ts`'s own static import specifiers are a subset of `{../utils/live-editor-config.ts, ../utils/artifact-hash.ts, ../utils/split-files.ts, ../scripts/pipeline.ts}` — every `@codemirror/*`, `circ-renderer`, `circ-theme.mjs`, `circ-editor.ts`, `circ-diagnostics.ts`, `libcirc-client.ts` and `share-link.ts` specifier appears only inside an `import(` expression, and any `import type` is spelled with the `type` keyword so esbuild erases it; and nothing reachable from `Base.astro`, `Nav.astro`, `Footer.astro` or `DocsLayout.astro` imports `@codemirror/*` or `LiveEditor.astro`. |

Decision 9's two stages and its clear trigger are **not** unit-tested again here: `Stage`, `ANALYZE_DEBOUNCE_MS`, `BUILD_DEBOUNCE_MS` and `outputsShouldClear` are Phase 3's `site/src/scripts/pipeline.ts`, re-exported by `live-editor-config.ts`, and Phase 3's `pipeline — Stage debounce and sequence` (`PHASE_3_workbench.md:414`) and `pipeline — outputsShouldClear` (`:416`) cases cover them. This phase re-runs them; it writes no second copy.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `every seeded preview equals circ_preview` | `site/test/libcirc.test.ts` (the existing loop at `:99-107`, widened) + committed `site/public/wasm/libcirc.wasm` | The loop iterates `[...examples, ...tour]` instead of `examples` alone: for all 17 shipped sources `callOp(w,'preview',requestFor(splitFiles(source),{color:'never'}))` is status 0 and rtrim-equals (`libcirc.test.ts:97`'s helper) the `preview` prop the page seeds — the pane cannot visibly jump when the pipeline takes over. Widening the existing loop rather than copying it keeps one wasm-driven pass, not two. The status-1 shape that drives "keep the last good output, dimmed" is already pinned at `libcirc.test.ts:83-93`; this phase adds no second copy. |
| `every simulate poster artifact exists` | `site/test/live-editor.test.ts` | Every `wasm` field in `site/src/content/examples.ts` resolves to a file under `site/public/wasm/`; no tour step declares one (`compile-content.ts:93-99` writes `tour-<N>.wasm` untracked). |
| `the pinned renderer still decodes the compiled artifact` | `site/test/renderer-pin.test.ts` (existing) | Unchanged; it is the guard that `output="simulate"` can decode what the live compile produces. |
| `per-page eager JavaScript stays inside budget` | `dist/**/*.html` via `site/scripts/check-bundle.ts` | `/tour` and `/examples` ≤ 20 KB gzip; `/`, `/download`, `/reference`, `/reference/*` ≤ 10 KB gzip; `/playground` ≤ 360 KB raw / 120 KB gzip. Exits 1 over budget (decision 14). |

Run command: `cd site && bun test && bun --bun run build && bun run bundle`

(`bun --bun run build`, never plain `bun run build`, on this machine — `DOCS/PLANS_PROMPT.md:133`. Never set `SKIP_LIBCIRC_TEST=1` to make a slice pass, `:135`. No slice in this phase touches Zig, so `zig build test-all` is not part of this phase's gate.)

Manual checklist, to be recorded in each slice's STATUS entry as **unrun** unless someone actually runs it (no browser has ever been available on this branch, `DOCS/PLANS_PROMPT.md:136`): click into tour step 1's source, see a highlighted compact editor; type `not n(in=b)` and watch a red squiggle appear under `b` and the ASCII pane redraw; delete the `import xor` line from step 5 and still get an artifact (Phase 0's fix, visible here); on `/examples` press `▶ Run interactively`, toggle a pin, then edit the source and watch the canvas rebuild with the pin still set; click "Open in playground ↗" and land in `/playground` with the edit loaded and the fragment scrubbed; flip the theme with an editor and a canvas both live; flip to dark on `/examples` immediately after pressing Run and confirm the PNG gate sprites appear (the `onAssetsReady` rebuild); check no page-level horizontal scroll at 360 px, including on `/examples` with a canvas mounted (`DOCS/PLANS_PROMPT.md:31`).

## Open Questions / Spikes

`DOCS/PLANS_PROMPT.md`'s "Open items" list carries **no `TODO(phase7)` entry** (its entries are `TODO(phase0)`, two `TODO(phase1)`, `TODO(phase4)` and `TODO(phase5)`), so there is nothing from the plan prompt to resolve here. Two of the three questions this plan originally raised are answered by sibling plans that already exist in this tree; one spike remains.

- **Resolved at plan time, not a spike: the exported surface of Phase 4's `site/src/utils/share-link.ts`.** `DOCS/PLANS/PHASE_4_workspace_and_share.md:14,39,147-188` fixes it: `SHARE_CAP = 8192` (`:148`), `ShareKey = 'src' | 'src0'` (`:149`), `DeflateCodec` (`:151-154`), `webStreamsCodec(): DeflateCodec | null` (`:158`), `toBase64Url` / `fromBase64Url` (`:160-161`), `EncodeResult` / `DecodeResult` (`:163-171`), `encodeShare(source, codec?, cap?): Promise<EncodeResult>` (`:173-175`), `decodeShare(hash, codec?)` (`:176-178`), `readHash(hash): HashIntent` (`:185`), `shareUrl(href, fragment)` (`:188`). `encodeShare` enforces the cap itself and returns `{ ok:false, reason:'too-large', key, chars, cap }` (`:165`, asserted at `:260`), and its `fragment` already carries its leading `#` (`:258-259`). Slice 6 therefore wires `const enc = (s: string) => encodeShare(s, webStreamsCodec())` straight into `expandTarget`'s `encode`, and `live-editor-config.ts` imports `SHARE_CAP` rather than re-declaring it. The only thing left to confirm at implementation time is that Phase 4 shipped those names unchanged — read its STATUS entry.
- **Resolved at plan time, not a spike: what Phase 1's `compact: true` turns off.** `DOCS/PLANS/PHASE_1_editor.md:233-236` documents `compact?: boolean` as "Phase 7's `<LiveEditor>`: drops lineNumbers, both activeLine extensions and lintGutter", and `:272` gives the full set — non-compact is `lineNumbers()`, `highlightActiveLine()`, `highlightActiveLineGutter()`, `history()`, `keymap.of([indentWithTab, ...defaultKeymap, ...historyKeymap])`, `lintGutter()`, `EditorState.tabSize.of(2)`, `indentUnit.of('  ')`, `EditorView.lineWrapping`, `EditorView.contentAttributes.of({ 'aria-label': ariaLabel })`, `EditorView.updateListener.of(...)`, the language and the theme compartment; compact drops the first three plus `lintGutter()`. `foldGutter` is never in the set at all, and `lineWrapping` is always on, so this phase passes `compact: true` and adds no extensions of its own. The CodeMirror names are verified against the locked package set in the CodeMirror scratch install (`@codemirror/view` 6.43.11 `dist/index.d.ts:2395` `lineNumbers`, `:1445` `EditorView.lineWrapping`, `:1435` `EditorView.contentAttributes`, `:1284` `EditorView.editable`, `:1124` `destroy()`; `@codemirror/language` 6.12.4 `dist/index.d.ts:827` `foldGutter`, `:833` `HighlightStyle`, `:891` `syntaxHighlighting`, `:1194` `StreamLanguage`; `@codemirror/state` 6.7.4 `dist/index.d.ts:732` `Compartment`, `:1242` `EditorState.readOnly`, `:1193` `EditorState.create`; `@codemirror/lint` 6.9.7 `dist/index.d.ts:128` `setDiagnostics`, `:174` `linter`, `:9` `Diagnostic`, `:5` `Severity`; `@codemirror/commands` 6.11.0 `dist/index.d.ts:649` `defaultKeymap`, `:102` `history`, `:153` `historyKeymap`) — so nothing here is a question about the API either.
- **`TODO(phase7)`: whether a `<LiveEditor>` page's eager graph actually fits 20 KB gzip.** `TODO(phase0)` is already answered, and it removes the premise this question was originally written on: Astro never runs Vite's HTML transform for a static build and emits **no** `modulepreload` at all (`DOCS/PLANS/PHASE_0_builtins_and_budget.md:298-300`, expected grep count `0`), and the shipped walker seeds from `<script type="module" src>` tags, follows only the built chunks' own **static** import graph, and collects `import("…")` specifiers into the ungated `lazy` line without ever following them (`:181`). The remaining risk is therefore plain static reachability out of `live-editor.ts`, whose only static imports are `live-editor-config.ts` (which re-exports Phase 3's DOM-free `pipeline.ts`, so that module counts too) and `artifact-hash.ts` — `libcirc-client.ts` + `libcirc-abi.ts` and the worker chunk `libcirc-client.ts:30` creates are behind `??=`-cached `import()` like everything else. *Spike, in slice 3:* run `bun --bun run build` and `bun run bundle`, read the emitted `dist/tour/index.html` tags, and record the number. Escalation, agreed in advance: if `/tour` is over 20 KB gzip the cause is **not** `getSharedClient` — it is already dynamic; report the emitted tag set and the per-page chunk list in STATUS, name the chunk that is over, and split `live-editor.ts` into an eager activation stub plus a dynamically imported controller before touching the ceiling. A ceiling is never raised silently, and any raise is argued in STATUS with the measured number (`DOCS/PLANS_PROMPT.md:55`).
