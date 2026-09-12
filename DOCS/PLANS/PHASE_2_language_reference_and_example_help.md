# Phase 2 — Language reference and example help

> **Dependencies:** Phases 0 and 1 implemented and accepted before this phase's implementation begins. Reuse their shared registry, result envelope, validation, page lifecycle, and bounded-read conventions.
> **Warnings:** Read the macroplan, both prior phase specifications, `DOCS/language.md`, `DOCS/circuit-format.md`, and `DOCS/decisions/{playground,playground-bench,libcirc}.md`. Knowledge is generated from canonical sources, not maintained as a second language manual. ChatGPT is the primary native consumer; the same tool works through Phase 0's external paths. This phase performs build-time compiler validation, not compilation inside a browser help call. Complete examples include memory initialization data, which the current gallery Markdown mirror omits.

## Goal

An agent can call `circ_help` to search circ syntax and usage, look up an exact diagnostic code, read a cited reference section, or retrieve a complete example project with its entry file, sibling files, and required memory images. The results identify the static corpus and compiler against which examples were checked, stay within the existing tool response budget, and remain useful before the active playground compiler or simulator has loaded. Search and retrieval run locally over lazily fetched static assets; they do not select a project, alter source or runtime state, or contact a backend/search service. Generated links resolve to the corresponding rendered reference/gallery content, and compiler-backed checks plus retrieval fixtures prove that agents receive usable source and relevant guidance.

## Scope

**In scope:**
- One `circ_help` tool with `search`, `read`, and `example` actions, using the existing native/external registry and envelope.
- Section records from the six public references: language, getting started, circuit format/diagnostics, WASM API, preview, and simulation protocol.
- Exact compiler diagnostic entries checked against `lib/validator/codes.zig`, with canonical explanations and related reference sections.
- Full gallery and retained tour examples, including named files, default entry, source citations, catalogue identity, and memory initialization.
- Stable semantic knowledge IDs, explicit aliases/tombstones for changed IDs, and a maintained identity inventory.
- A deterministic build-time corpus generator and compiler/example validation using the committed `libcirc.wasm`, with bounded behavioral smoke cases for representative circuits.
- Static manifest/search index/record shards, content hashes, owned-output cleanup, and build/dev integration that keeps deployment Bun-only.
- Publication of `DOCS/sim-protocol.md` through the existing site reference registry; matching LLM-mirror/index updates and full-bundle inclusion.
- Lazy browser loading, deterministic lexical ranking, exact-code boosts, corpus-bound pagination/chunking, cache/lifecycle handling, and explicit retrieval errors.
- Search-quality, content-integrity, compiler/runtime, generated-link, bundle, and actual agent acceptance checks.

**Explicitly deferred:**
- Hosted search, vector databases, embeddings/model calls, semantic rerankers, arbitrary URL retrieval, and runtime access to repository files.
- Indexing active user projects, private files, planning prompts, archived plans, source code outside the declared diagnostic registry, or the entire test-fixture tree.
- Authoring/loading an example into the user's workspace as a help side effect; project changes remain Phase 3 operations.
- Live behavioral verification tools or memory mutations, which ship in Phase 4; this phase's validation runs during generation/tests on isolated artifacts.
- Automatic source fixes, autocomplete/editor search UI, a chat interface, or changes to circ syntax/compiler diagnostics.
- A general-purpose Markdown engine or syntax highlighter in the browser knowledge chunk.

## File & Module Topology

Paths are relative to the worktree root. The generator and build-time Markdown/compiler dependencies must stay outside the browser import graph.

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| Knowledge contract | `site/src/scripts/knowledge-contract.ts` | Manifest, record, search, example, compatibility, and response DTOs; no Node/Markdown/compiler imports. |
| Search | `site/src/scripts/knowledge-search.ts` | Pure token normalization, ranked lookup, filtering, exact-code selection, and deterministic pagination. |
| Browser service | `site/src/scripts/knowledge-client.ts` | Lazy manifest/index/shard loading, digest/schema checks, cache ownership, bounded reads, and disposal. |
| Tool | `site/src/scripts/agent-tools/help.ts` | The eager lightweight descriptor and action validator; dynamically imports the knowledge service on invocation. |
| Corpus metadata | `site/src/content/agent-reference.ts` | Allowed document keys, semantic ID overrides/aliases/tombstones, topic synonyms and example-topic associations; contains no copied reference prose or example source. |
| Generator entry | `site/scripts/build-agent-reference.ts` | Orchestrates canonical input loading, validation, deterministic asset generation, and owned-output publication. |
| Extraction/build helpers | `site/scripts/lib/agent-reference-build.ts` | Markdown section extraction, citation mapping, record assembly, ID validation, search-index construction, hashing, and ownership-manifest checks. |
| Verification helper | `site/scripts/lib/agent-reference-verify.ts` | Serial compile validation and bounded isolated runtime scenarios against the shipped compiler; emits evidence metadata. |
| Shared mirror helpers | `site/scripts/lib/reference-content.ts` | Shared title stripping, link rewriting, and reference URL construction for sync/mirror/knowledge generation. |
| Generated pointer | `site/public/agent-reference/manifest.json` | Build-time pointer to the current immutable corpus manifest and the generator's owned asset list. |
| Generated assets | `site/public/agent-reference/assets/<sha256>.json` | Immutable manifest, index, and record shards named by content hash. |
| Identity fixture | `site/test/fixtures/agent-reference/ids.json` | Reviewed public ID inventory and alias/removal decisions; catches accidental renumbering or disappearance. |
| Retrieval fixtures | `site/test/fixtures/agent-reference/queries.json` | Queries, filters, expected record IDs/rank bounds, and negative cases. |
| Builder tests | `site/test/agent-reference-build.test.ts` | Extraction, canonical-source parity, ID stability, deterministic generation, link mapping, and owned cleanup. |
| Search tests | `site/test/knowledge-search.test.ts` | Exact diagnostic ranking, topic queries, code token handling, paging, and no-match behavior. |
| Client/tool tests | `site/test/knowledge-client.test.ts` | Lazy/deduplicated fetches, digest/corpus errors, bounded reads, lifecycle cancellation, and example delivery. |
| Verification tests | `site/test/agent-reference-verify.test.ts` | Returned projects compile and representative behaviors/preloads pass against the exact committed compiler. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| Build scripts/dependencies | `site/package.json`, `site/bun.lock` | Add `agent-reference` generation and place it after reference/mirror generation in build/dev; explicitly pin the build-only Markdown processor already used by Astro. |
| Generated files | `site/.gitignore` | Ignore the generated `public/agent-reference/` tree while keeping input metadata/tests tracked. |
| Document registry | `site/scripts/lib/site-config.ts` | Give indexed docs stable keys, add simulation protocol, and share base-aware public URL helpers. |
| Reference sync | `site/scripts/sync-reference.ts` | Use the shared canonical-body/link helper; record ownership of its generated reference files. |
| LLM mirror | `site/scripts/build-llm-mirror.ts` | Use shared helpers, include memory initialization in gallery Markdown, derive full reference-bundle membership from the doc registry, and clean only owned obsolete twins. |
| Tour content | `site/src/content/tour.ts` | Add an explicit stable slug to each existing step for knowledge identity; retain the existing positional playground IDs and source/prose ownership. |
| Playground page/island | `site/src/pages/playground.astro`, `site/src/components/Playground.astro` | Embed only the generated manifest locator/corpus identity and register the help descriptor with a lightweight compiler-identity reader. |
| Existing tests | `site/test/{agent-tools,webmcp-adapter,island-smoke,bundle-graph,content-artifacts,site-labels}.test.ts` | Add help discovery/parity, no-side-effect reads, lazy boundaries, memory metadata parity, and public citation checks. |
| Usage/decisions | `DOCS/agent-playground.md`, `DOCS/decisions/agent-playground.md` | Document `circ_help`, ID/version/chunk semantics, validation coverage, and actual agent lookup/retrieval evidence. |

