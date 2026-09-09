# Phase 2 — Files as tabs

> **Dependencies:** `DOCS/PLANS/PHASE_0_builtins_and_budget.md` (the usage-aware builtin fast path, the regenerated artifacts, `bun run bundle` + `site/test/bundle-graph.test.ts` and the committed `site/bundle-budget.json`) and `DOCS/PLANS/PHASE_1_editor.md` (CodeMirror 6 installed and pinned, `site/src/scripts/circ-editor.ts`, `site/src/scripts/circ-diagnostics.ts`, `site/src/utils/circ-tokens.mjs`), both shipped and committed.
> **Warnings:** Read Phase 1's `DOCS/STATUS.md` entries before slice 3a — they are the only record of the real CodeMirror extension names and of `createEditor`'s handle shape (`DOCS/PLANS_PROMPT.md:37`, `:190`), and slice 3a modifies that file. Phase 1's pre-agreed re-scope rule (`DOCS/PLANS_PROMPT.md:189`) can remove `@codemirror/commands` *before this phase starts*; that package owns `history()` / `historyField` (`@codemirror/commands@6.11.0` `dist/index.d.ts:102,110`), which is what makes one `EditorState` per file give per-file undo for free. **That rule is Phase 1's to execute and Phase 2's only to read**: `TODO(phase1)` is resolved, recorded in STATUS and deleted from the Open items in the phase it names (`DOCS/PLANS_PROMPT.md:186`), so Phase 2 reads the verdict rather than re-deciding it, and drops, keeps or substitutes no package on its own authority — see `TODO(phase2)-B`. Do **not** smuggle decision 9's two-stage debounce forward: Phases 1 and 2 keep the page's single `DEBOUNCE_MS = 250` and its one `state.gen` counter (`site/src/components/Playground.astro:85`, `:105-106`), and the split is Phase 3's slice 5 (`DOCS/PLANS_PROMPT.md:63`). The file tab strip must not reuse the `.pg-tabs` class — that is the *output* tab strip (`Playground.astro:51`, styled at `site/src/styles/global.css:604-627`) — and must not touch `.lc-mount` (`global.css:477-525`), which `/` and `/examples` share through `LiveCanvas.astro:26`. `<builtin>/…` paths appear in `analyze.files` and have no editor buffer (`DOCS/analyze-api.md:55`), and Phase 0 makes many more of them appear on the compile route.

**Sibling-plan citations are by symbol, not by line.** Every `DOCS/PLANS/PHASE_N_*.md:<line>` reference in this file was written against that file as it stood when this plan was drafted; those files have since been revised and many of the line numbers no longer resolve. Locate each reference by the symbol or heading it names (`createEditor`, `EditorOptions`, `EditorHandle`, `onChange`, `setTheme`, `select`, `showDocument`, `setDocuments`, `mapDiagnostics`, `rangeToSpan`, `AnalyzeSymbol`, `Analysis`, `Stage`, `shouldCompile`, `outputsShouldClear`, `writeEnvelope`, `encodeShare`, `PageGraph`), never by the number, and re-verify the shape before coding against it.

## Goal

A reader opens tour step 6 in `/playground` and sees two file tabs — `half_adder.circ` and `root.circ`, the second carrying a `root` badge — above one editor. Clicking a tab swaps the editor to that file's own document, with its own selection and its own undo history; the other file's text is untouched. They can add a file (it lands *before* the root), rename it inline with live validation, delete it behind a two-press confirm, and reorder tabs by dragging or with `Alt+Arrow` — dropping a tab at the end is how the root changes. Each tab carries its own error/warning count, computed from `analyze.diagnostics[].file_id` through `analyze.files[].path`, and clicking a diagnostic that belongs to another file switches to that tab before placing the cursor. Everything is a view over the one interchange format: `site/src/utils/split-files.ts` gains `joinFiles`, the exact inverse of `splitFiles`, so all ten sources in `site/src/content/examples.ts` and all seven in `site/src/content/tour.ts` round-trip through the tab model byte for byte under `bun test`, and the multi-file artifact still names `ha1`, `ha2` and `half_adder` (`site/src/content/tour.ts:140-141`, asserted today at `site/test/libcirc.test.ts:70-81`).

## Scope

**In scope:**

- `joinFiles(files)` in `site/src/utils/split-files.ts`, with its marker-emission rules, its round-trip theorem, and `joinConflicts` naming the four file arrays the format — or the request builder — cannot represent.
- `isFileName(name)` in the same module — one predicate derived from the single `MARKER` regex (`split-files.ts:14`) so the tab UI and the splitter can never disagree about what a legal file name is.
- Widening `SplitFile` to extend a new `NamedFile { name, body }`, and widening `rootOf` / `requestFor` to accept `readonly NamedFile[]` so the tab array (which has no `startLine`) can drive the worker requests unchanged.
- A new pure module `site/src/scripts/file-tabs.ts`: the `FileTabsState` model and every reducer over it (`fromSource`, `toSource`, `select`, `setBody`, `addFile`, `renameFile`, `deleteFile`, `moveFile`), the rename validation, and `countsByFile`.
- A document registry in `site/src/scripts/circ-editor.ts`: one `EditorState` per file, swapped with `EditorView.setState`, with the theme compartment fanned out over every stored state and lint diagnostics addressable per file. Its index bookkeeping is extracted into a new DOM-free `site/src/scripts/doc-registry.ts` so `bun test` can reach it (the same move Phase 1 justified at `DOCS/PLANS/PHASE_1_editor.md:55`).
- The tab strip in `site/src/components/Playground.astro` and its `.pg-file*` CSS in `site/src/styles/global.css`: markup, ARIA (`role="tablist"` / `role="tab"` / `role="tabpanel"`, roving tabindex), mouse and keyboard operation, the `root` badge, the diagnostic-count badges, drag-and-drop reorder.
- Re-pointing the existing diagnostics list at per-file documents. Phase 1 already labels **every** row `<file>:<line>:<col> <code> <message>` unconditionally (`DOCS/PLANS/PHASE_1_editor.md:414-421`, pinned by its `list rows carry the compiler's own file-local position` test at `:531` and its `docLine reproduces today's combined line` test at `:532`) and that label does not change; what Phase 2 adds is the jump — a row whose file is not the active tab switches to that tab before it places the cursor.
- Appending Phase 2's exercised decisions to `DOCS/decisions/playground.md` (creating it and registering it under "Topics" in `DOCS/decisions/index.md` if Phase 0/1 has not).

**Explicitly deferred:**

