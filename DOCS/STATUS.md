## 2026-09-12 — Phase 0 — Connection contract and first tool

**What shipped:** Added the typed `circ_get_status` contract, observational controller, shared registry, public `window.circPlayground` facade, lifecycle gates, and `document.modelContext.registerTool` adapter. The visible playground now accurately states that connected agents receive requested results.
**Files touched:** `site/src/scripts/playground-contract.ts`, `site/src/scripts/playground-controller.ts`, `site/src/scripts/agent-tools/`, `site/src/scripts/webmcp-adapter.ts`, `site/src/components/Playground.astro`, `site/test/playground-controller.test.ts`, `site/test/agent-tools.test.ts`, `site/test/webmcp-adapter.test.ts`, `site/test/island-smoke.test.ts`, `DOCS/agent-playground.md`, `DOCS/decisions/agent-playground.md`, `DOCS/index.md`, `DOCS/decisions/index.md`
**Tests:** added controller/registry/native-adapter and built-island public-registry coverage; ran `bun --bun run typecheck && bun --bun run build && bun test && bun run bundle`, result pass (641 tests; `/playground` 50.4 KiB gzip under the 120 KiB ceiling).
**Next slice:** Phase 0 real-client acceptance is blocked pending access to the exact ChatGPT browser-integrated environment and separately configured OpenCode/Claude Code browser tooling.
**Notes:** The native mapping uses the WebMCP explainer's `document.modelContext.registerTool` with abort-signal teardown and a JSON `ToolResult` text content block. OpenCode 1.18.30 and Claude Code 2.1.269 are installed; Chrome DevTools MCP 1.9.0 is available from npm, but no Chrome installation or configured browser-tool connection is available. There is also no ChatGPT session/browser product, so no real discovery/call, reload, bfcache, or external fallback evidence was claimed.

## 2026-09-12 — Phase 0 — ChatGPT Desktop native acceptance

**What shipped:** ChatGPT Desktop discovered `circ_get_status`, invoked it successfully, then rediscovered and invoked it again after a full reload of `http://localhost:4321/playground`.
**Files touched:** `DOCS/agent-playground.md`, `DOCS/STATUS.md`
**Tests:** recorded actual native tool calls; first page ID `e53efd77-7f0b-4234-8080-d213138b2eb1`, post-reload page ID `d183bd30-ecf5-4643-ab59-33f5b90164f5`; result pass.
**Next slice:** Configure Chrome/browser tooling for OpenCode and Claude Code, then record external discovery, page-registry fallback, and lifecycle evidence.
**Notes:** The client did not expose ChatGPT Desktop or embedded-browser versions. Both status results reported native `registered` using `document.modelContext.registerTool`, the same `NOT chain` project/compiler identity, and no errors. The pre-reload session was present; the post-reload session was absent, as live session state is page-memory-only. No user-visible project mutation was performed.

## 2026-09-12 — Phase 0 — Claude Code page-registry acceptance

**What shipped:** Claude Code 2.1.269 discovered and invoked `circ_get_status` through the public page registry in Chrome 153.0.8010.36, before and after reload.
**Files touched:** `site/src/scripts/webmcp-adapter.ts`, `site/test/webmcp-adapter.test.ts`, `DOCS/agent-playground.md`, `DOCS/STATUS.md`
**Tests:** added document/navigator native-context detection coverage; external fallback calls returned `ok: true` with page IDs `343b38f6-2ee3-4379-be0c-266db1cde365` and `82eb3a3b-b9f3-489d-98d8-b061cf857a5a`; result pass.
**Next slice:** Configure OpenCode browser tooling and record the equivalent external acceptance; independently validate native WebMCP through Chrome DevTools MCP where available.
**Notes:** Chrome DevTools MCP was not configured. The Claude in Chrome extension's JavaScript evaluator could access only its own tab group, so it navigated that tab to the local playground. Native WebMCP was absent in that profile and correctly reported unsupported; this is page-registry fallback evidence, not a native-WebMCP pass. The exploratory Claude extension probe is intentionally not recorded.

## 2026-09-12 — Phase 0 — OpenCode Chrome DevTools MCP acceptance