Canonical reference prose or example descriptions may receive narrowly scoped corrections when a required verification case demonstrates an error. Make those corrections at the source and regenerate; do not patch the generated corpus to hide the discrepancy. `DOCS/STATUS.md` is appended after implementation slices under the macroplan.

**New dependencies:** One explicit build-only devDependency: `@astrojs/markdown-remark` pinned to `6.3.11`, the version installed at this planning baseline and used by Astro's Markdown pipeline. Its public `createMarkdownProcessor`, `RemarkPlugin`, and heading metadata APIs supply parsing/positions/real rendered anchors. Resolve and verify the actual accepted Astro tree before pinning if an earlier phase updated it. Do not rely on an undeclared transitive import or add Markdown/search packages to browser code. Bun/Node built-ins provide hashing, filesystem work, and bounded verification subprocesses; the existing `libcirc-abi.ts` and pinned renderer provide compile/runtime validation.

### Existing integration anchors

- `site-config.ts:15–46`: currently five published reference documents; add `sim-protocol.md` here so HTML and Markdown citations both exist.
- `sync-reference.ts:16–45` and `build-llm-mirror.ts:59–69`: canonical H1 stripping and link rewriting must stay consistent with extracted citation anchors/source lines.
- `build-llm-mirror.ts:72–94`: gallery Markdown currently emits source/preview but no `Example.memory` data.
- `build-llm-mirror.ts:320–359`: the full bundle currently names reference paths manually; derive the reference portion from the shared registry so simulation protocol is not missed.
- `examples.ts:21–40`: full example metadata; source, level, repo path, and memory images belong here. The lightweight playground catalogue is not the complete knowledge source.
- `tour.ts:6–11`, `113–138`: steps have no stable slug today, and the full-adder step contains the two named files a useful retrieval must retain.
- `gallery.astro:51–56`: actual HTML example anchors are `ex.slug`, not slugs computed from their display titles.
- `DocsLayout.astro:16–17`, `41–43`: Astro's heading metadata owns the rendered heading IDs; do not guess them from a separate slugger.
- `lib/validator/codes.zig:1–52` and `DOCS/circuit-format.md:149–175`: authoritative compiler code set/default messages and the documented diagnostic table.
- `libcirc-abi.ts:31–80`, `site/test/libcirc.test.ts:17–44`: use the existing ABI helpers and binary-reported compiler identity rather than invoking a local Zig compiler during site generation.
- `site/.gitignore:6–17`: reference HTML-source files and Markdown twins are generated, while WASM is committed.

Line numbers refer to the planning baseline; locate the symbols again before implementation.

## Data & State

### Canonical inputs, records, and stable IDs

The allowlist is the shared document registry with keys `language`, `getting-started`, `circuit-format`, `wasm-api`, `preview`, and `sim-protocol`, plus the gallery and retained tour arrays. Both the generator and tests read these exact sources. Plans, archives, compiler implementation files, and arbitrary URLs do not enter the corpus; the diagnostic registry is read solely to validate/extract its published code vocabulary and default messages.

```ts
export type SearchKind = 'reference' | 'diagnostic' | 'example';
export type RecordKind = SearchKind | 'example_file' | 'memory_image';

export interface Citation {
  sourcePath: string;
  sourceHash: string;
  startLine: number | null;
  endLine: number | null;
  htmlPath: string | null;
  markdownPath: string | null;
  heading: string | null;
}

export interface ResolvedCitation extends Citation {
  htmlUrl: string | null;
  markdownUrl: string | null;
}

export interface RecordHeader {
  id: string;
  kind: RecordKind;
  title: string;
  parentId: string | null;
  relatedIds: string[];
  citation: Citation;
}

export type PublicRecordHeader = Omit<RecordHeader, 'citation'> & {
  citation: ResolvedCitation;
};

export interface TextRecord extends RecordHeader {
  kind: 'reference' | 'diagnostic' | 'example_file' | 'memory_image';
  format: 'markdown' | 'circ' | 'hex';
  text: string;
  textSha256: string;
}
```

ID policy:

- Reference: `ref:<document-key>:<semantic-section-id>`, such as `ref:language:input-pins`, `ref:language:imports`, and `ref:language:parametric-sub-circuits`.
- Diagnostic: `diagnostic:E014`, preserving the compiler's exact uppercase code. Accept a case-insensitive exact diagnostic query and return the canonical ID. Unknown codes do not acquire invented definitions.
- Gallery example: `example:<existing-slug>`, aligned with the current `example:<slug>` playground catalogue ID.
- Tour example: `tour-example:<explicit-step-slug>`. Add stable slugs to `TourStep`; retain the current `tour:<n>` as separately generated `playgroundId`, not as the durable knowledge ID. Reordering steps changes that association, not the knowledge identity.
- Example file: `<example-id>/file/<encoded-file-name>`; memory image: `<example-id>/memory/<encoded-source-file>/<encoded-memory-name>`. Encode each segment with one defined URI-component encoder; decode only through manifest lookup, never into filesystem/fetch paths supplied by a caller.
- Section IDs are assigned from semantic headings with leading section numbers removed, with explicit overrides in `agent-reference.ts` for ambiguities or title changes. Position, line numbers, array index, and generated HTML anchors are not the permanent identity. Duplicate semantic IDs require an override rather than an order-dependent numeric suffix.
- The reviewed ID inventory freezes the baseline and records aliases/removals. Content edits and section renumbering retain IDs. A renamed section retains its explicit ID or adds an alias; deliberate removal adds a tombstone with an optional replacement. Aliases must be acyclic and resolve to one canonical record; none may silently point to a different example after a tour reorder.

