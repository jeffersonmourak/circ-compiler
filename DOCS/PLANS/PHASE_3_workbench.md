# Phase 3 — The workbench

> **Dependencies:** Phase 0 (`DOCS/PLANS/PHASE_0_builtins_and_budget.md` — `bun run bundle`, `site/bundle-budget.json` and the build-free graph test must exist before a slice here can prove it did not blow the budget), Phase 1 (`DOCS/PLANS/PHASE_1_editor.md` — the pane this phase resizes contains a CodeMirror 6 view, not a `<textarea>`), Phase 2 (`DOCS/PLANS/PHASE_2_file_tabs.md` — the editor pane's furniture, the tab strip, is final before the splitter sizes it). Phase 4 (`DOCS/PLANS/PHASE_4_workspace_and_share.md`), Phase 5 (`DOCS/PLANS/PHASE_5_source_linking.md`), Phase 6 (`DOCS/PLANS/PHASE_6_settings_and_rom_images.md`) and Phase 7 (`DOCS/PLANS/PHASE_7_live_editors.md`) all build on the envelope, the status bar and the two-stage pipeline this phase creates.
>
> **Warnings:** `DOCS/PLANS_PROMPT.md` decisions 7, 9, 10, 11, 13 and 15 bind every slice below, and its Recurring Traps are load-bearing here in four places. (1) **`.lc-mount` is shared.** `Playground.astro:62` is `<div class="lc-mount pg-sim-mount">` while `.lc-mount` is declared at `global.css:477-500` and again inside the mobile block at `:515-525`, outside the `.pg*` block, and is also `LiveCanvas.astro:26` — which `/` and `/examples` render. No rule in this phase may touch a `.lc-mount` selector; `.pg-sim-mount` (`global.css:656`) is declared *after* `.lc-mount` in the same file, so at equal specificity it already wins, and `[data-layout="app"] …` wins outright. (2) **`ThemeToggle.astro` dispatches no event** (`ThemeToggle.astro:9-16`); the `MutationObserver` at `Playground.astro:452-455` stays the only hook, and the compact app-layout footer must keep `.site-footer-row` alive because below 600px the footer holds the *only* theme toggle (`global.css:343-363`). (3) **There is no cancellation.** `LibcircClient` has no abort and no timeout (`libcirc-client.ts:20-81`); dropping a stale reply by sequence number is all this phase can do, and the wasm keeps computing. (4) **`compile` transfers `bytes.buffer`** (`libcirc.worker.ts:63-65`) — capture `bytes.length` into a number the moment the reply lands, because a detached view reports `0`. Git conduct per `CLAUDE.md:184-206` and the Working Loop waiver in `DOCS/PLANS_PROMPT.md:96-102`: stage by path, one slice one commit, no trailers, never push.

## Goal

After this phase a visitor who opens `/playground` gets a workbench instead of an article: the page fills the viewport exactly once (`100dvh`, no page scrollbar at any width), the editor and the output pane sit side by side with a draggable divider between them that is also operable from the keyboard (`Tab` to it, arrows to move it two points at a time, `Home`/`End` to slam it to either end), and the divider's position survives a reload because a new `site/src/utils/playground-store.ts` writes it into `localStorage['circ.playground.v1']` — the whole schema-versioned envelope of decision 7, created here with only `layout.ratios` populated, quota-safe and provably evicting its least-recently-updated scratch project under `bun test`. Below 800px the two panes stack and the divider disappears from the page and from the tab order. A status bar across the bottom of the workbench says which of Idle / Loading / Compiling / Live / Error the page is in, names the compiler behind it (`circ 0.0.2 · c311f08 · CIRF v3`, read from the version handshake and falling back to the committed manifest), reports the compiled artifact's size, and surfaces any persistence note in its own polite live region. Typing continuously no longer flickers the schematic: `analyze` runs on its own 120 ms debounce and `compile`/`preview`/`truth_table` on a 350 ms one, each stage carrying its own sequence counter that is re-checked at *every* await boundary — including the second stage — langlang guards only its first stage (`PlaygroundPage.tsx:252-258`) and leaves its match step unguarded (`:290-301`) — and when the current source does not build, the last good preview, table and canvas stay on screen dimmed rather than vanishing, cleared only when the source's file set changes.

## Scope

**In scope:**

- An `app` layout variant on the existing `site/src/layouts/Base.astro` (`layout?: 'default' | 'app'`, default `'default'`), stamping `data-layout="app"` on `<body>` (`Base.astro:75`), plus the `[data-layout="app"]` CSS block that turns the body into a `100dvh` grid of `auto 1fr auto` with `overflow: hidden`, drops `main`'s `padding` / `max-width: 1100px` (`global.css:86-90`), and compacts `.site-footer` without deleting `.site-footer-row`.
- `site/src/pages/playground.astro` opting in, with its `<h1>` and its intro prose (the "nothing leaves the page" promise, `playground.astro:13-19`) preserved verbatim inside a collapsed `<details class="pg-about">` so the workbench keeps the claim without spending a screenful on it.
- A framework-free `site/src/scripts/splitter.ts`: pointer-capture drag, the WAI-ARIA window-splitter keyboard contract (`role="separator"`, `aria-orientation`, `aria-valuenow`/`min`/`max`/`text`, arrows, `Shift`+arrows, `Home`, `End`, `Escape` cancels a drag, double-click resets), px-based minimum pane sizes, and four pure helpers `bun test` drives with no DOM.
- One CSS custom property per splitter on the pane container (`--pg-split-main`), so a drag writes one property and never re-lays-out the editor (decision 10).
- `site/src/utils/playground-store.ts`: the complete `circ.playground.v1` envelope — `version`, `scratch`, `activeId`, `activeFile`, `layout.ratios`, `settings`, `tab` — with `read`/`normalize`/`write`, the 500 ms debounced writer, `try/catch` on every access, the version-mismatch reset, the 16-project / 32 KB-per-source / 256 KB-per-envelope limits, and the `QuotaExceededError` → evict-LRU → retry-once → disable-for-the-session path, all as pure functions over an injected `StorageLike`.
- Phase 3 populates `layout.ratios` only. `scratch`, `activeId`, `activeFile`, `settings` and `tab` are written with their defaults, are never read by this phase's UI, and are filled by Phase 4 (`scratch`/`activeId`/`activeFile`/`tab`) and Phase 6 (`settings`) with no second key and no `version` bump.
- The stacked mobile layout at the existing 800px breakpoint (`global.css:545-547`), with the separator removed from the page and the tab order and the persisted desktop ratio left untouched.
- A status bar row: state dot + label, detail (error/warning counts, artifact size, "showing the last good build"), compiler identity, a polite note channel for store messages, and an empty `.pg-status-actions` slot that Phase 4's Share button lands in.
- `site/src/scripts/pipeline.ts`: `ANALYZE_DEBOUNCE_MS = 120`, `BUILD_DEBOUNCE_MS = 350`, a `Stage` (one debounce + one sequence counter + `isCurrent`), the pure `statusFor` / `shouldCompile` / `outputsShouldClear` / `formatBytes`, and the island rewrite that retires the single `DEBOUNCE_MS = 250` and the single `state.gen` (`Playground.astro:85,105-106,171-217`).
- `getSharedClient(wasmUrl)` on `site/src/scripts/libcirc-client.ts` (decision 11), adopted by the playground island here. This is `PHASE_7_live_editors.md` slice 1's first half, pulled forward (`PHASE_7_live_editors.md:305`); when Phase 7 begins, its slice 1 reduces to lifting `fnv1a` into `site/src/utils/artifact-hash.ts` and re-pointing `Playground.astro`'s hash call site — `getSharedClient` and `site/test/shared-client.test.ts` already exist.
- The "last good output stays, dimmed" rule as a `data-stale` attribute on the output pane, and the file-set-change clear. This is code, not CSS: the three `state.artifact = null; hooks.onArtifact?.(null)` sites (`Playground.astro:190-191,206-207,210-211`) stop nulling on a failed build, `runPreview` (`:223`) and `runTruth` (`:244-247`) stop overwriting the pane on a non-zero status, and `hooks.onArtifact` (`:421-437`) is called with `null` from exactly one new place — the `outputsShouldClear` branch — so its teardown (`:423-431`) never runs on a syntax error.
- Appending this phase's decisions to `DOCS/decisions/playground.md` (creating it and registering it under "Topics" in `DOCS/decisions/index.md` if an earlier phase has not).

**Explicitly deferred:**

- The workspace sidebar and its third pane, share links, and `#src=`/`#pick=` load precedence — Phase 4. `LayoutState.ratios` is a `Record<string, number>` precisely so a second splitter key (`sidebar`) costs no schema change.
- Reading or writing `scratch` / `activeId` / `activeFile` / `tab` from the UI — Phase 4. Reading or writing `settings` — Phase 6.
- Any editor↔output highlighting, hover, or the `circ-renderer` pin bump — Phase 5.
- The settings drawer and ROM images — Phase 6. `PlaygroundSettings` is defined here so Phase 6 adds no fields, but no control is rendered.
- Live editors in the docs — Phase 7. `getSharedClient` ships here; the second consumer does not.
- Raising `UI_INPUT_BITS_CAP` (`Playground.astro:84`) or moving either of decision 13's two enforcement points — Phase 6 moves both together.
- Collapse/restore (`Enter` on the separator), a second splitter inside the output pane, saved per-breakpoint ratios, and any drag on touch beyond what pointer capture gives for free.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/splitter.ts` | `createSplitter()` (pointer capture, keys, ARIA, `ResizeObserver` re-clamp) over one CSS custom property, plus the pure `clampRatio` / `effectiveBounds` / `ratioFromPointer` / `stepRatio` / `ariaValues`. |
| site | `site/src/utils/playground-store.ts` | The `circ.playground.v1` envelope: types, `defaultEnvelope`, `normalize`, `readEnvelope`, `writeEnvelope` (cap trim + quota eviction + retry-once + disable), `createStore` (500 ms debounce, notes), `describeNote`. |
| site | `site/src/scripts/pipeline.ts` | Two-stage debounce + sequence guards (`Stage`), and the pure `statusFor` / `shouldCompile` / `outputsShouldClear` / `formatBytes` / `plural`. |
| site | `site/test/app-layout.test.ts` | Build-free guards: who opts into `layout="app"`, and that no `[data-layout="app"]` rule restyles `.lc-mount`. |
| site | `site/test/splitter.test.ts` | The pure splitter helpers and the whole keyboard contract as a table. |
| site | `site/test/playground-store.test.ts` | Envelope round-trip, normalisation, version reset, corrupt reset, throwing storage, debounce coalescing, envelope-cap trim, quota eviction and session disable. |
| site | `site/test/pipeline.test.ts` | `Stage` under a fake clock (coalescing, sequence claim at fire time, stale drop at both stages), `statusFor`, `shouldCompile`, `outputsShouldClear`, `formatBytes`. |
| site | `site/test/shared-client.test.ts` | `getSharedClient` memoises per URL and spawns no worker. Named exactly as `PHASE_7_live_editors.md:48` names it, so Phase 7 inherits this file instead of creating a near-duplicate. |

`site/src/scripts/pipeline.ts` is one module beyond decision 15's Phase 3 list (`playground-store.ts`, `splitter.ts`). It is added under decision 15's own governing sentence — "Behaviour a `bun test` could reach lives in a `.ts`/`.mjs` module under `site/src/`; each `.astro` island is markup plus a `<script>`" — because the pre-agreed slice-5 seam is a state machine and the trap at `PLANS_PROMPT.md:136` ("push as much behaviour as possible into pure functions `bun test` can reach") leaves it nowhere else to live: `bun test` cannot import `Playground.astro`. The slice that creates it records the addition in its STATUS entry.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/layouts/Base.astro` | `Props` gains `layout?: 'default' \| 'app'` (`:7-15`), destructured with the default `'default'` (`:17-21`); `<body>` (`:75`) becomes `<body data-layout={layout === 'app' ? 'app' : undefined}>` so every other page's markup is byte-identical. |
| site | `site/src/pages/playground.astro` | Passes `layout="app"` to `<Base>` (`:7-11`); wraps `<h1>` and the intro paragraph (`:12-19`) in `<header class="pg-head">`, the paragraph moving inside `<details class="pg-about"><summary>about this playground</summary>…</details>` with its prose unchanged. |
| site | `site/src/components/Playground.astro` | Markup: `.pg` becomes the workbench grid (banner / panes / status bar) inside a `main` that is itself an `auto minmax(0, 1fr)` grid over the `.pg-head` header that `playground.astro` renders as `.pg`'s sibling (`Base.astro:77-79` puts both inside one `<main>`); `.pg-panes` gains `#pg-pane-editor`, the `.pg-splitter` separator and `#pg-pane-output`; the pane-local `.pg-status` (`:48`) moves out of `.pg-editor` into the new `.pg-statusbar`, unchanged; `data-manifest-version={manifest.version}` and `data-manifest-revision={manifest.revision}` join `data-manifest-full-version` on the `.pg` div (`:18-23`) so the island can render the compiler identity before the handshake resolves. Island: adopts `getSharedClient` (replacing `new LibcircClient(...)` at `:104`), mounts the splitter, creates the store, renders the status bar, and replaces the single `DEBOUNCE_MS`/`state.gen` pipeline (`:85,105-106,124-125,137-146,170-217,219-224,234-243`) with the two `Stage`s, widening `hooks.onArtifact` (`:421-437`) to take a clear reason. |
| site | `site/src/styles/global.css` | Adds `--danger` to both token blocks (`:29-56`, `:58-70`); adds the `[data-layout="app"]` block and `.pg-head` / `.pg-about` / `.pg-splitter` / `.pg-statusbar` / `.pg-dot` / `.pg-output[data-stale]` rules after the existing `.pg*` block (`:528-656`); adds the splitter and stale-output entries to the `prefers-reduced-motion` block (`:336-338`). Touches **no** `.lc-mount` selector (`:477-525`). |
| site | `site/src/scripts/libcirc-client.ts` | Module-level `getSharedClient(wasmUrl: string): LibcircClient` memo (decision 11). `dispose()` (`:73-80`) is documented as never being called on a shared client. |
| DOCS | `DOCS/decisions/playground.md` | Appends this phase's `###` entries (app layout variant, splitter contract, envelope + eviction, status-bar states, two-stage pipeline). If an earlier phase has not created the file, the first slice here creates it and registers it under "Topics" in `DOCS/decisions/index.md` alongside the seven existing topic files. |
| DOCS | `DOCS/STATUS.md` | One entry per slice, per the template at `PLANS_PROMPT.md:112-124`. |

**New dependencies:** None. No new npm package, no CodeMirror package beyond Phase 1's locked set, no polyfill. `ResizeObserver`, `matchMedia`, Pointer Events and `100dvh` are used directly, with a `height: 100vh` declaration preceding `height: 100dvh` as the only fallback.

## Data & State

### The persisted envelope — `site/src/utils/playground-store.ts`

Complete as of this phase: Phases 4 and 6 fill fields, they do not add them.

```ts
export const STORE_KEY = 'circ.playground.v1';
export const STORE_VERSION = 1;
export const MAX_SCRATCH = 16;
export const MAX_SOURCE_BYTES = 32 * 1024;
export const MAX_ENVELOPE_BYTES = 256 * 1024;
export const WRITE_DEBOUNCE_MS = 500;

/** The four output tabs, unchanged from `Playground.astro:51-56`. */
export type OutputTab = 'diagnostics' | 'preview' | 'truth' | 'simulate';

/** `example:<slug>` | `tour:<n>` | `scratch:<id>` — the id shape `Playground.astro:66` already uses. */
export type PickId = string;

export interface ScratchProject {
  /** `scratch:<base36 ms><base36 rand>`; stable for the project's life. */
  id: PickId;
  /** `generateSillyName()` (`site/src/utils/sillyname.ts:23`). */
  name: string;
  /** The combined `// <name>.circ` marker text — `joinFiles()` output (Phase 2). Never an example or tour body. */
  source: string;
  /** Epoch ms. The LRU key eviction sorts on. */
  updatedAt: number;
}

