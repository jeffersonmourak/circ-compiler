# Archived plan: playground

**Canonical commit:** `ead16a942f6fec53becd9679b01f6e09fa2f0801` (`ead16a9 feat(site): download the compiled artifact, and polish the share button`)
**Archived on:** 2026-09-10
**Plan duration:** 2026-09-09 → 2026-09-10

> This file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the commit referenced above. Check that commit out (`git show ead16a942f6fec53becd9679b01f6e09fa2f0801:DOCS/PLANS_PROMPT.md`, etc.) when you need the unabridged source. The plan prompt at that commit carries its own text twice (the second copy, from line 194 on, is a stale duplicate; the first copy is the one that was maintained).

## Goal & scope

`/playground` went from a `<textarea>`, an example `<select>` and four tabs (`site/src/components/Playground.astro`, 460 lines) to the place a reader actually writes circ: a CodeMirror 6 editor with `circ_analyze` diagnostics as squiggles and gutter markers at the compiler's own byte-column ranges; a multi-file project edited over the unchanged `// <name>.circ` marker interchange format (the last file is the root); a viewport-locked workbench with a draggable, keyboard-operable divider, a status bar naming the compiler version, revision and artifact size, and a two-stage debounced pipeline (`analyze` at 120 ms, `compile`/`preview`/`truth_table` at 350 ms) with a sequence guard at every await; a workspace of shipped examples, tour circuits and the reader's own scratch projects in one schema-versioned `localStorage['circ.playground.v1']` envelope; share links whose fragment carries the source (`#src=` deflate-raw + base64url, `#src0=` plain, 8 KB cap, scrubbed at parse time); source-to-picture linking in four directions by declared name; a settings drawer bound to the six documented compiler options; and ROM images validated exactly as the library validates them and loaded into both the truth table and the live simulation. The stack did not change — Astro 5 islands, TypeScript, bun, one `libcirc.wasm` in a Web Worker, `circ-renderer` pinned by sha. Anchors that held throughout: no React and no Monaco; nothing heavy loads before interaction; the Web Worker owns the wasm instance; `--sim`, `--emit-zig` and `--inspect` stay out of libcirc; one compiler revision for every committed artifact; behaviour a `bun test` could reach lives in a `.ts`/`.mjs` module under `site/src/` and the `.astro` islands stay thin; a per-page JavaScript budget gates every route and no ceiling was ever raised. The single Zig change was Phase 0's usage-aware compile fast path.

## Phase-by-phase highlights

### Phase 0 — Builtins resolve; the bundle gets a budget

A single import-free `.circ` that instantiates a builtin macro compiles through the CLI, the library and the committed `libcirc.wasm` instead of returning `E001: undeclared name 'xor'`; the site gains a per-page JavaScript budget.

- `lib/libcirc/frontend.zig`'s `.project_if_imports` arm became `ast_file.imports.len > 0 or usesBuiltinMacro(ir_module)` — the IR is scanned, not `ast_file.components[]`, so an anonymous nested instance counts. `build/frontend_modules.zig` gives the `libcirc` module the `builtins` import. Fixture `tests/fixtures/circuits/builtin_xor_anonymous.circ` pins the predicate only (it does not compile — see papercuts). `tests/fixtures/expected-inspect/canonical_full_adder_root.txt` regenerated (two span lines; the `E001` line untouched) and pinned by a new CLI test.
- `full_adder_from_builtins.circ` joined `compile_fixtures` in `tests/libcirc/driver_test.zig`; the `four_bit_adder` drive case joined `tests/e2e/libcirc_wasm_test.zig`; `site/test/libcirc.test.ts` gained `compiles a builtin-using single file with no import`.
- `site/scripts/check-bundle.ts` (`bun run bundle`): walks `dist/**/*.html`, follows static imports through the built chunks, sums raw and gzip per page against `site/bundle-budget.json` (`default { gzip: 10240 }`, `/playground { raw: 368640, gzip: 122880 }`), exits 1 over budget; `import()` chunks are reported, never gated. `site/test/bundle-graph.test.ts` walks source from `Base.astro`/`Nav.astro`/`Footer.astro` and fails on any `@codemirror/*` reachable without a build.
- Spike answer: Astro's static build emits no `<link rel="modulepreload">`, so the walker's chunk scanner, not the modulepreload seed, is what shipped.

### Phase 1 — The editor