Parse canonical Markdown through the build-only Astro processor with syntax highlighting disabled. A remark plugin collects heading depths and original source positions outside code fences; returned renderer heading metadata supplies the actual HTML slugs from the same transformed body used by the reference page. Share title stripping/link transformations with the sync/mirror scripts and retain the line mapping to canonical `DOCS/` text. Assert one-to-one heading correspondence; fail on a mismatch instead of emitting a guessed anchor. GFM tables, inline code in headings, repeated headings, fenced heading-looking text, and nested sections have extraction fixtures.

A section record contains its heading and complete subtree up to the next heading of equal or shallower depth. Keep parent/child links so an agent can retrieve a narrower subsection when a parent is long. Search indexes the section's direct prose/code separately from inherited child text, avoiding counting the same paragraph repeatedly in every ancestor. Introductory text before the first H2 is a named overview record. Code fences and deliberate invalid examples are returned verbatim as documented; extraction does not turn every fenced block into a runnable example.

Diagnostic records combine the code's canonical default message, the corresponding documented table row, and links to relevant reference sections that mention or explain it. Additional handwritten repair prose belongs in the canonical reference first. Distinguish compiler `E001`–`E018`/`W001`–`W003`, the compiler's `syntax` category, simulation protocol `E_*` names, and agent-tool errors. The exact compiler-code collection test is exhaustive; simulation errors remain searchable protocol reference content unless explicitly given a separate namespace later.

### Complete example projects

```ts
export interface ExampleFile {
  name: string;
  body: string;
}

export interface ExampleMemory {
  file: string;
  name: string;
  kind: 'rom' | 'ram';
  width: number;
  addrWidth: number;
  encoding: 'hex-bytes-little-endian';
  hex: string;
  initialization: 'load-before-driving-inputs';
}

export interface ExampleRecord extends RecordHeader {
  kind: 'example';
  playgroundId: string;
  level: 'intro' | 'medium' | 'advanced' | null;
  description: string;
  entryFile: string;
  files: ExampleFile[];
  memory: ExampleMemory[];
  projectSha256: string;
  validation: {
    compile: 'passed';
    warnings: { code: string; file: string; line: number; message: string }[];
    memoryShapes: 'passed';
    behavior: 'passed' | 'not_checked';
    scenarioIds: string[];
  };
}
```

- Derive named files through `splitFiles`; validate `joinConflicts` and the existing round-trip rules. The last named file is `entryFile`. Compile that full file overlay. Do not reconstruct a multi-file project from a single highlighted code block or omit a sibling merely because it is not the entry.
- Source and prose come from the complete content record. Examples use `lede`/`level`, tour steps use `prose` and level null. The source citation names the owning content module, and may additionally link `repoPath` when present and source-matched. Do not invent line ranges for TypeScript template fields; null is acceptable when no verified field-level range is available.
- Existing `Example.memory` keys refer to root declarations: resolve them against the compiled/analyzed entry file and record `file`, declared kind, and shape. The RAM example's preload is an initial runtime RAM image, not a source-owned ROM setting. A help retrieval reports this distinction without applying either kind to the playground.
- Validate hex as the runtime image format using the shared image helpers: whole words, capacity, and per-word width. A partial image has the runtime's documented replace-all/zero-fill semantics. Normalize to canonical lowercase, even-length hex bytes after validation, retaining the original content source as the citation.
- A memory declaration without supplied initialization remains a valid example with an empty memory list; its description must not promise initial data that was not returned. Root-memory image validation does not imply nested per-instance images exist in today's content schema.
- `projectSha256` covers the ordered named sources, entry, and normalized initialization descriptors, not precompiled artifact filenames or prettified preview whitespace. Retrieval returns the exact source that was validated. Existing `wasm` and `preview` fields are not proof of that source's current compatibility.
- `compile: passed` and `memoryShapes: passed` are emitted only after generation runs those checks. Behavior is passed only for the listed explicit scenarios; compile success alone does not validate a prose claim or truth table. Every positively indexed gallery/tour example must compile. A failing example makes generation fail with its ID and actual diagnostics; repair the canonical source/prose or make an explicitly reviewed content decision, never silently omit it or label it passed.

### Corpus assets and identity

Use a small build-time pointer plus immutable content-addressed assets. The browser page embeds the immutable manifest URL and expected corpus ID, not a complete corpus or source bundle.

```ts
export interface AssetRef {
  path: string;
  sha256: string;
  bytes: number;
}

export interface CompilerIdentity {
  version: string;
  revision: string;
  grammarSha256: string;
  parserRuntimeSha256: string;
  topologyVersion: number;
  fullVersion: number;
  wasmSha256: string;
}

export interface KnowledgeManifest {
  schemaVersion: 1;
  corpusId: string;
  sourceSetSha256: string;
  repositoryRevision: string | null;
  compiler: CompilerIdentity;
  searchVersion: 1;
  index: AssetRef;
  shards: Record<string, AssetRef>;
  counts: { reference: number; diagnostic: number; example: number };
}

export interface IndexedRecord extends RecordHeader {
  kind: SearchKind;
  shardKey: string;
  headingPath: string[];
  tags: string[];
  excerpt: string;
  directContentLength: number;
  terms: {
    title: Record<string, number>;
    headings: Record<string, number>;
    tags: Record<string, number>;
    prose: Record<string, number>;
    code: Record<string, number>;
  };
}

export interface KnowledgeIndex {
  schemaVersion: 1;
  corpusId: string;
  records: IndexedRecord[];
  aliases: Record<string, string>;
  removed: Record<string, { replacementId: string | null }>;
  resources: Record<string, { shardKey: string; kind: 'example_file' | 'memory_image' }>;
}
```

Shard the full reference records by document and examples/resources by example. The index includes only bounded excerpts, searchable term counts, metadata, and record locations; it does not duplicate full source bodies or hex images. Resource records are directly readable but excluded from normal search results so every file in a project does not compete with its parent example.

`directContentLength` is the UTF-16 length of that record's own prose/code used for ranking, excluding inherited subsection text, previews, and hex images. Public search/read metadata must itself fit the response budget. Return fewer search hits when needed to fit the serialized envelope and advance the cursor by the number actually delivered; generation must reject an individual searchable record header or example manifest that cannot be represented without losing fields.

`corpusId` is SHA-256 over a deterministic canonical representation of source contents, generated record inputs, compiler identity, ID/alias metadata, and search/extraction schema versions. Do not hash a manifest recursively through its own ID. Compute the corpus ID first, then serialize the index/shards with that ID, hash each asset, and finally serialize/hash the immutable manifest. `manifest.json` points at that final immutable manifest and lists owned outputs; it is a build input to Astro, not the browser's mutable source of truth during a retrieval.

