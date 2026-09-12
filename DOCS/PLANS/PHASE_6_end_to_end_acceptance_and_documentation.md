# Phase 6 — End-to-End Acceptance and Documentation

> **Dependencies:** Phases 0–5 complete, reviewed, and committed; an actual supported ChatGPT browser-integrated environment; the Phase 0-pinned browser, Chrome DevTools MCP, OpenCode, and Claude Code versions; access to a static origin each selected client can reach.
> **Warnings:** This phase proves the shipped contracts; it does not replace real-client calls with mocks, DOM inspection, screenshots, or a browser-automation runner. A missing target environment, failed connection, contract-changing defect, or serverless-architecture blocker prevents completion until the human resolves it.

## Goal

Prove, on one frozen application commit, that ChatGPT, OpenCode, and Claude Code can each use the public tool contract to discover, author, repair, compile, simulate, verify, inspect, and hand off circ projects in the visible static playground. Each client completes the core workflow from isolated browser storage; native and external access paths also pass reload/re-registration, session replacement, fallback, concurrency, persistence, and bounded-refusal cases. The repository finishes with passing site gates, accurate public privacy copy, a published setup/usage guide, finalized architectural decisions, and curated evidence sufficient to reproduce every acceptance claim without publishing secrets or user-specific data.

## Scope

**In scope:**

- Run the complete core workflow independently in actual ChatGPT, OpenCode, and Claude Code environments against the same tested site commit and compiler/corpus identities.
- Exercise every lifecycle, replacement, conflict, persistence, fallback, malformed-input, stale-provenance, paging, result, share, Truth, and verification limit through each public path where that condition can reach the application. Record provider-level rejection/unregistration separately when native WebMCP cannot dispatch the equivalent call.
- Use a dedicated, initially clean browser profile/storage partition for each client. Reuse that client's profile only inside an explicit reload, bfcache, or persistence scenario.
- Verify visible editor, file, setting, view, highlight, schematic, Truth, Data, memory, pin, and console state through tool results plus human-visible agreement; never derive the expected result by scraping the DOM.
- Capture actual browser downloads externally, compare names and byte counts with dispatch receipts, and record SHA-256 hashes as identities for the captured bytes.
- Add one cross-phase built-page regression and update focused documentation/copy assertions where needed; rerun all earlier phase tests rather than duplicating every contract in a new harness.
- Permit narrow fixes to existing application modules and tests when acceptance exposes a defect and the approved Phase 0–5 contract remains unchanged.
- Finalize the canonical agent guide, decision record, documentation indexes, repository entry point, generated public reference registration, playground integration/privacy copy, and append-only STATUS evidence.
- Record unavailable checks and failures honestly. A mandatory target or access-path failure leaves the phase incomplete.

**Explicitly deferred:**

- A new application backend, relay, custom HTTP/WebSocket bridge, custom browser extension, or deployed agent service.
- A checked-in OpenCode, Claude Code, browser-profile, credential, token, port, or machine-local configuration.
- Playwright, Puppeteer, or another browser-automation dependency; automation cannot substitute for the three actual agent clients.
- A new CI workflow. Typecheck, build, Bun tests, bundle limits, and client/browser procedures remain recorded local acceptance gates for this initiative.
- New public tools, schemas, storage fields, compiler/runtime APIs, renderer behavior, or broader nested live-memory access.
- Archiving the initiative, removing active plan files, merging, publishing, or deploying. Those require their separate workflow and human authorization after Phase 6 is committed.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| Site acceptance | `site/test/agent-acceptance.test.ts` | One built-page, public-registry cross-phase regression that composes discovery, help, author/repair, operation waits, simulation, inspection, and handoff without treating the test as real-client evidence. |