export interface LayoutState {
  /** Splitter id → first-pane fraction, strictly between 0 and 1. Phase 3 writes only `main`. */
  ratios: Record<string, number>;
}

/**
 * Stored in camelCase on purpose: an envelope key can never be spread into a
 * libcirc `options` object, where an unknown or mistyped key is status 2 and
 * never a silent default (`DOCS/libcirc-api.md:43-44`). Phase 6 translates
 * field by field into the eight documented keys.
 */
export interface PlaygroundSettings {
  expandMacros: boolean;                        // → options.expand_macros
  expandDisplay: boolean;                       // → options.expand_display
  format: 'markdown' | 'csv' | 'json';          // → options.format
  valueFormat: 'binary' | 'hex' | 'decimal';    // → options.value_format
  /** 1..24, page default 12 — decision 13's two enforcement points read this one field. */
  truthTableCap: number;                        // → options.truth_table_cap
  warningsAsErrors: boolean;                    // → options.warnings_as_errors
  /** Declared `rom` name → hex image (Phase 6; `options.preloads` is built from it). */
  romImages: Record<string, string>;
}

export interface PlaygroundEnvelope {
  version: number;              // must equal STORE_VERSION or the envelope is discarded
  scratch: ScratchProject[];    // Phase 4
  activeId: PickId | null;      // Phase 4
  activeFile: string | null;    // Phase 4 — a file name inside the active project, not a path
  layout: LayoutState;          // Phase 3
  settings: PlaygroundSettings; // Phase 6
  tab: OutputTab;               // Phase 4
}