- Persistence of the tab set or of `activeFile`. `site/src/utils/playground-store.ts` and the `circ.playground.v1` envelope are Phase 3 slice 3; `activeFile` is filled in Phase 4 (`DOCS/PLANS_PROMPT.md:48`). Phase 2 keeps everything in the island's closure.
- The workspace sidebar and `#src=` share links (Phase 4). The `<select id="pg-pick">` (`Playground.astro:29-37`) stays exactly as it is; Phase 2 only re-points its `change` handler at the tab model.
- Undo *across* file operations. Deleting a file is not undoable — `DOCS/PLANS_PROMPT.md:73` defers "undo across file operations beyond CodeMirror's per-file history", and per-file history is precisely what this phase's state-per-file model provides.
- Rewriting `import` statements when a file is renamed. A rename that breaks an import surfaces as the compiler's own `E009: import not found` on the importing tab; the status bar says so once, and nothing is rewritten.
- Folder hierarchies, drag-out-to-new-project, and any second interchange key. Flat files under `/playground/<name>` only (`split-files.ts:37`, `:42`).
- The two-stage debounce and per-stage sequence guards (Phase 3 slice 5), the splitters and the app layout (Phase 3), source linking (Phase 5), settings and ROM images (Phase 6), `<LiveEditor>` (Phase 7).
- Any Zig change. This phase touches no file outside `site/` and `DOCS/`.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| playground scripts | `site/src/scripts/file-tabs.ts` | The tab-state model and every reducer over it, plus `countsByFile`. Pure data: no DOM, no CodeMirror, no `localStorage`. Imports only `splitFiles` / `joinFiles` / `isFileName` / `PLAYGROUND_DIR` from `../utils/split-files.ts`. |
| site tests | `site/test/file-tabs.test.ts` | `bun test` over every reducer, over `countsByFile`, and one source-text case pinning the module's purity. |
| playground scripts | `site/src/scripts/doc-registry.ts` | Pure index bookkeeping over an opaque `T` — `insert`, `remove`, `move`, `activeAfter` — the half of the editor's document registry a `bun test` can reach. No `@codemirror/*`, no DOM. Exists for the reason Phase 1 gives at `DOCS/PLANS/PHASE_1_editor.md:55`: `circ-editor.ts` imports `@codemirror/view`, which touches `document`, so `bun test` cannot import it. |
| site tests | `site/test/doc-registry.test.ts` | `bun test` over `insert` / `remove` / `move` / `activeAfter`, plus a source-text case pinning the module's purity. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site utils | `site/src/utils/split-files.ts` | Add `NamedFile`; `SplitFile extends NamedFile` (keeping `startLine`, `:10-11`); add `joinFiles`, `isFileName`, `JoinConflict`, `joinConflicts`; widen `rootOf` (`:34`) and `requestFor` (`:40`) to `readonly NamedFile[]`. `MARKER` (`:14`), `splitFiles` (`:16-32`) and `PLAYGROUND_DIR` (`:37`) are unchanged. |
| playground scripts | `site/src/scripts/circ-editor.ts` (Phase 1) | Add the document registry: `setDocuments`, `showDocument`, `insertDocument`, `removeDocument`, `moveDocument`, `textOf`, `setDiagnosticsFor`, all built on `doc-registry.ts`. Widen Phase 1's `onChange?: (doc: string) => void` (`DOCS/PLANS/PHASE_1_editor.md:298`) by **appending** the document index — `(doc: string, index: number) => void` — so Phase 7's single-document consumer stays source-compatible. Make `setTheme(mode)` (`PHASE_1_editor.md:307`), which *is* Phase 1's theme-compartment entry point, fan out over every stored state, not only the visible one. Phase 1's `getDoc` / `setDoc` / `setDiagnostics` / `select` are kept and act on the visible document. |
| playground scripts | `site/src/scripts/circ-diagnostics.ts` (Phase 1) | **Unchanged in signature.** `indexDoc`, `docLine`, `rangeToSpan` and `mapDiagnostics(doc, files, analysis)` (`DOCS/PLANS/PHASE_1_editor.md:380`, `:388`, `:397`, `:427`) keep their `readonly SplitFile[]` parameter, and Phase 1's `site/test/circ-diagnostics.test.ts` — including its multi-file `startLine` case (`PHASE_1_editor.md:527`) — is untouched. Slice 3b calls it **once per tab** with a synthetic single-entry array: `indexDoc(tab.body)` per document (recomputed on `setBody`) and `mapDiagnostics(f.body, [{ name: f.name, body: f.body, startLine: 0 }], analysis)`, so `docLine` degenerates to the file-local line, the offsets are file-local for `setDiagnosticsFor(i, …)`, and a diagnostic blaming another file comes back with `from`/`to`/`docLine` all `null` — `mapDiagnostics` is **total** by contract (`DOCS/PLANS/PHASE_1_editor.md:442`, clamping rule 1: one entry per analyze diagnostic; only `toLintDiagnostics` drops the span-less ones). The per-tab call therefore returns the whole list every time, so the flat panel list is built by keeping, from tab `i`'s result, only the entries whose `from !== null` — those are tab `i`'s own — tagged with `i`; the span-less rows (`<builtin>/…`, or a `/playground/` path naming no current tab) are produced exactly once from a single extra pass over `analysis.diagnostics`, so the list stays total and no diagnostic is rendered N times on an N-tab project. |
| playground island | `site/src/components/Playground.astro` | Tab-strip markup directly above Phase 1's `.pg-editor-wrap` (`DOCS/PLANS/PHASE_1_editor.md:64`); the island owns `state.tabs: FileTabsState`. Phase 1's `state.source` (`PHASE_1_editor.md:454-461`) is **replaced** by `state.tabs` as the pipeline's single source of truth: `fire()` builds its request from `requestFor(state.tabs.files)` instead of `splitFiles(state.source)`, and any consumer that still needs the combined string calls `toSource(state.tabs)` on demand. Phase 1's `mapDiagnostics` / `state.mapped` path (`PHASE_1_editor.md:427`) runs once per tab (see the `circ-diagnostics.ts` row) so `from`/`to` are file-local, and the flat list the diagnostics panel renders keeps, from tab `i`'s result, only the entries whose `from !== null` — tagged with `i` — plus one pass for the span-less rows, which every per-tab call reproduces (the mapper is total) and which must therefore be emitted exactly once — Phase 1 has already retired `locate()` from that path (`PHASE_1_editor.md:501`, its slice 5: `renderDiagnostics()` is rewritten over `state.mapped`). `Playground.astro:99`'s unscoped `[role=tab]` query is narrowed to `.pg-tabs [role=tab]`. `state.files` (`:107`) becomes `state.tabs.files`; the `#pg-pick` handler (`:143-146`) rebuilds the tab set through `fromSource`; `rootInputBits()`'s root path (`:229`) reads `rootOf(state.tabs.files)`. |
| site styles | `site/src/styles/global.css` | A new `.pg-files*` block inside the `/* ---------- Playground ---------- */` section (after `.pg-pane-label`, `:557-569`). No edit to `.pg-tabs` (`:604-627`) and none to `.lc-mount` (`:477-525`). |
| site tests | `site/test/split-files.test.ts` | New `joinFiles` / `isFileName` / `joinConflicts` describe block; the existing three cases (`:6-32`) are untouched. |
| site tests | `site/test/libcirc.test.ts` | `compiles tour step 6 with the last // name.circ file as root` (`:70-81`) is re-pointed through `fromSource` + `requestFor` and gains the byte-identity assertion on `toSource`. |
| decisions | `DOCS/decisions/playground.md` | Append the headings this phase exercises (see slice 1). Created here if Phase 0/1 did not create it. |
| decisions | `DOCS/decisions/index.md` | Register `playground.md` under "Topics" alongside the seven existing topic files, if not already registered. |
| status | `DOCS/STATUS.md` | One entry per slice, per the template at `DOCS/PLANS_PROMPT.md:116-124`. |

**New dependencies:** None. Phase 2 adds no npm package; `site/package.json:15-21` is untouched except for whatever Phase 0/1 already put there.

## Data & State

### The interchange format's inverse (`site/src/utils/split-files.ts`)

```ts
/** The two fields a tab edits. `SplitFile` adds `startLine` for callers that
 *  map a diagnostic into a COMBINED document; tabs never need it. */
export interface NamedFile {
  name: string;
  body: string;
}

export interface SplitFile extends NamedFile {
  /** 0-based line index, in the combined text, of this file's first body line. */
  startLine: number;
}

// Unchanged, split-files.ts:14 — the one regex everything below is derived from.
const MARKER = /^\/\/\s+([\w_.-]+\.circ)\s*$/;

/** Exact inverse of `splitFiles`. See the round-trip theorem below. */
export function joinFiles(files: readonly NamedFile[]): string {
  return files
    .map((f, i) => (omitsMarker(f, i) ? f.body : `// ${f.name}\n${f.body}`))
    .join('\n');
}

/** Only a LEADING `main.circ` may go unmarked, and only when its first body
 *  line would not itself be read as a marker: `splitFiles` opens a file on a
 *  marker whenever `cur` is still null (split-files.ts:22), so an unmarked
 *  first body line matching MARKER would be eaten as the file name. */
function omitsMarker(f: NamedFile, i: number): boolean {
  return i === 0 && f.name === 'main.circ' && !MARKER.test(f.body.split('\n', 1)[0]);
}

/** Would `// ${name}` be read back as a marker naming exactly `name`?
 *  Derived from MARKER so the tab UI and the splitter cannot drift: this
 *  rejects '', 'foo', 'a/b.circ', '<builtin>/xor.circ' and 'a.circ ' (whose
 *  trailing space MARKER tolerates but does not capture). */
export function isFileName(name: string): boolean {
  const m = `// ${name}`.match(MARKER);
  return m !== null && m[1] === name;
}

/** File arrays the marker format — or the request builder — cannot represent.
 *  The first two are body-level; the last two are name-level: 'illegal-name'
 *  breaks splitFiles' ability to read the emitted marker back at all, and
 *  'duplicate-name' breaks requestFor's `/playground/<name>` keying
 *  (split-files.ts:42). Every entry names an index. */
export type JoinConflict =
  | 'blank-body' | 'marker-in-body' | 'illegal-name' | 'duplicate-name';

export function joinConflicts(
  files: readonly NamedFile[],
): { index: number; reason: JoinConflict }[] { /* rules below */ }
```

**Marker-emission rules.** Every file emits `// <name>` on its own line followed by its body, and the segments are joined with `'\n'` — that is exactly the line list `splitFiles` consumes (a marker line is consumed by the splitter and never becomes a body line, `split-files.ts:20-29`), so bodies keep their exact leading and trailing newlines. The one exception is `omitsMarker`: a first file literally named `main.circ` is emitted bare, because that is the name `splitFiles` invents when a source opens with no marker (`split-files.ts:26`).

`joinConflicts` also reports the two name-level failures the emission rules cannot survive. `'illegal-name'` at every index where `!isFileName(files[i].name)`, because `// ${name}` would not be read back as a marker naming exactly `name` — `joinFiles([{ name: 'foo', body: 'input a' }, { name: 'b.circ', body: 'x' }])` emits `// foo`, which `MARKER` does not match, so the two files silently merge. `'duplicate-name'` at every index after the first whose `name` already appeared, because `requestFor` keys its map by `/playground/<name>` (`split-files.ts:42`) and the earlier body would be dropped from the request with no diagnostic at all.

**Round-trip theorem (what slice 1 pins under `bun test`).**

