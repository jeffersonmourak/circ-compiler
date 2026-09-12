# Agent Playground

The `/playground` page exposes a small browser-resident tool contract for agents working alongside a person. Compilation, simulation, project storage, and the page registry run locally in the browser. The static site has no application backend, relay, or custom MCP bridge.

Tool arguments and requested results are delivered to the connected agent through its browser integration or browser-control tooling. Treat source and results as data shared with that client and subject to its provider/tooling policies.

## Phase 3 Capability

All tools are read-only: they do not select a project, flush a debounce, compile, create a session, edit source, or write storage.

| Tool | Input | Result |
| --- | --- | --- |
| `circ_get_status` | `{}` | Tracked project/target revisions, output freshness/provenance, current operation IDs, session/preload status, and compiler transport health. |
| `circ_list_projects` | `{ cursor?, limit? }` | A deterministic, revision-bound page of readable projects. |
| `circ_read_project` | `{ projectId?, expectedRevision?, cursor?, limit? }` | A revision-bound file manifest without source bodies. |
| `circ_read_file` | `{ projectId?, name, expectedSourceRevision?, offset?, maxCodeUnits? }` | Exact UTF-16 source chunks, including offsets and EOF metadata. |
| `circ_wait_for_operation` | `{ operationId, timeoutMs? }` | A retained terminal outcome, or a bounded `timed_out` observation. |
| `circ_help` | `{ action: 'search', query, kind?, limit?, cursor?, expectedCorpusId? }` | Deterministic local search of shipped references, diagnostics, and examples. |
| `circ_help` | `{ action: 'read', id, offset?, maxCodeUnits?, expectedCorpusId? }` | UTF-16-safe chunks of a cited reference, diagnostic, source file, or memory image. |
| `circ_help` | `{ action: 'example', id, expectedCorpusId? }` | Complete named-file gallery/tour project and its required ROM/RAM initialization, or a resource manifest when it cannot fit. |

Results are JSON-safe, bounded to 32 KiB, and include a page ID. After bootstrap, status provenance is `tracked`: an output's producer operation and captured inputs distinguish a current result from a retained last-good result. IDs are page-memory-only and expire after reload; retained terminal operation history is bounded to 128 records.

Source chunks use zero-based UTF-16 offsets and exclusive ends. The default chunk is 2,048 code units; `maxCodeUnits` is 2 through 4,096. A nonzero offset requires the prior `sourceRevision`, and changed source or paging state returns `REVISION_CONFLICT` rather than mixing revisions.

Agents can now author and repair visible projects through the same page registry:

| Tool | Input | Result |
| --- | --- | --- |
| `circ_create_project` | Observed workspace/active/target revisions, optional name/files/entry | Creates and opens one scratch project. |
| `circ_open_project` | Observed workspace/active/target revisions and project revision | Opens an existing project without editing shipped content. |
| `circ_update_project` | Active project/source/target revisions and ordered edits/creates/renames/deletes | Applies one atomic source revision; a shipped project forks only on its first effective edit. |
| `circ_select_entry` | Active project/source/target revisions and file name | Selects the visible compilation entry without reordering source. |
| `circ_set_compile_settings` | Target/options revisions and `warningsAsErrors` | Updates the shared compile option. |
| `circ_compile` | Active project/source/target/options revisions | Returns exact analyze and compile operation IDs; wait for the compile ID. |
| `circ_get_diagnostics` | Operation ID, optional source revision/cursor/limit | Returns retained compiler diagnostics with native UTF-8-byte and source UTF-16 locations. |

Mutation calls are revision guarded. Read `circ_get_status` and `circ_read_project` before a write, then use the returned project/source, target, workspace, and compile-setting revisions on the next call. A human edit or target change between the read and call returns a conflict and leaves the workspace unchanged. File-edit ranges are zero-based UTF-16, exclusive at the end, and may not split a surrogate pair. Rename warnings explicitly state that imports are not rewritten.

