# Phase 3 — Author, compile, and repair

> **Dependencies:** Phases 0, 1, and 2 implemented and accepted before this phase's implementation begins. Reuse their shared registry, public result envelope, revision/operation coordinator, read conventions, page lifecycle, and connection paths.
> **Warnings:** Read the macroplan, all prior phase specifications, `DOCS/analyze-api.md`, `DOCS/libcirc-api.md`, and `DOCS/decisions/{playground,playground-bench,libcirc}.md`. The prior phase modules are specified but not implemented at this planning baseline; resolve their actual exports before writing code. The active editor file is the compilation entry, while the last file remains only the default on first open/interchange. `EditorHandle.setDoc` suppresses `onChange`; an agent edit must explicitly update the model, persistence, revisions, and shared pipeline. Never reset the whole CodeMirror document registry for an ordinary edit. Compile status 1 carries its own file map, and compiler byte columns are not editor UTF-16 columns.

## Goal

An agent can create or visibly open a playground project, atomically edit/create/rename/delete its files against an expected source revision, select the visible compilation entry, set warnings-as-errors, request an explicit compile, wait for its exact operation, and page through structured diagnostics tied to the source and file map that produced them. The same application operations serve the UI, native WebMCP, and external browser tooling. Successful edits preserve surviving files' selections and per-file undo histories, fork shipped content before its first effective change, carry source-owned images through file identity changes, persist within the existing limits, and report storage failures or evictions without claiming lost data was saved. A human edit that wins a race makes the agent's stale mutation fail without partial changes, and a late compiler reply remains historical rather than overwriting current output.

## Scope

**In scope:**
- Register `circ_create_project`, `circ_open_project`, `circ_update_project`, `circ_select_entry`, `circ_set_compile_settings`, `circ_compile`, and `circ_get_diagnostics` through the existing shared registry.
- Create scratch projects from the existing starter or a validated ordered named-file array; open catalogue or scratch projects through the visible workspace path.
- Apply ordered batches of file body edits, creates, renames, and deletes as one revision-checked model commit with no partial mutation.
- Preserve file identity and CodeMirror state for surviving files, including hidden-file history, selection, diagnostics state, and one undo step per affected surviving file for one tool invocation.
- Keep the textarea fallback operational and ensure a later rich-editor mount receives the current model rather than the boot source.
- Fork an example or tour project only on its first effective mutation, return the new project identity, and copy/move/delete source-owned image records consistently.
- Select an entry file without reordering source, expose current compile-setting revision, and mutate only `warningsAsErrors` in this phase.
- Flush or reuse the existing analyze/build coordinator for explicit compilation, returning exact Phase 1 operation IDs rather than creating an agent-only compiler path.
- Retain and page structured diagnostics from analysis and status-1 compile producers, with exact operation/target provenance and both native byte ranges and file-local UTF-16 ranges when source is available.
- Extend store mutation receipts so agent calls can report saved, memory-only, disabled, image-skipped, and eviction outcomes accurately.
- Route the human actions corresponding to this phase's create/open/file edit/create/rename/delete/entry/warnings operations through the same commit boundary while retaining human-only confirmation, selection, focus, and announcement behavior.
- Unit, built-island, real-WASM, real-browser, and actual ChatGPT/OpenCode/Claude Code author-repair acceptance.

**Explicitly deferred:**
- Project rename, project duplication, project deletion, file reordering, arbitrary file upload, and source export as agent tools. Existing human UI behavior remains available and revision-tracked; the approved agent completion scope requires project create/open and file read/write/rename/delete.
- Automatically rewriting imports after a file rename. The result warns that imports still name the old file, matching the existing UI contract.
- Source-owned memory image mutation and live ROM/RAM operations, which ship in Phase 4. This phase only preserves existing image ownership during project/file changes.
- Pin driving, reset, isolated behavioral verification, schematic/Truth payload retrieval, broad view/settings control, share links, and exports, which ship in Phases 4–5.
- A new compiler worker, worker preemption, compiler restart, background autosave worker, backend, relay, custom bridge, filesystem workspace, or cross-tab synchronization.
- Persisted operation/diagnostic history, collaborative merge/OT/CRDT behavior, semantic source transformations, automatic repairs, or formatter support.
- Guaranteeing per-file undo in the one-textarea fallback. The fallback remains editable and mutation-correct as one combined native text document; per-file history acceptance uses the successfully loaded CodeMirror surface.

## File & Module Topology

Paths are relative to the worktree root. Keep mutation planning and diagnostic conversion importable without the Astro island or CodeMirror.

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| Mutation planner | `site/src/scripts/playground-mutations.ts` | Validate and apply ordered file operations to immutable snapshots, maintain ephemeral file identity, produce a reconciliation plan, enforce limits/marker round trips, and classify no-ops. |
| Diagnostics store | `site/src/scripts/playground-diagnostics.ts` | Convert exact-request diagnostic payloads to public locations, associate build/analyze producers, retain bounded sets, and provide revision-bound pages. |
| Authoring tools | `site/src/scripts/agent-tools/authoring.ts` | Descriptors, strict input validators, and handlers for project creation/opening, project updates, entry selection, and compile settings. |
| Compiler tools | `site/src/scripts/agent-tools/compiler.ts` | Descriptors, validators, and handlers for explicit compile tickets and diagnostic retrieval. |
| Mutation tests | `site/test/playground-mutations.test.ts` | Atomicity, ordered operation semantics, range validation, limits, identity reconciliation, and marker-conflict tests. |
| Diagnostics tests | `site/test/playground-diagnostics.test.ts` | Exact file-map conversion, related ranges, producer selection, paging, retention, and result-budget tests. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| Public contract | `site/src/scripts/playground-contract.ts` | Add authoring/build/diagnostic DTOs, compile-setting status, persistence receipts, and error-code members without changing prior envelope semantics. |
| Controller | `site/src/scripts/playground-controller.ts` | Add revision-checked mutation/open/entry/settings methods, explicit compile coordination, diagnostic reads, and injected workspace/store/compiler ports. |
| Revisions | `site/src/scripts/playground-revisions.ts` | Commit one source revision per effective batch/fork, expose current compile options revision, and classify entry/settings changes separately. |
| Operations | `site/src/scripts/playground-operations.ts` | Link paired explicit analyze/compile records to their diagnostic producer and reuse queued/running/current exact-input work. |
| Read model | `site/src/scripts/playground-reads.ts` | Publish new project/fork/eviction identities immediately and keep active-buffer reads coherent after atomic mutations. |
| Registry | `site/src/scripts/agent-tools/registry.ts` | Register the seven descriptors, enforce a bounded JSON-safe input size before dispatch, and preserve the inherited result bound/lifecycle rules. |
| Editor | `site/src/scripts/circ-editor.ts` | Add an indexed external document replacement transaction that works for visible and hidden documents without firing `onChange` or losing history. |
| File model | `site/src/scripts/file-tabs.ts` | Add only the pure reconciliation helpers required to apply a validated plan while preserving active-file identity; retain existing reducers and last-file default semantics. |
| Diagnostic mapping | `site/src/scripts/circ-diagnostics.ts` | Add reusable file-local byte-column-to-UTF-16 range conversion, including related locations, without changing existing UI mapping. |
| Store | `site/src/utils/playground-store.ts` | Return structured update/flush outcomes with evicted project identities and image-save status; retain one key, schema version 2, and current limits. |
| Settings binding | `site/src/scripts/settings-drawer.ts` | Call the shared compile-setting mutation path for warnings-as-errors while preserving existing controls and operation-specific projections. |
| Playground island | `site/src/components/Playground.astro` | Supply workspace/editor/store/compiler ports, route corresponding human/tool mutations through one commit core with origin-specific presentation, render every committed result, and remove duplicated persistence/scheduling branches. |
| Existing tests | `site/test/{playground-controller,playground-revisions,playground-operations,playground-reads,agent-tools,webmcp-adapter,file-tabs,playground-store,circ-diagnostics,editor-preferences,island-smoke}.test.ts` | Extend prior contracts for mutation parity, undo, persistence receipts, build reuse, diagnostic provenance, and adapter behavior. |
| Usage/decisions | `DOCS/agent-playground.md`, `DOCS/decisions/agent-playground.md` | Document author/compile/repair calls, concurrency preconditions, coordinates, limits, persistence truth, and real-agent evidence. |

