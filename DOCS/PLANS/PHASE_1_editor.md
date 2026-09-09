# Phase 1 — The editor

> **Dependencies:** Phase 0 (`DOCS/PLANS/PHASE_0_builtins_and_budget.md`) — its `site/scripts/check-bundle.ts`, `site/bundle-budget.json` and `site/test/bundle-graph.test.ts` are this phase's budget gate, and its regenerated `site/public/wasm/libcirc.wasm` is what slice 4's wasm-driven test analyses. Nothing else.
> **Warnings:** Read `DOCS/PLANS_PROMPT.md` decisions 1, 2, 5, 14, 15 and the whole "Recurring Traps" section before the first slice; `CLAUDE.md` "Git, commits, and PRs" governs every commit. The playground's markup and CSS live in **two** files (`site/src/components/Playground.astro` and the `.pg*` block at `site/src/styles/global.css:527-656`) and `.lc-mount` (`global.css:477-525` — the block at `:477-500` plus its mobile override at `:515-525`, the span `PLANS_PROMPT.md:178` gives) is **shared with `LiveCanvas.astro:26`**, which `/` and `/examples` render — never edit it here. `ThemeToggle.astro` dispatches no event (`ThemeToggle.astro:9-16`); the only hook is the `MutationObserver` on `document.documentElement`'s `data-theme` that `Playground.astro:452-455` already installs. **Decision 9 must not be smuggled forward:** this phase keeps `DEBOUNCE_MS = 250` (`Playground.astro:85`) and the single `state.gen` counter (`Playground.astro:105`) exactly as they are; the `ANALYZE_DEBOUNCE_MS` / `BUILD_DEBOUNCE_MS` split is Phase 3 slice 5. `site/node_modules` **is** installed in this worktree (247 top-level entries, and no `@codemirror` directory among them), so the plan prompt's "does not exist" trap (`PLANS_PROMPT.md:132`) is stale — but `bun add` still needs network, so slice 1 cannot start offline.

## Goal

A visitor opens `/playground` and, instead of a `<textarea>` (`Playground.astro:39-47`), gets a CodeMirror 6 editor whose circ mode colours `input` / `output` / `import`, all twelve builtin types — **including `rom` and `ram`, which are unhighlighted everywhere on the site today** (`circ-lang.mjs:57`) — numbers, strings, operators, comments, instance call sites and port names, in a palette derived at build time from the same `shikiLight` / `shikiDark` objects the docs code blocks use (`site/src/utils/shiki-themes.mjs:38,66`), flipping in place with the site's theme toggle and never rebuilding the view. Every `circ_analyze` diagnostic appears as a red or amber squiggle at the exact document offset the compiler's 1-based **byte** column names — correct across file-marker boundaries (`SplitFile.startLine`, `split-files.ts:10-11`) and across multi-byte characters — with a marker in the lint gutter, and the diagnostics list below the editor becomes a list of buttons that focus the editor and select that same range. `bun test` (from `site/`) grows four new files that prove the tokenizer, the palette derivation and the offset mapping as pure functions plus one wasm-driven case that proves the mapping against the committed `libcirc.wasm`; `bun --bun run build` and `bun run bundle` stay green, and no `@codemirror/*` module is reachable from `Base.astro`, `Nav.astro` or `Footer.astro`.

## Scope

**In scope:**