**What shipped:** OpenCode discovered and invoked `circ_get_status` through both Chrome DevTools MCP's native WebMCP tools and the public page registry, before and after reload.
**Files touched:** `DOCS/agent-playground.md`, `DOCS/STATUS.md`
**Tests:** Chrome 153.0.0.0 returned `ok: true` for native and page-registry calls; page ID changed from `86096362-55d9-49b5-96a2-f160d16aea7c` to `b9d112a9-87f3-4ba2-b214-bf4aa8a5dd09` after reload; navigation to `about:blank` and back preserved the latter page ID and session across successful native/page-registry calls; result pass.
**Next slice:** Review and commit Phase 0.
**Notes:** The first call observed the expected startup `compiling` state without an artifact/session. The post-reload call observed the settled `live` state with a 23995-byte artifact and session. The reload command timed out waiting for DOM stabilization, but page replacement, native tool rediscovery, and both successful post-reload calls confirm that the reload completed and registration was recreated. The back navigation preserved page ID and session, demonstrating bfcache restore. No mutation was performed.

## 2026-09-12 — Phase 1, Slice 1 — Revision and operation primitives

**What shipped:** Added pure page-scoped revision allocation/tracking, detached source/image/input snapshots, byte-and-file-mapping artifact comparison, and bounded operation lifecycle/wait primitives.
**Files touched:** `site/src/scripts/playground-contract.ts`, `site/src/scripts/playground-revisions.ts`, `site/src/scripts/playground-operations.ts`, `site/test/playground-revisions.test.ts`, `site/test/playground-operations.test.ts`, `DOCS/STATUS.md`
**Tests:** `bun test test/playground-revisions.test.ts test/playground-operations.test.ts` (11 pass) and `bun --bun run typecheck` (pass).
**Next slice:** Wire the project/source tracker into existing workspace mutation boundaries and expose bounded project/file read tools.
**Notes:** The new primitives are not yet connected to the Astro island, compiler pipeline, or public registry. Phase 0 continues to return explicitly untracked status until those real input/output boundaries are covered.

## 2026-09-12 — Phase 1, Slice 2 — Workspace reads

**What shipped:** Registered bounded project/file read tools backed by an island-owned, revisioned in-memory workspace snapshot. Active editor buffers take precedence over persisted scratch records; inactive scratch and catalogue projects remain read-only and do not change selection.
**Files touched:** `site/src/components/Playground.astro`, `site/src/scripts/playground-controller.ts`, `site/src/scripts/agent-tools/{registry,page-api,workspace}.ts`, `site/src/scripts/playground-contract.ts`, `site/test/{agent-tools,playground-controller}.test.ts`
**Tests:** `bun test test/playground-revisions.test.ts test/playground-operations.test.ts test/playground-reads.test.ts test/playground-controller.test.ts test/agent-tools.test.ts` (24 pass) and `bun --bun run typecheck` (pass; existing hints only).
**Next slice:** Connect captured analyze/compile request provenance and terminal outcomes before exposing tracked status or operation waits.
**Notes:** `circ_get_status` deliberately remains untracked. Waiting is not public yet because no actual pipeline operation IDs are assigned at scheduling/publication boundaries.

## 2026-09-12 — Phase 1, Slice 3 — Analyze and compile provenance

**What shipped:** Analyze and compile now receive queued operation records at scheduling time with copied request bodies/options, transition to running before compiler readiness, and finalize as succeeded, diagnostics, refused, failed, or superseded. A later source/target/settings request supersedes its logical predecessor immediately; delayed worker replies cannot publish after ownership changes. Compile now sends `warnings_as_errors` and skips with a diagnostics outcome when fresh analysis proves it cannot succeed. The worker client records fatal transport failure and rejects future work.
**Files touched:** `site/src/components/Playground.astro`, `site/src/scripts/libcirc-client.ts`, `site/test/island-smoke.test.ts`
**Tests:** `bun test test/pipeline.test.ts test/playground-operations.test.ts test/playground-revisions.test.ts test/shared-client.test.ts test/agent-tools.test.ts test/playground-controller.test.ts` (40 pass); `bun --bun run typecheck` (pass; existing hints only).
**Next slice:** Track independent preview/Truth/session operation provenance and runtime lifecycle before publishing tracked status or operation waits.
**Notes:** The production build and rebuilt island smoke test remain blocked in this worktree because the installed Rollup package lacks `@rollup/rollup-darwin-x64`; `bun install --frozen-lockfile` reported no changes and did not repair the missing optional dependency. Public status and tool registration remain unchanged.

## 2026-09-12 — Phase 1, Slices 4–5 — Derived observations and waits