Successful authoring results include a persistence receipt. `saved` means the accepted active source was written to local storage; `memory_only` means the visible in-memory change succeeded but reload survival is not claimed. Tool inputs are JSON-safe and limited to 128 KiB; results remain limited to 32 KiB.

Diagnostic pages are tied to the operation's captured source and file map, not the current editor. Native ranges remain 1-based UTF-8-byte columns. When captured playground source is available, a file-local UTF-16 range and offsets are included; `currentlyEditable` is an observation at page time and can become false after a rename or later edit.

`circ_help` is read-only and never selects a project, creates a compiler or simulation session, starts a build, or changes memory/runtime state. Its generated corpus is pinned to a SHA-256 corpus ID and the committed compiler identity that validated its examples. Search accepts 1 through 10 results; read chunks use zero-based UTF-16 offsets, default to 4,096 code units, and require `expectedCorpusId` for continuation. `E014` and other validator codes resolve to their canonical `diagnostic:<code>` records; unknown codes return an empty successful search result rather than invented guidance. Complete examples retain sibling files, the default entry file, and normalized little-endian memory images labeled `load-before-driving-inputs`.

Knowledge assets are fetched lazily from same-origin `/agent-reference/` content-addressed JSON only after an invocation. Asset hashes and corpus/schema IDs are verified in the browser. `HELP_UNAVAILABLE`, `HELP_INVALID_CORPUS`, `HELP_CORPUS_CHANGED`, `HELP_NOT_FOUND`, `HELP_REMOVED`, and `HELP_BUSY` are structured domain errors; a valid search with no match is successful data.

Waits never start or cancel compiler/runtime work. They default to 5 seconds and allow 0 through 30 seconds. A timeout leaves work running. Suspension returns `PAGE_SUSPENDED`, disposal returns `PAGE_DISPOSED`, and a caller cancellation returns `WAIT_CANCELLED`.

The page registry is available at `window.circPlayground`:

```js
async () => window.circPlayground?.listTools()
async () => window.circPlayground?.callTool('circ_get_status', {})
async () => window.circPlayground?.callTool('circ_list_projects', { limit: 20 })
```

Select the target tab through the installed browser tool before evaluating either expression. Discover schemas before calling tools. Pass user text as browser-tool arguments, never by interpolating it into evaluated JavaScript.

## Native WebMCP

When the browser exposes `document.modelContext.registerTool` or `navigator.modelContext.registerTool`, the page registers the same descriptor and routes calls through the same registry. The native callback returns one text content block containing the JSON `ToolResult`; aborting the registration signal tears it down. Missing or rejected native registration leaves the page registry and human UI usable.

On bfcache suspension the registry reports `PAGE_SUSPENDED` and native exposure is removed. A restored cached page keeps its page ID and re-registers. A normal unload disposes the facade; rediscover after reload.

## External Clients

OpenCode and Claude Code use separately configured Chrome DevTools MCP or equivalent existing browser tooling. The documented fallback is `evaluate_script` over the page registry. Chrome DevTools MCP's WebMCP tools require its experimental WebMCP category; exact release, Chrome, Node, attachment mode, and flags must be recorded for each acceptance run.

Use a clean browser profile for each client. A separately launched browser has separate local playground storage.

## Limits And Privacy

- Invalid inputs and unknown tools return structured application errors.
- Native-provider rejection before the page callback is a provider error, not an application result.
- The source/share fragment is scrubbed before deferred page integrations run, but this is not a claim that the page makes no network requests.
- Source is exposed only by explicit bounded `circ_read_file` calls. Memory images, diagnostics payloads, compilation, simulation mutations, and exports remain unavailable in this phase.

## Compatibility Evidence