Hash the actual committed WASM bytes and read `circ_version()` during generation. Check that identity against `libcirc.manifest.json` and the canonical grammar hash; a mismatch fails generation before publication. `repositoryRevision` is informational checkout HEAD and may differ from the compiler build commit. `sourceSetSha256` covers actual file contents, including uncommitted content edits, so the corpus never claims that HEAD alone identifies those bytes. No timestamps enter deterministic assets.

Each shard carries `schemaVersion` and `corpusId`; the manifest owns its lookup path and digest. Client code resolves only these declared asset paths under the generated asset directory. All paths must be same-origin site-relative assets; arbitrary schemes, traversal, protocol-relative paths, and external URLs are rejected. Content IDs supplied by callers are lookup keys, never fetch paths.

### Tool input and response contract

Register one descriptor, `circ_help`, marked read-only. Its description says it searches/reads the shipped circ reference, diagnostics, and complete examples; lookup does not change the active project. Use the inherited object schema with an `action` enum and field descriptions, then enforce the discriminated shapes in the handler. Unknown keys, keys belonging to another action, and invalid ranges produce `INVALID_ARGUMENT` or the inherited `INVALID_RANGE` as appropriate.

```ts
export type HelpInput =
  | {
      action: 'search';
      query: string;
      kind?: SearchKind;
      limit?: number;
      cursor?: string;
      expectedCorpusId?: string;
    }
  | {
      action: 'read';
      id: string;
      offset?: number;
      maxCodeUnits?: number;
      expectedCorpusId?: string;
    }
  | {
      action: 'example';
      id: string;
      expectedCorpusId?: string;
    };

export interface HelpContext {
  corpusId: string;
  compiler: CompilerIdentity;
  activeCompilerComparison: 'match' | 'mismatch' | 'not_initialized';
}

export interface SearchPage {
  context: HelpContext;
  query: string;
  matches: {
    id: string;
    kind: SearchKind;
    title: string;
    excerpt: string;
    citation: ResolvedCitation;
    relatedIds: string[];
  }[];
  totalMatches: number;
  nextCursor: string | null;
}

export interface HelpTextChunk {
  context: HelpContext;
  record: PublicRecordHeader;
  format: 'markdown' | 'circ' | 'hex';
  textSha256: string;
  offset: number;
  endOffset: number;
  totalCodeUnits: number;
  text: string;
  completeRecordInResponse: boolean;
  nextOffset: number | null;
}
```

Search accepts a trimmed nonempty query of at most 512 UTF-16 code units and at most 32 normalized terms. Limit defaults to 5, range 1–10. Excerpts are at most 480 code units, shortened at a safe character/word boundary and explicitly marked as excerpts. Empty query is invalid; a valid no-match query returns an empty array and nextCursor null without inventing an answer. Filter kind applies before ranking. Cursor binds corpus, normalized query, filter, and offset; repeated paging is deterministic and a cursor cannot be reused with another query/filter.

Read follows Phase 1's zero-based UTF-16/exclusive-end convention: default offset 0, budget 4,096 code units, range 2–4,096, with safe surrogate boundaries. A nonzero offset requires `expectedCorpusId`. The context identifies immutable content, and `textSha256` verifies reassembly. A Markdown fragment is labeled incomplete when paged; do not add/remove fences or pretend the fragment is a self-contained runnable example. A hex record uses even offsets/end boundaries so each chunk contains complete bytes; require an even start and adjust the end downward when needed.

Treat the requested text budget as an upper bound and shorten a chunk further if its fully serialized response would exceed 32 KiB. Every non-EOF chunk must advance at least one complete Unicode character or hex byte; if the required metadata leaves no room for that, return `RESULT_TOO_LARGE`. An empty record or a read at EOF returns empty text and nextOffset null. Reject offsets beyond EOF or inside surrogate pairs with `INVALID_RANGE`.

`read` accepts reference, diagnostic, and resource IDs. Passing an example parent ID returns an actionable invalid-argument result directing the caller to `action: example`; it does not serialize an undocumented alternate text representation. `example` accepts a gallery/tour example ID or alias, not a reference ID. Both resolve IDs through the same canonical lookup and return the canonical ID; aliases do not create duplicate search hits.

### Example delivery within the response budget

Most existing examples fit as one response. Preserve complete source and memory values instead of trimming them to make a large example fit.

```ts
export interface ExampleResourceRef {
  recordId: string;
  textSha256: string;
  totalCodeUnits: number;
}

export type ExampleDelivery = {
  context: HelpContext;
  id: string;
  title: string;
  description: string;
  level: 'intro' | 'medium' | 'advanced' | null;
  playgroundId: string;
  entryFile: string;
  projectSha256: string;
  citation: ResolvedCitation;
  relatedIds: string[];
  validation: ExampleRecord['validation'];
} & (
  | {
      delivery: 'inline';
      completeProjectInResponse: true;
      files: ExampleFile[];
      memory: ExampleMemory[];
    }
  | {
      delivery: 'manifest';
      completeProjectInResponse: false;
      files: { name: string; content: ExampleResourceRef }[];
      memory: (Omit<ExampleMemory, 'hex'> & { content: ExampleResourceRef })[];
    }
);
```

Measure the final application `ToolResult` envelope against Phase 0's 32 KiB UTF-8 limit, including context, quotes/escapes, and metadata. Return inline only when the complete result fits; otherwise return the manifest with resource IDs for `read` retrieval. All resources belong to the same corpus and project hash. The manifest is complete metadata but explicitly incomplete source delivery; the agent must retrieve and assemble every referenced file/image before treating it as a complete project. If even the manifest cannot fit, return `RESULT_TOO_LARGE` rather than omitting a file.

The generator verifies the manifest form fits for every example and materializes resource records even for currently inline examples, enabling stable direct reads. An oversize synthetic example fixture proves fallback and lossless assembly. A `playgroundId` or open-in-playground link identifies the catalogue selection only; it is not a claim that the link itself transports or applies the returned initialization images.

### Local lexical ranking

Ranking is deterministic and testable without network or an LLM:

1. Normalize Unicode text consistently, lowercase query tokens, and retain circ identifiers and exact diagnostic tokens. Index both a compound identifier and its underscore-separated parts. Preserve width/parameter forms as explicit syntax tags where useful; do not reduce `E014` to a generic number.
2. Apply a small reviewed synonym map from `agent-reference.ts`, such as bus/multi-bit/width and parameter/parametric. Expansion adds related terms but does not erase the original term or change exact diagnostic matching. Stop words are fixed and tested; syntax/diagnostic tokens are never stop words.
3. Place exact requested diagnostic IDs and exact record-ID matches in the highest rank tier within the chosen kind filter. For remaining candidates require at least one meaningful matched term. Let coverage be the number of distinct original query terms matched anywhere; lexical score is `12 * coverage + sum(termWeight * fieldWeight * min(termFrequency, 3))`, summed over distinct normalized query/expanded terms and fields. Field weights are title 8, tags 6, heading path 4, prose 2, code 2. Original terms have weight 1 and synonym-only terms 0.5; a term present in both is counted once as original. Capping occurrence counts keeps long ripple-adder source from dominating every gate query.
4. Tie-break by original-term coverage, shorter direct-content length, then canonical ID in lexical order. Ranking does not depend on generation order, object insertion order, timestamps, locale-dependent collation, or user project state.
5. Return canonical excerpts and citations, not synthesized language advice. Large previews and hex image strings are excluded from ranking text; source code identifiers and explanatory prose remain searchable.

Use NFKC normalization and Unicode-aware letter/number/underscore word tokens. The prose/query stop-word set is `a, an, the, how, do, does, i, is, are, of, to, for, with, please, what`; code tokens are retained, and circ keywords/port names such as `and`, `or`, `not`, and `in` are never removed as stop words. A query consisting only of stop words returns no matches. Record these rules with searchVersion 1. The acceptance fixture constrains relevant results/rank bounds rather than mirroring a private scoring formula byte-for-byte. Any ranking change affecting those expectations is reviewed with the queries and returned results together.

Required baseline retrieval cases:

| Query / filter | Observable result |
|----------------|-------------------|
| `E014` and `how do I fix e014` | `diagnostic:E014` is first and links to actual width rules. |
| `E017` | The memory declaration diagnostic is first, with the documented instance-position `[W, A]` rule reachable. |
| `E999` with diagnostic filter | No invented diagnostic result. |
| `input pins` | `ref:language:input-pins` is in the first three. |
| `parametric sub circuit width arguments` | `ref:language:parametric-sub-circuits` is in the first three. |
| `slice high end exclusive` | The canonical slicing section is in the first three and preserves the half-open rule. |
| `concat low bit first` | The canonical concatenation/bit-order section is in the first three. |
| `imports multiple files` | The import section and the full-adder tour example are reachable in the first five. |
| `half adder` with example filter | The gallery half-adder and relevant tour example are returned; direct example retrieval yields source, not its preview alone. |
| `ROM lookup initialization` with example filter | `example:rom-lookup` is in the first three and retrieval includes its image. |
| `RAM clock write read` with example filter | `example:ram-write-read` is in the first three and returns RAM initialization labeled as runtime data. |
| `reset unknown pins` | The browser simulation protocol section is in the first three, including reset versus boot behavior. |

Assign/freeze the corresponding semantic section/tour slugs in Slice 1, then use those exact IDs in `queries.json`; no fixture relies on array positions.

### Compatibility and errors

`HelpContext.compiler` is the identity validated during generation. Read the active compiler identity through a lightweight callback into the controller; do not initialize it to perform a comparison. Compare version/revision, grammar, parser runtime where available, and topology identities. When uninitialized, return `not_initialized`; when initialized and comparable fields differ, return `mismatch`. `match` means those reported identity fields agree; it does not claim a new browser-side WASM byte-hash verification or a re-run of example tests. A known mismatch does not rewrite the corpus or mark its examples validated against the active binary. Return the reference with explicit context so the agent can see which version it describes. Status/global compiler state is not modified by help.

Add domain error members through the inherited Phase 1 domain-result-to-registry mapping:

| Code | Meaning | Retryable with the same invocation |
|------|---------|------------------------------------|
| `HELP_UNAVAILABLE` | Static manifest/index/shard could not be loaded within the fetch deadline | Yes; report the failing asset class/status in bounded details |
| `HELP_INVALID_CORPUS` | Unsupported schema, invalid structure, digest mismatch, undeclared path, or inconsistent corpus IDs | No; reload/rebuild the site data |
| `HELP_CORPUS_CHANGED` | The caller's expected corpus or cursor differs from this page's pinned corpus | No; rediscover and explicitly choose the current corpus |
| `HELP_NOT_FOUND` | ID is absent from canonical records and aliases | No |
| `HELP_REMOVED` | A known ID was intentionally removed | No; include its replacement ID when recorded |
| `HELP_CANCELLED` | Caller cancelled retrieval | No |
| `HELP_BUSY` | The page already has 32 pending help invocations | Yes after a pending invocation finishes |

Use inherited `INVALID_ARGUMENT`, `INVALID_RANGE`, `RESULT_TOO_LARGE`, `PAGE_SUSPENDED`, and `PAGE_DISPOSED` where applicable. A valid query with no matches is successful data, not `HELP_NOT_FOUND`. Validation/compiler generation failures fail the build and identify the record; they do not become fabricated runtime help records.

## Execution & Concurrency Model

### Build-time pipeline

The generator is an asynchronous Bun build script with serial compiler access. The compiler ABI owns one result buffer, so two operations on the same instance must never overlap; copy results through the existing `callOp` helper before the next call.

Generation order:

1. Read only declared inputs and record their content hashes. Validate ID inventory, aliases, document keys, example/tour slugs, and diagnostic-registry/table coverage.
2. Produce canonical reference body/heading mappings with the same Astro Markdown processor configuration used by the generated reference pages (syntax highlighting can be disabled because it does not define heading IDs). Build reference and diagnostic records from original content/source positions.
3. Derive example files/resources/memory descriptors, instantiate the committed compiler, and verify binary/manifest/grammar identity. Compile every example project's complete overlay using default warning policy, preserving reported warnings. Analyze/inspect decoded topology as needed to validate declared memory targets and shape.
4. Run a fixed bounded set of behavior scenarios on isolated runtimes loaded from those freshly compiled artifacts. Use explicit initialization and declared images; no scenario depends on previous examples' runtime state. Destroy each runtime when finished. These are build validation functions reused by tests, not live playground operations.
5. Assemble deterministic records, term counts, excerpts, related IDs, and immutable assets. Check schema/record/response budgets and ID/resource referential integrity. Verify generated-citation expectations against the processor's rendered output.
6. Write the candidate hashed assets, then publish the pointer last. A failed validation must leave the previous complete pointer intact and exit nonzero, preventing Astro from producing a new page that advertises a partial corpus.
7. Remove obsolete files only from the previous owned-output list after validating their paths belong to this generator's output root. Retain unrelated files. A corrupted ownership list fails cleanup explicitly rather than broad-deleting a directory.

