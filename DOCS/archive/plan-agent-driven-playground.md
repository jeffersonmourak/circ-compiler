# Archived plan: agent-driven-playground

**Canonical commit:** `797b17bea753ea722dbedb89061484dae4a00e51` (`797b17b feat(site): add agent activity and project handoff`)
**Archived on:** 2026-09-12
**Plan duration:** 2026-09-12 → 2026-09-12

> This file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the commit referenced above. Use `git show 797b17bea753ea722dbedb89061484dae4a00e51:DOCS/PLANS_PROMPT.md`, or the corresponding path under `DOCS/PLANS/` or `DOCS/STATUS.md`, for the unabridged source.

**Closure:** Archived at the user's request after implementation, corrective work, and client walkthroughs. The user explicitly deferred the remaining storage/edge acceptance matrix. This is an implementation archive, **not full Phase 6 acceptance signoff**: the complete three-client matrix was not rerun against one frozen application commit. The canonical SHA preserves the delivered code and historical evidence; it does not retroactively identify the changing builds used in earlier client tests.

## Goal & scope

Make the visible `/playground` operable through native WebMCP and existing browser-control tooling, with one shared semantic tool registry over the browser's project model, compiler worker, and `SimSession`. Agents can read and edit named files, consult local language help, compile and repair diagnostics, drive and verify circuits, inspect outputs, and hand off source or downloads. Compilation, simulation, storage, and knowledge search remain browser-local on a statically deployed Astro site; no application backend, relay, custom HTTP/WebSocket bridge, or browser extension was added. Requested tool arguments/results are shared with the connected client. Source/image/runtime ownership remains explicit, and compiled topology is not mutated by agents.

## Phase-by-phase highlights

### Phase 0 — Connection contract and first tool

Expose observational status through native and external browser access before adding mutations.

- Added the typed `ToolResult`, detached status controller, schema-bearing registry, and frozen `window.circPlayground` facade.
- Registered `circ_get_status({})` with optional native WebMCP and a page-evaluation fallback; initial provenance was explicitly `untracked`.
- Isolated native absence/failure from the human UI; guarded registration generations and `pagehide`/`pageshow` lifecycle.
- Recorded real ChatGPT native, OpenCode native/page-registry, and Claude Code page-registry discovery/call evidence.

Native receiver detection was extended from `document.modelContext.registerTool` to also support `navigator.modelContext.registerTool`. Claude Code used the existing Claude in Chrome extension instead of Chrome DevTools MCP in its recorded fallback run.

### Phase 1 — Observable, revision-aware playground

Expose exact project/file reads and distinguish current source from the inputs behind displayed outputs and running operations.

- Added page-scoped source/project/image/target identities and operation summaries with supersession, terminal outcomes, and bounded waits.
- Added project listing, manifests, and UTF-16 file chunks with active-buffer precedence and revision conflicts.
- Captured analyze/compile inputs before awaits; corrected `warnings_as_errors`, compile-metadata deduplication, and fatal worker handling.
- Tracked preview/compiler Truth/scratch Truth and session lifecycle, including preload counts and reset-after-destruction protection.
- Published tracked status and `circ_wait_for_operation`; registered the complete native catalogue and exercised read/wait paths in Chrome.

The local ARM64 Bun/x64 Node mismatch required explicit macOS Rollup host packages. Operation waiting does not preempt synchronous WASM, and scratch Truth can delay timer delivery while it runs.

### Phase 2 — Language reference and example help

Provide local, cited reference lookup and complete examples without selecting projects or invoking the live compiler.

- Added lazy `circ_help` search/read/example actions over generated reference, diagnostic, and gallery/tour records.
- Generated compiler/corpus identities and named-file/image example payloads; compiled all 21 indexed examples with committed `libcirc.wasm`.
- Published simulation-protocol and tour Markdown references and included memory initialization in the gallery mirror.
- Exercised `diagnostic:E014`, the imported full-adder, and RAM example retrieval with unchanged live project/session state.

Acceptance corrected the canonical ID to `tour-example:full-adder-imports`, retaining `tour-example:imported-half-adder` as an alias. The RAM example's image is initial runtime data, not a persisted ROM source preload.

### Phase 3 — Author, compile, and repair

Let agents author the visible project against explicit revisions and retrieve the diagnostics produced by their compile.

- Added scratch create/open, ordered file edit/create/rename/delete, entry selection, and compile-setting tools.
- Added mutation planning, external editor transactions, example forking, and structured persistence receipts.
- Exposed exact-input compile start/join/reuse and operation-bound diagnostics with UTF-8 and UTF-16 locations.
- Recorded native author/repair and stale-revision refusal; final acceptance also exercised a two-file `E014` repair and all eight adder vectors.

