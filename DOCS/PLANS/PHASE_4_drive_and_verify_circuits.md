# Phase 4 — Drive and verify circuits

> **Dependencies:** Phases 0, 1, 2, and 3 implemented and accepted before this phase's implementation begins. Reuse their shared registry, public result envelope, revision/operation coordinator, artifact/session identities, atomic workspace mutation path, persistence receipts, and verified client access paths.
> **Warnings:** Read the macroplan, all prior phase specifications, `DOCS/sim-protocol.md`, `DOCS/wasm-api.md`, and `DOCS/decisions/{playground,playground-bench,agent-playground}.md`. The prior phase modules are specified but not implemented at this planning baseline; resolve their actual exports before writing code. Initial page boot drives root inputs low, while protocol reset leaves them undefined. Every assignment settles before the next. Root live memories are named only within the selected entry; imported runtime memories have no stable public live-mutation identity. Values and defined masks must never cross JSON as numbers.

## Goal

An agent can prepare the current compiled circuit's one visible simulation session, inspect and drive its named root pins, reset it, page through root ROM/RAM contents, mutate live root memory, and edit declaration-owned ROM preloads with the same observable canvas, Data, memory-panel, and console effects as human actions. Every live mutation checks the artifact, session, and live-state identities the caller observed, serializes against reset and human mutations, and returns lossless string values plus updated provenance. An agent can also run bounded independent vectors and stateful scenarios in disposable sessions built from an exact artifact and explicit initialization/image configuration, retrieve assertion-level results, and prove behavior without changing live pins, RAM, session identity, views, persistence, or console. Completion is demonstrated by a half-adder vector suite and a RAM clock/write/read/reset scenario through the real page and target agent paths.

## Scope

**In scope:**
- Register `circ_get_simulation`, `circ_prepare_simulation`, `circ_drive`, `circ_reset`, `circ_read_memory`, `circ_update_memory`, `circ_set_memory_preload`, `circ_run_verification`, and `circ_get_verification` through the existing shared registry.
- Observe an already-ready session without creating one, and explicitly start or join preparation of the current artifact's exact runtime/image configuration.
- List and read root pins and root ROM/RAM declarations in compiler declaration order, preserving value and defined-bit masks as canonical hexadecimal strings.
- Validate an entire ordered pin drive before changing runtime state, settle after every assignment, then return requested pin values from that same live session.
- Reset through the tracked Phase 1 session-reset operation, invalidating the old session identity at reset start and minting a new ready identity on completion.
- Page root live memory, and perform one explicit live `poke`, `clear`, or full-image `load` against ROM or RAM with protocol-compatible shape/error semantics.
- Set or clear a source-owned ROM preload by active project, file, and declaration; fork shipped catalogue content on its first effective mutation; persist and report the same storage outcomes as Phase 3.
- Apply a changed preload to every compatible instance in the current artifact when its captured source mapping is current enough to prove ownership, including independent imported copies; otherwise retain it for the next session and report that it was not applied live.
- Route corresponding canvas, Data, Truth-row, console, reset, memory-panel, and agent live mutations through one session coordinator or its external-drive observation boundary, with one exact console record per completed mutation.
- Run user-supplied vector cases and stateful scenarios in disposable sessions using an exact retained artifact, explicit floating/low initialization, current-or-no source preloads, and optional root ROM/RAM image overrides.
- Bound verification input, runtime work, retained results, response pages, and wall-clock execution; yield between bounded batches and report honest timeout/cancellation points.
- Unit, real-WASM, built-island, real-browser, and actual ChatGPT/OpenCode/Claude Code acceptance.

**Explicitly deferred:**
- Direct live read/write/load of nested imported memory instances. Their source declaration may own a ROM preload, and each flattened instance receives an independent copy, but live operations remain root-only as `SimSession` and `--sim` are today.
- Persisting live pin state, RAM contents, live ROM pokes, verification operations/results, session IDs, or revisions across reload.
- Simultaneous atomic pin assignment. Ordered drives retain `--sim` semantics: each assignment settles before the next.
- Waveforms, clocks as a special primitive, temporal assertions, HDL-style test languages, random/property generation, exhaustive truth enumeration, schematic/Truth result retrieval, and benchmarking. Clock behavior is expressed as ordered ordinary pin drives.
- Mutating the live session from verification, copying verification end state into Live, or writing verification actions to the visible console.
- Background worker execution, runtime preemption, renderer/runtime API changes, nested runtime-instance IDs, backend services, relays, custom browser bridges, filesystem access, or cross-tab synchronization.
- Source/share/WASM/memory/transcript export and general view/settings/highlight controls, which ship in Phase 5.
- Claiming that aborting a wait or reaching a deadline interrupted a synchronous WASM call already in progress.

## File & Module Topology

Paths are relative to the worktree root. Keep value parsing, verification planning, and result paging importable without Astro, DOM, CodeMirror, or the renderer's eager entry.

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| Simulation coordinator | `site/src/scripts/playground-simulation.ts` | Validate session preconditions, serialize live mutations and reset, coordinate explicit preparation, project session events into revisions/results, and request exact-once transcript records. |
| Verification runner | `site/src/scripts/playground-verification.ts` | Validate bounded suites, build disposable sessions, apply explicit initialization/images, execute ordered cases/steps, collect assertion results, yield/deadline-check, and retain bounded paged results. |
| Simulation tools | `site/src/scripts/agent-tools/simulation.ts` | Descriptors, strict validators, and handlers for simulation discovery/preparation, pin drive/reset, root memory reads/mutations, and source ROM preloads. |
| Verification tools | `site/src/scripts/agent-tools/verification.ts` | Descriptors, strict validators, and handlers for starting verification and retrieving result pages. |
| Simulation coordinator tests | `site/test/playground-simulation.test.ts` | Preconditions, queueing, reset races, event/revision accounting, root-only memory policy, and transcript-record tests. |
| Verification tests | `site/test/playground-verification.test.ts` | Validation, isolation, ordering, initialization, images, assertions, limits, timeout, cancellation, retention, and paging tests. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| Public contract | `site/src/scripts/playground-contract.ts` | Add simulation, memory, preload, verification DTOs, operation/result summaries, and error-code members while retaining prior envelopes. |
| Controller | `site/src/scripts/playground-controller.ts` | Expose simulation/preload/verification methods over injected session, workspace, store, transcript, and disposable-runtime ports. |
| Revisions | `site/src/scripts/playground-revisions.ts` | Enforce live-state/image transition rules and produce post-mutation preconditions without changing Phase 1 identity definitions. |
| Operations | `site/src/scripts/playground-operations.ts` | Add `verification` operation records, result ownership/retention links, and exact-input start/join/terminal behavior. |
| Registry | `site/src/scripts/agent-tools/registry.ts` | Register the nine descriptors and apply inherited input/result/lifecycle limits uniformly. |
| Simulation session | `site/src/scripts/sim-session.ts` | Add immutable preload outcomes, guarded mutation/reset generations, all-before-any validation helpers, and the narrow hooks the coordinator needs without changing protocol behavior. |
| Console model | `site/src/scripts/console.ts` | Add origin/correlation-aware transcript records for coordinator operations, including non-protocol image comments, while preserving transcript/script caps and existing spellings. |
| Source images | `site/src/utils/source-images.ts` | Resolve source declaration ownership and summarize imported-instance application without exposing runtime component IDs publicly. |
| ROM images | `site/src/utils/rom-image.ts` | Reuse strict image parsing/validation for public hex inputs and detached verification overrides; preserve existing raw-image rules. |
| Playground island | `site/src/components/Playground.astro` | Supply live/disposable runtime ports, route human and agent operations through shared coordination, render committed changes, and remove `consoleState.busy` as the source of cross-origin log suppression. |
| Existing tests | `site/test/{sim-session,sim-executor,sim-transcripts,console,source-images,memory-panel,data-view,truth-view,playground-controller,playground-revisions,playground-operations,agent-tools,webmcp-adapter,island-smoke}.test.ts` | Extend lifecycle, parity, isolation, UI reflection, imported preload, and adapter coverage. |
| Usage/decisions | `DOCS/agent-playground.md`, `DOCS/decisions/agent-playground.md`, `DOCS/sim-protocol.md` | Document live versus isolated behavior, value encoding, ordering, root-memory boundary, persistence, transcript records, limits, and real-agent evidence. |