export type StoreNote =
  | { kind: 'reset'; reason: 'version' | 'corrupt' }
  | { kind: 'evicted'; names: string[] }
  | { kind: 'disabled'; reason: 'quota' | 'unavailable' };

/** Injected so `bun test` never touches a global; the island passes `browserStorage()`. */
export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export interface TimerLike {
  setTimeout(fn: () => void, ms: number): number;
  clearTimeout(id: number): void;
}

export function defaultEnvelope(): PlaygroundEnvelope;
/** Never throws. Unknown keys are dropped; only a parse failure or a wrong `version` yields a note. */
export function normalize(raw: unknown): { envelope: PlaygroundEnvelope; note: StoreNote | null };
export function readEnvelope(storage: StorageLike | null): { envelope: PlaygroundEnvelope; note: StoreNote | null };
export function writeEnvelope(env: PlaygroundEnvelope, storage: StorageLike | null): { ok: boolean; note: StoreNote | null };
/** Removes the least-recently-updated scratch project; returns its name, or null when there is none. */
export function evictOldest(env: PlaygroundEnvelope): string | null;
/** `try/catch` around `globalThis.localStorage`: private windows and blocked site data throw on access, not just on write. */
export function browserStorage(): StorageLike | null;
export function describeNote(note: StoreNote): string;

export interface PlaygroundStore {
  /** The live envelope. Mutate only through `update()`. */
  readonly envelope: PlaygroundEnvelope;
  /** False once persistence has been disabled for the session. */
  readonly enabled: boolean;
  /** Applies the mutation immediately and schedules a debounced write. */
  update(mutate: (draft: PlaygroundEnvelope) => void): void;
  /** Writes now, cancelling any pending debounce. Bound to `pagehide` and `visibilitychange`. */
  flush(): void;
  /** Notes buffered before the first subscriber are delivered on subscribe. */
  onNote(fn: (note: StoreNote) => void): () => void;
}

export function createStore(opts?: {
  storage?: StorageLike | null;
  timers?: TimerLike;
  now?: () => number;
}): PlaygroundStore;
```

Defaults: `{ version: 1, scratch: [], activeId: null, activeFile: null, layout: { ratios: {} }, settings: { expandMacros: false, expandDisplay: false, format: 'json', valueFormat: 'binary', truthTableCap: 12, warningsAsErrors: false, romImages: {} }, tab: 'diagnostics' }`. `format` defaults to `'json'` because the page parses the truth table as JSON today (`Playground.astro:242,249`); the library's own default is `'markdown'` (`DOCS/libcirc-api.md:51`), which is why the page always sends the option explicitly.

`normalize` rules, field by field: a non-object or a `version !== STORE_VERSION` yields `defaultEnvelope()` plus a `reset` note (no migration path before v2). `scratch` keeps only entries with a string `id`/`name`/`source` and a finite `updatedAt`, drops any whose source exceeds `MAX_SOURCE_BYTES` UTF-8 bytes (dropping the project, never silently truncating the source), sorts by `updatedAt` descending and slices to `MAX_SCRATCH`. `activeId` that names a scratch id no longer present becomes `null`. `layout.ratios` keeps only finite numbers with `0 < r < 1`. `settings` is rebuilt key by key from the defaults, with `truthTableCap` clamped to 1..24 and the two enums checked against their literal sets. `tab` must be one of the four. Every unrecognised key is dropped, which is what guarantees a hand-edited envelope can never smuggle a key into `options`.

### The splitter — `site/src/scripts/splitter.ts`

```ts
export interface SplitterBounds { min: number; max: number }

export interface SplitterOptions {
  /** The grid container carrying the custom property. */
  container: HTMLElement;
  /** The `role="separator"` element. */
  separator: HTMLElement;
  /** Default '--pg-split-main'. */
  property?: string;
  /** The separator's own orientation, mirrored into `aria-orientation`. Default 'vertical' (a bar between left and right panes). */
  orientation?: 'vertical' | 'horizontal';
  /** Hard minimum for either pane. Default 240. */
  minPanePx?: number;
  minRatio?: number;      // default 0.2
  maxRatio?: number;      // default 0.8
  step?: number;          // arrow key, default 0.02
  coarseStep?: number;    // Shift+arrow, default 0.10
  initial?: number;       // default 0.5; also the double-click reset target
  label?: string;         // aria-label
  labels?: [string, string];  // aria-valuetext parts, default ['editor', 'output']
  /** Every visual change: drag frames and key presses. */
  onChange?: (ratio: number) => void;
  /** User-driven settle only: pointerup, key press, double-click. The persistence hook. */
  onCommit?: (ratio: number) => void;
}

export interface SplitterHandle {
  /** The rendered ratio: `clampRatio(intent, bounds)`. */
  readonly ratio: number;
  /** The last user-requested ratio, unclamped by the current container width. */
  readonly intent: number;
  set(ratio: number, opts?: { commit?: boolean }): void;
  /** Recompute bounds and re-render (container resize, layout-mode change). */
  refresh(): void;
  destroy(): void;
}