The `<textarea>` became a CodeMirror 6 island with a circ mode from one token table, a palette derived from the shiki themes, and diagnostics as squiggles plus gutter markers plus a clickable list.

- Six packages pinned exactly (`@codemirror/{state,view,language,commands,lint}`, `@lezer/highlight`), guarded by `site/test/codemirror-pin.test.ts`; a hand-rolled `circKeymap` instead of `defaultKeymap` (the keymap-only split, taken so the editor chunk cleared the plan's 20 % band once; it crossed it again with highlighting and stayed an ungated lazy chunk).
- `site/src/utils/circ-tokens.mjs` is the one token table; `circ-lang.mjs`'s TextMate `match` strings are built from it — the `rom`/`ram` highlighting bug fix for every docs code block. `site/src/scripts/circ-editor.ts` holds `createEditor` and the `StreamLanguage`; `site/src/utils/circ-editor-theme.ts` derives both palettes from `shiki-themes.mjs`; `site/src/scripts/circ-diagnostics.ts` maps 1-based byte columns to document offsets across file markers and multi-byte text.
- Both diagnostics producers (analyze and the status-1 compile reply) go through one `publishDiagnostics(snapshot, analysis)` guarded by `snapshot === state.source`.
- Measured, not assumed: the headline example `not n(in=a)` reports `E004` over the whole declaration plus `W001` over `b`; validator codes carry declaration or connection spans, never a bare identifier.

### Phase 2 — Files as tabs

The marker format got a tab strip with add, inline rename, two-press delete, drag and `Alt+Arrow` reorder, a `root` badge on the last file, per-tab diagnostic counts and cross-file jumps.

- `site/src/utils/split-files.ts` gained `joinFiles` (the exact inverse of `splitFiles`, round-tripped over every shipped source), `isFileName` and `joinConflicts` (`blank-body`, `marker-in-body`, `illegal-name`, `duplicate-name`).
- `site/src/scripts/file-tabs.ts` is the pure tab model (`fromSource`, `toSource`, `addFile`, `renameFile`, `deleteFile`, `moveFile`, `countsByFile`); `site/src/scripts/doc-registry.ts` is the pure index bookkeeping; `circ-editor.ts` keeps one `EditorState` per file, which is what makes undo and selection per file.
- Plan correction: an illegal file name does not collapse a pair through the round trip; it preserves the count and loses the identity (`main.circ` invented, the marker stranded in a body).

### Phase 3 — The workbench

Full-height `app` layout, splitter, the `circ.playground.v1` envelope, the status bar, and the two-debounce pipeline.

- `Base.astro` gained `layout?: 'default' | 'app'`; the `[data-layout='app']` block in `global.css` is the only place app-layout rules live, and `site/test/app-layout.test.ts` freezes the `.lc-mount` selector set (shared with `LiveCanvas.astro`).
- `site/src/scripts/splitter.ts`: `role="separator"`, one unitless custom property `--pg-split-main`, pointer capture, `Escape` restore, double-click reset, `ResizeObserver` re-clamp that never commits.
- `site/src/utils/playground-store.ts`: the whole envelope (`version`, `scratch`, `activeId`, `activeFile`, `layout.ratios`, `settings`, `tab`), `normalize` as a fixed point, a 500 ms debounced writer, LRU trim, quota eviction with exactly one retry, session disable, all pure over injected `StorageLike`/`TimerLike` and proven under `bun test`.
- `site/src/scripts/pipeline.ts`: `Stage` (one debounce, one monotonic counter claimed at fire time), `ANALYZE_DEBOUNCE_MS = 120`, `BUILD_DEBOUNCE_MS = 350`, `statusFor`, `shouldCompile`, `outputsShouldClear`; `getSharedClient(wasmUrl)` on `libcirc-client.ts`. A failing build dims the last good outputs rather than clearing them; `hooks.onArtifact(null, 'files-changed')` fires only on a file-set change.

### Phase 4 — Workspace, persistence, and share links

A sidebar of examples, tour steps and scratch projects; copy-on-write forking; `#src=`/`#src0=`/`#pick=` links; "Open in playground" on every card and step with zero JavaScript added.

- `site/src/utils/share-link.ts`: `SHARE_CAP = 8192`, injectable `DeflateCodec`, chunked base64url, every failure a value (`bad-alphabet`, `bad-utf8`, …), `readHash` reporting every key so a failed decode falls through to `#pick=`.
- `playground-store.ts` gained the catalogue (`buildCatalogue`, ids `example:<slug>` / `tour:<n>` / scratch), `createScratch`/`duplicateScratch`/`renameScratch`/`deleteScratch`/`touchScratch`, `resolveInitial` with ten precedence cases, and `keep` (the active project is never evicted). Limits: 16 scratch projects, 32 KB per source, 256 KB per envelope; shipped text is never persisted, only ids.
- A classic `is:inline` script stashes the fragment on `window.__circShareHash` and `history.replaceState`s it at parse time, before PostHog's deferred module can read it.
- `site/src/components/OpenInPlayground.astro` throws at build time on an id not in the catalogue.

### Phase 5 — Source linking

Cursor → canvas, canvas hover → declaration, truth-table header and diagnostics row → both, joined by declared name.

- `circ-renderer` `host-pin-api` commit `2a76686` (`2.1.0-alpha.2`): `RenderOptions.onHover`, `CircCanvas.setHighlight(id | null)` feeding the existing `SkinContext.hovered`, `CircCanvas.getLayout()` (required: collapsed macro boxes carry synthetic ids that exist only in a `LayoutGrid`); headless `test/canvas.test.ts` over a `canvas-stub.ts`. The human pushed at the phase's hard stop; the site bumped the pin with `RENDERER_PIN_VERSION` asserted against the installed tree and the lock.
- `site/src/scripts/source-link.ts`: `rootFileId` (null, never 0, for an unknown root), `rootDeclarations`, `linkLayout`, `declarationAt`, `headerSymbolName` — top-level components only, tested against the committed `half-adder.wasm` through the pinned renderer's own `decodeFullTopology` + `buildLayout`.
- `circ-editor.ts` gained `onCursor` and `setLinkHighlight` (a `StateField` decoration that maps through later changes and survives `showDocument`); a hover on a declaration in a sibling file is named in the note, never switched to.
- The `bun --bun run typecheck` gate (`astro check`) was added after an unasserted string replace shipped `getSharedClient is not defined` in the island with every other gate green.

### Phase 6 — Settings and ROM images

A settings drawer for `expand_macros`, `expand_display`, `format`, `value_format`, `truth_table_cap` and `warnings_as_errors`, persisted; per-`rom` image loading into both outputs.

- `site/src/scripts/settings-drawer.ts`: `optionsFor(op, settings, preloads?)` sends each operation only its documented keys (an unknown key is status 2); `capRefusal` and the request read one field, so the two enforcement points of the truth-table cap cannot drift; `UI_INPUT_BITS_CAP` is gone.
- `site/src/utils/rom-image.ts`: `parseRomImage` tolerant of whitespace, commas, `0x`, `//`/`#` comments; validation in the compiler's order (whole words, capacity, width); `romPlan` re-parses the reader's text against current declarations; `applyRomImages` checks `getMemInfo` before every write and re-takes the byte view after every `memBuffer` call.
- ROM images are session state — not persisted, not shareable (a full `[64, 16]` image outweighs the whole envelope).

### Phase 7 — Live editors in the docs

Inert, lazy `<LiveEditor>` snippets in every tour step sharing one worker, with an expand link that carries an id when it can and the source when it must.

- `site/src/utils/artifact-hash.ts` (`fnv1a` lifted out of the island) and `site/src/utils/live-editor-config.ts` (`expandTarget` with six proven paths); `LiveEditor.astro` + `live-editor.ts` activated on first `pointerdown`/`focusin`.
- Slice 5 (`output="simulate"`) was not shipped: its poster frame needs a committed artifact and the tour's `tour-<N>.wasm` files are deliberately untracked. `/tour` measured 5.6 KB gzip, under the default ceiling, so no budget row was added.
- The whole component was deleted again after the plan closed (see below); `compact` on `createEditor` is its orphaned consumer-less option.

## Work logged after the plan closed

STATUS kept recording site work past Phase 7, on the same branch, before the log was archived:

- `site/test/island-smoke.test.ts` (happy-dom) runs the built islands and is the only gate executing island code; it needs `dist/`.
- The examples became a graded gallery (`level: intro | medium | advanced`, `GROUP_OF_LEVEL`, `CATALOGUE_GROUPS`), eight of them lifted verbatim from `tests/fixtures/circuits/` with a `repoPath` pinned byte for byte; `site/test/content-artifacts.test.ts` asserts every named `.wasm` exists, is wasm, is tracked, and that no committed artifact is orphaned. `public/wasm/tour-*.wasm` is gitignored.
- Diagnostics and settings moved from the output pane into a dock under the editor; the truth tab refuses with a reason (`truthTableRefusal`, `aria-disabled`, errors outrank the cap).
- The workspace sidebar became a tree (`site/src/scripts/ws-tree.ts`, `visibleNodes`, `moveFor`) and the file tab strip was retired; file rows carry the root chip, badges, rename (`✎`, F2), delete and reorder. Two layout regressions followed from the human's header removal (`grid-template-rows` counting hidden children) and the guard is now structural: `app-layout.test.ts` walks the built DOM and checks declared tracks against rendered children.
- A Memory dock tab appears only when the root declares a `rom`/`ram`: one word grid as the editor (`site/src/scripts/memory-panel.ts`, `rom-words.ts`), the prefix rule for images (earlier words become marked implied zeros), `?` for unknown, paging 64 words at a time, refusals inline.
- The examples page became the Gallery at `/gallery` with a redirect from `/examples` (`site/test/site-labels.test.ts` checks nav, footer, title, heading and mirror agree). The `/tour` page was deleted (its circuits stay in `src/content/tour.ts` and the workspace); `LiveEditor.astro`, `live-editor.ts` and `live-editor-config.ts` went with it. `site/.node-version` pins 22.19.0.
- Gallery cards declare a `memory` image (`Example.memory`, `site/src/scripts/canvas-memory.ts`) and auto-run on scroll (`autoRun`, one-shot `IntersectionObserver`); the ripple-carry adders moved onto buses with `site/test/adders.test.ts` driving the whole input space (`a + b == s + cout·2^N`).
- Renderer sync, six pin bumps in a day: `9694198` (`2.2.0-alpha.1`, bus pins take a typed value, `onPinChange`, `setInputValue`, `valueFormat`), `de92703` (typed memory API on `CircRuntime`: `memories()`, `memInfo`, `readMemWord`, `writeMemWord`, `loadMemImage`, `storeMemImage`, `clearMem`, `hasMemory`; the site's `raw` reaches and its `MemoryHost` deleted), `dc7e48b` (the renderer draws one highlight ring for every kind through a `highlight` theme hook; site skins for `slice`, `concat`, `rom`, `ram`), `5129114` (`setTheme`, `redraw`, `setValueFormat` in place — no rebuild on a theme flip, so pins and memory survive), `e38e49f` (`exports` map with a `circ-renderer/topology` entry point, `traceWire` exported; the site deletes every local copy of the renderer's shapes), `62d0def` (`2.2.0-alpha.6`, the bus-pin editor is a dialog with a slider). The site pins `62d0def`.
- `Download .wasm` in the status bar (`site/src/utils/artifact-name.ts`), Share with a share sheet on coarse pointers, and `height: auto !important` so a wide simulation keeps its proportion.

## API surface frozen by the plan

- **Site modules** (behaviour under `bun test`): `site/src/utils/{circ-tokens.mjs,circ-editor-theme.ts,split-files.ts,playground-store.ts,share-link.ts,rom-image.ts,artifact-hash.ts,artifact-name.ts,renderer-versions.ts}`, `site/src/scripts/{circ-editor.ts,circ-diagnostics.ts,file-tabs.ts,doc-registry.ts,splitter.ts,pipeline.ts,source-link.ts,settings-drawer.ts,ws-tree.ts,memory-panel.ts,rom-words.ts,canvas-memory.ts,libcirc-client.ts}`.
- **Storage:** `localStorage['circ.playground.v1']` `{ version: 1, scratch[], activeId, activeFile, layout.ratios, settings, tab, dock }`; a `version` mismatch resets; unknown keys drop; an invalid `tab` or `dock` falls back field by field.
- **URL fragments:** `#src=<base64url(deflate-raw(utf8))>`, `#src0=<base64url(utf8)>`, `#pick=example:<slug>` / `#pick=tour:<n>`; 8192-character cap; precedence `src` → `src0` → `pick` → persisted `activeId` → first pick; all consumed and scrubbed with `history.replaceState`.
- **Budget:** `site/bundle-budget.json` — default 10 KB gzip per page, `/playground` 360 KB raw / 120 KB gzip; `bun run bundle` after `bun --bun run build`; lazy chunks informational.
- **Gates run after every slice:** `bun test`, `bun --bun run typecheck`, `bun --bun run build`, `bun run bundle`; `zig build test-all` for Zig; `bun test` + `bun run typecheck` in `circ-renderer` for renderer slices.
- **Renderer hooks the site depends on:** `onHover`, `onPinChange`, `setHighlight`, `getLayout`, `setInputValue`/`getInputValue`, `boxOf`, `setTheme`/`redraw`/`setValueFormat`, the `CircRuntime` memory family, `traceWire`, `circ-renderer/topology`; `RENDERER_PIN_VERSION` in `site/src/utils/renderer-versions.ts` and `site/test/renderer-pin.test.ts` are the guard.
- **Compiler:** the `.project_if_imports` route is usage-aware for `compile` and `--emit-zig`; `.single_module` (`--inspect`) still reports `E001` for an unimported builtin, pinned by `canonical_full_adder_root.txt`.

## Known papercuts carried forward

- **`builtin_xor_anonymous.circ` takes the project route but does not compile** (three `E012`s): `resolve_bodies.specializeCallSites` pairs AST instances to IR components positionally and never visits appended anonymous components. Recorded in `DOCS/decisions/playground.md`; a resolver fix is its own initiative.
- **The manual browser checklist for Phases 1–7 was never run inside the plan.** The human found the first bugs in a browser afterwards (the unimported symbol, the editor sizing to its content, the swallowed cell edit); `island-smoke.test.ts` and `astro check` are the gates that grew from those.
- **The `TODO(phase4)` browser confirmation that the fragment scrub beats PostHog's `$pageview` is open.** Struck structurally (the capture script runs during parsing; `ph.init` is a deferred module), never measured.
- **Declarations inside a macro stay unresolvable for source linking** while the renderer draws one collapsed box per instance; they land in the join's `unlinked` list.
- **`output="simulate"` on a live editor never shipped**, and the live editors were then removed with `/tour`; `createEditor`'s `compact` option has no consumer.
- **Ten example previews in `site/src/content/examples.ts` differ from `circ-compile --preview` by trailing whitespace only** (an editor stripped it); nothing asserts that fidelity, and a regeneration will restore the spaces as a large no-op diff.
- **The LLM mirror never removes a twin it stopped writing** (`public/examples.md` had to be deleted by hand after the rename); `/examples.md` is a 404 with no redirect.
- **`warningsAsErrors` does not reach the truth tab's refusal**: severities come from the analysis, which does not receive that setting, so with it on a `W001` leaves the tab enabled and the refusal arrives from the worker.
- **A dev server racing a build hangs the build** (both write `public/` in the `sync` step); `astro build` alone does not race. Do not run a build with a dev server up.
- **Renderer sync Phase 6 (G03 in `circ-renderer/DOCS/plan-playground-sync.md`) is parked**; the renderer's `host-pin-api` PR into its `main` is still the maintainer's to open.
- **Source-text scanning tests trip over English** three times in this log (`localStorage` in a comment, the word `document`, `grid-template-rows` in a rule's comment); strip comments before matching.

## Decisions & specs that survived the plan

Authoritative docs remain outside this archive:

- `DOCS/decisions/playground.md` — the twenty-seven entries the phases appended (the compile fast path; the budget; the editor, its chunk, the token table, the palette; offset mapping; the marker format and the root; per-file editor state; per-tab diagnostics; the `app` layout; the splitter; the envelope; the status bar; two debounces; share links and the scrub; scratch projects and forking; the renderer hooks and the name join; settings, the cap, ROM images; the live editor and the expand link).
- `DOCS/decisions/libcirc.md` — the library half (the Web Worker, committed artifacts, the renderer following the compiler); `DOCS/libcirc-api.md` — the request/option contract every `optionsFor` key is drawn from; `DOCS/analyze-api.md` — the symbols and byte-column contract the editor maps; `DOCS/wasm-api.md` — the memory family and image format the ROM loader implements.
- `circ-renderer/DOCS/plan-playground-sync.md` and that repository's README — the host hooks, the typed runtime, the dialog's class names.
- `CLAUDE.md`, `DOCS/index.md` and `site/package.json`'s scripts for the build and gate commands.