**What shipped:** Preview and compiler Truth requests now have their own captured operation records and output provenance. Lazy session construction has a runtime operation record and records a session identity/live-state revision. `circ_get_status` publishes tracked revision/output/operation/session/transport fields after bootstrap; `circ_wait_for_operation` observes retained records with bounded timeout and page-lifecycle cancellation. Native registration now registers the complete public catalogue rather than only status.
**Files touched:** `site/src/components/Playground.astro`, `site/src/scripts/{playground-contract,playground-controller,webmcp-adapter}.ts`, `site/src/scripts/agent-tools/{operations,page-api,status}.ts`, `site/test/playground-controller.test.ts`
**Tests:** `bun --bun run typecheck` (pass; existing hints only); targeted controller/registry/adapter/operation tests pass.
**Notes:** Superseded worker work remains physical work; a wait timeout never claims preemption. Scratch Truth's synchronous bounded enumeration can delay JavaScript timer delivery until it returns.

## 2026-09-12 — Phase 1 completion — lifecycle and integration closure

**What shipped:** Fixed tracked built-island expectations and deduplicated compile metadata analysis against the optionless analyze request. Scratch Truth now records its own captured artifact/image/fixed-input provenance and terminal path. `SimSession` publishes isolated reset/run lifecycle observations, retains bounded initial/reset preload results, and discards a late reset runtime after destruction. Status now reports reset/build state, actual preload counts, image binding, and image freshness; waits distinguish suspension and disposal from caller cancellation. Added both Rollup host packages at the installed Rollup version so a rebuilt site can run on either macOS architecture.
**Files touched:** `site/src/components/Playground.astro`, `site/src/scripts/{sim-session,truth-view,playground-contract,playground-controller,playground-operations}.ts`, `site/src/scripts/agent-tools/page-api.ts`, `site/test/{island-smoke,sim-session,truth-view,playground-controller}.test.ts`, `site/package.json`, `site/bun.lock`, `DOCS/{agent-playground,STATUS}.md`
**Tests:** `bun --bun run typecheck && bun test && bun run bundle` (663 pass; `/playground` 57.4 KiB gzip under 120 KiB); rebuilt `bun --bun run build`; focused rebuilt island/lifecycle/Truth/controller run (66 pass).
**Next slice:** Phase 2; Phase 1 exposes observations only and intentionally defers agent mutations, diagnostic payload retrieval, and simulation/memory controls.
**Notes:** Chrome DevTools MCP on Chrome 153.0.0.0 served this worktree's `dist` at `http://127.0.0.1:4322/playground`. Native WebMCP discovered all five tools and returned tracked status; native/page-registry project, manifest, and bounded file reads succeeded. Waiting on session-build operation `7542c87d-77e7-4a64-a810-6ef7a5558137:operation:3` returned its terminal succeeded result with matching artifact/session/image provenance. No user project mutation was performed. IDs and operation records are page-memory-only.

## 2026-09-12 — Phase 2 — Language reference and example help

**What shipped:** Added `circ_help` with lazy local search, bounded record reads, exact diagnostic lookup, and complete gallery/tour example delivery. The deterministic generated corpus includes all six public references, validator diagnostics, named sibling files, and ROM/RAM initialization metadata, linked to a compiler/corpus identity.
**Files touched:** `site/src/scripts/{knowledge-*,agent-tools/help}.ts`, `site/scripts/{build-agent-reference,build-llm-mirror,sync-reference}.ts`, `site/src/content/{agent-reference,tour,examples}.ts`, reference registry/page integration, tests, and agent documentation.
**Tests:** generated corpus using committed `libcirc.wasm` (21 examples compiled); `bun --bun run typecheck && bun --bun run build && bun test && bun run bundle` passed (667 tests; `/playground` 58.0 KiB gzip under 120 KiB).
**Next slice:** Run fresh built-site native/page-registry acceptance for `circ_help`; Phase 3 remains deferred until Phase 2 acceptance is recorded.
**Notes:** Chrome 153.0.0.0 native WebMCP at `http://127.0.0.1:4322/playground` discovered `circ_help`; `E014` ranked first with circuit-format citations and matching compiler identity `0.0.3/e8869c8`, the imported full-adder returned `half_adder.circ` and `root.circ`, and the RAM example returned its `data` initialization image. Status before/after retained the same project, source/build/session IDs and operation IDs. Help is observational: it does not initialize compiler/simulator state or mutate projects. The generated `/agent-reference/` tree is intentionally ignored and rebuilt before Astro builds.

## 2026-09-12 — Phase 3 — Author, compile, and repair