| Client / product | App + browser version | Connection tool version / mode | Page origin + tested commit | API variant | Discovery evidence | Status-call evidence | Result |
|------------------|-----------------------|--------------------------------|----------------------------|-------------|--------------------|----------------------|--------|
| ChatGPT Desktop | Product/browser version not exposed by the client | Native WebMCP | `http://localhost:4321/playground`, uncommitted Phase 0 worktree | `document.modelContext.registerTool` | `circ_get_status` discovered with `{}`-only schema | Two successful calls across reload | Pass |
| OpenCode 1.18.30 | Attached Chrome 153.0.0.0 | Chrome DevTools MCP with WebMCP tools | `http://localhost:4321/playground`, uncommitted Phase 0 worktree | Page registry and `document.modelContext.registerTool` | Both paths discovered before and after reload | Both paths invoked successfully before and after reload | Pass |
| Claude Code 2.1.269 | Installed, no attached browser | Chrome DevTools MCP 1.9.0 not configured/attached | Not run | Page registry fallback | Pending actual client | Pending actual client | Blocked: no Chrome/browser-tool connection |

The implementation’s automated tests prove the registry and adapter boundary only. They are not evidence that any listed client discovered or invoked a tool.

### Phase 1 local acceptance, 2026-09-12

Chrome DevTools MCP on Chrome 153.0.0.0 opened this worktree's built site at `http://127.0.0.1:4322/playground`. Native WebMCP discovered all five Phase 1 tools. Native and page-registry calls returned tracked status, a revision-bound project page, an active-project manifest, and a bounded source chunk without changing the selected project. Waiting through the page registry on the already scheduled session-build operation returned its terminal succeeded record with the same artifact, session, and image revisions status then reported. This was an observational acceptance run; no source, project, or runtime mutation was performed.

### ChatGPT Desktop acceptance, 2026-09-12

ChatGPT Desktop discovered `circ_get_status`, invoked it with exactly `{}`, reloaded the same local playground tab, rediscovered the same `{}`-only schema, and invoked it again. The app/product and embedded-browser version were not exposed by the client context. No project edits or visible UI controls were used.

First call:

```json
{"apiVersion":1,"pageId":"e53efd77-7f0b-4234-8080-d213138b2eb1","ok":true,"data":{"lifecycle":"ready","bootstrapError":null,"project":{"id":"example:inverter-chain","name":"NOT chain","entryFile":"main.circ","fileCount":1},"view":"truth","compiler":{"ready":true,"loading":false,"identity":{"version":"0.0.3","revision":"e8869c8","topologyVersion":3,"fullVersion":3,"grammarSha256":"fedba84c15900db11223fcfbb720ad1061b30d1b1ddbdde17385bdb99600992e"},"simulationCompatible":true},"reportedPipeline":{"kind":"live","analyzing":false,"building":false,"analyzePending":false,"buildPending":false,"errors":0,"warnings":0,"stale":false,"failure":null},"artifact":{"present":true,"bytes":23995},"session":{"present":true},"provenance":{"tracking":"untracked","sourceRevision":null,"buildRevision":null,"sessionId":null},"persistence":{"enabled":true},"agentAccess":{"pageRegistry":"available","native":{"state":"registered","apiVariant":"document.modelContext.registerTool","reason":null}}}}
```

After reload:

```json
{"apiVersion":1,"pageId":"d183bd30-ecf5-4643-ab59-33f5b90164f5","ok":true,"data":{"lifecycle":"ready","bootstrapError":null,"project":{"id":"example:inverter-chain","name":"NOT chain","entryFile":"main.circ","fileCount":1},"view":"truth","compiler":{"ready":true,"loading":false,"identity":{"version":"0.0.3","revision":"e8869c8","topologyVersion":3,"fullVersion":3,"grammarSha256":"fedba84c15900db11223fcfbb720ad1061b30d1b1ddbdde17385bdb99600992e"},"simulationCompatible":true},"reportedPipeline":{"kind":"live","analyzing":false,"building":false,"analyzePending":false,"buildPending":false,"errors":0,"warnings":0,"stale":false,"failure":null},"artifact":{"present":true,"bytes":23995},"session":{"present":false},"provenance":{"tracking":"untracked","sourceRevision":null,"buildRevision":null,"sessionId":null},"persistence":{"enabled":true},"agentAccess":{"pageRegistry":"available","native":{"state":"registered","apiVariant":"document.modelContext.registerTool","reason":null}}}}
```

