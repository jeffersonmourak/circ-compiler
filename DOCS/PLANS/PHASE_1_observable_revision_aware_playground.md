# Phase 1 — Observable, revision-aware playground

> **Dependencies:** Phase 0 — Connection contract and first tool, implemented and accepted before this phase's implementation begins. Read `PHASE_0_connection_contract_and_first_tool.md` for the registry, public facade, native adapter, result envelope, and lifecycle contracts.
> **Warnings:** Read the macroplan and `DOCS/decisions/{playground,playground-bench,libcirc}.md`. The Phase 0 modules are specified but not implemented at this planning baseline; resolve their actual exported names before writing code. `state.doc` is not a source-only revision, `Stage.seq` advances at timer fire, and artifact hashes do not prove byte equality. The active file is the runtime entry point. ChatGPT remains the primary native target; both external clients use Phase 0's verified connection paths. This phase exposes reads and waits, not new agent-driven mutations or builds.

## Goal

An agent can discover the available projects, inspect a project's files, read exact source text in bounded chunks, and determine which source/configuration produced the displayed diagnostics, artifact, and live session. It can wait for a named operation already scheduled by the playground and receive an explicit terminal outcome or a bounded wait timeout. Human edits, file/project switches, settings and source-image changes, delayed replies, byte-identical recompiles, worker failures, and runtime resets update the corresponding identities without treating old output as current. The visible playground continues to show its last good output during failing body edits and clears unrelated output on target changes; the tools make those distinctions observable. Reads do not select files, trigger builds, flush debounces or persistence, or initialize the compiler/session.

## Scope

**In scope:**
- Extend Phase 0's controller and result contract with tracked project/source/configuration/target revisions, operation identities, artifact provenance, and session identity/state.
- Add `circ_list_projects`, `circ_read_project`, `circ_read_file`, and `circ_wait_for_operation`; upgrade `circ_get_status` to report authoritative freshness alongside its inherited observational fields.
- Read active editor buffers, inactive scratch records, and shipped catalogue content through the existing model, with bounded revision-bound pagination and no selection side effects.
- Track the existing analyze, compile, preview, Truth, session-build, and session-reset operations from scheduling through terminal outcomes.
- Capture request bodies, options, entry target, source-file mapping, and relevant runtime/preload inputs before asynchronous work; correlate each output with that captured input.
- Track existing UI changes so revisions move when their actual inputs change, independently of persistence timestamps and debounce counters.
- Repair stale-result publication, busy-state ownership, missing async error finalization, and reset-after-destruction races necessary for truthful status.
- Preserve matching byte-identical artifacts/runtimes where valid, while recording a newly validated source revision and maintaining separate runtime-configuration identity.
- In-memory bounded operation retention and event-driven waiting, including timeout, cancellation of the wait, page suspension/disposal, and expired operation IDs.
- Existing UI and console behavior, compiler request semantics, docs, and regression tests updated with each relevant slice.

**Explicitly deferred:**
- Agent project/file mutations and explicit compile/analyze initiation, which ship in Phase 3.
- Full diagnostic-message/range retrieval and repair tools in Phase 3; this phase reports counts, producer identity, and operation outcomes.
- Language help and example lookup, which ship in Phase 2.
- Agent pin/reset/memory mutation tools and isolated behavioral verification in Phase 4.
- Schematic/topology/Truth payload tools, view changes, settings tools, and exports in Phase 5; their existing UI work is tracked here.
- Persisting operation history or revision IDs, cross-tab live synchronization, worker preemption, automatic worker crash recovery, and long-loop chunking.
- Changes to circ syntax, CLI modes, topology encoding, renderer dependencies, or storage limits.

## File & Module Topology

Paths are relative to the worktree root. New modules hold behavior testable without importing an Astro island; project/source data stays owned by the existing application model.

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| Revisions | `site/src/scripts/playground-revisions.ts` | Opaque identity allocation, project/source/configuration comparisons, target epochs, and per-output input equality. |
| Operations | `site/src/scripts/playground-operations.ts` | Operation records and legal transitions, bounded retention, wait subscriptions/deadlines, and lifecycle finalization. |
| Read model | `site/src/scripts/playground-reads.ts` | Project summaries, file manifests, revision-bound cursors, and Unicode-safe bounded file chunks over injected project snapshots. |
| Workspace tools | `site/src/scripts/agent-tools/workspace.ts` | Shared descriptors, validation, and handlers for list-projects/read-project/read-file. |
| Wait tool | `site/src/scripts/agent-tools/operations.ts` | Shared descriptor, validation, and handler for waiting on an existing operation. |
| Revision tests | `site/test/playground-revisions.test.ts` | Change classification, identity lifetime, snapshot ownership, and byte/provenance reuse rules. |
| Operation tests | `site/test/playground-operations.test.ts` | Transition, retention, deadline, supersession, failure, and subscriber cleanup tests over fake time/deferred work. |
| Read tests | `site/test/playground-reads.test.ts` | Active/inactive source selection, paging, conflict errors, Unicode boundaries, and no-side-effect reads. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| Contract | `site/src/scripts/playground-contract.ts` | Add tracked status, revision/input/operation/read DTOs and error-code members; retain Phase 0's envelope and existing fields. |
| Controller | `site/src/scripts/playground-controller.ts` | Coordinate projections, revision notifications, operations, and waits over injected model/session/compiler dependencies. |
| Status tool | `site/src/scripts/agent-tools/status.ts` | Update the descriptor and return tracked status; remove the Phase 0 untracked-release description after tracking is actually connected. |
| Registry/page lifecycle | `site/src/scripts/agent-tools/{registry,page-api}.ts` | Register the new descriptors and terminate outstanding waits on suspension/disposal; permit the controller's internal cancellation signal to reach wait handlers. |
| Native adapter | `site/src/scripts/webmcp-adapter.ts` | Forward provider cancellation when supported by the Phase 0 compatibility findings; preserve decoded result parity. |
| Playground island | `site/src/components/Playground.astro` | Notify model changes, snapshot requests, associate outputs and sessions with records, and derive publication/busy/stale state from the correct request. |
| Pipeline helpers | `site/src/scripts/pipeline.ts` | Retain Stage's timing contract; add or consume request-aware publication helpers and terminal outcomes without using `seq` as a source revision. |
| Compiler client | `site/src/scripts/libcirc-client.ts` | Notify the owner of fatal worker/transport failures, reject outstanding work exactly once, and reject new calls after a fatal failure rather than sending into a known dead worker. |
| Simulation session | `site/src/scripts/sim-session.ts` | Expose a separate lifecycle observer for reset/run observation; guard async reset against destruction and report preload application results needed by session status. |
| Existing tests | `site/test/{playground-controller,agent-tools,webmcp-adapter,pipeline,shared-client,sim-session,source-images,island-smoke}.test.ts` | Extend Phase 0 and existing behavioral tests for authoritative tracking and real-page integration. |
| Usage/decisions | `DOCS/agent-playground.md`, `DOCS/decisions/agent-playground.md` | Document read/wait tools, freshness, limits, in-memory identity lifetime, worker failures, and concrete acceptance evidence. |