`DOCS/STATUS.md` is appended by the implementation agent after each implemented slice under the macroplan. No compiler, renderer, WASM artifact, lockfile, or persistent schema change is planned.

**New dependencies:** None. Use the existing TypeScript/Bun tests, Phase 0–3 modules, `SimSession`, pinned renderer runtime, localStorage store, and committed compiler/runtime artifacts.

### Existing integration anchors

- `Playground.astro:929–1083`: transcript ownership and prompt execution; the current `busy` flag suppresses every session echo, including unrelated asynchronous callers.
- `Playground.astro:2254–2287`: source image contexts, imported-image mapping, root declarations, and compiler preload projection.
- `Playground.astro:2741–2962`: persisted ROM image edits, live RAM writes/clears, image application, and current UI status behavior.
- `Playground.astro:3661–3685`: Truth-row input drives already flow through the live session in declaration order.
- `Playground.astro:3795–3835`: disposable scratch-session precedent; current Truth enumeration is synchronous and is not the Phase 4 verification runner.
- `Playground.astro:4126–4229`: one-session build/drop/subscription path, artifact-byte guards, pin replay, face refresh, and console event spelling.
- `Playground.astro:4273–4282`: canvas mutates the runtime first and reports the completed external drive through `notifyExternal`.
- `Playground.astro:4458–4467`: Data reset clears remembered pins and awaits the shared session reset.
- `sim-session.ts:279–342`: protocol-compatible all-before-any `eval`, ordered settle, and named pin reads.
- `sim-session.ts:349–481`: preload/reset and root-memory operations, including current reset deduplication and raw-image validation.
- `console.ts:176–204`: existing event-to-command spelling; image application is a comment, not a fabricated browser file path.
- `source-images.ts:23–39`: flattened imported ROM preloads derive from innermost source file and runtime component ID, with independent writes.
- `memory-panel.ts:98–167`: existing 64-word UI paging rationale; public reads need an independent result-size bound.
- `sim-protocol.md:62–103`: command/error/settle semantics, especially floating reset and assignment ordering.

Line numbers refer to the planning baseline; locate symbols again before implementation.

## Data & State

### Limits and scalar encoding

```ts
export const MAX_SIM_ASSIGNMENTS = 64;
export const MAX_SIM_QUERIES = 128;
export const DEFAULT_MEMORY_READ_WORDS = 64;
export const MAX_MEMORY_READ_WORDS = 256;
export const MAX_SOURCE_PRELOADS_PER_CALL = 16;
export const MAX_VERIFICATION_CASES = 128;
export const MAX_VERIFICATION_STEPS = 512;
export const MAX_VERIFICATION_ACTIONS = 2048;
export const MAX_VERIFICATION_ASSERTIONS = 2048;
export const MAX_VERIFICATION_IMAGES = 16;
export const DEFAULT_VERIFICATION_TIMEOUT_MS = 5_000;
export const MAX_VERIFICATION_TIMEOUT_MS = 10_000;
export const VERIFICATION_YIELD_ACTIONS = 32;
export const DEFAULT_VERIFICATION_PAGE_LIMIT = 20;
export const MAX_VERIFICATION_PAGE_LIMIT = 100;
export const MAX_RETAINED_VERIFICATION_RESULTS = 16;
export const MAX_RETAINED_VERIFICATION_BYTES = 1024 * 1024;
export const MAX_VERIFICATION_RESULT_BYTES = 512 * 1024;
```

- Inherit Phase 3's 128 KiB serialized tool-input cap and Phase 0's 32 KiB serialized result cap. Apply both before dispatch/publication; no handler accepts an unbounded image, case list, query list, or result.
- Every pin value, memory address, memory value, and defined mask is a canonical lowercase `0x` hexadecimal string in results. Inputs accept canonical `0x` strings only; do not accept JSON numbers, signed values, separators, decimal strings, or implicit coercion. `0x0` is the sole zero spelling, and leading zeroes are normalized in output.
- Validate values/masks against declared widths before enqueueing a live mutation or allocating verification work. An omitted `defined` means the full width mask. Canonicalize value bits under undefined mask bits to zero in every result and comparison.
- Counts, widths, list limits, timeout milliseconds, and page limits remain finite safe JSON integers. Addresses still cross as strings because address/value DTOs use one lossless convention and must not acquire mixed numeric semantics.
- Full image input is normalized hex text accepted by the existing strict raw-image parser after comments/formatting are excluded from the public schema. Public image `hex` is an even-length lowercase byte string with no prefix; empty means clear. The decoded bytes must form whole words, fit capacity and width, and fit the inherited serialized input cap.
- Memory reads are one page of 1–256 words. `start` must resolve inside the memory; count clips at the end, matching `dumpMem`. A zero count is invalid publicly because it provides no useful page; callers stop when `nextStart` is null.

Append these errors to the inherited application union:

| Code | Meaning | Retryable with the same arguments/facade |
|------|---------|-----------------------------------------|
| `ARTIFACT_CONFLICT` | Expected current artifact ID/provenance no longer matches | No; reread status and prepare the current artifact |
| `SESSION_NOT_READY` | No ready live session exists for an operation that does not prepare one | Yes after `circ_prepare_simulation`/operation wait |
| `SESSION_CONFLICT` | Expected session ID changed, reset started, or the session was replaced/destroyed | No; reread simulation/status |
| `LIVE_STATE_CONFLICT` | Expected live-state revision changed before mutation commit | No; reread the live state and decide whether to retry |
| `IMAGE_CONFLICT` | Expected project image revision changed | No; reread project/simulation state |
| `SIMULATION_REFUSED` | `SimSession` rejected a named pin/memory/value/address operation | Depends on `details.simCode`; fix input or reread declarations |
| `SIMULATION_FAILED` | Runtime load/run/reset/memory transport failed unexpectedly | No with the same session; inspect status/rebuild/reload |
| `MEMORY_NOT_ROOT` | A source declaration exists but the requested live operation targets an imported/nested instance | No; use a source ROM preload or select that file as entry |
| `PRELOAD_CONFLICT` | File/declaration/kind/shape no longer matches the expected source target | No; reread the project/declarations |
| `VERIFICATION_INVALID` | Suite IDs, bounds, action ordering, values, images, or expectations are invalid | No; correct the suite |
| `VERIFICATION_NOT_READY` | The requested verification operation has not produced a retained result | Yes after waiting for its operation |
| `VERIFICATION_EXPIRED` | The operation is known but its unpinned result was evicted | No; rerun the suite if still applicable |
| `VERIFICATION_UNAVAILABLE` | The operation failed/superseded or its result exceeded retention limits | No; details identify the terminal reason |

`SIMULATION_REFUSED.details` contains the unchanged `SimError` code (`E_PROTO`, `E_NOPIN`, `E_NOTIN`, `E_WIDTH`, `E_BADVAL`, `E_NOSETTLE`, `E_NOMEM`, `E_IO`, `E_MEMFMT`, or `E_ADDR`) and bounded `arg`. Do not turn a protocol refusal into an internal exception or compiler diagnostic. Lifecycle, input-size, result-size, project/target/source/options conflict, persistence, operation, and internal errors remain inherited.

### Tool catalogue

| Tool | Read-only | Input summary | Success summary |
|------|-----------|---------------|-----------------|
| `circ_get_simulation` | Yes | Optional expected session/live revision | Observes current session binding, root declarations, and pin values without preparing a session |
| `circ_prepare_simulation` | No | Exact active target, artifact, and image preconditions | Starts, joins, or reuses the exact tracked session build and returns its operation ticket |
| `circ_drive` | No | Exact session/live revision, ordered assignments, optional queries | Validates all, drives/settles in order, logs once, and returns queried/current values with next revision |
| `circ_reset` | No | Exact session/artifact/live revision | Starts or joins tracked reset and returns the operation ticket; completion yields a new session identity |
| `circ_read_memory` | Yes | Exact ready session, root name, start/count | Returns a bounded root-memory page and observation provenance |
| `circ_update_memory` | No | Exact session/live revision and one live poke/clear/load action | Mutates one root ROM/RAM, settles, logs once, and returns next live revision |
| `circ_set_memory_preload` | No | Project/source/image preconditions, file/declaration, optional image | Persists/forks one source ROM preload and reports live application plus persistence truth |
| `circ_run_verification` | No | Exact artifact/target/images and bounded cases | Starts or joins an isolated tracked verification and returns its operation ID |
| `circ_get_verification` | Yes | Verification operation ID, cursor, limit | Returns bounded case/step/assertion results and complete provenance |

All tools remain discoverable after bootstrap. Descriptions distinguish observing from preparing, live from source-owned memory changes, and live simulation from isolated verification. `circ_get_status`, project reads, help, diagnostics, and operation waiting retain their earlier no-side-effect contracts.

### Live simulation DTOs

```ts
export interface SignalValue {
  value: string;
  defined: string;
  width: number;
}

export interface SimulationPin {
  name: string;
  kind: 'in' | 'out';
  width: number;
  state: SignalValue;
}

export interface RootMemory {
  name: string;
  kind: 'rom' | 'ram';
  width: number;
  addressWidth: number;
  words: number;
  liveAccess: 'root';
  sourceOwner: { projectId: string; file: string; declaration: string } | null;
}

export interface SimulationRef {
  target: TargetRef;
  artifactId: ArtifactId;
  sessionId: SessionId;
  liveStateRevision: Revision;
  imageRevision: Revision;
  initialization: 'page_boot_low' | 'reset_floating';
  preloadState: SessionStatus['preloadState'];
}

export interface SimulationSnapshot {
  observationRevision: Revision;
  status: SessionStatus;
  simulation: SimulationRef | null;
  pins: SimulationPin[];
  memories: RootMemory[];
}

export interface GetSimulationInput {
  expectedSessionId?: SessionId;
  expectedLiveStateRevision?: Revision;
}

export interface PrepareSimulationInput {
  projectId: string;
  expectedSourceRevision: Revision;
  expectedTargetEpoch: Revision;
  expectedArtifactId: ArtifactId;
  expectedImageRevision: Revision;
}

export interface SimulationOperationTicket {
  operationId: OperationId;
  kind: 'session_build' | 'session_reset';
  disposition: 'started' | 'joined' | 'already_current';
  inputs: WorkInputs;
  sessionId: SessionId | null;
}

export interface DriveInput {
  projectId: string;
  expectedTargetEpoch: Revision;
  expectedArtifactId: ArtifactId;
  expectedSessionId: SessionId;
  expectedLiveStateRevision: Revision;
  assignments: { pin: string; value: string; defined?: string }[];
  queries?: string[];
}

export interface DriveResult {
  simulation: SimulationRef;
  disposition: 'driven' | 'unchanged';
  assignments: { pin: string; state: SignalValue }[];
  values: SimulationPin[];
  consoleRecord: { recorded: true; lines: number };
}
```