`DOCS/STATUS.md` is appended by the implementation agent after each implemented slice under the macroplan. No compiler, renderer, WASM artifact, lockfile, or persistent schema change is planned.

**New dependencies:** None. Use existing TypeScript, Bun tests, CodeMirror packages, localStorage store, worker client, compiler WASM, and Phase 0–2 modules.

### Existing integration anchors

- `Playground.astro:1328–1356`: project loading currently replaces the complete editor registry, which remains correct only for an actual project switch.
- `Playground.astro:1377–1417`: first-edit example forking and image copying; the shared mutation path must return the fork identity instead of relying on a status sentence.
- `Playground.astro:1419–1468`: current project creation/import and source-cap behavior.
- `Playground.astro:1951–2021`: existing project duplicate/delete/rename UI stays human-facing but must continue notifying Phase 1 revisions.
- `Playground.astro:3103–3255`: visible entry/file create/rename/delete/reorder behavior and image-key movement. Structural changes currently schedule work separately from body persistence; consolidate commit ownership.
- `Playground.astro:3276–3315`: one schedule/flush path and immediate invalidation rules.
- `Playground.astro:3360–3377`: CodeMirror changes update model/persistence/scheduling; external transactions deliberately do not re-enter this callback.
- `Playground.astro:3483–3577`: current independent analyze/build producers, exact-request compile file-map handling, and last-good artifact policy.
- `Playground.astro:3860–3979`: current diagnostics use exact producer data for UI mapping but retain no public operation-bound page.
- `circ-editor.ts:398–507`: `setDoc` is visible-only; hidden external replacements need the same transaction/history semantics.
- `playground-store.ts:720–780`: scratch creation/edit limits and eviction, and `:416–475` for write/quotas; expose outcomes rather than duplicating these policies.
- `libcirc-api.md:62–78`: status 0 compile returns bytes and omits warnings; status 1 returns analysis-shaped diagnostics with its own `files[]`.

Line numbers refer to the planning baseline; locate symbols again before implementation.

## Data & State

### Limits and shared validation

```ts
export const MAX_AGENT_INPUT_BYTES = 128 * 1024;
export const MAX_PROJECT_FILES = 128;
export const MAX_PROJECT_NAME_CODE_UNITS = 120;
export const MAX_AGENT_FILE_NAME_CODE_UNITS = 256;
export const MAX_FILE_MUTATIONS = 64;
export const MAX_TEXT_EDITS = 256;
export const DEFAULT_DIAGNOSTIC_LIMIT = 20;
export const MAX_DIAGNOSTIC_LIMIT = 100;
export const MAX_RETAINED_DIAGNOSTIC_SETS = 32;
export const MAX_RETAINED_DIAGNOSTIC_BYTES = 2 * 1024 * 1024;
export const MAX_DIAGNOSTIC_SET_BYTES = 1024 * 1024;
export const MAX_PINNED_DIAGNOSTIC_SETS = 2;
```

- The registry validates that input is JSON-safe and at most 128 KiB UTF-8 in its serialized form before invoking a handler. This is independent of Phase 0's 32 KiB result bound. An oversized input returns `INPUT_TOO_LARGE`; it is never partially parsed or applied.
- Project source retains `MAX_SOURCE_BYTES = 32 * 1024` UTF-8 from the existing store. A successful agent create/update must end at or below it. If a human has an active over-limit in-memory buffer, an agent may replace it only with a final project at or below the limit; it cannot grow or preserve an unpersistable result.
- Every agent-provided string must be well-formed UTF-16; reject lone surrogates before UTF-8 measurement, compiler dispatch, persistence, or mutation. Project names are trimmed, nonempty, free of C0/C1 control characters, and at most 120 UTF-16 code units. The store's existing `uniqueName` numbers duplicate scratch names. Agent-created/renamed file names additionally have at most 256 UTF-16 code units, continue to use `isFileName`, and file arrays continue to use `joinConflicts` plus `joinFiles`/`splitFiles` round-trip equality. Existing restored names are not rewritten to this new authoring limit, but every mutating result containing one is preflighted for representability.
- Numeric inputs are finite safe integers with no coercion or clamping. Unknown object fields are invalid. Every discriminated mutation rejects fields belonging to another kind.
- A project at or below 128 files must remain in that range after every operation. A restored/human-created project already above the cap accepts only delete operations until repaired; every operation must decrease its count, and multiple calls may reduce it progressively. It cannot be edited, renamed, or extended while over the cap. The project is always nonempty.
- Before any non-read-only handler commits state or allocates/starts compiler operations, build the exact base success result plus the largest bounded persistence-receipt representation and serialize it through the inherited JSON-safe/result-size checker. If it cannot fit within 32 KiB, return `RESULT_TOO_LARGE` before changing the model, editor, store, revisions, operations, or focus. Persistence notices use bounded count/omission summaries, so a post-write outcome cannot turn an already committed mutation into a transport-level size error.

Append these errors to the inherited application union:

| Code | Meaning | Retryable with the same arguments/facade |
|------|---------|-----------------------------------------|
| `INPUT_TOO_LARGE` | Serialized JSON input exceeds the public registry limit | No; submit a smaller batch |
| `PROJECT_NOT_ACTIVE` | A source/entry/settings mutation names a project other than the visible active project | No; open it and reread revisions |
| `TARGET_CONFLICT` | Expected target epoch/project/entry no longer matches | No; read status and choose the current target |
| `OPTIONS_CONFLICT` | Expected compile-options revision no longer matches | No; read status and choose the current setting |
| `FILE_CONFLICT` | An ordered mutation references an invalid/duplicate/missing file or leaves an unrepresentable file array | No; details identify operation index/file/reason |
| `SOURCE_TOO_LARGE` | Created or final updated source exceeds 32 KiB UTF-8 | No; reduce source |
| `TOO_MANY_FILES` | A batch creates/exceeds 128 files, or performs a non-delete operation before repairing a legacy over-cap project | No; reduce the project with delete-only calls |
| `UNSAVED_CHANGES` | Opening/replacing a project would abandon an active over-limit buffer that has no matching in-memory scratch record | No; reduce/save that project first |
| `DIAGNOSTICS_NOT_READY` | The requested running/queued operation has not produced a diagnostic outcome | Yes after waiting for the operation |
| `DIAGNOSTICS_UNAVAILABLE` | The operation failed/refused without a diagnostic payload, or its diagnostic set exceeded the retention cap | No; details retain operation failure/count/size facts |
| `DIAGNOSTICS_EXPIRED` | The operation remains known but its unpinned diagnostic set was evicted | No; compile current source again if needed |