`DOCS/STATUS.md` receives implementation entries under the macroplan's working loop. Add any newly split test file to its module's phase record, rather than silently dropping a named assertion. Existing package scripts and budget files suffice.

**New dependencies:** None. Use the existing TypeScript/Bun tests, worker client, CodeMirror handle, native adapter, and renderer/session APIs. No new worker, network endpoint, storage key, or schema migration is introduced.

### Source anchors to verify before implementation

- `Playground.astro:1328–1356`, `1382–1417`, and `3104` onward: project load, example fork, file selection, and file operations.
- `playground-store.ts:764–792`: oversize scratch edits may remain in the active buffer while the stored record retains earlier text; `resolveSource` alone cannot read the active project accurately.
- `Playground.astro:2240–2287`, `2742–2755`, and `2964–2982`: mutable source-image maps, preload application, settings projection, and output scheduling.
- `Playground.astro:3276–3315`, `3483–3593`: schedule/flush/analyze/build/preview; the old code captures `state.doc` before compiler readiness but builds requests after that await.
- `Playground.astro:3754–3834`: compiler and scratch Truth paths; snapshot fixed pins, source images, and table identity independently of build debounce sequence.
- `Playground.astro:4126–4229`: session drop/build/replay/subscription; compiled source-file metadata and current analysis must not be mixed.
- `sim-session.ts:357–395`: preload result and async reset; destruction currently does not guard the later `await load()` continuation.
- `libcirc-client.ts:28–66`: worker errors reject pending calls, but the existing caller paths lack uniform terminal outcome handling and the client retains its worker/init state.
- `pipeline.test.ts:159–185`: a pending later debounce deliberately does not invalidate `Stage.seq`; preserve this timing fact while adding source-aware publication rules.

## Data & State

### Identity model

Opaque strings are generated from Phase 0's page ID and a monotonic allocation sequence; callers compare them for equality and do not interpret their encoding. Test factories are deterministic. They are never saved to localStorage and never derived from timestamps or FNV hashes.

```ts
export type Revision = string;
export type OperationId = string;
export type ArtifactId = string;
export type SessionId = string;

export interface ProjectVersion {
  projectId: string;
  revision: Revision;
  sourceRevision: Revision;
  imageRevision: Revision;
}

export interface TargetRef {
  projectId: string;
  sourceRevision: Revision;
  entryFile: string;
  targetEpoch: Revision;
}

export type OperationKind =
  | 'analyze'
  | 'compile'
  | 'preview'
  | 'truth_table'
  | 'session_build'
  | 'session_reset';

export interface WorkInputs {
  target: TargetRef;
  optionsRevision: Revision;
  imageRevision: Revision | null;
  artifactId: ArtifactId | null;
  liveStateRevision: Revision | null;
}
```

Identity rules:

| Identity | Changes when | Does not change merely because |
|----------|--------------|--------------------------------|
| Project `revision` | Readable project name, ordered named-file contents, or declaration-owned image text changes | The project is read, saves, or becomes active |
| `sourceRevision` | Any file body/name/order is changed, inserted, or removed | Entry selection, compiler settings, images, save timestamps, or display preferences change |
| `imageRevision` | The project's effective source-image text by file/declaration changes | A memory filename label/implied-zero decoration or value-format display changes |
| Workspace revision | Listed project IDs/order/names/readable revisions or the active-project flag change | Pagination, a source read, or entry selection within the same project occurs |
| `targetEpoch` | The active project or active entry changes, including switching away and back | Body edits within that target or status reads occur |
| Per-operation `optionsRevision` | That operation's projected semantic options change | An option irrelevant to that operation changes |
| `artifactId` | A different compiled byte payload or incompatible exact-request source-file mapping replaces the accepted artifact | The same bytes and compatible mapping validate a newer source revision |
| `sessionId` | A runtime becomes ready after a fresh load, reset, or reset failure that retains the old runtime | Ordinary pin/memory drives or status reads occur |
| `liveStateRevision` | A published session drive/memory/preload/run/reset completion changes or may change runtime observations | The same values are read or the canvas is repainted |

Compare actual ordered file names/bodies and operation projections before bumping revisions. An ordinary no-op update keeps its revision; edit then undo allocates a new revision even if the content becomes equal to an older snapshot. Renaming a project changes its broad revision, not its source revision. Forking an example creates a new project identity with its own revisions. All identity state is materialized at bootstrap/mutation boundaries; public reads do not allocate new revisions as a side effect.

Keep workspace order deterministic: catalogue projects in their existing catalogue order, then scratch projects sorted by descending `updatedAt` with ID as the tie-breaker. Listing may preserve display group labels as metadata; it does not use the open/closed tree state or current search filter.

### Operation-specific inputs

- **Analyze:** all named files plus entry and an empty options projection. Image/configuration-only changes do not invalidate its input. A compile's diagnostic payload is a separate producer, even when its source target matches analysis.
- **Compile:** the same source target plus `optionsFor('compile', settings)`. Source-image changes do not invalidate compiled bytes; they affect runtime configuration separately. Capture source-file metadata for the exact compile request.
- **Preview:** the source target plus `optionsFor('preview', settings)`. It has its own operation sequence because settings/view requests can run outside the build debounce.
- **Compiler Truth:** the source target, projected Truth options, and relevant immutable preloads. Record whether it is exhaustive. A live pin change does not invalidate an exhaustive compiler table.
- **Scratch Truth:** the source target, artifact identity, options, source images, and the fixed-input snapshot when filtered. Use `liveStateRevision` only for a table depending on live values; exhaustive scratch Truth ignores unrelated live drives. Status records the path and filtered flag without returning table rows yet.
- **Session build/reset:** compiled artifact/source mapping, the image snapshot actually supplied, and explicit initialization mode. These operations do not borrow declarations or file IDs from a later analysis.