Acceptance added `workspaceRevision` to tracked status so create/open preconditions can be obtained directly. Ordinary file rename does not rewrite imports.

### Phase 4 — Drive and verify circuits

Operate one visible simulation session and run separate verification sessions with lossless values and explicit identity checks.

- Added session discovery/preparation, ordered drive/reset, root ROM/RAM reads, and live poke/clear/load.
- Added source-owned ROM preload mutation and isolated case/step/assertion verification with retained results.
- Exercised stale live-write rejection, reset identity rotation, ROM application, and verification preserving live state.
- Claude Code verified RAM load `0xa5`, clocked write `0x3c`, reset to undefined, and four half-adder cases with eight passing assertions.

Live memory access remains root-only. Persisted preloads remain ROM-only: `circ_set_memory_preload` returns `PRELOAD_CONFLICT` for RAM. The Phase 6 procedure was corrected, with user approval, to assert that reset clears live RAM instead of restoring its fixture image.

### Phase 5 — Inspect and hand off the workbench

Expose bounded inspection and visible controls, and state exactly what each source/share/download handoff contains.

- Added schematic requests/text, artifact topology pages, and exhaustive/filtered Truth requests/results.
- Added workbench settings, view/Data, and declaration highlight tools over existing visible state.
- Added source/share/transcript retrieval and artifact/live-memory/source-preload download dispatch receipts.
- Exercised native and page-registry inspection, handoff omissions, and visible workbench agreement.

Source/share formats retain ordered marker text and do not encode a separately selected non-last entry. They also omit images and live state. Downloads report `dispatched` with `completionKnown: false`; filesystem capture is external evidence.

### Phase 6 — Acceptance, corrections, and documentation

Exercise real client workflows and publish accurate setup, lifecycle, privacy, and evidence documentation.

- Published `DOCS/agent-playground.md` at `/reference/agent-playground`, including its Markdown twin, and linked the guide from README and decisions.
- Corrected stable example IDs, workspace preconditions, JSON-safe `circ_set_view` receipts, and nested simulation schemas.
- Made native registration transactional; removed the trial `unload` fallback after it impaired bfcache eligibility.
- Recorded fresh ChatGPT/Codex native RAM/reload success, Claude Code fallback workflows, and OpenCode native/page-registry workflows.
- Captured artifact downloads externally and demonstrated same-page bfcache restoration in attached Chrome.

The latest recorded native discovery contains **35 tools**. Earlier STATUS entries recorded smaller counts during registration/testing; those counts are historical observations, not the final catalogue.

#### Decisive client and download evidence

| Context | Recorded result |
| --- | --- |
| Fresh ChatGPT/Codex in-app browser; product/browser versions unavailable | Native RAM load/drive returned `q=0xa5`, `defined=0xff`. Reload changed page `0ef4663c-4eb6-4c97-8b22-c7dfdf107403` to `8cc82824-3d76-4bc5-9a11-e67acd2c3da4`; native status succeeded after rediscovery. Earlier stale-registration attempts remain in history. |
| Claude Code 2.1.270, Chrome 153.0.8010.36, Claude in Chrome MCP | Page-registry RAM load/write/reset, half-adder verification, schematic/topology/Truth, text handoff, and reload passed. Native API was unsupported. Reload restored the half-adder and replaced the page ID. Its Back navigation was a new document, not bfcache. |
| OpenCode with attached Chrome DevTools tooling; Chrome reported 153.0.0.0 | Native and page-registry author/repair, simulation, inspection, and reload evidence recorded. After removing `unload`, `/playground` → `/gallery` → Back preserved page `331221c6-734a-48da-8c90-4991ecee286d`; native status succeeded. |
| `half-adder.wasm` filesystem capture | 25,140 bytes, matching the Claude receipt; SHA-256 `71a2521b4fc6ad0164a2e883aa96574b2c0ad8975ee6e012b41eef192c5133ba`. |
| `not-chain.wasm` filesystem capture | 23,995 bytes; SHA-256 `9f674cf5810c67b3959f91fdc232e6f43380f92c03225d035cd9eca191bf738e`. |

These are scoped observations across iterative builds, not a claim that every client passed every planned scenario on the canonical SHA. The storage/quota and complete edge matrices were deferred at the user's request; the unified frozen-commit rerun was not performed.

### Follow-up — Agent activity and project handoff

- Added a status-line activity indicator through shared dispatch, with no persistent-connection or agent-identity claim.
- Added **Connect agent** beside Share: copied instructions include the active source Share URL, project name, and selected entry.
- Oversized source is carried as JSON in the prompt for import; denied clipboard access offers a selected multiline fallback.
- `site/test/agent-connect.test.ts` proves captured multi-file source round-trip and over-cap source retention; built-island coverage exercises clipboard success/failure.