**What shipped:** Added revision-guarded authoring, explicit compile, and diagnostic tools; ordered atomic file mutation planning; historical diagnostic conversion and bounded retention; external CodeMirror document replacement; and structured persistence receipts.
**Files touched:** `site/src/scripts/{playground-mutations,playground-diagnostics,playground-contract,playground-controller,circ-editor}.ts`, `site/src/scripts/agent-tools/{authoring,compiler,registry,page-api}.ts`, `site/src/components/Playground.astro`, store/tests/docs.
**Tests:** `bun --bun run typecheck && bun --bun run build && bun test && bun run bundle` passed (672 tests; `/playground` 64.2 KiB gzip under 120 KiB). Focused mutation/diagnostic/controller/registry tests passed (17 tests). Native Chrome acceptance at `http://127.0.0.1:4323/playground` discovered all 13 tools, created an invalid scratch project, retrieved compile-owned `E004`, repaired it through a revision-guarded UTF-16 edit, explicitly compiled a current artifact, and proved a stale update inert with `REVISION_CONFLICT`.

## 2026-09-12 - Phase 4 - Drive and verify circuits

**What shipped:** Added revision/session-guarded simulation discovery, preparation, ordered pin drive/reset, root-memory reads/mutations, source ROM preloads, and isolated bounded verification through the shared browser registry.
**Files touched:** `site/src/scripts/{playground-contract,playground-controller,playground-simulation,playground-verification}.ts`, `site/src/scripts/agent-tools/{page-api,simulation,verification}.ts`, `site/src/components/Playground.astro`, tests, and agent/protocol docs.
**Tests:** `bun --bun run typecheck && bun --bun run build && bun test && bun run bundle` passed (678 tests; `/playground` 71.3 KiB gzip under the 120 KiB ceiling). Browser acceptance at `http://127.0.0.1:4321/playground` discovered all 21 tools through the public registry with native registration active; drove a live pin, loaded/read a root ROM, updated its source preload, replaced a reset session identity, rejected a stale drive, and ran a passing disposable verification without changing the live session revision.
**Next slice:** Record independent external-client/native-tool invocation acceptance if required for release.

## 2026-09-12 - Phase 5 - Inspect and hand off the workbench

**What shipped:** Added bounded, revision-aware schematic, full-topology, and Truth inspection; visible workbench settings/view/Data/highlight controls; source/share/transcript handoff; and dispatch-only artifact or memory download receipts. Source/share output explicitly omits images, live state, settings, transcript, and artifacts as applicable. The public registry now exposes all 13 Phase 5 tools through the same page and native WebMCP dispatch paths.
**Files touched:** `site/src/components/Playground.astro`, `site/src/scripts/{playground-contract,playground-controller,playground-inspection,playground-topology,playground-handoff}.ts`, `site/src/scripts/agent-tools/{page-api,inspection,workbench,exports}.ts`, `site/test/{playground-inspection,playground-topology,playground-handoff,island-smoke}.test.ts`, `DOCS/{agent-playground,STATUS}.md`
**Tests:** `bun test` (682 pass), `bun --bun run build`, `bun --bun run typecheck` (0 errors), and `bun run bundle` passed (`/playground` 78.1 KiB gzip under the 120 KiB ceiling).
**Notes:** Native Chrome WebMCP at `http://127.0.0.1:4324/playground` registered all Phase 5 tools. It returned an exact 3-row schematic, 5-component flattened topology, exhaustive 2-row Truth result, revision-bound source/share/transcript payloads with omissions, and a persisted Schematic/Data view transition. Browser download dispatch was not exercised to avoid creating an unsolicited local download; its receipt-only behavior has focused unit coverage.

## 2026-09-12 - Phase 6 - Documentation, gate, and partial OpenCode acceptance

**What shipped:** Registered the canonical agent guide at `/reference/agent-playground` with a Markdown twin and LLM-mirror inclusion; updated the playground disclosure to distinguish browser-local computation/no application backend from requested connected-agent results; finalized the guide's setup, lifecycle, limits, privacy, troubleshooting, evidence, and blocker sections; and added focused guide-registration, disclosure, and route-local agent-graph assertions.

**Files touched:** `DOCS/{agent-playground,STATUS}.md`, `DOCS/decisions/{agent-playground,index}.md`, `DOCS/index.md`, `README.md`, `site/scripts/lib/site-config.ts`, `site/src/{components/Playground.astro,pages/playground.astro}`, `site/test/{bundle-graph,island-smoke,site-labels}.test.ts`.