The snapshots backing these stamps contain copied file bodies, projected options, image text maps, analysis/file mapping where required, and fixed-pin values. Their large payloads remain internal and are released after consumers finish. Stamp equality uses the fields relevant to the operation, not the broad project revision; renaming the display title does not force a compile.

### Operation lifecycle and output provenance

```ts
export type OperationState =
  | 'queued'
  | 'running'
  | 'succeeded'
  | 'diagnostics'
  | 'refused'
  | 'failed'
  | 'superseded';

export interface DiagnosticCounts {
  errors: number;
  warnings: number;
}

export interface OperationSummary {
  id: OperationId;
  kind: OperationKind;
  inputs: WorkInputs;
  state: OperationState;
  createdAt: number;
  startedAt: number | null;
  finishedAt: number | null;
  counts: DiagnosticCounts | null;
  failure: {
    kind: 'transport' | 'bad_request' | 'oom' | 'internal' | 'runtime';
    message: string;
    libraryStatus: number | null;
  } | null;
  refusal: { message: string; libraryStatus: number | null } | null;
  supersededBy: OperationId | null;
  supersededReason: 'new_inputs' | 'new_request' | 'target_changed' | null;
  artifactId: ArtifactId | null;
  sessionId: SessionId | null;
  truthScope: 'exhaustive' | 'filtered' | null;
}

export type Freshness = 'absent' | 'current' | 'stale';

export interface OutputProvenance {
  operationId: OperationId;
  inputs: WorkInputs;
  counts: DiagnosticCounts | null;
}

export interface OutputStatus {
  freshness: Freshness;
  provenance: OutputProvenance | null;
}

export interface SessionStatus {
  state: 'absent' | 'building' | 'ready' | 'resetting' | 'failed';
  id: SessionId | null;
  artifactId: ArtifactId | null;
  liveStateRevision: Revision | null;
  imageRevision: Revision | null;
  matchesCurrentTarget: boolean;
  matchesCurrentImages: boolean;
  preloadState: 'none' | 'applied' | 'partial' | 'failed' | 'unknown';
  operationId: OperationId | null;
}
```

- Timestamps are informational epoch milliseconds from an injected clock, not revision keys. Counts are null before a producer has reported them; missing analysis is not zero errors.
- `queued` records are created when work is scheduled, before the debounce fires. A replacement finalizes the old queued record as superseded. `running` begins when the operation starts preparing/executing its captured inputs, including waiting for compiler readiness.
- Terminal states are immutable. An input-changing edit finalizes outstanding work for the old input as superseded; a later physical worker reply cannot rewrite that terminal result. Already completed success stays a historical success, while its output freshness may become stale.
- Compile status 0 with a valid artifact is succeeded. Compile status 1 is diagnostics. An analyze status-0 payload containing errors is diagnostics; warnings alone are succeeded with counts. Library status 3 is refused, status 2/4/5 or thrown/invalid responses are failed with their status/kind. A compile skipped because fresh analysis already proves an error or promoted warning is diagnostics, not succeeded or indefinitely queued.
- A compile operation ends when the artifact and its required exact-request metadata have been handled. Follow-on preview/Truth and lazy session construction have separate IDs; a compile success is not a promise that those operations succeeded or that a session exists.
- Current freshness requires compatible source target, relevant options, image/live-state dependencies, and publication ownership. A target change clears unrelated outputs. Matching inputs alone do not authorize an older request to replace a newer published request.
- Preserve the last **published** good output on body edits. Discard newly arriving obsolete output rather than publishing it as a replacement after an input change. Keeping the old visible artifact does not require accepting an old in-flight build's reply. Stage's debounce timing contract remains intact.

### Extend status without removing Phase 0 fields

Retain Phase 0's result envelope, project summary, `reportedPipeline`, compiler identity, artifact/session presence fields, persistence availability, and connection health. Expand its provenance discriminant to `'untracked' | 'tracked'`; after Phase 1 initialization, return tracked provenance only once all current model dependencies are registered.

```ts
export interface TrackedStatusFields {
  observationRevision: Revision;
  projectVersion: ProjectVersion | null;
  currentTarget: TargetRef | null;
  provenance: {
    tracking: 'tracked';
    sourceRevision: Revision | null;
    buildRevision: Revision | null;
    sessionId: SessionId | null;
  };
  outputs: {
    analysis: OutputStatus;
    diagnostics: OutputStatus;
    artifact: OutputStatus & { id: ArtifactId | null };
    preview: OutputStatus;
    truth: OutputStatus;
  };
  simulation: SessionStatus;
  operationIds: Record<OperationKind, OperationId | null>;
  compilerTransport: {
    state: 'not_started' | 'starting' | 'available' | 'failed';
    failure: string | null;
  };
}
```

`buildRevision` is the source revision of the displayed artifact's latest successful validation, not its byte hash or operation ID. It can differ from `sourceRevision`; `outputs.artifact.provenance` carries the full target/options stamp that makes the difference meaningful. `observationRevision` changes whenever a publicly reported model/operation/output/session fact changes, including new publication or preload failure, and stays stable across reads. It is not a write precondition; Phase 3 uses the project/target revisions appropriate to its mutation.

`operationIds` names the latest known request in each family for the current target epoch; null means none was requested. A session reset ID is shown while its original target remains active. Previous target operation IDs remain queryable within retention by callers already holding them. Output provenance summaries stay with displayed outputs even after a historical operation record expires.

The inherited `reportedPipeline` remains a compatibility/UI observation. `outputs` is authoritative for freshness. If the old status record or stale attribute would disagree, update the UI projection from tracked state at the publication/mutation boundary; do not change UI fields from a read tool. Compiler handshake identity may remain available after a worker crash, so `compilerTransport` separately says the client can no longer execute work.

### Read tools and pagination

All tools reuse Phase 0's descriptor/validation/result mechanism. Descriptions state that these operations read project content without selecting it or compiling it.