1. *Left inverse.* For any `files` with `files.length >= 1` and `joinConflicts(files).length === 0` — which, because `joinConflicts` reports `'illegal-name'`, is exactly what guarantees `files.every((f) => isFileName(f.name))` — `splitFiles(joinFiles(files))` returns `files.length` entries whose `name` and `body` equal the inputs'. The name clause is load-bearing, not decorative: without it a hand-built array such as `[{ name: 'foo', body: 'input a\n' }, { name: 'b.circ', body: 'x\n' }]` falsifies the clause with zero reported conflicts, because `// foo` is not a marker and the two files merge.
2. *Right inverse, with three normalisations.* `joinFiles(splitFiles(s)) === s` for every string `s`, **except** the three shapes below. An implementer who encodes this clause as a property test over arbitrary strings must exclude all three, not only the first.
   (a) An `s` that opens with an explicit `// main.circ` marker whose *next* line is not itself a marker line; there the marker is dropped, because `NamedFile` carries no "the marker was written" bit and decision 3 (`DOCS/PLANS_PROMPT.md:39`) fixes the tab model at `{name, body}`. Both branches are pinned:
   `joinFiles(splitFiles('// main.circ\ninput a\n')) === 'input a\n'` (normalised) and
   `joinFiles(splitFiles('// main.circ\n// a.circ\ninput a\n'))` is byte-identical (the marker survives, because dropping it would promote line 1 to a marker).
   (b) An `s` whose **last** line is a marker line: that file's body-line list is empty (`split-files.ts:24`, `:31`), so `joinFiles` emits `// <name>\n` followed by an empty body and one trailing newline appears —
   `joinFiles(splitFiles('input a\n// b.circ')) === 'input a\n// b.circ\n'`.
   (c) An `s` carrying a non-canonical marker: `MARKER` (`split-files.ts:14`) tolerates any `\s+` after `//` and any trailing `\s*` but captures neither, so `'//   a.circ'` and `'// a.circ '` both re-emit as `'// a.circ'`.
   None of the 17 committed sources hits any of these — none opens with `// main.circ`, none ends on a marker line, and the only three marker lines in the corpus (`site/src/content/tour.ts:100`, `:129`, `:137`) are canonical — so all 17 round-trip byte-identically.
3. *`splitFiles` output is always conflict-free*, so (1) applies to it: a non-last file can never have a blank body (the marker that ended it is only honoured once the body holds a non-blank line, `split-files.ts:22`), and an unmarked first file's body line 0 can never match `MARKER` (it would have opened a file instead).

**The ambiguous cases, decided.**

| Case | Decision |
|---|---|
| A body whose first line is a marker-looking comment (`// notes.circ`) | Round-trips. The marker for the owning file is emitted first, so when the splitter reaches that line `cur.body` is still empty and the line stays an ordinary comment (`split-files.ts:22`). For an unmarked leading `main.circ`, `omitsMarker` refuses to omit and the marker is emitted, which fixes the same case. |
| A body with a marker-looking comment **after** non-blank content | **Unrepresentable.** The splitter will open a new file there. `joinConflicts` reports `'marker-in-body'` at that index. This is not a regression — the same text in today's `<textarea>` already splits — and it is how the format lets a reader hand-write a second file. The strip shows a warning on that tab and `.pg-status` (`Playground.astro:48`, already `aria-live="polite"`) names it. |
| A blank (or whitespace-only) body on a **non-last** file | **Unrepresentable**, with or without an emitted marker: the following marker is swallowed as a comment because the preceding body holds no non-blank line (`split-files.ts:22`, pinned by `site/test/split-files.test.ts:26-32`). `joinConflicts` reports `'blank-body'`. Slice 4 avoids reaching this state at birth by seeding a new file with `// <bare-name>` — one non-blank, non-marker line — and the warning covers the case where the reader deletes it. A blank **last** file is fine and round-trips. |
| A single unnamed `main.circ` (the shape of all 10 examples and 5 of the 7 tour steps — every `examples[].source`, plus tour steps 1-4 and 7; step 5 is the named-file row below and step 6 is the two-file case. The only `MARKER`-matching lines in the whole corpus are `site/src/content/tour.ts:100`, `:129` and `:137`; the three examples that *open* with a `//` comment — `mux-2to1` (`examples.ts:126`), `two-bit-adder` (`:189`), `sr-latch` (`:239`) — do not match `MARKER`, which requires a `.circ` suffix at end of line) | Emitted bare, no marker. `joinFiles([{ name: 'main.circ', body }]) === body`. |
| A single file with a real name (tour step 5, `site/src/content/tour.ts:100`, splits to one file named `half_adder.circ`) | Emits `// half_adder.circ` and round-trips byte-identically. The rule is *not* "skip the marker when there is one file". |
| Two files with the same name | Round-trips through `joinFiles`/`splitFiles`, but `requestFor` keys its map by `/playground/<name>` (`split-files.ts:42`) so the earlier body would be silently lost from the request, and `countsByFile`'s `Map<file_id, tabIndex>` (below) resolves the name to whichever tab it saw last. Blocked on add and on rename by `nameError` — but **not** on `fromSource`, which is `splitFiles` and happily returns two `a.circ` entries from hand-typed or pasted text (the free typing `DOCS/PLANS_PROMPT.md:148` warns a playground invites). That path is surfaced instead: `joinConflicts` reports `'duplicate-name'` at the later index, the tab shows the same warning marker slice 6 gives a `'marker-in-body'` tab, and `.pg-status` names it. |

### The tab model (`site/src/scripts/file-tabs.ts`)

```ts
import {
  splitFiles, joinFiles, isFileName, PLAYGROUND_DIR, type NamedFile,
} from '../utils/split-files.ts';

export type FileTab = NamedFile;               // { name, body } — no startLine

export interface FileTabsState {
  /** Never empty. The LAST entry is the root (split-files.ts:34). */
  readonly files: readonly FileTab[];
  /** 0 <= active < files.length. */
  readonly active: number;
}

export function fromSource(source: string): FileTabsState;   // splitFiles, active 0
export function toSource(s: FileTabsState): string;          // joinFiles(s.files)
export const rootIndex = (s: FileTabsState): number => s.files.length - 1;
export const activeFile = (s: FileTabsState): FileTab => s.files[s.active];

/** Selects a TAB. Always called qualified — `fileTabs.select(...)` — because
 *  `EditorHandle.select(from, to)` (PHASE_1_editor.md:309) places a CURSOR and
 *  the two sit on the same code path in slice 6. */
export function select(s: FileTabsState, index: number): FileTabsState;
export function setBody(s: FileTabsState, index: number, body: string): FileTabsState;

/** First free `file<N>.circ`, N from 1. */
export function nextFileName(files: readonly FileTab[]): string;
/** `// <name without .circ>\n` — one non-blank, non-marker line, so a fresh
 *  file is never a 'blank-body' conflict and never a 'marker-in-body' one. */
export function seedBody(name: string): string;

/** Inserts at `rootIndex(s)` so the root stays last, and activates the new tab. */
export function addFile(s: FileTabsState, name?: string): FileTabsState;

/** null when the rename is legal. Skips `index` itself, so renaming a file to
 *  its own name is not a duplicate. */
export function nameError(s: FileTabsState, index: number, name: string): string | null;
/** No-op when `nameError` is non-null; the caller shows the message. */
export function renameFile(s: FileTabsState, index: number, name: string): FileTabsState;

export const canDelete = (s: FileTabsState): boolean => s.files.length > 1;
/** No-op when `!canDelete`. active: `active > index ? active - 1 : min(active, len - 1)`. */
export function deleteFile(s: FileTabsState, index: number): FileTabsState;

/** `to` clamps to [0, len - 1]. The previously active FILE stays active. */
export function moveFile(s: FileTabsState, from: number, to: number): FileTabsState;

export interface TabCounts { errors: number; warnings: number }

/** Per-tab diagnostic counts. Structural parameter, not Phase 1's `Analysis`
 *  interface, so this module stays independent of where that type landed. */