export function createSplitter(options: SplitterOptions): SplitterHandle;

// Pure — the whole `bun test` surface, no DOM.
export function clampRatio(ratio: number, bounds: SplitterBounds): number;
/** Tightens [minRatio, maxRatio] by `minPanePx / sizePx` at both ends; collapses to {0.5, 0.5} when the container cannot hold two minimums. */
export function effectiveBounds(sizePx: number, o: { minPanePx: number; minRatio: number; maxRatio: number }): SplitterBounds;
export function ratioFromPointer(startPx: number, sizePx: number, clientPx: number): number;
/** Returns the next ratio, or null when the key is not part of the contract (so the island does not preventDefault). */
export function stepRatio(
  ratio: number,
  ev: { key: string; shiftKey?: boolean },
  o: { orientation: 'vertical' | 'horizontal'; step: number; coarseStep: number; bounds: SplitterBounds },
): number | null;
export function ariaValues(ratio: number, bounds: SplitterBounds, labels: [string, string]):
  { now: number; min: number; max: number; text: string };
```

`--pg-split-main` holds a **unitless number in (0,1)** — the first pane's fraction — written as `container.style.setProperty(property, String(ratio))` and read by exactly one rule, so the separator's own width never has to be subtracted from the ratio: `[data-layout="app"] .pg-panes { --pg-split-w: 8px; grid-template-columns: minmax(0, calc(var(--pg-split-main, 0.5) * (100% - var(--pg-split-w)))) var(--pg-split-w) minmax(0, 1fr); }`. Nothing else reads the property. A percentage form that ignored the separator's width would sum to more than 100% and, under this phase's `overflow: hidden` body, clip invisibly instead of raising a scrollbar.

The keyboard contract, exactly as `stepRatio` implements it and `site/test/splitter.test.ts` asserts it:

| Key | `orientation: 'vertical'` | `orientation: 'horizontal'` | Result |
|---|---|---|---|
| `ArrowLeft` / `ArrowRight` | handled | ignored (`null`) | ∓`step` (0.02) |
| `ArrowUp` / `ArrowDown` | ignored (`null`) | handled | ∓`step` |
| `Shift` + the handled arrows | handled | handled | ∓`coarseStep` (0.10) |
| `Home` | handled | handled | `bounds.min` |
| `End` | handled | handled | `bounds.max` |
| anything else | `null` | `null` | not handled — no `preventDefault`, the key keeps its browser meaning |

Every result is passed through `clampRatio`. The unhandled arrows are deliberately `null` so `ArrowUp`/`ArrowDown` on a vertical separator still scroll the page. `Escape` during a drag is handled by `createSplitter` (not `stepRatio`): it releases pointer capture and restores the ratio recorded at `pointerdown`. Double-click resets to `initial` and commits. The separator carries `tabindex="0"`, `aria-controls` naming both pane ids, and `touch-action: none` in CSS so a touch drag is not stolen by scrolling.

`intent` versus `ratio` is the reason a narrow window does not eat a preference: a `ResizeObserver` on the container recomputes `effectiveBounds` and re-renders `clampRatio(intent, bounds)`, updating `aria-valuemin`/`aria-valuemax`/`aria-valuenow`, but never calls `onCommit` — only a drag, a key or a double-click persists.

### The pipeline — `site/src/scripts/pipeline.ts`

```ts
export const ANALYZE_DEBOUNCE_MS = 120;
export const BUILD_DEBOUNCE_MS = 350;

export interface TimerLike {
  setTimeout(fn: () => void, ms: number): number;
  clearTimeout(id: number): void;
}

/**
 * One debounce plus one monotonic sequence counter. The counter is claimed
 * when the timer FIRES, never when it is scheduled: a keystroke arriving
 * while a call is in flight must not invalidate that call, or the panes
 * would go empty between builds. That is the "last good output stays" half
 * of decision 9; `isCurrent` is the "drop the stale reply" half.
 */
export class Stage {
  constructor(delayMs: number, timers?: TimerLike);
  readonly delayMs: number;
  get seq(): number;
  get pending(): boolean;
  /** (Re)start the debounce; `run` receives the sequence claimed at fire time. */
  schedule(run: (seq: number) => void): void;
  /** Cancel the pending run and fire now (example pick, tab switch, first focus). */
  flush(run: (seq: number) => void): void;
  cancel(): void;
  /**
   * Claim a sequence with no timer — only for a run started outside
   * `schedule()`/`flush()` that must invalidate earlier runs. A tab switch does
   * NOT claim: it re-uses `build.seq`, so a compile already in flight stays
   * current and its artifact still lands.
   */
  claim(): number;
  /** The guard. Re-checked after EVERY await, in both stages. */
  isCurrent(seq: number): boolean;
}

export type StatusKind = 'idle' | 'loading' | 'compiling' | 'live' | 'error';

export interface StatusInput {
  ready: boolean;             // the version handshake resolved
  loading: boolean;           // the handshake is in flight
  analyzing: boolean;         // the analyze stage has a call in flight
  building: boolean;          // the build stage has a call in flight
  errors: number;             // from the freshest analysis, or a status-1 compile body
  warnings: number;
  artifactBytes: number | null;  // captured at reply time; the buffer may be transferred
  stale: boolean;             // outputs on screen are older than the current source
  failure: string | null;     // a transport error or a status 2/3/5 message; wins over everything
}

export interface StatusView { kind: StatusKind; label: string; detail: string }