| Tool | Input | Default and limits | Result |
|------|-------|--------------------|--------|
| `circ_list_projects` | `{ cursor?: string, limit?: number }` | Limit 20, maximum 50; count and serialized-result bounds both apply | Workspace revision, project metadata page, next cursor or null |
| `circ_read_project` | `{ projectId?: string, expectedRevision?: string, cursor?: string, limit?: number }` | Omitted project means active at call capture; files limit 20, maximum 50 | Project version/name/source origin/default and selected entry, paged file metadata, next cursor or null |
| `circ_read_file` | `{ projectId?: string, name: string, expectedSourceRevision?: string, offset?: number, maxCodeUnits?: number }` | Offset 0; code-unit budget 2,048, maximum 4,096; expected source revision required for nonzero offset | Exact source substring and offset/length/EOF metadata bound to a source revision |
| `circ_wait_for_operation` | `{ operationId: string, timeoutMs?: number }` | Default 5,000 ms, range 0–30,000 ms | Captured operation outcome on terminal state, or current operation summary when the wait times out |

Use safe finite integer validation for numeric parameters; no coercion of strings or silent clamping. Unknown fields are invalid. Scope cursor tokens to the page, tool, project where applicable, and revision; they encode only traversal metadata, never source. An invalid/mismatched cursor is an argument error, and a correctly shaped cursor whose bound contents changed is a revision conflict. Repeated reads with unchanged contents and a cursor advance exactly once through deterministic ordering. Pagination may return fewer than the requested count to fit Phase 0's 32 KiB serialized application-result budget; one unrepresentable metadata item returns `RESULT_TOO_LARGE` rather than an empty non-progressing page.

Project/file-page `limit` is 1–50. `maxCodeUnits` is 2–4,096 so a valid request can always accommodate a complete surrogate pair; zero or one is invalid. Offset is a nonnegative safe integer. Manifest cursors also bind the header's active/selected-entry context: an entry or active-project change rejects a cursor whose header would otherwise silently change, without bumping the source revision. File chunks explicitly addressed by project/source revision remain readable across mere entry selection.

```ts
export interface ProjectSummary {
  id: string;
  name: string;
  kind: 'example' | 'tour' | 'scratch';
  active: boolean;
  version: ProjectVersion;
  fileCount: number;
}

export interface ProjectManifest {
  project: ProjectSummary;
  sourceOrigin: 'active_buffer' | 'scratch_record' | 'catalogue';
  defaultEntryFile: string;
  selectedEntryFile: string | null;
  files: {
    name: string;
    utf16Length: number;
    utf8Bytes: number;
    lineCount: number;
  }[];
  nextCursor: string | null;
}

export interface FileChunk {
  projectId: string;
  sourceRevision: Revision;
  name: string;
  encoding: 'utf16';
  offset: number;
  endOffset: number;
  totalCodeUnits: number;
  text: string;
  nextOffset: number | null;
  eof: boolean;
}

export interface WaitResult {
  wait: 'terminal' | 'timed_out';
  operation: OperationSummary;
}
```

### Controller and dispatch extensions

The registry remains the sole owner of the public `ToolResult` envelope. Read/wait methods return an internal domain result so expected lookup/conflict errors are not mistaken for unexpected thrown failures:

```ts
export type DomainResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: AgentError };

export interface ProjectPage {
  workspaceRevision: Revision;
  projects: ProjectSummary[];
  nextCursor: string | null;
}

export interface ObservationMethods {
  listProjects(input: {
    cursor?: string;
    limit?: number;
  }): DomainResult<ProjectPage>;
  readProject(input: {
    projectId?: string;
    expectedRevision?: string;
    cursor?: string;
    limit?: number;
  }): DomainResult<ProjectManifest>;
  readFile(input: {
    projectId?: string;
    name: string;
    expectedSourceRevision?: string;
    offset?: number;
    maxCodeUnits?: number;
  }): DomainResult<FileChunk>;
  waitForOperation(input: {
    operationId: string;
    timeoutMs?: number;
  }, context?: {
    signal?: AbortSignal;
  }): Promise<DomainResult<WaitResult>>;
}
```

Add these methods to the existing controller while retaining `getStatus()` and `dispose()`. Handlers map successful domain values to the registry's data field and domain errors to its error field; they never nest two public envelopes. Extend the internal handler invocation context with an optional `AbortSignal`. The native adapter may supply it when the provider supports cancellation, and controller/page lifecycle cancellation always applies. Do not add signals or functions to a JSON input schema or change `window.circPlayground.callTool(name, input)`.

### Read semantics

- `circ_list_projects` returns `{ workspaceRevision, projects: ProjectSummary[], nextCursor }`. It does not attach guessed diagnostics to inactive projects. Freshness belongs to the active target's status outputs.
- Active source is read from the current `state.tabs` bodies, including text that `touchScratch` could not persist. Inactive scratch source comes from the current in-memory envelope record, not a new localStorage read. Catalogue source comes from the already shipped catalogue. Reconcile revision state when loading/leaving a buffer so any change of readable contents receives a matching source revision; never reuse the active-buffer revision for different stored text.
- `selectedEntryFile` is the actual selection only for the active project; it is null for inactive projects. `defaultEntryFile` is the last file in interchange order. No inactive read changes selection, project activation, tree expansion, pin replay, or the console.
- Project manifests contain metadata, not bodies or memory image contents. Use `circ_read_file` to fetch each needed source. This avoids failure when a legal near-32-KiB source becomes larger after JSON escaping.
- File offsets are zero-based UTF-16 code units with an exclusive end, matching JavaScript text indexing. Reject a start offset inside a surrogate pair or beyond the document. Shorten an end boundary to avoid splitting a surrogate pair. Preserve exact newlines/whitespace without rejoining marker text. Empty files and reads at EOF return an empty string with EOF true and nextOffset null. Every non-EOF response advances.
- An optional first-read expected revision is checked before returning data. Nonzero-offset reads require the revision from the preceding response. If text changes mid-read, return a revision conflict instead of splicing old/new content. An expected project revision on a manifest includes project metadata/image changes; a file's expected source revision intentionally does not.
- A byte/metadata bound failure is explicit; silently truncating names, file bodies, or error provenance is not acceptable. Internal failure messages remain bounded under the inherited error contract.

### Errors and limits

Append the following application error members to Phase 0's union; do not change the meaning of existing codes:

| Code | Meaning | Retryable with the same arguments/facade |
|------|---------|-----------------------------------------|
| `NOT_READY` | Project restoration has not completed | Yes while initializing; no after bootstrap failure |
| `PROJECT_NOT_FOUND` | The requested project is absent or has been deleted/evicted | No |
| `FILE_NOT_FOUND` | The requested file is absent in that project snapshot | No |
| `REVISION_CONFLICT` | Expected source/project/cursor revision differs | No; reread and choose the new revision |
| `INVALID_RANGE` | Invalid or non-Unicode-boundary source offset | No |
| `OPERATION_NOT_FOUND` | Unknown operation ID or another page's ID | No |
| `OPERATION_EXPIRED` | A formerly issued operation record was evicted | No; current output provenance may still be inspected |
| `WAIT_LIMIT` | This page already has the maximum outstanding waits | Yes after another wait completes |
| `WAIT_CANCELLED` | Caller cancelled this wait | No; an intentional new wait is a new request |