The handoff includes unsaved editor contents but retains Share's source-only model. The prompt tells the recipient to restore the source in a new tab and select the supplied entry before further work.

## API surface frozen by the plan

The registry is the discoverable schema source. `site/src/scripts/playground-contract.ts` and the `agent-tools/` descriptors carry exact DTOs and error vocabulary.

| Family | Public names |
| --- | --- |
| Facade | `window.circPlayground.apiVersion`, `pageId`, `listTools()`, `callTool(name, input)` |
| Observation | `circ_get_status`, `circ_list_projects`, `circ_read_project`, `circ_read_file`, `circ_wait_for_operation` |
| Knowledge | `circ_help` (`search`, `read`, `example`) |
| Authoring/compiler | `circ_create_project`, `circ_open_project`, `circ_update_project`, `circ_select_entry`, `circ_set_compile_settings`, `circ_compile`, `circ_get_diagnostics` |
| Simulation | `circ_get_simulation`, `circ_prepare_simulation`, `circ_drive`, `circ_reset`, `circ_read_memory`, `circ_update_memory`, `circ_set_memory_preload` |
| Verification | `circ_run_verification`, `circ_get_verification` |
| Inspection | `circ_request_schematic`, `circ_get_schematic`, `circ_get_topology`, `circ_request_truth_table`, `circ_get_truth_table` |
| Workbench | `circ_set_workbench_settings`, `circ_set_view`, `circ_highlight` |
| Handoff | `circ_export_source`, `circ_create_share_link`, `circ_download_artifact`, `circ_download_memory`, `circ_get_transcript` |

- API v1 envelopes include `pageId`, `ok`, and `data` or a structured `error`. Serialized input/result limits are 128 KiB/32 KiB.
- Expected revisions distinguish source, target, options, artifact, image, session, and live-state ownership. Phase 0's temporary `untracked` status was extended with tracked output and operation fields.
- Values and masks use lossless hexadecimal strings. Drives settle in array order. Reset floats pins; source ROM preloads and ephemeral live RAM have different lifetimes.
- Source/share use the existing `src`/`src0` fragment codec with an 8,192-character payload cap. No new localStorage key or persistent schema migration was introduced.
- This initiative added no compiler diagnostic code, CLI flag, WASM export, or topology version. Existing `E001`–`E018`, `W001`–`W003`, syntax diagnostics, `--sim`, and runtime memory APIs remain owned by their living specs.

## Known papercuts carried forward

- The deferred storage/quota and complete native/page-registry edge matrices, and a single frozen-commit three-client rerun, are still needed for the original Phase 6 signoff.
- Historical client walkthroughs do not exhaustively prove all planned range, retention, quota, cancellation, or concurrency assertions. Use the canonical specs to scope a future acceptance pass.
- Some client/tool/browser versions were unavailable. ChatGPT/Codex stale-registration errors disappeared in a fresh-session retest; this is not universal browser compatibility evidence.
- Browser tools may use a separate profile or only their extension's tab group. Projects/live state are not shared across those contexts; Connect agent transfers a source snapshot.
- Native per-request cancellation depends on host support. A timeout/cancelled wait is not worker or synchronous WASM preemption.
- `unload` listeners can disqualify bfcache. Keep native teardown on the existing `pagehide`/`pageshow` lifecycle and test actual restoration separately from Back navigation.
- ROM source images, live RAM/pins, settings, and compiled bytes are not bundled into source/share handoffs. Export images separately for memory-circuit reproduction.
- The local macOS toolchain used ARM64 Bun alongside x64 Node; the Rollup host-package workaround remains in site dependencies.
- Preserve the canonical commit if squashing the PR: the archive's `git show` instructions require that object to remain reachable in repository history.

## Decisions & specs that survived the plan

- [Agent Playground](../agent-playground.md): setup, public tool workflow, client evidence, activity indicator, and Connect agent handoff.
- [Agent playground decisions](../decisions/agent-playground.md): dual access, provenance, native lifecycle, disclosure, and RAM acceptance policy.
- [Playground decisions](../decisions/playground.md) and [workbench decisions](../decisions/playground-bench.md): editor history, active entry, shared session, storage, and source-image ownership.
- [Simulation protocol](../sim-protocol.md): ordered drives, reset, and root memory behavior.
- [Analyze API](../analyze-api.md) and [libcirc API](../libcirc-api.md): compiler requests, status codes, and diagnostic mapping.
- [Language](../language.md), [circuit format](../circuit-format.md), [preview](../preview.md), and [WASM API](../wasm-api.md): canonical corpus inputs and runtime/reference contracts.
- `site/src/scripts/playground-contract.ts`, `site/src/scripts/agent-tools/`, and `site/scripts/build-agent-reference.ts`: shipped public schemas, dispatch, and generated corpus ownership.