Track newly created candidate paths during publication and remove only those on a failed write; never remove reused hashed files referenced by the previous pointer. Keep build-temporary files under the already ignored `.astro/agent-reference-tmp/`, with separate owned runs, rather than leaving failed validation inputs in the public asset tree.

The site scripts become:

```json
{
  "agent-reference": "bun run scripts/build-agent-reference.ts",
  "dev": "bun run sync && bun run llm-mirror && bun run agent-reference && astro dev",
  "build": "bun run sync && bun run llm-mirror && bun run agent-reference && astro build"
}
```

The default `agent-reference` invocation must perform validation; do not add a production flag that stamps unchecked examples as passed. If the environment cannot run the committed compiler/runtime, fail with an actionable message and record the blocker rather than silently adopting `SKIP_LIBCIRC_TEST` as a successful generation path. Existing tests that honor that skip flag remain as they are, but a skipped check cannot satisfy this phase's acceptance. The Astro page reads the generated pointer through a build-only filesystem helper when rendering, rather than a TypeScript JSON import that fails module resolution in `astro check` on a clean checkout before generation; actual page rendering still fails explicitly if its required generated corpus is absent.

Run compiler/runtime verification in a bounded child process of the generator so a stalled synchronous WASM call cannot hang the build indefinitely. Start with a 60-second whole-corpus verification deadline, explicit per-scenario caps, and a deterministic machine-readable success/failure report. A timeout terminates that verification process and fails generation without publishing. Child invocation uses argument arrays and the current Bun executable; do not shell-interpolate source, IDs, or paths. Measure actual local/CI duration before accepting the deadline and record any justified adjustment. Temporary verification data lives under an owned build-temp directory and is cleaned on success/failure; it is not a deployed backend.

Behavior scenarios are finite: inverter truth values; all four half-adder inputs; all eight input vectors for the two-file full-adder tour example; representative width/slice/concat vectors; selected ROM addresses against its image; and a RAM write/read/reset sequence with explicit clock transitions. Store test inputs/expected outputs as scenario data keyed by stable example IDs in the verification helper or fixture files, never as duplicate source programs. Examples outside those scenarios retain `behavior: not_checked`. Reference fences illustrating bad syntax are never run as positive examples.

### Browser service and loading

- Register the lightweight help descriptor alongside existing tools. Its module imports only contract types and small validators statically. It dynamically imports the knowledge client/search code only when `circ_help` is invoked; no reference assets, source corpus, Markdown processor, compiler helpers, or renderer load merely because tools are discovered.
- The page passes a build-pinned immutable manifest asset locator and expected corpus ID into the service factory. First invocation fetches and verifies that manifest. Search loads the index, while read/example uses its lookup map and then only the required shard. Cached calls reuse verified data.
- Deduplicate concurrent fetches by asset path/digest. Allow at most four simultaneous asset fetches and 32 pending help invocations; additional invocations return `HELP_BUSY`, while accepted requests share a bounded fetch queue. Each caller has its own cancellation/deadline semantics; one cancelled caller must not abort a shared asset fetch still needed by another. Abort an underlying fetch only after no interested caller remains or the service/page is disposed.
- Use a 10-second fetch deadline per asset; clear failed in-flight cache entries so an explicit retry can succeed. Never poison the page with a permanently rejected initialization promise. Do not retry in an unbounded loop.
- Validate declared byte sizes, actual byte size/hash, schema, IDs, and referenced record kinds before caching. Use browser Web Crypto SHA-256 and return an explicit unavailable/error result if the required environment cannot perform verification; do not silently skip digests.
- Pin one corpus for the page installation. An old HTML page whose hashed assets disappear after a deployment reports a load error and advises reload; it does not combine an old index with a newer mutable manifest. A caller with an expected corpus/cursor from another version receives `HELP_CORPUS_CHANGED`.
- Search and section slicing are synchronous pure work after assets load. Bound query/result/index sizes before work. This phase introduces no search worker; record warm search duration against a 50 ms per-call target on the reference desktop environment, and raise a concrete finding before changing this model if it is exceeded.
- Keep verified manifest/index for the page lifetime; use an LRU for loaded full shards with an 8 MiB serialized-byte budget. In-flight assets are bounded independently. A single shard may be at most 1 MiB; index at most 1 MiB; manifest at most 128 KiB; total generated record assets at most 8 MiB. Generation enforces these caps and reports raw/gzip/index counts so growth is reviewable.
- On Phase 0 suspension, resolve pending help invocations as `PAGE_SUSPENDED`, release unused in-flight work, and retain bounded verified cache for bfcache restoration. Disposal resolves `PAGE_DISPOSED`, aborts remaining fetches, and drops all cache/listeners. Late fetch completion cannot resurrect a disposed service. Provider cancellation uses Phase 1's optional execution context; it does not enter the JSON schema.
- A help result's active-compiler comparison is captured immediately before final response assembly from the existing identity reader. It is an observation, not a request to initialize, analyze, compile, or rebuild anything. Corpus identity remains fixed throughout the call.

## Persistence & I/O

The browser adds no localStorage fields or keys. Reference cache and pending requests are memory-only. All runtime I/O is GET of declared same-origin static assets; there is no source upload, analytics event carrying queries, external search, or arbitrary URL fetch in the knowledge service. The agent receives only the bounded results it requested through the existing tool transport.

The generator reads canonical repository inputs, the committed compiler/manifest, and its own metadata/verification fixtures. It writes ignored generated assets. Stable ID inventory, input metadata, verification scenarios, and generator code are tracked. Repeated generation with the same inputs produces identical hashed assets and pointer contents; volatile timestamps, absolute local paths, and incidental file iteration order are excluded.

Publish `sim-protocol.md` at `/reference/sim-protocol` and its Markdown twin through the shared registry. The reference subset of `llms-full.txt` must be derived from that registry, preserving landing/gallery/download entries explicitly. Include gallery image descriptors/hex in its Markdown twin so human and tool consumers can reproduce the same content; the knowledge example still reads canonical content directly.

Extend sync/mirror ownership bookkeeping for their generated files without deleting unowned public assets. Generator cleanup rules are root-constrained and tested with corrupted/stale manifests. The knowledge generator owns only `public/agent-reference/`; reference sync/mirror own their separately recorded outputs. Newly generated section IDs do not require rewriting canonical Markdown just to add anchors.

Store citation routes as root-relative logical paths plus the actual fragment. Public responses project these into `ResolvedCitation`, retaining the logical paths and adding complete `htmlUrl`/`markdownUrl` values against the current page origin and configured `BASE_PATH`; this points at the same deployed snapshot the tool is reading. Generated mirror prose may continue using the configured canonical site origin. Browser asset requests also use the current origin/base. Verify both root deployment and a non-root base such as `/circ-compiler/`. Do not hardcode `https://circ-lang.org/reference` into browser fetch code or duplicate the base prefix. Gallery HTML citations use `#<example.slug>`; Markdown citations use the actual mirror heading anchor or an explicit generated alias. Tour content has no standalone `/tour` page: cite its owning content source and a generated tour Markdown twin under the owned reference output tree if a public prose/source citation is needed; never link a supposedly readable tour section to the redirect-only `/tour` route.