Use inherited `NOT_READY`, `PROJECT_NOT_FOUND`, `FILE_NOT_FOUND`, `REVISION_CONFLICT`, `INVALID_RANGE`, `OPERATION_NOT_FOUND`, `OPERATION_EXPIRED`, lifecycle, serialization, and internal errors. Mutation conflicts contain bounded JSON-safe details, including actual revision/target where disclosure is already allowed by read/status tools. Expected conflicts or an unrepresentable success throw no internal exceptions and produce no store write, editor transaction, focus change, schedule, operation, fork, or revision allocation.

### Tool catalogue

| Tool | Read-only | Input summary | Success summary |
|------|-----------|---------------|-----------------|
| `circ_create_project` | No | Optional name, optional complete ordered files, optional entry | Creates and visibly opens one scratch project |
| `circ_open_project` | No | Project ID, expected project revision, optional entry | Visibly opens an existing catalogue/scratch project |
| `circ_update_project` | No | Active project/source revision and ordered mutation batch | Atomically commits files, possibly forking shipped content |
| `circ_select_entry` | No | Active target/source preconditions and file name | Visibly selects that file as compilation entry without reordering |
| `circ_set_compile_settings` | No | Active target/options preconditions and warnings-as-errors | Updates the shared visible setting and schedules dependent work |
| `circ_compile` | No | Exact active source/target/options preconditions | Starts, joins, or reuses revision-bound analyze/compile operations |
| `circ_get_diagnostics` | Yes | Operation ID, optional expected source revision/cursor/limit | Returns one bounded exact-producer diagnostic page |

All seven remain discoverable after page bootstrap even when their state precondition is not met; handlers return actionable readiness/project errors. Avoid native unregister/register churn on every project change. Descriptions explicitly tell an agent to read status/projects first and use `circ_wait_for_operation` after `circ_compile`.

### Project creation and opening

```ts
export interface CreateProjectInput {
  expectedWorkspaceRevision: Revision;
  expectedActiveProjectId: string | null;
  expectedTargetEpoch: Revision | null;
  name?: string;
  files?: { name: string; body: string }[];
  entryFile?: string;
}

export interface OpenProjectInput {
  expectedWorkspaceRevision: Revision;
  expectedActiveProjectId: string | null;
  expectedTargetEpoch: Revision | null;
  projectId: string;
  expectedRevision: Revision;
  entryFile?: string;
}

export type PersistenceNotice =
  | {
      kind: 'evicted';
      cause: 'project_cap' | 'quota';
      count: number;
      reportedProjects: { id: string; name: string }[];
      omittedCount: number;
    }
  | { kind: 'images_skipped'; ownerCount: number }
  | { kind: 'disabled'; reason: 'quota' | 'unavailable' };

export type PersistenceReceipt =
  | { state: 'unchanged'; enabled: boolean; persistedActive: null; notices: [] }
  | {
      state: 'saved';
      enabled: true;
      persistedActive: {
        projectId: string;
        projectRevision: Revision;
        sourceRevision: Revision;
        sourceStored: 'inline' | 'catalogue';
      };
      notices: Exclude<PersistenceNotice, { kind: 'disabled' }>[];
    }
  | {
      state: 'memory_only';
      enabled: false;
      persistedActive: null;
      notices: [Extract<PersistenceNotice, { kind: 'disabled' }>, ...PersistenceNotice[]];
    };

export type AuthoringWarning = {
  kind: 'imports_not_rewritten';
  oldName: string;
  newName: string;
};

export interface WorkspaceChangeResult {
  disposition: 'created' | 'opened' | 'updated' | 'entry_selected' | 'settings_updated' | 'unchanged';
  workspaceRevision: Revision;
  project: ProjectSummary;
  target: TargetRef;
  compileSettings: CompileSettingsStatus;
  entryFile: string;
  forkedFromProjectId: string | null;
  previousProjectId: string | null;
  warnings: AuthoringWarning[];
  operationIds: { analyze: OperationId | null; compile: OperationId | null };
  persistence: PersistenceReceipt;
}
```

- Omitted `files` uses `NEW_PROJECT_SOURCE` and its `main.circ`. A supplied array is copied, must be nonempty and representable, and preserves its order. Omitted `entryFile` selects the last file; an explicit entry must name one supplied file. Duplicate-name numbering must itself fit the project-name limit; otherwise reject with guidance to choose a shorter name rather than truncating it.
- Create/open first check the workspace revision, active project ID, and active target epoch observed by the caller. This binds a visible project replacement to the page state the agent inspected, catches an intervening source/project/entry switch, and makes a retried successful create conflict instead of creating a duplicate. Null active/target values are accepted only when status actually has none.
- Creation allocates a collision-free scratch ID through the existing factory, protects both the previously active project and the new project while enforcing the 16-scratch cap, reports evicted projects, opens the result, replaces the editor registry once, updates the workspace, and starts the normal target-change pipeline. Try fresh random salts a bounded 16 times, then use a page-monotonic suffix; never overwrite or alias an existing ID.
- Opening resolves the exact current project snapshot and checks its broad expected revision before leaving the current project. It does not fork catalogue content. For another project, it selects the requested entry or the last-file default. Calling open for the already active project is unchanged only when `entryFile` is omitted or already selected; a different requested entry is invalid with guidance to use revision-checked `circ_select_entry`, so open cannot bypass the target-epoch precondition.
- Before create/open replaces the active registry, commit any current representable active scratch source into the in-memory envelope. If the visible buffer is over the source cap and differs from its in-memory scratch record, return `UNSAVED_CHANGES` and keep the page untouched. Persistence being disabled does not itself block a switch because the envelope still owns in-memory scratch records.
- Agent create/open flushes the resulting envelope synchronously through the store's existing writer so its response can report persistence. A failed/quota-disabled write does not undo a successful in-memory/visible operation; return `memory_only` with a required disabled notice and leave `persistence.enabled` false. `saved.persistedActive` binds the exact active project/source revisions represented by the accepted envelope and says whether source was inline scratch text or catalogue-by-ID, rather than merely saying a write was queued.
- `unchanged` is used only when the requested project and entry are already visible and no store/model fact changes. It allocates no revisions or compiler operations and does not flush merely to manufacture a saved result.
- Every workspace-change result returns `workspaceRevision`, the complete current `TargetRef`, and current compile settings so the next select/settings/compile call can use fresh preconditions without a mandatory status round trip. Rename operations add one typed `imports_not_rewritten` warning each; the warning appears in both native and page-registry results, not only the status line.

### Atomic file mutations

```ts
export interface TextEdit {
  from: number;
  to: number;
  text: string;
}

export type FileMutation =
  | { kind: 'edit'; name: string; edits: TextEdit[] }
  | { kind: 'create'; name: string; body?: string; before?: string | null }
  | { kind: 'rename'; name: string; newName: string }
  | { kind: 'delete'; name: string };

export interface UpdateProjectInput {
  projectId: string;
  expectedSourceRevision: Revision;
  expectedTargetEpoch: Revision;
  operations: FileMutation[];
}
```

`operations` contains 1–64 entries and executes against an immutable draft in array order. A later operation names the draft produced by earlier operations. The planner validates the entire sequence and final result before the controller changes live state.

Mutation rules:

1. **Edit:** `edits` contains 1–256 entries across the whole invocation. Every range is zero-based UTF-16 with an exclusive end, addresses the body as it exists at the start of that `edit` operation, and lies on Unicode scalar boundaries. Ranges are ordered by ascending `from`, do not overlap, and do not contain two zero-length insertions at the same offset. Apply them from the end so offsets do not drift. Empty replacement text is valid.
2. **Create:** the name must not exist in the current draft. Omitted `body` uses `seedBody(name)`. A string `before` inserts immediately before that currently existing file; explicit null appends; omission inserts before the current last file, matching the UI's root-preserving add. Creation does not silently select the file.
3. **Rename:** `name` must exist and `newName` must be legal and unused at that operation. The file's stable planning identity, body, editor state, active selection, and source-image ownership survive. Imports are text and are not rewritten. A rename followed by an edit uses the new name.
4. **Delete:** the name must exist. The draft may never become empty. Deleting the active entry selects the surviving file at the same index, clamped to the new last index, matching `deleteFile`; deleting another file retains the same active file identity. Delete owned image records for that project/file.
5. **Final validation:** enforce the normal file cap or the monotonic delete-only recovery rule, the source limit, and well-formed text; run `joinConflicts`, serialize with `joinFiles`, split again, and require exact ordered name/body equality. Report the first conflict in operation order plus all bounded final conflict details; never accept a lossy marker round trip.

The planner assigns internal symbols to initial and newly created files solely for reconciliation; they never cross the public boundary or persist. It returns final files/entry, identity-preserving renames, deletions, insertions, and the ordered text-edit batches for each surviving changed file. The editor composes those sequential batches into one granular transaction per file, preserving meaningful position mapping while producing one undo step for this tool invocation.

An effective no-op batch returns `disposition: 'unchanged'`: no source revision, fork, editor transaction, persistence write, pipeline schedule, or operation ID changes. No-op equality includes ordered names/bodies, active stable file identity, surviving file identities, and source-image ownership effects. A structurally destructive batch that deletes/recreates identity but returns to byte-identical named source is rejected as `FILE_CONFLICT` rather than silently destroying history/images under an unchanged public revision. Validation still runs, so an invalid operation cannot hide behind a later no-op.

For an effective catalogue mutation, validate the expected catalogue source first, create one scratch fork containing the final files, copy the original project's source-image maps, apply the plan's rename/delete transformations to the copied keys, switch `activeId` to the fork, and return both IDs. Never first modify the catalogue identity. The fork receives one initial source/project revision describing its final content; it does not expose an intermediate unedited scratch revision.

Commit order in one JavaScript turn:

1. Recheck active project, source revision, target epoch, and current file snapshot against the prepared plan.
2. Materialize a scratch fork if required and update source-image ownership in the same store draft.
3. Assign final `state.tabs` once and reconcile CodeMirror by stable file identity: remove deleted states, insert new states, retain renamed states, and externally replace changed bodies. Do not call `setDocuments`.
4. Update the fallback combined textarea if it still exists, active project/file fields, workspace rows, diagnostics/editor projections, and user-facing announcement.
5. Allocate one source revision, invalidate/schedule affected Phase 1 operations once, and persist once. Structural name/create/delete or entry deletion immediately clears unrelated outputs; body-only changes retain last-good output as stale and use the existing debounces.
6. Flush the agent-originated store mutation and return its exact receipt. Human-originated edits retain the existing debounced writer but use the same mutation/revision/schedule core.

The external editor transaction carries the module's existing `external` annotation so it does not re-enter `onChange`, but it remains a normal history-bearing CodeMirror change. When the human invokes undo, CodeMirror emits an ordinary change, the shared human mutation path updates the model/persistence/revision, and one file's undo does not affect another.

### Identity transitions

Apply Phase 1's definitions explicitly at the atomic commit boundary:

| Operation | Project/source/image identity | Workspace/target/options identity |
|-----------|-------------------------------|-----------------------------------|
| Create scratch | New project ID with initial project, source, and image revisions for its final contents | Workspace revision and target epoch advance; compile options retain their value/revision |
| Open another project | Existing project/source/image revisions do not change | Workspace revision advances because active flags change; target epoch and observation revision advance |
| Body/name/create/delete update | Project and source revisions advance once when final named source differs | Workspace revision advances because the listed project revision changed; target epoch advances only if the active file identity/name changes |
| Rename/delete with owned images | Source/project revisions advance; image revision also advances when effective file/declaration ownership changes | Workspace/target rules are as above |
| Catalogue fork | Catalogue identities remain unchanged; the scratch gets new initial project/source/image revisions for final source/images | Workspace revision and target epoch advance to the new project |
| Select entry | No project/source/image revision changes | Target epoch and observation revision advance; workspace/options revisions do not |
| Set warnings-as-errors | No project/source/image revision changes | Compile options and observation revisions advance; workspace/target do not |
| Persisted project eviction | Removed project revision records and all owned image/layout/diagnostic references are discarded | Workspace and observation revisions advance; the active project is protected so target does not change |

A source-equal body edit sequence that leaves identity/images unchanged is a no-op. Edit then user undo are two separately committed changes and receive distinct source/project/workspace revisions even when the later text equals an older snapshot, preserving Phase 1's no-revision-resurrection rule.

### Entry and compile settings

```ts
export interface SelectEntryInput {
  projectId: string;
  expectedSourceRevision: Revision;
  expectedTargetEpoch: Revision;
  name: string;
}

export interface CompileSettingsStatus {
  revision: Revision;
  warningsAsErrors: boolean;
}

export interface SetCompileSettingsInput {
  projectId: string;
  expectedTargetEpoch: Revision;
  expectedOptionsRevision: Revision;
  warningsAsErrors: boolean;
}
```

Extend tracked status with `configuration.compile: CompileSettingsStatus`. It is available after Phase 1 tracking becomes ready and changes only when the compile projection changes. Phase 5 may add other operation-specific settings without turning this into an untyped options bag.

`circ_select_entry` requires the named project to be active and the source/target preconditions to match. It selects the file through the same visible file-selection core as the UI, persists `activeFile`, creates a new target epoch, clears prior target diagnostics/artifact/session immediately, and starts one analyze/build pair. It never reorders files or changes source/project revision. Selecting the existing entry is unchanged and does not steal focus, compile, or allocate a target epoch.

`circ_set_compile_settings` mutates only the boolean accepted by `optionsFor('compile', settings)`. Unknown setting names cannot enter the schema. It checks the active target and options revision, updates the checkbox/store and compile projection together, advances the compile options revision once, marks incompatible build/preview/Truth output stale, and schedules only the affected operation families through the shared path. Analysis has an empty option projection, remains current, and is reused rather than allocating a semantically identical analyze operation. A same-value request is unchanged. Agent-originated changes flush persistence and report its receipt; display-only editor settings remain outside this operation.

Entry/settings calls that would persist against an active over-limit buffer differing from its scratch record return `UNSAVED_CHANGES` before changing either field. They must not write an `activeFile` that the persisted source does not contain or return `saved` against an older source revision. `circ_update_project` remains the recovery operation because it can reduce the project to a representable final source; `circ_compile`, reads, and help do not mutate persistence and remain usable while recovery is needed.

### Explicit compilation

