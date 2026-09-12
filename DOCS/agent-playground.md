# Agent Playground

Use **Connect agent** beside Share to copy an active-project handoff into ChatGPT Desktop, Claude Code, Claude in Chrome, or another browser-capable agent. The prompt includes a freshly generated Share URL containing all current file bodies, including unsaved edits, plus the project name and selected entry file. It instructs the agent to restore the snapshot in a new tab and select that entry before asking for its next task. It prefers native WebMCP and includes the public page-registry fallback. Like Share, it transfers source, not ROM images, live state, settings, or artifacts. If the source exceeds the Share URL cap, the prompt includes the combined source as JSON for import instead. If clipboard access is blocked, a selected text area provides the same handoff for manual copying.

`/playground` exposes a browser-resident tool contract for an agent working beside a person. Compilation, simulation, project storage, and knowledge search run locally in the browser. The static deployment has no application backend, relay, custom MCP server, or custom browser extension.

Tool arguments and bounded results requested by a user are shared with the connected agent through that client's browser integration or browser-control tool. They are subject to that client and provider's policies. The early share-fragment scrub prevents source-bearing fragments reaching deferred page integrations; it is not a claim that the page makes no network requests.

The playground status line reports observed tool activity, not a persistent connection. It starts at `agent tools ready · no requests yet`, shows `agent active` while a discovery or tool request is being handled (with a short visible grace period), then settles to `agent used tools recently`. Native registration alone does not activate the indicator, and the page cannot identify or count agents.

## Setup

1. Build the site from `site/` with `bun --bun run build`.
2. Start one static preview with `bun --bun run preview --host 127.0.0.1` and use its printed loopback URL, or use an authorized static host.
3. Open `/playground` in the client-specific clean browser profile. Do not reuse another client's profile or storage.
4. Select the visible tab using the client's verified browser connection mechanism.
5. Discover tool schemas before invoking a tool. Read `circ_get_status` before every revision-guarded mutation.

Native WebMCP is available only when the browser exposes `document.modelContext.registerTool` or `navigator.modelContext.registerTool`. It routes to the same registry as the external API and is abort-scoped on page suspension/disposal. A provider that rejects an undiscovered tool name has not called the application; record that as a provider result, not an application code.

The external page-registry fallback is `window.circPlayground`:

```js
async () => window.circPlayground?.listTools()
async () => window.circPlayground?.callTool('circ_get_status', {})
```

Select the tab before evaluating either expression. Pass user text as browser-tool arguments, never by interpolating it into evaluated JavaScript. OpenCode and Claude Code require separately configured browser tooling. Native WebMCP tooling also requires its browser/tool-specific experimental support.

## Workflows

The public catalogue covers discovery, corpus help, project/file reads, authoring, compilation, diagnostics, simulation, verification, inspection, visible workbench controls, source/share/transcript handoff, and browser download dispatch. Every result is JSON-safe and capped at 32 KiB.

For the acceptance fixture, use the frozen corpus records `ref:language:parametric-sub-circuits`, `diagnostic:E014`, `tour-example:full-adder-imports`, `example:half-adder`, `example:rom-lookup`, and `example:ram-write-read`. Read the corpus/compiler identities first; a mismatch is a preflight failure.

1. Discover schemas and call `circ_get_status`; compare the returned project, selected entry, view, and session state with the visible page.
2. Use `circ_help` to read the reference and diagnostic, then retrieve the named tour and examples. Help is read-only and does not select, compile, or simulate a project.
3. Create/open a scratch project, read the manifest, and make only revision-guarded edits. Wait for `circ_compile`, read file-local diagnostics, repair, and compile a current artifact.
4. Call `circ_prepare_simulation`, wait if necessary, then use `circ_drive` with current artifact/session/live-state provenance. Its `assignments` array contains `{ pin, value, defined? }` items and `queries` contains pin-name strings; assignments settle one at a time. `circ_update_memory.action` is exactly one of `{ kind: 'poke', address, value, defined? }`, `{ kind: 'clear' }`, or `{ kind: 'load', hex }`.
5. Use `circ_run_verification` for isolated bounded vectors. It never changes the live session, UI, or console.
6. Request/read schematic and Truth results, read bounded topology, set supported workbench/view state, and apply then clear a source highlight. Confirm each changed state in the visible workbench.
7. Use `circ_export_source`, `circ_create_share_link`, and `circ_get_transcript` for bounded handoff. Source/share omit images, live RAM, live pins, settings, transcript, and artifacts as applicable.
8. `circ_download_artifact` and `circ_download_memory` prove dispatch only. Capture browser downloads outside the tool channel to prove completion; compare one captured filename and byte length with each receipt and record SHA-256. WASM validation includes topology/provenance decoding and vectors; source/live memory bytes compare against their source/readback.