For tour citations, generate `public/reference/tour-examples.md` from the retained tour records, include it in the LLM index/full bundle, and use explicit stable slug anchors. This is a static Markdown reference, not a restored interactive tour page. The `playgroundId` remains a separate selection link. Add this generated file to mirror ownership and built-link tests.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Define corpus identity and extraction | Shared canonical-reference helpers, explicit document/tour IDs, simulation-protocol registry and tour Markdown twin generation, section extraction through the build-only Astro processor, diagnostic cross-checks, and reviewed ID/query fixtures. | Heading/code-fence/source-range tests, diagnostic-set equality, ID stability/alias/tombstone tests, and base-path citation fixtures pass. |
| 2 | Generate verified complete examples and assets | Bounded committed-WASM validation, complete example/resource records, deterministic manifest/index/shards, pointer-last publication, owned cleanup, and build/dev generation wiring. | All positive examples compile, memory shapes validate, representative behavior scenarios pass, repeated generation is identical, and failure leaves the last complete corpus pointer intact. |
| 3 | Implement local retrieval | Pure deterministic lexical ranking, exact-code lookup, corpus-bound search pagination, section/resource chunking, and inline/manifest example delivery. | Named relevance fixtures and negative cases pass; oversized Unicode/source/image fixtures reassemble exactly within the inherited response budget. |
| 4 | Expose lazy circ_help | Browser knowledge service, lightweight tool descriptor/action validation, immutable manifest locator on the page, shared native/external dispatch, and lifecycle/cancellation integration. | Public help discovery fetches nothing; first calls load only required static assets; concurrency, corruption, retry, cancellation, mismatch, and no-project-mutation tests pass. |
| 5 | Complete public-reference parity and prove agent use | Verify simulation protocol and tour Markdown citations, finish the memory-complete gallery twin and dynamic full-bundle membership, and deliver final link checks, usage/decisions, and actual ChatGPT/external retrieval walkthroughs. | Every returned citation/resource resolves in the built site, real agents retrieve width/diagnostic/multi-file/memory help, corpus/compiler evidence is accurate, and site gates/budgets pass. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own. Extraction/generation are independently verifiable build-time deliverables before the tool ships. The tool description only advertises actions and records that the generated corpus actually provides. Public-reference corrections and decision documentation land with the slice that requires them rather than being deferred wholesale to the last slice.

## Tests

Test names below are required assertions/scenarios, not claims that they already exist. Share verification functions with the generator so build metadata and tests cannot disagree about what passed, while expected behavioral vectors and retrieval relevance remain independently specified fixtures.

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `markdown_sections_ignore_fenced_headings` | `agent-reference-build.test.ts` | Heading-looking code is not a section; real nested sections retain exact source text, hierarchy, and original line ranges. |
| `citations_use_rendered_heading_ids` | `agent-reference-build.test.ts` | Inline code, numbering, punctuation, duplicate headings, and title stripping map to the same anchors the Astro processor renders. |
| `semantic_ids_survive_reordering_and_renumbering` | `agent-reference-build.test.ts` | Moving/renumbering sections or tour records retains knowledge identity and updates only location/playground association. |
| `duplicate_ids_and_alias_cycles_fail` | `agent-reference-build.test.ts` | Ambiguous semantic IDs, missing overrides, alias cycles, dangling references, and removed IDs without inventory updates are rejected. |
| `diagnostic_registry_and_reference_agree` | `agent-reference-build.test.ts` | Every compiler code has one canonical diagnostic record with the registry message and documented explanation; no invented code is added. |
| `example_files_and_memory_come_from_content` | `agent-reference-build.test.ts` | Multi-file arrays, root selection, descriptions, and memory images match canonical gallery/tour content rather than the lightweight catalogue/mirror. |
| `corpus_hash_covers_real_inputs` | `agent-reference-build.test.ts` | Source, compiler bytes, IDs, or ranking-schema changes alter corpus identity; timestamps and filesystem iteration order do not. |
| `failed_generation_does_not_publish_partial_corpus` | `agent-reference-build.test.ts` | Compiler/digest/record validation failure leaves the previous complete pointer intact and exits failure. |
| `cleanup_is_owned_and_root_constrained` | `agent-reference-build.test.ts` | Obsolete owned assets disappear; unrelated files and malicious traversal entries are never deleted. |
| `exact_diagnostic_is_ranked_first` | `knowledge-search.test.ts` | Exact `E014` in mixed-case natural-language queries returns its canonical diagnostic before general width references. |
| `unknown_diagnostic_is_not_invented` | `knowledge-search.test.ts` | `E999` under diagnostic filter has no fabricated match or substituted nearby code. |
| `relevance_fixture_queries_find_expected_sections` | `knowledge-search.test.ts` | The reviewed width/import/concat/reset/memory queries meet their expected top-three/top-five bounds. |
| `ranking_is_deterministic_and_not_source_length_driven` | `knowledge-search.test.ts` | Reordered index input produces the same results; repeated gate tokens in a long adder cannot overwhelm exact/title matches. |
| `search_cursor_binds_query_filter_and_corpus` | `knowledge-search.test.ts` | Paging returns each ranked result once and rejects changed query/filter/corpus cursors. |
| `read_chunks_preserve_markdown_circ_and_hex` | `knowledge-client.test.ts` | UTF-16-safe chunks reproduce exact text/fences/newlines; hex chunks preserve full bytes and reject odd starting offsets. |
| `large_example_returns_complete_resource_manifest` | `knowledge-client.test.ts` | Oversized inline delivery switches to explicit incomplete-source manifest mode, listing every file/image and enabling hash-matched lossless reassembly. |
| `help_discovery_is_lazy` | `knowledge-client.test.ts` | Registering/listing tools loads no knowledge assets, Markdown/compiler package, or renderer. |
| `asset_requests_are_shared_but_cancellation_is_per_caller` | `knowledge-client.test.ts` | Concurrent lookups share verified fetches; cancelling one caller leaves another's request alive, and unused fetches are released. |
| `fetch_failure_can_be_retried` | `knowledge-client.test.ts` | Timeout/404/network failure clears the failed in-flight cache entry; a later explicit retry can succeed without an infinite retry loop. |
| `mixed_or_corrupt_corpus_is_rejected` | `knowledge-client.test.ts` | Wrong digest/byte size/schema/corpus ID or an undeclared asset path fails before caching/returning record data. |
| `compiler_comparison_does_not_initialize_wasm` | `knowledge-client.test.ts` | Uninitialized/known-matching/known-mismatching identities are labeled correctly with no compiler/session call. |
| `suspend_dispose_and_late_fetch_are_safe` | `knowledge-client.test.ts` | Pending calls receive the proper lifecycle error; late completion cannot revive disposed state; bfcache restoration can reuse verified bounded cache. |
| `reference_cache_and_asset_budgets_are_bounded` | `knowledge-client.test.ts` | Shard LRU eviction and manifest/index/asset limits prevent unbounded retained corpus data. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `every_returned_example_compiles` | Generator and `agent-reference-verify.test.ts`, real committed libcirc | Every indexed gallery/tour project compiles from its returned named-file overlay and entry, with real warnings preserved. |
| `returned_memory_images_match_declared_shapes` | Real compiler/topology plus image helpers | Every declared image targets the correct root file/memory/kind and satisfies whole-word/capacity/width checks; RAM data is not mislabeled as a source ROM setting. |
| `half_and_full_adder_examples_match_vectors` | Isolated freshly compiled runtimes | All four half-adder and eight multi-file full-adder inputs produce independently specified sums/carries. |
| `inverter_and_bitshape_examples_match_vectors` | Isolated runtimes | Inversion, slice endpoints, and concat low-bit order match actual output values and any canonical description correction is made at its source. |
| `rom_example_uses_returned_image` | Isolated ROM runtime | Selected addresses read the supplied image values, proving source alone was not treated as complete initialization. |
| `ram_example_initialization_and_clock_sequence` | Isolated RAM runtime | Supplied initial RAM bytes load correctly; explicit low/high clock sequence writes/reads the expected word; reset semantics are declared and verified. |
| `verification_timeout_fails_generation` | Bounded verification subprocess fixture | A deliberately stalled verifier terminates at its deadline and cannot publish passed metadata or hang the site build indefinitely. |
| `generated_reference_links_resolve` | Fresh built site | Reference/diagnostic HTML and Markdown citations, gallery anchors, simulation protocol, tour Markdown anchors, and all resource assets exist. |
| `root_and_subpath_deploys_resolve_help_assets` | Builds with root and non-root base fixtures | Generated locators/citations resolve once under the configured base without hardcoded production origins or duplicated prefixes. |
| `mirror_and_help_share_memory_complete_examples` | Generated mirrors and corpus | Gallery/tour source and initialization descriptors match canonical content; the full LLM bundle includes every registered reference plus the tour Markdown twin. |
| `public_help_actions_share_native_and_page_contract` | Built island/registry plus verified adapter | Search/read/example validation and decoded responses match across both access paths under a fixed corpus/compiler observation. |
| `help_lookup_does_not_change_playground_state` | Built island and real browser | Help calls leave project/source revisions, selected entry, compiler operation count, session identity, pins, images, and persistence untouched. |
| `chatgpt_reference_diagnostic_and_example_lookup` | Actual primary ChatGPT browser path | ChatGPT discovers `circ_help`, retrieves width/parameter guidance and `E014`, then retrieves the complete two-file adder and memory example with citations and version context. |
| `external_agents_reference_and_example_lookup` | Actual OpenCode and Claude Code paths | Both clients perform the same semantic discovery/search/read/example workflow through Phase 0's verified tooling and report source plus initialization accurately. |
| `knowledge_does_not_enter_eager_or_light_page_graphs` | Source graph and built bundle | The descriptor remains small; search/corpus/compiler-build/Markdown/renderer code is absent from eager/light page graphs, and existing route budgets pass. |

