# Phase 3 — Stubs and Placeholders

> **Dependencies:** Phase 2 (Legacy Zig Binaries) must be complete before this phase begins.
> **Warnings:** Do NOT delete `lib/parser.c` or `lib/parser.h` — they are vendored generated sources required at build time; only the commented-out generation step wiring in `build.zig` is removed. Do NOT touch the `getTopology()` placeholder — its static payload is intentional future-implementation scaffolding and part of the frozen v0 API surface.

## Goal

After this phase `build.zig` contains zero commented-out lines, confirmed by a grep check. A WIP/stub inventory is appended to `DOCS/STATUS.md` so the user can address those items in a future initiative. The stale `lib/syntax/` "WIP / not yet connected" description in `DOCS/Architecture.md` is corrected. `zig build test` passes clean. No source code is deleted; this phase edits and documents, it does not remove logic.

## Scope

**In scope:**
- Remove every commented-out line from `build.zig` (parser-gen step wiring, `wasm_lib.linkSystemLibrary`, and any other commented blocks left after Phases 1 and 2)
- Scan all active `.zig` files for WIP stubs and placeholder implementations; append a full inventory to `DOCS/STATUS.md`
- Correct the stale "WIP / not yet connected" description of `lib/syntax/` in `DOCS/Architecture.md`
- `zig build test` passes clean after each slice

**Explicitly deferred:**
- Removal of WIP stubs and placeholder implementations — user will triage from the `DOCS/STATUS.md` inventory in a future initiative
- Unreferenced symbols, unused imports, orphaned test fixtures — Phase 4
- Any new documentation beyond the `Architecture.md` correction and the STATUS.md entry

## File & Module Topology

**New files:** None

**Modified files:**

| Module/Package | File | Change |
|----------------|------|--------|
| Build system | `build.zig` | Remove all commented-out lines |
| Docs | `DOCS/STATUS.md` | Append WIP/stub inventory section |
| Docs | `DOCS/Architecture.md` | Correct stale `lib/syntax/` "WIP / not yet connected" description |

**Deleted files:** None — only lines within `build.zig` are removed.

**New dependencies:** None

## Data & State

No new types or schemas. The WIP inventory appended to `DOCS/STATUS.md` follows the existing STATUS entry format from `DOCS/PLANS_PROMPT.md`, extended with a `## WIP Inventory` subsection listing each stub found. Each entry carries:

```
| File | Symbol / Location | Marker | Notes |
|------|-------------------|--------|-------|
```

**Marker** is the indicator found in source: `// TODO`, `// FIXME`, `// WIP`, `@panic("TODO")`, `unreachable` used as a stub body, or an empty/trivial placeholder return.

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines, workers, or build steps are introduced. All work is targeted edits to existing files.

## Persistence & I/O

File system only:
- **Slice 1:** targeted line deletions in `build.zig`
- **Slice 2:** append to `DOCS/STATUS.md`; edit `DOCS/Architecture.md`

No database, network, or external API is touched.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | `build.zig` comment cleanup | All commented-out lines removed from `build.zig`; `lib/parser.c` and `lib/parser.h` untouched; `getTopology()` untouched | `zig build test` exits 0; `grep -n '^\s*//' build.zig` returns no output |
| 2 | WIP scan and docs correction | WIP inventory appended to `DOCS/STATUS.md`; `DOCS/Architecture.md` `lib/syntax/` description corrected | `zig build test` exits 0 (no code changed); human reviews inventory |

## Tests

**Unit tests:** N/A — this phase contains no new or modified logic.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| Post-slice-1 suite | Full `zig build test` | Removing commented-out lines from `build.zig` does not break any registered test binary |
| Grep check | `grep -n '^\s*//' build.zig` | Returns empty — zero commented-out lines remain |
| Post-slice-2 suite | Full `zig build test` | Doc edits introduced no accidental code change |

Run command: `zig build test`

## Open Questions / Spikes

None — phase is fully specified.