`example:ram-write-read` supplies runtime RAM initialization, not a source preload. Load its corpus image with `circ_update_memory`, read `q=0xa5/defined=0xff` at `a=0x5`, then perform the ordered `we=1, clk=0, clk=1` write and read `q=0x3c/defined=0xff`. After `circ_reset`, drive the address again and expect an undefined `q`: live RAM is reset/replacement/reload state. `circ_set_memory_preload` accepts only ROM declarations and must return `PRELOAD_CONFLICT` for RAM.

## Lifecycle And Bounds

Page, project, source, target, artifact, image, session, operation, result, cursor, and presentation identities are page-scoped. Re-read after a conflict; stale calls are refused instead of applying to newer work. Reload creates a new page ID and registration. A genuine bfcache restoration retains the page ID, resumes the registry, and re-registers native tools. `pagehide` aborts native registrations before a non-cached page facade is discarded, without an `unload` listener that would disqualify Chrome bfcache.

Project/files/entry/settings/source preloads use the documented local-storage envelope when persistence succeeds. Sessions, live pins/RAM, highlights, operations, result stores, and page IDs are memory-only. Storage failure is reported as `memory_only` or refusal; never modify local storage behind the app to manufacture a pass.

- Tool input is limited to 128 KiB; result envelopes are limited to 32 KiB.
- Source and stores have their published caps; text/topology/diagnostic/Truth/verification results page with provenance-bound cursors.
- Full topology is limited to a 4 MiB section, 32,768 components, and 65,536 connections.
- Truth refuses RAM and projected work above 4,096 rows; filtered Truth requires its documented live-session scope.
- Verification permits at most 128 cases, 512 steps, 2,048 actions/assertions, and a 10-second deadline.
- Unknown semantic tools and retained-facade `PAGE_DISPOSED` are page-registry cases. Native unknown-name rejection and registration disappearance after reload are provider/lifecycle observations.

## Privacy And Exports

Local computation does not make requested tool data private from the connected agent. Do not use credentials, personal source, account information, cookies, or browser-profile paths in acceptance evidence. Record only public fixture inputs, provider/browser/tool versions, app commit, result codes, relevant provenance, payload sizes, and hashes. Replace local origins/paths with neutral labels when publication would reveal machine-specific information.

Artifact and memory receipts report `state: "dispatched"` and `completionKnown: false`; the application neither reports a filesystem path nor claims a completed download. Normal browser controls cannot reliably induce pre-dispatch `DOWNLOAD_FAILED`; that branch remains automated coverage, while real-client runs record successful dispatch or a provider/browser block after dispatch.

## Troubleshooting

- `REVISION_CONFLICT`, `TARGET_CONFLICT`, `ARTIFACT_CONFLICT`, `IMAGE_CONFLICT`, or session/live-state conflicts: reread status and retry with the returned provenance.
- `PAGE_SUSPENDED` or `PAGE_DISPOSED`: return the tab to view or rediscover after reload; do not reuse a retained facade.
- `HELP_UNAVAILABLE`, `HELP_INVALID_CORPUS`, `HELP_CORPUS_CHANGED`, `HELP_NOT_FOUND`, `HELP_REMOVED`, or `HELP_BUSY`: retain the reported corpus identity and retry only as the code permits.
- Native tool unavailable/rejected: use the page registry when the client has an evaluator. This fallback does not convert native absence into a native pass.
- Browser download blocked: preserve the dispatch receipt and record the browser/provider observation. Do not report the receipt as file completion.

## Compatibility And Evidence

| Client / product | Access path | Current Phase 6 result |
| --- | --- | --- |
| OpenCode | Native WebMCP and page registry through attached Chrome tooling | Author/repair, full-adder, half-adder, ROM, RAM, inspection, handoff, persistence, and reload observations recorded; same-origin bfcache restoration demonstrated. |
| ChatGPT/Codex in-app browser | Native WebMCP | Fresh-session retest discovered 35 tools, loaded/drove RAM, and returned successful status with a new page ID after reload. Product/browser versions were not exposed. |
| Claude Code 2.1.270 / Chrome 153.0.8010.36 | Page registry through Claude in Chrome MCP | RAM load/write/reset, half-adder verification, inspection, handoff, and reload passed in the reported workflow. Native API was unsupported; Back produced a new document. |

Automated tests cover the registry, adapter, built-page public surface, documentation registration, and prior-phase regressions. They are not substitutes for client evidence. The repository archive at `DOCS/archive/plan-agent-driven-playground.md` preserves the evidence summary and canonical commit containing the full STATUS history. The initiative was closed for archiving at the user's request with the storage/edge matrix deferred. The original full Phase 6 signoff, including a unified three-client run against one frozen application commit, is not claimed.

### OpenCode browser evidence, 2026-09-12

Attached Chrome DevTools tooling used the visible tab at `[loopback preview]/playground` after the Phase 6 site gate. The application commit was `7af1faafb18770d677a19d5e559953662dd9ea52`; the tested build also contained uncommitted Phase 6 documentation/copy-only changes, so this is not final frozen-commit acceptance. Bun was `1.2.10`, Node was `v24.20.0`, Chrome reported `153.0.0.0` to the attached tooling, and the client was this OpenCode browser-tool session. The native API was `document.modelContext.registerTool`; the compiler was `0.0.3/e8869c8`; corpus ID was `ef1f2fb0918d8fad1248b957784557442b26140e432751767ac091428ecd42c7`.

