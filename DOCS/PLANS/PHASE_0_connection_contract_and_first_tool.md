# Phase 0 — Connection contract and first tool

> **Dependencies:** None. `DOCS/PLANS_PROMPT.md` is the approved macroplan; this is the first implementation phase.
> **Warnings:** Read `CLAUDE.md`, the macroplan, and `DOCS/decisions/{playground,playground-bench,libcirc}.md`. ChatGPT is the human's primary browser-integrated target, clarified during phase discovery. Native WebMCP compatibility must be investigated and demonstrated on the exact product/version. The external path uses existing browser-control tooling with OpenCode and Claude Code. No application backend or custom bridge server may be added. This phase exposes observational status; authoritative source/build/session revisions ship in Phase 1.

## Goal

A person can open the playground in a supported ChatGPT browser environment and ask ChatGPT to discover and invoke `circ_get_status`, receiving a structured description of the project and pipeline currently visible on that page. OpenCode and Claude Code can discover and invoke the same operation through existing Chrome/browser-control tooling, including through the documented page registry when native WebMCP is unavailable. The tool reads existing application state without initiating compilation, loading a simulator, or changing the project. Setup instructions and an evidence matrix identify the tested product, browser, agent, connection-tool versions, and actual discovery/call results. Unsupported or failed native registration leaves the external registry and human playground usable. Completion requires real calls through all three target clients; a browser-API probe or mocked adapter test is supporting evidence, not the final proof.

## Scope

**In scope:**
- A compatibility investigation prioritizing ChatGPT's browser-integrated WebMCP path and establishing the precise supported product, version, API shape, and origin/setup requirements.
- Investigation of Chrome DevTools MCP's native WebMCP tools and its page-JavaScript evaluation fallback for OpenCode and Claude Code.
- One typed read-only controller method, one application tool definition, and a registry shared by native registration and external page access.
- The public page API `window.circPlayground`, with version metadata, `listTools()`, and `callTool(name, input)`.
- `circ_get_status({})`, returning project identity, entry file, compiler identity if already known, reported pipeline state, artifact presence, session availability, persistence availability, and connection health.
- Explicit indication that artifact/diagnostic freshness and revision identities are not yet tracked authoritatively in this phase.
- Runtime argument validation, JSON-safe results, stable application error codes, bounded results, and detached snapshots.
- Readiness, asynchronous native registration, registration failure, page suspension/restoration, and disposal behavior.
- Existing built-island coverage extended to the public interface, adapter/registry/controller unit tests, and actual ChatGPT/OpenCode/Claude Code connection acceptance.
- User-facing setup and compatibility documentation, the architectural decision record, and their index links.

**Explicitly deferred:**
- Phase 1's project listing/file reads, authoritative revision tracking, operation waiting, and build/session provenance.
- Phase 2's `circ_help`, reference corpus, diagnostic lookup, and complete-example retrieval.
- Phase 3's project/file mutations, explicit builds, compiler diagnostics retrieval, and compiler settings tools.
- Phases 4–5's simulation, memory, verification, inspection, view controls, and export tools.
- Additional application workers, hosted services, custom MCP bridge processes, extension development, and user-agent configuration changes performed by the site.
- Automatic registration of every circ operation as a separate native tool in an external agent's own tool list; the supported external workflow may use its existing discovery/execution or evaluation tools.
- Broad browser coverage beyond the primary target and documented compatibility results; adding another browser does not substitute for demonstrating ChatGPT without human agreement.

## File & Module Topology