- `circ_get_simulation` never calls `ensureSession`, initializes the renderer, drives pins, resets, flushes storage, opens a panel, or appends the console. With no ready session it returns the tracked status and empty pin/memory arrays rather than claiming the circuit has no declarations.
- Preparation is explicit. It accepts only the current active target and currently published artifact, captures artifact-owned file/declaration metadata and a by-value image snapshot before awaiting renderer load, and delegates to Phase 1's `session_build` operation. Exact queued/running work is joined; an already-ready exact binding is `already_current` and allocates no session or revision.
- A successful prepare produces the page's established low-boot state and handshake. It does not replay stale remembered pins from a superseded session; the implementation must reconcile Phase 1's captured-session rules with the old island map rather than letting an untracked map become initialization input.
- `circ_drive` accepts 0–64 assignments and 0–128 unique queries, with at least one of the two arrays nonempty. Duplicate assignment names are permitted and retain order because repeated edges can be meaningful; duplicate queries are invalid noise. Resolve every assignment and query against one ready session and validate all widths before the first write. Then perform every assignment through `SimSession.eval` semantics, one settle each, and read queries after the final settle.
- The live coordinator rechecks target, artifact, session, and live-state identities immediately before the first write. There is no rollback after a runtime write; this is why no asynchronous work occurs after the queue grants ownership and before validation/commit. A runtime throw after a partial drive is `SIMULATION_FAILED`, advances `liveStateRevision` conservatively, refreshes all faces, and reports `partial: true` in details rather than claiming atomicity.
- A drive whose assignments exactly equal current input states is still executed in order because an input transition history can matter to RAM. It is never classified as unchanged merely from final scalar equality. `unchanged` is reserved for an empty assignment list, which is allowed only when at least one query is present and causes no console record or live revision change.
- Return queried pins in query order. When queries are omitted, return every root output in declaration order. `assignments` reports canonical values actually supplied. Reads and results use the session's post-drive state and the newly allocated live revision.

### Reset and serialization

```ts
export interface ResetInput {
  projectId: string;
  expectedTargetEpoch: Revision;
  expectedArtifactId: ArtifactId;
  expectedSessionId: SessionId;
  expectedLiveStateRevision: Revision;
}
```

- One coordinator owns the active session mutation lane. Agent drive/reset/memory/preload application, console commands, Data edits, Truth-row drives, memory-panel live edits, and UI reset enter this lane. Synchronous canvas drives remain renderer-owned but must report through a guarded external-drive boundary; reset disables/gates canvas interaction so it cannot mutate the old runtime after reset starts.
- Do not queue a stale expected identity behind earlier work. Validate once on dispatch; if another mutation owns the lane, retain the request only while its exact expected session/live revision can still become current. Since every effective predecessor advances live state, a conflicting queued agent mutation normally returns `LIVE_STATE_CONFLICT` when it reaches the head. Internal UI sequences may carry the predecessor's returned revision explicitly.
- Reset checks all preconditions, allocates/joins the Phase 1 `session_reset` operation, marks the binding resetting, and invalidates the ready session ID before awaiting runtime load. Repeated exact reset requests while that same reset owns the old session join its operation; unrelated mutations fail `SESSION_CONFLICT` rather than touching the retiring runtime.
- Completion retains protocol semantics: the fresh runtime starts with all pins undefined, captured preloads are reapplied, remembered page pins are cleared, all faces rebuild/refresh, one `> reset`/`ok` record and one handshake are appended, and a new session/live-state identity is published. Failure follows Phase 1's old-runtime survival rule and never resurrects a destroyed/superseded generation.
- `run` remains an internal console verb. Its completion advances live state conservatively under Phase 1 because runtime observations may change, but this phase does not add a separate agent run tool: every public drive/memory mutation already settles.

### Root live memory

```ts
export interface ReadMemoryInput {
  expectedArtifactId: ArtifactId;
  expectedSessionId: SessionId;
  memory: string;
  start?: string;
  count?: number;
}

export interface MemoryCell {
  address: string;
  state: SignalValue;
}

export interface MemoryPage {
  simulation: SimulationRef;
  memory: RootMemory;
  start: string;
  cells: MemoryCell[];
  nextStart: string | null;
}

export type LiveMemoryAction =
  | { kind: 'poke'; address: string; value: string; defined?: string }
  | { kind: 'clear' }
  | { kind: 'load'; hex: string };

export interface UpdateMemoryInput {
  projectId: string;
  expectedTargetEpoch: Revision;
  expectedArtifactId: ArtifactId;
  expectedSessionId: SessionId;
  expectedLiveStateRevision: Revision;
  memory: string;
  action: LiveMemoryAction;
}

export interface UpdateMemoryResult {
  simulation: SimulationRef;
  memory: RootMemory;
  action: 'poke' | 'clear' | 'load';
  wordsLoaded: number | null;
  consoleRecord: { recorded: true; lines: number };
}
```

- Resolve live memory only through `SimSession.mems`, which contains root declarations in order. Never accept a runtime component ID, source path as a live address, bare imported declaration, or guessed nested instance. If metadata proves the name is imported rather than root, return `MEMORY_NOT_ROOT`; otherwise preserve `E_NOMEM` through `SIMULATION_REFUSED`.
- Reads are synchronous snapshots against a ready session. Validate the session before and after constructing the bounded page in the same JavaScript turn; reset cannot interleave. Return `nextStart` only when another address exists. Reading does not advance live state, record the console, open Memory, or change its UI page.
- `poke` and `clear` preserve `SimSession` semantics for either root ROM or RAM. `load` accepts a complete raw image for either kind, marks loaded words defined, leaves the remaining cells undefined, settles, and reports word count. These are explicitly live-only actions and are lost on reset/replacement/reload unless represented separately by a source preload.
- Successful `poke`, `clear`, and `load` each advance live state once and refresh canvas/Data/memory/Truth dependencies once. `poke`/`clear` use protocol echoes. A browser agent image has no filesystem path, so `load` records one truthful comment, `# <name>: live image from agent, <n> words`, rather than fabricating a `load <path>` command. Script extraction keeps it as a comment.
- Runtime errors after a validated single memory call conservatively advance live state if the runtime may have changed. Refusals returned before the runtime call are inert and add no transcript record.

### Source-owned ROM preloads

```ts
export interface SetMemoryPreloadInput {
  projectId: string;
  expectedSourceRevision: Revision;
  expectedImageRevision: Revision;
  expectedTargetEpoch: Revision;
  file: string;
  declaration: string;
  hex: string | null;
}

export interface PreloadApplicationSummary {
  state: 'not_running' | 'not_current' | 'applied' | 'partial' | 'failed';
  rootApplied: boolean;
  importedInstancesApplied: number;
  failedInstances: number;
  reportedFailures: { instance: string; message: string }[];
  omittedFailureCount: number;
  sessionId: SessionId | null;
  liveStateRevision: Revision | null;
}

export interface SetMemoryPreloadResult extends WorkspaceChangeResult {
  imageRevision: Revision;
  owner: { projectId: string; file: string; declaration: string };
  image: { present: boolean; hex: string | null; words: number | null };
  liveApplication: PreloadApplicationSummary;
}
```