Run command, from `site/`, for extraction/search/client unit coverage:

```sh
bun test test/agent-reference-build.test.ts test/knowledge-search.test.ts test/knowledge-client.test.ts
```

Run command, from `site/`, to generate and validate the corpus explicitly:

```sh
bun run agent-reference
```

Run command, from `site/`, for compiler/runtime evidence:

```sh
bun test test/agent-reference-verify.test.ts
```

Required site gate, from `site/`:

```sh
bun --bun run typecheck && bun --bun run build && bun test && bun run bundle
```

Use the accepted Phase 0 setup/versions for real ChatGPT and external-agent walkthroughs against the fresh built page. Record actual query/action arguments, returned IDs/citations/context, complete example file/image counts, and observed absence of project mutation. A useful demonstration asks for a parametric width rule, an exact diagnostic, the multi-file full-adder, and the initialized RAM example. Compiler verification is performed by the generator/test harness in this phase; do not pretend the not-yet-shipped agent authoring/simulation tools ran that demonstration.

## Open Questions / Spikes

- **TODO(phase2): Reconcile prior-phase implementation contracts.** Phases 0–1 are specifications at this planning baseline. Use their accepted registry/domain-result/cancellation interfaces when implementing; maintain one shared `circ_help` definition and the existing response budget.
- **TODO(phase2): Verify Astro processor alignment.** The inspected installed processor is `@astrojs/markdown-remark@6.3.11`; confirm the implementation lock resolves the site and generator consistently, and prove heading metadata/positions against the built reference before accepting citations. Update the exact build-only pin only with that evidence if Astro changed.
- **TODO(phase2): Freeze the complete ID inventory and retrieval fixtures.** Assign semantic IDs/overrides to actual sections and explicit slugs to all retained tour steps in Slice 1. Record aliases/tombstones for deliberate changes; do not use positional IDs or title-only guesses for actual HTML anchors.
- **TODO(phase2): Validate content claims against real behavior.** The current NOT-chain example has three inverters but its lede says the output is `a`; the representative inverter check should expose and correct that canonical description. Check the documented feedback examples against the shipped compiler without inventing an alternate agent-only explanation. Any other failing example/description is a content finding, not permission to mark it verified.
- **TODO(phase2): Measure build verification on the deployment environment.** Historical library records include skipped WASM tests on some hosts. Establish that the selected Bun/Node/committed-WASM combination can complete corpus validation, record durations, and keep timeout/failure reporting explicit. If the static deployment environment cannot perform required validation, bring that concrete blocker to the human before weakening the build's passed-metadata contract.
- **TODO(phase2): Record initial corpus/search cost.** Measure record counts, manifest/index/shard raw and gzip sizes, cold/warm help load counts, ranking time, and representative agent-call output sizes. Stay within stated limits and the existing route budget; any worker/search-library or budget change requires a measured follow-up decision.
- Scope, source ownership, local retrieval, complete-example delivery, compiler/version evidence, lifecycle behavior, and acceptance strategy are fixed above. These spikes verify actual inputs/toolchain behavior during implementation; they do not authorize a backend or a separate hand-maintained language manual.