Paths are relative to the worktree root. The files below describe implementation work, not artifacts to generate during this planning session.

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| Application contract | `site/src/scripts/playground-contract.ts` | Status DTOs, connection metadata, application result/error types, and API version; no DOM, editor, or renderer imports. |
| Controller | `site/src/scripts/playground-controller.ts` | A narrow read-only controller over an injected status reader; returns detached snapshots and owns controller disposal, not project/compiler state. |
| Tool registry | `site/src/scripts/agent-tools/registry.ts` | Definitions, discovery snapshots, argument validation, dispatch, result normalization/size bound, and active/suspended/disposed gates. |
| Status tool | `site/src/scripts/agent-tools/status.ts` | The sole `circ_get_status` description, empty-object schema, and controller-backed handler. |
| Page access | `site/src/scripts/agent-tools/page-api.ts` | Installs the frozen public facade, owns installation identity, and integrates pagehide/pageshow/remount cleanup. |
| Native adapter | `site/src/scripts/webmcp-adapter.ts` | Detects the investigated browser API, adapts one registry into native registrations/results, and handles asynchronous registration/cleanup. |
| Controller tests | `site/test/playground-controller.test.ts` | Status snapshot ownership, observational semantics, and disposal tests using injected readers. |
| Registry/page tests | `site/test/agent-tools.test.ts` | Schema/dispatch/results, public-facade isolation, size bounds, and installation/lifecycle tests. |
| Native tests | `site/test/webmcp-adapter.test.ts` | Injected native-provider tests for missing APIs, rejection, result adaptation, and lifecycle races. |
| Agent usage guide | `DOCS/agent-playground.md` | ChatGPT-first setup, external discovery/call recipes, compatibility evidence, and phase-accurate capability descriptions. |
| Agent decisions | `DOCS/decisions/agent-playground.md` | Records the verified connection mechanisms, shared registry/controller boundary, and observational status contract. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| Playground island | `site/src/components/Playground.astro` | Supplies an explicit status projection over existing state; tracks bootstrap outcome; mounts the controller/registry/adapters after their referenced records exist; wires lifecycle cleanup. |
| Built-island tests | `site/test/island-smoke.test.ts` | Exercises `window.circPlayground` against the built page, including project selection, missing native API, delayed bootstrap, and observing seeded compiler output. |
| Bundle graph tests | `site/test/bundle-graph.test.ts` | Proves new eager agent modules do not pull CodeMirror, the renderer's heavy entry point, or knowledge content into shared/light page graphs. |
| Documentation index | `DOCS/index.md` | Links the agent usage guide with its supported scope. |
| Decision index | `DOCS/decisions/index.md` | Links the agent integration decisions. |

`site/package.json`, the lockfile, WASM artifacts, and the persistent envelope need no planned changes. Existing `typecheck`, `build`, `test`, and `bundle` scripts cover the new TypeScript modules. `DOCS/STATUS.md` is appended by the implementation agent after each implemented slice, under the macroplan's working loop.

**New dependencies:** None in the application. Chrome DevTools MCP is separately configured existing agent tooling, not a site dependency. Slice 1 records the exact tested release and Node/browser requirements instead of assuming the site's Node pin is sufficient for that external tool. Model only the native API subset confirmed by the investigation in the adapter; no broad polyfill or native-API emulation is introduced.

### Existing integration anchors

- `Playground.astro:479–482`: current single-root mount; introduce ownership protection around the agent mount rather than invoking the whole island twice.
- `Playground.astro:577–604`: existing project tabs, analysis, artifact, compiler identity, and active-file request root.
- `Playground.astro:638–661`: the mutable `el.__playground` test hook; retained for old tests but never exposed through the public facade.
- `Playground.astro:1215–1235` and `pipeline.ts:88–166`: `StatusInput` and `statusFor`; the projection reads these records rather than status DOM text.
- `Playground.astro:2988–3039`: asynchronous share/bootstrap restoration; readiness must follow its actual completion or failure.
- `Playground.astro:3097–3101`: existing persistence flushing; agent lifecycle handlers must not cause additional store flushes.
- `Playground.astro:3276–3315`: scheduling and pipeline flush; status calls must not invoke them.
- `Playground.astro:3394–3421`: compiler handshake and renderer compatibility; status reports existing values without calling `ensureReady()`.
- `Playground.astro:4148–4157`: lazy session creation; status reports session presence without calling `ensureSession()`.
- `libcirc-client.ts:55–66`: initialization/call methods; neither belongs on a status-read path.

Line numbers refer to the planning baseline; resolve the symbols again before implementation.

## Data & State

### Public result and discovery contract

All returned data is JSON-safe: finite numbers, strings, booleans, null, arrays, and plain objects. No BigInt, functions, DOM nodes, runtime handles, typed arrays, Maps, Sets, undefined fields, or Error instances cross this boundary.

```ts
export const AGENT_API_VERSION = 1 as const;
export const MAX_TOOL_RESULT_BYTES = 32 * 1024;

export type AgentErrorCode =
  | 'UNKNOWN_TOOL'
  | 'INVALID_ARGUMENT'
  | 'PAGE_SUSPENDED'
  | 'PAGE_DISPOSED'
  | 'RESULT_TOO_LARGE'
  | 'INTERNAL_ERROR';

export interface AgentError {
  code: AgentErrorCode;
  message: string;
  retryable: boolean;
}

export type ToolResult<T> = {
  apiVersion: 1;
  pageId: string;
} & (
  | { ok: true; data: T }
  | { ok: false; error: AgentError }
);

export interface ToolDescriptor {
  name: string;
  description: string;
  inputSchema: {
    type: 'object';
    properties: Record<string, unknown>;
    required: string[];
    additionalProperties: false;
  };
  readOnly: boolean;
}

export interface ToolCatalogue {
  apiVersion: 1;
  pageId: string;
  tools: ToolDescriptor[];
}

export interface PlaygroundPageApi {
  readonly apiVersion: 1;
  readonly pageId: string;
  listTools(): Promise<ToolResult<ToolCatalogue>>;
  callTool(name: string, input: unknown): Promise<ToolResult<unknown>>;
}
```