export function countsByFile(
  files: readonly FileTab[],
  analysis: {
    files: readonly { file_id: number; path: string }[];
    diagnostics: readonly { file_id: number; severity: string }[];
  } | null,
): TabCounts[];
```

`countsByFile` builds `Map<file_id, tabIndex>` by keeping only `analysis.files[]` whose `path` starts with `${PLAYGROUND_DIR}/` and whose remainder names a current tab; every other `file_id` — `<builtin>/xor.circ` and friends (`DOCS/analyze-api.md:55`), and any path left over from a stale reply that named a since-renamed file — is dropped. A diagnostic whose `file_id` is not in the map increments nothing, so a late reply degrades to *no* badge rather than to a wrong one. `severity` is `"error"` or `"warning"` (`DOCS/analyze-api.md:56`); anything else counts as a warning.

### Invariants the island upholds

- `state.tabs` is the **single owner of the text**. `circ-editor.ts`'s registry is a mirror: `editor.textOf(i) === state.tabs.files[i].body` after every mutation.
- Every mutation goes **reducer first, then registry, then re-render, then `schedule()`** (except `select`, which never schedules).
- The root is `state.tabs.files[state.tabs.files.length - 1]` — `rootOf` (`split-files.ts:34`). No separate root field exists and none is added.
- **Phase 1's staleness guard is carried forward, per tab.** `fire()` snapshots the bodies it sent; `setDiagnosticsFor(i, …)` is skipped for any tab whose body has moved on since that snapshot, exactly as `DOCS/PLANS/PHASE_1_editor.md:475` skips `setDiagnostics` when `snapshot !== state.source`. See *Execution & Concurrency Model*.
- **The strip requires the registry.** `.pg-files` is only ever unhidden once `createEditor` has resolved; on Phase 1's fallback path (`editor === null`, `PHASE_1_editor.md:470`) the strip stays hidden and the `<textarea>` edits `toSource(state.tabs)` as one buffer.

### The editor's document registry (`site/src/scripts/circ-editor.ts`, Phase 1)

**Decision: one `EditorState` per file, swapped with `EditorView.setState`.** Verified against the exact locked package set installed at `/private/tmp/claude-501/-Users-jeffersonmourak-circus/9a9d359a-4d8b-4945-873f-09a96a28a456/scratchpad/cm-spike/node_modules` — `@codemirror/state` 6.7.4, `@codemirror/view` 6.43.11, `@codemirror/language` 6.12.4, `@codemirror/commands` 6.11.0, `@codemirror/lint` 6.9.7, `@lezer/highlight` 1.2.3 (each package's `package.json`). Every name below is read from those `.d.ts` files, so `DOCS/PLANS_PROMPT.md:190`'s "treat every CodeMirror name as intent" no longer applies to these six:

| Name | Declared at |
|---|---|
| `EditorState.create(config)` | `@codemirror/state/dist/index.d.ts:1193` (`EditorStateConfig.doc`/`selection`/`extensions`, `:1060-1082`) |
| `EditorState.update(...specs): Transaction` / `Transaction.state` | `state/dist/index.d.ts:1124` / `:966` |
| `EditorState.doc: Text` (`Text.toString()`, `Text.line(n)`, `Text.lines`) | `state/dist/index.d.ts:1096`; `:91`, `:47`, `:39` |
| `Compartment.of(ext)` / `.reconfigure(content)` / `.get(state)` | `state/dist/index.d.ts:732-748` |
| `EditorView.setState(newState)` / `EditorView.state` | `@codemirror/view/dist/index.d.ts:854` / `:742` |
| `EditorView.updateListener` (Facet) and `ViewUpdate.state` / `.docChanged` | `view/dist/index.d.ts:1275`; `:553` / `:597` |
| `EditorView.prototype.scrollSnapshot(): StateEffect<ScrollTarget>` | `view/dist/index.d.ts:1170` |
| `setDiagnostics(state, diagnostics): TransactionSpec` | `@codemirror/lint/dist/index.d.ts:128` |
| `history(config?)`, `historyField`, `historyKeymap` | `@codemirror/commands/dist/index.d.ts:102`, `:110`, `:153` |

Why state-per-file and not one document rewritten on switch:

- Undo history is a `StateField` (`historyField`, `commands/dist/index.d.ts:110`), so one state per file *is* per-file undo, for free and by construction. With one shared document, `Ctrl-Z` after a tab switch would rewrite the other file's text into this one — the exact behaviour `DOCS/PLANS_PROMPT.md:73` defers rather than invites.
- Selection is on the state too (`state/dist/index.d.ts:1100`), so a tab remembers its cursor with no bookkeeping.
- Lint diagnostics ride a state field: `setDiagnostics` returns a `TransactionSpec` (`lint/dist/index.d.ts:128`), so a hidden file's squiggles can be computed and stored with `states[i] = states[i].update(setDiagnostics(states[i], ds)).state` and are already on screen the moment that tab is shown.
- The cost is bounded: the extension array is built once and shared by every `EditorState.create` call, and each state holds only its own `Text` rope plus field values.

Two consequences slice 3a must honour:

1. **The theme compartment must fan out.** Phase 1 holds the `HighlightStyle` + `EditorView.theme` in one `Compartment` reconfigured from the `MutationObserver` on `document.documentElement`'s `data-theme` (`Playground.astro:452-455`; `DOCS/PLANS_PROMPT.md:79`). `Compartment.reconfigure` produces a `StateEffect` (`state/dist/index.d.ts:742`) that applies to **one** state. `circ-editor.ts` therefore stores the current compartment content and, on a theme change, rewrites every stored state (`states[i] = states[i].update({ effects: themeCompartment.reconfigure(next) }).state`) before dispatching on the visible one — otherwise a tab shown after a flip renders in the previous palette.
2. **Write-back on every change.** The `EditorView.updateListener` (`view/dist/index.d.ts:1275`) stores `update.state` back into `states[active]` and, when `update.docChanged` (`:597`), calls the island's `onChange(update.state.doc.toString(), active)`, which runs `setBody` and `schedule()`. The index is **appended**, never prepended, to Phase 1's `onChange?: (doc: string) => void` (`DOCS/PLANS/PHASE_1_editor.md:298`): `circ-editor.ts` is also the module Phase 7's `<LiveEditor>` mounts (decision 15, `DOCS/PLANS_PROMPT.md:56`), and it passes a single-document callback (`DOCS/PLANS/PHASE_7_live_editors.md:307`). Appending keeps that callback source-compatible; prepending would silently change its meaning.

Scroll position is not on the state; `showDocument` captures `view.scrollSnapshot()` (`view/dist/index.d.ts:1170`) for the outgoing tab and dispatches the incoming tab's saved effect after `setState`. This is a nicety, not a gate — it is DOM-only and appears in the manual checklist, not in `bun test`.

Registry surface added to Phase 1's handle (indices are the island's tab indices, always in lockstep with `state.tabs.files`):

```ts
setDocuments(texts: readonly string[], active: number): void;   // replaces the whole set
showDocument(index: number): void;
insertDocument(index: number, text: string): void;
removeDocument(index: number): void;
moveDocument(from: number, to: number): void;
textOf(index: number): string;
setDiagnosticsFor(index: number, diagnostics: readonly Diagnostic[]): void;  // Diagnostic from @codemirror/lint