**Tests:** With Bun `1.2.10` and Node `v24.20.0`, ran `bun --bun run typecheck && bun --bun run build && bun test && bun run bundle` from `site/`: pass, 684 tests/0 failures; `/playground` 78.1 KiB gzip under the 120 KiB ceiling; `/reference/agent-playground` and its Markdown twin generated. The check emitted existing TypeScript/Astro warnings only. Other preview/dev processes already existed and were not terminated, so the plan's no-server-during-build procedural condition is not independently attested.

**Browser evidence:** OpenCode used attached Chrome DevTools tooling on the visible `http://127.0.0.1:4324/playground` tab. The application commit was `7af1faafb18770d677a19d5e559953662dd9ea52`; the built tree also contained uncommitted Phase 6 documentation/copy-only changes, so this is not final frozen-commit acceptance. Chrome reported `153.0.0.0`; native `document.modelContext.registerTool` discovered all 33 tools before and after reload. Native `circ_get_status` and `circ_help(diagnostic:E014)` passed with compiler `0.0.3/e8869c8`, corpus `ef1f2fb0918d8fad1248b957784557442b26140e432751767ac091428ecd42c7`, and matching active compiler/corpus identity. Page-registry discovery also returned 33 tools; malformed known input returned application `INVALID_ARGUMENT`, and `phase6_unknown_tool` returned application `UNKNOWN_TOOL`. On NOT chain, page-registry drive `a=0x0` returned `out=0x1/defined=0x1`; isolated verification passed 2 cases/2 steps/2 assertions; schematic, 5-component/4-connection topology, exhaustive two-row Truth, visible Truth/Data agreement, source/share/transcript omissions, and native artifact dispatch passed. Dispatch receipt `21bc63f2-be10-4d7d-854a-19aeee8ee733:download:126` was `not-chain.wasm`, 23,995 bytes, `dispatched`, completion unknown. Reload changed page ID from `21bc63f2-be10-4d7d-854a-19aeee8ee733` to `7c0160e4-e1f0-4f4d-a440-9782e0594ce6` and native registration rediscovered successfully.

**Blockers:** Phase 6 is incomplete. Mandatory `circ_help` ID `tour-example:full-adder-imports` returns `HELP_NOT_FOUND`; corpus search returns `tour-example:imported-half-adder` instead, which may not be substituted under the plan. `circ_create_project` and `circ_open_project` require `expectedWorkspaceRevision`, but tracked `circ_get_status` does not publish it; a status-derived create call returned `REVISION_CONFLICT`, blocking the required author/repair and all clean-profile project workflows. Correcting either is a public corpus/DTO contract change and requires owning-phase/human approval. ChatGPT supported browser-integrated evidence and Claude Code configured-client evidence are unavailable. Browser download dispatch ran, but this attached tooling cannot externally capture/download/hash the file. The complete native/page-registry edge matrix, persistence/new-profile/bfcache, half-adder, RAM/ROM, memory handoff, and per-client final workflows were not claimed.

**Next work:** Obtain approval for the Phase 2 stable-ID correction and Phase 3 status/create contract correction; commit a corrective application slice, rebuild from a stopped-server environment, then restart all clean-profile client and edge acceptance runs against one frozen application commit.

## 2026-09-12 - Phase 6 - Stable corpus and workspace-precondition correction

**What shipped:** Restored `tour-example:full-adder-imports` as the canonical stable identity for the existing two-file imported full-adder source; retained the former descriptive identity as a knowledge alias. Tracked status now exposes the exact `workspaceRevision` already used by create/open preconditions. The new field is optional/additive in the status DTO and does not alter existing result semantics.

**Files touched:** `site/src/content/{tour,agent-reference}.ts`, `site/src/scripts/playground-contract.ts`, `site/src/components/Playground.astro`, `site/test/{agent-reference-build,island-smoke}.test.ts`, `DOCS/{agent-playground,STATUS}.md`.

**Tests:** Focused `bun --bun run typecheck && bun --bun run build && bun test test/agent-reference-build.test.ts test/island-smoke.test.ts` passed (31 tests, 0 failures). The full docs-inclusive site gate is rerun after this entry. Typecheck reported the repository's existing hints only.

**Browser evidence:** A new isolated OpenCode/attached-Chrome context at the loopback preview discovered 33 native tools and status published `workspaceRevision` `...:workspace:90`. The regenerated corpus `a466f055a7de0274ba7531547a09f4e18bfb186772e57b587842fa6c218b6f2a` returned `tour-example:full-adder-imports` with `half_adder.circ` and `root.circ`. Using only returned status/list revisions, the page-registry created a saved scratch full-adder, produced compile-owned `E014` after the width edit, repaired it, and rebuilt. All eight full-adder vectors returned correct scalar values/masks. Opening half-adder returned the four required vectors and isolated verification passed 4 cases/4 steps/8 assertions. ROM preload and `pc=0xc` returned `out=0x90/defined=0xff`; source/share/WASM/preload/transcript handoffs dispatched with documented omissions. Full-adder Truth returned eight rows; settings, view, highlight/clear, and visible state agreed. Reload restored the scratch project, changed page ID, and native discovery re-registered 33 tools. No page console errors/warnings were observed.