`DOCS/agent-playground.md`, `DOCS/decisions/agent-playground.md`, and `DOCS/STATUS.md` are created by earlier phases. If an implementation reaches Phase 6 without them, stop: do not silently create substitutes for missing earlier-phase deliverables.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| Agent guide | `DOCS/agent-playground.md` | Consolidate prerequisites, exact client setup, discovery/invocation recipes, core workflows, lifecycle rules, limits, troubleshooting, privacy/data handling, compatibility matrix, and curated acceptance evidence. |
| Agent decision | `DOCS/decisions/agent-playground.md` | Finalize the verified native API variant, dual-access architecture, lifecycle, revision/concurrency, bounds, disclosure, and evidence decisions; record approved deviations only. |
| Delivery log | `DOCS/STATUS.md` | Append one entry per Phase 6 slice with exact gates, tested commit and versions, scenario results, blockers, and next work; never rewrite previous entries. |
| Documentation index | `DOCS/index.md` | Link the agent-playground guide and describe its supported-client/setup scope. |
| Decision index | `DOCS/decisions/index.md` | Index the durable agent-playground decisions using the existing topic convention. |
| Repository entry point | `README.md` | Briefly advertise agent operation of the browser playground and link the canonical guide; do not present it as a CLI mode. |
| Public reference registry | `site/scripts/lib/site-config.ts` | Publish the canonical guide under a stable reference route/Markdown twin without adding it to circ-language `circ_help` search content. |
| LLM mirror generator | `site/scripts/build-llm-mirror.ts` | Include the registered guide in navigation/full-mirror output only if Phase 2's generalized registry does not already do so. |
| Playground metadata | `site/src/pages/playground.astro` | Replace ambiguous “no server” wording with accurate local-computation/no-application-backend wording and expose the guide route where page metadata supports it. |
| Playground surface | `site/src/components/Playground.astro` | Replace “nothing leaves the page” with concise copy distinguishing local computation from requested results shared with a connected agent. |
| Built-page coverage | `site/test/island-smoke.test.ts` | Assert the revised visible disclosure and preserve the existing chrome/lifecycle checks. |
| Documentation coverage | `site/test/site-labels.test.ts` | Assert the agent guide's route, title, Markdown twin, and documentation-label parity. |
| Lazy-boundary coverage | `site/test/bundle-graph.test.ts` | Confirm the final agent/help/editor/renderer surfaces remain playground-only and heavy modules remain lazy. |

Narrow acceptance fixes may modify the Phase 0–5 controller, registry, adapter, operation, knowledge, simulation, inspection, or handoff modules and their existing tests. Such files are added to the active slice's topology and STATUS entry before editing. A fix that changes a public DTO, operation semantic, persistence contract, compiler/runtime/renderer API, or architectural boundary is out of scope until the human approves a revised owning-phase decision.

Generated files under `site/src/pages/reference/` and `site/public/` are generator outputs and remain untracked unless the repository's landed Phase 2 policy says otherwise.

**New dependencies:** None. Chrome DevTools MCP and the three agent clients remain separately installed acceptance tools, not site dependencies.

## Data & State

Phase 6 introduces no application DTO, operation state, persistent playground field, or public tool. It consumes the exact Phase 0–5 registry and result contracts. The only new model is a documentation/evidence convention:

```ts
type AcceptanceClient = 'chatgpt' | 'opencode' | 'claude_code';
type AcceptancePath = 'native_webmcp' | 'external_native_webmcp' | 'page_registry';
type AcceptanceResult = 'pass' | 'fail' | 'blocked' | 'not_applicable';

interface AcceptanceEnvironment {
  client: AcceptanceClient;
  clientProduct: string;
  clientVersion: string;
  browserProduct: string;
  browserVersion: string;
  connectionTool: string | null;
  connectionToolVersion: string | null;
  connectionMode: string;
  nodeVersion: string | null;
  bunVersion: string;
  originKind: 'loopback_preview' | 'authorized_static_host';
  applicationCommit: string;
  compilerVersion: string;
  compilerRevision: string;
  corpusId: string;
  apiVariant: string;
}

interface AcceptanceStepEvidence {
  ordinal: number;
  tool: string;
  arguments: unknown;
  expectedObservation: string;
  result: AcceptanceResult;
  applicationCode: string | null;
  pageId: string | null;
  projectId: string | null;
  sourceRevision: string | null;
  artifactId: string | null;
  sessionId: string | null;
  operationId: string | null;
  visibleAgreement: string;
  resultExcerpt: unknown;
  serializedResultBytes: number;
  resultPageCount: number | null;
  resultSha256: string;
  notes: string | null;
}

interface AcceptanceDownloadEvidence {
  tool: 'circ_download_artifact' | 'circ_download_memory';
  dispatchId: string;
  receiptState: 'dispatched';
  completionKnown: false;
  receiptName: string;
  receiptByteLength: number;
  sourceKind: 'artifact' | 'live_root' | 'source_preload';
  sourceProvenance: string;
  capturedName: string;
  capturedByteLength: number;
  capturedSha256: string;
  downloadCount: 1;
}

interface AcceptanceScenarioRecord {
  id: string;
  path: AcceptancePath;
  environment: AcceptanceEnvironment;
  cleanProfile: boolean;
  startedAt: string;
  steps: readonly AcceptanceStepEvidence[];
  downloads: readonly AcceptanceDownloadEvidence[];
  result: AcceptanceResult;
  blocker: string | null;
}
```