- Resolve `file` in the active project's exact source revision and `declaration` against current exact analysis/artifact-owned metadata. It must be a ROM declaration with known width/address width. RAM has no persisted source image; initialize live RAM with `circ_update_memory` or an isolated verification image.
- `hex: null` removes the stored preload record. `hex: ''` is a present empty image that intentionally clears every instance on build/reset. Preserve that distinction in storage/results. A same normalized image or absent removal is unchanged and causes no fork, revision, session write, Truth request, or persistence flush.
- An effective catalogue change forks once through Phase 3's workspace commit boundary, copies all existing source images, applies the one owner change to the fork, and returns both identities. An effective scratch change advances project/image/workspace/observation revisions once; source revision and target epoch remain unchanged unless forking changes the active project identity.
- Validate the complete post-change source-image envelope and largest response before commit. Commit source ownership, revision tracking, UI image context, dependent Truth invalidation, and persistence once. Agent calls flush and return Phase 3's exact `saved`/`memory_only` receipt, including image-skipped notices; a visible application does not imply reload survival.
- Apply in place only when the ready session's artifact mapping can prove that the owner belongs to its captured source and the session is otherwise compatible. Root ownership writes the root memory; imported ownership writes every flattened instance independently. Do not expose component IDs: failure identities use bounded stable descriptive ordinals within this application result only, such as `file:declaration instance 2`, and are not accepted by later calls.
- Full successful application updates the session's image binding to the new image revision and advances live state once. Partial/failure advances live state if any write occurred, leaves `matchesCurrentImages: false`, and reports exact bounded counts. If there is no session or it represents stale source/mapping, save the preload without touching the runtime and return `not_running`/`not_current`; the next exact prepare/reset applies it.
- Console recording for an applied source preload is one comment naming `file:declaration`, root/imported instance counts, and words. It is a preload record, not a live `load` command. A persisted change not applied to the live session records no simulation line.

### Isolated verification suites

```ts
export interface VerificationImage {
  memory: string;
  hex: string;
}

export type VerificationAction =
  | { kind: 'drive'; pin: string; value: string; defined?: string }
  | { kind: 'poke'; memory: string; address: string; value: string; defined?: string }
  | { kind: 'clear'; memory: string }
  | { kind: 'load'; memory: string; hex: string }
  | { kind: 'reset' };

export type VerificationExpectation =
  | { kind: 'pin'; name: string; value: string; defined?: string }
  | { kind: 'memory'; name: string; address: string; value: string; defined?: string };

export interface VerificationStep {
  id: string;
  actions: VerificationAction[];
  expect: VerificationExpectation[];
}

export interface VerificationCase {
  id: string;
  initialization: 'floating' | 'low';
  sourcePreloads: 'current' | 'none';
  images?: VerificationImage[];
  steps: VerificationStep[];
}

export interface RunVerificationInput {
  projectId: string;
  expectedSourceRevision: Revision;
  expectedTargetEpoch: Revision;
  expectedArtifactId: ArtifactId;
  expectedImageRevision: Revision;
  timeoutMs?: number;
  stopOnFailure?: boolean;
  cases: VerificationCase[];
}

export interface VerificationTicket {
  operationId: OperationId;
  disposition: 'started' | 'joined' | 'already_complete';
  inputs: WorkInputs;
  caseCount: number;
  stepCount: number;
  assertionCount: number;
}

export interface GetVerificationInput {
  operationId: OperationId;
  cursor?: string;
  limit?: number;
}
```

- A suite has 1–128 cases, 1–512 total nonempty steps, at most 2,048 total actions, at most 2,048 total expectations, and at most 16 explicit images per case within the global input cap. Case IDs are unique; step IDs are unique within a case; IDs are well-formed nonempty UTF-16 strings of at most 80 code units without control characters.
- Preflight the complete suite against artifact-owned root pin/memory shape before creating an operation or runtime. Validate every name, kind, address, value, mask, image, duplicate explicit image target, and all aggregate limits. `drive` may target only root inputs. Expectations may read root inputs/outputs or root memories. Live nested access remains unavailable; current source-owned imported ROM preloads may still initialize the artifact internally.
- Each case receives a fresh disposable `SimSession` from the exact artifact, so cases are independent. `floating` uses `noInitialPinDrive` and leaves inputs undefined. `low` explicitly drives every root input to zero in declaration order and settles once after image setup, matching page boot without borrowing live pin state.
- `sourcePreloads: current` captures by value the exact expected image revision, applies root source ROM and imported source ROM images using artifact-owned mapping, and fails the case setup if any requested image cannot be applied. `none` supplies no source images. Explicit `images` then replace complete root ROM or RAM contents in array order and become that case's reset overrides. Their target names are root-only and may intentionally override a current root source ROM preload.
- Steps retain state within one case. Actions execute in array order; every drive/poke/clear/load settles before the next. `reset` rebuilds the disposable session to floating protocol state, reapplies the case's selected source preloads and explicit root images, and does not reapply low initialization. A low state after reset must be expressed by explicit drive actions, making RAM edges unambiguous.
- Expectations run after all actions in their step and compare exact canonical `(value & defined, defined, width)` tuples. Omitted expected `defined` means full width, not don't-care. Record every expectation unless `stopOnFailure` is true; in that mode stop after the first failed assertion and mark later steps/cases `not_run` without fabricating observations.
- Verification never calls `ensureSession`, reads live pins/RAM, mutates `sim.session`, advances live-state/session revisions, changes views/settings/source, writes storage, or appends console lines. It may reuse the renderer module promise/runtime constructor, but every disposable runtime is destroyed in `finally`, including validation-after-load failure, timeout, supersession, page disposal, and result-admission failure.
- Exact suite calls may join one queued/running operation or reuse its retained terminal result. Equality covers target/artifact/image inputs, normalized cases/actions/expectations, timeout, and stop policy. Source changes may leave a historical exact-artifact verification running, but current-target replacement supersedes its logical operation when its artifact is destroyed/unavailable; a late physical result cannot publish as current.

### Verification operation and results

Extend `OperationKind` with `'verification'`. The operation's `WorkInputs` bind the exact target, artifact ID, expected image revision when source preloads are used, and null live-state revision. Operation terminal state is `succeeded` whenever the runner publishes a coherent result, including failed assertions, a boundary-observed timeout, or cooperative cancellation; those distinctions live in `VerificationSummary.state` and partial counts. Assertion failures are behavioral results, not tool/runtime failures. Invalid suites allocate no operation. A setup/runtime failure before a coherent result uses `failed`, and supersession before publication uses `superseded`. Neither timeout nor cancellation claims that synchronous WASM already executing was preempted.