// EditorOptions.onChange is widened by APPENDING the index:
//   onChange?: (doc: string, index: number) => void;   // PHASE_1_editor.md:298
// Phase 1's single-document methods are KEPT and act on the VISIBLE document,
// so Phase 7's <LiveEditor> (compact: true, one file) needs no change:
//   getDoc() === textOf(active); setDoc(t) replaces the active document;
//   setDiagnostics(ds) is sugar for setDiagnosticsFor(active, ds);
//   select(from, to) is relative to the active document (PHASE_1_editor.md:309).
// setTheme(mode) (PHASE_1_editor.md:307) is the fan-out entry point: it
// rewrites every stored EditorState before dispatching on the visible one.
```

`showDocument(index)` calls `view.setState(states[index])` (`view/dist/index.d.ts:854`) **synchronously**, so slice 6's cross-file jump is `editor.showDocument(i); editor.select(from, to);` in one statement — no `requestAnimationFrame`, no promise, no callback. A handle that was never given `setDocuments` behaves as a one-document registry: `onChange` fires with `index === 0` and `setDiagnostics(ds)` addresses document 0, which is precisely why Phase 7's compact `<LiveEditor>` is unaffected by every line of this section. `circ-editor.ts` still imports nothing playground-specific — the registry speaks only in integer indices and strings — and the index bookkeeping itself (`insert`, `remove`, `move`, `activeAfter`) lives in `site/src/scripts/doc-registry.ts`, which imports no `@codemirror/*` and touches no `document`, so `bun test` can prove it.

### The tab strip: markup, ARIA and keyboard (`site/src/components/Playground.astro`)

The strip sits inside `.pg-editor` (`Playground.astro:26`), directly below the existing `.pg-pane-label` row (`:27-38`, which keeps the `source` label and the `#pg-pick` select until Phase 4 replaces it) and directly above Phase 1's `.pg-editor-wrap` (`DOCS/PLANS/PHASE_1_editor.md:64`), which holds **both** the fallback `<textarea id="pg-source">` and the `<div id="pg-editor" class="pg-cm">` CodeMirror host. Phase 1 does not replace the textarea; it moves it into that wrapper and keeps it live forever if the editor chunk rejects (`PHASE_1_editor.md:470`). Class names are new (`.pg-file*`); `.pg-tabs` is the *output* strip (`:51`) and is not reused.

```html
<!-- Server-rendered `hidden`; the island unhides it only once createEditor resolves. -->
<div class="pg-files" hidden>
  <!-- Ships EMPTY in Playground.astro. Every role="tab" div below is created by
       the island, so this block is the RENDERED DOM, not source to paste. -->
  <div class="pg-filetabs" role="tablist" aria-label="Project files" aria-orientation="horizontal">
    <!-- one per file, rendered by the island; index 0 -->
    <div role="tab" class="pg-filetab" id="pg-filetab-0"
         aria-controls="pg-editor-panel" aria-selected="false" tabindex="-1"
         draggable="true" data-index="0"
         aria-label="half_adder.circ, 2 errors">
      <span class="pg-filetab-name">half_adder.circ</span>
      <span class="pg-filetab-badge" data-severity="error" aria-hidden="true">2</span>
      <button type="button" class="pg-filetab-close" tabindex="-1"
              aria-label="Delete half_adder.circ">&times;</button>
    </div>
    <!-- the last file is the root -->
    <div role="tab" class="pg-filetab" id="pg-filetab-1"
         aria-controls="pg-editor-panel" aria-selected="true" tabindex="0"
         draggable="true" data-index="1"
         aria-label="root.circ, root file, no diagnostics">
      <span class="pg-filetab-name">root.circ</span>
      <span class="pg-filetab-root" aria-hidden="true">root</span>
      <button type="button" class="pg-filetab-close" tabindex="-1" aria-label="Delete root.circ">&times;</button>
    </div>
  </div>
  <button type="button" class="pg-file-add" aria-label="Add a file">+</button>
  <span class="pg-filetab-error" role="alert"></span>
</div>
<!-- Phase 1's host (PHASE_1_editor.md:64), unchanged except for the two new
     ARIA attributes. The WRAPPER carries role="tabpanel", not #pg-editor: the
     mount itself is `hidden` at first paint, and the wrapper covers both
     editing surfaces. There is no `.pg-editor-mount` element and none is added. -->
<div class="pg-editor-wrap" id="pg-editor-panel" role="tabpanel" aria-labelledby="pg-filetab-1">
  <textarea id="pg-source" class="pg-source" …>…</textarea>   <!-- Phase 1's fallback -->
  <div id="pg-editor" class="pg-cm"></div>                    <!-- Phase 1's CodeMirror host -->
</div>
```

Notes on the shape, each load-bearing:

- **A tab is a `<div role="tab">`, not a `<button>`**, because it contains a real close `<button>` and a nested `<button>` inside a `<button>` is invalid HTML. Clicking anywhere in the div except the close control selects the tab; `Enter` and `Space` on a focused tab do the same. The binding constraint is stronger than the HTML one, though: `tab` is on ARIA's *presentational children* list (alongside `button`), so a control nested inside `role="tab"` may be pruned from the accessibility tree whatever the host element is — the close `<button>`'s `aria-label="Delete half_adder.circ"` and the rename `<input>`'s `aria-label="File name"` may never be announced. That is why the close control is `tabindex="-1"` and pointer-only, why `Delete`/`Backspace` on the tab is the keyboard path, and why both affordances are carried in the tab's own accessible name and announced through `.pg-status` (`Playground.astro:48`, already `aria-live="polite"`) rather than by the nested controls.
- **Roving tabindex**: exactly one tab carries `tabindex="0"` (the selected one) and every other carries `tabindex="-1"`, so `Tab` moves past the whole strip in one press and lands on `.pg-file-add`. The close buttons are `tabindex="-1"` and are reached with the pointer or with the `Delete` key path below.
- **One shared panel.** All tabs share `aria-controls="pg-editor-panel"`, and the panel's `aria-labelledby` is rewritten to the selected tab's id on every switch. This is the standard single-panel tabs shape and matches what the output strip already does with `aria-selected` (`Playground.astro:52-55`, `:122`).
- **The accessible name carries what the badges show**: file name, `root file` when it is the last tab, the error/warning counts (or `no diagnostics`), and `unsaveable: …` when `joinConflicts` names that index. The visible badge and the `root` chip are `aria-hidden` so they are not announced twice.
- **One `role="alert"` span per strip**, not per tab, for the rename validation message; it is emptied on cancel and on a successful commit.
- Root changes and delete/rename outcomes are announced through the existing `.pg-status` element, which is already `aria-live="polite"` (`Playground.astro:48`).
- The strip scrolls horizontally on its own (`overflow-x: auto`, the pattern `.pg-tabs` already uses at `global.css:609`), so the page never scrolls horizontally.
- **The strip only exists when the editor does.** `.pg-files` is server-rendered `hidden` and the island unhides it only once `createEditor` resolves. On Phase 1's fallback path (`editor === null`, `DOCS/PLANS/PHASE_1_editor.md:470`, where "the page never ends up with no editing surface") the `<textarea id="pg-source">` keeps editing the combined text — seeded from `toSource(state.tabs)` and re-read as `state.tabs = fromSource(textarea.value)` on every `input` — and the strip stays hidden, so a reader never sees N tabs over one combined buffer and never clicks a tab that means nothing. `.pg-status` says `Rich editor unavailable; using the plain text box.` (Phase 1's own message). A visible-but-disabled strip was considered and rejected for exactly that reason; the reducers keep their proof either way, because it lives in `bun test`, not in the DOM.
- **`Playground.astro:99`'s `[role=tab]` query must be narrowed in the same slice.** It is `const tabs = Array.from(el.querySelectorAll<HTMLButtonElement>('[role=tab]'))` — unscoped over the whole `.pg` root — so it would collect the file tabs too. `:122` (`b.setAttribute('aria-selected', String(b.dataset.tab === tab))`) would then clobber every file tab's `aria-selected` on each output-tab switch, and `:127`'s click listener would call `showTab(undefined)`, which sets `state.tab = undefined` and hides all four `.pg-panel`s — the output pane goes blank. Slice 3b changes it to `el.querySelectorAll<HTMLButtonElement>('.pg-tabs [role=tab]')`.

**Keyboard contract** (focus is on a tab unless stated):

| Keys | Effect |
|---|---|
| `ArrowLeft` / `ArrowRight` | Move focus to the previous / next tab, wrapping, **and select it** (automatic activation — a switch is a `setState` call, not a compile). |
| `Home` / `End` | Focus and select the first / last tab. |
| `Enter` / `Space` | Select the focused tab (no-op when it is already selected). |
| `F2` | Start renaming the focused tab: `.pg-filetab-name` is replaced by `<input class="pg-filetab-input" aria-label="File name" aria-invalid="false">`, pre-filled and fully selected. |
| `Enter` (in the rename input) | Commit when `nameError` is `null`; otherwise keep the input open, set `aria-invalid="true"` and write the message into the `role="alert"` span. |
| `Escape` (in the rename input, or on an armed tab) | Cancel; restore the previous name / disarm. |
| blur (of the rename input) | Commit if valid, otherwise revert silently and clear the alert. |
| `Delete` / `Backspace` | Arm the focused tab's close control (`data-confirm` on the tab, `aria-label` becomes `Delete <name>? Press Delete again to confirm`). A second `Delete`, or activating the close button, deletes. Arming clears on blur, on any other strip interaction, or after 4 s. Refused outright when `canDelete(state.tabs)` is false, with a `.pg-status` note. |
| `Alt+ArrowLeft` / `Alt+ArrowRight` | Move the focused **tab** one place left / right (`moveFile`); focus and selection follow the tab. The strip's `keydown` handler calls `preventDefault()` on **every** key it consumes — `Alt+ArrowLeft` is the browser's *Back* on Windows and Linux (Chrome and Firefox) and this phase persists nothing (see *Persistence & I/O*), so one unhandled press navigates away and destroys the reader's whole session; `Delete`, `F2`, `Home` and `End` carry the same exposure at lower stakes. Moving past the last position makes it the root — decision 3's stated way to change the root (`DOCS/PLANS_PROMPT.md:39`) — and `.pg-status` announces it. |

Pointer reorder uses HTML5 drag-and-drop on the tab divs (`draggable="true"`, `dragstart` stores the index, `dragover` previews the drop position with a `data-drop` marker, `drop` calls `moveFile`). Drag is an enhancement over `Alt+Arrow`, never the only path.

## Execution & Concurrency Model

This phase is **fully synchronous on the main thread**. No worker is added, no `Promise` chain is introduced, and no new instance of `LibcircClient` is created — the island keeps the single client at `Playground.astro:104`. The only timers are the existing `DEBOUNCE_MS = 250` debounce (`Playground.astro:85`, `:137-141`) and one 4-second `setTimeout` that disarms the delete confirmation; the latter is cleared on any other strip interaction and holds no state the model can read.

The single `state.gen` monotonic counter (`Playground.astro:105`, incremented at `:171` and checked at `:178`, `:195`, `:222`, `:243`) is carried over untouched. Decision 9's `ANALYZE_DEBOUNCE_MS` / `BUILD_DEBOUNCE_MS` split with a counter per stage belongs to Phase 3 slice 5 (`DOCS/PLANS_PROMPT.md:63`, `:80`).

Which tab operations kick the pipeline:

| Operation | Schedules a run? | Why |
|---|---|---|
| `fileTabs.select` (click a tab, arrow key, Home/End, a diagnostic jump into another file) — the *tab* reducer, not `EditorHandle.select(from, to)`, which places a cursor | **No** | The source is unchanged. Only the visible document swaps; diagnostics, preview, table and canvas stay exactly as they are. |
| `setBody` (any keystroke, through the editor's update listener) | Yes | Same path the `<textarea>`'s `input` listener used (`Playground.astro:142`). |
| `addFile`, `deleteFile`, `renameFile`, `moveFile` | Yes | Each changes the request: `requestFor` keys by name (`split-files.ts:42`) and roots on the last file (`:44`). |
| A `#pg-pick` change (`Playground.astro:143-146`) | Yes | It replaces the whole tab set via `fromSource`. |

Shared state and its owner: `state.tabs` lives in the island closure and is only ever replaced (the reducers are pure and never mutate), so there is no lock to take and no re-entrancy — every reducer call is a synchronous statement inside one DOM event handler. The `circ-editor.ts` registry is mutable but is written only from the same handlers, immediately after the reducer, in the same task.

Staleness across a tab edit: a reply that was in flight when a file was renamed or deleted still resolves against `state.gen`, and if it survives that guard its `analysis.files[].path` may name a file that no longer exists. `countsByFile` drops those ids, so the badges are simply absent until the next reply, and the per-tab `mapDiagnostics` call still **produces** the entry — the mapper is total (`DOCS/PLANS/PHASE_1_editor.md:442`, clamping rule 1) — with `from`/`to`/`docLine` all `null`, because `docLine` (`:388`) returns `null` for a file that is not in the array it was handed; it therefore reaches the flat list through the span-less pass, exactly once, and the row renders without a click handler — which is already the shape the existing code produces for an unmappable diagnostic (`Playground.astro:302-313`, the `if (loc)` guard).

**Phase 1's snapshot guard generalises; it does not go away.** `DOCS/PLANS/PHASE_1_editor.md:475` makes it mandatory — "One new staleness guard, and it is required" — because `@codemirror/lint` maps stored diagnostics forward through later changes (`@codemirror/lint/dist/index.js:151-152`) and cannot know they were computed against an older base; `fire()` must therefore compute offsets against the exact text it sent and skip the push when the document has moved on. Phase 2 dissolves `state.source` into `state.tabs`, so the guard is re-based per tab: `fire()` captures `const snapshot = state.tabs.files.map((f) => f.body)` **before** building the request, and when the reply lands `editor.setDiagnosticsFor(i, …)` runs **only** for tabs where `snapshot[i] === state.tabs.files[i]?.body`; it is skipped for the whole set when `snapshot.length !== state.tabs.files.length`, since an add, delete or move landed in flight and the indices no longer line up. A tab whose body moved on keeps its previous squiggles until the next reply — a fresher `fire()` is already scheduled. The diagnostics *list* still renders in full, because it carries file-local positions, which do not go stale the same way. `state.source` itself is **retired**: the combined text is never stored, only computed on demand as `toSource(state.tabs)`.

## Persistence & I/O

This phase has no persistence and no external I/O beyond what prior phases established. Nothing is written to `localStorage`: `site/src/utils/playground-store.ts` and the `circ.playground.v1` envelope are created in Phase 3 slice 3, and its `activeFile` field is filled in Phase 4 (`DOCS/PLANS_PROMPT.md:48`). A page reload discards the tab set, exactly as it discards the textarea's text today.

The only I/O is the existing worker traffic, unchanged in shape. `requestFor(state.tabs.files, options)` produces the same `{ root, files, options }` payload as `requestFor(splitFiles(source.value), options)` does today (`split-files.ts:40-48`), because the tab array is byte-for-byte the split of the same source; the four `client.call` sites (`Playground.astro:177`, `:194`, `:221`, `:242`) keep their current arguments. `compile` still transfers `bytes.buffer` (`site/src/workers/libcirc.worker.ts:64`) and the artifact is still identified by the FNV-1a hash at `Playground.astro:319-326` — Phase 2 adds no second consumer of those bytes.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each. Every slice's gate is `bun test` **and** `bun --bun run build` (plain `bun run build` fails on this machine), plus `bun run bundle` for any slice that changes a page's eager module graph — slice 3a onward.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | `joinFiles`, the name predicate, the round-trip contract | `site/src/utils/split-files.ts`: `NamedFile`, `SplitFile extends NamedFile`, `joinFiles`, `isFileName`, `JoinConflict`, `joinConflicts`; `rootOf` and `requestFor` widened to `readonly NamedFile[]`. `DOCS/decisions/playground.md` gains `### The marker format does not fork; `joinFiles` is its inverse` and `### The last file is the root; reorder is how you change it` (creating the file and registering it under "Topics" in `DOCS/decisions/index.md` if Phase 0/1 did not). | `bun test`: 12 new cases in `site/test/split-files.test.ts` — the 17-source byte-identical round trip, the left inverse over hand-built arrays, the two `// main.circ` normalisation pins, the trailing-marker-line normalisation, the non-canonical-marker normalisation, `'blank-body'`, `'marker-in-body'`, `'illegal-name'`, `'duplicate-name'`, the `isFileName` accept/reject table, and `requestFor` over a bare `{ name, body }[]`. `bun --bun run build`. |
| 2 | The tab-state model | New `site/src/scripts/file-tabs.ts` with `FileTab`, `FileTabsState`, `fromSource`, `toSource`, `rootIndex`, `activeFile`, `select`, `setBody`. No DOM, no CodeMirror, no `localStorage`. New `site/test/file-tabs.test.ts`. | `bun test`: `toSource(fromSource(s)) === s` over all 10 examples and 7 tour steps; `fromSource('')` yields exactly one `main.circ` tab with `active === 0`; `select` clamps out-of-range indices; `setBody` returns a new object and leaves the input untouched; and a source-text case reading `site/src/scripts/file-tabs.ts` with `Bun.file` asserting it matches neither `/@codemirror\//` nor `/\bdocument\.|localStorage/` (decision 15, `DOCS/PLANS_PROMPT.md:56`). `bun --bun run build`. |
| 3a | The document registry | New `site/src/scripts/doc-registry.ts`: pure index bookkeeping over an opaque `T` — `insert(items, at, item)`, `remove(items, at)`, `move(items, from, to)`, `activeAfter(active, op)` — no `@codemirror/*`, no DOM (the extraction Phase 1 justified at `DOCS/PLANS/PHASE_1_editor.md:55`). `circ-editor.ts` gains `setDocuments`, `showDocument`, `insertDocument`, `removeDocument`, `moveDocument`, `textOf`, `setDiagnosticsFor` built on it, plus the theme fan-out over every stored `EditorState` through `setTheme` (`PHASE_1_editor.md:307`) and the widened `onChange(doc, index)`. Phase 1's `getDoc` / `setDoc` / `setDiagnostics` / `select` are kept and act on the visible document, so Phase 7's `<LiveEditor>` needs no change. | `bun test`: new `site/test/doc-registry.test.ts` — `insert` at `rootIndex` shifts later entries and keeps the previously active *entry* active; `remove` clamps the active index in the `active < i`, `active === i` and `active > i` branches; `move` is a permutation whose inverse restores the input; every op returns a new array and does not mutate its input; the module's source matches neither `/@codemirror\//` nor `/\bdocument\b/`. Everything from slices 1–2 stays green. `bun --bun run build`; `bun run bundle`. |
| 3b | The tab strip | `Playground.astro` renders `.pg-files` (server-rendered `hidden`, `role="tablist"`, roving tabindex) directly above Phase 1's `.pg-editor-wrap` (`DOCS/PLANS/PHASE_1_editor.md:64`), which gains `id="pg-editor-panel"` and `role="tabpanel"`; the island owns `state.tabs`, swaps documents on select, unhides the strip only once `createEditor` resolves, re-points `#pg-pick` through `fromSource`, and **narrows `Playground.astro:99`'s unscoped `[role=tab]` query to `.pg-tabs [role=tab]`** so the output-tab handlers at `:122` / `:127` cannot reach the file tabs. Diagnostics are mapped per tab by calling Phase 1's mapper unchanged, once per file — `mapDiagnostics(f.body, [{ name: f.name, body: f.body, startLine: 0 }], analysis)` — behind the per-tab snapshot guard. Until slice 6 adds the tab switch, a diagnostics row whose file is not the active tab renders with its file-name prefix and **no click handler** — the same unclickable-row shape `Playground.astro:302-313` already produces — so no slice ever mis-places the caret. `.pg-files*` CSS in `global.css`. | `bun test`: everything from slices 1–3a stays green, Phase 1's `site/test/circ-diagnostics.test.ts` is untouched and stays green, **and** `site/test/libcirc.test.ts`'s tour-step-6 case, re-pointed through `fromSource` + `requestFor`, still reports status 0 with `ha1` / `ha2` / `half_adder` in `circ.topology.v0.full`, plus a new assertion that `toSource(fromSource(tour[5].source)) === tour[5].source`, plus a `bun test` case over `tour[5].source` asserting the concatenated list has exactly `analysis.diagnostics.length` rows for a two-tab project. `bun --bun run build`; `bun run bundle` shows `/playground` inside its committed ceiling and `site/test/bundle-graph.test.ts` still finds no `@codemirror/*` reachable from `Base.astro` / `Nav.astro` / `Footer.astro`. Browser walk-through (tour step 6 → two tabs, `root` badge on `root.circ`, switch tabs and find each file's cursor and undo intact; switching *output* tabs leaves the selected file tab selected) recorded in STATUS as **unrun**. |
| 4 | Add, rename, delete | `file-tabs.ts` gains `nextFileName`, `seedBody`, `addFile`, `nameError`, `renameFile`, `canDelete`, `deleteFile`. The strip gains the `+` button, the inline rename input with `aria-invalid` and a `role="alert"` message, and the two-press delete confirmation (`Delete`/`Backspace` on a focused tab arms the same state the close control does). A rename writes one note to `.pg-status`: `import` paths are not rewritten. | `bun test`: `addFile` inserts at `rootIndex` so the root is unchanged, activates the new tab, names it `file1.circ` then `file2.circ` skipping taken names, and seeds a body for which `joinConflicts` is empty; `nameError` rejects `''`, `'foo'`, `'foo.circ '`, `'a/b.circ'`, `'<builtin>/xor.circ'` and a duplicate, accepts `'a-b_1.circ'` and accepts renaming a file to its own name; `renameFile` is a no-op when `nameError` is non-null; `deleteFile` refuses the last remaining file, promotes a new root when the root is deleted, and clamps `active` in all three branches. `bun --bun run build`; `bun run bundle`. Mouse rename and the confirm timeout recorded as **unrun**. |
| 5 | Reorder and the root badge | `file-tabs.ts` gains `moveFile`. HTML5 `draggable` reorder on the strip, `Alt+ArrowLeft` / `Alt+ArrowRight` keyboard reorder with focus following the tab, the `root` badge always on the last tab and named in its `aria-label`, and a `.pg-status` announcement (already `aria-live="polite"`, `Playground.astro:48`) when the root changes. | `bun test`: moving a tab to the end changes `rootOf(files).name` and `requestFor(files).root`; the previously active file is still active after any move; `to` out of range clamps; `toSource` after a move re-emits the markers in the new order and `splitFiles` of that string reads the moved file as the root. `bun --bun run build`; `bun run bundle`. Pointer drag recorded as **unrun**. |
| 6 | Per-tab diagnostic counts and cross-file jumps | `file-tabs.ts` gains `TabCounts` and `countsByFile`. Each tab renders an error/warning badge and folds the counts into its `aria-label`; a tab with a `joinConflicts` entry renders a warning marker and names the reason in `.pg-status`. The diagnostics list keeps Phase 1's unconditional `<file>:<line>:<col> <code> <message>` label (`DOCS/PLANS/PHASE_1_editor.md:414-421`, pinned by its `list rows carry the compiler's own file-local position` test at `:531` and its `docLine reproduces today's combined line` test at `:532`) — making the prefix conditional would regress a shipped dependency. What slice 6 adds is the **jump**: a row whose file is not the active tab *gains its click handler*, which runs `fileTabs.select(tabIndex)` and `editor.showDocument(tabIndex)` before `editor.select(from, to)` with that file's local offsets; a row whose `file_id` maps to no tab stays unclickable, exactly as `Playground.astro:302-313` renders it today. | `bun test`: `countsByFile` splits errors and warnings across two tabs; skips a `file_id` whose path is `<builtin>/xor.circ`; skips a `file_id` whose `/playground/…` path names no current tab; returns all-zero rows for a `null` analysis and for a tab with no diagnostics. `bun --bun run build`; `bun run bundle`. Clicking a `root.circ` diagnostic while `half_adder.circ` is active recorded as **unrun**. |

Slices are ordered by dependency: 1 has no consumer, 2 consumes 1, 3a consumes 2 and changes no rendered HTML (its whole proof is `bun test`), 3b consumes 3a and is the first slice that changes a byte of rendered HTML, and 4–6 each add one strip capability on top of 3b. Each is independently reviewable and independently committable with `bun test` and `bun --bun run build` green.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `joinFiles round-trips every example and tour source` | `site/test/split-files.test.ts` | For each of the 10 `examples[].source` and 7 `tour[].source`, `joinFiles(splitFiles(s)) === s`, byte for byte. |
| `joinFiles is a left inverse of splitFiles` | `site/test/split-files.test.ts` | For hand-built conflict-free arrays (one unnamed `main.circ`; one named file; three named files; a body whose first line is `// notes.circ`; a blank last file), `splitFiles(joinFiles(files))` matches name-for-name and body-for-body. |
| `joinFiles drops a redundant leading main.circ marker` | `site/test/split-files.test.ts` | `joinFiles(splitFiles('// main.circ\ninput a\n')) === 'input a\n'`. |
| `joinFiles keeps a leading main.circ marker that shields a marker line` | `site/test/split-files.test.ts` | `joinFiles(splitFiles('// main.circ\n// a.circ\ninput a\n'))` is byte-identical to its input. |
| `joinConflicts flags a blank non-root body` | `site/test/split-files.test.ts` | `[{main.circ,''},{a.circ,'input a\n'}]` reports `{ index: 0, reason: 'blank-body' }`, and `splitFiles(joinFiles(...))` really does collapse to one file. |
| `joinConflicts flags a marker line after content` | `site/test/split-files.test.ts` | `[{a.circ,'input a\n// b.circ\n'}]` reports `{ index: 0, reason: 'marker-in-body' }`; a marker line *before* any content reports nothing. |
| `joinFiles normalises a trailing marker line` | `site/test/split-files.test.ts` | `joinFiles(splitFiles('input a\n// b.circ')) === 'input a\n// b.circ\n'` — the empty body-line list at `split-files.ts:24`, `:31` adds one newline; the same source with a body line after the marker round-trips byte-identically. |
| `joinFiles normalises a non-canonical marker` | `site/test/split-files.test.ts` | `'//   a.circ'` and `'// a.circ '` both re-emit as `'// a.circ'`, because `MARKER` (`split-files.ts:14`) captures neither the inner `\s+` nor the trailing `\s*`; a canonical `'// a.circ'` is byte-identical. |
| `joinConflicts flags an illegal file name` | `site/test/split-files.test.ts` | `[{ name: 'foo', body: 'input a\n' }, { name: 'b.circ', body: 'x\n' }]` reports `{ index: 0, reason: 'illegal-name' }`, and `splitFiles(joinFiles(...))` really does collapse the pair — the case that makes clause 1's name precondition load-bearing. |
| `joinConflicts flags a duplicate file name` | `site/test/split-files.test.ts` | Two files both named `a.circ` report `{ index: 1, reason: 'duplicate-name' }`, and `Object.keys(requestFor(files).files).length === 1` — the body `requestFor` silently drops. |
| `isFileName follows the MARKER regex exactly` | `site/test/split-files.test.ts` | Accepts `main.circ`, `a-b_1.circ`, `x.y.circ`; rejects `''`, `foo`, `foo.circ ` (trailing space), `a/b.circ`, `<builtin>/xor.circ`, `.circ`-less names, and a name with an embedded newline. |
| `requestFor accepts a startLine-free file array` | `site/test/split-files.test.ts` | `requestFor([{name,body},…])` produces the same `{ root, files }` as `requestFor(splitFiles(source))` for tour step 6. |
| `insert, remove and move are pure permutations` | `site/test/doc-registry.test.ts` | Every op returns a new array and mutates neither its input array nor its entries; `move` composed with its inverse restores the input; `insert` at `rootIndex` shifts every later entry by one. |
| `activeAfter clamps in all three branches` | `site/test/doc-registry.test.ts` | After `remove(i)`: `active < i` is unchanged, `active === i` clamps into `[0, len - 1]`, `active > i` decrements. After `insert(at)`: the previously active *entry* is still the active one. |
| `doc-registry.ts stays free of CodeMirror and the DOM` | `site/test/doc-registry.test.ts` | The module's own source text matches neither `/@codemirror\//` nor `/\bdocument\b/` — the property that lets `bun test` reach it at all (`DOCS/PLANS/PHASE_1_editor.md:55`). |
| `fromSource/toSource round-trip every content source` | `site/test/file-tabs.test.ts` | All 17 sources, byte for byte, through `FileTabsState`. |
| `fromSource of an empty string is one main.circ tab` | `site/test/file-tabs.test.ts` | `files.length === 1`, `files[0].name === 'main.circ'`, `active === 0`. |
| `select and setBody are pure and clamped` | `site/test/file-tabs.test.ts` | `select` clamps to `[0, len-1]`; `setBody` returns a new state and does not mutate the input's `files` array or its entries. |
| `file-tabs.ts stays free of CodeMirror and the DOM` | `site/test/file-tabs.test.ts` | The module's own source text matches neither `/@codemirror\//` nor `/\bdocument\.|localStorage/`. |
| `addFile lands before the root and seeds a joinable body` | `site/test/file-tabs.test.ts` | Insert index is `rootIndex`; `rootOf` is unchanged; `active` is the new index; the name is the first free `file<N>.circ`; `joinConflicts(next.files)` is empty. |
| `nameError enforces the marker name and uniqueness` | `site/test/file-tabs.test.ts` | The reject/accept table above, plus renaming a file to its own name returning `null`. |
| `renameFile is a no-op on an invalid name` | `site/test/file-tabs.test.ts` | State is returned unchanged (identity or deep-equal) whenever `nameError` is non-null. |
| `deleteFile promotes a new root and clamps active` | `site/test/file-tabs.test.ts` | Deleting the last file is refused; deleting the root makes the new last file the root; `active` is correct for `active < index`, `active === index` and `active > index`. |
| `moveFile to the end changes the root` | `site/test/file-tabs.test.ts` | `rootOf(files).name` and `requestFor(files).root` follow the move; the previously active file stays active; `to` clamps; `splitFiles(toSource(moved))` reads the new order. |
| `countsByFile skips builtins and unknown paths` | `site/test/file-tabs.test.ts` | A `<builtin>/xor.circ` `file_id` and a `/playground/gone.circ` `file_id` contribute nothing; errors and warnings land on the right tabs; `null` yields all zeros. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `compiles tour step 6 with the last // name.circ file as root` (existing, `site/test/libcirc.test.ts:70-81`, re-pointed) | `file-tabs.ts` + `split-files.ts` + the committed `site/public/wasm/libcirc.wasm` | `fromSource(tour[5].source).files` names `['half_adder.circ','root.circ']`; `callOp(w, 'compile', requestFor(files))` returns status 0; the `circ.topology.v0.full` custom section still contains `ha1`, `ha2` and `half_adder`; and `toSource(fromSource(tour[5].source)) === tour[5].source`. This is the Phase Index's stated proof (`DOCS/PLANS_PROMPT.md:64`). |
| `preview text equals the examples' preview fields` (existing, `site/test/libcirc.test.ts:99-107`) | regression over the widened `requestFor` | The 10 committed previews are still reproduced byte for byte after `rootOf`/`requestFor` change parameter type. |
| `half-adder truth table as JSON` (existing, `site/test/libcirc.test.ts:109-120`) | regression | Unchanged. |
| `the pinned renderer decodes what libcirc.wasm emits` (existing, `site/test/renderer-pin.test.ts:21-33`) | regression | Untouched by this phase; it must not move. |
| `no base page eagerly loads CodeMirror` (Phase 0's `site/test/bundle-graph.test.ts`) | build-free budget gate | The tab strip adds markup and island code but no new eager import outside `/playground`. |

Run command:

```sh
cd /Users/jeffersonmourak/circus/worktrees/v0.0.3/playground/site && bun test
```

Targeted, while iterating on a slice:

```sh
cd /Users/jeffersonmourak/circus/worktrees/v0.0.3/playground/site && bun test test/split-files.test.ts test/file-tabs.test.ts
```

Full per-slice gate (slice 3a onward):

```sh
cd /Users/jeffersonmourak/circus/worktrees/v0.0.3/playground/site && bun test && bun --bun run build && bun run bundle
```

`SKIP_LIBCIRC_TEST=1` is never the workaround for a red run (`DOCS/PLANS_PROMPT.md:135`); `site/test/libcirc.test.ts:12` and `site/test/renderer-pin.test.ts:12` honour it and a green run under it proves nothing about the module.

### Manual checklist (record in STATUS as *unrun* unless someone actually runs it)

No browser has ever been available in a session on this branch (`DOCS/PLANS_PROMPT.md:136`). The list, in one place:

1. Open `/playground`, pick "6. A full-adder, by importing the half-adder": two tabs, `root.circ` last with the `root` badge.
2. Type in `half_adder.circ`, switch to `root.circ`, switch back — the cursor is where it was and `Ctrl-Z` undoes only this file's edit.
3. `+` adds `file1.circ` **before** `root.circ`; the root badge does not move.
4. `F2` on a tab renames it; typing `foo` shows the error and refuses; `foo.circ` commits; the status bar names the import caveat.
5. `Delete` on a focused tab arms the close control; a second `Delete` removes it; the last remaining file cannot be deleted.
6. `Alt+ArrowRight` on the second-to-last tab moves it past the root; the badge follows and the status bar announces the new root. A mouse drag does the same.
7. Break `root.circ` (`not n(in=zzz)`): the `root.circ` tab shows a red `1`; while `half_adder.circ` is active, the diagnostics list row reads `root.circ: …` and clicking it switches tabs and lands the cursor on `zzz`.
8. Flip the theme with a hidden tab selected, then show that tab: it is in the new palette (the compartment fan-out).
9. At 360 px wide the strip scrolls horizontally and the page does not.
10. Force Phase 1's fallback (block the `circ-editor.ts` chunk in devtools): `.pg-files` stays hidden, the `<textarea id="pg-source">` holds the combined `toSource(state.tabs)` text and still compiles, `.pg-status` reads `Rich editor unavailable; using the plain text box.` (`DOCS/PLANS/PHASE_1_editor.md:470`), and no tab strip appears over the single buffer.
11. Switching *output* tabs (Diagnostics → Preview → Truth table → Simulate) leaves the selected file tab selected and never blanks the output pane — the `.pg-tabs [role=tab]` narrowing of `Playground.astro:99`.

## Open Questions / Spikes

`DOCS/PLANS_PROMPT.md`'s "Open items" list carries **no** `TODO(phase2)` entry (its open items are `TODO(phase0)`, two `TODO(phase1)`, `TODO(phase4)` and `TODO(phase5)`), so there is nothing of its to resolve here. Three items are genuinely open in this phase:

- **`TODO(phase2)-A`: does the shipped `circ-editor.ts` match Phase 1's specified handle?** The shape is not open. `DOCS/PLANS/PHASE_1_editor.md:301-312` pins `EditorHandle { readonly view, getDoc, setDoc, setDiagnostics, setTheme, select, focus, destroy }`, `:314` pins `createEditor(parent, options?)`, `:289-299` pins `EditorOptions { doc, theme, readOnly, compact, ariaLabel, onChange }` with `onChange?: (doc: string) => void` at `:298` — all written against the same scratch install this plan reads, and authoritative once the phase plan exists (`DOCS/PLANS_PROMPT.md:77`). The registry is a **delta** on that handle, not a redesign: the seven new methods are additive, `getDoc` / `setDoc` / `setDiagnostics` / `select` keep their meaning against the visible document, `setTheme(mode)` gains the fan-out, and `onChange` gains an appended index. *Read, do not re-litigate:* before starting slice 3a, read the shipped `site/src/scripts/circ-editor.ts` and Phase 1's STATUS entries for its slices 1, 3 and 4 (which are required to record the real extension names, `DOCS/PLANS_PROMPT.md:190`) only to confirm it landed as specified. If it diverges, slice 3a adapts to what shipped and records the delta in its own STATUS entry rather than reshaping Phase 1's API. Blocks slice 3a only.
- **`TODO(phase2)-B`: does `@codemirror/commands` survive Phase 1's budget measurement, and does per-file undo survive with it?** `DOCS/PLANS_PROMPT.md:189` pre-agrees that if `/playground` measures within 20% of the 120 KB gzip ceiling, "Phase 2 drops `@codemirror/commands` and hand-rolls its two keymaps before it starts". That package owns `history()` and `historyField` as well as `defaultKeymap` (`commands/dist/index.d.ts:102`, `:110`, `:649` — `:658` is the file's final barrel `export { … }` line, not a declaration, and `DOCS/PLANS/PHASE_1_editor.md:567` and `DOCS/PLANS/PHASE_7_live_editors.md:354` both already cite `:649` for `defaultKeymap`), so a literal drop removes undo entirely, not just two keymaps. *Read, do not decide:* the rule belongs to `TODO(phase1)`, and `DOCS/PLANS_PROMPT.md:186`'s protocol is "Resolve it in the phase named, record the answer in that slice's STATUS entry, and delete the entry from this list" — so by the time Phase 2 starts, Phase 1's install-slice STATUS already carries the measured `/playground` raw/gzip row and the verdict of the 20% rule, and the Open item is gone. Phase 2 reads that verdict and builds on it; it does not substitute an action of its own, and it adds no package (see **New dependencies**). **If the rule fired and Phase 1 executed it literally**, `history()` / `historyField` are gone, per-file undo is gone with them, the state-per-file model still stands (it is a `@codemirror/state` property, `state/dist/index.d.ts:1193`), and only manual-checklist step 2 changes. **If Phase 1 stopped for the human instead**, which is what its own plan already instructs — `DOCS/PLANS/PHASE_1_editor.md:568` records the rule as *partially resolved*, notes that `PLANS_PROMPT.md:189` "assumed dropping `@codemirror/commands` meant hand-rolling two keymaps" while this phase has since made `history()` / `historyField` load-bearing, and has slice 1 "stop for the human with two named options" — then the amendment to `DOCS/PLANS_PROMPT.md:189` must already be in that file, made by the human who locked the rule, before slice 3a begins. Phase 2 does not write that amendment and does not act as if it existed. Evidence for whoever makes that call, measured here: `gzip -9` over the unminified `dist/index.js` of the installed spike packages gives `@codemirror/view` 118,509 B, `@codemirror/state` 34,976 B, `@codemirror/language` 26,662 B, `@codemirror/commands` 17,267 B, `@codemirror/lint` 9,193 B, `@lezer/highlight` 8,131 B — pre-tree-shake, pre-minify upper bounds, so they do not predict the built bundle, but they do show a `view`-dominated budget that dropping `commands` cannot rescue. Blocks slice 3a's undo claim only.
- **`TODO(phase2)-C`: after Phase 0, do any diagnostics arrive with a `<builtin>/…` `file_id`?** Phase 0 makes implicit builtins resolve on the compile route, and the trap at `DOCS/PLANS_PROMPT.md:154` warns to "expect far more of them" in `analyze.files`. `countsByFile` already skips them for badges, but the *diagnostics list* would render them as unclickable rows with a confusing location. *Spike:* in slice 6, add a temporary `bun test` case that runs `callOp(w, 'analyze', requestFor(fromSource(tour[5].source).files))` against the regenerated `site/public/wasm/libcirc.wasm` and counts diagnostics whose `file_id` maps to a path starting `<builtin>/`. If the count is zero for every example and tour source, delete the temporary case and leave the list as it is; if it is non-zero, slice 6 filters those rows out of the list (they are not the reader's code) and keeps a single summary line instead. Blocks slice 6 only; it is a five-minute test, not a design question.