**Remaining blockers:** Phase 6 remains incomplete. The RAM fixture's image can be explicitly loaded live and reads `q=0xa5/defined=0xff`; ordered `we=1, clk=0, clk=1` writes `q=0x3c/defined=0xff`. However, source preload correctly refuses RAM with `PRELOAD_CONFLICT`, and reset produces undefined RAM rather than restoring `0xa5`, contrary to the mandatory Phase 6 procedure. This needs a contract/plan decision before a code fix. There is still no actual supported ChatGPT client or configured Claude Code client, no browser-download capture/hash capability, no genuine bfcache result, and no complete edge/storage matrix. The application tree is uncommitted, so this is not frozen-commit final acceptance.

## 2026-09-12 - Phase 6 - Correction gate rerun

**Tests:** From `site/`, reran `bun --bun run typecheck && bun --bun run build && bun test && bun run bundle`: pass with 684 tests/0 failures and 26,657 assertions. `/playground` is 78.1 KiB gzip under its 120 KiB ceiling. The generated agent corpus carried the canonical full-adder-imports record; built-island coverage asserted the returned workspace revision. Typecheck completed with the repository's existing hints only.

**Next work:** Resolve the RAM-image/reset contract mismatch with an approved owning-phase decision, then rerun the affected isolated-client workflow and all remaining mandatory client, edge, bfcache, storage, and captured-download procedures against a committed frozen application tree.

## 2026-09-12 - Phase 6 - Approved RAM acceptance and final OpenCode rerun

**Decision and fixes:** User approval revised the Phase 6 RAM procedure to load the corpus RAM image through live `circ_update_memory`, verify its ordered write, and verify reset leaves RAM undefined. RAM remains ineligible for `circ_set_memory_preload`; no persistent-RAM contract was added. The Phase 6 plan, canonical agent guide, and agent-playground decision record now state that boundary. During the final browser rerun, `circ_set_view` exposed absent operation IDs as `undefined`, causing a false `INTERNAL_ERROR` after its visible effect had applied. The response now omits absent IDs, and built-island coverage asserts the JSON-safe result.

**Files touched:** `DOCS/PLANS/PHASE_6_end_to_end_acceptance_and_documentation.md`, `DOCS/{agent-playground,STATUS}.md`, `DOCS/decisions/agent-playground.md`, `site/src/components/Playground.astro`, and `site/test/island-smoke.test.ts`.

**Tests:** From `site/`, final `bun --bun run typecheck && bun --bun run build && bun test && bun run bundle` passed with 684 tests/0 failures and 26,658 assertions. `/playground` remained 78.1 KiB gzip under the 120 KiB ceiling. The focused built-island gate also passed (29 tests/0 failures). Typecheck reported the repository's existing hints only.

**Browser evidence:** The attached isolated OpenCode/Chrome context reloaded `http://127.0.0.1:4324/playground`, received fresh page ID `bf3c2caf-f2b6-4f64-a123-a582e40170ef`, and rediscovered 33 native `document.modelContext.registerTool` tools. Its page registry retrieved corpus `a466f055a7de0274ba7531547a09f4e18bfb186772e57b587842fa6c218b6f2a` and the RAM runtime image. It loaded 16 words into `data`, read `q=0xa5/defined=0xff` at `a=0x5`, wrote `0x3c` using ordered `d`, `we`, `clk=0`, `clk=1` assignments, then read `q=0x3c/defined=0xff`. Source preload returned `PRELOAD_CONFLICT`; reset operation succeeded with new session `...:session:127`; after explicitly driving `a=0x5`, `q=0x0/defined=0x0`. Page-registry and native `circ_set_view` both returned JSON-safe `live`/Data-open results; native retained only `session_build` in `operationIds`. The visible Data panel showed `q` as `?`, and no console warnings/errors were observed.

**Remaining blockers:** Phase 6 remains incomplete. This is an uncommitted application tree rather than frozen-commit acceptance. No actual supported ChatGPT browser-integrated session or configured Claude Code client session is available. Attached tooling cannot capture a downloaded file's bytes/name/hash, no genuine bfcache result was observed, and the complete native/page-registry edge and storage/quota matrices remain incomplete. Existing preview/dev processes were not stopped, so the plan's stopped-server build procedure is not independently attested.