```ts
export interface CompileInput {
  projectId: string;
  expectedSourceRevision: Revision;
  expectedTargetEpoch: Revision;
  expectedOptionsRevision: Revision;
}

export interface CompileTicket {
  target: TargetRef;
  optionsRevision: Revision;
  analysis: {
    operationId: OperationId;
    disposition: 'started' | 'joined' | 'already_current';
  };
  compile: {
    operationId: OperationId;
    disposition: 'started' | 'joined' | 'already_current';
  };
  artifactId: ArtifactId | null;
}
```

- `circ_compile` compiles only the active visible entry and all current siblings. It has no hidden `entryFile`, source, options object, or project-switch side effect; callers use the dedicated operations first.
- Validate all four preconditions before scheduling. Capture files, entry, compile options, target epoch, and source mapping before the first await. The operation input stamp is the Phase 1 stamp; this phase adds no parallel revision system.
- Resolve analysis and compile independently. An exact queued operation is flushed and reported `started`; an exact running operation is `joined`; an exact retained terminal operation that qualifies below is `already_current`; an absent/incompatible/expired operation gets a new `started` record after incompatible queued work is superseded. This permits, for example, current analysis to be reused while a missing compile starts, without lying through one aggregate disposition.
- Reusable analysis terminal states are `succeeded` or `diagnostics` for the exact target/source. Reusable compile terminal states are `succeeded`, `diagnostics`, or deterministic `refused` for exact target/source/options. A failed operation is retried with a new record when the transport remains available; when Phase 1 marks the compiler transport fatally failed, return/reuse one current immediate failed record instead of allocating unbounded retries. `superseded` is never reusable.
- The analyze and compile IDs are allocated/returned before worker initialization can await. The compile operation remains the workflow's terminal gate: if fresh analysis prevents compilation because of errors or promoted warnings, it ends as `diagnostics`; callers wait only for `compile.operationId` to learn that the build cannot proceed.
- Reuse `analysisFor`/the shared physical request cache only for byte-identical request JSON, while retaining each logical operation's target identity. The worker remains the sole libcirc owner. Explicit and debounced UI work use the same execute/publish/finalize functions.
- A known failed compiler transport still yields a ticket whose operations immediately terminalize as failed, preserving one observable operation model. It does not turn the tool transport itself into `INTERNAL_ERROR` or silently respawn the worker.
- Compile status 0 publishes/revalidates an artifact according to Phase 1's byte-and-file-map rules. Status 1 terminalizes as diagnostics and uses that reply's own file map. Status 2/4/5 and malformed replies are failures; a future unexpected status 3 is a distinct refusal. Last-good output remains visible with its old provenance.
- Cancellation of the tool invocation after a ticket is issued does not claim to cancel synchronous WASM or the worker message. Page disposal finalizes logical operations under Phase 1's lifecycle rules; a wait timeout is still only a wait timeout.

### Structured diagnostic sets

```ts
export type NativeDiagnosticRange = {
  lineBase: 1;
  columnBase: 1;
  columnEncoding: 'utf8-bytes';
  endExclusive: true;
  startLine: number;
  startColumn: number;
  endLine: number;
  endColumn: number;
};

export type SourceDiagnosticRange = {
  lineBase: 1;
  columnBase: 1;
  columnEncoding: 'utf16';
  offsetBase: 0;
  endExclusive: true;
  startLine: number;
  startColumn: number;
  endLine: number;
  endColumn: number;
  startOffset: number;
  endOffset: number;
};

export interface DiagnosticLocation {
  fileId: number;
  path: string | null;
  fileName: string | null;
  sourceAvailable: boolean;
  currentlyEditable: boolean;
  nativeRange: NativeDiagnosticRange;
  sourceRange: SourceDiagnosticRange | null;
}

export interface AgentDiagnostic {
  severity: 'error' | 'warning';
  code: string;
  message: string;
  location: DiagnosticLocation;
  related: { message: string; location: DiagnosticLocation }[];
}

export interface DiagnosticCompilerIdentity {
  version: string;
  revision: string;
  parser: string;
  parserRuntimeSha256: string;
  grammarSha256: string;
  topologyVersion: number;
  fullVersion: number;
}

export interface DiagnosticPage {
  requestedOperationId: OperationId;
  producerOperationId: OperationId;
  diagnosticSetId: string;
  observationRevision: Revision;
  requestedInputs: WorkInputs;
  producerInputs: WorkInputs;
  compiler: DiagnosticCompilerIdentity;
  counts: DiagnosticCounts;
  diagnostics: AgentDiagnostic[];
  nextCursor: string | null;
}

export interface GetDiagnosticsInput {
  operationId: string;
  expectedSourceRevision?: string;
  cursor?: string;
  limit?: number;
}
```

Diagnostic producer rules:

- An analyze operation resolves to its own status-0 analysis payload. A compile status-1 operation resolves to its own payload and file map. A compile status-0 or analysis-based diagnostic skip resolves to the exact paired analysis operation for that compile ticket. Store this relationship explicitly; never choose whichever analysis is currently displayed. `requestedInputs` always describes the operation ID the caller supplied, while `producerInputs` describes the actual diagnostic producer, so a compile's warnings-as-errors option provenance is not misreported as the analysis operation's empty projection.
- A queued/running operation returns `DIAGNOSTICS_NOT_READY`. A failed/refused operation with no compiler diagnostic payload returns `DIAGNOSTICS_UNAVAILABLE` with its structured operation failure/refusal. A successful producer with zero diagnostics returns an empty successful page and zero counts.
- `expectedSourceRevision`, when supplied on the first page, is checked against `requestedInputs.target.sourceRevision`. A cursor binds page ID, diagnostic set, producer/requested operation IDs, both complete input stamps, and next index. Cursor calls may omit the expected revision because it is already bound; supplying a different one is invalid.
- Default limit is 20, range 1–100. Return fewer items when required by the 32 KiB serialized envelope and advance by the number delivered. One unrepresentable diagnostic returns `RESULT_TOO_LARGE`; do not truncate code, message, related records, path, or provenance.
- Preserve compiler order. Counts describe the complete set, not the current page. Duplicate compiler diagnostics remain distinct entries in order.

At producer completion, convert locations while the immutable request files remain available, then release source bodies when no other consumer needs them. `nativeRange` preserves the compiler's 1-based UTF-8-byte-column contract. For an exact `/playground/<name>` request file, `sourceRange` converts each endpoint against that file body's line using the same UTF-8-to-UTF-16 primitive as `circ-diagnostics.ts`, and computes file-local UTF-16 offsets. `sourceAvailable` records that this historical request body was available for conversion. `currentlyEditable` is projected at page time and is true only when the same project/source revision and file name are still active; `observationRevision` identifies that projection. It may truthfully change between cursor pages without changing the immutable diagnostic set. A historical renamed/deleted file remains source-available but is not advertised as editable. For `<builtin>/...` or a path without captured source, return null source range. An unknown file ID has null path/name and no source range; never fabricate a path. Related locations follow the same rules and are never remapped through the primary file.

Validate every primary and related native range strictly before public conversion: all coordinates are positive safe integers; start is not after end lexicographically; lines exist in the captured source; each column normally lies in `1..utf8LineLength + 1`; and each byte column is on a UTF-8 scalar boundary. Preserve the compiler's documented synthetic `syntax` widening as the sole source-bound exception: on one line, a zero-width mark at `utf8LineLength + 1` may end exactly one column later. Keep that native range verbatim and clamp only its UTF-16 source end to the line/EOF, which may yield a zero-width editable source range on an empty line. Unknown/builtin source can be checked for numeric/order shape but has no source-bound validation. Any other malformed impossible project-source range makes the producer operation failed/internal before terminal publication rather than returning a plausible editable span. Keep the existing permissive/clamping mapper only for defensive legacy UI rendering and share its low-level byte-column conversion; do not use general clamping as public validation. Syntax diagnostics, `E*`, and `W*` codes pass through unchanged; tool/storage/compiler transport errors never masquerade as compiler diagnostics.

