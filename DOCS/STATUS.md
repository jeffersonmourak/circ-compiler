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