- `pageId` identifies one controller/page installation and is not a browser tool's tab ID. Use an injected ID factory in tests and a browser-generated opaque ID at mount; a full reload/remount creates a new one. A back-forward-cache restoration of the same mounted document retains it.
- `window.circPlayground` is a frozen facade over the private registry. Its methods never return the registry, controller, or mutable island records. Discovery returns fresh descriptor/schema copies in a stable order. Registering duplicate tool names is a construction error, not last-registration-wins behavior.
- Only the site registry defines tool names, descriptions, schemas, validation, and handlers. Native/provider-specific hints are projected from descriptors; `readOnly` is the internal semantic flag and is not blindly forwarded under an assumed browser annotation spelling.
- `callTool` requires a string tool name and explicit JSON object input. In Phase 0, `circ_get_status` accepts exactly `{}`; arrays, null, strings, omitted input, and unknown properties return `INVALID_ARGUMENT` without invoking the handler. A known tool with malformed arguments is distinct from an unknown tool. Lifecycle errors take precedence after suspension/disposal.
- Measure the UTF-8 bytes of the serialized application result. Oversized results return a small `RESULT_TOO_LARGE` error instead of truncating fields silently. Bound internal error messages so the error response itself fits. The bound applies before any native text-envelope wrapping.
- Validate JSON compatibility before serialization: reject cycles, non-finite numbers, undefined values, and non-plain objects rather than relying on `JSON.stringify` to silently drop or coerce them. The snapshot clone and validation must not invoke custom `toJSON` methods. `retryable` means retrying the same invocation against the same facade can recover: it is true for `PAGE_SUSPENDED` and false for the other Phase 0 errors; invalid arguments require correction and a disposed page requires rediscovery.
- Ordinary validation/lifecycle failures resolve as `ToolResult`, not rejected promises. Catch unexpected handler/serialization failures and return `INTERNAL_ERROR`; do not serialize a thrown stack or arbitrary thrown object. Native discovery/transport failures that occur before a handler runs remain provider failures and are documented separately.
- Both native execution and external invocation route through the same `callTool` dispatch. Native wrapping may vary with the investigated API, but decoding the returned application result must produce this exact contract.

### The first tool

```ts
const statusDescriptor: ToolDescriptor = {
  name: 'circ_get_status',
  description:
    'Read the open circ playground project and reported compiler status. ' +
    'Returns connection readiness and existing output availability. ' +
    'This operation does not compile or change the project; ' +
    'revision-verified freshness is reported as untracked in this release.',
  inputSchema: {
    type: 'object',
    properties: {},
    required: [],
    additionalProperties: false,
  },
  readOnly: true,
};
```

The description is shared by native and page discovery. It must not advertise operations that later phases have not registered.

### Observational status

```ts
export type NativeConnectionState =
  | 'not-configured'
  | 'checking'
  | 'unsupported'
  | 'registering'
  | 'registered'
  | 'failed'
  | 'suspended';

export interface PlaygroundStatus {
  lifecycle: 'initializing' | 'ready' | 'failed';
  bootstrapError: string | null;
  project: {
    id: string;
    name: string;
    entryFile: string;
    fileCount: number;
  } | null;
  view: 'schematic' | 'live' | 'truth';
  compiler: {
    ready: boolean;
    loading: boolean;
    identity: {
      version: string;
      revision: string;
      topologyVersion: number;
      fullVersion: number;
      grammarSha256: string;
    } | null;
    simulationCompatible: boolean | null;
  };
  reportedPipeline: {
    kind: 'idle' | 'loading' | 'compiling' | 'live' | 'error';
    analyzing: boolean;
    building: boolean;
    analyzePending: boolean;
    buildPending: boolean;
    errors: number;
    warnings: number;
    stale: boolean;
    failure: string | null;
  };
  artifact: {
    present: boolean;
    bytes: number | null;
  };
  session: {
    present: boolean;
  };
  provenance: {
    tracking: 'untracked';
    sourceRevision: string | null;
    buildRevision: string | null;
    sessionId: string | null;
  };
  persistence: {
    enabled: boolean;
  };
  agentAccess: {
    pageRegistry: 'available';
    native: {
      state: NativeConnectionState;
      apiVariant: string | null;
      reason: string | null;
    };
  };
}

export interface StatusReader {
  read(): PlaygroundStatus;
}

export interface PlaygroundController {
  getStatus(): PlaygroundStatus;
  dispose(): void;
}
```