Retain complete converted sets in memory, not source snapshots. The 32-set and 2 MiB limits include pinned and unpinned records. One set may be at most 1 MiB, and at most two unique sets are pinned: the currently displayed diagnostic producer and the current compile ticket's exact paired producer (often the same set). Before admitting a new current set, unpin producers no longer referenced, evict oldest unpinned terminal sets, and then admit only if both total caps hold. A set that still cannot fit is not retained and yields `DIAGNOSTICS_UNAVAILABLE` with count/size facts; the operation keeps its counts/failure truth and the UI may render the immediate payload without promising later tool retrieval. Expiration does not remove `OperationSummary` counts or output provenance. A full reload starts with no diagnostic history; bfcache restoration retains the bounded store.

## Execution & Concurrency Model

### Ownership

- The island/store remain owners of projects, files, source images, settings, and visible editor state. The Phase 1 controller remains owner of revisions, operation/output provenance, and public orchestration. The mutation planner owns no live state. The diagnostics store owns bounded converted records. The worker remains the only compiler instance owner.
- Introduce a narrow injected workspace port whose methods read the current snapshot and commit a prepared mutation/open/selection/settings result. It exposes no DOM or store object publicly. The UI and controller call the same commit core for the operations this phase covers. The core accepts an internal origin mode: human typing is `already_applied` because CodeMirror changed first, while an agent mutation is `apply_external`; human add-file may select the new file while agent create-file keeps the current entry. These presentation/selection intents do not duplicate validation, revisions, persistence, or scheduling. Project rename/duplicate/delete and file reorder remain existing human-only paths with Phase 1 notifications; this phase does not claim an unspecified public domain contract for them.
- All workspace/create/open/entry/settings commits are synchronous and non-reentrant within one JavaScript turn. JavaScript event-loop ordering is the lock: validate expected identities immediately before commit, suppress external editor callbacks, commit once, and return. No mutex, worker, polling timer, or optimistic rollback is introduced.
- The controller rejects a nested mutation attempt with a bounded internal invariant failure; it does not queue stale expected revisions behind another mutation. Sequential native/external calls must use the revision returned by the preceding call.

### Mutation race behavior

1. Parse and validate input without reading mutable editor internals.
2. Capture the active project/version/files and prepare the immutable plan.
3. Recheck expected project/source/target/options identities at the commit boundary.
4. Commit synchronously, advance revisions, publish visible state, schedule once, and flush agent persistence.
5. Return the detached post-commit snapshot and operation IDs.

A human input event after the agent's earlier read but before this handler is dispatched wins and makes the expected revision stale. Input cannot interleave with the synchronous capture/recheck/commit sequence in steps 2–4. A human input immediately after commit receives the next source revision and may supersede queued/in-flight work; the successful agent result remains truthful for the revision it created. A delayed native result envelope does not imply the revision is still current, so callers use its returned revision/status preconditions for the next mutation.

Opening and project creation first protect representable current work as described above. They serialize with source mutations under the same synchronous gate. Project changes invalidate target work before starting the new target. A stale async compile can finish physically but Phase 1's target/source checks prevent publication.

### Editor reconciliation and lazy loading

- `applyDocumentEdits(index, batches)` synchronizes the active state and applies the planner's granular sequential edit batches to the indexed state as one transaction. For the active document use `view.dispatch`; for a hidden document use `state.update`. Mark it with `Transaction.userEvent.of('input.agent')` and `isolateHistory.of('full')` so it is one undo event and cannot merge with adjacent human typing. Granular changes let CodeMirror map selections and lint ranges before/inside/after edits; both paths use only existing dependencies.
- Reconcile removals from highest index downward and insertions in final order while tracking stable plan identity. Rename does not replace a document. Show the final active identity once at the end. Theme/preferences/diagnostics compartments ride with retained states.
- If CodeMirror has not loaded, commit against `state.tabs`, update the combined textarea exactly once, and let `mountEditor` construct documents from the latest state. If editor loading failed, tools remain usable and visible through the fallback. Do not force-load CodeMirror merely to mutate source.
- The built-island undo acceptance waits for CodeMirror readiness, edits two files through one agent batch, and proves independent user undo. Fallback acceptance proves correct current source/compile/persistence, not per-file history it cannot represent.

### Compile execution

Explicit compilation introduces no new background mechanism. It flushes or joins Phase 1's existing debounced operation coordinator. Analyze and compile remain independent logical operations and may share exact physical analysis. The worker processes messages under its existing request/reply ownership; every caller checks its immutable input stamp after awaits.

At most one current queued/running logical analyze and compile operation exists per active target/input family. Repeated exact `circ_compile` calls join instead of enqueueing unbounded worker work. An input change immediately terminalizes obsolete logical records as superseded and creates at most one replacement queued pair through normal scheduling. Tool waits retain the Phase 1 limit and semantics.

Diagnostic conversion is synchronous bounded work after a compiler reply. Convert once per producer rather than per page. If measured conversion of the maximum legal source/result blocks the reference browser's main thread for more than 50 ms, record a concrete finding before introducing chunking or another worker; do not silently move compiler ownership.

Page suspension/disposal uses Phase 0–1 registry and operation lifecycle gates. Synchronous commits already completed before suspension remain committed. Calls not yet dispatched receive lifecycle errors. No late editor load, worker reply, diagnostic conversion, or storage callback may publish through a disposed controller.

## Persistence & I/O

This phase adds no localStorage key or schema field. Scratch projects, active project/file, compile settings, source images, and UI state continue under `localStorage['circ.playground.v1']`, schema version 2. Revisions, operation IDs, mutation plans, diagnostic sets/cursors, and persistence receipts are page-memory only.

Extend the store internally so `flush()` returns the actual `writeEnvelope` result and evicted project identities, while existing callers may ignore it. Preserve debounced UI writes and make agent-originated mutating calls flush once after their coherent update. Do not implement a second serializer or write localStorage behind the store. Generate all applicable notices in one receipt; project-cap eviction, quota eviction, and image omission may coexist instead of one notice hiding another.

Persistence truth rules:

- `saved` means the post-normalization envelope containing the mutation was written successfully, `enabled` is true, and `persistedActive` names the exact active revision represented. It may include simultaneous project-cap, quota-eviction, and image-skipped notices.
- `memory_only` means the visible/in-memory mutation succeeded but storage is unavailable or became disabled. `persistedActive` is null and the first notice is the required disabled reason; reload recovery is not guaranteed.
- Source over 32 KiB is rejected before an agent commit, so no successful agent result uses the store's source-skipped path.
- Image overflow may omit images while retaining source, exactly as the existing writer does. Report `images_skipped`; do not claim source-owned memory scenarios will survive reload.
- The 16-project cap is an in-memory workspace mutation decided before persistence; its evictions remain effective even if storage later fails. Quota fitting and its one retry operate on a detached candidate envelope. Commit quota-driven removals to live state only after `setItem` succeeds; if both writes fail, preserve every live project and return memory-only/disabled rather than losing projects without saving them. Never evict the active project to save itself.
- A committed eviction removes every project-owned source-image key, data-panel position, remembered diagnostic badge, revision record, diagnostic pin, and other page-memory ownership record, not only the scratch row. Return exact counts and a bounded list of identities; if legacy names/IDs would overflow the reserved receipt budget, set `omittedCount` rather than truncating a string or losing the eviction count. Notify workspace/observation revisions once.
- A no-op compile/diagnostic read adds no storage call. Status/read/help behavior from prior phases remains side-effect-free.

