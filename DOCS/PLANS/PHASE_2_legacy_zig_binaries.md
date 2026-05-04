# Phase 2 — Legacy Zig Binaries

> **Dependencies:** Phase 1 (Browser Layer Removal) must be complete before this phase begins.
> **Warnings:** `orchestrator_embed_module.zig` re-exports from `lib/orchestrator/embed.zig` and is wired as a build module for the orchestrator test suite — do NOT delete it. Confirm the test wiring in `build.zig` (orchestrator test modules) is untouched after every edit. **`lib/transport.zig` is not deleted in this phase:** `lib/circuit.zig` calls `transport.encodeState` on the simulation path (Phase 0 audit). Retain `transport` until encoding is inlined or moved (future slice / Phase 4), or the initiative explicitly scopes a refactor.

## Goal

After this phase the legacy debug harness (`main.zig`), the old `compiler` prototype binary (`lib/compiler.zig`), and their build steps are gone. A developer running `zig build test` sees a clean pass. The `logic-sim`, `compiler`, `compiler:run`, and `run` build targets no longer exist. The primary compiled CLI entry remains `cmd/circ-compile/main.zig` (plus per-target test binaries as registered in `build.zig`).

## Scope

**In scope:**
- Remove `logic-sim`, `compiler`, `compiler:run`, and `run` build targets from `build.zig`
- Remove any `b.installArtifact` calls and step dependencies that exclusively serve those targets
- Delete `main.zig` (repo root) and `lib/compiler.zig`
- Remove the empty root `unit_tests` artifact that existed only to anchor `main.zig` (no `test` blocks lived there)
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

**New dependencies:** None

## Data & State

No new types, interfaces, or schemas are introduced. This phase is pure deletion. After Slice 1, `build.zig` no longer declares the legacy executables or their steps; `main.zig` may still exist on disk only as an implementation detail until Slice 2. After Slice 2, `main.zig` and `lib/compiler.zig` are gone. **`lib/transport.zig` remains** (live via `lib/circuit.zig` and orchestrator embed fixtures).

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines, workers, or build steps are introduced. All work is targeted edits to `build.zig` followed by file deletions.

## Persistence & I/O

File system only:
- **Slice 1:** targeted edits to `build.zig` removing dead build targets
- **Slice 2:** delete `main.zig`, `lib/compiler.zig`; drop the `main.zig`-rooted `unit_tests` / `run_unit_tests` wiring from `build.zig` and `test` step

No database, network, or external API is touched.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Strip dead build targets | `logic-sim`, `compiler`, `compiler:run`, `run` targets and their exclusive `b.installArtifact`/step wiring removed from `build.zig`; source files still present on disk | `zig build test` exits 0; `zig build logic-sim` exits non-zero with "no target named 'logic-sim'" |
| 2 | Delete legacy source files | `main.zig`, `lib/compiler.zig` deleted from disk; `transport.zig` retained | `zig build test` exits 0 |

## Tests

**Unit tests:** N/A — this phase contains no new or modified logic.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| Post-slice-1 suite | Full `zig build test` | Stripping the dead build targets does not break any registered test binary |
| Dead targets absent | `zig build logic-sim` (expect failure) | Confirms `logic-sim` target is gone from `build.zig` |
| Post-slice-2 suite | Full `zig build test` | Deleting `main.zig` and `lib/compiler.zig` does not break any registered test binary |
| Orchestrator tests intact | `zig build test` (verify orchestrator suite passes) | Confirms `orchestrator_embed_module.zig` and its orchestrator-related `build.zig` wiring were not disturbed |

Run command: `zig build test`

## Open Questions / Spikes

- **Encoding home for `transport.encodeState`:** If the initiative later mandates removing `lib/transport.zig`, relocate `encodeState` (and related types) into `lib/circuit.zig` or a dedicated module (for example `lib/circuit/encode.zig`) first, then delete `transport.zig` in a focused follow-up.