Projection rules:

1. `lifecycle` refers to project/bootstrap restoration, not compiler readiness. Initial status is valid while a share is decoding. Until restoration completes, `project` is null rather than exposing the server-rendered default as the restored project. A failed restoration is visible through `lifecycle: 'failed'` and a bounded `bootstrapError`.
2. After restoration, project ID/name come from the active workspace selection; entry and file count come from `state.tabs`. No source bodies, memory images, filenames from the host filesystem, or raw share fragment are included in this tool's payload.
3. `compiler.identity` comes from the completed `state.version` handshake only. Before the handshake it is null; do not call the compiler or substitute build-time manifest identity as though it had been checked in this page. `simulationCompatible` is null until the handshake and then reflects the existing version compatibility check.
4. `reportedPipeline.kind` is `statusFor(pipe).kind`. Booleans/counts/failure come from `pipe`; pending flags come from `analyzeStage.pending` and `buildStage.pending`. Report stale conservatively as `state.stale || pipe.stale`. These are the application's reported observations, not new revision guarantees.
5. `artifact.present`/`bytes` derive from `state.artifact`; absent means null size, not zero bytes. `session.present` is true only for an existing live session (`sim.session?.isAlive`); do not create one to answer.
6. All three provenance identity fields are null and `tracking` is `untracked` in this phase. `state.doc`, a debounce sequence, and the artifact's hash are not substituted for the authoritative identities Phase 1 will introduce. In particular, a reported `kind: 'live'` does not prove that current source has a matching artifact.
7. `persistence.enabled` reads `store.enabled`; it means persistence is available, not that a pending debounced save has completed.
8. Native connection metadata belongs to the adapter's in-memory status record. `registered` means the browser registration succeeded, not that ChatGPT has discovered or used it. Only the integration evidence may claim successful agent invocation.

Slice 3's independently shippable external-only integration reports native state `not-configured` with the reason that the native adapter is not installed yet. Slice 4 installs that adapter and replaces the placeholder with actual detection/registration health; do not label a browser unsupported merely because the adapter has not shipped.

The controller wraps an injected reader and returns detached copies. It does not start maintaining a duplicate project/store model. Its `dispose()` invalidates further reads with a recognizable internal controller-disposed error; the registry maps that error to `PAGE_DISPOSED` rather than `INTERNAL_ERROR`. The island projection is field-by-field and reads all records synchronously in one JavaScript turn. Phase 1 extends this boundary and provenance contract after adding actual tracking.

### Native-provider boundary

Keep browser-specific registration behind an internal injectable interface:

```ts
export interface NativeRegistration {
  dispose(): Promise<void>;
}

export interface NativeRegistrar {
  readonly apiVariant: string;
  register(
    descriptor: ToolDescriptor,
    invoke: (input: unknown) => Promise<ToolResult<unknown>>,
    signal: AbortSignal,
  ): Promise<NativeRegistration>;
}
```

This is an application test boundary, not a claim that any browser exposes those signatures. Slice 1 records the actual provider's receiver, registration method, callback shape, supported return value, registration completion signal, and unregistration/cancellation mechanism. Slice 4 implements the mapping. If an invocation wrapper requires a text content block, serialize the complete `ToolResult` into that block; if it accepts a JSON object, return the object. Pick and document the verified representation per API variant and assert round-trip equivalence. Do not simultaneously register the same tool through several detected native APIs.

## Execution & Concurrency Model

### Ownership and read execution

- The existing island remains the owner of project, compiler, store, and live session state. The read-only controller holds a reader function; the private registry owns definitions and dispatch; the native adapter owns registration state; the page installation owns lifecycle listeners and the public facade.
- Status capture is synchronous and side-effect-free. Discovery/dispatch expose promises for a consistent external/native interface, but this phase introduces no compiler work, simulation work, new Web Workers, timers for polling, or mutation queue.
- Multiple status calls can execute independently. Each captures a fresh snapshot in one JavaScript turn. Two calls separated by user input may correctly differ; adapter parity tests use a fixed reader rather than expecting changing live state to be byte-identical across time.
- Validate lifecycle and arguments before reading. The controller's reader is never invoked for malformed/unknown calls. After a successful synchronous snapshot, deliver that snapshot; no second read at response serialization changes its meaning.

### Mount and bootstrap

