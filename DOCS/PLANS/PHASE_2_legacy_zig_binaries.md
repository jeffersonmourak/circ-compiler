# Phase 2 — Legacy Zig Binaries

> **Dependencies:** Phase 1 (Browser Layer Removal) must be complete before this phase begins.
> **Warnings:** `orchestrator_embed_module.zig` re-exports from `lib/orchestrator/embed.zig` and is wired as a build module for the orchestrator test suite — do NOT delete it. Confirm the test wiring in `build.zig` around line 620 is untouched after every edit. `lib/transport.zig` lands in this phase (slid from Phase 1 for build coherence — `main.zig` still imported it at the end of Phase 1).

## Goal

After this phase the two legacy Zig entry points and the transport shim are gone, and `build.zig` contains no build targets that reference them. A developer running `zig build test` sees a clean pass. The `logic-sim`, `compiler`, `compiler:run`, and `run` build targets no longer exist. The only remaining entry point compiled by the build system is `cmd/circ-compile/main.zig`.

## Scope

**In scope:**
- Remove `logic-sim`, `compiler`, `compiler:run`, and `run` build targets from `build.zig`
- Remove any `b.installArtifact` calls and step dependencies that exclusively serve those targets
- Delete `main.zig` (repo root), `lib/compiler.zig`, and `lib/transport.zig`
- `zig build test` passes clean after each slice

**Explicitly deferred:**
- Commented-out lines remaining in `build.zig` after target removal — Phase 3
- Unreferenced symbols inside otherwise-live `.zig` files — Phase 4
- Any stubs or placeholder implementations in active modules — Phase 3/4

## File & Module Topology

**New files:** None

**Modified files:**

| Module/Package | File | Change |
|----------------|------|--------|
| Build system | `build.zig` | Remove `logic-sim`, `compiler`, `compiler:run`, `run` target declarations, their `b.installArtifact` calls, and any step dependencies that exclusively serve those targets |

**Deleted files:**

| Path | Type | Slice |
|------|------|-------|
| `main.zig` (repo root) | file | 2 |
| `lib/compiler.zig` | file | 2 |
| `lib/transport.zig` | file | 2 |

**New dependencies:** None

## Data & State

No new types, interfaces, or schemas are introduced. This phase is pure deletion. After Slice 1, `build.zig` must have no references to `main.zig`, `lib/compiler.zig`, or `lib/transport.zig`. After Slice 2 those files are gone from disk.

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines, workers, or build steps are introduced. All work is targeted edits to `build.zig` followed by file deletions.

## Persistence & I/O

File system only:
- **Slice 1:** targeted edits to `build.zig` removing dead build targets
- **Slice 2:** delete `main.zig`, `lib/compiler.zig`, `lib/transport.zig`

No database, network, or external API is touched.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Strip dead build targets | `logic-sim`, `compiler`, `compiler:run`, `run` targets and their exclusive `b.installArtifact`/step wiring removed from `build.zig`; source files still present on disk | `zig build test` exits 0; `zig build logic-sim` exits non-zero with "no target named 'logic-sim'" |
| 2 | Delete legacy source files | `main.zig`, `lib/compiler.zig`, `lib/transport.zig` deleted from disk | `zig build test` exits 0 |

## Tests

**Unit tests:** N/A — this phase contains no new or modified logic.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| Post-slice-1 suite | Full `zig build test` | Stripping the dead build targets does not break any registered test binary |
| Dead targets absent | `zig build logic-sim` (expect failure) | Confirms `logic-sim` target is gone from `build.zig` |
| Post-slice-2 suite | Full `zig build test` | Deleting `main.zig`, `lib/compiler.zig`, `lib/transport.zig` does not break any registered test binary |
| Orchestrator tests intact | `zig build test` (verify orchestrator suite passes) | Confirms `orchestrator_embed_module.zig` and its `build.zig` wiring around line 620 were not disturbed |

Run command: `zig build test`

## Open Questions / Spikes

None — phase is fully specified.