Extend `AgentError` with optional bounded `details` only where useful, such as `{ expectedRevision, actualRevision, projectId }`; it remains JSON-safe. A terminal failed compiler operation is returned as `ok: true` with `wait: 'terminal'` and `operation.state: 'failed'`: the read/wait succeeded in observing a failed operation. A wait timeout similarly returns `ok: true` and does not finalize or cancel that operation.

Limits are constants in the relevant pure modules: 128 retained unpinned terminal operation records, maximum 32 concurrent waiters, per-call wait maximum 30 seconds, and the read/page limits above. Pin only the bounded set of terminal records referenced by current output/operation slots; release pins when those slots change. Live operations are not evicted to make room for terminal history. Use an issuance sequence and eviction bookkeeping to distinguish expired IDs without an unbounded set of every historical ID. Do not retain source snapshots, artifacts, or large diagnostics merely to keep a terminal summary.

Deliver a terminal summary to its existing wait subscribers before eviction can remove it. Already-terminal and zero-timeout observations consume no waiter slot, so they remain available when the outstanding-wait limit is reached.

## Execution & Concurrency Model

### Ownership and revision notifications

The existing project model/store continues to own source and user settings. The controller owns the revision tracker, operation store, current output provenance, and session binding. The worker owns its compiler instance. The session owns its runtime. The page registry and native adapter remain consumers of controller operations.

At every existing UI mutation boundary, compare the relevant before/after inputs and notify the tracker synchronously before scheduling dependent work. Cover CodeMirror changes, fallback textarea changes, project create/load/fork/rename/delete/duplicate/import, file insert/delete/rename/reorder/select, settings changes, and declaration-owned image edits. Initialization registers the source projects and their identities before tracked status is published. Store normalization and actual mutations remain in their current modules; do not implement a second normalization policy in the tracker.

Display-only editor preferences, theme, panel geometry, and source highlighting do not bump source/config revisions. A view selection changes observational state and may request preview/Truth through the existing UI, but does not change source. Per-operation option projections prevent unrelated settings from invalidating every output. For example, `warningsAsErrors` affects compile/preview/Truth; `expandMacros` affects preview; a source image affects session/Truth; changing the display title affects neither compile nor analysis.

The tracker may compare entire source arrays at these mutation boundaries; it must not repeatedly serialize source on status polling. Cursor pagination and immutable read snapshots are computed from an already captured model view. `observationRevision` is advanced by controller events, never by reading.

### Schedule, capture, execute, publish

1. **Schedule:** create a queued operation with immutable inputs when an existing UI path requests work. Replacing pending work terminalizes its record as superseded, clears its scheduled callback, and allocates the replacement ID. Preserve the current 120 ms analyze and 350 ms build debounces and the per-Stage sequence claimed at fire time.
2. **Capture:** the request and backing file bodies/options are already fixed before the first `await`, including compiler initialization. Bind callback IDs to that snapshot. No later `activeRequest()`, current settings lookup, or current image-map read may silently change the request associated with the captured revision.
3. **Execute:** transition the named record to running and call the existing shared client. Pending analysis deduplication may share physical work for identical request bytes, but every subscriber retains its own operation/target identity. All await paths have catch/finalization handling. A UI flush replaces or starts scheduled records through the same coordinator; the read/wait tools never flush them.
4. **Publish:** check target epoch, input equality, request ordering, and record ownership after every await. A superseded reply is discarded; an obsolete reply cannot clear a newer busy flag or error. A valid reply updates its specific output provenance and the corresponding UI projection together.
5. **Finalize:** every path leaves a terminal record or an explicitly still-running physical request. A fresh-analysis skip ends compile as diagnostics. Refusals, malformed result JSON, missing compile bytes, failed required metadata, worker exceptions, and session load errors end the appropriate records. `finally` only releases the work it owns; it does not blindly set shared booleans false.

On input change, mark in-flight affected operations superseded immediately, even before a new debounce fires. Physical worker work can finish later and is ignored. Keep transport pending-call accounting separate from logical operation state so a superseded request is not reported as cancelled CPU work. Unrelated output families retain their records when their inputs are unchanged.

Compile metadata must come from the exact request (reuse a matching analysis result or request one). The source-file ID map and root declaration shapes travel with the artifact. If required metadata cannot be obtained, do not adopt a runtime with guessed mapping; retain the last-good artifact and return a failed build outcome. Full-file metadata availability is explicit rather than inferred from the latest displayed analysis.

### Identical bytes, source changes, and runtime configuration

- Every successful compile has a new operation ID and records the source/options actually validated. FNV/hash comparison may be a fast prefilter, but byte-for-byte equality plus compatible source-file mapping is required to retain an artifact ID. A forced equal-hash/different-byte test must replace the artifact.
- If bytes and mapping match, advance the artifact's validation provenance without replacing a compatible live runtime, preserving its pin/RAM state. The session's artifact binding remains truthful; fresh validation does not mean reset or a new simulation run occurred.
- If bytes match but file-ID/source ownership mapping differs, allocate a replacement artifact identity and rebuild its runtime configuration. Root-memory declarations and imported-file IDs come from that artifact's captured analysis, never `currentRoms()` against newer source.
- Capture image maps by value. `importedImagesFor()` currently can retain mutable per-file Map references; its replacement receives the operation's image snapshot and source-file mapping explicitly.
- Source images are a runtime input, not compiled bytes. If images change while a source-compatible compile is running, that compile can still validate its source; preparing the live session separately captures the latest eligible images, validates them against that artifact's shape, and records the actual image revision applied. Never restore old image text merely because an older compile finished.
- When source and artifact differ, last-good session state retains its own mapping and applied-image provenance. A current-source image edit cannot be labeled applied to that session without validation against its compiled declaration shape. Reuse the existing application path and expose preload failure/partial application explicitly; do not declare all images applied based solely on a successful compile.

### Session lifecycle observation

