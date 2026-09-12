# agent-playground

### One application registry serves native and external agents

**Decision.** `circ_get_status` has one descriptor, validation path, handler, and JSON-safe result envelope. `window.circPlayground` and native WebMCP invoke that registry rather than reading rendered text or driving UI controls.

**Rationale.** A shared dispatcher keeps browser-specific registration details from changing tool semantics and gives external agents a usable path when native browser support is absent.

**Alternatives.** A custom MCP backend or browser bridge (violates static deployment); exposing the mutable test hook (leaks private page state); separate native/external handlers (contracts drift).

### Native registration is abort-scoped and optional

**Decision.** The investigated WebMCP mapping uses `document.modelContext.registerTool(descriptor, { signal })`; the callback returns a text content block containing the shared JSON result. The page aborts registration on suspend/disposal through `pagehide`, preserving Chrome bfcache eligibility, and preserves the external registry when native detection or registration fails. Registration is transactional: if a provider rejects one descriptor, every already-registered descriptor is aborted/disposed before reporting failure.

**Rationale.** The WebMCP explainer documents abort-based unregistration. Feature detection avoids user-agent assumptions, while optional registration preserves the serverless external fallback.

**Alternatives.** A WebMCP polyfill (would falsely claim browser support); keeping registrations across bfcache suspension (can leave stale exposure); disabling the page API on native failure (removes the documented external path).

### Status is observational until revision tracking ships

**Decision.** Phase 0 reports current page state in one synchronous snapshot, with provenance explicitly `untracked` and all revision/session identity fields null. Reads never initialize the compiler or simulator.

**Rationale.** Existing pipeline records are useful to observe but do not provide Phase 1's captured request/revision guarantees. Reporting them as authoritative would make stale output look current.

**Alternatives.** Deriving identity from debounce counters or artifact hashes (not authoritative); waiting for Phase 1 before exposing any status (delays connectivity proof).

### Help is an immutable, lazy local corpus

**Decision.** `circ_help` is one read-only action dispatcher over generated content-addressed static assets. The browser verifies a page-pinned manifest, index, and only the requested shard; the lightweight descriptor dynamically imports the retrieval code only when invoked.

**Rationale.** Canonical DOCS, gallery, tour, and validator inputs can be checked against the committed compiler during generation without making browser help calls compile, mutate a workspace, or contact a search service. Immutable corpus and compiler identifiers make citations and returned examples auditable across deployments.

**Alternatives.** Bundling source in the playground island (breaks the lazy/budget boundary); reading repository files in the browser (not available in static deployment); hosted/vector search (adds a backend and nondeterministic results).

### Authoring commits are revision-guarded and reuse the visible workspace

**Decision.** Agent create, open, file mutation, entry selection, compile settings, explicit compilation, and diagnostic reads enter through the same page registry/controller boundary as existing workspace state. Ordered file mutations are fully validated against an immutable draft before changing tabs, storage, revisions, or compiler scheduling. Compiler diagnostic pages retain converted ranges from the exact request that produced them.

**Rationale.** A stale agent call must never partially overwrite a person’s active work, and a delayed compile reply must never be remapped through newer source. Keeping the existing worker and scheduling path means visible UI work and agent work retain the same operation provenance.

**Alternatives.** A separate agent compiler or workspace shadow copy (would drift from the visible editor); applying each batch item immediately (permits partial edits); remapping historical diagnostics through current tabs (can point at unrelated text).

### Acceptance evidence keeps application and provider boundaries separate

**Decision.** Final acceptance records actual native and page-registry calls with their application provenance, visible agreement, bounded-result identity, and external download capture. Native provider rejection before dispatch is recorded as provider behavior; only page-registry calls can assert application `UNKNOWN_TOOL` or retained-facade `PAGE_DISPOSED`.

**Rationale.** Browser tooling can reject a name before the page callback and browser download dispatch cannot promise a filesystem write. Treating either as an application result would fabricate evidence and hide the boundary a user must diagnose.

**Alternatives.** Treat native rejection as an application code (false attribution); treat a dispatch receipt as disk completion (unsupported); use mocks or a browser runner as real-client proof (does not exercise the selected client).

### Browser-local work and agent disclosure are distinct

**Decision.** Public copy says that compilation, simulation, browser storage, and knowledge search execute locally and that the static deployment has no application backend. It separately says that requested tool arguments and results are shared with the connected agent.

**Rationale.** The first statement explains the architecture and local project-data boundary; the second prevents an inaccurate claim that nothing leaves the page once an agent is connected.

**Alternatives.** "Nothing leaves the page" (false for requested agent calls); "no server" (ambiguous about static hosting and browser requests); a custom relay (outside the static architecture).

### RAM images are live session data, not source preloads

**Decision.** The RAM acceptance workflow loads the corpus image through `circ_update_memory`, verifies the ordered clocked write, then verifies that reset leaves RAM undefined. `circ_set_memory_preload` remains ROM-only and returns `PRELOAD_CONFLICT` for RAM.

**Rationale.** RAM contents belong to the active simulation session, so persisting them as source-owned state would contradict the existing Phase 4 reset, replacement, and reload contract. The corpus image is valid runtime initialization evidence, not a declaration setting.

**Alternatives.** Persist RAM images as source preloads (changes the established state/persistence contract); accept reset restoring a live image (mislabels ephemeral state as source configuration); omit RAM reset evidence (fails to prove lifecycle semantics).
