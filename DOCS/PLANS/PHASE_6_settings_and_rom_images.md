# Phase 6 — Settings and ROM images

> **Dependencies:** Phases 0–5, all shipped. Phase 0 (the regenerated `site/public/wasm/libcirc.wasm`, `bun run bundle` and `site/bundle-budget.json`), Phase 1 (the widened `Analysis` / `AnalyzeSymbol` types, which live in `site/src/scripts/circ-diagnostics.ts` — Phase 1 slice 4 replaced `Playground.astro:75-81`'s local interfaces with those imports (`DOCS/PLANS/PHASE_1_editor.md:498`, slice 4) — and which **already carry `symbols[].range` and `symbols[].addr_width`** (`:21`; `AnalyzeSymbol` at `:357-364`, `addr_width` at `:362`) — `references` is a top-level field of `Analysis` (`:375`), not a member of a symbol, and this phase reads neither — so this phase adds no field to them), Phase 2 (the tab strip, so the root file is a named tab), Phase 3 (`site/src/utils/playground-store.ts` and the `circ.playground.v1` envelope, whose `settings` field Phase 3 **already writes with full defaults and normalises key by key** — `DOCS/PLANS/PHASE_3_workbench.md:105-121`, defaults at `:181`, `normalize` at `:183` — so this phase is the first to *read it back into the UI and let the reader change it*, not the first to populate it; `site/src/scripts/pipeline.ts` and its `shouldCompile` (`:317`, called as at `:355`), which replaced the island's inline error gate; the status bar; the two-stage debounce with a sequence counter per stage), Phase 4 (`activeId`, so a settings change is persisted against a live workspace), Phase 5 (the bumped `circ-renderer` pin — this phase reads `runtime.raw` and `runtime.topology` off the same pinned package).
> **Warnings:** Required reading before the first line of code — decisions **12** and **13** of `DOCS/PLANS_PROMPT.md`; `DOCS/libcirc-api.md:43-55` (the eight documented option keys; **an unknown or mistyped key is status 2, never a silent default** — `lib/libcirc/json.zig:147-149`); `DOCS/wasm-api.md:86-119` (the memory family, the raw image format, the staging protocol and the eight status codes). Five traps this phase walks straight into: (1) **there is no `memLoadImage`** — the family is `getMemInfo`/`memBuffer`/`memLoad`/`memStore`/`memClear`/`setMemWord`/`getMemValue`/`getMemDefined` and every one is optional (`DOCS/wasm-api.md:29-37`, typed optional at `circ-renderer/src/wasm/runtime.ts:50-57`); (2) **`memBuffer(id)` may grow linear memory** — re-take the `Uint8Array` view over `raw.memory.buffer` *after* the call and before writing (`DOCS/wasm-api.md:98`; the working sequence is `circ-renderer/test/runtime.test.ts:48-65`); (3) **`circ-renderer` captures its theme at construction** (`src/render/canvas.ts:72`), so a theme flip destroys and rebuilds the view — and the rebuilt artifact instance has an all-undefined memory, which is why the images must be re-applied from inside `buildSim()` and not at its call sites (`Playground.astro:359-416`, observer at `:452-455`); (4) **the library's hex parser is strict** — `std.fmt.hexToBytes` over an even-length digit string, anything else is `PreloadNotHex` → status 2 (`lib/libcirc/json.zig:12-18,32,48`), so all tolerance lives in the browser and only canonical hex crosses the boundary; (5) **the truth-table cap is enforced in two places that must move together** (`Playground.astro:237` and `:242`) — raising one alone produces a silent refusal with no table. Also: `preloads` applies to `rom` only; a `ram` anywhere in the circuit is a status-3 refusal by design (`lib/libcirc/modes.zig:149`, message at `:103-106`). This phase touches **no Zig** — `zig build test-all` is not one of its gates.
> **Line numbers:** Every `Playground.astro:<n>` cited here is the line at plan time; Phases 1-5 rewrite that file, so resolve each by symbol (`fire`, `runPreview`, `runTruth`, `buildSim`, `rootInputBits`, `hooks.onArtifact`) rather than by line — the rule `DOCS/PLANS/PHASE_3_workbench.md:345` already states for itself.

## Goal

A reader can open the playground, expand a settings drawer from the output pane, and change six compiler options — `expand_macros`, `expand_display`, `format`, `value_format`, `truth_table_cap` and `warnings_as_errors` — with every control keyboard-operable and every choice surviving a reload through the existing `circ.playground.v1` envelope. In the same drawer, every `rom` declared in the root file gets its own loader: the reader pastes hex (whitespace, `0x` prefixes, `,`/`_` separators and `//` comments all tolerated), sees `ceil(W/8)`-bytes-per-word and `2^A`-word validation reported inline in the compiler's own wording, and those exact bytes then appear in **both** outputs — as `options.preloads` on the `truth_table` request, and as a `memBuffer` + `memLoad` write into the live simulation's artifact instance that is re-applied after every artifact rebuild and every theme flip. The observable end-state, in the Phase Index's words: declare `rom code[8, 4](addr = pc.out)`, paste sixteen bytes, drive `pc` to `3`, and read `0x33` out of the truth table's `out` column and off the canvas. Under `bun test`, the same claim is proved headlessly against the committed `libcirc.wasm`: compile a rom circuit, instantiate the artifact, run the site's own write sequence, and assert `getOutputValue(out) === 0x33n`.

## Scope

**In scope:**

- `site/src/scripts/settings-drawer.ts`: the per-op request-option projection `optionsFor()`, `DOCUMENTED_OPTION_KEYS`, the pre-flight `capRefusal()`, and the drawer's DOM wiring. **`PlaygroundSettings`, its defaults and its normalisation are Phase 3's** (`site/src/utils/playground-store.ts`, `DOCS/PLANS/PHASE_3_workbench.md:105-121,181,183`) and are imported here, never redeclared; `optionsFor` is the single place the envelope's camelCase field names become libcirc's snake_case option keys (`DOCS/libcirc-api.md:46-55`).
- `site/src/utils/rom-image.ts`: the tolerant hex codec, the `ceil(W/8)` / `2^A` / bits-above-`W` validator returning **errors as values**, the `romSymbols()` / `preloadsFor()` / `romPlan()` projections, and `applyRomImages()` — the `getMemInfo` → `memBuffer` → re-view → `memLoad` sequence over an injectable host.
- A `<details>` settings drawer in `Playground.astro`'s output pane, four `<fieldset>` groups (Preview / Truth table / Compile / ROM images), `<label for>` on every control, and its `.pg-settings*` CSS inside the existing `.pg*` block.
- Deleting `UI_INPUT_BITS_CAP` (`Playground.astro:84`) and moving **both** enforcement points (`:237`, `:242`) onto `settings.truth_table_cap` in one edit, with a `bun test` case that proves they cannot drift.
- Reusing Phase 5's root-file lookup: `rootFileId` is **not** recomputed here. The island passes `rootFileId(analysis.files, rootPath)` from `site/src/scripts/source-link.ts` (`DOCS/PLANS/PHASE_5_source_linking.md:204`) — the same value `rootInputBits()` uses after Phase 5 re-pointed it (`:340`, slice 5) — into `romSymbols()`. A third inline `${PLAYGROUND_DIR}/${files.at(-1).name}` derivation (`Playground.astro:229-230` today) is exactly the drift decision 13 exists to prevent.
- Truth-table `format` reaching the panel: `json` keeps today's HTML table, `markdown`/`csv` render the library's text in a `<pre>`; `value_format: 'hex'` yields cell **strings**, not numbers (`lib/truth_table/json.zig:8-12,74-76`).
- Rendering status-3 refusals verbatim — the preload reason (`lib/libcirc/modes.zig:102`), the stateful-`ram` reason (`:103-106`) and the cap reason (`:107-110`) — and echoing a preload refusal next to the rom that caused it.
- Persisting only `settings` in `circ.playground.v1`: **no second key, no `version` bump** (decision 7). Phase 3's seventh settings field, `romImages: Record<string, string>` (`DOCS/PLANS/PHASE_3_workbench.md:120`, defaulted to `{}` at `:181`), **stays in the schema and is deliberately never written by this phase** — see *Explicitly deferred*. Removing it was considered and rejected: it would change the envelope's key set inside `version: 1`, contradicting slice 4's own literal key-set comparison against what Phase 3 writes, for a field that costs two bytes when empty.