```ts
export interface VerificationAssertionResult {
  expectationIndex: number;
  expected: { kind: 'pin' | 'memory'; name: string; address: string | null; state: SignalValue };
  actual: { kind: 'pin' | 'memory'; name: string; address: string | null; state: SignalValue } | null;
  passed: boolean;
  error: { simCode: SimError; arg: string } | null;
}

export interface VerificationStepResult {
  caseId: string;
  stepId: string;
  state: 'passed' | 'failed' | 'error' | 'not_run';
  actionsCompleted: number;
  assertions: VerificationAssertionResult[];
}

export interface VerificationSummary {
  operationId: OperationId;
  state: 'passed' | 'failed' | 'error' | 'timed_out' | 'cancelled';
  cases: number;
  steps: number;
  assertions: number;
  passedAssertions: number;
  failedAssertions: number;
  notRunSteps: number;
  elapsedMs: number;
}

export interface VerificationPage {
  operationId: OperationId;
  resultId: string;
  observationRevision: Revision;
  inputs: WorkInputs;
  artifactValidation: OutputProvenance;
  imageRevision: Revision;
  summary: VerificationSummary;
  steps: VerificationStepResult[];
  nextCursor: string | null;
}
```

- `circ_run_verification` returns a ticket after validation/operation allocation, before renderer/runtime awaits. Callers use `circ_wait_for_operation`, then `circ_get_verification`. A direct tool-call timeout therefore stops waiting only; it does not misstate the operation.
- Execute on the main thread because `CircRuntime` and the existing renderer integration are browser-owned. After every 32 actions, or sooner when 8 ms of a batch has elapsed, await a zero-delay/macrotask yield, then check page lifecycle, logical operation ownership, abort signal, and monotonic deadline before continuing. A single synchronous runtime call cannot be interrupted; timeout is observed at the next boundary and reports elapsed/last completed case/step/action.
- Measure timeout using an injected monotonic clock (`performance.now` in the page), not epoch timestamps. `timeoutMs` defaults to 5,000 and ranges 1–10,000. Operation informational timestamps retain Phase 1's epoch clock.
- Retain flattened step results, summaries, and provenance in memory: at most 16 results, 1 MiB total, and 512 KiB per result. Pin only the current target's latest verification result and any result currently being paged; enforce the aggregate cap including pins. Evict oldest unpinned results first. Never retain source bodies, runtime instances, artifact byte copies, or input image byte copies solely for result retrieval.
- `circ_get_verification` preserves case/step/assertion order. Page limit is 1–100 step records, default 20, shortened as needed under the 32 KiB envelope. One step too large for an empty page returns `RESULT_TOO_LARGE`; do not truncate assertions or strings. Cursors bind result ID, operation ID, complete input stamp, and next step index. Expired/unavailable states preserve summary counts in the operation where possible.
- `actual: null` appears only when an expectation itself produced a named read refusal after earlier runtime actions; preflight normally prevents this. A runtime action error marks the step `error`, records actions completed, skips its expectations, and follows `stopOnFailure` for remaining work. Do not convert simulation errors into failed expected values.

## Execution & Concurrency Model

### Ownership

- The Phase 1 controller remains owner of target/artifact/session/live/image revisions and operation records. The island/store remain owners of source images, visible faces, and persistence. `SimSession` remains sole owner of each live runtime. The simulation coordinator owns only the active mutation lane and transcript correlation. The verification runner owns disposable sessions and bounded results.
- The live lane is a page-memory FIFO with at most one executing mutation. It is not a general task queue and stores no large snapshots. Public requests retain parsed scalar inputs and expected identities only until dispatch; source image changes capture a detached bounded map through the workspace transaction. Limit pending live mutations to 32; excess calls return inherited `BUSY`/bounded refusal rather than growing memory.
- Synchronous pin/memory writes do not yield while they own the lane. Reset and explicit preparation may await runtime loading; their generation/identity guards are rechecked after every await. Mark reset state before yielding so canvas/Data/memory/console callers cannot write the retiring runtime.
- Human UI actions use the same operation functions without stale public DTO ceremony, but they still capture the current identity on dispatch and surface conflicts/failures. UI controls disable while their conflicting operation owns the lane. Do not maintain a privileged second reset or memory path.
- Canvas interaction is the sole unavoidable write-first path because the renderer mutates before `onPinChange`. The coordinator supplies an external-drive token/gate before interactive mode is enabled, accepts the callback only for the currently bound session/runtime generation, allocates one live revision, refreshes faces, and records once. A callback from an old canvas is ignored for publication and triggers no transcript line.

### Exact-once transcript records

- Replace global `consoleState.busy` suppression with per-operation correlation. Every mutation receives an internal monotonically allocated record ID and origin (`console`, `canvas`, `data`, `truth`, `memory_panel`, `agent`, or `system`). Session events carry or are associated with that internal ID without exposing it publicly.
- The console prompt may echo immediately for responsiveness, but completion marks that exact record as already represented. Session event observation suppresses only the matching record, not unrelated agent/UI actions. Non-console origins derive their command/reply/comment after the mutation succeeds. Failed preflight calls produce no session event and no line; a typed console command retains its own typed echo/error reply.
- One drive assignment produces one `set`/`ok` pair, preserving ordered assignments. One poke/clear/reset produces its protocol pair. Live and source image application use the truthful comments defined above. Reset handshake follows its one reply. Verification produces no records. The existing 2,000-line transcript cap and script extraction remain unchanged.
- Listener exceptions cannot fail a completed runtime mutation. The coordinator records a bounded internal/transcript publication failure in status and still advances live state; it never reruns an action to reconstruct a missing line.

### Verification concurrency

- At most one verification operation executes at a time. A distinct validated suite queues behind it only while total queued verification count is at most four; a fifth returns `BUSY`. Exact calls join. Starting verification never blocks the live mutation lane.
- Each queued suite rechecks page/artifact availability before loading. It executes against its captured artifact and images, not current mutable state. Source/image changes after capture make the result historical but do not contaminate it; artifact/session replacement rules decide whether the operation remains executable or becomes superseded.
- Yielding allows human/live tool events to run, but disposable state is not shared and needs no mutex. Runtime construction and each synchronous action remain single-threaded. Cleanup always runs before the next suite begins.
- Page suspension/disposal prevents new work, aborts queued suites, requests cooperative stop for running suites, destroys the disposable session at the next boundary, and finalizes records. It does not destroy the visible session merely because verification ended.

## Persistence & I/O

This phase adds no localStorage key or schema field. Source ROM preloads continue under `localStorage['circ.playground.v1']`, schema version 2, keyed by project/file/declaration through the existing `sourceImages` envelope. Agent preload mutations use Phase 3's single workspace commit and exact persistence receipt. A successful write may still report `images_skipped`; in that case the current page keeps the preload in memory but reload recovery is not promised.

Live pin values, ROM/RAM mutations, session generations, mutation queues, transcript correlations, verification definitions/results/cursors, and disposable sessions are page-memory only. Reset/replacement drops live changes and reapplies only the captured source preloads. Reload creates new page/artifact/session/revision identities; saved source preloads restore, while live RAM and verification history do not.