These interfaces specify fields in the Markdown evidence; they do not require JSON evidence files or a runtime validator. IDs and timestamps may be shortened only if they remain sufficient to correlate adjacent calls. Tool names, argument shapes, application codes, provenance transitions, serialized UTF-8 byte counts, page counts, and lowercase hex SHA-256 values are exact. `resultExcerpt` contains the complete result when bounded and reasonable; large source, schematic, topology, Truth, and transcript results use the decisive fields plus a representative excerpt, while `serializedResultBytes`, `resultPageCount`, and `resultSha256` cover the complete reassembled JSON-safe application result. Binary evidence correlates the receipt's dispatch ID/name/length/source provenance with one captured file. The captured SHA-256 identifies those bytes; it is not described as matching a receipt field that does not exist. Preload/live-memory downloads are compared with known source image or live readback bytes. Artifact downloads are validated as WASM, decoded for the expected topology/provenance, and exercised on the recorded vectors; no unavailable public artifact-hash oracle is invented. The guide does not paste unbounded payloads.

Evidence redaction is deterministic:

- Never record credentials, tokens, cookies, account identifiers, private prompts, browser-profile paths, local usernames, or unrelated projects/tabs.
- Replace machine-specific absolute paths and authorized private hostnames with labeled placeholders while preserving the command shape and origin kind.
- Use only initiative-authored public fixture source in recorded calls. If unrelated user data appears, redact its value and record that redaction occurred.
- Do not redact client/browser/tool versions, tested commit, public tool arguments needed to reproduce the fixture, application result codes, provenance relationships, payload sizes/hashes, or pass/fail/blocker facts.
- A redacted result cannot support a claim whose decisive value was removed; rerun with the public fixture instead.

### Required scenario matrix

Each of ChatGPT, OpenCode, and Claude Code runs the complete core sequence in a fresh profile. Bind the run to these Phase 2 stable records: `ref:language:parametric-sub-circuits`, `diagnostic:E014`, `tour-example:full-adder-imports`, `example:half-adder`, `example:rom-lookup`, and `example:ram-write-read`. Phase 2 must freeze `tour-example:full-adder-imports` for the existing two-file full-adder tour before Phase 6; a renamed/missing ID is a failed dependency, not permission to select an arbitrary replacement.

1. Discover capability/status schemas and verify the visible page/project identity.
2. Use `circ_help` to read `ref:language:parametric-sub-circuits` and `diagnostic:E014`, then retrieve the complete `tour-example:full-adder-imports`, `example:rom-lookup`, and `example:ram-write-read` projects with every named file/image and corpus/compiler citation.
3. Create a named scratch project from `tour-example:full-adder-imports`, change its root `sum` output to width 2 to cause `E014`, select the root visibly, build, read the file-local diagnostic, restore the retrieved scalar declaration with expected revisions, and obtain a current artifact. Verify all eight `(a,b,cin)` combinations as binary addition, with scalar defined masks `0x1`.
4. Open `example:half-adder`, prepare its session, and drive `(a,b) = 00, 01, 10, 11`; expect `(sum,carry) = 00, 10, 10, 01`, with scalar defined masks `0x1`. Compare values/masks with the UI/console and run the same four vectors in isolated verification.
5. Inspect schematic text, topology origins, exhaustive Truth, then over-cap filtered Truth with explicit held/unknown scope; change supported settings/view and apply/clear a source highlight.
6. Open `example:ram-write-read`, load its runtime image `a0a1a2a3a4a5a6a7a8a9aaabacadaeaf` with `circ_update_memory`, and at address `0x5` observe `q=0xa5/defined=0xff`. Write `0x3c` with ordered `we=1, clk=0, clk=1`, then observe `q=0x3c/defined=0xff`. Reset, explicitly drive the address again, and observe `q` undefined. RAM is live session state: `circ_set_memory_preload` refuses it with `PRELOAD_CONFLICT`, and reset does not restore its runtime image. Confirm live-memory, console, reset, and session provenance.
7. Use the two-file `tour-example:full-adder-imports` project for origin inspection and `example:rom-lookup` with source image `00010409101924314051647990a9c4e1` for image handoff. At `pc=0xc`, expect `out=0x90/defined=0xff`. Produce source/share/WASM/preload/transcript handoffs whose omissions and reproduction requirements are explicit.
8. Capture each binary download once and verify its actual name, bytes, and SHA-256 independently of the dispatch receipt.

