# Phase 4 — Workspace, persistence, and share links

> **Dependencies:** Phase 0 (`DOCS/PLANS/PHASE_0_builtins_and_budget.md` — `bun run bundle` and `site/bundle-budget.json` are the gate every slice here re-runs), Phase 1 (`DOCS/PLANS/PHASE_1_editor.md` — `site/src/scripts/circ-editor.ts`; this phase swaps the editor's **document registry** on every project switch, through Phase 2's `setDocuments`/`showDocument`, and adds no new editor API), Phase 2 (`DOCS/PLANS/PHASE_2_file_tabs.md` — `fromSource`/`toSource`/`activeFile`/`rootIndex` in `site/src/scripts/file-tabs.ts` (`:148-153`) over `joinFiles` in `site/src/utils/split-files.ts`, plus the registry `setDocuments`/`showDocument`/`textOf` its slice 3 adds to `circ-editor.ts` (`:232-238,333`); a project's stored `source` is the joined marker string and `activeFile` is a tab name), Phase 3 (`DOCS/PLANS/PHASE_3_workbench.md` — `site/src/utils/playground-store.ts`, the whole `circ.playground.v1` envelope, `readEnvelope`/`writeEnvelope`/`normalize`/`evictOldest`/`browserStorage`/`describeNote` and the `createStore()` handle (`envelope`, `enabled`, `update()`, `flush()`, `onNote()` — `PHASE_3_workbench.md:150-178`) with its 500 ms debounce, the version-mismatch reset and the quota-eviction path; plus the app layout and the `.pg-status-actions` slot the Share button lands in, `:22,378`).
> **Warnings:** Read locked decisions **6** and **7** of `DOCS/PLANS_PROMPT.md:47-48` in full before the first slice; this phase implements them and adds nothing to the envelope. **No new envelope key and no `version` bump** (`PLANS_PROMPT.md:48`). **Never persist example or tour text — store ids** (same line); a pristine content project is a reference, and only the reader's own edit is written. `localStorage` can throw rather than return `null` (`PLANS_PROMPT.md:181`; the models are `ThemeToggle.astro:14` and `Base.astro:66-72`). `site/src/utils/playground-store.ts` must keep **every** `localStorage`/`window` access inside a function — this phase imports catalogue helpers from it in `Playground.astro` frontmatter, which runs in bun at build time. `<PostHog />` is mounted on every page at `Base.astro:62` while `site/src/pages/playground.astro:13-19` promises "nothing leaves the page"; the fragment scrub in slice 5 is what keeps that promise. **Verified against the local bun (1.2.10): `CompressionStream` and `DecompressionStream` are `undefined`**, so the deflate half of decision 6 cannot be tested against the global — `share-link.ts` takes an injectable codec and `site/test/share-link.test.ts` supplies a `node:zlib` one (`deflateRawSync`/`inflateRawSync`, both present and round-tripping in this bun). New CSS goes under `.pg-ws*`, `.pg-share` and `.oip` names. Layout-dependent sidebar rules belong inside the `[data-layout="app"]` block Phase 3 adds *after* the `.pg*` block (`PHASE_3_workbench.md:62`), not in the `.pg*` block itself (`site/src/styles/global.css:528-656` today), or the app-layout rules override them. Nothing under `.lc-*` is touched — `.lc-mount` at `:477` is shared with `LiveCanvas.astro:26`, which `/` and `/examples` both render (`PLANS_PROMPT.md:178`). `site/src/pages/tour.astro:15,31,33` hard-codes `/reference` and `/examples` without `url()`; do not copy that — every link this phase adds goes through `url()` (`site/src/utils/url.ts:6-9`) or it breaks under `BASE_PATH`. Git conduct per `CLAUDE.md:184-206`: stage by path, Conventional Commits under 70 chars, no phase/slice prefixes, no trailers.

## Goal

A visitor opens `/playground` and sees a workspace sidebar listing the ten examples, the seven tour steps and their own scratch projects; clicking a row loads it into the editor. Typing into an example forks it into a named scratch project rather than overwriting the shipped text, and that project is still there after a reload — as are the active project, the active file tab, and everything Phase 3 already persisted, all in the one `localStorage['circ.playground.v1']` envelope. A Share button in the status bar copies a URL whose fragment reproduces the current source byte for byte (`#src=` deflate-raw + base64url, `#src0=` where the browser has no `CompressionStream`, a refusal with "copy the source" instead past 8192 characters); opening that URL in a private window yields the same bytes, lands them in a fresh scratch project named by `generateSillyName()` (`site/src/utils/sillyname.ts:23`), and the fragment is gone from the address bar before PostHog's deferred init script has run. Every example card on `/examples` and every step on `/tour` carries an "Open in playground" link that names content by id (`#pick=example:half-adder`, `#pick=tour:5`) and ships zero new JavaScript to those pages. `bun test`, `bun --bun run build` and `bun run bundle` are green after every slice.

## Scope

**In scope:**

- `site/src/utils/share-link.ts`: `encodeShare` / `decodeShare` / `readHash` / `shareUrl` / `toBase64Url` / `fromBase64Url` / `webStreamsCodec`, all pure, all returning results as values, never throwing, with the 8192-character cap and the `#src=` / `#src0=` key pair of decision 6.
- The scratch-project model filling the Phase 3 envelope's `scratch`, `activeId`, `activeFile` and `tab` fields: create, rename, delete, duplicate, and LRU-by-`updatedAt` eviction under Phase 3's own `MAX_SCRATCH` / `MAX_SOURCE_BYTES` / `MAX_ENVELOPE_BYTES` (`PHASE_3_workbench.md:78-80`, decision 7) — as pure functions added to `site/src/utils/playground-store.ts`, with Phase 3's `evictOldest`/`writeEnvelope` widened to take a `keep` id rather than a second eviction path added. `tab` is claimed here because Phase 3 assigns it to this phase (`PHASE_3_workbench.md:20,31,130`); it costs no key and no `version` bump, and leaving it would strand a field no phase ever reads.
- Copy-on-write: a pristine `example:<slug>` / `tour:<n>` project is stored as an id only; the first edit forks it into a scratch project.
- The workspace sidebar in `Playground.astro`: server-rendered rows for examples and tour steps, client-rendered rows for scratch projects, per-row rename / delete / duplicate, keyboard-operable with native buttons, a desktop toggle and a mobile disclosure.
- Load precedence `#src=` / `#src0=` → `#pick=` → persisted `activeId` → the first catalogue entry, with a status-bar note on every fall-through, and the `history.replaceState` scrub that removes all three keys before PostHog's init module runs.
- The Share button in Phase 3's status bar, its clipboard write, its over-cap refusal and its "copy the source" fallback.
- `site/src/components/OpenInPlayground.astro` and its mounts on `site/src/pages/examples.astro` and `site/src/pages/tour.astro`, with a build-time assertion that every mounted id exists in the catalogue.
- Phase 4's entries appended to `DOCS/decisions/playground.md` (registered in `DOCS/decisions/index.md` if this phase is the first to create it), and `DOCS/PLANS_PROMPT.md`'s `TODO(phase4)` Open item narrowed to the one thing still unmeasured rather than deleted (`PLANS_PROMPT.md:186`; see Open Questions).

**Explicitly deferred:**

- Folder hierarchies in the workspace. Decision 7 says **flat projects only**; the sidebar has three fixed groups and no nesting. langlang's `WorkspaceDirNode` (`workspace/types.ts:5-10`) and its `addDir` / `isDescendant` / `findParentDirId` tree walkers (`workspace/storage.ts:76-149`) are deliberately not ported.
- Collaborative or server-side sharing, a short-link service, and any network I/O (`PLANS_PROMPT.md:73`).
- Import/export of a project as a file, drag-and-drop of `.circ` files, and a per-project settings override. Settings stay one global block filled by `DOCS/PLANS/PHASE_6_settings_and_rom_images.md`.
- Undo across project switches. A switch replaces the whole document registry through Phase 2's `setDocuments(texts, active)` (`PHASE_2_file_tabs.md:232,333`), which builds fresh `EditorState`s and therefore fresh `historyField`s (`:217`), so per-project undo is discarded by construction — the intended semantics (`PLANS_PROMPT.md:73`). Phase 1's `setDoc`, which explicitly *keeps* history (`PHASE_1_editor.md:245`), is deliberately not the mechanism used here.
- The "expand to playground" button on the docs live editors; it consumes this phase's `encodeShare` but ships in `DOCS/PLANS/PHASE_7_live_editors.md`.
- A schema migration. A `version` mismatch resets to defaults, per decision 7; there is no v1→v2 path.
- Any change to the `// <name>.circ` marker format, to `splitFiles`/`joinFiles`, or to `requestFor` (`site/src/utils/split-files.ts:14,16,40`).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site/src/utils | `share-link.ts` | The share codec. base64url helpers, the injectable `DeflateCodec`, `webStreamsCodec()`, `encodeShare`, `decodeShare`, `readHash`, `shareUrl`, `SHARE_CAP`. No DOM, no `location`, no `localStorage`. |
| site/src/components | `OpenInPlayground.astro` | A zero-JavaScript `<a>` to `${url('/playground')}#pick=<id>`, with a build-time assertion that the id is in the catalogue. |
| site/test | `share-link.test.ts` | Round-trip over all 17 shipped sources through both keys, the cap refusal, and every malformed-payload result. |
| site/test | `workspace.test.ts` | Scratch CRUD, the three limits, LRU eviction, `resolveSource`, `resolveInitial` precedence, and the "no content text in the envelope" assertion. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site/src/utils | `playground-store.ts` | Adds the scratch-project ops, the catalogue helpers (`buildCatalogue`, `resolveSource`) and the sync `resolveInitial`, and widens Phase 3's `evictOldest`/`writeEnvelope` with a `keep` id and a `skipped` report, adds the `{ kind: 'skipped'; names: string[] }` variant to `StoreNote` with its `describeNote` case, and threads `keep = env.activeId` plus the `skipped` note through Phase 3's `createStore` debounced writer and quota retry — one eviction implementation and one writer, widened, never duplicated. Phase 3's `readEnvelope`/`writeEnvelope`/`normalize`/`createStore`/`describeNote`, its three limits and its debounce/reset/quota path are reused, never redeclared. Any top-level `localStorage`/`window` access Phase 3 left behind moves inside a function in slice 2. |
| site/src/components | `Playground.astro` | Sidebar markup and its group lists built from `buildCatalogue(examples, tour)`, replacing the `<label for="pg-pick">` / `<select id="pg-pick">` pair at `:28-37` — and with it the island's `#pg-pick` handle (`:92`) and its `change` listener (`:143-145`), since `querySelector('#pg-pick')!` on removed markup returns `null` and throws before the editor mounts. `#pg-picks` (`:66`) keeps its id and its `type="application/json"`, but its body becomes the serialized `CatalogueItem[]`, so the island's `Record<string, string>` cast at `:101` becomes a `CatalogueItem[]` parse. Plus `data-default-pick` on the `.pg` root; an `is:inline` fragment-capture script; the async bootstrap that awaits `decodeShare` before creating the editor; the Share button wired into Phase 3's `.pg-status-actions` slot; the scratch-row event delegation. |
| site/src/styles | `global.css` | `.pg-ws*` rules for the sidebar column, rows, row actions, the inline rename input and the mobile disclosure, plus `.pg-share` and `.oip`. Static appearance sits with the other `.pg*` rules (`:528-656`); every rule that depends on the workbench geometry goes inside Phase 3's `[data-layout="app"]` block, which is declared *after* that block (`PHASE_3_workbench.md:62`) and would otherwise override it. Nothing under `.lc-*` is touched. |
| site/src/pages | `examples.astro` | Mounts `<OpenInPlayground id={`example:${ex.slug}`} />` inside each `<article class="example-card">` (`:26-39`), after `<CodePreview>` at `:29`. |
| site/src/pages | `tour.astro` | Mounts `<OpenInPlayground id={`tour:${i + 1}`} />` inside each `<section class="tour-step">` (`:20-27`), after `<CodePreview>` at `:26`. |
| DOCS/decisions | `playground.md` | Appends `###` entries for the share encoding, the load precedence and scrub, the scratch model and its three limits, and the copy-on-write fork. Created here if no earlier phase created it, and then registered under "Topics" in `DOCS/decisions/index.md` per that file's convention (`###` headings, referenced by slug, never by number). |
| DOCS | `PLANS_PROMPT.md` | Rewrites the `TODO(phase4)` Open item at `:191` down to its residual browser confirmation once slice 5 records the structural argument in STATUS; the entry is deleted only when that confirmation actually runs (`PLANS_PROMPT.md:186`). |
| DOCS | `STATUS.md` | One entry per slice, per the template at `PLANS_PROMPT.md:116-124`. |

**New dependencies:** None. `node:zlib` is used only by `site/test/share-link.test.ts` and is a bun built-in, not a package. `generateSillyName` is already in the bundle graph of every page through `PostHog.astro:22`, so the island's import of it adds nothing new to `/playground` (`site/src/utils/sillyname.ts` is 8,645 raw / 3,840 gzip bytes, measured — if `bun run bundle` shows it duplicated into a second chunk rather than shared, say so in STATUS rather than raising a ceiling).

## Data & State

Ids and the envelope. Both are Phase 3's, unchanged. `PlaygroundEnvelope`, `ScratchProject`, `PickId`, `OutputTab`, `LayoutState`, `PlaygroundSettings`, `STORE_KEY`, `STORE_VERSION`, `MAX_SCRATCH`, `MAX_SOURCE_BYTES`, `MAX_ENVELOPE_BYTES` and `WRITE_DEBOUNCE_MS` are declared at `DOCS/PLANS/PHASE_3_workbench.md:76-131` and are neither redeclared nor renamed here — a second `export const MAX_SCRATCH` or `export interface ScratchProject` in one module is a duplicate-declaration error, and a second name for `PickId` would have `Playground.astro` and `OpenInPlayground.astro` importing two aliases of one type. This phase fills `scratch`, `activeId`, `activeFile` and `tab`, and adds only the surface below.

```ts
// site/src/utils/playground-store.ts — Phase 3 owns `PlaygroundEnvelope` in full
// (`PHASE_3_workbench.md:123-131`). Phase 4 fills exactly four of its fields and
// changes no type: `scratch: ScratchProject[]`, `activeId: PickId | null`,
// `activeFile: string | null` (a tab NAME, e.g. 'root.circ', not a path) and
// `tab: OutputTab` (non-nullable, default 'diagnostics'). `version` stays
// STORE_VERSION; `layout: LayoutState` (Phase 3) and `settings: PlaygroundSettings`
// (Phase 6 — a typed interface, never a `Record<string, unknown>`, precisely so an
// envelope key can never be spread into a libcirc `options` object where an unknown
// key is status 2, `PHASE_3_workbench.md:105-110`) are untouched. No key is added.

/** `PickId` (`PHASE_3_workbench.md:87`) and `ScratchProject` (`:89-98`) are Phase 3's.
 *  Only the kind helper is new here. */
export type ProjectKind = 'example' | 'tour' | 'scratch';

/** Server-rendered rows, the `#pg-picks` blob and `OpenInPlayground` all come from
 *  this one call, so the sidebar, the blob and the links cannot drift. */
export interface CatalogueItem {
  id: PickId;                    // 'example:inverter' | 'tour:5'
  label: string;                 // `examples[].title` verbatim ('Half-adder'), or '5. A half-adder'
  group: 'Examples' | 'Tour';
  source: string;
}
export function buildCatalogue(
  examples: readonly { slug: string; title: string; source: string }[],
  tour: readonly { title: string; source: string }[],
): CatalogueItem[];

// Limits (decision 7) are Phase 3's `MAX_SCRATCH` / `MAX_SOURCE_BYTES` /
// `MAX_ENVELOPE_BYTES` (`PHASE_3_workbench.md:78-80`), counted in UTF-8 bytes exactly
// as `normalize` counts them — "drops any whose source exceeds `MAX_SOURCE_BYTES`
// UTF-8 bytes" (`:183`) — i.e. `new TextEncoder().encode(s).length`. This phase adds
// no limit, changes no value, and introduces no character-counted twin: two limits in
// two units on one field would let a 32,800-byte source pass a write and then be
// dropped by `normalize` on the next read.

export const NEW_PROJECT_SOURCE = 'input a\nnot n(in=a)\noutput out(in=n.out)\n';

export function idKind(id: PickId): ProjectKind | null;
/** `scratch:<base36 ms><base36 rand>` — Phase 3's shape (`PHASE_3_workbench.md:90`).
 *  `now` and `rand` are injected so `bun test` is deterministic and no `crypto` global
 *  is required (`crypto.randomUUID` is absent on older Safari and on any non-secure
 *  origin), and so no second id generator competes with Phase 3's. */
export function newScratchId(now: number, rand?: () => number): PickId;
export function uniqueName(base: string, taken: readonly string[]): string;

export interface ScratchEdit {
  list: ScratchProject[];
  evicted: ScratchProject[];
  /** Refused for exceeding `MAX_SOURCE_BYTES`; kept in memory, never in the envelope. */
  skipped: ScratchProject[];
}
export function createScratch(
  list: readonly ScratchProject[],
  init: { name: string; source: string; now: number; keep?: PickId | null; rand?: () => number },
): ScratchEdit & { created: ScratchProject | null };
export function duplicateScratch(
  list: readonly ScratchProject[], id: PickId,
  init: { now: number; rand?: () => number },
): (ScratchEdit & { created: ScratchProject | null }) | null;
export function renameScratch(list: readonly ScratchProject[], id: PickId, name: string): ScratchProject[];
export function deleteScratch(list: readonly ScratchProject[], id: PickId): ScratchProject[];
/** An over-size body is refused at the source: `list` comes back unchanged with the
 *  offending project in `skipped`, so nothing over `MAX_SOURCE_BYTES` ever reaches the
 *  envelope and no second envelope-fitting pass is needed. */
export function touchScratch(
  list: readonly ScratchProject[], id: PickId, source: string, now: number,
): ScratchEdit;

/** Phase 3's eviction and write path, widened in slice 2 — never duplicated. There is
 *  exactly one eviction implementation. Both gain an optional `keep`, so neither the
 *  pre-write trim loop nor the quota retry (`PHASE_3_workbench.md:365`) can drop the
 *  project the reader is typing into, and `writeEnvelope` reports any scratch source it
 *  had to omit for exceeding `MAX_SOURCE_BYTES`. */
export function evictOldest(env: PlaygroundEnvelope, keep?: PickId | null): string | null;
export function writeEnvelope(
  env: PlaygroundEnvelope, storage: StorageLike | null, keep?: PickId | null,
): { ok: boolean; note: StoreNote | null; skipped: ScratchProject[] };
/** Phase 3's `StoreNote` union gains one variant and `describeNote` one case —
 *  the envelope's key set and `version` are untouched, so decision 7 still holds:
 *    | { kind: 'skipped'; names: string[] }   // sources over MAX_SOURCE_BYTES, kept in memory
 */

export function resolveSource(
  id: PickId, catalogue: readonly CatalogueItem[], scratch: readonly ScratchProject[],
): string | null;
```

The share codec. Every failure is a value; nothing here throws.

```ts
// site/src/utils/share-link.ts
export const SHARE_CAP = 8192;              // characters of payload, decision 6
export type ShareKey = 'src' | 'src0';

export interface DeflateCodec {
  deflateRaw(bytes: Uint8Array): Promise<Uint8Array>;
  inflateRaw(bytes: Uint8Array): Promise<Uint8Array>;
}
/** A codec over CompressionStream('deflate-raw'), or null where the global is
 *  absent or the format is unsupported (Safari < 16.4, Firefox < 113, and bun
 *  1.2.10 — verified: both globals are `undefined` there). */
export function webStreamsCodec(): DeflateCodec | null;

export function toBase64Url(bytes: Uint8Array): string;         // no '=' padding
export function fromBase64Url(s: string): Uint8Array | null;    // null on a bad alphabet

export type EncodeResult =
  | { ok: true;  key: ShareKey; payload: string; fragment: string; chars: number }
  | { ok: false; reason: 'too-large'; key: ShareKey; chars: number; cap: number };

export type DecodeReason =
  | 'no-key' | 'unknown-key' | 'bad-base64' | 'bad-deflate' | 'bad-utf8' | 'no-codec';
export type DecodeResult =
  | { ok: true;  key: ShareKey; source: string }
  | { ok: false; reason: DecodeReason };

export async function encodeShare(
  source: string, codec?: DeflateCodec | null, cap?: number,
): Promise<EncodeResult>;
export async function decodeShare(
  hash: string, codec?: DeflateCodec | null,
): Promise<DecodeResult>;

/** Every key the fragment carries, so `resolveInitial` — not `readHash` — owns the
 *  precedence. Decision 6 requires a failed `#src=` to fall through to `#pick=`
 *  (`PLANS_PROMPT.md:47`), which a three-way union cannot express: it would have
 *  discarded the lower-precedence key before the decode was even attempted.
 *  `{}` means the fragment carried nothing this phase reads. */
export interface HashIntent {
  src?: { key: ShareKey; payload: string };   // `#src=` wins over `#src0=`
  pick?: string;                              // `#pick=<id>`
  /** Present-but-unrecognised keys; decision 6 still owes them a fall-through note. */
  unknown?: readonly string[];
}
export function readHash(hash: string): HashIntent;

/** `new URL(href)` with the fragment replaced; the query is preserved. */
export function shareUrl(href: string, fragment: string): string;
```

The initial-load resolution, sync and pure, called once after the async decode settles. The precedence lives here and is walked one rule at a time — `src` → `pick` → `env.activeId` → `defaultId` — each failure falling through to the *next* rule with a note, never straight to the default (decision 6, `PLANS_PROMPT.md:47`).

```ts
// site/src/utils/playground-store.ts
export type LoadOutcome =
  | { kind: 'share';   source: string; key: ShareKey }
  | { kind: 'pick';    id: PickId; source: string }
  | { kind: 'active';  id: PickId; source: string }
  | { kind: 'default'; id: PickId; source: string };

export function resolveInitial(input: {
  intent: HashIntent;
  decoded: DecodeResult | null;          // null when `intent.src` is absent
  env: PlaygroundEnvelope;               // always present: readEnvelope returns defaults, never null
  catalogue: readonly CatalogueItem[];
  defaultId: PickId;                     // the `.pg` root's data-default-pick
}): { outcome: LoadOutcome; note: string | null };
```

`note` is the status-bar string for a fall-through and `null` on a clean hit — and the two strings name the two landing places the fall-through actually has: `'That share link could not be decoded; opened the last project instead.'` when `env.activeId` is set (outcome `active`), `'Unknown example id in the link; opened the first example instead.'` when it is null (outcome `default`).

Measured headroom for the cap, over every shipped source: the largest is `example:sr-latch` at 521 UTF-8 bytes → **695** base64url characters plain, **390** deflated. `example:two-bit-adder` is next at 508 → 678 / 335. Deflate wins on all 17 sources, so `#src=` is always the shorter key in practice and no shipped source comes within an order of magnitude of the 8192 cap. Where the cap binds depends entirely on how well the text compresses, measured in this bun with `node:zlib` `deflateRawSync`: 12,000 characters of near-random ASCII already exceed it on the deflate path (11,280 base64url characters), while 43,008 characters of repetitive `wire wN(in=a)` lines land at 8,342 — just over — and 40,960 characters of a single repeated line come to 151. Real hand-written circ therefore runs to tens of KB before `#src=` refuses, while the plain fallback refuses at ~6 KB (6,200 characters is 8,267 base64url characters).

## Execution & Concurrency Model

This phase introduces **no worker, no thread and no polling**. It is synchronous on the main thread with exactly two asynchronous seams, both of which resolve before or independently of the compile pipeline:

1. **The share decode.** `CompressionStream` is a `TransformStream`, so `encodeShare`/`decodeShare` are `async`. The island's bootstrap is therefore `async`: it reads the captured fragment, awaits `decodeShare` when `readHash` reports an `src` key, calls the synchronous `resolveInitial` (which owns the fall-through, so a failed decode still reaches a `#pick=` in the same fragment), and only then creates the editor with `createEditor(parent, { doc, … })`. Nothing renders a document twice and there is no flash of the wrong source. The whole path is main-thread stream work over at most 32 KB and completes in well under a frame; it happens before the first-focus `ensureReady()` handshake (`Playground.astro:458`), so it never races the worker.
2. **The debounced write.** Phase 3 owns the single 500 ms debounced writer inside `createStore` (decision 7). Phase 4 adds source text to what that writer writes and adds no listener of its own: Phase 3 already binds `store.flush()` to `pagehide` and `visibilitychange` (`PHASE_3_workbench.md:168,377`), which is what caps the loss at 500 ms of typing — `pagehide`, not `beforeunload`, because `beforeunload` is discouraged and blocks the bfcache.

Ownership of shared state is single-writer by construction: Phase 3's `createStore()` holds the one `PlaygroundEnvelope`, every mutation goes through `store.update(draft => …)` applying a pure function from `playground-store.ts` that returns a new array, every forced write is `store.flush()`, and the only reader of `localStorage` is Phase 3's `readEnvelope(browserStorage())`, called once when the store is constructed. There is no second tab protocol — two `/playground` tabs each keep their own in-memory envelope and the last debounced write wins. That is stated, accepted and out of scope (no `storage` event listener, no locking).

The Share button's clipboard write is user-gesture-driven and fire-and-forget; a rejected `navigator.clipboard.writeText` falls back to a read-only `<input>` the reader can select, and never leaves the button in a pending state.

## Persistence & I/O

- **`localStorage['circ.playground.v1']`, one key, created by Phase 3.** This phase writes `scratch`, `activeId`, `activeFile` and `tab` into it and reads them back at bootstrap. No second key. No `version` bump. Every access is inside Phase 3's `try/catch`; a throw (private window, blocked site data — `PLANS_PROMPT.md:181`) disables persistence for the session and posts a status-bar note, and the page still runs on the in-memory envelope.
- **What is never written:** the `source` of any `example:` or `tour:` project. Those are referenced by id and re-read from `buildCatalogue(...)` on every load, so a `site/src/content/examples.ts` edit reaches the returning reader. The proof is a `bun test` assertion that the serialized envelope of a browse-only session contains none of the 17 shipped sources.
- **Write path, in order:** `store.update()` mutates the in-memory envelope and arms Phase 3's 500 ms debounce; on fire, `writeEnvelope(env, storage, activeId)` omits the **whole project** for any scratch source over `MAX_SOURCE_BYTES` (returned in `skipped`, kept in the in-memory envelope so the reader keeps typing) — never a project record with an empty or missing `source`, which Phase 3's `normalize` would drop on the next read with no note (`PHASE_3_workbench.md:183`) — then evicts least-recently-updated projects other than `activeId` until the serialization fits `MAX_ENVELOPE_BYTES`, then `setItem`; on `QuotaExceededError` Phase 3's path evicts once more — again never `activeId` — retries **exactly once**, then disables persistence for the session and says so (`PHASE_3_workbench.md:365`). There is one eviction implementation, Phase 3's; this phase widens it with `keep` rather than running a second trim over the same array.
- **Crash recovery:** none beyond the debounce plus Phase 3's `pagehide`/`visibilitychange` flush. A hard kill loses at most the last 500 ms of typing. The envelope is self-describing — a `version` mismatch or a `JSON.parse` failure resets to defaults with a note (Phase 3), and this phase adds no partial-write window because `setItem` on one key is atomic.
- **`history.replaceState`** is the only History API use: one call, at document-parse time, replacing the URL with `location.pathname + location.search` when the fragment matches `#src=` / `#src0=` / `#pick=`. Wrapped in `try/catch`; a throw leaves the fragment in place and the island still reads it.
- **`navigator.clipboard.writeText`** is the only other browser API touched, on the Share button only, behind a user gesture, with a visible fallback.
- **No network, no fetch, no file system, no new artifacts.** No Zig, no `bun run libcirc`, no `bun run scripts/compile-content.ts`, so none of the 11 committed `.wasm` files change and the 7 untracked `tour-<N>.wasm` files (`PLANS_PROMPT.md:14,142`) are not produced by this phase at all.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each. Every slice ends green on `cd site && bun test` and `cd site && bun --bun run build`; slices **2** onward also end green on `cd site && bun run bundle`, because slice 2 grows `playground-store.ts`, which Phase 3 already put inside `/playground`'s eager module graph, and decision 14's ceilings are byte ceilings (`PLANS_PROMPT.md:55,99`). Slice 1 adds `share-link.ts` with no importer, so its graph is unchanged.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The share codec | `site/src/utils/share-link.ts` complete: `SHARE_CAP`, `DeflateCodec`, `webStreamsCodec()`, `toBase64Url`/`fromBase64Url` (chunked, `=`-stripped, URL-safe alphabet), `encodeShare`/`decodeShare` (results as values), `readHash` (reports every key the fragment carries — `#src=` over `#src0=` inside `src`, plus `pick` and any `unknown` — leaving the precedence to `resolveInitial`), `shareUrl`. No UI, no imports from the store. | `site/test/share-link.test.ts` under `bun test`: each of the 10 `examples[].source` and 7 `tour[].source` round-trips byte-identically through `#src=` (with a `node:zlib` `deflateRawSync`/`inflateRawSync` codec) and through `#src0=` (`codec = null`), with `chars <= 8192` on both; the cap is proved with the payload each path actually binds on, because a compressible source cannot prove it — measured in this bun with `node:zlib` `deflateRawSync`, 40,960 characters of `not n(in=a)\n` is **54,614** base64url characters plain (`#src0=` → `{ ok:false, reason:'too-large', cap:8192 }`, `chars > 8192`) but only **151** deflated (`#src=` → `ok:true`), so `#src=`'s refusal is asserted instead on an incompressible payload: 12,000 characters drawn from a seeded LCG over the 90 printable ASCII symbols, measured **11,280** base64url characters deflated and 16,000 plain, over the cap on both paths; `fromBase64Url('!!')` is `null`; a truncated deflate payload decodes to `{ ok:false, reason:'bad-deflate' }`; `readHash('#src=A&src0=B')` yields `src.key === 'src'`, `readHash('#pick=tour:5')` yields `pick === 'tour:5'`, and `readHash('#src=A&pick=tour:5')` yields **both** fields so a failed decode can still fall through to the pick. |
| 2 | The scratch model | `site/src/utils/playground-store.ts` gains `ProjectKind`/`CatalogueItem`, `buildCatalogue`, `idKind`, `newScratchId`, `uniqueName`, `createScratch`/`duplicateScratch`/`renameScratch`/`deleteScratch`/`touchScratch`, `resolveSource`, `resolveInitial` and `NEW_PROJECT_SOURCE`, and widens Phase 3's `evictOldest`/`writeEnvelope` with a `keep` id and a `skipped` report. Phase 3's `PickId`, `ScratchProject`, `PlaygroundEnvelope`, `MAX_SCRATCH`, `MAX_SOURCE_BYTES` and `MAX_ENVELOPE_BYTES` are imported and reused, never redeclared or renamed. Any top-level `localStorage`/`window` access left by Phase 3 moves inside a function. No UI. | `site/test/workspace.test.ts` under `bun test`: a 17th `createScratch` leaves 16 projects with the oldest `updatedAt` gone and the `keep` id present; `evictOldest(env, keep)` never drops `keep` even when it is the oldest, taking the second-oldest instead; `touchScratch` with a 33 KB body returns `list` unchanged and the project in `skipped`, while a 31 KB one is stored; `writeEnvelope(env, fake, keep)` trims by LRU until `new TextEncoder().encode(JSON.stringify(env)).length <= MAX_ENVELOPE_BYTES` with `keep` still present; `uniqueName('Half-adder', ['Half-adder'])` is `'Half-adder 2'`; `idKind` classifies all three shapes and returns `null` for `'nope'`; `buildCatalogue(examples, tour)` yields 17 items whose ids are exactly `example:<slug>` × 10 and `tour:<n>` × 7; `resolveSource` returns `examples[4].source` verbatim for `'example:half-adder'`. Additionally the module imports cleanly in bun with no `localStorage` in scope (the test importing it *is* that proof); `describeNote({ kind: 'skipped', names: ['x'] })` returns a non-empty string, and `createStore`'s fired write passes `env.activeId` as `keep`. |
| 3 | The workspace sidebar | `Playground.astro`: the `<label for="pg-pick">` / `<select id="pg-pick">` pair (`:28-37`) is replaced by a `<nav class="pg-ws" aria-label="Workspace">` with server-rendered Examples and Tour lists from `buildCatalogue(examples, tour)` — each group headed by an `<h2 class="pg-ws-group">` its list names through `aria-labelledby` — a client-rendered Scratch list, `aria-current="true"` on the active row, a desktop collapse toggle (`aria-expanded`/`aria-controls`, not persisted) and a mobile disclosure. The island's `#pg-pick` handle (`:92`) and its `change` listener (`:143-145`) are deleted in the same slice, or `querySelector('#pg-pick')!` returns `null` and throws before the editor mounts. The `<nav>` is a **sibling of `.pg-panes`** in the `.pg` workbench grid, never a track inside it: Phase 3's `--pg-split-main`, its `ratioFromPointer(startPx, sizePx, clientPx)` arithmetic over the `.pg-panes` rect, its `ResizeObserver` re-clamp and its `aria-controls` all assume exactly `#pg-pane-editor` and `#pg-pane-output` (`PHASE_3_workbench.md:61,231,349,376`) and none of them moves; the collapse toggle flips the `.pg` grid's first column between its width and `0`. `#pg-picks` (`:66`) keeps its id and its `type="application/json"`, but its body becomes the serialized `CatalogueItem[]` from the same `buildCatalogue(examples, tour)` call that renders the rows — `set:html={JSON.stringify(buildCatalogue(examples, tour))}` — so the island parses one array (`JSON.parse(el.querySelector('#pg-picks')!.textContent || '[]') as CatalogueItem[]`, replacing the `Record<string, string>` cast at `:101`) and hands it straight to `resolveSource` / `resolveInitial`; the blob is page data, not a module, so it never enters the eager module graph `bun run bundle` measures and `site/src/content/{examples,tour}.ts` stay out of the island script entirely. `data-default-pick` on the `.pg` root. Selection rebuilds the tab set with `fromSource(resolveSource(id, catalogue, env.scratch))`, installs it with `setDocuments(texts, active)`, restores the stored `activeFile` **by name** through `showDocument(i)` — falling back to `rootIndex(state.tabs)` when the name is absent (`PHASE_2_file_tabs.md:148,150,232-233,333`) — and writes `activeId` and `activeFile` (`activeFile(state.tabs).name`) through `store.update`. The island's bootstrap calls the synchronous `resolveInitial({ intent: {}, decoded: null, env, catalogue, defaultId })` and loads its `outcome`, so a stored `activeId` reopens on reload and `data-default-pick` opens on a first visit; slice 5 adds only the `src` / `pick` intents to that same call site. Clicking an output tab writes `tab` through `store.update`, and the bootstrap restores it. The `.pg-ws*` CSS in `global.css`: static appearance beside the other `.pg*` rules, geometry inside Phase 3's `[data-layout="app"]` block. Read-only workspace — no create/rename/delete yet. | `bun test` stays green (17 catalogue ids assertion from slice 2 now also covers what the markup renders, since both call `buildCatalogue`); `bun --bun run build` green; `bun run bundle` shows `/playground` within its committed ceiling and `/examples`, `/tour`, `/reference/*` unchanged. Browser walk-through — clicking "Full-adder" (the shipped title, `site/src/content/examples.ts:155`) loads it, reloading returns to it — recorded in STATUS as **unrun**. |
| 4 | Scratch lifecycle | New / rename (inline `<input>`, Enter commits, Escape cancels, blur commits) / delete (two-step inline confirm) / duplicate on scratch rows, duplicate on content rows (forks to scratch); copy-on-write — the first `onChange` while `activeId` names a content project calls `createScratch` with the content label as the base name via `uniqueName`, switches `activeId` and posts a status note; `touchScratch` on every later change, committed through Phase 3's debounced `store.update` — no new listener, since `store.flush()` is already bound to `pagehide` and `visibilitychange` (`PHASE_3_workbench.md:168,377`). | `bun test`: `workspace.test.ts` gains the fork case — starting from `{ scratch: [], activeId: 'example:half-adder' }`, one edit produces a scratch whose `source` is the edited text and whose `name` is `'Half-adder'` — the shipped title at `site/src/content/examples.ts:100`, carried through `buildCatalogue`'s `label` — `activeId` moves to it, and a `store.flush()` → `readEnvelope(fake)` cycle returns the edited text from `resolveSource`; a second fork of the same example names it `'Half-adder 2'`. `bun --bun run build` and `bun run bundle` green. The browser proof (edit an example, reload, find the edit) recorded as **unrun**. |
| 5 | Load precedence and the fragment scrub | The `is:inline` capture script at the top of `Playground.astro`'s markup: it stashes a `#src=`/`#src0=`/`#pick=` fragment on `window.__circShareHash` and calls `history.replaceState(history.state, '', location.pathname + location.search)` inside `try/catch`, running at parse time and therefore before every deferred module — PostHog's `ph.init` (`PostHog.astro:21-61`, a hoisted module; the inline snippet at `:20` is stub-only per the comment at `:13-15`) included. The async bootstrap reads `window.__circShareHash ?? location.hash`, passes it through `readHash` (which keeps **every** key it found, so precedence stays in `resolveInitial`), awaits `decodeShare(…, webStreamsCodec())` when `intent.src` is present, calls `resolveInitial` at the same call site slice 3 established, creates a `generateSillyName()`-named scratch project for a `src` hit (decision 6), and posts `note` to the status bar on any fall-through. `DOCS/PLANS_PROMPT.md:191`'s Open item is **narrowed**, not deleted: the configuration half (PostHog's property-sanitising hook) is struck, since the structural argument in Open Questions removes the need for it, and the entry is rewritten to name only the residual browser confirmation, to be deleted by whichever session first has a browser (`PLANS_PROMPT.md:186`). | `bun test`: `resolveInitial` returns `share` for a decoded `src` intent even when `env.activeId` is set; `pick` for a known id; `active` for a stored `activeId`; and it falls through one rule at a time, per decision 6 (`PLANS_PROMPT.md:47`) — a `{ ok:false }` decode whose fragment also carried `#pick=tour:5` returns `{ kind:'pick', id:'tour:5' }`; a `{ ok:false }` decode with a stored `activeId` and no pick returns `active` with the "opened the last project instead" note; an unknown `#pick=` id with a stored `activeId` returns `active` with a note; and only an envelope whose `activeId` is null reaches `default` — with a note when an intent was present, `null` when it was not. Plus the standing assertion that a browse-only envelope's JSON contains none of the 17 shipped sources. `bun --bun run build` green. The PostHog confirmation (`bun run dev` with a throwaway `PUBLIC_POSTHOG_KEY`, open a `#src=` link, read `$current_url` in the `/e/` request) is a manual checklist item recorded as **unrun** — see Open Questions. |
| 6 | The Share button | A `<button class="pg-share">` mounted into the `.pg-status-actions` slot Phase 3 reserves for it (`PHASE_3_workbench.md:22,378`): serialises the current tab state through `toSource(state.tabs)` (`PHASE_2_file_tabs.md:149,332`), calls `encodeShare(source, webStreamsCodec())`, and on `ok` writes `shareUrl(location.href, fragment)` to the clipboard with a status note naming the character count; on `{ reason:'too-large' }` it switches to "Copy the source" and copies the raw text with a note naming `chars` and `cap`; a rejected or absent `navigator.clipboard` falls back to a focused read-only `<input>` holding the URL. | `bun test`: the pure half is already covered by slice 1's cap and `shareUrl` cases; add a case asserting `shareUrl('https://x.dev/circ/playground?a=1#old', '#src=AAA')` keeps the path and query and replaces the fragment. `bun --bun run build` and `bun run bundle` green. The copy-and-open-in-a-private-window walk-through recorded as **unrun**. |
| 7 | Open in playground | `site/src/components/OpenInPlayground.astro`: `<a href={`${url('/playground')}#pick=${id}`}>`, no `<script>`, with frontmatter that throws when `id` is not in `buildCatalogue(examples, tour)`. Mounted per card in `examples.astro:26-39` and per step in `tour.astro:20-27`. `.oip` styling in the examples/tour CSS sections (`global.css:717-773`). | `bun test`: for every catalogue item, `readHash('#pick=' + item.id)` yields `{ kind:'pick', id }` and `resolveSource(id, catalogue, [])` returns that item's source byte-identically. `bun --bun run build` is itself the gate on the ids, since a bad id throws in frontmatter. `bun run bundle` shows `/examples` and `/tour` still at or below the 10 KB gzip ceiling with **no** change to their eager module graphs. |
| 8 | Decisions and cleanup | `DOCS/decisions/playground.md` gains `###` entries for: the two-key share encoding and its 8192 cap; the load precedence and the parse-time scrub; the flat scratch model and its three limits; copy-on-write forking of content projects. Registered under "Topics" in `DOCS/decisions/index.md` if this phase created the file. STATUS entry closes the phase and lists its commits. | Docs only: `bun test` and `bun --bun run build` unchanged green. The reviewable assertion is that every `###` heading added is referenced by slug from nothing but prose, per the convention stated in `DOCS/decisions/index.md`'s "Conventions" section. |

