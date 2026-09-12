# agent-playground

### One application registry serves native and external agents

**Decision.** `circ_get_status` has one descriptor, validation path, handler, and JSON-safe result envelope. `window.circPlayground` and native WebMCP invoke that registry rather than reading rendered text or driving UI controls.

**Rationale.** A shared dispatcher keeps browser-specific registration details from changing tool semantics and gives external agents a usable path when native browser support is absent.

**Alternatives.** A custom MCP backend or browser bridge (violates static deployment); exposing the mutable test hook (leaks private page state); separate native/external handlers (contracts drift).

### Native registration is abort-scoped and optional

**Decision.** The investigated WebMCP mapping uses `document.modelContext.registerTool(descriptor, { signal })`; the callback returns a text content block containing the shared JSON result. The page aborts registration on suspend/disposal and preserves the external registry when native detection or registration fails.

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