- Native discovery listed 33 tools before and after reload. Native status and `diagnostic:E014` help returned `ok: true`; the help result's active compiler comparison was `match`.
- The page registry independently listed the same 33 tools. A malformed known call returned application `INVALID_ARGUMENT`; `phase6_unknown_tool` returned application `UNKNOWN_TOOL`.
- On the existing public NOT-chain project, page-registry drive of `a=0x0` returned `out=0x1/defined=0x1`; isolated verification passed 2 cases, 2 steps, and 2 assertions. Schematic returned the three-NOT path, topology returned 5 components/4 connections, and exhaustive Truth returned `0 -> 1`, `1 -> 0`. Source/share/transcript handoff returned the documented omissions. The visible page showed the corresponding Truth view, Data card, source, schematic, and local-computation disclosure.
- Native artifact dispatch returned receipt `download:126`, `not-chain.wasm`, 23,995 bytes, `state: dispatched`, `completionKnown: false`. This tooling could not expose a captured browser-download file, filename, byte count, or SHA-256; no completion claim is made.
- Full reload replaced page ID `21bc63f2-be10-4d7d-854a-19aeee8ee733` with `7c0160e4-e1f0-4f4d-a440-9782e0594ce6`; native tools rediscovered and native status again returned `registered`. This proves reload/re-registration, not bfcache.

The initial stable-ID and workspace-revision blockers were corrected and rerun in a new isolated browser context. The regenerated corpus is `a466f055a7de0274ba7531547a09f4e18bfb186772e57b587842fa6c218b6f2a`; `tour-example:full-adder-imports` now returns the existing `half_adder.circ`/`root.circ` project, and status publishes `workspaceRevision` for create/open preconditions.

- The isolated profile created a persisted two-file scratch project, changed root `output sum` to `output[2] sum`, received compile-owned `E014`, repaired the exact range, and rebuilt a current artifact. All eight `(a,b,cin)` vectors returned binary-addition `sum`/`cout` values with scalar `defined: 0x1`.
- `example:half-adder` returned the four required vectors and isolated verification passed 4 cases, 4 steps, and 8 assertions. Full-adder exhaustive Truth returned eight rows; workbench settings/view, source highlight/clear, and visible source/Schematic/Data state agreed. Reload restored the persisted scratch project, replaced the page ID, and re-registered 33 native tools.
- `example:rom-lookup` accepted its corpus ROM image, returned `out=0x90/defined=0xff` at `pc=0xc`, and dispatched source/share/WASM/preload/transcript handoffs with their stated omissions. No browser download capture/hash is available through this tooling.
- `example:ram-write-read` is a live-memory acceptance pass: its corpus image loaded with `circ_update_memory` yielded `q=0xa5/defined=0xff` at `a=0x5`, and the ordered write yielded `q=0x3c/defined=0xff`. `circ_set_memory_preload` correctly refused RAM with `PRELOAD_CONFLICT`; after reset and an explicit address drive, `q` was undefined. This is the documented live-RAM reset contract, not a source-preload failure.

The final attached-Chrome rerun reloaded the rebuilt page, rediscovered 33 native tools, and repeated that RAM sequence through the page registry. Its fresh page ID was `bf3c2caf-f2b6-4f64-a123-a582e40170ef`; corpus `a466f055a7de0274ba7531547a09f4e18bfb186772e57b587842fa6c218b6f2a` returned the runtime image. The session reset to `...:session:127`, and the post-reset drive returned `q.value=0x0`, `q.defined=0x0`. Native `circ_set_view` then returned a JSON-safe success response with its retained `session_build` operation ID; the visible Data panel showed `q` as `?`. No console warnings/errors were observed.

After removing the redundant `unload` teardown listener, attached Chrome navigated same-origin from `/playground` to `/gallery` and Back. The public registry kept page ID `331221c6-734a-48da-8c90-4991ecee286d`; native discovery reappeared and native `circ_get_status` succeeded with that same ID. This demonstrates bfcache restoration in this Chrome/tooling context, not full Phase 6 acceptance.

Subsequent user-supplied evidence completed the scoped ChatGPT/Codex native RAM/reload retest and Claude Code page-registry RAM/verification/inspection/handoff/reload workflow summarized above. External filesystem capture found `half-adder.wasm` at 25,140 bytes (matching Claude's receipt), SHA-256 `71a2521b4fc6ad0164a2e883aa96574b2c0ad8975ee6e012b41eef192c5133ba`, and `not-chain.wasm` at 23,995 bytes, SHA-256 `9f674cf5810c67b3959f91fdc232e6f43380f92c03225d035cd9eca191bf738e`. These observations span iterative builds. The complete native/page-registry edge matrix, storage/quota scenarios, and one frozen-commit final rerun remain deferred rather than passed.