**Explicitly deferred:**

- **Persisting ROM images.** They are session state, held in the island and lost on reload. A legal image is at most `maxImageSize(W, A) = ceil(W/8) << A` bytes (`lib/memimage.zig:30-32`) — 512 KiB at `[64, 16]`, over 1 MB once hex-encoded — against decision 7's **256 KB per-envelope** ceiling, so persisting them would guarantee the `QuotaExceededError` eviction path on a legitimate circuit. `settings.romImages` therefore stays `{}` for the life of `version: 1`, and `preloadsFor` is built from the island's in-memory `state.romImages` instead. Images are per project **and** per session: switching projects shows the new project's images (usually none), nothing is carried across by name, and a reload shows none at all. The drawer says so in one line under the ROM fieldset.
- **Carrying ROM images in a share link.** Same reason against decision 6's 8192-character cap; `#src=` stays source-only.
- **Writing a `ram`.** `preloads` is rom-only by design, and a `ram` in a truth table is status 3 (`DOCS/libcirc-api.md:68`). Rams are listed in the drawer as one disabled, informational row so a reader with a `ram` is told why there is no box, and nothing more — no `setMemWord`, no poking, no memory viewer (the plan prompt's deferred list).
- **Reading memory back out.** `memStore`/`getMemValue`/`getMemDefined` are not called; the canvas already shows the word through the memory's `out` (`DOCS/wasm-api.md:90`).
- **A `color` control.** `color` is one of the eight documented keys but is not reader-facing; `optionsFor('preview', …)` pins it to `'never'` exactly as `Playground.astro:221` does today.
- **Options on `analyze`.** `libcirc.analyze` never reads `req.options` (`lib/libcirc.zig:127-138`); the analyze request keeps sending none.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site utils | `site/src/utils/rom-image.ts` | Tolerant hex → bytes codec; `bytesPerWord`/`maxWords`/`validateRomBytes` mirroring `lib/memimage.zig:24-62`; `romSymbols()` (over Phase 5's `rootFileId`, never a second root-file lookup), `preloadsFor()`, `romPlan()`; `applyRomImages(host, …)` and `applyToView(host, …)` — the only impure exports, over an injectable `MemoryHost`. **Imports nothing from `circ-renderer`** at runtime, and only a type from `circ-diagnostics.ts` (see New dependencies). |
| site scripts | `site/src/scripts/settings-drawer.ts` | `optionsFor(op, settings, preloads?)`, `capRefusal(bits, settings)`, `DOCUMENTED_OPTION_KEYS`, and `mountSettingsDrawer(root, deps)` — the DOM wiring, so the island stays markup plus a `<script>` (decision 15). `PlaygroundSettings` and its defaults are **Phase 3's** (`site/src/utils/playground-store.ts`, `DOCS/PLANS/PHASE_3_workbench.md:111-121,181`) and are imported, not redeclared; `optionsFor` is the single place the envelope's camelCase names become libcirc's snake_case keys (`DOCS/libcirc-api.md:46-55`), and `site/test/settings-drawer.test.ts` asserts every emitted key is in `DOCUMENTED_OPTION_KEYS`. |
| site test | `site/test/rom-image.test.ts` | Pure codec/validator/projection cases (unguarded) plus a `describe.skipIf(SKIP_LIBCIRC_TEST)` block that drives the committed `libcirc.wasm` and a compiled rom artifact. |
| site test | `site/test/settings-drawer.test.ts` | `optionsFor` (eight-key whitelist, per-op subsets, the camelCase → snake_case translation), `capRefusal`, and the envelope round-trip through `playground-store.ts`'s `writeEnvelope`/`readEnvelope`. **No normaliser cases** — Phase 3's `normalize` owns them (`DOCS/PLANS/PHASE_3_workbench.md:183,408`). |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site components | `site/src/components/Playground.astro` | Delete `UI_INPUT_BITS_CAP` (`:84`); wrap `.pg-tabs` and a new settings toggle in a `.pg-output-head` row; add the `<details id="pg-settings">` markup; route `runPreview` (`:219-224`), `runTruth` (`:234-269`) and the `compile` call (`:194`) through `optionsFor()`; replace the `:237-240` pre-flight with `capRefusal()`; render non-`json` tables as text and **widen `TruthTable`'s cells (`:82`)** from `(number | null)[]` to `(number | string | null)[]`, because `value_format: 'hex'` emits strings (`lib/truth_table/json.zig:8-12,75`); **widen the local `CircView` type (`:330-335`)** so `runtime` also carries `raw: { memory: WebAssembly.Memory; getMemInfo?; memBuffer?; memLoad?; memClear? }` (`circ-renderer/src/wasm/runtime.ts:326`, the family typed optional at `:50-57`) and so each `topology.components` entry carries `width: number` and `memory?: { addrWidth: number }` (`circ-renderer/src/wasm/topology.ts:128-139` — `width` at `:132`, `memory` at `:138`) — the four fields `MemoryHost` structurally requires and today's narrowed `{ id; kind; name; origin }` omits, so without this widening `applyRomImages(sim.view.runtime, …)` does not typecheck; call `applyRomImages()` inside `buildSim()` (`:359-416`) **after `simNote.textContent = 'Click input pins to toggle them.'` (`:384`)** — which sits inside the old window and would otherwise clobber a ROM failure message — and before the by-name pin replay (`:386-398`). |
| site utils | `site/src/utils/playground-store.ts` | **No source change.** `PlaygroundSettings`, its defaults and its normalisation ship in Phase 3, which already writes the field fully populated (`DOCS/PLANS/PHASE_3_workbench.md:181`) and already rebuilds it key by key with `truthTableCap` clamped to 1..24 and both enums checked (`:183`). This phase reads `store.envelope.settings` and commits through the existing `store.update((d) => { d.settings.<field> = … })`, riding Phase 3's 500 ms debounce — there is no second copy of the settings anywhere. Phase 3's exported surface is `defaultEnvelope`, `normalize`, `readEnvelope`, `writeEnvelope`, `evictOldest`, `browserStorage`, `describeNote` and `createStore(...)` returning `{ envelope, enabled, update, flush, onNote }` (`:150-178`); **there is no `read()`/`write()` pair.** `settings.romImages` stays in the schema and is deliberately never written (Scope). No new key, no `version` bump (decision 7). |
| site scripts | `site/src/scripts/pipeline.ts` | `shouldCompile` (`PHASE_3_workbench.md:317`, called as at `:355`) is widened in place to `shouldCompile(analysis: { doc: number; errors: number; warnings?: number } | null, doc: number, warningsAsErrors = false): boolean`, returning false exactly when `analysis` is for `doc` and `analysis.errors + (warningsAsErrors ? (analysis.warnings ?? 0) : 0) > 0`. Both additions are optional, so Phase 3's four existing cases (`PHASE_3_workbench.md:415`) compile and pass unchanged. No other stage logic changes. Phase 3 slice 5 split `fire()` (`Playground.astro:170-217`) into an analyze runner and a build runner and moved this decision into this module (`:388`), so the gate is no longer inline in the island. |
| site test | `site/test/pipeline.test.ts` | A fresh analysis with `errors: 0, warnings: 1` yields `shouldCompile === true` with `warningsAsErrors` off and `false` with it on; `errors: 0, warnings: 0` is unaffected either way; Phase 3's existing `shouldCompile` cases (`:415`) stay green. |
| site styles | `site/src/styles/global.css` | New `.pg-output-head`, `.pg-settings`, `.pg-settings-group`, `.pg-rom`, `.pg-rom-error`, `.pg-table-text`, `.pg-refusal` rules **inside the `.pg*` block (`:528-656`)**. Do not touch `.lc-mount` (`:477-525`) — it is shared with `LiveCanvas.astro:26`, which `/` and `/examples` render. |
| docs | `DOCS/decisions/playground.md` | Append this phase's `###` decisions (see slice 7). |
| docs | `DOCS/STATUS.md` | One entry per slice, per the plan prompt's template. |

**New dependencies:** None. `rom-image.ts` and `settings-drawer.ts` are dependency-free TypeScript. In particular **neither may `import` from `circ-renderer`**: the package is loaded lazily (`Playground.astro:347`) to keep it out of `/playground`'s eager module graph, and a static import from a module the island imports eagerly would pull it in and blow decision 14's 120 KB gzip ceiling. The two component-kind constants are inlined as numeric literals with a citation, exactly as `Playground.astro:349` already does for `INPUT_PIN = 0`:

```ts
// circ-renderer ComponentKind.Rom / .Ram (src/wasm/topology.ts:37-38);
// the wire truth is lib/topology/format.zig. Inlined, not imported: a static
// import of circ-renderer would put the renderer in /playground's eager graph.
const ROM_KIND = 8;
const RAM_KIND = 9;
```

Phase 5 hard-codes the same two bytes in `site/src/scripts/source-link.ts`'s `TOPOLOGY_KIND_OF` (`rom: 8`, `ram: 9` — `DOCS/PLANS/PHASE_5_source_linking.md:168-173`) for exactly this reason, and guards them with the test `the topology kind table matches ComponentKind` (`:359`), which imports `ComponentKind` **in the test**, where the eager graph does not reach. `rom-image.ts` keeps its own literals rather than importing from `scripts/` — a `utils/` → `scripts/` runtime edge for two numbers is worse than the duplication — but it does **not** ship unguarded: slice 2 mirrors Phase 5's guard, asserting `ROM_KIND === ComponentKind.Rom` and `RAM_KIND === ComponentKind.Ram` against the package imported inside `site/test/rom-image.test.ts`. `RAM_KIND` earns its place through that guard and through `romPlan`'s refusal to write a component the name join resolved to a `ram`.

The one cross-directory reference is `import type { AnalyzeSymbol } from '../scripts/circ-diagnostics.ts'` (Phase 1, `DOCS/PLANS/PHASE_1_editor.md:357-364`) in `rom-image.ts`: an `import type` is erased at build time and adds nothing to any module graph.

## Data & State

**The settings live in Phase 3's envelope; this phase only translates them.** `PlaygroundSettings`, `defaultEnvelope()`'s settings defaults and their key-by-key normalisation already ship in `site/src/utils/playground-store.ts` (`DOCS/PLANS/PHASE_3_workbench.md:105-121`, defaults at `:181`, `normalize` at `:183`), deliberately in **camelCase**, and for a reason this phase must not reopen: an envelope key can never then be spread into a libcirc `options` object, where an unknown or mistyped key is status 2 and never a silent default (`DOCS/libcirc-api.md:43-44`, `lib/libcirc/json.zig:147-149`). Phase 6 adds **no field, no default and no normaliser** — it adds the translation and the pre-flight, and `optionsFor` is the one place camelCase becomes libcirc's snake_case:

```ts
// site/src/scripts/settings-drawer.ts
import type { PlaygroundSettings } from '../utils/playground-store.ts';
// { expandMacros, expandDisplay, format, valueFormat, truthTableCap,
//   warningsAsErrors, romImages } — PHASE_3_workbench.md:111-121.
// `truthTableCap` is already trunc'd and clamped to 1..24 and both enums are
// already checked against their literal sets by Phase 3's `normalize` (:183),
// so this module re-validates nothing and defines no second normaliser.
// `romImages` is in the type but is never read or written here (see Scope).
```

**The per-op projection and the single cap.** Only the keys `DOCS/libcirc-api.md:46-55` marks as *used by* an op are sent, so a stray key can never become status 2:

```ts
export const DOCUMENTED_OPTION_KEYS = [
  'expand_macros', 'expand_display', 'color', 'format',
  'value_format', 'truth_table_cap', 'preloads', 'warnings_as_errors',
] as const;

export function optionsFor(
  op: 'analyze' | 'compile' | 'preview' | 'truth_table',
  s: PlaygroundSettings,
  preloads?: Record<string, string>,
): Record<string, unknown>;
// analyze     -> {}                                   (lib/libcirc.zig:127-138 ignores options)
// compile     -> { warnings_as_errors: s.warningsAsErrors }
// preview     -> { color: 'never', expand_macros: s.expandMacros,
//                  expand_display: s.expandDisplay,
//                  warnings_as_errors: s.warningsAsErrors }
// truth_table -> { format: s.format, value_format: s.valueFormat,
//                  truth_table_cap: s.truthTableCap,
//                  warnings_as_errors: s.warningsAsErrors,
//                  ...(preloads && Object.keys(preloads).length ? { preloads } : {}) }

/** The page's pre-flight refusal, or null. `bits` is null when no analysis has
 *  landed yet. Reads the SAME s.truthTableCap that optionsFor() sends as the
 *  `truth_table_cap` option: decision 13's
 *  two enforcement points are now one field, asserted by settings-drawer.test.ts. */
export function capRefusal(bits: number | null, s: PlaygroundSettings): string | null;
```

**Memory symbols, images and validation.** `analyze.symbols` is the declared side (`DOCS/analyze-api.md:57`; emitted as `"name":"code","kind":"rom","width":8,"addr_width":4` — `lib/analyze/analyze.zig:451,614`); the topology is the addressable side.

```ts
// site/src/utils/rom-image.ts
import type { AnalyzeSymbol } from '../scripts/circ-diagnostics.ts';  // Phase 1; type-only, erased

export interface MemorySymbol {
  name: string;
  kind: 'rom' | 'ram';
  width: number;     // W, 1..64  (E018)
  addrWidth: number; // A, 1..16  (E018)
}

/** Root-file rom/ram symbols. `analysis.files` paths beginning `<builtin>/`
 *  have no editor buffer and are skipped (DOCS/analyze-api.md:55); a rom symbol
 *  without `addr_width` is dropped rather than guessed. Mirrors the topology
 *  side's `origin.len == 0` rule (lib/engine_session.zig:47).
 *
 *  `AnalyzeSymbol` already carries `addr_width?: number` — Phase 1 widened it
 *  (DOCS/PLANS/PHASE_1_editor.md:21,362) and Phase 1 slice 4 replaced the
 *  island's local interfaces with these imports (:419); this phase adds no
 *  field to it.
 *
 *  The caller passes the id from `rootFileId(analysis.files, rootPath)` in
 *  `site/src/scripts/source-link.ts` (Phase 5, PHASE_5_source_linking.md:204 —
 *  the same value `rootInputBits()` uses after :340). This phase adds no second
 *  root-file lookup. `null` (no root file resolved) yields an empty list. */
export function romSymbols(
  symbols: readonly AnalyzeSymbol[],
  rootFileId: number | null,
): MemorySymbol[];

export const bytesPerWord = (w: number) => (w + 7) >> 3;   // lib/memimage.zig:24-27
export const maxWords = (a: number) => 1 << a;             // lib/memimage.zig:55

export type RomImageError =
  | { kind: 'bad_char'; index: number; char: string }
  | { kind: 'odd_token'; token: string; index: number }
  | { kind: 'not_word_multiple'; bytes: number; bytesPerWord: number }
  | { kind: 'too_many_words'; words: number; capacity: number }
  | { kind: 'word_exceeds_width'; word: number; dataWidth: number };

export type RomImageResult =
  | { ok: true; bytes: Uint8Array; words: number; hex: string }   // hex: lowercase, even length
  | { ok: false; error: RomImageError; message: string };

/** Parse the reader's text, then validate against (W, A). Never throws. */
export function parseRomImage(text: string, mem: MemorySymbol): RomImageResult;
```

The accepted grammar, decided here and pinned by tests: **`//` starts a comment that runs to end of line and is dropped; whitespace, `,` and `_` separate tokens and are dropped; each token may carry one leading `0x`/`0X`; a token must then be non-empty, all `[0-9a-fA-F]`, and of *even* length** (which is what rejects the `0x0` foot-gun before it silently shifts every later byte). Tokens concatenate into one lowercase hex string. Rationale for tolerance at all: the library will not do it — `hexToBytes` rejects an odd length or one stray character as `PreloadNotHex` → status 2 (`lib/libcirc/json.zig:12-18`), a bad-request error the reader cannot act on. Rationale for the even-token rule: words are whole bytes (`bpw = ceil(W/8)`), so a lone nibble is never meaningful.

Validation runs in `lib/memimage.zig:51-62`'s exact order — length multiple, then word count, then bits above `W` — so the first message the reader sees client-side is the one the library would have produced. The three shared messages are copied verbatim from `lib/engine_session.zig:75-83`:

| Error | Message |
|---|---|
| `not_word_multiple` | `length {bytes} is not a multiple of {bpw} byte(s)` |
| `too_many_words` | `{words} words exceed capacity {2^A}` |
| `word_exceeds_width` | `a word has bits set beyond data width {W}` |
| `bad_char` | `unexpected character '{char}' at offset {index}` *(client-only)* |
| `odd_token` | `'{token}' has an odd number of hex digits` *(client-only)* |

The bits-above-`W` check needs no BigInt: only the top byte of a word can carry stray bits, and only when `W % 8 !== 0` — `hiMask = W % 8 === 0 ? 0 : (0xff << (W % 8)) & 0xff`, tested against `bytes[i * bpw + bpw - 1]`.

**The write plan and the host.** Structural typing, so both a `CircRuntime` (`topology` at `circ-renderer/src/wasm/runtime.ts:209`, `raw` at `:326`) and a bare `WebAssembly.Instance.exports` + `decodeFullTopology(...)` pair satisfy it — which is what lets `bun test` prove the sequence with no renderer, no canvas and no jsdom:

```ts
export interface RomWrite { name: string; bytes: Uint8Array | null } // null = memClear

/** Re-parse the reader's raw text against the CURRENT symbols, so a source edit
 *  from `rom code[8,4]` to `rom code[16,4]` re-validates instead of writing stale
 *  bytes. Names no longer declared as a root rom are skipped (keeping their text
 *  in the session map, so restoring the declaration restores the image). */
export function romPlan(
  images: ReadonlyMap<string, string>,
  roms: readonly MemorySymbol[],
): { writes: RomWrite[]; rejected: { name: string; message: string }[] };

/** name -> canonical hex, for `options.preloads` (DOCS/libcirc-api.md:54). rom only. */
export function preloadsFor(
  images: ReadonlyMap<string, string>,
  roms: readonly MemorySymbol[],
): { preloads: Record<string, string>; rejected: { name: string; message: string }[] };

export interface MemoryHost {
  topology: { components: readonly { id: number; kind: number; name: string; width: number; origin: readonly unknown[]; memory?: { addrWidth: number } }[] };
  raw: {
    memory: WebAssembly.Memory;
    getMemInfo?(id: number): number;                    // DOCS/wasm-api.md:30
    memBuffer?(id: number): number;                     // :31
    memLoad?(id: number, len: number): number;          // :32
    memClear?(id: number): number;                      // :34
  };
}

export function applyRomImages(
  host: MemoryHost,
  writes: readonly RomWrite[],
  roms: readonly MemorySymbol[],
): { applied: string[]; failures: { name: string; message: string }[] };

/** The whole island-side act, so `bun test` can reach it: `romPlan` + one
 *  `applyRomImages` + exactly one `refresh()` — and NO `refresh()` when the
 *  plan writes nothing. The island's `buildSim()` calls only this (decision 15
 *  and the plan prompt's trap: push as much behaviour as possible into pure
 *  functions `bun test` can reach; no browser has ever been available here). */
export function applyToView(
  host: MemoryHost & { refresh(): void },
  images: ReadonlyMap<string, string>,
  roms: readonly MemorySymbol[],
): { applied: string[]; failures: { name: string; message: string }[] };
```

`applyRomImages` never throws, which is what keeps a bad image out of `buildSim()`'s `try/catch` and off the canvas. Two guards do that work between `memBuffer` and the copy. (a) **`memBuffer(id)` may return `-1`** — it is documented as "a pointer to the memory's staging buffer, or -1" (`DOCS/wasm-api.md:31`), and `new Uint8Array(buffer).set(bytes, -1)` throws a `RangeError`; a return `<= 0` is therefore a `failures` entry reading `staging buffer unavailable for '<name>'` and **no** write. (b) After the re-view, `ptr + bytes.length > host.raw.memory.buffer.byteLength` is a `failures` entry and no write, so the copy can never run past linear memory.

`MEM_LOAD_STATUS` maps the return code to a sentence, mirroring `DOCS/wasm-api.md:111-119`: `-1` not initialised, id out of range, or not a `rom`/`ram`; `-2` image length is not a whole number of words; `-3` a word has a bit set at or above the data width; `-4` more words than the memory holds; `-5` `len` is negative or exceeds the staging buffer; `-6` `memBuffer` was never called for this memory; `-7` address out of range.

**The island's session state.** Added to the `state`/`sim` objects at `Playground.astro:105-114` and `:337-346`:

```ts
// No `settings` field: the drawer reads `store.envelope.settings` and commits
// through `store.update()`, so there is exactly one copy (see Modified files).
romImages: new Map<string, Map<string, string>>(),
   // activeId -> (memory NAME -> the reader's raw text). By NAME inside a
   // project, never by id: ids shift as the source changes
   // (Playground.astro:341). Scoped by Phase 4's `activeId`
   // (DOCS/PLANS/PHASE_4_workspace_and_share.md:8) because two projects may
   // both declare `rom code`: the inner map is cleared when its project is
   // deleted and is NEVER carried across a project switch — `romPlan`'s
   // deliberate "keep the text for names no longer declared" would otherwise
   // make a cross-project leak persist rather than self-heal.
romNotes: new Map<string, string>(),       // memory NAME -> the last inline message,
                                           // for the active project only
```

## Execution & Concurrency Model

This phase is **fully synchronous on the main thread**. It introduces no worker, no timer of its own, and no background task; the only asynchrony it participates in is what Phases 1 and 3 already established — the `LibcircClient` round-trip (`site/src/scripts/libcirc-client.ts:63-66`) and the two debounces with a sequence counter per stage.

Three ownership rules make that safe:

1. **Two wasm instances, two owners, no sharing.** The worker owns `libcirc.wasm` and handles messages serially (`site/src/workers/libcirc.worker.ts:72-81`); the page owns the *artifact* instance the renderer created (`circ-renderer/src/wasm/runtime.ts:148-207`). `applyRomImages` only ever touches the second. No lock, no channel, no atomics — the artifact instance is reachable from exactly one place, `Playground.astro`'s `sim.view`.
2. **An image edit bumps the build sequence.** Changing an image, or any truth-table setting, increments the same `BUILD` sequence counter Phase 3 introduced, so a `truth_table` reply computed with the previous `preloads` is dropped on arrival rather than painted over the new state. This matters because dropping a stale reply is *not* cancellation — `LibcircClient` has no abort and no timeout, and the wasm keeps computing (`DOCS/PLANS_PROMPT.md`, Pillar 4(d)). A 4096-row table cannot be stopped; `capRefusal()` is the only real defence, which is why it runs before the request is built.
3. **`memBuffer` invalidates every outstanding view of `raw.memory.buffer`.** `applyRomImages` therefore takes a *fresh* `new Uint8Array(host.raw.memory.buffer)` between the `memBuffer(id)` call and the `set(...)`, once per memory, never hoisted out of the loop (`DOCS/wasm-api.md:98`; the working sequence is `circ-renderer/test/runtime.test.ts:56-61`). Writing through a view taken before the call is the one way this phase can silently corrupt linear memory.

**Re-application points.** Every path that produces a *new* artifact instance loses the memory contents, because `CircRuntime.loadFromBytes` instantiates a new module and boots pins to LOW (`circ-renderer/src/wasm/runtime.ts:194-204`) with all cells undefined (`DOCS/wasm-api.md:90`). All four such paths funnel through `buildSim()` (`Playground.astro:359-416`) — the artifact-hash change (`:433-436`), the Simulate-tab click (`:442-444`), the theme `MutationObserver` (`:452-455`) and `onAssetsReady` (`:408-411`) — so the apply is hooked **once, inside `buildSim`**, after `simNote.textContent = 'Click input pins to toggle them.'` (`:384`) and before the by-name pin replay (`:386-398`) — *after* `:384`, not merely after `simMount.appendChild(view.canvas)` (`:382`), because `:384` unconditionally overwrites `.pg-sim-note` and would otherwise erase a ROM failure message on every build. Applying before the replay means a replayed address pin settles against loaded contents; `memLoad` re-presents the memory's `out` before returning either way, so no `run()` is needed (`DOCS/wasm-api.md:105`), but a `view.view.refreshState()` **is** — nothing polls, the canvas redraws only when told (`circ-renderer/src/render/canvas.ts:151-163`).

The fifth path is an image edit while a view is already live: `applyRomImages` runs against `sim.view` directly, with no rebuild (a rebuild would discard the reader's pin toggles for a change that does not affect layout), followed by the same `refreshState()`.

## Persistence & I/O

- **`localStorage` only, through Phase 3's store.** The single key `circ.playground.v1`'s `settings` field — already written with full defaults and normalised key by key by Phase 3 (`DOCS/PLANS/PHASE_3_workbench.md:181,183`) — becomes reader-controlled; nothing else in the envelope changes, no key is added or removed, and `version` stays `1` (decision 7). Every read and write stays inside Phase 3's `try/catch` — `localStorage` can *throw*, not merely return null, in a private window or with site data blocked (`ThemeToggle.astro:14`, `Base.astro:66-72` model this). A `version` mismatch resets the whole envelope to `defaultEnvelope()` with a status-bar note — Phase 3's `normalize` already does this (`:183`) and this phase adds nothing to it; there is no migration path before v2. A settings change is a `store.update((d) => { d.settings.<field> = … })` riding Phase 3's existing 500 ms debounce; it does not add a second writer and does not fork the envelope's live `settings` object.
- **ROM images are never persisted, never shared, never sent anywhere but the compiler.** They live in `state.romImages` for the session (see *Explicitly deferred* for the 512 KiB-vs-256 KB arithmetic). They reach the worker as `options.preloads` hex and the artifact instance as bytes in the page's own linear memory; nothing crosses the network, which keeps `/playground`'s promise that "nothing leaves the page" (`site/src/pages/playground.astro:13-19`) intact.
- **No new file-system, network or build-time I/O.** No committed artifact changes, no `bun run libcirc`, no `bun run scripts/compile-content.ts`, no Zig. The `bun test` integration cases read two files that are already committed — `site/public/wasm/libcirc.wasm` and `libcirc.manifest.json` — the way `site/test/renderer-pin.test.ts:13-14` already does.
- **Crash contract.** There is none to add: a torn write is impossible (one `JSON.stringify` per debounce tick), and a corrupt or partial envelope is absorbed by Phase 3's `normalize`, which is total over `unknown` (`DOCS/PLANS/PHASE_3_workbench.md:183`) — this phase adds no second normaliser.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each. Gates for every slice: `bun test` and `bun --bun run build` (never plain `bun run build` on this machine), plus `bun run bundle` for any slice that can change `/playground`'s eager module graph (**1**, 4, 5, 6) — slice 1 is where `settings-drawer.ts` first enters that graph.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The per-op option builder and the compile gate | `site/src/scripts/settings-drawer.ts`'s pure half — `optionsFor`, `capRefusal`, `DOCUMENTED_OPTION_KEYS` — importing `PlaygroundSettings` from `site/src/utils/playground-store.ts` and declaring **no type, no defaults and no normaliser** of its own (Phase 3 owns all three: `DOCS/PLANS/PHASE_3_workbench.md:105-121,181,183`). `Playground.astro` routes `compile` (`:194`), `runPreview` (`:221`) and `runTruth` (`:242`) through `optionsFor(op, store.envelope.settings)` and replaces the `:237-240` pre-flight with `capRefusal()`; `UI_INPUT_BITS_CAP` is deleted. `shouldCompile` in `site/src/scripts/pipeline.ts` (Phase 3's, `:317,:355,:388`) is widened in place to `shouldCompile(analysis: { doc: number; errors: number; warnings?: number } | null, doc: number, warningsAsErrors = false): boolean`, returning false exactly when `analysis` is for `doc` and `analysis.errors + (warningsAsErrors ? (analysis.warnings ?? 0) : 0) > 0` — both additions optional, so Phase 3's four existing cases (`PHASE_3_workbench.md:415`) compile and pass unchanged — so `analyze`, which ignores the option (`lib/libcirc.zig:127-138`), and `compile`, which honours it (`:119`), cannot disagree. Behaviour-neutral by construction: the defaults reproduce today's `{color:'never'}` and `{format:'json', truth_table_cap:12}` exactly, and the gate change is inert while `warningsAsErrors` is `false`, which is Phase 3's default (`:181`). | `bun test site/test/settings-drawer.test.ts`: `optionsFor` emits only keys in `DOCUMENTED_OPTION_KEYS` for all four ops over a swept settings matrix; `optionsFor('analyze', …)` is `{}`; `optionsFor('preview', …).color === 'never'`; for every cap 1..24, `optionsFor('truth_table', s).truth_table_cap === s.truth_table_cap` **and** `capRefusal(cap, s) === null` while `capRefusal(cap + 1, s) !== null` — the drift proof for decision 13's two points. `bun test site/test/pipeline.test.ts`: a fresh analysis with `errors: 0, warnings: 1` gives `shouldCompile === true` with `warningsAsErrors` off and `false` with it on, and `errors: 0, warnings: 0` is unaffected either way. (The clamp/fallback cases belong to Phase 3's `normalize` test, `DOCS/PLANS/PHASE_3_workbench.md:408`; this phase adds no second normaliser.) Plus `bun --bun run build` **and `bun run bundle`** — `settings-drawer.ts` enters `/playground`'s eager graph here, so this is the first slice that must re-prove the 360 KB raw / 120 KB gzip ceiling against `/playground`'s committed `site/bundle-budget.json` row. |
| 2 | The ROM image codec | `site/src/utils/rom-image.ts`: `bytesPerWord`, `maxWords`, `parseRomImage`, `validateRomBytes`, `romSymbols`, the message table, `ROM_KIND`/`RAM_KIND` literals. Pure; no DOM, no `circ-renderer` import. | `bun test site/test/rom-image.test.ts` (unguarded block): tolerance table — `"00112233"`, `"00 11 22 33"`, `"0x00,0x11\n// note\n0x22 0x33"`, `"00_11_22_33"` all yield the same four bytes and the same lowercase `hex`; the five error kinds each fire with the documented message, in `lib/memimage.zig:51-62`'s order; `[12, 4]` accepts `bpw = 2` and rejects a word with bit 12 set; `[8, 4]` rejects 17 words with `17 words exceed capacity 16`; `[64, 16]` computes `bpw = 8` without BigInt; and `ROM_KIND` / `RAM_KIND` equal `ComponentKind.Rom` / `.Ram` imported from `circ-renderer` **in the test**, mirroring `source-link.test.ts`'s guard (`DOCS/PLANS/PHASE_5_source_linking.md:359`) so the two hard-coded copies of the wire bytes cannot drift. Guarded block: `parseRomImage(...).hex` for a 16-byte ramp, sent as `options.preloads` through the committed `libcirc.wasm` for `input[4] pc / rom code[8,4](addr=pc.out) / output[8] out(in=code.out)` (`tests/fixtures/circuits/rom_lookup.circ`), returns status 0 — proving the site's canonical hex never trips `PreloadNotHex`; and a 17-word image returns status 3 with `truth-table: preload 'code': 17 words exceed capacity 16`, proving the client message and the library message are the same sentence. |
| 3 | `applyRomImages` — the runtime write sequence | `romPlan`, `preloadsFor`, `MemoryHost`, `MEM_LOAD_STATUS`, `applyRomImages`: id join by name over `topology.components` restricted to `origin.length === 0 && kind === ROM_KIND`; `getMemInfo(id)` decoded as `kind = info >>> 16`, `W = (info >> 8) & 0xff`, `A = info & 0xff` and checked against the symbol's `width`/`addrWidth` — **a mismatch disables that memory with a visible message instead of writing to the wrong id** (decision 12); `memBuffer` → re-view → `set` → `memLoad`; a `memBuffer(id)` return `<= 0` (`DOCS/wasm-api.md:31`) is a `failures` entry reading `staging buffer unavailable for '<name>'` with **no** write, and a `ptr + bytes.length > raw.memory.buffer.byteLength` check runs after the re-view so the copy can never write past linear memory; an empty image → `memClear`. Plus `applyToView(host, images, roms)` — `romPlan` + `applyRomImages` + exactly one `refresh()`, and no `refresh()` at all when the plan writes nothing — which is the one function slice 6's island calls. | `bun test site/test/rom-image.test.ts` (guarded block): compile the rom source with the committed `libcirc.wasm`, `WebAssembly.instantiate` the artifact with `libcirc.test.ts:21-27`'s `RUNTIME_IMPORTS`, stage `circ.topology.v0.min` via `topology_alloc` + `init` (`libcirc.test.ts:57-60`), build a `MemoryHost` from those exports plus `decodeFullTopology` of the `.full` section (`renderer-pin.test.ts:25-28`), run `applyRomImages` with the 16-byte ramp, then `setPin(pc, 3n, 0xfn)`, `run()` and assert `getOutputValue(out) === 0x33n` **and** `getOutputDefined(out) === 0xffn` — the same assertion as `circ-renderer/test/runtime.test.ts:62-64`, through the site's function. Also: `getMemInfo` returns `(8 << 16) | (8 << 8) | 4`; a host stubbed to report `W = 16` yields a `failures` entry and **zero** `memLoad` calls; a host with `getMemInfo` absent (a pre-v03 artifact) yields one failure and no throw; a host whose `memBuffer` returns `-1` yields one failure, **zero** `memLoad` calls and no throw; an empty write calls `memClear` and the cell reads back undefined. And, against a fake `MemoryHost` recording calls: `applyToView` issues the `memBuffer` → re-view → `memLoad` sequence once per rom and calls `refresh()` exactly once, a plan with no writes calls neither `memLoad` nor `refresh()`, and a `getMemInfo` mismatch produces a `failures` entry, no `memLoad` and still one `refresh()`. |
| 4 | The drawer: markup, controls, persistence | `mountSettingsDrawer()`; the `<details id="pg-settings">` with `<summary>`, three `<fieldset>` groups (Preview / Truth table / Compile) and `<label for>` on all six controls; the `.pg-output-head` wrapper that keeps the toggle **outside** `role="tablist"`; `Escape` closes when focus is inside; the `.pg-settings*` CSS in the `.pg*` block; **the drawer reads `store.envelope.settings` and commits through `store.update((d) => { d.settings.<field> = … })`** — no new store code, no second normaliser, no island-local copy; the cap control's `<label>` and its `aria-describedby` note carry the live row count (`2 ** cap`, rendered as `4,096 rows` at 12 and `16,777,216 rows` at 24) and state that a table above roughly 2^16 rows cannot be cancelled once sent — `LibcircClient` has no abort and no timeout (`site/src/scripts/libcirc-client.ts:63-66`) and the worker is shared by every island on the page (decision 11), so the request blocks all of them until it finishes; a change re-runs only the affected stage (table below). | `bun test site/test/settings-drawer.test.ts`: an envelope written with non-default settings reads back identical through `writeEnvelope()` then `readEnvelope()` over an injected `StorageLike` (Phase 3's real exports — `DOCS/PLANS/PHASE_3_workbench.md:150-178`; there is no `read()`/`write()` pair); the envelope's key set and `version` are unchanged from Phase 3's, `settings.romImages` included (a literal comparison, so an added key, a removed key or a bump fails the test); a `version: 2` envelope reads back as `defaultEnvelope()`. Phase 0's build-free bundle-graph test still green (no `@codemirror/*` reachable from `Base.astro`). `bun --bun run build` + `bun run bundle` with `/playground` under 360 KB raw / 120 KB gzip. **Manual, recorded in STATUS as unrun:** tab to the summary, `Enter` to open, tab through all six controls, flip the theme with the drawer open, reload and find the settings. |
| 5 | The ROM loader UI and truth-table preloads | A fourth `<fieldset>` rendered from `romSymbols(state.analysis.symbols, rootFileId(state.analysis.files, rootPath))` — Phase 5's export from `site/src/scripts/source-link.ts` (`DOCS/PLANS/PHASE_5_source_linking.md:204`), the same value `rootInputBits()` uses after `:340`; this phase adds no second root-file lookup: one row per root `rom` showing `name [W, A]`, its capacity in words, a `<textarea>` bound to `state.romImages.get(activeId)`, a Clear button, and an `aria-live="polite"` paragraph referenced by `aria-describedby`; one disabled informational row per root `ram`; a one-line note that images are not saved. `runTruth` sends `preloadsFor(...)`. `format !== 'json'` renders the library's text in `<pre class="pg-table-text">`; `value_format: 'hex'` cells arrive as strings (`lib/truth_table/json.zig:8-12`). Status-3 bodies render verbatim in `.pg-refusal`, and a body matching `/^truth-table: preload '([^']+)': (.*)$/` (`lib/libcirc/modes.zig:102`) also echoes its reason next to that rom. | `bun test site/test/rom-image.test.ts`: `preloadsFor` emits `{name: hex}` only for names the current `roms` list declares as `rom`, drops a `ram` name, drops an image that no longer validates after a `[8,4] → [16,4]` edit (with a `rejected` entry), and returns `{}` when nothing is loaded — so `optionsFor` omits the key entirely; and a case proving images stored under project A are not visible once `activeId` moves to B, even when both projects declare `rom code` (the per-project map in *Data & State*). Guarded: a `truth_table` request carrying the ramp for the rom source returns status 0 and the JSON table's `out` column contains `0x33`'s decimal `51` at the row where `pc === 3`; and a `truth_table` request carrying **no** preloads against `ram data[8, 4](addr = a.out, din = d.out, we = we.out, clk = clk.out)` returns status 3 whose `error` starts `truth-table: ram 'data' is stateful` (`lib/libcirc/modes.zig:103-106`) — the ram check runs only *after* the preload loop (`:124-149`), so re-using the rom request's `preloads: {code: …}` here would refuse with `truth-table: preload 'code': no memory named 'code' (declared memories: ram data[8, 4])` (`:130-140`) instead, which is exactly why `preloadsFor` must drop `ram` names rather than send them. Also in this slice: the one-grep confirmation that Phase 5 attached its header link per `<th>` (see *Open Questions*), recorded in STATUS. Plus `bun --bun run build` + `bun run bundle`. |
| 6 | Canvas wiring: apply on every rebuild and every edit | `buildSim()` calls `applyToView(...)` — one call, which does `romPlan` + `applyRomImages` + the single `view.view.refreshState()` — **after `simNote.textContent = 'Click input pins to toggle them.'` (`:384`)**, which would otherwise clobber the failure message, and before the by-name pin replay (`:386-398`); the local `CircView` type (`:330-335`) is widened here to carry `runtime.raw` and per-component `width` / `memory?: { addrWidth }` (see *Modified files*), which is what makes `sim.view.runtime` satisfy `MemoryHost`; failures render in `.pg-sim-note` (`:98`) and next to the offending rom; an image edit re-applies to the live `sim.view` with no rebuild and bumps the build sequence; when Simulate is disabled by the version-skew banner (`:158-165`) the loader still feeds the truth table and says the canvas half is off. | `bun test site/test/rom-image.test.ts`: with a fake `MemoryHost` recording calls, `applyToView` issues the `memBuffer` → re-view → `memLoad` sequence once per rom and calls `refresh()` exactly once; a plan with no writes calls neither `memLoad` nor `refresh()`; a `getMemInfo` mismatch produces a `failures` entry, no `memLoad` and still one `refresh()` (the slice-3 cases, now also the proof for the island's single call site — no browser has ever been available in a session on this branch, so the behaviour has to live where `bun test` can reach it: decision 15). Gates: `bun test` all green, `bun --bun run build`, `bun run bundle`. **Manual, recorded in STATUS as unrun:** type `input[4] pc / rom code[8, 4](addr = pc.out) / output[8] out(in = code.out)`, paste `00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff`, open Simulate, click `pc` to `0011`, read `0x33` on `out`; flip the theme and confirm the value survives the rebuild; read the same word out of the Truth table tab. |
| 7 | Decisions, docs, and the phase walk-through | Append this phase's `###` decisions to `DOCS/decisions/playground.md` (settings are the envelope's sixth field and the option names are verbatim; the tolerant-in-the-browser / canonical-on-the-wire hex split; ROM images are session-only, with the 512 KiB-vs-256 KB arithmetic); add any trap this phase hit to `DOCS/PLANS_PROMPT.md`'s Recurring Traps; confirm `DOCS/decisions/index.md`'s Topics entry for `playground.md` names the new headings. | Docs-only. Gates: `bun test` and `bun --bun run build` still green (proving the docs commit is clean of stray edits). The STATUS entry carries the full manual checklist from slices 4 and 6 with its actual run state. |

Slices are ordered by dependency: 1 and 2 are pure and independent of each other but 1 lands first because it is the one that removes `UI_INPUT_BITS_CAP`; 3 needs 2's validator; 4 needs 1's type; 5 needs 2, 3 and 4; 6 needs 3 and 5. Each is fully reviewable on its own and leaves the page working.

**Which stage a settings change re-runs** (so a cosmetic change never rebuilds the canvas or the artifact; `build` is Phase 3's `BUILD_DEBOUNCE_MS` `Stage`, and `state.gen` was deleted in Phase 3 slice 5 — `DOCS/PLANS/PHASE_3_workbench.md:388`):

| Changed | Re-runs |
|---|---|
| `expandMacros`, `expandDisplay` | `runPreview(build.seq)` if the Preview tab is active; nothing otherwise |
| `format`, `valueFormat`, `truthTableCap`, any ROM image | `runTruth(build.seq)` if the Truth table tab is active; plus, for an image, `applyToView` on the live `sim.view` |
| `warningsAsErrors` | the full build stage — Phase 3 split `fire()` into an analyze runner and a build runner (`DOCS/PLANS/PHASE_3_workbench.md:388`) — because it changes `compile` (`lib/libcirc.zig:119`) and therefore the artifact and the canvas |

Note on `warnings_as_errors`: `analyze` ignores it (`lib/libcirc.zig:127-138`), so with it on the diagnostics panel would say "0 errors, 1 warning" while `compile` returns status 1 and the status bar says "Compile reported diagnostics" (`Playground.astro:203-208`). Slice 1 therefore widens `shouldCompile` in `site/src/scripts/pipeline.ts` — Phase 3 moved this decision out of the island's inline gate when it split `fire()` (`DOCS/PLANS/PHASE_3_workbench.md:317,355,388`) — to count warnings when the setting is on, so the two agree and one pointless `compile` round-trip is skipped. The drawer's label says what the setting costs: a warning then blocks the artifact, and the outputs go `data-stale` — the last good schematic, preview and table stay on screen dimmed (decision 9; `PHASE_3_workbench.md:25`, the `outputsShouldClear` contract at `:319`, slice 5 at `:388`, manual check M5 at `:438`) until the warning is fixed or the setting is turned off. It does **not** empty Simulate.

## Tests

**Unit tests** (pure; no `SKIP_LIBCIRC_TEST` guard, so they run everywhere):

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `optionsFor sends only documented keys` | `settings-drawer.ts` | For all four ops over a swept settings matrix, every emitted key is in `DOCUMENTED_OPTION_KEYS` (`DOCS/libcirc-api.md:46-55`) — the guard against status 2 (`lib/libcirc/json.zig:147-149`). |
| `optionsFor sends only the keys the op uses` | `settings-drawer.ts` | `analyze → {}`; `compile → {warnings_as_errors}`; `preview` includes `color:'never'` and both `expand_*`; `truth_table` includes `format`, `value_format`, `truth_table_cap`, and `preloads` only when non-empty. |
| `the cap moves in both places at once` | `settings-drawer.ts` | For every cap 1..24: `capRefusal(cap, s) === null`, `capRefusal(cap + 1, s)` names both the bit count and the cap, and `optionsFor('truth_table', s).truth_table_cap === cap`. Decision 13's drift proof. |
| `parseRomImage tolerates the documented forms` | `rom-image.ts` | Whitespace, `0x`/`0X`, `,`, `_` and `//` comments all normalise to the same lowercase even-length `hex` and the same bytes. |
| `parseRomImage rejects in the compiler's order` | `rom-image.ts` | `bad_char`, `odd_token`, then `not_word_multiple` → `too_many_words` → `word_exceeds_width`, matching `lib/memimage.zig:51-62`, with the three shared messages byte-identical to `lib/engine_session.zig:78-81`. |
| `bytesPerWord and the width mask cover 1..64` | `rom-image.ts` | `bytesPerWord(1..64) === ceil(W/8)`; the top-byte mask rejects exactly the bits at or above `W` for `W = 12`, `W = 8` and `W = 64`; no BigInt is used. |
| `romSymbols filters to the root file's memories` | `rom-image.ts` | Only `file_id === rootFileId` and `kind` of `rom`/`ram`; a `<builtin>/…` file id is excluded (`DOCS/analyze-api.md:55`); a rom symbol missing `addr_width` is dropped, not guessed. |
| `preloadsFor drops what the source no longer declares` | `rom-image.ts` | A `ram` name, a vanished name, and an image invalidated by a `[8,4] → [16,4]` edit are all excluded and appear in `rejected`; an empty result is `{}` so the option key is omitted. |
| `applyRomImages refuses a getMemInfo mismatch` | `rom-image.ts` | With a stub host reporting `W = 16` for a symbol declaring `W = 8`, `memLoad` is never called and `failures` names the memory (decision 12's "rather than writing to the wrong id"). |
| `applyRomImages tolerates a pre-v03 artifact` | `rom-image.ts` | With `getMemInfo`/`memBuffer`/`memLoad` absent from `raw` (all optional — `circ-renderer/src/wasm/runtime.ts:50-57`), one failure is returned and nothing throws. |
| `the settings envelope keeps one key and version 1` | `settings-drawer.ts` + `playground-store.ts` | A round-trip through `writeEnvelope()` then `readEnvelope()` over an injected `StorageLike` (`DOCS/PLANS/PHASE_3_workbench.md:150-178`) preserves the six reader-facing settings and leaves the envelope's key set — `settings.romImages` included, still `{}` — and its `version` exactly as Phase 3 wrote them; a `version: 2` envelope resets to `defaultEnvelope()`. |

**Integration tests** (wasm-driven; in `describe.skipIf(process.env.SKIP_LIBCIRC_TEST === '1')` mirroring `site/test/libcirc.test.ts:12,29` — never set that variable to make a slice pass):

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `canonical hex is accepted as a preload` | committed `libcirc.wasm` | `parseRomImage(...).hex` for a 16-byte ramp, sent as `options.preloads: {code: hex}` with the rom source, returns status 0 — the site's output never trips `PreloadNotHex` (`lib/libcirc/json.zig:14-16`). |
| `an over-capacity preload refuses with the shared sentence` | committed `libcirc.wasm` | A 17-word image returns status 3 whose `error` is `truth-table: preload 'code': 17 words exceed capacity 16` — identical to the client-side message (`lib/libcirc/modes.zig:102`, `lib/engine_session.zig:79`). |
| `a ram refuses with the library's own message` | committed `libcirc.wasm` | `ram data[8, 4](addr=…, din=…, we=…, clk=…)` returns status 3 starting `truth-table: ram 'data' is stateful` (`lib/libcirc/modes.zig:103-106`), which is what the panel renders verbatim. |
| `the loaded word appears in the truth table` | committed `libcirc.wasm` | With the ramp preloaded and `format: 'json'`, the row where `pc === 3` has `out === 51` (`0x33`); with `value_format: 'hex'` the same cell is the **string** `"33"` (`lib/truth_table/json.zig:44-56,74-76`). |
| `the loaded word appears through applyRomImages` | committed `libcirc.wasm` + the compiled artifact | Compile the rom source, instantiate the artifact (`site/test/libcirc.test.ts:21-27,55-60`), decode `circ.topology.v0.full` (`site/test/renderer-pin.test.ts:25-28`), run `applyRomImages`, drive `pc` to `3n`, and assert `getOutputValue(out) === 0x33n` and `getOutputDefined(out) === 0xffn` — the site's own path reaching `circ-renderer/test/runtime.test.ts:62-64`'s result. |
| `an emptied image clears the memory` | the compiled artifact | A `RomWrite` with `bytes: null` calls `memClear` (`DOCS/wasm-api.md:34`) and the addressed cell reads back `getOutputDefined === 0n`. |
| `the committed module still emits the memory family` | committed `libcirc.wasm` | `WebAssembly.Module.exports(artifact)` contains all eight of `getMemInfo`, `memBuffer`, `memLoad`, `memStore`, `memClear`, `setMemWord`, `getMemValue`, `getMemDefined` — the standing guard that a later regeneration cannot silently drop the family this phase depends on. |

Run command (from `site/`): `bun test` — or, for this phase alone, `bun test test/rom-image.test.ts test/settings-drawer.test.ts`. The build gate is `bun --bun run build` (**plain `bun run build` fails on this machine**: local `node` is x64 under Rosetta and rollup's native loader aborts), followed by `bun run bundle` for slices 1, 4, 5 and 6 — slice 1 is the one that first puts `settings-drawer.ts` into `/playground`'s eager graph. No Zig gate: this phase changes no Zig.

## Open Questions / Spikes

The plan prompt's *Open items* list carries **no `TODO(phase6)` entry** — nothing from that list is this phase's to resolve. Four questions that would otherwise have been open were closed by reading the code and the shipped phase plans during planning, and are recorded here rather than left as markers:

- **Does the committed `libcirc.wasm` emit artifacts that carry the memory family?** Yes. `strings -a site/public/wasm/libcirc.wasm` finds all eight of `getMemInfo`, `memBuffer`, `memLoad`, `memStore`, `memClear`, `setMemWord`, `getMemValue`, `getMemDefined` in the embedded runtime's export section, and the manifest reports `topology_version 3` / `full_version 3` (`site/public/wasm/libcirc.manifest.json`), which `circ-renderer`'s decoder accepts (`src/wasm/topology.ts:160,168`). The canvas half of this phase is not blocked on Phase 0's regeneration. The standing guard is the last integration test above.
- **Must the site decode `circ.topology.v0.full` itself to find a memory's id?** No. `CircRuntime` already decodes it at load and exposes it (`circ-renderer/src/wasm/runtime.ts:187-193`, getter at `:209`), so the island reads `view.runtime.topology.components` — which also avoids handing the transferred artifact `Uint8Array` to a second consumer (`site/src/workers/libcirc.worker.ts:63-65`; the trap is a detached buffer). `bun test` builds the same structure from `decodeFullTopology` directly, which is why `applyRomImages` takes a structural `MemoryHost` instead of a `CircRuntime`.
- **Does `memLoad` redraw the canvas?** No. `memLoad` re-presents the memory's `out` inside the runtime (`DOCS/wasm-api.md:105`), but the canvas paints only from `refreshState()`, which pulls `runtime.snapshot()` and draws (`circ-renderer/src/render/canvas.ts:151-163`). Nothing polls, so the apply must call it.
- **Does Phase 5's truth-table-header source link survive `format: 'markdown' | 'csv'`?** Yes, with no work. Phase 5 attaches `data-symbol-name` / `data-symbol-kind` (via `headerSymbolName`) plus `tabindex="0"` and the four `pointerenter`/`pointerleave`/`focus`/`blur` handlers to each `<th>` as the JSON renderer creates it (`DOCS/PLANS/PHASE_5_source_linking.md:342`, slice 7, over `Playground.astro:250-256`); there is no panel-level or delegated listener to detach, so the `<pre class="pg-table-text">` branch simply has no links. Slice 5 confirms this against the shipped code in one grep before writing the branch and records the confirmation in STATUS; in the unlikely case Phase 5 shipped a delegated listener instead, slice 5 detaches it in the same commit.

Genuinely open, each with the spike that resolves it:

- **`TODO(phase6)`: where does the drawer toggle sit once Phase 3's status bar and Phase 4's Share button exist?** This plan places it in a new `.pg-output-head` row beside `.pg-tabs` (`Playground.astro:51-56`), deliberately **outside** `role="tablist"` so a non-tab button cannot break the tab strip's roving tabindex. **Spike, in slice 4 before the markup lands:** read the shipped `Playground.astro` status bar and confirm the toggle does not collide with the Share button's row or with the stacked mobile layout at the narrowest breakpoint (`global.css:545-547`); if the status bar is the better home, move it there and say so in STATUS — the drawer's contents and every test above are unaffected by where its toggle lives.
- **`TODO(phase6)`: what is the largest image a reader can paste before the drawer becomes unresponsive?** `parseRomImage` is linear, but a `[64, 16]` memory admits 512 KiB of bytes — over a million hex characters — re-parsed on every keystroke of the textarea. **Spike, in slice 5:** measure `parseRomImage` on a 512 KiB image under `bun test` with `performance.now()`; if it exceeds ~16 ms, debounce the textarea at `BUILD_DEBOUNCE_MS` (Phase 3's 350 ms) instead of parsing on `input`, and record the measured number. The parse stays pure and the tests are unchanged either way.