Add a small **separate** lifecycle subscription to `SimSession`; do not overload the existing console-facing `SessionEvent` union with begin/failure bookkeeping. Existing `drive`, `memory`, `rebuilt`, and `destroyed` event payloads and transcript spelling stay stable.

```ts
export type SessionLifecycleEvent =
  | { kind: 'reset-started' }
  | { kind: 'reset-finished'; preloads: ApplyResult }
  | { kind: 'reset-failed'; message: string }
  | { kind: 'run-finished' };
```

`ApplyResult` is the existing internal preload result type; convert it to a bounded public summary rather than returning its Map values directly. Provide subscription removal; observer failures must not prevent runtime cleanup or the existing face events. The coordinator listens to lifecycle events plus existing drive/memory/rebuilt/destroyed events, counting a reset completion once even though both event channels observe it. Initial build exposes its preload result to its caller so `preloadState` can be truthful from first publication.

- Existing session creation paths produce `session_build` records before awaiting runtime/module loading. Simultaneous Live/Data requests share the pending physical build and its operation ID for the same complete inputs. Different image/configuration stamps must not share merely because bytes are identical.
- Reset-started records one `session_reset` operation, marks the binding resetting, and invalidates its formerly ready public session ID. Repeated calls joining the same pending reset share that operation. On success, mint a new ID, record preload outcome, and retain the protocol's floating-pin semantics. On failure, if the old runtime remains alive, publish it under a new ready ID with the reset failure preserved in the operation record; otherwise report failed/absent session state.
- After an awaited load, check the session is still alive and belongs to that reset/build generation. If destroyed or superseded, destroy the newly loaded runtime instead of swapping it in or emitting a resurrected `rebuilt` event. A superseded logical record remains superseded even if the physical load succeeds.
- Session drive/memory events and run completion advance `liveStateRevision`; reset/build publication establishes a new one. Preload reapplication records its actual result and advances state when any writes occurred, including partially successful application. A failure-only application updates status/observation without claiming the requested images were installed.
- No pin/memory/reset tools are added in this phase. Existing UI/console operations supply the events. Runtime mutation serialization and richer behavioral verification remain Phase 4 work.

### Compiler failures and honest waiting

Add a client failure subscription/transport-state accessor with no eager worker creation. Fatal worker `error`/message decoding failures reject outstanding client promises once and notify the controller, which finalizes affected running/queued operations. New requests against a known failed worker reject immediately with a transport error. Preserve the last published artifact, flag its freshness correctly, and report the transport failure separately from source diagnostics. Do not silently dispose and respawn the shared compiler client; reload is the documented recovery for this phase.

Every `runAnalyze`, `runBuild`, preview/Truth continuation, session preparation, and reset observer must finalize its logical record even when `ensureReady()` returns false or a promise rejects. Pending analysis deduplication entries clear on both outcomes. Compiler failure must not erase a newer source revision or another operation family's established failure.

`circ_wait_for_operation` is an event subscription over a retained record:

1. Validate page lifecycle, ID, timeout, and waiter limit. Return an already-terminal record immediately, without consuming a waiter slot.
2. Subscribe and re-check atomically so completion between lookup and subscription cannot be missed. A zero timeout performs one observation and returns terminal or timed_out immediately.
3. On terminalization, deadline, abort, page suspension, or disposal, resolve exactly once and remove its timer/listener. Waiting never starts/restarts an operation, updates source, wakes the worker, or follows a replacement ID automatically.
4. A timeout leaves a running operation running. A native cancellation signal, when the verified provider supplies one, cancels only this wait and yields `WAIT_CANCELLED` if the provider still delivers a result. The page facade keeps its Phase 0 two-argument public shape; external callers use bounded timeout and may wait again.
5. Phase 0 suspension resolves pending waits with `PAGE_SUSPENDED`; disposal resolves them with `PAGE_DISPOSED`. On a restored cached document the IDs/records remain page-scoped, but callers establish new waits. On a full reload they must rediscover and obtain new IDs.

No worker abort or main-thread preemption is claimed. A stalled synchronous worker can leave a logical operation running until a real transport failure arrives; a bounded wait returns timed_out with that fact. A long synchronous scratch Truth computation can delay main-thread timeout delivery until JavaScript yields; record this limitation and retain the existing computation cap. Adding chunking or worker termination is outside this phase.

## Persistence & I/O

This phase adds no persisted schema or storage key. Revisions, read cursors, operation summaries, output stamps, and waiter subscriptions live for the page installation established in Phase 0. Bootstrap derives initial project revisions from the source that actually becomes readable. A full reload creates new IDs and an empty operation history; existing scratch content/settings/images restore through the version-2 envelope. A bfcache restoration retains controller state while restoring tool registration according to Phase 0.

`circ_list_projects`, `circ_read_project`, and `circ_read_file` read in-memory application/catalogue data only. They do not re-read localStorage, switch projects, select a file, fetch documentation, initialize WASM, create a runtime, invoke a compiler operation, or flush saves. A request for an unknown project/file returns a specific error. Reading an inactive project does not analyze it; missing diagnostics are never interpreted as a clean compile.

The existing UI continues to drive the shared compiler worker and runtime. Snapshotting changes the ownership of request data, not the compiler's JSON API or its overlay path rules. Only per-operation documented settings are projected. In particular, the compile path must actually send its captured `warnings_as_errors` option; the current baseline's `runBuild` constructs an optionless request despite the existing projection helper. Cover that correction as part of making compile-input provenance truthful.

Public response payloads cross the same native/external connection as Phase 0, now including source when explicitly requested. Documentation names this new capability and the revision/chunking contract. No source upload service, backend, network reference lookup, or custom bridge is added.