The only compiler I/O is the existing same-origin `libcirc.wasm`/worker path. Project source and diagnostic results cross only the already verified native/external tool connection. No repository filesystem, clipboard, file picker, download, remote compiler, hosted persistence, source upload, analytics query, backend, or custom agent bridge is introduced.

Reload restores successfully saved scratch source, active entry, setting, and source-image data through the current envelope. It intentionally creates new page/revision/operation/diagnostic identities. Agents rediscover the page and reread status; old expected revisions/cursors cannot match the new page.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Define atomic mutation and diagnostic primitives | Add public DTO/error members, pure ordered mutation planning, file-local diagnostic conversion/store, indexed history-preserving editor replacement, and focused unit tests. | Atomicity, Unicode ranges, marker conflicts, stable file identity, hidden-file undo, exact producer mapping, paging, and retention tests pass. |
| 2 | Unify visible workspace mutations | Add controller/workspace ports and expose create/open/update/select-entry tools; route corresponding human operations through the same commit core with example forking, image ownership, one schedule, and structured persistence receipts. | Built-island create/open/edit/rename/delete/fork/fallback/reload cases agree through UI and public tools; conflict and quota paths are inert or truthfully memory-only. |
| 3 | Expose compile settings and explicit builds | Publish compile-setting revision, route the checkbox and tool through one setting operation, add `circ_compile`, and integrate start/join/already-current behavior with Phase 1's operation coordinator and real worker. | Exact-input reuse, flush, warnings-as-errors, worker failure, source/target/options conflict, and late-reply tests pass without a second compiler path. |
| 4 | Publish operation-bound diagnostics | Associate analyze/status-1 compile producers, register paged diagnostic reads, preserve native and UTF-16 locations/related spans, and integrate current UI diagnostic publication with bounded retention. | Multi-file, Unicode, builtin, syntax, compile-own-map, empty-success, unavailable, expiration, and result-budget cases pass against real compiler payloads. |
| 5 | Prove author-repair workflows | Complete documentation/decisions and run actual ChatGPT, OpenCode, and Claude Code multi-file author/repair flows, including human conflict, per-file undo, example fork, persistence reload, and native-unavailable fallback. | Recorded client calls plus all affected typecheck/build/test/bundle/browser gates pass with exact versions and provenance evidence. |

Slices are ordered by dependency and individually reviewable. Slice 1 changes no public registry. Slice 2 may expose authoring tools before explicit compile only if descriptions and usage docs accurately say that the existing automatic pipeline is the available build path until Slice 3. Do not advertise diagnostics retrieval before Slice 4. Each code slice includes its relevant documentation and real-page regression checks rather than deferring all integration to Slice 5.

## Tests