The browser fetches only the existing same-origin static renderer/compiler assets during normal lazy preparation. Verification loads the already-published artifact bytes held by the page; it performs no compiler request unless the caller separately uses Phase 3 compile. This phase adds no filesystem, file picker, download, clipboard, remote API, analytics, backend, relay, WebSocket, or custom bridge I/O. Tool arguments/results travel only through Phase 0's documented native/external connection paths.

Raw image strings may contain user circuit data. Documentation must state that tool inputs/results are visible to the connected agent/client even though simulation executes locally. Do not describe local execution as preventing the agent from receiving those requested values.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Define simulation and verification primitives | Add public DTO/errors/limits, strict lossless scalar/image parsing, suite preflight, result paging/retention, and pure tests without public registration. | Canonical encoding, aggregate limits, root-only resolution, suite IDs/actions/expectations, cursor binding, and result-budget tests pass. |
| 2 | Serialize the visible simulation session | Add the live coordinator, explicit preparation, pin discovery/drive/reset tools, generation guards, live revisions, and correlation-based transcript recording; route corresponding human paths through it. | Ordered settle, stale conflicts, reset races, old-canvas callbacks, cross-origin concurrency, exact-once logs, and existing transcript goldens pass. |
| 3 | Expose root memory and source preloads | Add paged root reads, live poke/clear/load, source-owned ROM preload mutation/fork/persistence/application, and UI parity. | Root ROM/RAM operations, imported refusal, independent imported copies, partial application, persistence/reload, image omission, and console comments pass. |
| 4 | Run isolated behavioral verification | Add tracked queued disposable sessions, explicit initialization/images/reset behavior, cooperative yielding/deadlines, assertion collection, cleanup, and result retrieval. | Half-adder vectors, RAM edge scenario, isolation, timeout/cancellation, runtime failure, retention, and real-WASM cases pass. |
| 5 | Prove drive-and-verify workflows | Complete usage/decision/protocol documentation and run real-browser ChatGPT, OpenCode, and Claude Code workflows, including concurrent human action and native-unavailable fallback. | Recorded client calls plus all affected typecheck/build/test/bundle/browser gates pass with visible UI/console agreement and exact versions. |

Slices are ordered by dependency and individually reviewable. Slice 1 changes no public registry. Slice 2 may register only the simulation operations implemented in that slice; discovery text must not advertise memory/verification until their slices land. Every code slice includes built-island regression checks and updates exercised documentation rather than postponing all integration to Slice 5.

## Tests