1. Declare a small bootstrap-state record before invoking the existing asynchronous `bootstrap()` function. Set it to ready only when project restoration and the existing restored-view setup finish; catch a rejected bootstrap and record failure through the existing error/status presentation path.
2. At the end of `init(el)`, once `state`, `pipe`, the stages, `store`, and `sim` exist, create the read-only controller and registry, install the page facade, and start native detection/registration. Native registration does not wait for share decoding, CodeMirror, WASM, or a session. The tool can report initializing state.
3. Use an element-keyed ownership record for agent mounting. Repeated attachment to the same live element returns the existing installation; it does not register again. A legitimate replacement disposes the old installation first. An unrelated existing `window.circPlayground` value is a named installation conflict, never silently overwritten.
4. Cleanup removes the global only if it still points to that installation's facade. An older cleanup cannot remove a newer mount's global or unregister another owner's tools. Preserve the existing `.astro` initialization behavior; agent-mount idempotence does not require rerunning or rewriting the entire island.

### Native registration and teardown

- Feature detection checks callable members on the investigated API receiver and any verified context requirements, not user-agent strings. No native API means `unsupported`; a rejected registration means `failed`, with a bounded reason. Both leave the external facade available.
- Guard asynchronous registration with an installation generation and `AbortController`. A completion belonging to an old generation cannot mark the new installation registered. If a stale registration still succeeds, immediately dispose that registration handle.
- Serialize native unregister/register transitions for this installation. On restore, await the previous registration's cleanup before trying to register the same name again. Handle both synchronously thrown and asynchronously rejected browser API calls.
- Unexpected native registration failure is reported in `agentAccess.native`; it does not become a compiler failure in `pipe.failure` and does not disable the editor or external tool path.

### Page lifecycle

- On `pagehide` with `persisted: true`, suspend dispatch, set native state to suspended, and unregister/abort native exposure. Retain the controller, registry, facade, and `pageId` for the same cached document. A held facade answers `PAGE_SUSPENDED`; no project or compiler state is destroyed by agent suspension.
- On `pageshow` for that restored installation, reactivate dispatch and register native tools again after pending cleanup completes. This is a new native registration generation with the same page/controller identity.
- On non-persisted `pagehide` or explicit installation disposal, invalidate dispatch, dispose the controller, unregister native exposure, remove only owned listeners/global state, and answer `PAGE_DISPOSED` to any retained facade reference.
- `visibilitychange` alone does not suspend agent tools: an external agent may operate a background tab. Existing persistence handlers retain their current semantics; the new handlers never call `store.flush`, `client.dispose`, session reset, or compilation.
- Verify browser lifecycle behavior in addition to the injected test model. If the target API cannot unregister reliably on a cached-document transition, record the provider limitation and resolve the lifecycle contract before claiming the phase complete.

## Persistence & I/O

This phase adds no persisted playground fields or storage keys. It reads the existing in-memory store view and status records. The normal bootstrap may decode a share and restore/save the project as it already does; invoking discovery or status must add no storage write or network request. Read-only tests measure the operation's incremental effects, not a false assumption that normal page bootstrap never initializes the compiler.

The page exposes tool descriptions and requested status results to the connected agent through native browser APIs or the existing external browser connection. The site still serves static HTML/JS/WASM assets through its existing deployment. A local static preview used for testing is the existing site preview, not an added application backend. Do not introduce a relay, a source-upload endpoint, a custom browser extension, or a custom HTTP/WebSocket listener.

### Compatibility investigation and evidence

Planning sources inspected on 2026-09-12:

- [WebMCP implementation status](https://github.com/webmachinelearning/webmcp/blob/main/implementation-status.md) lists ChatGPT Desktop as supported.
- [WebMCP explainer](https://github.com/webmachinelearning/webmcp/blob/main/README.md) describes the evolving imperative registration API; the version inspected uses `document.modelContext`.
- [Chrome DevTools MCP tool reference](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md) documents `list_webmcp_tools` and `execute_webmcp_tool` behind `--categoryExperimentalWebmcp`, and `evaluate_script` for JSON-serializable page-JavaScript results.
- [Chrome DevTools MCP README](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/README.md) documents existing external-client setup and browser requirements.

These are candidate compatibility sources, not recorded successful playground tests. Record exact release/source revisions and retrieval dates during Slice 1; mutable upstream main-branch documentation is not a pin.

The investigation must establish:

1. **ChatGPT:** the precise application/browser surface and version that discovers page-provided WebMCP tools; whether the agent is attached to the same visible document; origin/secure-context and any feature-enablement requirements; whether the development URL is reachable. Do not infer that ChatGPT web chat, Desktop, and every built-in browser mode have identical support. Start with the documented ChatGPT Desktop candidate and verify the actual available product. If a static hosted test URL is needed, record that deployment requirement; this plan does not authorize publishing it.
2. **External clients:** one exact released Chrome DevTools MCP version, compatible Chrome/Node versions, configuration recipes for OpenCode and Claude Code, browser ownership/attachment mode, and tab selection. Prefer its native WebMCP discovery/execution tools when that release and browser actually support them. Verify the page-evaluation fallback independently. An unreleased main-branch tool reference is not evidence that the installed package exposes those tools.
3. **Shared visible context:** the selected external tab is the playground document whose project is being observed. A separately launched browser/profile has separate storage; setup instructions explicitly distinguish opening the project there from attaching to an existing browser. The normal browser debugging connection used by existing tooling is permitted; no project-specific bridge service is added.
4. **Registration/result contract:** the precise native API variant, input forwarding, output representation, cleanup behavior, and how discovery exposes the description/schema to the model. Bind the adapter to proven behavior.

Use a compatibility matrix in `DOCS/agent-playground.md`:

| Client / product | App + browser version | Connection tool version / mode | Page origin + tested commit | API variant | Discovery evidence | Status-call evidence | Result |
|------------------|-----------------------|--------------------------------|----------------------------|-------------|--------------------|----------------------|--------|
| ChatGPT, exact product from investigation | To measure | Native | To measure | To measure | Required | Required | Pending |
| OpenCode | To measure | Chrome DevTools MCP, exact release and mode | To measure | Native or page registry | Required | Required | Pending |
| Claude Code | To measure | Chrome DevTools MCP, exact release and mode | To measure | Native or page registry | Required | Required | Pending |

Record failures and unavailable environments as such, including the failing step and reproduction. Do not mark another browser's pass as a ChatGPT pass. If the target cannot be exercised, stop the acceptance process and bring the blocker to the human; implementation remains unaccepted until the target succeeds or the human explicitly changes the target.

### External page-registry recipe

The guide documents tab selection through the installed browser tool before executing either expression:

```js
async () => {
  if (!window.circPlayground) {
    return { available: false, reason: 'Playground tool registry not mounted' };
  }
  return window.circPlayground.listTools();
}
```

```js
async () => window.circPlayground.callTool('circ_get_status', {})
```

The external client discovers schemas first and calls by semantic tool name. It uses the browser tool's native argument passing or properly serialized JSON for future inputs; no unescaped user text is interpolated into executable code. `evaluate_script` is existing agent tooling; the playground itself exposes no arbitrary-evaluation operation. The native external recipe records the tested tool names and flags separately, since their presence is version-dependent.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Establish the compatibility contract | Investigate the ChatGPT-first path and existing external tooling; create the usage guide with exact candidate/probed versions, API/result/cleanup findings, setup recipes, and an initially incomplete acceptance matrix. | `compatibility_api_probe` records the actual native registration surface and external tool availability; `compatibility_origin_probe` records a reachable static-page origin and visible-tab association; final `circ_get_status` acceptance remains explicitly pending. |
| 2 | Define observational status | Add `playground-contract.ts`, the injected read-only controller, and its unit tests, fixing the Phase 0 DTO and explicitly untracked provenance semantics. | `status_snapshot_is_detached`, `status_read_has_no_side_effects`, `status_preserves_untracked_provenance`, and controller disposal cases pass. |
| 3 | Ship the external page registry | Add the sole status definition, registry, page facade/lifecycle, island projection and bootstrap tracking; expose the operation through the public page API. | Registry validation/isolation/lifecycle tests and built-island `public_status_tracks_selected_project` pass; `external_page_registry_call` demonstrates a real external-client call in the selected tab. |
| 4 | Expose native WebMCP | Implement the investigated native-provider mapping, registration health, result normalization, and generation-guarded cleanup/restoration over the same registry. | Native adapter unit tests pass for the investigated variants, including delayed registration after teardown; `native_status_tool_call` proves real browser-mediated invocation with the application's result schema. |
| 5 | Prove all target clients and document the contract | Complete actual ChatGPT, OpenCode, and Claude Code discovery/status calls; verify native-unavailable fallback and reload/restoration; finalize setup, decisions, index links, and measurements. | `chatgpt_status_discovery_and_call`, `opencode_status_discovery_and_call`, `claude_code_status_discovery_and_call`, public lifecycle/no-extra-work checks, and all required site gates pass with evidence recorded. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own. Slice 1 is a research/documentation deliverable; it does not claim the final tool exists. A blocker that invalidates the connection architecture is resolved before dependent implementation. Record genuinely unavailable target access in STATUS instead of filling the compatibility table with assumed passes. Every code slice runs the affected automated gates; each connection slice also runs its specified browser check.

## Tests

Test names below are required named assertions/scenarios; integration evidence names can be recorded browser walkthroughs where the agent product has no automatable runner. Do not label a manual agent scenario as a Bun test.

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `status_snapshot_is_detached` | `playground-controller.test.ts` | Mutating one returned nested record does not alter the reader's records or another returned snapshot. |
| `status_read_has_no_side_effects` | `playground-controller.test.ts` | A status call invokes only its injected reader once; no compiler initialization, session creation, storage write, or scheduling dependency is reachable. |
| `status_preserves_untracked_provenance` | `playground-controller.test.ts` | A reported live pipeline with an artifact retains `tracking: untracked` and null identity fields; it cannot become revision-verified status. |
| `disposed_controller_rejects_reads` | `playground-controller.test.ts` | Repeated dispose is harmless and a disposed controller cannot return current-looking data. |
| `catalogue_has_one_status_tool` | `agent-tools.test.ts` | Discovery lists exactly `circ_get_status`, with the shared description, empty-object schema, read-only flag, and API/page identity. |
| `catalogue_is_detached_and_duplicates_refused` | `agent-tools.test.ts` | Mutating a descriptor/schema copy cannot change future discovery or validation; duplicate names fail registry construction. |
| `invalid_status_arguments_are_inert` | `agent-tools.test.ts` | Null, arrays, strings, missing input, and objects with unknown keys return `INVALID_ARGUMENT` without invoking the status reader. |
| `unknown_tool_is_distinct` | `agent-tools.test.ts` | An unknown name returns `UNKNOWN_TOOL`; invalid argument shape for a known name returns `INVALID_ARGUMENT`. |
| `results_are_json_safe_and_bounded` | `agent-tools.test.ts` | A valid result survives JSON round-trip, an oversized one becomes `RESULT_TOO_LARGE`, and non-JSON/throwing handler results become bounded `INTERNAL_ERROR` responses. |
| `page_facade_exposes_only_public_methods` | `agent-tools.test.ts` | The frozen facade exposes metadata/discovery/call only; no island state, registry mutation, compiler, or runtime handle is reachable through returned objects. |
| `mount_ownership_is_idempotent` | `agent-tools.test.ts` | Reattaching to the same element does not duplicate tools/listeners; old cleanup cannot remove a replacement's facade; an unrelated global collision is refused. |
| `cached_page_suspends_and_resumes` | `agent-tools.test.ts` | Persisted pagehide gates dispatch, pageshow restores it with the same page ID, and non-persisted disposal invalidates old references; visibilitychange alone leaves tools available. |
| `missing_native_api_keeps_page_registry` | `webmcp-adapter.test.ts` | Missing/incomplete native APIs yield unsupported status while public discovery/calls still work. |
| `native_registration_failure_is_isolated` | `webmcp-adapter.test.ts` | A synchronous throw or rejected registration records failed connection health without changing compiler state or disabling the page registry. |
| `native_and_page_calls_share_dispatch` | `webmcp-adapter.test.ts` | Native and page invocation call the same validator/handler; decoded results match under a fixed snapshot for both success and malformed input. |
| `late_registration_cannot_revive_disposed_tools` | `webmcp-adapter.test.ts` | A registration resolving after suspension/disposal is cleaned up and cannot overwrite a later generation's status. |
| `restore_waits_for_native_cleanup` | `webmcp-adapter.test.ts` | Re-registration waits for prior cleanup, creating one active registration and using the correct receiver for native methods. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `compatibility_api_probe` | Slice 1, real target API/tool investigation | Records actual callable native API members, input/output/cleanup behavior, and which discovery/execution/evaluation tools the selected released external package exposes. |
| `compatibility_origin_probe` | Slice 1, real target environment | Establishes that the target can open a static test page and that the agent acts in the visible document; reports any static-hosting prerequisite. |
| `public_status_tracks_selected_project` | Built-island test | Calls the public registry after existing UI project/file selection and receives the corresponding project ID, entry file, and file count without using the debug hook as its API. |
| `public_status_observes_pipeline_without_driving_it` | Built-island test | With controlled/seeded pending stages and compiler output, returns reported fields and null provenance; repeated public reads add no worker calls, schedule calls, store writes, or session builds. |
| `public_status_during_delayed_share_restore` | Built-island test | Before delayed decode finishes, status says initializing/project null; after restore it names the shared scratch project; a rejected bootstrap produces failed lifecycle without losing the registry. |
| `public_status_survives_editor_load_failure` | Built-island test | Rich-editor load failure retains the textarea and public status API; reads do not force editor loading or focus. |
| `external_page_registry_call` | Real browser via existing external client tooling | After selecting the tab, discovery and evaluation invoke the public semantic tool and return the agreed JSON application result. |
| `native_status_tool_call` | Real native WebMCP registration | Browser-mediated discovery/call reaches the same handler and returns a decodable ToolResult; existence of an API property alone cannot pass. |
| `chatgpt_status_discovery_and_call` | Actual ChatGPT browser-integrated agent | ChatGPT discovers `circ_get_status` with its schema, invokes it on the target page, and reports the project's actual identity/status; tool-call evidence distinguishes this from screenshot/DOM inference. |
| `opencode_status_discovery_and_call` | Actual OpenCode with existing browser tooling | Discovers/calls through the verified native external route when available, and independently through page evaluation; records tool/version/tab identity and result. |
| `claude_code_status_discovery_and_call` | Actual Claude Code with existing browser tooling | Performs the same documented discovery/call workflow successfully against the visible playground and records equivalent evidence. |
| `native_unavailable_external_fallback` | Real browser with native API unavailable/disabled | Page registry discovery/calls succeed, native health reports unsupported, and normal project editing remains usable. |
| `registration_reload_and_cache_restore` | Real browser plus injected lifecycle tests | Reload gets a new page ID with one registration; genuine cached-document restoration retains its ID and restores exposure; stale installation cleanup cannot unregister the new one. Record whether the real browser actually used bfcache. |
| `status_adds_no_work_or_network` | Real-browser incremental observation | After allowing normal bootstrap activity to settle, repeated status/discovery calls trigger no additional compiler/runtime initialization, network request, storage write, or visible state change. |
| `agent_modules_respect_bundle_boundaries` | Source graph and built bundle | Agent imports stay on the playground route, heavy editor/renderer/knowledge modules remain lazy, and existing route budgets pass. |

Run command, from `site/`, for focused unit tests:

```sh
bun test test/playground-controller.test.ts test/agent-tools.test.ts test/webmcp-adapter.test.ts
```

Run command, from `site/`, for the required code-slice site gate:

```sh
bun --bun run typecheck && bun --bun run build && bun test && bun run bundle
```

Run the built site for real-browser acceptance, from `site/`, after the build has completed and the dev server is stopped:

```sh
bun --bun run preview --host 127.0.0.1
```

Use the URL printed by Astro; the ChatGPT investigation establishes whether that product can reach this local origin or needs an authorized static deployment. Do not run the generator-bearing dev server concurrently with the build. The baseline macroplan's Zig/renderer gates apply only if a separately justified change reaches those layers.

Agent acceptance is a recorded procedure, not a fabricated shell command: open/select the test page through the actual client, discover its tool definition, call `circ_get_status({})`, compare the result with the visible project, change project/file through the UI, call again, then exercise reload/fallback as applicable. Include the prompt, actual tool name and arguments, returned application result, tested commit/version information, and pass/fail in the guide/STATUS. Screenshots may supplement this evidence but do not replace the tool trace.

## Open Questions / Spikes

- **TODO(phase0): Verify the exact ChatGPT product and version.** The upstream support list names ChatGPT Desktop, while the human asked for ChatGPT's browser experience. Slice 1 must establish the actual available surface, native discovery/invocation, origin reachability, and any feature setup. A product label or upstream support claim is not a successful integration test. If unavailable, report the blocker and ask the human before substituting another primary target.
- **TODO(phase0): Pin the native API mapping from observed behavior.** Confirm the receiver (`document.modelContext` in the inspected current explainer, or another verified implementation), registration/callback/result/cleanup signatures, and cached-document behavior. Fill `apiVariant` vocabulary and the provider-specific wrapper in the implementation decision record. Keep the application's public DTO and registry contract independent of that result.
- **TODO(phase0): Verify the released external tooling.** Confirm that the selected Chrome DevTools MCP release exposes the documented experimental native tools, including the exact flag and tab-argument shape; otherwise use its verified `evaluate_script` workflow and record why. Test OpenCode and Claude Code separately. Record browser attachment/profile behavior and external Node requirements.
- **TODO(phase0): Obtain actual target-client evidence.** The planning session has fetched upstream documentation and inspected repository code; it has not exercised ChatGPT or either external browser connection. The implementation must arrange those real-client checks with the human when they require their application/session access. Do not count missing evidence as a passed phase.
- The remaining scope, application file topology, public types, state ownership, persistence behavior, slices, and assertions are specified above. The compatibility items are deliberately assigned to Slice 1 and final acceptance; they are not permission to invent a backend or silently weaken the ChatGPT requirement.