**Next work:** Commit an approved application slice, then perform every remaining mandatory client, download-capture, lifecycle/bfcache, edge, and storage scenario against that one frozen application commit.

## 2026-09-12 - Phase 6 - Native schema and reload-registration correction

**What shipped:** `circ_drive` now declares bounded assignment items (`pin`, `value`, optional `defined`) and string query items; `circ_update_memory.action` declares mutually exclusive `poke`, `clear`, and `load` objects. Registry validation now evaluates the declared JSON-schema subset, including array items, object fields, bounds, `const`, nullable fields, and `oneOf`, so a valid native action is no longer rejected after schema discovery. Native registration is transactional: a provider rejection after earlier registrations disposes those earlier registrations. The page also invokes the same teardown from an `unload` fallback when `pagehide` is not delivered.

**Files touched:** `site/src/scripts/{agent-tools/{simulation,registry,page-api},webmcp-adapter}.ts`, `site/test/{agent-tools,webmcp-adapter}.test.ts`, `DOCS/{agent-playground,STATUS}.md`, and `DOCS/decisions/agent-playground.md`.

**Tests:** From `site/`, reran `bun --bun run typecheck && bun --bun run build && bun test && bun run bundle`: pass, 688 tests/0 failures and 26,669 assertions. `/playground` is 78.4 KiB gzip under the 120 KiB ceiling. Typecheck completed with the repository's existing hints only.

**Browser evidence:** Attached Chrome DevTools native WebMCP on `http://127.0.0.1:4324/playground` exposed 35 unique `document.modelContext.registerTool` tools. Native discovery showed the complete nested schemas for `circ_drive` and `circ_update_memory`. On page `e0f520da-acc4-4a62-8b18-f68d070f621d`, native `circ_update_memory` accepted `{ kind: 'load', hex: 'a0a1a2a3a4a5a6a7a8a9aaabacadaeaf' }`, loaded 16 RAM words, and native `circ_drive` accepted `assignments: [{ pin: 'a', value: '0x5' }]` plus `queries: ['q']`, returning `q=0xa5/defined=0xff`. After reload, native discovery contained 35 unique names and native `circ_get_simulation` returned fresh page `6f431635-4c15-46b6-8494-9b76f8c4e501`; its status reported native `registered`. No console errors or warnings were observed. This validates the attached Chrome path, not ChatGPT.

**Non-defects:** RAM reset remains intentionally live-session behavior, so reset leaving RAM undefined is not changed. RAM Truth refusal remains intentional.

**Remaining ChatGPT retest:** In an actual supported ChatGPT browser-integrated session, rediscover the two complete schemas, invoke `circ_update_memory` with a `load` action and `circ_drive` with assignment/query items using fresh provenance, then reload, rediscover, and verify a new-page native result with no stale registration. The broader mandatory ChatGPT Phase 6 workflow, client edge matrix, bfcache/storage, and external download-capture evidence are still outstanding.

## 2026-09-12 - Phase 6 - ChatGPT/Codex native schema retest

**What shipped:** The native schema correction was retested in the ChatGPT/Codex in-app browser.
**Tests:** The client discovered 35 tools. Native RAM `load` accepted 16 words and `circ_drive` at `a=0x5` returned `q=0xa5/defined=0xff`; result pass for schema discovery and live RAM control.
**Next work:** Obtain a supported ChatGPT native reload workflow or product guidance for stale WebMCP registration; retain the attached Chrome reload pass as separate evidence.
**Notes:** After reload, the client rediscovered all 35 tools but every `circ_get_status` invocation failed before reaching the page with `WebMCP tool registration is stale. Call fetchTools() again.`, including after tool/capability refresh. No post-reload page result was returned, so the replacement page ID could not be observed. This is failed ChatGPT/Codex reload acceptance, not proof that the application failed to re-register. No other errors were reported.

## 2026-09-12 - Phase 6 - Fresh ChatGPT/Codex native reload acceptance