Test names are required assertions/scenarios, not claims that they exist at planning time. Use deterministic ID/clock factories, deferred runtime loads, injected transcript/storage failures, stub runtimes for edge cases, and the committed real compiler/runtime artifacts where specified.

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `simulation_scalars_are_lossless_canonical_hex` | `playground-simulation.test.ts` | Inputs reject numbers/signs/noncanonical forms/overflow; outputs canonicalize value under mask for widths through 64 bits. |
| `simulation_observation_never_prepares` | `playground-controller.test.ts` | `circ_get_simulation` reports absent/building/ready accurately without renderer load, session build, drive, store write, view change, or console line. |
| `prepare_uses_exact_artifact_images_and_mapping` | `playground-simulation.test.ts` | Preparation captures artifact-owned metadata and by-value images, starts/joins/reuses Phase 1 session work, and cannot borrow later analysis/maps. |
| `drive_validates_all_before_any_write` | `playground-simulation.test.ts` | A bad later assignment/query leaves runtime, revisions, faces, and transcript untouched. |
| `drive_settles_assignments_in_order` | `playground-simulation.test.ts` | Duplicate/ordered assignments each settle, preserve clock edges, then queries observe the final state. |
| `live_mutations_require_exact_session_state` | `playground-simulation.test.ts` | Target/artifact/session/live-state changes reject stale drive/reset/memory calls before runtime access. |
| `live_lane_serializes_reset_and_human_actions` | `playground-simulation.test.ts` | Reset marks the session unavailable before awaiting; stale queued actions cannot mutate old/new runtimes and controls receive coherent completion. |
| `reset_generation_cannot_resurrect_or_replay_pins` | `sim-session.test.ts` | Late loads after destroy/replacement are destroyed; success floats pins, reapplies exact preloads, clears remembered pins, and publishes one new identity. |
| `old_canvas_callback_cannot_publish` | `playground-simulation.test.ts` | A callback from a replaced/disabled canvas does not advance revisions, refresh current faces, or append a transcript line. |
| `transcript_correlation_records_each_mutation_once` | `console.test.ts` | Concurrent console/agent/Data actions suppress only their own duplicate event, retain order, and produce exactly one command/reply or image comment. |
| `transcript_failure_never_replays_runtime_action` | `playground-simulation.test.ts` | A throwing recorder/listener leaves the mutation applied and identified but never invokes the runtime twice. |
| `memory_pages_are_root_only_and_bounded` | `playground-simulation.test.ts` | Root declarations page 1–256 cells with exact masks/next cursor; nested IDs/names and invalid ranges are refused without reads. |
| `live_memory_actions_preserve_protocol_semantics` | `sim-session.test.ts` | Poke/clear/load validate before mutation, settle once, update ROM or RAM, canonicalize values, and preserve `E_*` reasons. |
| `source_preload_changes_image_not_source_revision` | `playground-revisions.test.ts` | Effective preload edits advance project/image/workspace/observation once while source/target remain stable, except catalogue fork identity transition. |
| `source_preload_forks_and_persists_truthfully` | `playground-controller.test.ts` | First catalogue image edit forks once; scratch updates reuse Phase 3 receipts and report image omission/storage failure without false reload claims. |
| `imported_preload_applies_independent_instances` | `source-images.test.ts` | One file/declaration image reaches every matching flattened instance independently, reports bounded counts, and exposes no reusable runtime ID. |
| `partial_preload_never_matches_current_images` | `playground-simulation.test.ts` | Some successful writes advance live state, failures are bounded/reported, and session image freshness remains false. |
| `verification_preflight_is_total_and_inert` | `playground-verification.test.ts` | Invalid IDs/names/values/masks/images/limits reject before operation allocation, renderer load, live read, persistence, or console output. |
| `verification_cases_are_independent_steps_are_stateful` | `playground-verification.test.ts` | Each case receives a fresh runtime while ordered steps within one case preserve pin/RAM state. |
| `verification_initialization_and_reset_are_explicit` | `playground-verification.test.ts` | Floating versus low setup differs; reset floats inputs and reapplies selected source/explicit images without silently reapplying low. |
| `verification_expectations_compare_value_and_mask` | `playground-verification.test.ts` | Exact definedness participates in pass/fail, unknown value bits canonicalize, and omitted masks mean fully defined. |
| `verification_stop_policy_marks_not_run` | `playground-verification.test.ts` | Full mode records all assertions; stop-on-failure halts after the first failed assertion and truthfully marks remaining steps. |
| `verification_yields_and_times_out_honestly` | `playground-verification.test.ts` | Fake monotonic time proves periodic yields/deadline checks, last-completed location, and no claim that an in-progress synchronous call was aborted. |
| `verification_always_destroys_disposable_runtime` | `playground-verification.test.ts` | Success, assertion failure, action error, timeout, cancellation, supersession, oversize result, and page disposal each destroy once. |
| `verification_does_not_touch_live_state` | `playground-verification.test.ts` | Runner ports cannot access live mutation/session/transcript/store paths; live identities and values remain byte-for-byte snapshots. |
| `verification_results_are_bounded_and_revision_bound` | `playground-verification.test.ts` | Retention caps include pins, eviction is oldest-unpinned, pages preserve complete steps/order/provenance, and cursors cannot cross results. |
| `verification_operation_distinguishes_behavior_failure` | `playground-operations.test.ts` | Completed failed assertions produce a succeeded operation with failed behavioral summary; setup/runtime/timeout/supersession remain distinct. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `public_half_adder_drive_matches_all_vectors` | Built island plus real `libcirc.wasm`/runtime | Prepares the current artifact, drives all four ordered input vectors, reads sum/carry with exact masks, and shows matching Data/canvas state and one console record per assignment. |
| `public_ram_clock_write_read_reset_scenario` | Built island plus real runtime | Ordered low/high clock edges write/read RAM, live memory page and UI agree, reset floats pins/reapplies images/drops live write, and transcript has one ordered record per action. |
| `public_simulation_conflicts_with_human_drive` | Built island with controlled dispatch | A human drive between agent observation and mutation advances live state; stale agent input fails without overwriting human state or logging a phantom action. |
| `public_reset_replacement_race_is_safe` | Built island with deferred runtime loads | Project/artifact replacement during reset supersedes the operation, destroys late runtime, leaves the new session/UI intact, and emits no old-session handshake. |
| `public_console_agent_interleaving_is_exact_once` | Built island | A pending console reset and agent/Data actions retain valid ordering, no unrelated event is swallowed by prompt busy state, and no action is double logged. |
| `public_root_memory_policy_is_actionable` | Multi-file real artifact | Root memory reads/writes work; nested live access returns `MEMORY_NOT_ROOT`; selecting the declaring file as entry or setting its source preload provides the documented alternatives. |
| `public_imported_preload_persists_and_rebuilds` | Multi-file real artifact/store | Inactive imported-file ROM preload forks if needed, reaches repeated independent instances, survives successful reload, and is reapplied by exact reset/build. |
| `public_preload_storage_failure_is_honest` | Built/real browser storage failure | The in-memory image and compatible live application remain visible while receipt says memory-only/images-skipped and reload survival is not claimed. |
| `isolated_half_adder_verification` | Real artifact and verification tools | Four independent low/floating cases return all expected sum/carry assertions with exact target/artifact/image provenance and no live changes. |
| `isolated_ram_stateful_verification` | Real RAM artifact and verification tools | One case uses ordered clock/write/read/reset steps, verifies RAM/pin masks, and proves state retention within the case and reset semantics. |
| `isolated_verification_leaves_ui_and_console_identical` | Built island | Before/after snapshots of live session ID/revision/pins/RAM, view, Data, memory page, transcript, source, settings, and storage are identical. |
| `verification_timeout_keeps_page_responsive` | Real browser with maximum bounded synthetic suite | Scheduled UI input runs between verification batches; deadline stops at a boundary, returns partial counts, destroys scratch runtime, and leaves live tools responsive. |
| `simulation_tools_share_native_and_page_contracts` | Registry/native adapter | All nine tools expose identical schemas/results/errors through native WebMCP and page invocation, including 64-bit strings and result-size refusals. |
| `chatgpt_drive_and_verify` | Actual supported ChatGPT browser-integrated agent | Discovers tools, compiles/prepares a half adder, drives vectors, runs isolated verification, and reports exact visible/provenance results through native calls. |
| `opencode_drive_and_verify` | Actual OpenCode plus Phase 0 browser tooling | Performs half-adder and RAM workflows through the verified external route, including a human live-state conflict and reread/retry. |
| `claude_code_drive_and_verify` | Actual Claude Code plus Phase 0 browser tooling | Performs the same visible and isolated workflows and records exact tab/tool/version/result evidence. |
| `simulation_native_unavailable_fallback` | Real browser/external page registry | Simulation, memory, preload, and verification operations work through the public registry when native WebMCP is unavailable with matching results/UI. |
| `simulation_respects_bundle_boundaries` | Source graph and built bundle | Eager registry/controller code does not import renderer/CodeMirror/knowledge heavy entries; renderer and verification runtime remain lazy and route budgets pass. |

Run focused tests from `site/`:

```sh
bun test test/playground-simulation.test.ts test/playground-verification.test.ts test/playground-controller.test.ts test/playground-revisions.test.ts test/playground-operations.test.ts test/sim-session.test.ts test/sim-executor.test.ts test/sim-transcripts.test.ts test/console.test.ts test/source-images.test.ts test/memory-panel.test.ts test/data-view.test.ts test/truth-view.test.ts test/agent-tools.test.ts test/webmcp-adapter.test.ts
```

Run the required site gate after each implementation code slice, from `site/`, with no dev server running:

```sh
bun --bun run typecheck && bun --bun run build && bun test && bun run bundle
```

Run built-site real-browser acceptance after that build:

```sh
bun --bun run preview --host 127.0.0.1
```

Use the Phase 0 documented URL/origin and client setup. Record discovery, exact arguments/results, visible UI/console agreement, operation waits, artifact/session/image/live revisions, browser/client/connection-tool versions, tested commit, and pass/fail in `DOCS/agent-playground.md` and `DOCS/STATUS.md`. A direct controller call, `el.__playground`, mocked adapter, screenshot, DOM-scraped value, or isolated runner invoked outside the public registry is supporting evidence only. No Zig or renderer gate is required unless implementation discovers and justifies a concrete missing API; if it does, stop and follow `CLAUDE.md` and the macroplan rather than silently broadening this phase.

## Open Questions / Spikes

None — phase is fully specified. Implementation must resolve prior phases' actual exported symbol names after they land, but may not expand live access to imported runtime instances or weaken isolation, revision, ordering, persistence, and result-bound contracts above.
