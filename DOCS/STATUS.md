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