- Installing the six CodeMirror packages at exact pinned versions and recording the measured chunk size (resolves two of the plan prompt's `TODO(phase1)` entries).
- `site/src/utils/circ-tokens.mjs` — the one token table, consumed by `circ-lang.mjs` (TextMate, for Shiki) and by the CodeMirror `StreamParser`.
- The `rom`/`ram` highlighting bug fix in `circ-lang.mjs:57`, and the repoint of its stale in-tree path comment (`circ-lang.mjs:8-9`).
- `site/src/scripts/circ-editor.ts` — `createEditor(parent, options)` and the returned handle; the single module both this island and Phase 7's `<LiveEditor>` mount, so it imports nothing playground-specific and is loaded through a dynamic `import()`.
- `site/src/utils/circ-editor-theme.ts` — the pure shiki-scope → CodeMirror-tag palette derivation (see **New files** for why this is a fourth module beyond decision 15's three, and why it is `.ts` where `circ-tokens.mjs` must be `.mjs`).
- `site/src/scripts/circ-diagnostics.ts` — analyze range → absolute document offset, pure, `bun test`-importable.
- Wiring all of the above into `Playground.astro` behind a progressive-enhancement fallback that leaves the working `<textarea>` in place if the editor chunk fails to load.
- Widening `Playground.astro:77-81`'s `Analysis` interface to carry `symbols[].range`, `symbols[].addr_width` and `references` (decision 5 assigns this to Phase 1).
- New `.pg-cm*` CSS geometry inside the existing `.pg*` block.
- Appending Phase 1's exercised decisions (1, 2, 5, 14, 15) to `DOCS/decisions/playground.md`, as `###` headings per `DOCS/decisions/index.md:65-70` — creating the file and registering it under "Topics" in `DOCS/decisions/index.md` only if Phase 0 has not (Phase 0 creates it, `PHASE_0_builtins_and_budget.md:22,45,238`).

**Explicitly deferred:**

- File tabs, `joinFiles`, per-tab diagnostic counts — Phase 2 (`DOCS/PLANS/PHASE_2_file_tabs.md`). The editor holds one combined document with `// <name>.circ` markers, exactly as today.
- The app layout, splitters, the status bar, and the two-stage debounce with per-stage sequence guards — Phase 3 (`DOCS/PLANS/PHASE_3_workbench.md`).
- Persistence of any kind. `localStorage['circ.playground.v1']` is created in Phase 3 slice 3 (decision 7); this phase reads `localStorage` never and writes it never.
- Share links, the workspace sidebar, "Open in playground" — Phase 4 (`DOCS/PLANS/PHASE_4_workspace_and_share.md`).
- Editor ↔ canvas / truth-table hover linking and the `circ-renderer` pin bump — Phase 5 (`DOCS/PLANS/PHASE_5_source_linking.md`).
- The settings drawer and ROM images — Phase 6 (`DOCS/PLANS/PHASE_6_settings_and_rom_images.md`).
- `<LiveEditor>` in the docs — Phase 7 (`DOCS/PLANS/PHASE_7_live_editors.md`). `createEditor`'s `compact` option is specified here and shipped here, but no `.astro` component consumes it in this phase.
- Autocompletion, go-to-definition, rename, bracket matching, code folding, search — permanently out (`PLANS_PROMPT.md:73`), and `@codemirror/autocomplete` / `@codemirror/search` are not installed.
- Hover tooltips on diagnostics beyond what `@codemirror/lint`'s own `lintGutter()` provides for free.
- Any change to `site/src/utils/columns.ts`, `site/src/utils/split-files.ts`, `site/src/scripts/libcirc-client.ts`, `site/src/scripts/libcirc-abi.ts` or `site/src/workers/libcirc.worker.ts`.
- `/Users/jeffersonmourak/circus/circ-lsp/syntaxes/circ.tmLanguage.json` — a vendored TextMate copy in another repository that names `circ-lang.mjs` canonical and is missing `rom`/`ram` too. This repo cannot edit it; slice 2 only repoints the comment that points at it.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site utils | `site/src/utils/circ-tokens.mjs` | The token vocabulary (keywords, builtin types, operators), the TextMate alternation strings built from it, and the pure incremental tokenizer `nextToken(line, pos, state)` / `tokenizeLine(line, state)`. No CodeMirror import. |
| site utils | `site/src/utils/circ-editor-theme.ts` | Pure derivation of the editor palette from `shikiLight` / `shikiDark`: `styleSpecs(theme)` returns `{ tag: string, color, fontStyle?, fontWeight?, textDecoration? }[]` with tag names as **strings**, `editorPalette(theme)` returns the chrome colours. No CodeMirror import, no `@lezer/highlight` import. **A `.ts` file, not `.mjs`:** decision 15 (`PLANS_PROMPT.md:56`) does not name this module at all, so no extension is locked for it, and nothing build-time reaches it — only `circ-editor.ts` and `site/test/circ-editor-theme.test.ts` import it, and both resolve `.ts`. `circ-tokens.mjs` is the module that genuinely must stay `.mjs` (see the note under its API block). |
| site scripts | `site/src/scripts/circ-editor.ts` | `createEditor(parent, options) → EditorHandle`. The only file in the tree that imports `@codemirror/*`. Builds the `StreamLanguage` from `circ-tokens.mjs`, the `HighlightStyle` + `EditorView.theme` from `circ-editor-theme.ts` inside one `Compartment`, and exposes `setDoc` / `getDoc` / `setDiagnostics` / `setTheme` / `select` / `focus` / `destroy`. Never imported statically by anything — only through `import()`. |
| site scripts | `site/src/scripts/circ-diagnostics.ts` | The analyze JSON types (widened from `Playground.astro:77-81`) plus `indexDoc`, `fileNameFor`, `docLine`, `offsetAt`, `rangeToSpan`, `mapDiagnostics`, `toLintDiagnostics`. Pure; imports only `./columns.ts` and the `SplitFile` type. |
| site test | `site/test/circ-tokens.test.ts` | Tokenizer over every example and tour source; TextMate/tokenizer agreement; advance guarantee. |
| site test | `site/test/circ-editor-theme.test.ts` | Palette totality over the emitted tag set; tag names valid against `@lezer/highlight`'s `tags`; colours equal to the shiki source values. |
| site test | `site/test/circ-editor-parser.test.ts` | The `StreamParser` adapter, driven headlessly: the advance precondition `readToken` enforces by throwing, the returned tag's shape, and the parser's `languageData`. `circ-editor.ts` imports cleanly under `bun test` (see the callout below); only `createEditor` needs a DOM. |
| site test | `site/test/circ-diagnostics.test.ts` | Offset mapping: multi-file `startLine`, multi-byte columns, `<builtin>/` skip, clamping, empty-range widening. |
| site test | `site/test/codemirror-pin.test.ts` | `site/package.json` pins all six packages at exact versions and `site/bun.lock` resolves each. |

> **Why a fourth module.** Decision 15 names three new Phase 1 modules (`circ-tokens.mjs`, `circ-editor.ts`, `circ-diagnostics.ts`); `circ-editor-theme.ts` is a fourth. The reason is *not* that `circ-editor.ts` cannot be imported headlessly — it can (below) — but that it cannot be **exercised** headlessly: its only meaningful entry point, `createEditor(parent, …)`, constructs an `EditorView`, which builds real DOM nodes unconditionally (`@codemirror/view/dist/index.js:7894-7906`), and `bun test` has no `document`. Decision 15's own rule is that "behaviour a `bun test` could reach lives in a `.ts`/`.mjs` module", and the palette derivation is exactly such behaviour: it is the thing that must not drift from `shiki-themes.mjs`, and a pure module is the only way a test can prove it does not. It is also what keeps `circ-editor.ts` a thin CodeMirror wiring file. The slice-3 STATUS entry records this addition and this reason.
>
> **`bun test` *can* import `circ-editor.ts`, and slice 2 uses that.** `@codemirror/view` guards both of its module-scope host accesses — `let nav = typeof navigator != "undefined" ? … ` and `let doc = typeof document != "undefined" ? document : { documentElement: { style: {} } }` (`@codemirror/view/dist/index.js:6-7`); `style-mod` guards `globalThis` (`style-mod/dist/style-mod.cjs:4`, `style-mod/src/style-mod.js:4`) and reaches `document` only inside `StyleModule.mount()`, i.e. when a view is constructed; `crelt` and `w3c-keyname` touch the host only inside functions or behind `typeof` guards (`crelt/index.js:3,19`; `w3c-keyname/index.js:83-84`); `@codemirror/language`'s single module-scope host read is guarded too (`language/dist/index.js:570`). Everything short of constructing an `EditorView` therefore runs headlessly, which is what lets `site/test/circ-editor-parser.test.ts` drive the `StreamParser` adapter — the one piece of this phase whose failure mode is a **runtime throw** in the browser (`"Stream parser failed to advance stream."`, `@codemirror/language/dist/index.js:2490`, thrown after ten non-advancing calls) — in a phase whose entire manual checklist is recorded *unrun*.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site utils | `site/src/utils/circ-lang.mjs` | `repository.keyword.patterns[0].match` and `repository.type.patterns[0].match` are built from `circ-tokens.mjs` instead of being hand-written literals (`:49`, `:57`), which adds the missing `rom` / `ram`. The header comment at `:8-9` repoints from the non-existent in-tree `tools/circ-lsp/syntaxes/circ.tmLanguage.json` to `https://github.com/jeffersonmourak/circ-lsp` (`syntaxes/circ.tmLanguage.json`, which names this file canonical at its own `:3` and carries the same missing entries). Everything else — `scopeName`, the pattern order at `:26-38`, every other repository entry — is byte-identical, so `astro.config.mjs:17` and `CodePreview.astro:41` keep working unchanged. |
| site components | `site/src/components/Playground.astro` | Markup: the `<textarea id="pg-source">` at `:39-47` moves inside a new `<div class="pg-editor-wrap">` beside a new `<div id="pg-editor" class="pg-cm" hidden>` mount. Script: a `state.source` string becomes the pipeline's single source of truth (read by `fire()` at `:174`, by `locate()` at `:287`, by `renderDiagnostics()` at `:299-316`); a lazily imported editor writes it back through `onChange`; the `Analysis` interface at `:77-81` is replaced by the imported types from `circ-diagnostics.ts`; `renderDiagnostics()` jumps with `editor.select(from, to)`; the existing `MutationObserver` at `:452-455` also calls `editor.setTheme(...)`; the first-focus `ensureReady()` hook at `:458` moves to the editor host's `focusin`. The compile **status-1 branch at `:203-208` is not untouched**: it is a second, independent diagnostics producer (`state.diagnostics = (JSON.parse(c.text) as Analysis).diagnostics; renderDiagnostics();`), so it re-runs the same mapping as the analyze branch — parse `c.text` as an `Analysis`, set `state.analysis` and `state.diagnostics` from **it**, recompute `state.mapped = mapDiagnostics(snapshot, splitFiles(snapshot), compileAnalysis)`, re-render, and re-push `toLintDiagnostics(state.mapped)` behind the same `snapshot !== state.source` guard. The compile-route reply carries its own `files[]` (`DOCS/libcirc-api.md:66`: `{"files":[…],"diagnostics":[…],"symbols":[],"references":[]}`), which `fileNameFor` needs, so pass **that** `Analysis`, not the analyze one, and no extra plumbing is required. Without this the branch renders the stale analyze mapping under the status text `Compile reported diagnostics.` — the Pillar 4(b) case (`PLANS_PROMPT.md:147`) the playground surfaces most, and one Phase 0 makes more likely, not less. `DEBOUNCE_MS`, `state.gen`, `showTab`, `runPreview`, `runTruth`, `fnv1a`, and the whole `// ---- simulate ----` block from `:328` down are untouched. |
| site styles | `site/src/styles/global.css` | Inside the `.pg*` block only (`:527-656`): `.pg-source` (`:581-596`) keeps its rules for the fallback textarea; new `.pg-cm`, `.pg-cm .cm-editor`, `.pg-cm .cm-scroller`, `.pg-cm .cm-content`, `.pg-editor-wrap` and `.pg-cm[hidden]` rules carry geometry (flex, min-height, `--font-mono-strict`, `overflow`). Colours are **not** set here — they come from the `EditorView.theme` compartment. `.lc-mount` (`:477-525` — the rules at `:477-500` and the mobile override at `:515-525`) is not touched. |
| site package | `site/package.json` | Six exact-pinned `dependencies`. No change to `scripts`. |
| site lock | `site/bun.lock` | Written by `bun add`. |
| decisions | `DOCS/decisions/playground.md` | Append this phase's `###` entries — `### The editor is CodeMirror 6 with a hand-written StreamLanguage` (slice 1), `### One token table, two consumers` (slice 2), `### The editor palette is derived from the shiki themes` (slice 3, carrying the fourth-module justification against decision 15's three-module list), `### Analyze offsets are mapped in a pure module` (slice 4), `### The editor chunk loads on idle, not on interaction` (slice 1). Created here, and registered under "Topics" in `DOCS/decisions/index.md`, only if Phase 0 has not (`PHASE_0_builtins_and_budget.md:22,45,238`). Headings are referenced by slug, never by number (`DOCS/decisions/index.md:65-70`). |
| docs | `DOCS/STATUS.md` | One appended entry per slice, per `PLANS_PROMPT.md:114`'s template, never overwriting a prior entry. Slice 1 carries the measured CodeMirror chunk size, the verdict of the 20 % rule and the verified extension names; slice 2 the JSDoc-in-`.mjs` note; slice 3 the fourth-module justification; slice 4 the observed diagnostic code and span. |
| docs | `DOCS/PLANS_PROMPT.md` | Slice 4 adds the `snapshot !== state.source` staleness guard to "Recurring Traps" under Pillar 4(d); the slice that lands each resolved `TODO(phase1)` deletes that entry from "Open items" (`:190` in slice 1, `:189` once the measurement is in STATUS). Nothing else there is edited. **`site/bundle-budget.json` is not touched by this phase** — see *Open Questions*. |

**New dependencies:** six, all under decision 1's allowlist, all exact-pinned (no `^`, no `~`), versions verified against the scratch install at `/private/tmp/claude-501/-Users-jeffersonmourak-circus/9a9d359a-4d8b-4945-873f-09a96a28a456/scratchpad/cm-spike/node_modules`:

| Package | Version pinned | Why |
|---------|---------------|-----|
| `@codemirror/state` | `6.7.4` | `EditorState`, `Compartment`, `Annotation`, `EditorSelection`, `Extension`. |
| `@codemirror/view` | `6.43.11` | `EditorView`, `keymap`, `lineNumbers`, `highlightActiveLine`, `highlightActiveLineGutter`. |
| `@codemirror/language` | `6.12.4` | `StreamLanguage`, `StreamParser`, `HighlightStyle`, `syntaxHighlighting`, `indentUnit`. |
| `@codemirror/commands` | `6.11.0` | `defaultKeymap`, `history`, `historyKeymap`, `indentWithTab`. |
| `@codemirror/lint` | `6.9.7` | `setDiagnostics`, `lintGutter`, the `Diagnostic` shape. |
| `@lezer/highlight` | `1.2.3` | `tags` — a **direct** dependency, imported by name when building the `HighlightStyle`. |

No `codemirror` meta-package, no `@codemirror/autocomplete`, no `@codemirror/search`, no `@codemirror/basic-setup`. Transitively `bun` will also install `style-mod`, `w3c-keyname`, `crelt`, `@lezer/common` and `@marijn/find-cluster-break`; they are not direct dependencies and are not listed in `package.json`.

## Data & State

Every CodeMirror name below is verified against the installed `.d.ts` files at the versions pinned above; each is cited with `<package>/dist/index.d.ts:<line>`.

### `site/src/utils/circ-tokens.mjs`

```ts
/** The three declaration keywords the grammar reserves
 *  (proto-circ.peg:15,17,22 — `import` at :15, `input` at :17, and `output`
 *  as the first `ComponentType` alternative at :22). */
export const DECLARATION_KEYWORDS: readonly string[]; // ['input', 'output', 'import']

/**
 * Builtin component types. The first ten are `circ-lang.mjs:57`'s list verbatim;
 * `rom` and `ram` are the fix (lib/ir/resolver.zig:69-70 recognises them;
 * lib/resolver/scan_imports.zig:33 reserves them).
 */
export const BUILTIN_TYPES: readonly string[];
// ['and','not','wire','led','or','nand','nor','xor','xnor','bus','rom','ram']

/**
 * Multi-character operators, longest first so `<>` wins over `<`.
 * This array is the tokenizer's ONLY source for steps 4, 5 and 8 of the state
 * machine below: they match longest-first out of `OPERATORS` and never repeat
 * the literals. The three TextMate patterns stay hand-written literals
 * (`circ-lang.mjs:66`, `:96`, `:97`) because they carry three different scopes
 * and different regex escaping, so collapsing them into one alternation would
 * be wrong; slice 2's test pins the two grammars against each other instead,
 * which is what decision 2 (`PLANS_PROMPT.md:38`) asks the operator set to buy.
 */
export const OPERATORS: readonly string[]; // ['<>', '..', '=']

/** `\b(a|b|c)\b` — the exact string shape circ-lang.mjs:49,57 use today. */
export function alternation(words: readonly string[]): string;
export const KEYWORD_MATCH: string;  // alternation(DECLARATION_KEYWORDS)
export const BUILTIN_MATCH: string;  // alternation(BUILTIN_TYPES)

/**
 * Per-line tokenizer state. `params` is true between a `<` and the matching
 * `>` on the SAME line, mirroring circ-lang.mjs:69-70's `begin: '<'` /
 * `end: '>|$'`, so it is reset whenever `pos === 0`.
 */
export interface CircTokenState { params: boolean }
export function startState(): CircTokenState;
export function copyState(state: CircTokenState): CircTokenState;

/**
 * One token starting at `pos` on `line`. ALWAYS advances: `end > pos` for every
 * `pos < line.length`. `tag` is a @lezer/highlight tag name (dot-separated
 * modifiers allowed) or `null` for whitespace.
 */
export function nextToken(
  line: string,
  pos: number,
  state: CircTokenState,
): { end: number; tag: string | null };

/** Convenience wrapper used by the tests; drives `nextToken` to end of line. */
export function tokenizeLine(
  line: string,
  state?: CircTokenState,
): { from: number; to: number; tag: string | null }[];
```

> **This block is the type view, not the file's contents.** `circ-tokens.mjs` is `.mjs` because `astro.config.mjs:2` reaches it through `circ-lang.mjs` and an `.mjs` Astro config cannot import `.ts`; decision 15 (`PLANS_PROMPT.md:56`) locks that extension. Plain JavaScript carries no annotations, so every shape above ships as JSDoc — `/** @typedef {{ params: boolean }} CircTokenState */` plus `@param` / `@returns` on each exported function — which is what makes `import { type CircTokenState } from '../utils/circ-tokens.mjs'` (`circ-editor.ts`) resolve under `astro/tsconfigs/strict` (`site/tsconfig.json`; `allowJs: true` comes from `astro/tsconfigs/base.json`). **No `.mjs` under `site/src/utils/` carries JSDoc types today** — verified by grep over all four of `circ-assets.mjs`, `circ-lang.mjs`, `circ-theme.mjs` and `shiki-themes.mjs` — and no `.ts` in this tree imports a type out of one; the existing pattern is `typeof import('../utils/circ-theme.mjs')` (`LiveCanvas.astro:42`, `Playground.astro:344`). This file is the first, and slice 2's STATUS entry records that. Nothing typechecks it in CI (`bun test` and `astro build` both strip types with esbuild; `site/package.json` has no `typecheck` script), so the JSDoc exists for the editor and for Phases 2 and 5, which reuse these exports. `circ-editor-theme.ts` and `circ-diagnostics.ts` are real `.ts` files and ship the syntax shown.

The state machine, in order (first match wins, exactly mirroring `circ-lang.mjs:26-38`'s `patterns` order):

| # | At `pos` | Consumes | `tag` | TextMate counterpart |
|---|----------|----------|-------|---------------------|
| 0 | `pos === 0` | — | — | resets `state.params = false` (`end: '>\|$'`) |
| 1 | `/\s/` | the whitespace run | `null` | — |
| 2 | `//` | to end of line | `comment` | `comment.line.double-slash.circ` (`:41`) |
| 3 | `"` | to the next `"` inclusive, else to EOL | `string` | `string.quoted.double.circ` (`:44`) |
| 4 | `<>` | 2 | `operator` | `keyword.operator.connection.circ` (`:66`) |
| 5 | `..` | 2 | `operator` | `keyword.operator.range.circ` (`:96`) |
| 6 | `<` | 1, sets `params = true` | `punctuation` | `punctuation.definition.parameters.begin.circ` (`:71`) |
| 7 | `>` | 1, sets `params = false` | `punctuation` | `punctuation.definition.parameters.end.circ` (`:72`) |
| 8 | `=` | 1 | `operator` | `keyword.operator.assignment.circ` (`:97`) |
| 9 | `.` + `[A-Za-z_]` | `.` + the identifier | `propertyName` | `variable.other.member.circ` (`:103`) |
| 10 | `[0-9]` | the digit run | `number` | `constant.numeric.circ` (`:63`) |
| 11 | `[A-Za-z_]` | the identifier, then classify (below) | see below | — |
| 12 | `[(),\[\]{}]` | 1 | `punctuation` | — |
| 13 | anything else | 1 | `invalid` | — (guarantees the advance) |

Steps 4, 5 and 8 are **one loop over `OPERATORS`**, matched longest-first; the three strings appear nowhere else in this module. That is what gives the exported operator set a consumer, as decision 2 (`PLANS_PROMPT.md:38`) intends.

Identifier classification at step 11, in order:

| Test | `tag` | TextMate counterpart |
|------|-------|---------------------|
| in `DECLARATION_KEYWORDS` | `keyword` | `keyword.declaration.circ` (`:50`) |
| in `BUILTIN_TYPES` | `typeName` | `support.type.builtin.circ` (`:58`) |
| rest of line matches `/^\s*\(/` | `variableName.function` | `entity.name.function.circ` (`:82`) |
| rest of line matches `/^\s*=/` | `propertyName` | `variable.parameter.circ` (`:90`) |
| `state.params` | `propertyName` | `variable.parameter.circ` (`:74`) |
| otherwise | `variableName` | falls through to `#port`/none |

`variableName.function` resolves as `tags.function(tags.variableName)` — `function` is a registered tag modifier (`@lezer/highlight/dist/index.d.ts:551`) and `@codemirror/language`'s `createTokenType` applies dot-suffixed modifiers to the base tag (`@codemirror/language/dist/index.js:2530-2552`). Every other tag name is a plain key of the `tags` object at `@lezer/highlight/dist/index.d.ts:207-572` — `comment` `:211`, `variableName` `:231`, `typeName` `:235`, `propertyName` `:243`, `string` `:271`, `number` `:287`, `keyword` `:320`, `operator` `:362`, `punctuation` `:402`, `invalid` `:513`.

### `site/src/utils/circ-editor-theme.ts`

```ts
import { shikiLight, shikiDark } from './shiki-themes.mjs';

export type ThemeMode = 'light' | 'dark';

/** One HighlightStyle spec, with the tag named as a STRING so this module
 *  needs no @lezer/highlight import and stays trivially testable.
 *
 *  Shiki's `settings.fontStyle` is a TextMate token setting, NOT a CSS
 *  property, and it must be split at derivation time. `HighlightStyle.define`
 *  takes `TagStyle` objects whose non-`tag`, non-`class` keys are handed
 *  straight to style-mod as CSS properties
 *  (`@codemirror/language/dist/index.d.ts:914-930`: `[styleProperty: string]: any`),
 *  and style-mod kebab-cases every key (`style-mod/src/style-mod.js:41`), so a
 *  passed-through `fontStyle: 'bold'` emits `font-style: bold` — invalid CSS
 *  that every browser drops without warning. `keyword` is exactly the scope
 *  that carries it (`shiki-themes.mjs:50` light, `:78` dark), so the most
 *  prominent token class would silently lose its weight. */
export interface TagSpec {
  tag: string;
  color: string;
  fontStyle?: 'italic';          // shiki 'italic'
  fontWeight?: 'bold';           // shiki 'bold'      → font-weight, NOT font-style
  textDecoration?: 'underline';  // shiki 'underline'
}

/** The scope each CodeMirror tag reads out of a shiki theme's tokenColors. */
export const TAG_SCOPES: readonly { tag: string; scope: string }[];
// [ { tag: 'comment',              scope: 'comment' },                 // shiki-themes.mjs:46 / :74
//   { tag: 'string',               scope: 'string' },                  // :47 / :75
//   { tag: 'number',               scope: 'constant.numeric' },        // :49 / :77
//   { tag: 'keyword',              scope: 'keyword' },                 // :50 / :78
//   { tag: 'typeName',             scope: 'support.type' },            // :53 / :81
//   { tag: 'operator',             scope: 'keyword.operator' },        // :51 / :79
//   { tag: 'variableName.function',scope: 'entity.name.function' },    // :52 / :80
//   { tag: 'variableName',         scope: 'variable' },                // :56 / :84
//   { tag: 'propertyName',         scope: 'variable.parameter' },      // :56 / :84
//   { tag: 'punctuation',          scope: 'punctuation' },             // :58 / :86
//   { tag: 'invalid',              scope: 'invalid' } ]                // :62 / :90

/** Last tokenColors entry whose `scope` array contains `scope` (or a dotted
 *  prefix of it). Throws if a scope in TAG_SCOPES is absent — the drift alarm. */
export function scopeStyle(theme: unknown, scope: string): { foreground: string; fontStyle?: string };

/** TAG_SCOPES resolved against one shiki theme. `scopeStyle(...).fontStyle` —
 *  the raw TextMate string, which may be `'italic'`, `'bold'`, `'underline'`
 *  or any whitespace-separated combination — is split on `/\s+/` and each word
 *  maps to exactly one of `TagSpec`'s three style fields. An unrecognised word
 *  throws, so a future shiki edit cannot leak a TextMate setting into CSS. */
export function styleSpecs(theme: unknown): TagSpec[];

/** Editor chrome. Background/foreground come from the theme's `colors`
 *  (shiki-themes.mjs:41-44 / :69-72); everything else is a site CSS variable
 *  so the editor matches the pane it sits in. */
export interface EditorPalette {
  background: string;       // theme.colors['editor.background']  #e8def0 / #1f1438
  foreground: string;       // theme.colors['editor.foreground']  #443856 / #c0abda
  gutterBackground: string; // 'var(--pane-label-bg)'
  gutterForeground: string; // 'var(--muted)'
  gutterBorder: string;     // 'var(--border)'
  /** '.cm-content': { caretColor: … } — overrides the base theme's
   *  `&light .cm-content { caretColor: black }` (view/dist/index.js:6852). */
  caret: string;            // 'var(--accent)'
  /** '.cm-content ::selection, .cm-content::selection': { backgroundColor: … }.
   *  It is the NATIVE selection that must be styled: `drawSelection()` is
   *  deliberately not in the extension set, and `.cm-selectionBackground` — the
   *  only selection class the base theme knows (view/dist/index.js:6868-6879) —
   *  is produced solely by the selection layer that extension installs
   *  (`RectangleMarker.forRange(view, "cm-selectionBackground", r)`, `:9589`),
   *  so without it that class never exists in the DOM. The value is NOT
   *  `var(--border)`: light `--border` is `#e6dff5` (global.css:33) against the
   *  editor background `#e8def0` (shiki-themes.mjs:19), and dark `--border` is
   *  `#1a1228` (global.css:62) against `#1f1438` (shiki-themes.mjs:28) — near
   *  zero contrast in both themes, so a reader could not see their selection.
   *  Use the accent at reduced alpha:
   *  'color-mix(in srgb, var(--accent) 28%, transparent)'. */
  selection: string;
  activeLine: string;       // '.cm-activeLine': { backgroundColor: 'var(--pane-label-bg)' }
  /** Fed to the theme spec's rebuilt `backgroundImage`, not to a colour
   *  property — see the lint bullet under *Implementation contracts*. */
  errorUnderline: string;   // scopeStyle(theme, 'invalid').foreground — '#a83737' / '#ff6b8a' (shiki-themes.mjs:62,90)
  warningUnderline: string; // theme's constant.numeric foreground, the literal orange — '#8e4a0e' / darkLiteralOrange (shiki-themes.mjs:49,77)
}
export function editorPalette(theme: unknown): EditorPalette;

export function themeFor(mode: ThemeMode): { specs: TagSpec[]; palette: EditorPalette };
```

### `site/src/scripts/circ-editor.ts`

```ts
import { Annotation, Compartment, EditorSelection, EditorState, type Extension } from '@codemirror/state';
import { EditorView, keymap, lineNumbers, highlightActiveLine, highlightActiveLineGutter } from '@codemirror/view';
import { HighlightStyle, StreamLanguage, type StreamParser, indentUnit, syntaxHighlighting } from '@codemirror/language';
import { defaultKeymap, history, historyKeymap, indentWithTab } from '@codemirror/commands';
import { lintGutter, setDiagnostics, type Diagnostic } from '@codemirror/lint';
import { tags } from '@lezer/highlight';
import { copyState, nextToken, startState, type CircTokenState } from '../utils/circ-tokens.mjs';
import { themeFor, type ThemeMode } from '../utils/circ-editor-theme.ts';

export type { ThemeMode };

export interface EditorOptions {
  doc?: string;                              // default ''
  theme?: ThemeMode;                         // default currentThemeMode()
  readOnly?: boolean;                        // default false
  /** Phase 7's <LiveEditor>: drops lineNumbers, both activeLine extensions
   *  and lintGutter. Nothing in Phase 1 passes it; it ships now so the module
   *  never needs a second consumer-driven change. */
  compact?: boolean;                         // default false
  ariaLabel?: string;                        // default 'circ source'
  onChange?: (doc: string) => void;          // never fired for setDoc()
}

export interface EditorHandle {
  readonly view: EditorView;
  getDoc(): string;
  /** Replaces the whole document without firing onChange. Keeps undo history. */
  setDoc(next: string): void;
  setDiagnostics(list: readonly Diagnostic[]): void;
  setTheme(mode: ThemeMode): void;
  /** Selects [from, to) and scrolls it into view. `to` defaults to `from`. */
  select(from: number, to?: number): void;
  focus(): void;
  destroy(): void;
}

export function createEditor(parent: HTMLElement, options?: EditorOptions): EditorHandle;

/** `document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light'`
 *  — the attribute Base.astro:63-73 pre-paints and ThemeToggle.astro:9-16 flips. */
export function currentThemeMode(): ThemeMode;

/** Exported for Phase 2/5 reuse; not consumed elsewhere in Phase 1. */
export const circStreamParser: StreamParser<CircTokenState>;
export const circLanguage: StreamLanguage<CircTokenState>;
```

Implementation contracts that later phases depend on:

- **The `StreamParser` adapter.** `token(stream, state)` reads `stream.string` and `stream.pos` (both public and mutable — `@codemirror/language/dist/index.d.ts:1017-1030`), calls `nextToken(stream.string, stream.pos, state)`, assigns `stream.pos = end`, and returns `tag`. `stream.start` is set by CodeMirror's own `readToken` before each call and read after it (`@codemirror/language/dist/index.js:2483-2491` and `:2452`), so assigning `pos` is the whole contract. `readToken` throws `"Stream parser failed to advance stream."` if `stream.pos` does not grow — hence `nextToken`'s advance guarantee and its `invalid` catch-all at step 13.
- `startState`, `copyState` and `languageData: { commentTokens: { line: '//' } }` are on the spec. The last one is what makes `Mod-/` (`toggleComment`, bound in `defaultKeymap` at `@codemirror/commands/dist/index.js:1814`) comment circ correctly; it is read as `state.languageDataAt('commentTokens', pos, 1)` (`@codemirror/commands/dist/index.js:61`).
- **One `Compartment` for the theme** (`@codemirror/state/dist/index.d.ts:732-748`). Its content is `[EditorView.theme(spec, { dark }), syntaxHighlighting(HighlightStyle.define(specs))]`, where `specs` maps each `TagSpec.tag` string through `tags` plus modifiers and copies the spec's remaining fields verbatim — `color`, and whichever of `fontStyle` / `fontWeight` / `textDecoration` `styleSpecs` set. Those keys land in CSS as written (`TagStyle` is `[styleProperty: string]: any`, `@codemirror/language/dist/index.d.ts:914-930`, kebab-cased by style-mod at `style-mod/src/style-mod.js:41`), which is why the TextMate→CSS split happens in `circ-editor-theme.ts` and not here. `EditorView.theme` is `@codemirror/view/dist/index.d.ts:1403-1407`, `HighlightStyle.define` is `@codemirror/language/dist/index.d.ts:864-882` and `syntaxHighlighting` is `:891-897`. `setTheme(mode)` dispatches `themeCompartment.reconfigure(...)`. The view is **never** destroyed and rebuilt for a theme flip — unlike the canvas, which has no choice (`circ-renderer` captures its theme at construction, `canvas.ts:72`).
- **The theme spec *rebuilds* the lint decorations; it does not recolour them.** `@codemirror/lint` bakes its colours into SVG data URIs, not into CSS colour properties, so a `color:` / `textDecorationColor:` override is a silent no-op. `.cm-lintRange-error` and `.cm-lintRange-warning` are `backgroundImage: underline('#f11')` / `underline('orange')` (`@codemirror/lint/dist/index.js:678-679`), where `underline(color)` (`:645-647`) wraps a wavy path in `svg(...)` (`:642-644`), which `encodeURIComponent`s the markup into a `url('data:image/svg+xml,…')`. `circ-editor.ts` therefore ships its own `underline(color)` helper — the same path `m0 2.5 l2 -1.5 l1 0 l2 1.5 l1 0`, `stroke-width=".7"`, `fill="none"`, `width="6" height="3"`, URL-encoded the same way — and the theme spec sets `'.cm-lintRange-error': { backgroundImage: underline(palette.errorUnderline) }` and `'.cm-lintRange-warning': { backgroundImage: underline(palette.warningUnderline) }`. `EditorView.theme` output outranks a package `baseTheme` (`:648`), so no `!important` is needed. **The gutter markers are left at their defaults in this phase**: `.cm-lint-marker-warning` (`:890-892`) and `.cm-lint-marker-error` (`:893-895`), inside `lintGutterTheme` (`:876`), are `content:` SVG data URIs whose colours are baked into a `fill` *and* a `stroke` on the path (`.cm-lint-marker` itself is `:883-886`; `-info` is `:887-889`; the class string is built at `:767`), and `EditorPalette` carries one hex per severity, not two. The slice-4 STATUS entry says so explicitly rather than leaving it to be discovered.
- **`setDoc` does not re-enter `onChange`.** A module-level `const external = Annotation.define<boolean>()` (`@codemirror/state/dist/index.d.ts:771`) is attached to the replacing transaction, and the update listener skips any update whose transactions carry it (`Transaction.annotation`, `:970`).
- **Extension set** (non-compact): `lineNumbers()`, `highlightActiveLine()`, `highlightActiveLineGutter()`, `history()`, `keymap.of([indentWithTab, ...defaultKeymap, ...historyKeymap])`, `lintGutter()`, `EditorState.tabSize.of(2)`, `indentUnit.of('  ')`, `EditorView.lineWrapping`, `EditorView.contentAttributes.of({ 'aria-label': ariaLabel })`, `EditorView.updateListener.of(...)`, the language, the theme compartment, and — when `readOnly` — `EditorState.readOnly.of(true)` plus `EditorView.editable.of(false)`. Compact drops the first three and `lintGutter()`.
- **Tab accessibility.** `indentWithTab` is `{ key: 'Tab', run: indentMore, shift: indentLess }` (`@codemirror/commands/dist/index.js:1824`), which traps Tab. `defaultKeymap` already binds `Ctrl-m` (`Shift-Alt-m` on macOS) to `toggleTabFocusMode` (`:1816`), CodeMirror's own escape hatch. The pane label gains a static hint naming that shortcut, so the editor is not a keyboard trap. This preserves today's behaviour (`Playground.astro:130-136` binds Tab to two spaces) rather than regressing it.

### `site/src/scripts/circ-diagnostics.ts`

```ts
import { byteColToUtf16 } from '../utils/columns.ts';
import type { SplitFile } from '../utils/split-files.ts';

/** 1-based line, 1-based BYTE column, END EXCLUSIVE.
 *  Proven by tests/fixtures/expected-analyze/clean.json: the symbol `a` of
 *  `input a` is {start_line:1,start_col:7,end_line:1,end_col:8} and `a` is the
 *  7th byte of a 7-byte line. Contract: DOCS/analyze-api.md:60-70. */
export interface AnalyzeRange { start_line: number; start_col: number; end_line: number; end_col: number }
export interface AnalyzeRelated { file_id: number; range: AnalyzeRange; message: string }

export interface AnalyzeDiagnostic {
  file_id: number;
  severity: 'error' | 'warning';
  code: string;                    // E001-E018, W001-W003, or 'syntax'
  range: AnalyzeRange;
  message: string;
  related?: AnalyzeRelated[];      // DOCS/analyze-api.md:48,56
}

export interface AnalyzeSymbol {
  file_id: number;
  name: string;
  kind: 'input' | 'output' | 'and' | 'not' | 'led' | 'rom' | 'ram' | 'instance';
  width: number;
  addr_width?: number;             // rom/ram only — DOCS/analyze-api.md:57
  range: AnalyzeRange;             // dropped by Playground.astro:80 today
}

export interface AnalyzeReference {
  file_id: number; range: AnalyzeRange;
  target_file: number; target_range: AnalyzeRange; hover: string;
}

export interface Analysis {
  files: { file_id: number; path: string }[];
  diagnostics: AnalyzeDiagnostic[];
  symbols: AnalyzeSymbol[];
  references: AnalyzeReference[];  // omitted by Playground.astro:77-81 today
}

/** Line texts and their absolute UTF-16 start offsets, computed once per doc. */
export interface DocIndex { readonly lines: readonly string[]; readonly starts: readonly number[]; readonly length: number }
export function indexDoc(doc: string): DocIndex;

/** `/playground/<name>.circ` → `<name>.circ`. Returns null for `<builtin>/…`
 *  (DOCS/analyze-api.md:55) and for anything outside PLAYGROUND_DIR. */
export function fileNameFor(analysis: Analysis, fileId: number): string | null;

/** File-local 1-based line → 0-based line in the combined document, via
 *  SplitFile.startLine (split-files.ts:10-11). Null if the file is not open. */
export function docLine(files: readonly SplitFile[], name: string, fileLine1: number): number | null;

/** Absolute UTF-16 offset of (0-based doc line, 1-based byte column), clamped
 *  to the line's end and to the document's end. */
export function offsetAt(index: DocIndex, docLine0: number, byteCol1: number): number;

/** Both ends of one analyze range, or null when the file has no buffer.
 *  Guarantees `from <= to <= doc.length`, and widens an empty span by one
 *  code point when the line has room so the squiggle is visible. */
export function rangeToSpan(
  index: DocIndex, files: readonly SplitFile[], analysis: Analysis,
  fileId: number, range: AnalyzeRange,
): { from: number; to: number } | null;

export interface MappedDiagnostic {
  /** Absolute UTF-16 span in the combined document — or NULL when the compiler
   *  blamed a file with no editor buffer (`<builtin>/…`, or anything outside
   *  PLAYGROUND_DIR). Nullable so the list can stay total: `mapDiagnostics`
   *  returns one entry per analyze diagnostic, and `toLintDiagnostics` is what
   *  drops the buffer-less ones before they reach @codemirror/lint. */
  from: number | null; to: number | null;
  severity: 'error' | 'warning';
  code: string;
  message: string;
  /** For the list row: the file the compiler blamed — the playground-local name
   *  from `fileNameFor`, or the raw `files[].path` when that returns null — and
   *  the compiler's own FILE-LOCAL position. `line` is `range.start_line`
   *  verbatim; `column` is `byteColToUtf16(lineText, range.start_col)` when the
   *  file has a buffer and the raw `range.start_col` when it does not. This is
   *  a deliberate label change from today's combined-document line
   *  (`Playground.astro:286,303`) — `<file>:<line>:<col>` only means anything
   *  file-locally — and `docLine` plus `from`/`to` are what keep the jump
   *  target and the old label reproducible. */
  fileName: string; line: number; column: number;
  /** 0-based line in the combined document: exactly what today's
   *  `locate().line0` returns (`Playground.astro:286`), i.e.
   *  `file.startLine + range.start_line - 1`. Null whenever `from` is null. */
  docLine: number | null;
}
export function mapDiagnostics(doc: string, files: readonly SplitFile[], analysis: Analysis): MappedDiagnostic[];

/** Structurally a @codemirror/lint `Diagnostic` (from/to/severity/message/source
 *  — @codemirror/lint/dist/index.d.ts:9-49) WITHOUT importing the package, so
 *  this module stays DOM-free and bun-test-importable. circ-editor.ts does the
 *  (structural) hand-off. */
/** Filters out every entry whose span is null (no editor buffer) and narrows
 *  the rest, so the return type is non-nullable. */
export function toLintDiagnostics(
  mapped: readonly MappedDiagnostic[],
): { from: number; to: number; severity: 'error' | 'warning'; message: string; source: string }[];
```

Clamping rules, each of which is a test case:

1. A `file_id` whose path is `<builtin>/…` (`DOCS/analyze-api.md:55`) or is not under `/playground/` yields `null` from `fileNameFor`, so `rangeToSpan` returns `null` and the `MappedDiagnostic`'s `from` / `to` / `docLine` are all `null`. It is **still produced** — `mapDiagnostics` returns one entry per analyze diagnostic, with `fileName` set to the raw `files[].path` and `line` / `column` set to the raw `start_line` / `start_col` — so the list stays total, matching today's fallback at `Playground.astro:303`. `toLintDiagnostics` is the only place such entries are dropped. Expect more of them after Phase 0, since implicit builtins are resolved on the compile route too (`PLANS_PROMPT.md:154`).
2. `end_line` past the document's last line clamps to the last line; `to` never exceeds `doc.length`.
3. `start_col` / `end_col` past a line's byte length clamp to that line's end — `byteColToUtf16` already does this (`columns.ts:16`), and `offsetAt` adds the absolute clamp.
4. After clamping, `to < from` becomes `to = from`.
5. `from === to` widens to `to = from + 1` when `from` is not at a line end; otherwise it stays zero-width and CodeMirror renders a point marker (`cm-lintPoint`, `@codemirror/lint/dist/index.js:454`).

### Island state (`Playground.astro`)

```ts
// Added to the existing `state` object at Playground.astro:105-114.
// `gen`, `files`, `analysis`, `diagnostics`, `artifact`, `tab`, `version`,
// `simulateEnabled` keep their current meaning and their current types.
const state = {
  /** The pipeline's single source of truth. Initialised from the server-
   *  rendered textarea, written by the editor's onChange, read by fire(),
   *  locate() and renderDiagnostics(). Never read off the DOM. */
  source: '' as string,
  mapped: [] as MappedDiagnostic[],
  // …existing fields unchanged…
};

let editor: EditorHandle | null = null;   // null until the chunk resolves, or forever on failure
```

## Execution & Concurrency Model

This phase is **fully synchronous on the main thread**. It introduces no worker, no timer, no queue and no shared mutable state beyond `state.source` and `editor`, both owned by the single `init(el)` closure at `Playground.astro:90`. The two pieces of asynchrony are both pre-existing or trivially bounded:

1. **The dynamic `import('../scripts/circ-editor.ts')`.** Kicked off once, from `requestIdleCallback` (falling back to `setTimeout(…, 0)`), owned by a module-scoped promise so a second call cannot double-mount — the same `??=` memo pattern `Playground.astro:347-348` and `LiveCanvas.astro:41-46` already use. Until it resolves, the `<textarea>` is the live editing surface and `state.source` tracks it through its `input` listener. On resolve, `createEditor` is handed `state.source`, the textarea is removed from the DOM, and the host is unhidden. On reject, the status line reads `Rich editor unavailable; using the plain text box.`, `editor` stays `null`, and every fallback path below stays live — the page never ends up with no editing surface.

   **Loading this on idle is a deliberate, recorded exception to `DOCS/PLANS_PROMPT.md:32`** ("Nothing heavy loads before interaction", which names dynamic `import()` **/ first-focus** and cites `LiveCanvas.astro:41-46` and `Playground.astro:347-348,458`, every one of them gated on a click or a focus). The exception is granted because on `/playground` the editor *is* the page — a first-focus gate would show a bare `<textarea>` to every visitor who reads before typing, which is the one thing this phase's Goal exists to remove — and because the chunk is the only heavy thing here that a reader cannot see is missing. It does **not** extend to `libcirc.wasm`: `ensureReady()` keeps its first-focus gate, now on the editor host's `focusin`, so the wasm module still loads only on interaction. The exception is recorded as `### The editor chunk loads on idle, not on interaction` in `DOCS/decisions/playground.md` and named in slice 1's STATUS entry alongside the measured chunk size. Phase 7's `<LiveEditor>` inherits **no** part of it: a docs page is not the playground, and that phase gates its own activation.
2. **The existing `LibcircClient` round-trips.** `client.call('analyze' | 'compile' | 'preview' | 'truth_table', …)` still runs in the worker that owns the wasm instance; nothing on the main thread instantiates `libcirc.wasm`. `DEBOUNCE_MS = 250` and the single `state.gen` counter are unchanged.

**One new staleness guard, and it is required.** `fire()` captures `const snapshot = state.source` before building the request. The existing `if (gen !== state.gen) return` checks (`:178`, `:195`) only fire once a *later* `fire()` has run, which cannot happen until 250 ms after the next keystroke — so a reply can arrive while the document has already moved on. Offsets computed against `snapshot` would then be silently wrong, because `@codemirror/lint` maps registered diagnostics forward through subsequent changes (`lintState.update`, `@codemirror/lint/dist/index.js:151-152`) and has no way to know these were computed against an older base. Therefore: `mapDiagnostics(snapshot, splitFiles(snapshot), analysis)`, and **`editor.setDiagnostics(...)` is skipped entirely when `snapshot !== state.source`** — a fresher `fire()` is already scheduled and will produce correct offsets. The diagnostics *list* still renders (it carries file-local positions, which do not go stale in the same way). This guard is a Phase 1 addition and belongs in the STATUS entry and in `DOCS/PLANS_PROMPT.md`'s Recurring Traps under "Pillar 4(d)".

No background work, no locks, no channels. `document.documentElement.dataset.theme` is read but never written — `ThemeToggle.astro:9-16` owns it, and the `MutationObserver` at `Playground.astro:452-455` is the only observer.

## Persistence & I/O

This phase has **no persistence**. `localStorage` is neither read nor written; the `circ.playground.v1` envelope of decision 7 is created in Phase 3 slice 3, and nothing here anticipates it.

External I/O, all pre-existing in kind:

- **The editor JavaScript chunk** — one extra HTTP request for a Vite-emitted chunk, issued on idle after first paint of `/playground` only (the stated exception to `PLANS_PROMPT.md:32` in *Execution & Concurrency*, item 1). It is not in any page's eager module graph, which is what `site/test/bundle-graph.test.ts` (Phase 0) asserts for `Base.astro` / `Nav.astro` / `Footer.astro` without needing a build.
- **`site/public/wasm/libcirc.wasm`** — fetched by the worker on first `client.init()`, unchanged (`libcirc.worker.ts:51`).
- **`localStorage.theme`** — read only by `Base.astro:63-73`'s pre-paint script and written only by `ThemeToggle.astro:14`; neither is touched here.

No crash-recovery contract applies: the editor's document is transient in this phase, and losing it on reload is the current behaviour.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each. Slice titles carry `DOCS/PLANS_PROMPT.md:79`'s five pre-agreed seams for Phase 1 in their agreed order; the Deliverable column is this plan's refinement of them, and from here this table is authoritative.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Install + spike + two-line editor | `bun add --exact` the six packages into `site/package.json` / `site/bun.lock` at the versions in **New dependencies**. Create `site/src/scripts/circ-editor.ts` declaring the **full** `EditorOptions` / `EditorHandle` surface of *Data & State*, with `ThemeMode` declared locally in this file (`export type ThemeMode = 'light' \| 'dark';`) and re-exported — slice 3 moves the declaration into `circ-editor-theme.ts` and re-exports it from here, so no consumer's import ever changes and slice 1 does not depend on a module slice 3 creates. Seed the theme `Compartment` with `EditorView.theme({}, { dark: currentThemeMode() === 'dark' })` and wire `setTheme(mode)` to reconfigure it: an empty spec, but the `{ dark }` flag alone selects CodeMirror's dark base variant (`&dark .cm-content` `@codemirror/view/dist/index.js:6853`, `&dark .cm-selectionBackground` `:6871`, `&dark .cm-activeLine` `:6934`, `&dark .cm-gutters` `:6953`), so the editor is not a light box inside a `--pane-bg: #0c0517` pane for the two slices before the derived palette lands. `setDiagnostics(list)` already dispatches `setDiagnostics(view.state, list)`, which works without `lintGutter()` because the transaction spec enables the lint state itself (`maybeEnableLint`, `@codemirror/lint/dist/index.js:134-138`). The language, the compartment's real content and the diagnostics producer are slices 2, 3 and 4. Create `site/test/codemirror-pin.test.ts`. In `Playground.astro`, add the `.pg-editor-wrap` / `#pg-editor` markup, introduce `state.source` and route `fire()` / `locate()` / `renderDiagnostics()` / `pick` through it, add the idle dynamic import with its reject fallback, extend the existing `MutationObserver` at `:452-455` with `editor?.setTheme(currentThemeMode())`, and move the first-focus `ensureReady()` hook off the textarea onto the editor host's `focusin`. Add `.pg-cm*` geometry to `global.css`. Read `site/scripts/check-bundle.ts` as Phase 0 shipped it, run `bun --bun run build` + `bun run bundle`, and record in STATUS the measured raw and gzip size of the emitted CodeMirror chunk, the verified extension names used, and the verdict of the pre-agreed 20 % rule **as corrected under *Open Questions*** — if the rule fires, slice 1 measures the keymap-only split (`defaultKeymap` and `historyKeymap` hand-rolled, `history()` and `historyField` kept, since Phase 2's per-file undo is built on them, `PHASE_2_file_tabs.md:232,236`) and applies it if that clears the band; `history()` is never dropped, and slice 1 opens no human gate of its own — **without editing `site/bundle-budget.json`**, per *Open Questions*. Delete `PLANS_PROMPT.md:190` from that file's "Open items" once STATUS re-states the names against the real `site/node_modules`. Append `### The editor is CodeMirror 6 with a hand-written StreamLanguage` (the six exact-pinned packages, no meta-package, no autocomplete/search) and `### The editor chunk loads on idle, not on interaction` (with the measured size and the `PLANS_PROMPT.md:32` exception) to `DOCS/decisions/playground.md`, creating and registering it only if Phase 0 did not. | `bun test` from `site/`: new `codemirror-pin.test.ts` asserts all six packages appear in `package.json.dependencies` with no `^`/`~` and resolve in `bun.lock`; the Phase 0 `bundle-graph.test.ts` still passes (no `@codemirror/*` reachable from `Base`/`Nav`/`Footer`). `bun --bun run build` green. `bun run bundle` green with `/playground`'s eager gzip still under its committed ceiling. **Manual, recorded unrun:** the editor mounts, accepts two lines, and the pipeline still compiles them. |
| 2 | `circ-tokens.mjs` + both consumers + tokenizer test | Create `site/src/utils/circ-tokens.mjs` (full state machine and both alternation strings). Rewrite `circ-lang.mjs:49` and `:57`'s `match` literals as `KEYWORD_MATCH` / `BUILTIN_MATCH`, which adds `rom` and `ram`; repoint the stale path comment at `circ-lang.mjs:8-9`. Add `circStreamParser` / `circLanguage` to `circ-editor.ts` and put the language into the extension set. Create `site/test/circ-tokens.test.ts` and `site/test/circ-editor-parser.test.ts`. Steps 4, 5 and 8 of the tokenizer read `OPERATORS` longest-first rather than repeating the three literals. Ship the JSDoc typedefs that make `circ-tokens.mjs`'s exported shapes importable as types (see the note under its API block) and record in STATUS that this is the first `.mjs` in `site/src/utils/` to carry them. Append `### One token table, two consumers` to `DOCS/decisions/playground.md` (`circ-tokens.mjs` feeds both `circ-lang.mjs`'s TextMate `match` strings and the CodeMirror tokenizer; `rom`/`ram` were the bug; the three operator scopes deliberately stay three literals). | `bun test`: `circ-tokens.test.ts` — `tokenizeLine` partitions every line of all 10 `examples[].source` and all 7 `tour[].source` with no gap and no overlap and concatenates back to the line; `nextToken` advances at every position of every such line and for `\t`, `%`, `@`, `#`, `;`; `rom`, `ram` and `bus` tokenize as `typeName`; `// half_adder.circ` tokenizes as one `comment`; `import xor "<builtin>/xor.circ"` yields `keyword`, `typeName`, `string`; `circLang.repository.type.patterns[0].match === BUILTIN_MATCH` and contains `rom` and `ram`; `circLang.repository.keyword.patterns[0].match === KEYWORD_MATCH`; `OPERATORS` is exactly `['<>', '..', '=']`, is sorted longest-first, and each entry is covered by exactly one of `circLang.repository.connection.patterns[0]` (`circ-lang.mjs:66`), `repository.operator.patterns[0]` (`:96`) and `repository.operator.patterns[1]` (`:97`), so an operator cannot be added to one grammar and not the other. New `circ-editor-parser.test.ts` — imports `circ-editor.ts` **headlessly** (see the callout under *New files*) and drives the adapter directly: for every line of all 17 shipped sources, feed `circStreamParser.token(stream, state)` a duck-typed `{ string, pos, start }` and assert `stream.pos` strictly increases on every call and that the return is `null` or a string, which is exactly the precondition `readToken` enforces by throwing (`@codemirror/language/dist/index.js:2483-2490`); plus `expect(() => StreamLanguage.define(circStreamParser)).not.toThrow()` and `expect(circStreamParser.languageData?.commentTokens).toEqual({ line: '//' })` (`languageData` is on the spec, `@codemirror/language/dist/index.d.ts:1173-1176`). `bun --bun run build` green (proves Shiki still accepts the grammar object at `astro.config.mjs:17` and `CodePreview.astro:41`). |
| 3 | The theme binding | Create `site/src/utils/circ-editor-theme.ts` (`ThemeMode`, `TAG_SCOPES`, `scopeStyle`, `styleSpecs`, `editorPalette`, `themeFor`) and move `ThemeMode`'s declaration there, re-exporting it from `circ-editor.ts` so no import changes. **Fill** the theme `Compartment` that slice 1 seeded with `EditorView.theme(...) + syntaxHighlighting(HighlightStyle.define(...))` — reconfigure in place, never destroy; the `MutationObserver` wiring is already done in slice 1 and is not touched here. Name the selection and caret selectors explicitly (`.cm-content { caretColor }`, `.cm-content ::selection`), since `drawSelection()` is not in the extension set. Create `site/test/circ-editor-theme.test.ts`. STATUS records the fourth-module justification, and `DOCS/decisions/playground.md` gains `### The editor palette is derived from the shiki themes` (including that justification against decision 15's three-module list). | `bun test`: `circ-editor-theme.test.ts` — `styleSpecs(shikiLight)` and `styleSpecs(shikiDark)` each return one spec per `TAG_SCOPES` entry and cover **every** tag `tokenizeLine` emits over all 17 sources (totality, computed in the test, not hard-coded); every `tag` string resolves through `@lezer/highlight`'s `tags` plus its modifiers; `keyword` is `#0a6634` light / `#1ee17d` dark (`shiki-themes.mjs:25,35`); `comment` is `#8a7e9a` / `#7d6e94` with `fontStyle: 'italic'` (`:21,30,46,74`); `editorPalette(shikiLight).background === '#e8def0'` and `editorPalette(shikiDark).background === '#1f1438'` (`:19,28`); `scopeStyle` throws for an absent scope. **The TextMate→CSS split is pinned, not assumed:** `expect(styleSpecs(shikiLight).find(s => s.tag === 'keyword')).toEqual({ tag: 'keyword', color: '#0a6634', fontWeight: 'bold' })` and the dark equivalent with `#1ee17d` — `fontWeight`, never `fontStyle`, because `shiki-themes.mjs:50,78` carry `fontStyle: 'bold'` and `font-style: bold` is invalid CSS; `expect(styleSpecs(shikiLight).find(s => s.tag === 'comment')).toEqual({ tag: 'comment', color: '#8a7e9a', fontStyle: 'italic' })`; and **no** spec in either theme carries a `fontStyle` value other than `'italic'`. `editorPalette(...).selection !== editorPalette(...).background` in both themes. `bun --bun run build` green. **Manual, recorded unrun:** toggling the theme recolours the editor without losing the cursor, the scroll position or the undo history. |
| 4 | Diagnostics → squiggles + gutter | Create `site/src/scripts/circ-diagnostics.ts` with the full type set and the six mapping functions. Add **`lintGutter()`** to `circ-editor.ts`'s extension set — and only that: `setDiagnostics` is not an extension but `setDiagnostics(state, diagnostics): TransactionSpec` (`@codemirror/lint/dist/index.d.ts:128`), and `EditorHandle.setDiagnostics(list)` already dispatches it from slice 1, self-installing the lint state through `maybeEnableLint` (`index.js:134-138`), so no `linter()` is needed. Add the `underline(color)` helper and the two `backgroundImage` rebuilds for `.cm-lintRange-error` / `-warning` to the theme spec (see the lint bullet under *Implementation contracts*); the gutter markers stay at their defaults and STATUS says so. In `Playground.astro`, replace the local `Range` / `Diagnostic` / `Analysis` interfaces (`:75-81`) with the imported ones, capture `snapshot` in `fire()`, and compute `state.mapped` at **both** producers — the analyze branch at `:183-185` and the compile status-1 branch at `:203-208`, the latter mapping the compile reply's own `Analysis` (it carries its own `files[]`, `DOCS/libcirc-api.md:66`, which `fileNameFor` needs) — pushing `toLintDiagnostics(state.mapped)` into the editor behind the `snapshot !== state.source` guard at each. Append `### Analyze offsets are mapped in a pure module` (byte column + `SplitFile.startLine` → absolute UTF-16 offset) to `DOCS/decisions/playground.md`, and add the staleness guard to `PLANS_PROMPT.md`'s Recurring Traps under Pillar 4(d). Create `site/test/circ-diagnostics.test.ts` with both its pure and its wasm-driven cases. | `bun test`: `circ-diagnostics.test.ts` pure cases — `offsetAt` on ASCII, on `éé x` and on `😀x` (the exact inputs `columns.test.ts:11-13` pins); a diagnostic in `tour[5]`'s `half_adder.circ` (`startLine: 1`) and one in its `root.circ` (`startLine: 9`) map to the right combined-document lines (the numbers `split-files.test.ts:15-16` already pins); a `<builtin>/xor.circ` `file_id` yields `null` from `fileNameFor`, still produces a `MappedDiagnostic` (null span, raw `start_line`/`start_col`, raw `files[].path` as `fileName`) and is absent from `toLintDiagnostics`'s output; `end_line` past EOF, `start_col` past EOL, and an inverted range all clamp inside `[0, doc.length]`; an empty range widens by one; `toLintDiagnostics` output has exactly `from`/`to`/`severity`/`message`/`source`; a `{files, diagnostics, symbols: [], references: []}` **status-1 compile body** maps identically to the same diagnostics arriving from `analyze`, and a source that analyzes with zero diagnostics but returns compile status 1 still yields a non-empty mapped list. Wasm-driven case (honours `SKIP_LIBCIRC_TEST=1` like `libcirc.test.ts:12`): `callOp(w, 'analyze', requestFor(splitFiles(src)))` over a deliberately broken single file, then `doc.slice(from, to)` equals the exact text the compiler's range names and `severity === 'error'`; the same over a two-file source whose error is in the **first** file, asserting `from` lands before `files[1].startLine`'s offset — the `startLine` bug a naive mapper gets wrong; and the same again with a `// é` comment padded ahead of the error, asserting the offset is unchanged in meaning. |
| 5 | The diagnostics list and its jump | Rewrite `renderDiagnostics()` (`Playground.astro:290-317`) over `state.mapped`, which **both** of its call sites — `:185` after analyze and `:205` after compile status 1 — must have refreshed first (slice 4). Each row is a button labelled `<file>:<line>:<col> <code> <message>` from the file-local `fileName`/`line`/`column`, carrying its severity class. **This deliberately replaces today's combined-document label** (`${loc.line0 + 1}:${loc.col}` with no filename, `Playground.astro:303`): `<file>:<line>:<col>` only means anything file-locally, `docLine` preserves the old number for the test, and `from`/`to` preserve the jump. Clicking calls `editor.select(from, to)` (which focuses and scrolls) or falls back to `setSelectionRange(from, to)` on the textarea when `editor === null`; a row whose span is `null` (a `<builtin>/…` file) renders with no click handler rather than vanishing from the list. Add a per-severity count line and keep the `No diagnostics.` empty state. Add `.pg-diag-warning` to the `.pg*` CSS block beside the existing `.pg-diag-error` (`global.css:642`). | `bun test`: extend `circ-diagnostics.test.ts` with the two rows the label change splits into — `list rows carry the compiler's own file-local position` and `the jump target does not regress` (see *Tests*), over both a single-file and a two-file source, plus the exact row string (`root.circ:1:1 E004 …`) pinned once. `bun --bun run build` and `bun run bundle` green. **Manual, recorded unrun:** clicking a diagnostics row focuses the editor with exactly that range selected, in both themes, and `Tab` still indents while `Ctrl-m` / `Shift-Alt-m` releases focus. |

Every slice ends green on `bun test` **and** `bun --bun run build` (Pillar 2's standing gate — plain `bun run build` fails on this machine), plus `bun run bundle` on slices 1, 4 and 5, whose changes move `/playground`'s **eager** module graph — slice 1 adds the island's idle `import()`, slice 4 adds the first runtime *static* import of a new module into the island (`circ-diagnostics.ts`, exactly what decision 14(a) gates), slice 5 rewrites the list. Slice 2 is not on that list: `circ-tokens.mjs` reaches the client only through `circ-editor.ts`'s dynamic `import()` and through `circ-lang.mjs`, which is build-time only (`astro.config.mjs:2` and `CodePreview.astro:3` are frontmatter). Running it on every slice is cheap and always acceptable. No slice touches Zig, so `zig build test-all` is not this phase's gate.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `codemirror packages are pinned exactly` | `site/test/codemirror-pin.test.ts` | Each of the six packages appears in `site/package.json`'s `dependencies` with a bare `x.y.z` version (no `^`, no `~`, no range) and has a resolution entry in `site/bun.lock`. |
| `tokenizeLine partitions every shipped source` | `site/test/circ-tokens.test.ts` | Over all 10 `examples[].source` and 7 `tour[].source`, every line's tokens are contiguous from 0 to `line.length` with no overlap, and their concatenated slices equal the line. |
| `nextToken always advances` | `site/test/circ-tokens.test.ts` | For every position of every shipped source line, and for `\t`, `%`, `@`, `#`, `;`, `nextToken(...).end > pos` — the precondition `@codemirror/language`'s `readToken` enforces by throwing (`index.js:2487-2490`). |
| `rom and ram tokenize as builtin types` | `site/test/circ-tokens.test.ts` | `rom code[8, 4](addr = pc.out)` yields `typeName` for `rom`; the same for `ram`; and for `bus`, `xnor`, `led`. |
| `the TextMate grammar is built from the token table` | `site/test/circ-tokens.test.ts` | `circLang.repository.type.patterns[0].match === BUILTIN_MATCH` and includes `rom`/`ram`; `circLang.repository.keyword.patterns[0].match === KEYWORD_MATCH`; `circLang.scopeName === 'source.circ'` and the `patterns` include order at `circ-lang.mjs:26-38` is unchanged. |
| `markers and builtin imports tokenize as expected` | `site/test/circ-tokens.test.ts` | `// half_adder.circ` is one `comment`; `import xor "<builtin>/xor.circ"` is `keyword`, `typeName`, `string`; `not n(in=a)` is `typeName`, `variableName.function`, `punctuation`, `propertyName`, `operator`, `variableName`, `punctuation`. |
| `the stream parser always advances` | `site/test/circ-editor-parser.test.ts` | Importing `circ-editor.ts` headlessly, `circStreamParser.token(stream, state)` over every line of all 17 shipped sources with a duck-typed `{ string, pos, start }`: `stream.pos` strictly increases on every call and the return is `null` or a string — the precondition `readToken` enforces by throwing `"Stream parser failed to advance stream."` (`@codemirror/language/dist/index.js:2483-2490`). |
| `the parser spec is accepted and carries its language data` | `site/test/circ-editor-parser.test.ts` | `StreamLanguage.define(circStreamParser)` does not throw, and `circStreamParser.languageData?.commentTokens` equals `{ line: '//' }` (`@codemirror/language/dist/index.d.ts:1173-1176`) — what makes `Mod-/` comment circ correctly. |
| `operators come from the token table` | `site/test/circ-tokens.test.ts` | `OPERATORS` is exactly `['<>', '..', '=']`, sorted longest-first, and each entry is covered by exactly one of `circLang.repository.connection.patterns[0]` (`circ-lang.mjs:66`), `repository.operator.patterns[0]` (`:96`) and `repository.operator.patterns[1]` (`:97`). |
| `every palette tag resolves through @lezer/highlight` | `site/test/circ-editor-theme.test.ts` | Each `TagSpec.tag`, split on `.`, has a base that is a non-function key of `tags` and modifiers that are function keys. |
| `the palette is total over the emitted tag set` | `site/test/circ-editor-theme.test.ts` | The set of non-null tags `tokenizeLine` produces over all 17 sources is a subset of `styleSpecs(shikiLight).map(s => s.tag)`, and the same for dark. |
| `the palette is the shiki palette` | `site/test/circ-editor-theme.test.ts` | `keyword` → `#0a6634` / `#1ee17d`; `comment` → `#8a7e9a` / `#7d6e94` with `italic`; `string` and `number` → `#8e4a0e` / `#e17d1e`; `operator` → `#6e49ab` / `#b097d1`; `invalid` → `#a83737` / `#ff6b8a`; `editorPalette(...).background` → `#e8def0` / `#1f1438`. `scopeStyle(theme, 'nope.not.a.scope')` throws. |
| `the TextMate fontStyle is split, not passed through` | `site/test/circ-editor-theme.test.ts` | `styleSpecs(shikiLight).find(s => s.tag === 'keyword')` equals `{ tag: 'keyword', color: '#0a6634', fontWeight: 'bold' }` and the dark one `{ …, color: '#1ee17d', fontWeight: 'bold' }` — never `fontStyle: 'bold'`, which style-mod would emit as the invalid `font-style: bold` (`style-mod/src/style-mod.js:41`); the `comment` spec equals `{ tag: 'comment', color: '#8a7e9a', fontStyle: 'italic' }`; and **no** spec in either theme carries a `fontStyle` value other than `'italic'`. |
| `the lint underline carries the palette colour` | `site/test/circ-editor-theme.test.ts` | `editorPalette(shikiLight).errorUnderline === '#a83737'` and `editorPalette(shikiDark).errorUnderline === '#ff6b8a'` (`shiki-themes.mjs:62,90`); `editorPalette(...).selection !== editorPalette(...).background` in both themes, so a selection is visible. |
| `the underline helper encodes its colour` | `site/test/circ-editor-parser.test.ts` | `underline(c)` (exported from `circ-editor.ts`, DOM-free) returns a `url('data:image/svg+xml,…')` string containing the URL-encoded `c` — so the colour that reaches `.cm-lintRange-error` is provable without a browser. |
| `offsetAt converts byte columns` | `site/test/circ-diagnostics.test.ts` | ASCII identity; `éé x` col 5 → the 3rd UTF-16 unit; `😀x` col 5 → the 3rd; past-end clamps to the line end — the same inputs `columns.test.ts:11-13` pins, now at absolute document offsets. |
| `docLine crosses file markers` | `site/test/circ-diagnostics.test.ts` | For `splitFiles(tour[5].source)`, a diagnostic on `half_adder.circ` line 1 maps to combined line 1 and one on `root.circ` line 1 maps to combined line 9 (`split-files.test.ts:15-16`). |
| `builtin files have no span but still have a row` | `site/test/circ-diagnostics.test.ts` | A `file_id` whose `files[].path` starts `<builtin>/` yields `null` from `fileNameFor`, still produces a `MappedDiagnostic` — `from`/`to`/`docLine` all `null`, `fileName` the raw `files[].path`, `line`/`column` the raw `start_line`/`start_col` — and is absent from `toLintDiagnostics`'s output. The list stays total, as it is today (`Playground.astro:303`). |
| `spans clamp and never invert` | `site/test/circ-diagnostics.test.ts` | `end_line` past EOF, `start_col` past EOL, `end_col < start_col`, and a range on an empty document all produce `0 <= from <= to <= doc.length`; an empty span widens by one where the line has room. |
| `toLintDiagnostics matches the lint Diagnostic shape` | `site/test/circ-diagnostics.test.ts` | Exactly the keys `from`, `to`, `severity`, `message`, `source`, with `severity` in `{'error','warning'}` (`@codemirror/lint/dist/index.d.ts:5,9-49`). |
| `list rows carry the compiler's own file-local position` | `site/test/circ-diagnostics.test.ts` | For a single-file and a two-file source, `mapDiagnostics(...)[i].{fileName,line,column}` equals `{ files[k].name, d.range.start_line, byteColToUtf16(lineText, d.range.start_col) }` — the position the compiler reported, **unshifted** by `startLine`. The rendered row is pinned once as an exact string (`root.circ:1:1 E004 …`), which deliberately replaces today's combined-line label at `Playground.astro:303`. |
| `docLine reproduces today's combined line` | `site/test/circ-diagnostics.test.ts` | For the same inputs, `mapDiagnostics(...)[i].docLine === locate(d).line0` and `.column === locate(d).col`, with `locate()` recomputed in the test from `file.startLine + range.start_line - 1` (`Playground.astro:286`). This is the only place the old number is still asserted. |
| `the jump target does not regress` | `site/test/circ-diagnostics.test.ts` | For the same inputs, `mapDiagnostics(...)[i].from === caretOffset(doc, loc.line0, loc.col)` for the `loc` above — so clicking a row still lands exactly where it lands today (`Playground.astro:309`). |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `maps an analyze diagnostic onto the exact source text` | `site/test/circ-diagnostics.test.ts`, wasm-driven, `describe.skipIf(process.env.SKIP_LIBCIRC_TEST === '1')` | `instantiateLibcirc(readFileSync('site/public/wasm/libcirc.wasm'))` → `callOp(w, 'analyze', requestFor(splitFiles(src)))` for a deliberately broken single-file source; `JSON.parse(text)` as `Analysis`; `mapDiagnostics(src, splitFiles(src), analysis)` produces at least one `severity === 'error'` entry whose `src.slice(from, to)` equals the substring the compiler's byte range names, computed independently in the test with `Buffer.byteLength`. |
| `maps a diagnostic in the first file of a two-file source` | same file | Same pipeline over `tour[5].source` with an error injected into `half_adder.circ`; the mapped `from` is strictly less than the offset of `splitFiles(src)[1].startLine`, and `src.slice(from, to)` is inside the first file's body. This is the assertion a mapper that forgets `SplitFile.startLine` fails. |
| `multi-byte padding does not shift the mapping` | same file | The same source with a `// éé 😀` comment line inserted above the error; `src.slice(from, to)` is unchanged. |
| `the grammar object still builds the site` | `bun --bun run build` | Shiki accepts `circLang` built from `circ-tokens.mjs` at `astro.config.mjs:17` and `CodePreview.astro:41`; the reference page (whose source `DOCS/language.md` carries 31 word-boundary `rom`/`ram` occurrences across 24 lines — `:237,243,568,574,638` among them — synced by `bun run sync` to `site/src/pages/reference.md`, i.e. route **`/reference`**, not `/reference/language`: `site/scripts/lib/site-config.ts:16-21` maps `src: 'language.md'` to `dst: 'reference.md'`, and `site/src/pages/reference/` holds only `getting-started.md`, `circuit-format.md`, `wasm-api.md` and `preview.md`) renders without a Shiki grammar error. |
| `no page eagerly loads CodeMirror` | `site/test/bundle-graph.test.ts` (Phase 0) + `bun run bundle` | No module reachable from `Base.astro`, `Nav.astro` or `Footer.astro` imports `@codemirror/*`; `/playground`'s eager graph stays under its committed raw/gzip ceilings and the editor chunk is reported as an ungated informational line. |