Source bodies are retrieved by stable ID from the Phase 2 corpus, never copied into a second Phase 6 fixture file. The explicit vectors/images above are the acceptance oracle already validated by Phase 2's behavior fixtures and Phases 4–5; a corpus mismatch fails preflight.

Run the application-level edge matrix through both native WebMCP and the page registry when a registered known tool can express the input: malformed known-tool arguments; source conflict and retry after a human edit; live-session conflict and retry; delayed operation supersession; stale last-good artifact labeling; session replacement during pending preparation; project persistence/reload and new page identity; genuine bfcache restoration when performed; storage unavailable/quota honesty; source/store/result/page/share caps; Truth preflight cap/RAM refusal; verification case/step/output/timeout bounds; and stale cursor/session/operation IDs. Test unknown semantic tool names and retained old-facade `PAGE_DISPOSED` only through the page registry. On native WebMCP, instead record provider rejection of an undiscovered name and absence of the old registration after reload; neither is mislabeled as an application code. Test native-unavailable fallback through the page registry. Pre-dispatch `DOWNLOAD_FAILED` remains an injected Phase 5 automated test because normal browser controls cannot reliably force Blob/object-URL/anchor creation failure; real clients test successful dispatch and honestly record any provider/browser blocking after dispatch without changing the receipt to failure. `not_applicable` is valid only for an environment-specific observation such as bfcache not being used and must name the reason; it cannot excuse a mandatory access path.

## Execution & Concurrency Model

Phase 6 adds no background worker, queue, mutex, or production state owner. Existing controller serialization, operation stores, worker ownership, and `SimSession` rules remain authoritative.

Acceptance runs are operationally serialized. Only one client controls one selected tab/profile during a recorded scenario. The operator stops the dev server, completes the build, starts one preview/static target, records its tested commit, and does not rebuild generated assets while acceptance is running. Separate client profiles prevent localStorage, page IDs, projects, artifacts, sessions, registrations, and downloads from contaminating another client's result.

Inside concurrency scenarios, the test deliberately overlaps only the named human action and agent operation. It records both precondition identity and resulting conflict/supersession, waits for settlement where the contract permits it, then re-reads and retries. It never adds arbitrary sleeps as proof of completion, never reruns a simulation mutation to recover a missing console line, and never treats cancellation of a wait as proof that synchronous WASM work stopped.

Reload destroys the old page lifetime and must produce a new page ID with one active registration. Genuine bfcache restoration retains the cached page identity and restores dispatch according to Phase 0. Session replacement invalidates the old session even for same-shaped artifacts. Retained references and old cursors must fail with their documented stale/disposed codes rather than observe a replacement.

## Persistence & I/O

The application remains statically deployed. Normal acceptance performs same-origin static asset/reference fetches, browser-local computation, existing `localStorage['circ.playground.v1']` reads/writes, fragment share encode/decode, tool-channel input/results, and user-visible browser downloads. It adds no database, source-upload endpoint, relay, custom server, telemetry payload, or storage key.

Run each clean-profile scenario from empty playground storage. Reload/persistence scenarios retain only the subject profile's existing envelope. Record whether a mutation persisted, remained memory-only after a storage failure, or was refused. Never edit localStorage behind the application to manufacture a pass; test setup may use the public project tools and browser-supported storage/quota controls only where the scenario explicitly documents them.