/** Ordered: failure → loading → not-ready → in-flight → errors → live. */
export function statusFor(input: StatusInput): StatusView;
/** False only when the freshest analysis is for THIS document and it has errors. */
export function shouldCompile(analysis: { doc: number; errors: number } | null, doc: number): boolean;
/** True when the file NAME list changed — the only case decision 9 clears outputs instead of dimming them. */
export function outputsShouldClear(prev: readonly string[], next: readonly string[]): boolean;
export function formatBytes(n: number): string;   // '812 B' | '1.4 KB'
export function plural(n: number, word: string): string;
```

### Island state — `site/src/components/Playground.astro`

The island's `state` after Phase 2 — `tabs` (`PHASE_2_file_tabs.md`, `FileTabsState`), `mapped` (Phase 1), `analysis`, `diagnostics`, `tab`, `version`, `simulateEnabled` — keeps all of those. **`state.source` no longer exists**: Phase 2 retired it (`PHASE_2_file_tabs.md:51`, `:362`), the combined text is computed on demand as `toSource(state.tabs)`, and Phase 1's `fire()` snapshot guard is already re-based per tab as `snapshot = state.tabs.files.map((f) => f.body)`, with `setDiagnosticsFor(i, …)` skipped for any tab whose body moved on and skipped wholesale when the tab count changed. Slice 5 carries that per-tab guard forward unchanged into the two runners; `gen` is deleted and these are added:

```ts
interface WorkbenchState {
  /** Bumped on every editor change; the freshness key `shouldCompile` compares. */
  doc: number;
  analyzedDoc: number | null;
  builtDoc: number | null;
  /** `state.tabs.files.map((f) => f.name)` as of the last rendered outputs — `outputsShouldClear` input. */
  renderedFiles: string[];
  /** `size` is captured eagerly: `libcirc.worker.ts:63-65` transfers `bytes.buffer`. */
  artifact: { bytes: Uint8Array; hash: number; size: number } | null;
  stale: boolean;
  failure: string | null;
}
```

`fnv1a` (`:319-326`) and the by-name pin map (`:341-357`) are untouched — artifact identity stays the FNV-1a hash, so the canvas is still not rebuilt on every keystroke.

Every `Playground.astro:<n>` cited in this phase is the line at this plan's writing (HEAD `6ffa744`); Phases 1 and 2 rewrite that file, so resolve each by the named symbol (`fire`, `showTab`, `runPreview`, `runTruth`, `rootInputBits`, `hooks.onArtifact`, `fnv1a`, the `MutationObserver`) rather than by line.

## Execution & Concurrency Model

This phase adds **no worker, no thread and no second wasm instance**. Everything is main-thread event-driven; the only OS-level concurrency remains the existing `libcirc.worker.ts`, which handles messages serially and owns the sole `libcirc.wasm` instance.

Asynchronous sources introduced or re-shaped here, each with a single owner:

- **Two debounce timers**, one per `Stage`, owned by the island. `Stage` owns its timer handle and its counter; nothing else reads or writes them. A keystroke calls `analyze.schedule(...)` and `build.schedule(...)`; each restarts its own timer independently.
- **The sequence guards.** `Stage.claim()` runs at fire time, and `isCurrent(seq)` is re-checked *after every `await`*: after `client.call('analyze', …)`; after `client.call('compile', …)`; and again after the follow-on `preview` / `truth_table` call, which reuses the build stage's sequence. That second check is the one langlang's match step omits (`PlaygroundPage.tsx:290-301`, whose `.then` and `.catch` compare no sequence, unlike its compile stage at `:252-258`) and the site must not copy. Dropping a reply is **not** cancellation — `LibcircClient` has no abort and no timeout (`libcirc-client.ts:20-81`), so the worker finishes the stale call and its result is discarded on arrival; a 4,096-row truth table cannot be stopped, and the pre-flight cap (`Playground.astro:226-232,237`) remains the only real defence.
- **Stage coupling.** The build stage consults, but never waits on, the analyze stage: `shouldCompile(state.analyzedDoc === state.doc ? { doc, errors } : null, state.doc)` skips the compile only when a *fresh* analysis already reported errors. When the analysis is stale or absent the compile runs and status 1 is handled, so no ordering assumption between the two timers can wedge the pipeline.
- **One debounced store write**, owned by `createStore`. `update()` mutates the in-memory envelope synchronously and (re)arms a 500 ms timer; `flush()` cancels it and writes. `pagehide` and `visibilitychange` (state `hidden`) call `flush()`. `localStorage` is synchronous, so there is no write race — the last writer within a debounce window wins, by construction.
- **Pointer capture during a drag.** `pointerdown` calls `separator.setPointerCapture(e.pointerId)`, so `pointermove`/`pointerup` are delivered to the separator even over the canvas — the canvas's own `pointermove` listener (`node_modules/circ-renderer/src/render/canvas.ts:172-179`) never sees them, and no `pointer-events: none` shim is needed. `pointercancel` and `Escape` both end the drag cleanly.
- **A `ResizeObserver` on `.pg-panes`** re-clamps the rendered ratio and refreshes the ARIA values. It never commits, so a transient window resize cannot overwrite the persisted preference.
- **A `matchMedia('(max-width: 800px)')` listener** toggles the separator's `hidden` attribute (removing it from the page and from the tab order) and calls `handle.refresh()`.
- **The existing `MutationObserver`** on `document.documentElement`'s `data-theme` (`Playground.astro:452-455`) is unchanged and still the only theme hook; it rebuilds the canvas, which is why the by-name pin replay (`:385-398`) must keep working after this phase's markup move.
- **CodeMirror needs no host poke on resize.** `@codemirror/view` 6.43.11 installs its own `ResizeObserver` on `view.scrollDOM` and re-measures (`node_modules/@codemirror/view/dist/index.js:7165-7171`, guarded by a 75 ms `lastUpdate` check), so the splitter never calls `requestMeasure` (`dist/index.d.ts:873`).
- **The canvas needs no host poke either.** `CircCanvas.resize()` sizes the element from `layout.width * cell + padding * 2` and the device pixel ratio (`node_modules/circ-renderer/src/render/canvas.ts:137-149`) — it does not consult its container, so a pane resize changes nothing it would recompute; `.lc-mount canvas { max-width: 100% }` (`global.css:483-487`) does the visual fit and `componentAtEvent` already rescales client coordinates by `intendedW / rect.width` (`canvas.ts:222-235`) so hit-testing stays correct in a shrunk pane. The splitter therefore neither rebuilds nor resizes the view, and pin state survives a drag. (This refines the trap at `PLANS_PROMPT.md:167`: its point — never `destroy()` on a resize — stands; the `resize()` call it suggests is a no-op for a pane resize and is omitted rather than shipped as dead code.)

Shared state across islands is limited to the memoised `LibcircClient` from `getSharedClient(wasmUrl)`: request/response only, no handles, no session, so two callers interleaving messages is safe (the worker answers by message id, `libcirc-client.ts:31-36`). A shared client is never `dispose()`d by a consumer.

## Persistence & I/O

One key, one envelope, one origin-local store: `localStorage['circ.playground.v1']`. No network I/O is added — the only fetch on this page remains the worker's `fetch(wasmUrl)` for `libcirc.wasm` (`libcirc.worker.ts:51`), and no request payload changes shape in this phase.

Contracts:

- **Access can throw, not just return null** (private windows, blocked site data), so `browserStorage()` probes `globalThis.localStorage` inside `try/catch` and returns `null` on failure; every read and write path then degrades to in-memory-only with a `disabled: 'unavailable'` note. This mirrors `ThemeToggle.astro:14` and `Base.astro:66-72`.
- **Read.** `readEnvelope` → `getItem` → `JSON.parse` → `normalize`. A parse failure yields defaults + `reset: 'corrupt'`; a `version` mismatch yields defaults + `reset: 'version'`; neither throws and neither leaves the page blank. langlang's corruption heuristic `JSON.stringify(ws).includes("undefined")` (`workspace/useWorkspacePlayground.ts:88`) is deliberately not copied — it false-positives on any source containing the word.
- **Write.** Serialise; while the JSON exceeds `MAX_ENVELOPE_BYTES` and `scratch` is non-empty, `evictOldest()` and re-serialise; `setItem`. On a thrown `QuotaExceededError` (matched by `DOMException.name` `QuotaExceededError` / `NS_ERROR_DOM_QUOTA_REACHED`, or `code === 22`, or a plain error whose `name` is `QuotaExceededError` — the shape a test fake throws): evict the least-recently-updated scratch project and retry **exactly once**; if that throws too, or there was nothing left to evict, persistence is disabled for the session (`enabled === false`) and a `disabled: 'quota'` note is emitted. Any non-quota throw disables with `unavailable`. Every eviction and every disable is surfaced in the status bar through `describeNote`.
- **Crash recovery.** The envelope is the whole state; there is no journal and no partial write (a `setItem` either lands or throws). The worst case after a crash mid-debounce is losing up to 500 ms of layout changes, which is a splitter position.
- **What is never persisted.** Example and tour text — Phase 4 stores ids (`example:<slug>` / `tour:<n>`) because copies go stale the moment `examples.ts` changes. Phase 3 persists exactly one number.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each. The standing gate after **every** slice is `cd site && bun test` plus `bun --bun run build` (plain `bun run build` fails on this machine), and `bun run bundle` after every slice whose module graph or markup changed; no ceiling in `site/bundle-budget.json` may be raised.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The `app` layout variant on `Base.astro` + CSS | `Base.astro` gains `layout?: 'default' \| 'app'` stamping `data-layout="app"` on `<body>` (`:75`); `playground.astro` opts in and moves its intro prose into `<details class="pg-about">`; `global.css` gains the `[data-layout="app"]` block — body `100dvh` (with a `100vh` fallback line) grid `auto 1fr auto`, `overflow: hidden`, `main` stripped of `padding`/`max-width` (`:86-90`) **and given `min-height: 0` plus its own `display: grid; grid-template-rows: auto minmax(0, 1fr)`**, so the `.pg-head` header and the `.pg` workbench share the `1fr` body row (without `min-height: 0` a grid item's default `min-height: auto` lets the `1fr` row grow past the viewport, and body `overflow: hidden` then makes the bottom of the page — footer, status bar, part of the panes — unreachable with no scrollbar anywhere), `.site-footer` compacted while keeping `.site-footer-row` and its mobile-only theme toggle (`:343-363`), `.pg` as the workbench grid — `margin: 0` (overriding `:528`'s `margin: 1rem 0 2rem`), `min-height: 0`, rows `auto minmax(0, 1fr) auto` for banner / panes / status bar — `.pg-panes` given `min-height: 0`, `.pg-editor`/`.pg-output` with `min-height: 0` overriding `:555`'s `min-height: 24rem`, `[data-layout="app"] .pg-editor .pg-cm { min-height: 0 }`, `[data-layout="app"] .pg-editor .pg-cm .cm-editor { height: 100% }` and `[data-layout="app"] .pg-editor .pg-cm .cm-scroller { overflow: auto }` — overriding, not duplicating, the `.pg-cm*` geometry Phase 1 shipped (`PHASE_1_editor.md:61`), and scoped to the app layout so Phase 7's `<LiveEditor>` CodeMirror instances on `/tour` and `/examples` are never matched (the base theme gives `.cm-editor` no height — its `&` block sets only `position: relative !important`, `box-sizing`, `display: flex !important` and `flex-direction: column`, `@codemirror/view` 6.43.11 `dist/index.js:6802-6818` — while `.cm-scroller` gets `height: 100%` and `overflow-x: auto` on top of `display: flex !important`, `:6819-6829`; so the pane needs an explicit editor height and a vertical overflow) — and `--danger` added to both token blocks. No `.lc-mount` selector is touched. | `site/test/app-layout.test.ts`: `Base.astro` defaults `layout` to `'default'`; `playground.astro` is the only file under `src/pages/**` passing `layout=`; the set of comment-stripped `global.css` selectors mentioning `.lc-mount` equals the frozen five named in the Tests table and no `[data-layout="app"]` rule mentions it. Plus `bun --bun run build` and `bun run bundle` (record `/playground`'s raw and gzip headroom in STATUS). Manual checklist M1a, M3 (nav and stacking clauses) — **unrun**. |
| 2 | The splitter component and its keyboard contract | `site/src/scripts/splitter.ts` with `createSplitter` and the five pure helpers; `.pg-panes` becomes the three-track grid given in *Data & State*, driven by the unitless `--pg-split-main` with `#pg-pane-editor`, `.pg-splitter` (`role="separator"`, `tabindex="0"`, `aria-orientation="vertical"`, `aria-controls`, `aria-valuemin/max/now/text`, `touch-action: none`) and `#pg-pane-output`; the island mounts it with `initial: 0.5`. No persistence yet — the ratio resets on reload. | `site/test/splitter.test.ts`: `clampRatio`, `effectiveBounds` (including the too-narrow collapse to 0.5), `ratioFromPointer` (including out-of-rect clamping), the full `stepRatio` key table above (both orientations, `Shift`, `Home`/`End`, `null` for unhandled keys), and `ariaValues` producing integer percents and the value text. Manual checklist M2 — **unrun**. |
| 3 | Ratio persistence (the `playground-store.ts` envelope of decision 7) + stacked mobile | `site/src/utils/playground-store.ts` in full: types above, `defaultEnvelope`, `normalize`, `readEnvelope`, `writeEnvelope` (cap trim, quota eviction, retry once, session disable), `browserStorage`, `createStore` (500 ms debounce, buffered notes), `describeNote`. The island reads `layout.ratios.main` before mounting the splitter and commits through `store.update`, flushing on `pagehide`/`visibilitychange`. At `(max-width: 800px)` the app layout stops being viewport-locked and the panes stack: `[data-layout="app"] body { height: auto; overflow: visible }`, `[data-layout="app"] main { overflow: visible }`, `.pg-panes { grid-template-columns: 1fr; grid-template-rows: auto auto }`, and `.pg-editor, .pg-output { min-height: 60vh }` — the page scrolls vertically below the breakpoint rather than crushing two panes into one `1fr` track under slice 1's `min-height: 0`. A `matchMedia('(max-width: 800px)')` listener sets `separator.hidden`, with the matching `.pg-splitter[hidden] { display: none }` rule the `[hidden]` trap at `global.css:494-500` requires. | `site/test/playground-store.test.ts`, all against an injected fake `StorageLike` and a fake `TimerLike`: defaults; round-trip; unknown keys dropped; `version: 2` → defaults + `reset:'version'`; non-JSON → defaults + `reset:'corrupt'`; a `getItem` that throws → defaults + `disabled:'unavailable'`; three `update()` calls inside the window produce exactly one `setItem`; `flush()` writes immediately; an oversized envelope trims by LRU before writing; a `setItem` that throws `QuotaExceededError` once evicts the least-recently-updated project, retries once and succeeds with an `evicted` note naming it; one that always throws leaves `enabled === false` and emits `disabled:'quota'` exactly once. Manual checklist M1b, M3 (divider clause) — **unrun**. |
| 4 | The status bar | `site/src/scripts/pipeline.ts` created with its pure half (`statusFor`, `formatBytes`, `plural`); `.pg-statusbar` becomes the workbench's last grid row and the existing `.pg-status` element (`Playground.astro:48`) moves into it **unchanged — same class, same `aria-live="polite"`** — because Phase 2's file-tab announcements target it by class (`PHASE_2_file_tabs.md:126,281,295,296`), so it stays the note channel `describeNote` feeds and the new dot, detail and identity spans are its siblings inside `.pg-statusbar`. The island's `const status = el.querySelector<HTMLElement>('.pg-status')!` (`:93`) therefore still resolves — the element moved, it was not removed — and its eight `status.textContent` assignments (`:151,155,175,180,192,202,208,212`) are rewritten as one `render(statusFor(input))` call against the new label and detail spans (a `!` assertion left aimed at a deleted node throws on the first line of `init()` and takes the whole island down, and neither `bun test` nor `bun --bun run build` executes that code). The bar carries the state dot (`.pg-dot[data-state]`, `--danger` for error, pulse for compiling, honouring `prefers-reduced-motion` at `global.css:336-338`), the label and detail, the compiler identity `circ <version> · <revision> · CIRF v<full_version>` (from `state.version` after the handshake; before it resolves, the fallback text is rendered server-side by `Playground.astro` from the `manifest` prop — the same block already stamps `data-manifest-full-version` at `:22`, so this slice adds `data-manifest-version={manifest.version}` and `data-manifest-revision={manifest.revision}` to the `.pg` div at `:18-23` and the island reads `el.dataset.manifestVersion` / `el.dataset.manifestRevision` / `el.dataset.manifestFullVersion`; the island is a bundled `<script>` module (`:69`), not Astro frontmatter, and never references the `manifest` prop, which is not in its scope), a `role="status" aria-live="polite"` note span fed by `describeNote`, and an empty `.pg-status-actions` slot reserved for Phase 4's Share button. The island writes the label only when `kind` changes, so the live region does not fire per keystroke. Still driven by the existing single debounce — `analyzing` and `building` receive the same flag until slice 5. | `site/test/pipeline.test.ts` (status half): `statusFor` returns `loading` before the handshake, `compiling` while either flag is set, `error` with a pluralised count when `errors > 0`, `live` with the artifact size when neither, `error` with the failure text when `failure` is set regardless of the other fields, and `detail` says "showing the last good build" exactly when `stale`; `formatBytes(812) === '812 B'`, `formatBytes(1434) === '1.4 KB'`. Manual checklist M4 — **unrun**. |
| 5 | The two-debounce rewrite with both sequence guards | `pipeline.ts` gains `Stage`, `ANALYZE_DEBOUNCE_MS = 120`, `BUILD_DEBOUNCE_MS = 350`, `shouldCompile` and `outputsShouldClear`; `getSharedClient(wasmUrl)` lands on `libcirc-client.ts` and the island adopts it (replacing `:104`); `DEBOUNCE_MS`/`state.gen` (`:85,105-106`) are deleted together with their five remaining readers — the `showTab` calls `runPreview(state.gen)` / `runTruth(state.gen)` (`:124-125`), which become `if (tab === 'preview') void runPreview(build.seq); if (tab === 'truth') void runTruth(build.seq);` (a tab switch re-uses the current sequence and never claims a new one, so a compile already in flight stays current and its artifact still lands), and the `gen` parameters and `gen !== state.gen` guards inside `runPreview` (`:219,222`) and `runTruth` (`:234,243`), which become `build.isCurrent(seq)` — and `fire()` (`:170-217`) is split into an analyze runner and a build runner, each guarded at every await, with the follow-on `preview`/`truth_table` call re-checking the build stage's sequence. Outputs get `data-stale` (dimmed, last good preview/table/canvas retained) and are cleared only when `outputsShouldClear(state.renderedFiles, nextFiles)`; the artifact reply captures `size` before the buffer can be transferred onward. That retention is code, not CSS: the three `state.artifact = null; hooks.onArtifact?.(null)` sites (`Playground.astro:190-191,206-207,210-211`) stop nulling on a failed build — an error or a status-1 compile now only sets `state.stale = true` and leaves `state.artifact` and the canvas alone; `runPreview` (`:223`) and `runTruth` (`:244-247`) leave the previous text in place on a non-zero status and set `data-stale` instead of overwriting it, with the refusal text going to the status bar's detail; and `hooks.onArtifact?.(null)` is called from exactly one new place, the `outputsShouldClear(state.renderedFiles, nextFiles)` branch, so the hook's teardown (`:423-431` — `sim.view?.destroy()`, `simMount.innerHTML = ''`, `simMount.hidden = true`, `sim.renderedHash = -1`) runs on a file-set change and never on a syntax error. The hook body (`:421-437`) is widened to take a reason so it writes `'Compile a circuit first.'` on a file-set clear rather than `'Fix the errors to simulate.'` (`:428`). `DOCS/decisions/playground.md` gains this phase's five `###` entries — *The playground is an `app` layout variant of `Base.astro`*, *The splitter is one custom property and a WAI-ARIA separator*, *One localStorage key, one schema-versioned envelope*, *The status bar is a pure function of one input record*, *Two debounces, a sequence counter per stage* — and, if Phase 0/1/2 did not create the file, this slice creates it and registers `### [playground.md](playground.md)` under *Topics* in `DOCS/decisions/index.md` alongside the seven existing topic files, per that file's convention (`###` headings, referenced by slug, never by number, `index.md:65-70`). | `site/test/pipeline.test.ts` (stage half), fake clock: five `schedule()` calls inside the window run once; the sequence is claimed at fire time, not at schedule time (a call in flight stays current while a later timer is merely pending); `isCurrent` goes false for the earlier sequence once a later one fires, and stays false for a second-stage check made after the first-stage check passed; `flush()` cancels and runs now; `cancel()` runs nothing. Plus `shouldCompile` (false only for a fresh analysis with errors; true for a stale one), `outputsShouldClear` (false on a body edit, true when a name is added, removed or reordered), and `site/test/shared-client.test.ts` (`getSharedClient(u) === getSharedClient(u)`, different URLs differ, construction spawns no worker). Plus `DOCS/decisions/playground.md` carrying the five headings and reachable from `DOCS/decisions/index.md`. Manual checklist M5 — **unrun**. |

Slices are ordered by dependency: the layout must exist before a splitter can size it, the splitter before there is a ratio worth persisting, the status bar before it can report the pipeline's notes and states, and the pipeline last because it is the only slice that rewrites behaviour the previous four merely reposition. Each is independently reviewable and leaves `bun test` and `bun --bun run build` green.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `app layout — Base defaults to the default layout` | `site/test/app-layout.test.ts` | `Base.astro`'s `Props` declares `layout?: 'default' \| 'app'` and destructures it with the default `'default'`, so no other page's markup changes. |
| `app layout — only the playground opts in` | `site/test/app-layout.test.ts` | Exactly one file under `src/pages/**` contains `layout="app"`, and it is `playground.astro`. |
| `app layout — nothing restyles .lc-mount` | `site/test/app-layout.test.ts` | The set of `global.css` **selectors** containing `.lc-mount` equals the frozen five — `.lc-mount` (`:477`), `.lc-mount canvas` (`:483`), `.lc-mount[hidden]` (`:499`, inside the `.lc-launch[hidden], .lc-mount[hidden], .lc-error[hidden]` group), and, inside `@media (max-width: 600px)`, `.lc-mount` (`:516`) and `.lc-mount canvas` (`:520`) — with `/* … */` comments stripped before the scan, because the prose at `:495` and `:505` also contains the literal string. No selector containing `[data-layout="app"]` mentions `.lc-mount`. |
| `splitter — clampRatio and effectiveBounds` | `site/test/splitter.test.ts` | Bounds tighten by `minPanePx / sizePx`; a container narrower than `2 × minPanePx` collapses both bounds to 0.5; clamping is idempotent. |
| `splitter — ratioFromPointer` | `site/test/splitter.test.ts` | A pointer at the container's midpoint yields 0.5; outside the rect clamps to 0 and 1; a zero-width container yields 0.5 rather than `NaN`. |
| `splitter — the keyboard contract` | `site/test/splitter.test.ts` | The full key table: arrows by `step`, `Shift`+arrow by `coarseStep`, `Home`/`End` to the bounds, the wrong-axis arrows and every other key returning `null`, all results inside the bounds. |
| `splitter — ariaValues` | `site/test/splitter.test.ts` | Integer percents for `now`/`min`/`max` and a value text naming both panes. |
| `store — defaults and round-trip` | `site/test/playground-store.test.ts` | `defaultEnvelope()` has all seven fields with the documented defaults; `normalize(JSON.parse(JSON.stringify(env)))` is a fixed point; unknown keys are dropped. |
| `store — version mismatch and corruption reset` | `site/test/playground-store.test.ts` | `version: 2` and non-JSON both yield defaults plus the matching `reset` note, and never throw. |
| `store — a throwing storage disables persistence` | `site/test/playground-store.test.ts` | A `getItem`/`setItem` that throws a non-quota error yields defaults, `enabled === false`, and one `disabled:'unavailable'` note. |
| `store — normalisation limits` | `site/test/playground-store.test.ts` | More than 16 scratch projects are trimmed newest-first; a source over 32 KB drops its project; ratios outside `(0,1)` and non-finite values are dropped; `truthTableCap` clamps into 1..24; a bad `format`/`valueFormat`/`tab` falls back to its default. |
| `store — writes are debounced and flushable` | `site/test/playground-store.test.ts` | Three `update()` calls inside 500 ms produce one `setItem`; `flush()` writes immediately and cancels the pending timer. |
| `store — the envelope cap trims by LRU before writing` | `site/test/playground-store.test.ts` | An envelope over 256 KB drops least-recently-updated projects until it fits, and the write then succeeds. |
| `store — quota eviction retries exactly once` | `site/test/playground-store.test.ts` | A `setItem` throwing `QuotaExceededError` on the first call only: the oldest project is evicted, the write is retried once and succeeds, and the note names the evicted project. |
| `store — a persistent quota error disables the session` | `site/test/playground-store.test.ts` | A `setItem` that always throws leaves `enabled === false`, emits `disabled:'quota'` once, and makes further `update()` calls attempt no further writes. |
| `pipeline — statusFor` | `site/test/pipeline.test.ts` | Precedence failure → loading → idle → compiling → error → live; pluralised counts; `detail` carries the artifact size when live and the stale hint when `stale`. |
| `pipeline — Stage debounce and sequence` | `site/test/pipeline.test.ts` | Coalescing under a fake clock; the sequence is claimed at fire time; `isCurrent` is true for an in-flight call while a later timer is only pending and false once that later timer fires; `flush`/`cancel`/`claim`. |
| `pipeline — shouldCompile` | `site/test/pipeline.test.ts` | False only for an analysis of the current document with errors; true for `null`, for a stale analysis, and for a clean one. |
| `pipeline — outputsShouldClear` | `site/test/pipeline.test.ts` | False for an edit inside a body; true when a file name is added, removed or reordered. |
| `pipeline — formatBytes` | `site/test/pipeline.test.ts` | Bytes under 1024 render as `N B`; above, as one decimal of KB. |
| `libcirc client — getSharedClient memoises per URL` | `site/test/shared-client.test.ts` | The same URL returns the identical instance, different URLs differ, and construction spawns no worker (`spawn()` runs only from `send()`, `libcirc-client.ts:46-52`). |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `bun --bun run build` | whole site | The Astro production build stays green with the new layout prop, the new markup and the three new modules — the standing gate after every slice. |
| `bun run bundle` | `dist/**/*.html` | `/playground` stays under its 360 KB raw / 120 KB gzip ceiling with `splitter.ts`, `playground-store.ts` and `pipeline.ts` in the eager graph, and every non-playground page's row is unchanged (the app layout adds markup, not modules, to any other page). No budget row is raised. |
| `bundle graph` (from Phase 0) | `site/test/bundle-graph.test.ts` | Still green: nothing reachable from `Base.astro`, `Nav.astro` or `Footer.astro` imports `@codemirror/*`. The `layout` prop must not pull a playground module into the base graph. |
| `existing suite` | `site/test/{libcirc,split-files,columns,renderer-pin}.test.ts` | The 16 pre-existing cases stay green; this phase changes no request shape, no artifact and no decoder. Never run under `SKIP_LIBCIRC_TEST=1`. |

**Manual checklist (recorded in each slice's STATUS entry as _unrun_ — no browser has ever been available on this branch, `PLANS_PROMPT.md:136`):**

| # | Step | Expected |
|---|------|----------|
| M1a | 1440×900, `/playground` | No page scrollbar at any width; nav, workbench and compact footer all visible at once; the editor and output panes fill the viewport and scroll inside themselves, never as a page. |
| M1b | 1440×900, `/playground` | Drag the divider — the editor reflows and the canvas keeps its toggled pins; release, reload, the divider is where it was left. |
| M2 | Keyboard only | `Tab` reaches the divider with a visible focus ring in both themes; `ArrowLeft`/`ArrowRight` move it 2 points, `Shift`+arrow 10, `Home`/`End` to the ends; `ArrowUp`/`ArrowDown` still scroll; a drag interrupted with `Escape` snaps back. |
| M3 | 375×667 | Panes stack, no horizontal scroll at any point, each pane is at least 60vh tall and the page scrolls vertically, the hamburger menu opens and closes inside the app grid, and the theme toggle is reachable in the compact footer. From slice 3 on, also: the divider is absent from the page and from the tab order. |
| M4 | Status bar | Idle → Loading the compiler… → Compiling… → Live with an artifact size; introduce an error and the dot turns red with a pluralised count; a private window reports persistence disabled once and the page still works. |
| M5 | Type continuously for ~10 s | The schematic never disappears; the outputs dim while the source is broken and un-dim on the next good build; adding a `// second.circ` marker line clears them instead of dimming. |

Run command: `cd /Users/jeffersonmourak/circus/worktrees/v0.0.3/playground/site && bun test`, then `bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- **`TODO(phase3)`: does the mobile nav dropdown survive inside the `100dvh` app grid?** `Nav.astro:28-39`'s `<nav id="primary-nav">` becomes a full-width block below 600px and is revealed by `[data-open]` (`global.css:349-353`); inside a body grid whose first track is `auto` and whose overflow is `hidden`, the opened menu should grow the nav row and squeeze `main` rather than being clipped, but that cannot be verified without a browser. **Spike:** manual checklist item M3 in slice 1, at 375×667, with the menu open. If it clips, the fallback is to let the nav row overlay — `[data-layout="app"] .site-nav { position: relative; z-index: 2 }` with `[data-layout="app"] .site-nav nav[data-open] { position: absolute; inset-inline: 0; top: 100%; background: var(--bg) }` — which needs no JS and no change to `Nav.astro`.
- **`TODO(phase3)`: how much gzip headroom is left on `/playground` for the three new modules?** `/playground`'s **gated** number does not contain CodeMirror — `circ-editor.ts` is reached only through `import()` and `check-bundle.ts` reports such chunks on the ungated `lazy` line (`PHASE_0_builtins_and_budget.md:204-205`, `:211`; `PHASE_1_editor.md:569`) — so the 120 KB ceiling measures the island's static graph plus `splitter.ts`, `playground-store.ts` and `pipeline.ts`, not the editor. **Spike:** run `bun run bundle` at the end of slice 1 (which adds no module) and record `/playground`'s raw and gzip numbers in STATUS as the baseline, then again after slice 5; the delta is this phase's cost. **Decision rule, agreed in advance:** any overage here is this phase's own and is fixed by shrinking these three modules — never by dropping `@codemirror/commands`, whose `history()` / `historyField` Phase 2 has already shipped per-file undo on (`PHASE_2_file_tabs.md:232`, `:236`). The ceiling is not raised; any raise is argued in STATUS with the measured number.
- **`TODO(phase3)`: is the status bar's live region quiet enough for a screen reader?** The mitigation ships regardless — the label element is written only when `StatusView.kind` changes, and the noisy per-keystroke text lives in a non-live `detail` span, with `role="status" aria-live="polite"` on the note span alone — but "polite enough" is a judgement only a real AT pass can make. **Spike:** manual checklist item M4 with VoiceOver in slice 4; if it is still chatty, drop `aria-live` from the label and announce only store notes.

No `TODO(phase3)` entries exist in `DOCS/PLANS_PROMPT.md`'s Open items list, so none are resolved or deleted from it here. Two of its questions were answerable from the installed trees and are recorded as **resolved** rather than carried: CodeMirror needs no host-side re-measure when its pane is resized (`@codemirror/view` 6.43.11 observes `view.scrollDOM` itself, `dist/index.js:7165-7171`), and `CircCanvas.resize()` is container-independent (`circ-renderer` `src/render/canvas.ts:137-149`), so the splitter neither rebuilds nor resizes the simulation view.