Test names are required assertions/scenarios, not claims that they exist at planning time. Use deterministic ID/clock factories, deferred promises, injected storage failures, and real compiler fixtures where specified.

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `ordered_file_mutations_are_atomic` | `playground-mutations.test.ts` | A late invalid rename/delete/range rejects the entire batch and leaves the input snapshot unchanged. |
| `text_edits_use_utf16_exclusive_ranges` | `playground-mutations.test.ts` | Ordered non-overlapping edits apply from the original operation body; surrogate-splitting, duplicate insert positions, overlap, and unsafe integers are rejected. |
| `agent_strings_are_well_formed_and_bounded` | `playground-mutations.test.ts` | Lone surrogates, overlong project/file names, and oversized serialized input are rejected before UTF-8 sizing or mutation. |
| `later_operations_name_the_current_draft` | `playground-mutations.test.ts` | Rename-then-edit/delete and create-then-edit work by the new/current name; stale old names fail at the exact operation index. |
| `effective_noop_does_not_allocate_work` | `playground-mutations.test.ts` | Same-text edits and same final state return unchanged with no fork/revision/reconciliation/schedule/persistence intent. |
| `destructive_source_equal_batch_is_not_noop` | `playground-mutations.test.ts` | Delete/recreate or another identity/image-destructive sequence cannot hide behind byte-identical final named source. |
| `final_files_round_trip_without_loss` | `playground-mutations.test.ts` | Blank non-last bodies, marker-looking body lines, illegal/duplicate names, empty projects, and source/file limits produce explicit conflicts. |
| `over_file_cap_project_can_be_reduced` | `playground-mutations.test.ts` | A legacy project above 128 accepts monotonic delete-only repair across calls and refuses edits/creates/renames until at the cap. |
| `mutation_plan_preserves_surviving_file_identity` | `playground-mutations.test.ts` | Rename/body changes retain stable identities, creates allocate new ones, deletes remove only their identity, and active selection follows identity. |
| `agent_document_edits_map_state_and_form_one_undo_step` | `editor-preferences.test.ts` | Visible/hidden granular transactions do not fire `onChange`, correctly map selections/lint spans before/inside/after edits, retain preferences, and independently undo through ordinary callbacks. |
| `catalogue_mutation_forks_once` | `playground-controller.test.ts` | The first effective example edit returns a scratch ID and copied images; subsequent edits target that scratch; no-op/failed edits do not fork. |
| `scratch_id_collision_cannot_alias_projects` | `playground-store.test.ts` | Sixteen injected random collisions fall back to a unique page-sequenced ID without replacing an existing record. |
| `revision_conflict_has_no_side_effects` | `playground-controller.test.ts` | A human revision win causes `REVISION_CONFLICT` with no editor/store/schedule/operation/focus changes. |
| `stale_workspace_create_and_open_are_inert` | `playground-controller.test.ts` | Workspace/active/target changes reject stale create/open, and retrying a successful create cannot duplicate it. |
| `mutating_success_is_size_checked_before_commit` | `playground-controller.test.ts` | Legacy oversized IDs/names or a warning-heavy result return `RESULT_TOO_LARGE` with no visible/model/store/revision changes. |
| `workspace_results_return_next_preconditions` | `playground-controller.test.ts` | Every changed/unchanged authoring result returns workspace, target, source, and compile-setting revisions usable by the next call. |
| `entry_selection_changes_target_not_source` | `playground-controller.test.ts` | Selecting another file advances target epoch, preserves source revision/order, clears unrelated output, persists active file, and queues one pair. |
| `authoring_identity_transition_matrix` | `playground-revisions.test.ts` | Create/open/body/rename/delete/image/fork/select/setting/eviction change exactly the project/source/image/workspace/target/options/observation identities specified. |
| `compile_setting_has_its_own_revision` | `playground-revisions.test.ts` | Warnings-as-errors advances compile options and invalidates compile, while source/editor/display revisions do not move incorrectly. |
| `explicit_compile_pair_has_independent_dispositions` | `playground-operations.test.ts` | Every mixed absent/queued/running/terminal/expired/failed analyze/compile pair receives truthful per-operation start/join/reuse behavior. |
| `explicit_compile_reuse_states_are_exact` | `playground-operations.test.ts` | Only the documented exact-input terminal states are reusable; superseded work and recoverable failures allocate correct replacements. |
| `compile_ticket_exists_before_worker_await` | `playground-controller.test.ts` | Delayed initialization still returns/records exact analyze and compile IDs; a known fatal transport yields immediate failed records. |
| `compile_status_one_owns_its_file_map` | `playground-diagnostics.test.ts` | Compile diagnostics use the status-1 reply's files and captured bodies, never a newer/current analysis map. |
| `diagnostic_locations_preserve_both_encodings` | `playground-diagnostics.test.ts` | Unicode project locations have exact native byte and file-local UTF-16 line/column/offset ranges; builtin locations remain noneditable with native ranges. |
| `malformed_diagnostic_ranges_fail_before_publication` | `playground-diagnostics.test.ts` | Unknown file IDs stay path-null, while bad line/column/order/UTF-8 boundaries in primary or related project ranges fail instead of clamping into plausible spans. |
| `compiler_widened_syntax_range_is_preserved` | `playground-diagnostics.test.ts` | Real empty/truncated-source `syntax` output keeps native `1:1-1:2` while its source projection clamps safely; the exception does not admit other past-EOL spans. |
| `diagnostic_related_ranges_use_related_files` | `playground-diagnostics.test.ts` | Every related span resolves against its own file ID/body and remains attached in compiler order. |
| `diagnostic_producer_follows_build_pair` | `playground-diagnostics.test.ts` | Analyze, status-1 compile, successful compile, and analysis-based skip resolve to the exact producer with separate requested/producer inputs, including warnings-as-errors. |
| `diagnostic_pages_are_bounded_and_revision_bound` | `playground-diagnostics.test.ts` | Pagination preserves complete records/counts/order, binds all provenance, advances under result-size shortening, and rejects cross-set cursors. |
| `diagnostic_retention_caps_include_pins` | `playground-diagnostics.test.ts` | Admission enforces individual/total/count/two-pin bounds, evicts stale sets first, and reports unavailable without silently dropping a current record. |
| `store_flush_returns_truthful_receipt` | `playground-store.test.ts` | Success, simultaneous cap/quota eviction and image omission, unavailable storage, and disablement return strict complete notices without changing schema. |
| `failed_quota_retry_preserves_live_projects` | `playground-store.test.ts` | Detached quota fitting cannot delete live projects or owned state when both storage writes fail; successful eviction cleans every owner record. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `public_multifile_author_repair_flow` | Built island plus real `libcirc.wasm` | Creates two files, selects the importing entry, observes an exact diagnostic, patches the blamed file, explicitly compiles, waits, and receives a current artifact for the returned source revision. |
| `public_agent_edits_preserve_per_file_undo` | Built island with CodeMirror | One batch edits two files; user undo in each file independently restores its prior text and emits coherent new revisions/build scheduling. |
| `public_example_edit_forks_with_images` | Built island/store | Opening a shipped memory example does not copy it; first effective update creates one scratch, preserves images, updates visible workspace/status, and persists the fork. |
| `public_file_rename_delete_preserve_ownership` | Built island/store | Rename moves source images/editor state and warns about imports; delete removes the right image/state, refuses the last file, and publishes one coherent pipeline change. |
| `public_fallback_editor_accepts_agent_mutations` | Built island with rejected editor import | Structured source changes update the textarea/model/read tools/persistence and compile normally without forcing CodeMirror. |
| `public_concurrent_human_edit_conflicts` | Built island with a stale expected revision | Human typing after the agent read but before its later tool call causes a revision conflict and preserves the human text, history, store state, and queued work. |
| `public_target_and_options_conflicts_are_inert` | Built island | Human entry/setting changes make stale select/settings/compile preconditions fail without selecting back or launching work. |
| `over_limit_buffer_blocks_persisted_entry_and_settings` | Built island/store | Entry/settings calls against a divergent over-limit active buffer return `UNSAVED_CHANGES`; update can reduce it and later saved receipts bind the repaired revision. |
| `explicit_compile_uses_shared_pipeline` | Built island/worker spies | UI debounce and tool compile share operation IDs, exact request/options, busy/freshness publication, deduplication, and worker failure handling. |
| `warnings_as_errors_produces_repairable_diagnostics` | Real compiler/browser | A warning-only source succeeds normally, becomes a diagnostic compile under the visible setting, returns the warning with exact provenance, and succeeds after repair. |
| `compile_diagnostics_survive_later_analysis` | Deferred real compiler replies | A status-1 compile's page keeps its own file map/ranges after a later analysis publishes; it never points into renamed source. |
| `agent_mutation_persistence_reload` | Real browser/localStorage | A created/repaired project, entry, setting, and retained images restore after reload; page/revision/operation IDs change and old cursors/preconditions fail. |
| `agent_mutation_storage_failure_is_honest` | Built/real browser storage failure | The visible mutation remains usable, result says memory-only/disabled, status agrees, and no reload-survival claim is made. |
| `quota_failure_keeps_inactive_projects_and_ownership` | Built island/store | A double quota failure preserves inactive projects/images/layout in memory, while a successful detached-fit eviction removes and reports all ownership consistently. |
| `chatgpt_author_compile_repair` | Actual supported ChatGPT browser-integrated agent | Discovers schemas, reads revisions/help, authors a multi-file project, compiles, retrieves/repairs a diagnostic, and identifies the final current artifact through native calls. |
| `opencode_author_compile_repair` | Actual OpenCode plus Phase 0 browser tooling | Performs the same visible flow through the verified external discovery/call route, including a human-edit conflict and reread/retry. |
| `claude_code_author_compile_repair` | Actual Claude Code plus Phase 0 browser tooling | Performs the same visible flow and records exact tab/tool/version/result evidence. |
| `authoring_native_unavailable_fallback` | Real browser/external page registry | All author/build/diagnostic operations work through the public registry when native WebMCP is unavailable, with matching result contracts. |
| `authoring_respects_bundle_boundaries` | Source graph and built bundle | New eager modules do not import CodeMirror/knowledge/renderer heavy entries; editor remains dynamically loaded and existing route budgets pass. |

Run focused unit tests from `site/`:

```sh
bun test test/playground-mutations.test.ts test/playground-diagnostics.test.ts test/playground-controller.test.ts test/playground-operations.test.ts test/playground-store.test.ts test/circ-diagnostics.test.ts test/editor-preferences.test.ts test/agent-tools.test.ts test/webmcp-adapter.test.ts
```

Run the required site gate after each implementation code slice, from `site/`, with no dev server running:

```sh
bun --bun run typecheck && bun --bun run build && bun test && bun run bundle
```

Run built-site real-browser acceptance after that build:

```sh
bun --bun run preview --host 127.0.0.1
```

Use the Phase 0 documented URL/origin and client setup. Record tool discovery, exact arguments/results, visible UI agreement, operation waits, compiler/corpus identity where used, browser/client/connection-tool versions, tested commit, and pass/fail in `DOCS/agent-playground.md` and `DOCS/STATUS.md`. A direct controller call, `el.__playground`, mocked native registration, screenshot, or DOM-scraped diagnostic is supporting evidence only. No Zig or renderer gate is required unless implementation discovers and justifies a change in those layers; if it does, follow `CLAUDE.md` and the macroplan rather than silently broadening this phase.

## Open Questions / Spikes

None — phase is fully specified. Implementation must resolve prior phases' actual exported symbol names after they land, but may not change the contracts above merely because the planning baseline predates those modules.
