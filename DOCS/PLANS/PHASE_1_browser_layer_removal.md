# Phase 1 — Browser Layer Removal

> **Dependencies:** Phase 0 (Audit) must be complete and signed off before any deletions begin.
> **Warnings:** `lib/transport.zig` is NOT deleted in this phase — it slides to Phase 2 to keep the build coherent (`main.zig` still imports it and its build targets are not removed until Phase 2). Do not touch `orchestrator_embed_module.zig` or `lib/circuit.zig`. Deleting `lib/wasm.zig` does not affect `lib/circuit.zig`; they are independent.

## Goal

After this phase the TypeScript/browser application tree and the WASM Zig library are gone from the repository. A developer running `zig build test` sees a clean pass. The `wasm` and `wasm_step` build targets no longer exist in `build.zig`. Nothing that is reachable from `cmd/circ-compile/main.zig` or the active test suite has been touched.

## Scope

**In scope:**
- Delete the frontend application tree: `example/`, `src/`
- Delete TypeScript tooling files: `package.json`, `tsconfig.json`, `bun.lock`, `node_modules/`
- Delete `lib/wasm.zig`
- Remove the `wasm` and `wasm_step` build targets from `build.zig`, including any `b.installArtifact`, step dependencies, or option wiring that exclusively serves those targets
- `zig build test` passes clean after each slice

**Explicitly deferred:**
- `lib/transport.zig` — Phase 2 (still imported by `main.zig`; deleting it here would break the `logic-sim`/`run` targets)
- `main.zig` (repo root) and `lib/compiler.zig` — Phase 2
- Commented-out lines remaining in `build.zig` after wasm wiring is removed — Phase 3
- Unreferenced symbols inside otherwise-live `.zig` files — Phase 4

## File & Module Topology

**New files:** None

**Modified files:**

| Module/Package | File | Change |
|----------------|------|--------|
| Build system | `build.zig` | Remove `wasm` and `wasm_step` target declarations, their `b.installArtifact` calls, and any step dependencies that exclusively serve those targets |

**Deleted files/directories:**

| Path | Type | Slice |
|------|------|-------|
| `example/` | directory tree | 1 |
| `src/` | directory tree | 1 |
| `package.json` | file | 1 |
| `tsconfig.json` | file | 1 |
| `bun.lock` | file | 1 |
| `node_modules/` | directory tree | 1 |
| `lib/wasm.zig` | file | 2 |

**New dependencies:** None

## Data & State

No new types, interfaces, or schemas are introduced. The only structural change is `build.zig` losing the wasm artifact registrations. After Slice 2 the wasm-related section of `build.zig` must be absent — not commented out (commented-out wiring is Phase 3 scope; anything added or left commented in this phase would become Phase 3 work).

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines, workers, or build steps are introduced. All work is file deletions and text edits to `build.zig`.

## Persistence & I/O

File system only:
- **Slice 1:** recursive delete of `example/`, `src/`, and the four TypeScript tooling files/dirs
- **Slice 2:** delete `lib/wasm.zig`; targeted edits to `build.zig`

No database, network, or external API is touched.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Frontend tree removal | `example/`, `src/`, `package.json`, `tsconfig.json`, `bun.lock`, `node_modules/` deleted from the repository | `zig build test` exits 0 |
| 2 | Zig WASM library removal | `lib/wasm.zig` deleted; `wasm` and `wasm_step` targets and all their exclusive wiring removed from `build.zig` | `zig build test` exits 0; `zig build wasm` exits non-zero with "no target named 'wasm'" (confirms removal) |

## Tests

**Unit tests:** N/A — this phase contains no new or modified logic.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| Post-slice-1 suite | Full `zig build test` | Removing the frontend tree does not break any registered test binary |
| Post-slice-2 suite | Full `zig build test` | Removing `lib/wasm.zig` and the wasm build targets does not break any registered test binary |
| Wasm target absent | `zig build wasm` (expect failure) | Confirms the `wasm` target is gone from `build.zig`, not merely unreachable |

Run command: `zig build test`

## Open Questions / Spikes

None — phase is fully specified.