Operation retention stores summaries, not source history. Bound terminal records and release snapshots once asynchronous consumers and current output metadata no longer need them. Source bodies retained for the displayed last-good artifact must be limited to that artifact's required context; do not grow a history of every keystroke. Cursor tokens bind current contents and reject revision changes rather than retaining historical projects solely for pagination.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Establish revision and operation primitives | Pure revision classification, immutable input stamps, operation transitions, bounded retention, and wait subscriptions with the DTOs/errors this phase uses. | Change-classification, no-op/undo, terminal immutability, queued replacement, retention, deadline, and no-lost-wakeup tests pass. |
| 2 | Publish project and file reads | Wire revisions to project/file/metadata/image mutation boundaries and add the three read tools with active-buffer precedence, paging, and bounded source chunks. | Public reads match an oversize/unsaved active buffer, read inactive projects without selection, and reject changed-revision cursors/chunks; normal UI editing still works. |
| 3 | Track analyze and compile accurately | Capture source/options before awaits, create records at schedule time, finalize every worker path, bind diagnostic/artifact provenance, and wire fatal client errors. | Delayed-handshake/reply, analysis/compile ordering, warnings-as-errors, skipped compile, worker failure, and last-good-output cases pass through the actual island pipeline. |
| 4 | Track derived outputs and live sessions | Give preview/Truth independent request identity, snapshot runtime/image inputs, track shared session builds/reset/run/preloads, and handle byte-identical artifact reuse plus lifecycle races. | Late preview/Truth, changed fixed pins/images, identical bytes versus mapping, same-shaped rebuild, and reset-after-destroy tests pass with preserved transcript behavior. |
| 5 | Expose tracked status and operation waiting | Complete the tracked status projection and register `circ_wait_for_operation`, integrate native cancellation/page lifecycle, and replace the temporary untracked status description. | Agent-visible superseded/terminal/timeout outcomes and authoritative per-output freshness agree across adapters; reads/waits cause no new work. |
| 6 | Verify integrated observation workflows | Complete ChatGPT-first and external-client read/wait walkthroughs, regression checks, usage/decision documentation, and measured bundle/retention results. | Real-agent project/file reads, human edit during a wait, failed compile with last-good display, entry switch, reload, and all affected site gates pass with recorded evidence. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own. Phase 0's observational fields remain available while tracking is connected incrementally; do not switch `provenance.tracking` to tracked in a partial integration that still guesses one of the advertised output/session identities. New read tools can return accurate project revisions before full output provenance is published.

## Tests

Test names are required assertions/scenarios, not claims that they already exist. Use deferred promises and injected timers/clocks for concurrency tests. Existing real-WASM and transcript fixtures remain the oracle for compiler/runtime behavior.

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `source_revision_tracks_only_named_source` | `playground-revisions.test.ts` | Body/name/order/insert/delete bump source; settings, image edits, entry selection, and project rename do not. |
| `project_revision_covers_metadata_and_images` | `playground-revisions.test.ts` | Broad revision detects name/source/image edits without confusing them with source-only changes. |
| `noop_and_undo_have_distinct_rules` | `playground-revisions.test.ts` | A no-op keeps IDs; edit then undo creates a new revision rather than resurrecting an old one. |
| `target_epoch_prevents_switch_back_aba` | `playground-revisions.test.ts` | Switching away and back to the same file/source cannot make an old target's pending reply current. |
| `options_revision_is_per_operation` | `playground-revisions.test.ts` | Preview expansion, warnings-as-errors, Truth cap, and source-image changes invalidate only dependent operations. |
| `snapshot_detaches_files_options_and_image_maps` | `playground-revisions.test.ts` | Later mutations of files, settings, nested Maps, or fixed-pin data cannot alter a captured request. |
| `equal_hash_is_not_equal_artifact` | `playground-revisions.test.ts` | Forced hash collisions with different bytes replace the artifact; equal bytes and compatible mapping permit reuse. |
| `equal_bytes_new_source_advances_validation` | `playground-revisions.test.ts` | A new successful source revision updates artifact provenance without inventing a runtime reset. |
| `queued_replacement_is_terminal` | `playground-operations.test.ts` | Replacing a debounce job marks the old ID superseded before the replacement timer fires. |
| `terminal_operation_cannot_be_rewritten` | `playground-operations.test.ts` | A late success/failure cannot rewrite a superseded or otherwise terminal record. |
| `physical_work_and_logical_supersession_differ` | `playground-operations.test.ts` | Supersession does not claim that the shared worker was aborted; late physical completion is discarded. |
| `wait_has_no_lost_completion_window` | `playground-operations.test.ts` | Completion between initial lookup and listener setup is observed exactly once. |
| `wait_timeout_leaves_work_running` | `playground-operations.test.ts` | Deadline returns timed_out, removes the waiter, and does not change operation state or schedule work. |
| `wait_lifecycle_and_abort_release_resources` | `playground-operations.test.ts` | Abort, suspension, disposal, and completion clear timers/listeners and obey single-settlement semantics. |
| `retention_is_bounded_and_expiry_is_explicit` | `playground-operations.test.ts` | Terminal history stays within the configured unpinned cap, current slots keep needed summaries, and evicted IDs return expired rather than fabricated results. |
| `wait_limits_do_not_reject_terminal_reads` | `playground-operations.test.ts` | Saturated waiters reject new outstanding waits but allow immediate terminal observations. |
| `read_active_buffer_before_scratch_record` | `playground-reads.test.ts` | Active unsaved/oversize text is read exactly even when the scratch record contains an older source. |
| `inactive_read_preserves_selection` | `playground-reads.test.ts` | Inactive catalogue/scratch reads call no activation, compile, session, storage, or tree-changing path. |
| `project_paging_is_revision_bound` | `playground-reads.test.ts` | Stable contents page once in deterministic order; a changed workspace/project rejects stale cursors with current revision details. |
| `file_chunks_round_trip_unicode_and_newlines` | `playground-reads.test.ts` | Combining revision-matched chunks reproduces exact source, including surrogate pairs, escaped characters, CRLF, and empty/EOF cases. |
| `file_chunk_requires_revision_after_first` | `playground-reads.test.ts` | Nonzero-offset reads require an expected source revision and never combine content from two revisions. |
| `read_payloads_fit_serialized_budget` | `playground-reads.test.ts` | Count-limited metadata also honors byte limits; escaped near-cap source remains readable in progressing chunks. |
| `transport_failure_rejects_pending_and_future_calls` | `shared-client.test.ts` | A fatal worker error rejects pending requests once, notifies subscribers, and prevents sends into the failed worker without spawning a replacement. |
| `reset_after_destroy_drops_loaded_runtime` | `sim-session.test.ts` | A late reset load after destruction is destroyed rather than adopted, with no resurrected rebuilt event. |
| `reset_observation_preserves_protocol_events` | `sim-session.test.ts` | Separate lifecycle notifications report begin/success/failure while existing console-facing events and floating-pin reset semantics stay intact. |
| `preload_partial_success_is_reported` | `sim-session.test.ts` | A mixture of valid/invalid preloads reports partial status and actual writes rather than all-applied success. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `public_project_reads_do_not_activate` | Built island/public tool registry | Reading another project/file leaves active entry, source editor, canvas session, console, and worker-call count unchanged. |
| `public_reads_follow_current_buffer` | Built island | After editing beyond persistence capacity, the source tool returns the exact live buffer and matching revision; inactive source origin is correctly labeled. |
| `edit_during_handshake_keeps_request_snapshot` | Pipeline integration with deferred client | The request after compiler readiness still contains the files/options stamped before the await; it cannot claim one revision while compiling another. |
| `old_reply_before_new_debounce_stays_stale` | Built island with controlled worker replies | A body edit immediately makes old work superseded and the last published artifact stale; a late pre-debounce success cannot mark it current. |
| `entry_switch_clears_unrelated_outputs` | Built island | Switching files/projects clears old target outputs and makes their pending IDs terminal superseded, including switching back to the same entry. |
| `analysis_and_compile_keep_their_own_diagnostics` | Real libcirc plus controlled completion order | Each producer maps its own file IDs/counts and source revision; a late producer cannot overwrite newer diagnostic provenance. |
| `warning_promotion_matches_captured_compile_options` | Real libcirc/build pipeline | Captured warnings-as-errors reaches the compile request, produces diagnostics, and never publishes a fresh successful artifact for the refused request. |
| `skipped_compile_resolves_waiters` | Pipeline integration | A fresh analysis error prevents the physical compile but terminalizes the logical compile as diagnostics, releasing waiters. |
| `failed_build_retains_identified_last_good` | Real compiler and public status | Invalid source reports current diagnostics and the previous artifact's older provenance while preserving the visible last-good circuit. |
| `identical_bytes_revalidate_without_reset` | Real runtime plus controlled compile metadata | A comment-only/source-equivalent compile advances source validation and keeps compatible live RAM/pin state; different file-ID mapping forces replacement. |
| `derived_output_requests_have_independent_identity` | Preview/Truth integration | Same build sequence with changed preview settings, fixed pins, or source images cannot accept a late table/preview as current. |
| `session_build_uses_artifact_owned_metadata` | Multi-file real artifact | Root declarations and imported source-image ownership come from that artifact's exact compile mapping, including while current analysis describes edited source. |
| `image_change_during_build_is_not_overwritten` | Multi-file ROM integration | New image text survives an older compile completion; session status reports the image revision actually validated/applied. |
| `session_reset_and_replacement_invalidate_identity` | Real session plus deferred reset load | Ready session IDs change across reset/replacement; dropping a session mid-reset cannot reattach the late runtime or mislabel the new session. |
| `worker_failure_finishes_all_affected_operations` | Built island/client failure injection | Running and queued affected work end explicitly, busy flags clear by ownership, waiters resolve, and last-good output plus source revisions survive. |
| `public_wait_timeout_does_not_compile` | Public registry and fake clock | Waiting times out on the named operation without flushing a debounce, starting another request, or changing project/session state. |
| `suspension_and_reload_end_old_waits` | Phase 0 lifecycle plus controller | Suspension/disposal releases outstanding waits; bfcache restoration retains records but full reload rejects old page IDs. |
| `agent_read_wait_and_human_edit` | Actual ChatGPT and Phase 0 external-client paths | Agent reads project/file metadata, waits on a current UI-scheduled operation, observes human-edit supersession, rereads the new revision, and accurately distinguishes current source from last-good output. |
| `existing_sim_transcripts_remain_identical` | `sim-transcripts.test.ts` and existing session tests | Lifecycle tracking does not add duplicate console lines, change drive ordering, or alter reset/preload behavior. |
| `tracked_observation_respects_bundle_budget` | Source graph/build bundle | New modules remain within the existing playground budget and do not add heavy code to light routes. |