Slices are ordered by dependency: 1 and 2 are pure modules with no consumer and are independent of each other; 3 is the first slice that changes a byte of rendered HTML and consumes 2's catalogue helpers; 4 adds mutation on top of 3's rows; 5 replaces 3's empty-intent bootstrap with the full precedence and needs 1's codec; 6 needs 1's encoder and Phase 3's `.pg-status-actions` slot; 7 needs 5's `#pick=` handling to be live before it links to it; 8 is documentation. Each is independently reviewable and independently committable with `bun test` and `bun --bun run build` green.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `toBase64Url round-trips arbitrary bytes` | share-link | Output matches `/^[A-Za-z0-9_-]*$/` with no `=`; `fromBase64Url(toBase64Url(b))` is byte-identical for 0, 1, 2, 3 and 40,000-byte inputs. |
| `fromBase64Url returns null, never throws, on a bad alphabet` | share-link | `'!!'`, `'a b'` and `'====' `each yield `null`. |
| `encodeShare picks #src= when a codec is present` | share-link | `key === 'src'`, `fragment.startsWith('#src=')`. |
| `encodeShare falls back to #src0= with a null codec` | share-link | `key === 'src0'`, `fragment.startsWith('#src0=')`, payload is plain base64url of the UTF-8 bytes. |
| `encodeShare refuses past the cap` | share-link | An incompressible payload — 12,000 characters from a seeded LCG over the 90 printable ASCII symbols, measured 11,280 base64url characters deflated and 16,000 plain — returns `{ ok:false, reason:'too-large', cap:8192 }` with `chars > 8192` on **both** codec paths. The complement pins why the payload has to be incompressible: 40,960 characters of `not n(in=a)\n` is `ok:true` at 151 characters through `#src=` and `too-large` at 54,614 through `#src0=`. (Both figures measured with `node:zlib` `deflateRawSync` in this bun.) |
| `decodeShare reports every malformed payload as a value` | share-link | `'#src=!!'` → `bad-base64`; `'#src=' + toBase64Url(randomBytes)` → `bad-deflate`; a deflated invalid UTF-8 sequence → `bad-utf8`; `'#src=…'` with `codec = null` → `no-codec`; `'#zz=1'` → `unknown-key`; `''` → `no-key`. |
| `readHash reports every key it found` | share-link | `#src=` wins over `#src0=` inside `intent.src`; `'#src=A&pick=tour:5'` yields **both** `src` and `pick`, so `resolveInitial` — not `readHash` — decides the precedence and a failed decode can still reach the pick; a leading `#` is optional; a fragment with none of the three keys yields `{}`, with any present-but-unrecognised key listed in `unknown`. |
| `shareUrl replaces the fragment and keeps path and query` | share-link | `'https://x.dev/circ/playground?a=1#old'` + `'#src=AAA'` → `'https://x.dev/circ/playground?a=1#src=AAA'`. |
| `idKind classifies the three id shapes` | playground-store | `example:` / `tour:` / `scratch:` map to their kinds; `'nope'` and `''` are `null`. |
| `uniqueName appends the first free suffix` | playground-store | `('Half-adder', ['Half-adder', 'Half-adder 2'])` → `'Half-adder 3'` — the shipped label the only real caller passes (`site/src/content/examples.ts:100`); an untaken base is returned unchanged. |
| `createScratch evicts the least-recently-updated past 16` | playground-store | 17 creates leave `MAX_SCRATCH` projects; the returned `evicted` names the lowest `updatedAt`. |
| `evictOldest never drops the kept project` | playground-store | Phase 3's `evictOldest(env, keep)`, widened here: with `keep` set to the oldest, the second-oldest is evicted instead — and the same holds on the quota-retry call, so the active project can never be the one lost. |
| `touchScratch refuses an over-size source` | playground-store | A 33 KB body leaves `list` unchanged and appears in `skipped` (measured `new TextEncoder().encode(source).length > MAX_SOURCE_BYTES`); a 31 KB one is stored. |
| `writeEnvelope trims until the envelope fits` | playground-store | After the write, `new TextEncoder().encode(JSON.stringify(env)).length <= MAX_ENVELOPE_BYTES`, `keep` is still present, and any source omitted for exceeding `MAX_SOURCE_BYTES` comes back in `skipped`. |
| `renameScratch / deleteScratch / duplicateScratch` | playground-store | Rename changes only `name`; delete removes exactly one id; duplicate yields a fresh id, a `uniqueName` name, an identical `source` and a newer `updatedAt`. |
| `touchScratch updates source and updatedAt only for the named id` | playground-store | Siblings are referentially unchanged. |
| `resolveInitial falls through one rule at a time` | playground-store | Three clean hits with `note === null` (a decoded `src` beats a stored `activeId`; a known `pick` beats `activeId`; `active` with no hash), and four fall-throughs with a non-null note: a failed decode whose fragment also carried `#pick=` lands on that `pick`; a failed decode and an unknown pick id each land on `active` when an `activeId` is stored, and on `default` when it is null; a present-but-unrecognised key lands the same way. `default` carries `note === null` only when no intent was present at all. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `every shipped source survives a share round-trip under the cap` | share-link × `content/{examples,tour}.ts` | All 17 sources, through both `#src=` (node:zlib codec) and `#src0=`: `decodeShare(encodeShare(s).fragment)` is `s` byte-identically and `chars <= SHARE_CAP`. This is decision 6's stated proof. |
| `every catalogue id opens through #pick=` | playground-store × content | For all 17 items, `readHash('#pick=' + id)` yields that id and `resolveSource` returns the item's source byte-identically — the assertion `OpenInPlayground.astro`'s links rest on. |
| `a browse-only session stores no content text` | playground-store × content | After opening every catalogue item without editing, `JSON.stringify(env)` contains none of the 17 sources and `env.scratch` is `[]`; only `activeId`/`activeFile` changed. |
| `an edited example forks and survives a write/read cycle` | playground-store | Fork from `example:half-adder`, `store.flush()`, `readEnvelope(fake)`: `activeId` names a `scratch:` id, `resolveSource` returns the edited text, the name is `'Half-adder'` (`site/src/content/examples.ts:100`), and a second fork is `'Half-adder 2'`. |
| `the quota path evicts once and then disables` | playground-store (Phase 3's case, extended) | With a stubbed `setItem` that throws `QuotaExceededError`, the first retry follows one LRU eviction and the second failure disables persistence and reports it — now exercised with real scratch projects rather than Phase 3's placeholder envelope. |
| `the marker source round-trips through the store` | playground-store × split-files | `joinFiles(splitFiles(tour[5].source))` stored and re-read equals `tour[5].source`, so a two-file project is not mangled by persistence (`split-files.test.ts:12-24` is the shape being preserved). |

Run command: `cd /Users/jeffersonmourak/circus/worktrees/v0.0.3/playground/site && bun test`

Focused: `cd .../site && bun test test/share-link.test.ts test/workspace.test.ts`. Standing gates after every slice, from the same directory: `bun --bun run build` (**never** plain `bun run build` on this machine — `PLANS_PROMPT.md:133`) and, from slice 2 on, `bun run bundle`. `SKIP_LIBCIRC_TEST=1` is never set to make a slice pass (`PLANS_PROMPT.md:135`); nothing in this phase touches the wasm-driven cases anyway.

## Open Questions / Spikes

- **`TODO(phase4)`: confirm in a browser that the scrub beats PostHog's `$pageview`.** The design resolves `PLANS_PROMPT.md:191` structurally rather than by configuration: `PostHog.astro:20`'s `is:inline` snippet is stub-only (its own comment at `:13-15` says so, and the snippet body only queues into `e._i`), the real `ph.init` lives in the hoisted module at `:21-61`, and a hoisted Astro `<script>` is a `type="module"` script — deferred, therefore executed after parsing — while slice 5's `is:inline` capture script is a classic script executed during parsing. So `location.href` has already lost the fragment by the time `ph.init` runs and `$current_url` cannot contain it. What is *not* verified is that claim in a real browser, because no browser has ever been available in a session on this branch (`PLANS_PROMPT.md:136`). **Spike, in slice 5:** `bun run dev` with a throwaway `PUBLIC_POSTHOG_KEY`, open `/playground#src=<payload>`, and read `$current_url` in the `/e/` request payload. If the fragment is present after all, add PostHog's property-sanitising hook to the `ph.init` call at `PostHog.astro:51-59`, **verifying the exact config key at runtime with `console.log(posthog.config)` rather than against a package** — posthog-js is not a dependency (`site/package.json:15-21`) and `PostHog.astro:16-17` loads the web snippet from `api_host + "/static/array.js"`. Record the answer in slice 5's STATUS entry. The entry at `PLANS_PROMPT.md:191` is **narrowed** in that slice, not deleted: its configuration half is struck on the structural argument above, and what remains names only the browser confirmation, which stays in the Open items — and whose STATUS line stays **unrun** — until a session that actually has a browser runs it and deletes the entry (`PLANS_PROMPT.md:186`). Closing an open item on an argument rather than on its stated measurement is what that rule forbids. The `history.replaceState` scrub ships regardless, since it also keeps the source out of the address bar and out of the browser's own history.
- **Resolved, not open — a project switch goes through Phase 2's document registry.** Phase 2 slice 3 already ships `setDocuments(texts, active)` / `showDocument(index)` / `textOf(index)` on `site/src/scripts/circ-editor.ts` and `fromSource` / `toSource` / `select` / `rootIndex` / `activeFile` on `site/src/scripts/file-tabs.ts` (`DOCS/PLANS/PHASE_2_file_tabs.md:148-153,232-238,333`). After Phase 2 a project is not one document but a `FileTabsState` with one `EditorState` per tab (`:201,217`), so loading a project is `state.tabs = fromSource(resolveSource(id, catalogue, env.scratch))`, then `setDocuments(state.tabs.files.map(f => f.body), i)`, where `i` is the index of `env.activeFile` in `state.tabs.files` — falling back to `rootIndex(state.tabs)` when the stored name is absent — and the reverse write is `env.activeFile = activeFile(state.tabs).name`. `view.setState(EditorState.create(…))` (`@codemirror/view` 6.43.11 `dist/index.d.ts:854`; `@codemirror/state` 6.7.4 `dist/index.d.ts:1193`, both read from the locked set at `/private/tmp/claude-501/-Users-jeffersonmourak-circus/9a9d359a-4d8b-4945-873f-09a96a28a456/scratchpad/cm-spike/node_modules`) is **not** called from this phase: on the single view it would orphan the per-file states, the tab strip and its per-file diagnostics, and it would drop Phase 1's theme `Compartment` and extension set (`PHASE_1_editor.md:269,272`). Phase 1's `setDoc` (`:244-245`) is not used either — it keeps history, and a project switch must not leave the previous project's text one `Ctrl-Z` away. Discarding undo across a project switch is a property of `setDocuments` replacing the registry, and is the intended semantics (`PLANS_PROMPT.md:73`). No new API is added to `circ-editor.ts`, which is why it is not in this phase's Modified files; if slice 3 finds the registry is not reachable from the island, it exports the existing call site rather than adding a document-replacement path, and adds the file to that table.
- **`TODO(phase4)`: whether Phase 3's `playground-store.ts` is importable from Astro frontmatter.** Slice 3 imports `buildCatalogue` from it in `Playground.astro`'s frontmatter, which bun evaluates at build time with no `window` and no `localStorage`. **Spike, at the start of slice 2:** grep the shipped module for top-level `localStorage`/`window`/`document` references; if any exist, move them inside `browserStorage()` / `readEnvelope` / `writeEnvelope` in slice 2 and note it in STATUS. This is cheap to check and cheap to fix, but it fails the build loudly if missed.
- **Accepted, not open — recorded so no slice re-opens them.** (a) Opening the same `#src=` link twice creates two scratch projects; the parse-time scrub means a *reload* does not re-import, only a fresh paste does, and the 16-project LRU absorbs the rest — no source-equality de-duplication is added, because decision 6 says the loaded source becomes *a new scratch project*. (b) A content project that is edited and then edited back to its pristine text stays forked; the fork trigger is the first change event, not a diff. (c) Two `/playground` tabs do not synchronise; the last debounced write wins and no `storage` event is observed. (d) The sidebar's collapse state is deliberately not persisted. It *could* be — `layout.ratios` is a `Record<string, number>` and Phase 3 reserves a `sidebar` key for exactly this (`PHASE_3_workbench.md:30`) — but a collapsed sidebar on a returning visit hides the workspace this phase exists to make visible, and the toggle is one click. If a later phase adds a draggable sidebar splitter, `ratios.sidebar` is where its value goes, with no schema change and no `version` bump.