Run command, from `/Users/jeffersonmourak/circus/worktrees/v0.0.3/playground/site`:

```sh
bun test && bun --bun run build && bun run bundle
```

`bun test` alone runs every case above except the last two; `SKIP_LIBCIRC_TEST=1` skips only the three wasm-driven cases and is never the way to make a slice pass (`PLANS_PROMPT.md:135`).

**Manual checklist — record in each slice's STATUS entry as _unrun_ unless someone actually ran it** (no browser has ever been available in a session on this branch, `PLANS_PROMPT.md:136`):

1. `/playground` shows a syntax-highlighted editor; `rom code[8, 4](addr = pc.out)` colours `rom` like `and`.
2. Typing a source with an undeclared signal produces a red squiggle at the compiler's range and a marker in the lint gutter, in both themes.
3. Clicking a diagnostics row focuses the editor with that range selected and scrolled into view.
4. Flipping the theme recolours the editor in place — cursor, scroll and undo history survive.
5. `Tab` indents; `Ctrl-m` (`Shift-Alt-m` on macOS) releases the Tab trap and lets Tab move focus out of the editor.
6. `/reference` (the rendered `DOCS/language.md`; `site/src/pages/reference/` holds only `getting-started`, `circuit-format`, `wasm-api` and `preview`) renders `rom` / `ram` highlighted in its code blocks.
7. With JavaScript for the editor chunk blocked, the `<textarea>` still edits and still compiles.