**What shipped:** The ChatGPT/Codex native reload retest used a new browser session and fresh tool capability rather than reusing prior handles.
**Tests:** The client discovered 35 native tools. It opened the RAM example, observed an already-current successful compile, loaded 16 RAM words, and drove `a=0x5`; `q` returned `0xa5/0xff` with console records. Result pass.
**Next work:** Complete the remaining configured-Claude, captured-download, bfcache, storage/edge-matrix, and frozen-commit acceptance requirements.
**Notes:** Before reload, status page ID was `0ef4663c-4eb6-4c97-8b22-c7dfdf107403`. After reload, fresh discovery again found 35 tools and `circ_get_status` succeeded with page ID `8cc82824-3d76-4bc5-9a11-e67acd2c3da4`; native state was `registered` through `document.modelContext.registerTool`. The previous stale-registration failure did not reproduce in the new session. The client reported one `INVALID_ARGUMENT` result without identifying its individual call, so it is not attributed to a specific operation. Product/browser version and console inspection were unavailable under the native-tool-only constraint.

## 2026-09-12 - Phase 6 - Claude Code page-registry acceptance

**What shipped:** Claude Code 2.1.270 completed the end-to-end acceptance workflow through the Claude in Chrome extension page registry against Chrome 153.0.8010.36.
**Tests:** It discovered 35 tools, opened/compiled RAM and half-adder examples, loaded/read/wrote/reset RAM, ran four isolated half-adder cases with eight passing assertions, retrieved schematic/topology/exhaustive Truth, produced source/share/transcript/download-dispatch handoffs, and reloaded successfully. No console messages were captured during the test window.
**Next work:** Capture a browser download externally, obtain genuine bfcache evidence, complete the outstanding edge/storage matrix, and rerun the final suite on a frozen commit.
**Notes:** Native WebMCP was unavailable in this Chrome profile (`navigator.modelContext` absent), so this is page-registry fallback evidence only. Reload changed page ID from `9ce94314-cbfd-4035-9150-def2fa3cc76c` to `474960be-0d30-40d6-b520-b43d30d9289c` and restored the persisted half-adder project. A same-origin back navigation created a new page ID `19a5c7d9-f886-4394-bd00-0fa2fc83aec2`; its pre-navigation JavaScript state was gone, so bfcache is explicitly not claimed. Download completion remained unobservable beyond the `half-adder.wasm` dispatch receipt (25,140 bytes, `completionKnown: false`).

## 2026-09-12 - Phase 6 - bfcache lifecycle correction

**What shipped:** Removed the redundant `unload` teardown listener. `pagehide` already suspends persisted pages and fully disposes non-persisted pages, so native registrations remain abort-scoped without adding a Chrome bfcache disqualifier.

**Files touched:** `site/src/scripts/agent-tools/page-api.ts`, `site/test/{page-api,webmcp-adapter}.test.ts`, `DOCS/{agent-playground,STATUS}.md`, and `DOCS/decisions/agent-playground.md`.

**Tests:** From `site/`, `bun test test/page-api.test.ts test/agent-tools.test.ts test/webmcp-adapter.test.ts` passed (17 tests); `bun run typecheck`, `bun run build`, and `bun test test/island-smoke.test.ts` passed (29 built-island tests). Typecheck retained only existing repository hints.

**Browser evidence:** Attached Chrome opened `http://127.0.0.1:4322/playground` with native `document.modelContext.registerTool`. The public registry initially reported page ID `331221c6-734a-48da-8c90-4991ecee286d`. A same-origin navigation to `/gallery` and Back returned the same page ID; native tools rediscovered and native `circ_get_status` returned that same ID with native state `registered`. This demonstrates bfcache restoration for this Chrome/tooling context.

**Remaining blockers:** This is still an uncommitted application tree rather than frozen-commit acceptance. Actual ChatGPT and configured Claude Code client sessions, captured browser-download bytes/hash, and the remaining edge/storage matrices are incomplete.

## 2026-09-12 - Phase 6 - Download capture evidence

**What shipped:** Confirmed the browser-dispatched artifacts reached the local Downloads directory.
**Tests:** `half-adder.wasm` was captured at 25,140 bytes on 2026-09-12 17:55:20 with SHA-256 `71a2521b4fc6ad0164a2e883aa96574b2c0ad8975ee6e012b41eef192c5133ba`. `not-chain.wasm` was captured at 23,995 bytes on 2026-09-12 16:44:19 with SHA-256 `9f674cf5810c67b3959f91fdc232e6f43380f92c03225d035cd9eca191bf738e`.
**Next work:** Commit the current corrective application slice, then repeat the final acceptance suite against that frozen commit and complete only the remaining storage/edge matrix.
**Notes:** The half-adder byte count matches the Claude Code dispatch receipt. The dispatch API correctly reports completion as unknown; the filesystem capture supplies the external filename/size/hash evidence.