The public copy and guide must distinguish these boundaries:

- Compilation, simulation, project storage, and knowledge search execute locally in the browser; the deployment has no application backend for project data.
- Tool arguments and the bounded results a user requests are disclosed to the connected agent and may be handled under that client/provider's policies.
- The existing early fragment scrub prevents source-bearing share fragments from reaching deferred page integrations; it is not a claim that no network requests occur.
- Source/share/WASM omit source-owned memory images and live RAM. Memory exports are separate raw downloads.
- A download result proves browser dispatch only. Phase 6's external capture proves completion for that acceptance run; the application never claims a filesystem path or completion.

`DOCS/agent-playground.md` is the canonical durable setup and evidence record. `DOCS/STATUS.md` remains append-only and summarizes each slice rather than duplicating every transcript. Generated public guide/twin outputs are rebuilt by the existing sync/mirror pipeline. No raw client transcript, browser profile, binary download, or temporary acceptance artifact is committed.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Close automated and documentation gaps | Add the public-registry cross-phase regression; correct page/privacy copy; finalize guide structure, public registration, indexes, ADR sections, redaction/evidence templates, and bundle assertions. Fix only contract-preserving defects found by the automated gate. | `public_registry_cross_phase_workflow`, guide/copy/mirror tests, all Phase 0–5 focused suites, and the full site gate pass. |
| 2 | Prove lifecycle, fallback, and limits | In isolated profiles, execute each edge at the correct application/provider boundary through native WebMCP and the page registry; make contract-preserving fixes and record exact outcomes/blockers. | Named lifecycle/conflict/persistence/limit scenarios pass; provider-only rejection/unregistration is distinguished from application codes; reload IDs, fallback health, UI state, and bounded outputs match contracts. |
| 3 | Preflight every client and freeze the application | Run the complete core sequence in ChatGPT, OpenCode, and Claude Code; fix contract-preserving defects, rerun affected automated/client scenarios, complete public behavior/docs, and commit the final application tree. | All three preliminary workflows pass, no known application defect remains, the full site gate passes, and the resulting application commit is frozen for final acceptance. |
| 4 | Run final acceptance and close | From clean isolated profiles, rerun the complete core sequence in all three clients against the same frozen application commit, rerun both access-path edge matrices, complete curated evidence and compatibility tables, audit observed behavior against docs/decisions, rerun the docs-inclusive site gate, and append completion STATUS. | `chatgpt_end_to_end_acceptance`, `opencode_end_to_end_acceptance`, `claude_code_end_to_end_acceptance`, lifecycle/limit procedures, documentation audit, full site gate, and evidence completeness all pass against one recorded application commit. |

Slices are ordered by dependency. Each slice is reviewable and committed before the next starts. Slice 4 begins only after Slice 3's application tree is committed; all final client and edge evidence names that one application commit. Slice 4 may change only evidence/STATUS prose after the run. If it reveals an application or public-guide defect, stop Slice 4, make and commit a new corrective slice with its gates, then restart every final client and edge run against the new frozen application commit. The later evidence-only commit is not misrepresented as the application commit that clients exercised.

## Tests

Test names below include Bun assertions and recorded real-client procedures. A manual client procedure is never labeled as an automated test in STATUS.

**Unit tests:**

No new standalone unit-test module is required because Phase 6 adds no production DTO or operation. All existing Phase 0–5 unit tests are regression requirements. Narrow fixes add named cases to the owning module rather than weakening expectations or adding Phase 6-only compatibility branches.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `agent_guide_is_registered_reference` | `site-labels.test.ts`, generated reference | The canonical guide has one stable HTML route/Markdown twin, matching title/description and index link, without entering the circ-language help corpus. |
| `agent_disclosure_is_accurate` | `island-smoke.test.ts`, built playground | Built copy promises local computation/no application backend while disclosing that requested tool results go to a connected agent; the obsolete “nothing leaves the page” claim is absent. |
| `final_agent_graph_is_route_local_and_lazy` | `bundle-graph.test.ts`, source/built graph | Agent code remains playground-only and knowledge/editor/renderer/inspection modules are absent from unrelated eager graphs. |
| `public_registry_cross_phase_workflow` | `agent-acceptance.test.ts`, built playground | Through `window.circPlayground` only, a clean project performs discovery, help, intentional diagnostic/repair, build/wait, live drive, isolated verify, inspection, and bounded text handoff with coherent project/source/artifact/session provenance and visible shared state. It does not stand in for a real client. |