Run command, from `site/`, for the focused pure tracking/read tests:

```sh
bun test test/playground-revisions.test.ts test/playground-operations.test.ts test/playground-reads.test.ts
```

Run command, from `site/`, for the affected controller/client/session and adapter tests:

```sh
bun test test/playground-controller.test.ts test/agent-tools.test.ts test/webmcp-adapter.test.ts test/pipeline.test.ts test/shared-client.test.ts test/sim-session.test.ts test/source-images.test.ts test/sim-transcripts.test.ts
```

Required site gate, from `site/`:

```sh
bun --bun run typecheck && bun --bun run build && bun test && bun run bundle
```

Use the Phase 0 verified client/browser/tool versions and setup to run the built-site real-agent scenarios. Stop the dev server before building; then `bun --bun run preview --host 127.0.0.1` serves the built site where the selected client can reach it. A static hosted origin, if required by the tested ChatGPT product, follows Phase 0's recorded arrangement. Record actual tool names/arguments/results, target version/commit, source/operation IDs, and pass/fail in the usage guide and STATUS. Do not substitute a seeded island test for actual ChatGPT/external-client acceptance.

## Open Questions / Spikes

- **TODO(phase1): Reconcile with implemented Phase 0.** This spec was drafted while Phase 0 existed only as a plan. At implementation cold start, read the accepted Phase 0 contract and native API findings, map the planned extensions to actual exports, and preserve its result/lifecycle semantics. If Phase 0 changed a public contract during compatibility work, review the consequential adjustment before implementing this phase.
- **TODO(phase1): Enumerate every current request/publication call site.** Before Slice 3, audit calls to `client.call`, `runAnalyze`, `runBuild`, `runPreview`, `runTruth`, `ensureSession`, and `reset`, including view/settings handlers and copy actions. Assign each owned operation or explicitly document a stateless export call whose bytes are returned directly and not published. No async publisher may remain attached only to the old build sequence while claiming tracked freshness.
- **TODO(phase1): Confirm source-image application outcomes at actual session boundaries.** `SimSession.build` currently ignores the return value of its initial preload application. Slice 4 must expose that result, verify source-owned imported image mapping against real fixtures, and ensure partially applied preloads cannot become `matchesCurrentImages: true` for the requested complete configuration.
- **TODO(phase1): Record wait responsiveness on the existing scratch Truth path.** The synchronous main-thread loop cannot honor a JavaScript deadline while executing. Exercise a bounded representative case and document observed wait latency; no claim of hard preemption or unmeasured responsiveness at the maximum cap is permitted. Any proposal to change computation limits or introduce chunking is brought to the human as separate scope.
- Project/read scope, revision semantics, operation waiting behavior, limits, in-memory ownership, tests, and the read-only boundary are fixed above. There are no further product decisions required to draft this phase; the TODOs are implementation verification tasks tied to prior-phase outcomes and real code paths.