The page ID changed from `e53efd77-7f0b-4234-8080-d213138b2eb1` to `d183bd30-ecf5-4643-ab59-33f5b90164f5`, as required for a full reload. The project/compiler/artifact state remained coherent. The session was present before reload and absent afterward, which is expected because live sessions are page-memory-only. Native registration remained `registered` after reload.

### Claude Code page-registry acceptance, 2026-09-12

Claude Code 2.1.269 used the Claude in Chrome extension MCP server's JavaScript evaluation tool against Chrome 153.0.8010.36. The extension could address only its own tab group, so it navigated tab `75063019` to the local playground rather than attaching to an existing visible tab. It discovered and invoked the public page registry before and after re-navigation; no page errors were logged. Chrome DevTools MCP was not configured, so experimental native WebMCP tools were unavailable. This is acceptance evidence for the page-registry fallback only.

The first registry result had page ID `343b38f6-2ee3-4379-be0c-266db1cde365`; after reload it had `82eb3a3b-b9f3-489d-98d8-b061cf857a5a`. Both calls returned `ok: true`, the `NOT chain` project, compiler `0.0.3` / `e8869c8`, artifact `23995` bytes, `untracked` provenance, and native state `unsupported` because that Chrome profile exposed neither native model-context API. The full unredacted call output was supplied to the implementation session and matches the status contract. No mutation was performed.

### OpenCode Chrome DevTools MCP acceptance, 2026-09-12

The attached OpenCode 1.18.30 session used Chrome DevTools MCP against Chrome 153.0.0.0 at `http://localhost:4321/playground`. It discovered `circ_get_status` through both native WebMCP tooling and `window.circPlayground.listTools()`, then invoked it through both `execute_webmcp_tool` and the public registry with exactly `{}`. Native calls returned the same JSON `ToolResult` as page-registry calls.

Before reload, both paths returned `ok: true` for page ID `86096362-55d9-49b5-96a2-f160d16aea7c`. The initial snapshot correctly captured the observable startup state: `reportedPipeline.kind` was `compiling`, with no artifact or session yet present. The reload command exceeded its page-stabilization wait, but the navigation completed. Native rediscovery and both call paths then succeeded for a new page ID, `b9d112a9-87f3-4ba2-b214-bf4aa8a5dd09`, proving re-registration. The settled post-reload snapshot was `ready` / `live`, with compiler `0.0.3` / `e8869c8`, a `23995`-byte artifact, a present session, no errors or warnings, `untracked` provenance, and native state `registered` through `document.modelContext.registerTool`.

The same tab then navigated to `about:blank` and back. Both native and registry calls succeeded with the unchanged page ID `b9d112a9-87f3-4ba2-b214-bf4aa8a5dd09`, a live pipeline, and a present session, which demonstrates bfcache restore rather than a new document. No project mutation or visible UI control was used.

### Phase 3 native author-repair acceptance, 2026-09-12

Chrome DevTools MCP attached to Chrome 153.0.0.0 served this worktree's freshly built site at `http://127.0.0.1:4323/playground`. Native `document.modelContext.registerTool` discovered all thirteen tools, including the seven Phase 3 additions. A native call created `scratch:mtyqrikxe2l5` (`WebMCP repair proof`) with an invalid `main.circ`; its persistence receipt was `saved`, with source revision `...:source:106` and compile operation `...:operation:5`.

Waiting for that operation returned `diagnostics` with one error and one warning. `circ_get_diagnostics` returned compile-owned `E004` with captured `/playground/main.circ` native byte columns `2:1-2:18`, UTF-16 offsets `8-25`, and `currentlyEditable: true`. A revision-guarded UTF-16 edit replaced `missing` with `a`, yielding source revision `...:source:118`; explicit native `circ_compile` operation `...:operation:10` finished `succeeded` with artifact `...:artifact:125`. Final tracked status reported that source as both current and build provenance, a 23,913-byte artifact, enabled persistence, and no errors. A deliberately stale update against source `...:source:106` returned `REVISION_CONFLICT` without changing the repaired project. No console warnings/errors were emitted.