The four rows above are automated integration tests run by Bun after the site build. The existing Phase 0–5 automated integration suites remain mandatory regressions.

**Real-client acceptance procedures:**

| Procedure Name | Scope | What It Proves |
|----------------|-------|----------------|
| `native_lifecycle_and_limit_acceptance` | Actual native WebMCP browser path | Every expressible known-tool edge reaches the application with documented state/codes; unknown names are provider rejections and old registrations disappear rather than fabricating application results. |
| `page_registry_lifecycle_and_limit_acceptance` | Actual external browser-tool path | The application edge matrix, unknown-tool result, retained-facade disposal, and native-unavailable fallback work through schema discovery and semantic calls; user text is data, not interpolated source. |
| `chatgpt_end_to_end_acceptance` | Actual supported ChatGPT browser-integrated agent | From isolated storage, ChatGPT completes every required core step via discovered native tools and records exact environment, calls/results, provenance, UI/console agreement, omissions, and captured downloads. |
| `opencode_end_to_end_acceptance` | Actual OpenCode with pinned browser tooling | From isolated storage, OpenCode completes every core step in the selected visible tab and independently proves the page-registry path. |
| `claude_code_end_to_end_acceptance` | Actual Claude Code with pinned browser tooling | From isolated storage, Claude Code completes every core step with evidence equivalent to OpenCode and no inferred pass from another client. |
| `acceptance_downloads_match_dispatch_receipts` | Real browser download capture per client | Every artifact/live/preload call dispatches exactly one file whose name/byte count match the receipt. Hashes identify captured bytes; memory bytes match source/readback, and WASM validates/decodes/behaves as the named artifact. Receipts still say only dispatched/completion unknown. |
| `acceptance_reload_persists_only_documented_state` | Each isolated client profile | Project/files/entry/settings/source preloads restore as documented; page/session IDs, live pins/RAM, transient highlight, operations, and ephemeral result stores do not masquerade as restored state. |

These are recorded operator procedures, not Bun tests and not covered by the shell command below.

**Human review gates:**

| Review Name | Artifact | What It Asserts |
|-------------|----------|----------------|
| `acceptance_evidence_is_complete_and_redacted` | Human review of guide and STATUS | Every mandatory cell names a tested commit/environment/path and decisive evidence or concrete blocker; no secrets, account data, private source, local profile paths, or unsupported success claims are present. |
| `final_usage_and_decisions_match_behavior` | Documentation review plus public guide route | Setup commands, tab selection, native/page recipes, privacy, limits, lifecycle, exports, troubleshooting, compatibility, and ADR statements match the observed released clients and shipped application. |

Run the required final site gate from `site/`, after stopping any development or preview server:

```sh
bun --bun run typecheck && bun --bun run build && bun test && bun run bundle
```

Run the built site only after that command succeeds:

```sh
bun --bun run preview --host 127.0.0.1
```

Use Astro's printed URL or the Phase 0-authorized static origin. Record the exact Bun version and all command results. Do not run `dev` concurrently with `build`; both invoke generators that write `site/public/`. Run `zig build test-all` only if a separately approved fix touches Zig, and run renderer repository gates/site pin checks only if a separately approved fix touches the renderer.

For each actual client, select the visible playground tab through that client's verified connection method, discover schemas, and make semantic tool calls. Evidence records exact bounded calls/results and provenance; large payloads use excerpt/length/hash records. Direct controller calls, `el.__playground`, DOM scraping, mocked native registration/downloads, screenshots, or a different client's successful run are supporting evidence only. Any required `blocked` or `fail` result keeps Phase 6 and the initiative incomplete.

## Open Questions / Spikes

None — phase is fully specified. Exact client/browser/connection-tool/API versions are measured values established by Phase 0 and repeated in Phase 6 evidence, not unresolved design choices. Implementation may make narrow contract-preserving fixes, but must stop for human review before changing a public contract, adding infrastructure/dependencies, substituting a target client, weakening evidence, or archiving/deploying the initiative.