## Open Questions / Spikes

The plan prompt's "Open items" list carries exactly **two** `TODO(phase1)` entries: the gzip size (`DOCS/PLANS_PROMPT.md:189`) and the extension names (`:190`). (The other two `TODO(phase1)` strings in that file, at `:37` and `:55`, are back-references inside decisions 1 and 14, not list entries — do not delete those.) `:190` is resolved below and is deleted from the list by slice 1, once its STATUS entry re-states the names against the real `site/node_modules`. `:189` needs slice 1's measurement and is deleted only when that number is in STATUS. **The three bullets after those two are new, phase-local spikes raised by this plan.** They share the `TODO(phase1)` label but are *not* entries in `DOCS/PLANS_PROMPT.md`; they are resolved in the slices named and there is nothing to delete from that file for them.

- **RESOLVED — `TODO(phase1)`: the exact CodeMirror 6 extension and API names.** Every name this plan uses is verified against a scratch install of the locked package set (`@codemirror/state 6.7.4`, `view 6.43.11`, `language 6.12.4`, `commands 6.11.0`, `lint 6.9.7`, `@lezer/highlight 1.2.3`), with `file:line` citations throughout **Data & State**: `StreamLanguage.define` / `StreamParser` / `StringStream` (`language/dist/index.d.ts:1194-1200,1128-1180,1017-1113`), `HighlightStyle.define` / `TagStyle` / `syntaxHighlighting` (`:864-882,914-930,891-897`), `Compartment.of` / `.reconfigure` (`state/dist/index.d.ts:732-748`), `Annotation.define` and `Transaction.annotation` (`:771,970`), `EditorSelection.range` and `TransactionSpec.scrollIntoView` (`:499,891`), `EditorState.create` / `.tabSize` / `.readOnly` (`:1193,1208,1242`), `Text.line` / `Line.from` (`:47,119-136`), `EditorView.theme` / `.baseTheme` / `.updateListener` / `.editable` / `.contentAttributes` / `.lineWrapping` / `dispatch` / `focus` / `destroy` (`view/dist/index.d.ts:1403,1422,1275,1284,1435,1445,835,1112,1124`), `keymap` / `lineNumbers` / `highlightActiveLine` / `highlightActiveLineGutter` (`:1576,2395,1687,2401`, all in the export list at `:2416`), `defaultKeymap` / `history` / `historyKeymap` / `indentWithTab` (`commands/dist/index.d.ts:649,102,153,656`), `setDiagnostics` / `lintGutter` / `Diagnostic` / `Severity` (`lint/dist/index.d.ts:128,185,9-49,5`), and `tags` with its `function` modifier (`@lezer/highlight/dist/index.d.ts:207-572,551`). Slice 1's STATUS entry re-states the list against `site/node_modules` after the real `bun add`, which is what makes later phases' CodeMirror claims non-provisional.
- **PARTIALLY RESOLVED — `TODO(phase1)`: the real gzip size of the locked CodeMirror package set.** The package set and its versions are now fixed and verified; the *bundled* size still needs a build, which this planning session may not run. **Spike (slice 1):** run `bun --bun run build` then `bun run bundle` and read the emitted chunk sizes out of `dist/`. Record the CodeMirror chunk's raw and gzip bytes in STATUS. The pre-agreed rule fires as written — **if the measurement lands within 20 % of the 120 KB gzip ceiling, the drop is decided before Phase 2 starts, not after** — but its *content* has changed since `PLANS_PROMPT.md:189` was written. That line assumed dropping `@codemirror/commands` meant hand-rolling two keymaps. `DOCS/PLANS/PHASE_2_file_tabs.md:218-239` has since made that package's `history()` / `historyField` **load-bearing** for per-file undo: "Undo history is a `StateField` (`historyField`, `commands/dist/index.d.ts:110`), so one state per file *is* per-file undo, for free and by construction" (`:236`), and its name table pins `history`, `historyField` and `historyKeymap` (`:232`). Hand-rolling a keymap is an afternoon; hand-rolling an undo `StateField` that maps through `ChangeSet`s is a re-plan of Phase 2's document registry. **Corrected pre-agreed rule, no human gate:** if the measurement lands within 20 % of the 120 KB gzip ceiling, slice 1 measures the keymap-only split — `defaultKeymap` and `historyKeymap` hand-rolled, `history()` and `historyField` kept, since Phase 2's per-file undo is built on them (`PHASE_2_file_tabs.md:232,236`) — and applies it if it clears the band. `history()` is never dropped. Only if the keymap-only split still leaves the number inside the band does slice 1 stop, and that stop is reported as a phase-boundary escalation under `DOCS/PLANS_PROMPT.md:93`, not as a new in-phase gate; Phase 5's renderer push stays the only hard stop inside a phase. No ceiling is raised silently; any raise is argued in STATUS with the measured number.
- **RESOLVED — `TODO(phase1)`: how does Phase 0's `site/scripts/check-bundle.ts` account for a lazily imported chunk?** It reports it and never gates it, and the sibling phase plan is authoritative here (`PLANS_PROMPT.md:77`) even though the files do not exist in this tree yet. `DOCS/PLANS/PHASE_0_builtins_and_budget.md:133-159` fixes `site/bundle-budget.json` as `{ version, default, routes, baseline }`, keyed by **route** — there is no named lazy-chunk key anywhere in the schema — and `:167-178` declares `PageGraph.lazy` as "Chunks reachable only through `import()`. Reported, never gated", with `:181` confirming that `import("…")` specifiers are collected into `lazy` and never followed. So `/playground`'s gated number will not contain CodeMirror, and the 120 KB ceiling does not by itself constrain the editor. **Per decision 14(a) (`PLANS_PROMPT.md:55`), which names "the docs editor's CodeMirror chunk" explicitly, the chunk stays an ungated informational line: do not add a budget row and do not edit `site/bundle-budget.json` in this phase.** Slice 1 reads the editor chunk's raw and gzip bytes off `bun run bundle`'s informational line, records them in STATUS, and evaluates the 20 % rule against that number by hand. If gating the chunk later looks worthwhile, that is a decision-14 amendment: it needs its own `###` entry in `DOCS/decisions/playground.md` carrying the measured number and the reason, not a slice-local call.
- **`TODO(phase1)`: which diagnostic code and span does the phase's headline browser check actually produce?** `DOCS/PLANS_PROMPT.md:63` promises "typing `not n(in=a)` with `a` undeclared and seeing a red squiggle under exactly `a`". The compiler emits **no per-identifier spans for validator codes**: `E001` is raised only for an unresolved component *type* and carries the whole declaration's span (`lib/validator/passes/name_resolution.zig:24`; `tests/fixtures/expected-diagnostics/E001_undeclared.txt` reports `2:1` for `mystery u1(in=a)`), `E004` carries the component span (`lib/validator/passes/required_input.zig:46`), and `E002` carries the narrower *connection* span (`lib/validator/passes/port_validation.zig:97,109`). So the squiggle will cover at least a whole connection or declaration, not a bare identifier, and the code may be `E002` or `E004` rather than `E001`. **Spike (slice 4, as a `bun test` case, not a browser session):** analyse `input b\nnot n(in=a)\noutput o(in=n.out)\n` against the committed `libcirc.wasm` and pin the observed `code` and `doc.slice(from, to)` in the test; then correct the manual-checklist wording in the slice-4 STATUS entry to name what the compiler actually reports. The editor's contract — the squiggle covers exactly the analyze range — is unaffected either way and is what the test asserts.
- **`TODO(phase1)`: does `input_pin` / `output_pin` belong in `BUILTIN_TYPES`?** `lib/ir/resolver.zig:63-64` recognises both as primitives and `lib/resolver/scan_imports.zig:33` reserves both, yet neither appears in `circ-lang.mjs:57`'s list, in `DOCS/language.md`, or in any shipped example or tour source (verified by grep). Adding them would change the rendering of every docs code block that happens to use those identifiers as names. **Spike (slice 2):** grep `DOCS/*.md` and `site/src/content/*.ts` for both names; if neither occurs (as it does not today), leave them out and record the omission in `circ-tokens.mjs`'s header comment with this reasoning, so the next maintainer does not rediscover it. This is deliberately not folded into decision 2's `rom`/`ram` fix, which is a bug; this would be a scope change.

Nothing else is open. Every module boundary, export name, type and test above is fixed by this document.
