# Phase 4 — Surgical Dead Symbols

> **Dependencies:** Phase 3 (Stubs and Placeholders) must be complete before this phase begins.
> **Warnings:** The Zig compiler catches unused imports as compile errors but is silent on unreferenced functions — those require a manual grep-and-verify pass. Never remove a symbol solely because grep finds no callers; confirm by reading its declaration context and checking all aliased or indirect call sites. Do not remove `getTopology()`'s placeholder payload — it is frozen API scaffolding. Do not touch `orchestrator_embed_module.zig` without re-verifying the build wiring in `build.zig` around line 620.

## Goal

After this phase every symbol, function, import, and test fixture that is not reachable from `cmd/circ-compile/main.zig` or the active test suite has been removed from the active `.zig` files. `zig build test` passes clean. The codebase contains no confirmed-dead code at the symbol level — the dead-code removal initiative is complete.

## Scope

**In scope:**
- Use the Phase 0 audit's "Newly Discovered Items" table as the starting checklist; remove each confirmed-dead symbol in that table
- Follow with a fresh grep-and-verify pass over all active `.zig` files to catch anything the Phase 0 audit missed: unreferenced functions, unused imports, and orphaned test fixtures
- Run `zig build test` after each individual removal within both slices
- Human review stop after each full slice (checklist exhausted; grep pass exhausted)

**Explicitly deferred:**
- WIP stubs and placeholder implementations listed in `DOCS/STATUS.md` from Phase 3 — those are intentional and user-triaged
- Any new feature work or refactoring
- The `getTopology()` placeholder payload — frozen, never touched

**Active file set** (files in scope for the grep pass after Phases 1–3):

| File / Package | Notes |
|----------------|-------|
| `cmd/circ-compile/main.zig` | Entry point — reachability root |
| `lib/syntax/` | Active pipeline |
| `lib/ir/` | Active pipeline |
| `lib/validator/` | Active pipeline |
| `lib/emit/` | Active pipeline |
| `lib/orchestrator/` (incl. `embed.zig`) | Active pipeline + test suite anchor |
| `lib/circuit.zig` | Simulation engine |
| `orchestrator_embed_module.zig` | Live re-export shim for orchestrator tests |
| `build.zig` | Build system — orphaned test fixture registrations |

## File & Module Topology

**New files:** None

**Modified files:**

| Module/Package | File | Change |
|----------------|------|--------|
| Any active module | Various `.zig` files | Dead symbol removals confirmed by grep-and-verify |
| Build system | `build.zig` | Remove orphaned test fixture registrations, if any are found |

**New dependencies:** None

## Data & State

No new types or schemas. All changes are removals. The only state to track during execution is the running checklist (Phase 0 audit table rows marked done as each item is removed).

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines, workers, or build steps are introduced. The agent works through removals one symbol at a time.

**Verification method for unreferenced functions** (Zig does not report these):
1. List all `fn` and `pub fn` declarations in the target file.
2. For each candidate, `grep -r "<symbol_name>" --include="*.zig"` across all active files.
3. If the only match is the declaration line itself, mark as a dead candidate.
4. Read the declaration context to rule out indirect calls, comptime references, or export annotations before removing.
5. Run `zig build test` immediately after each removal.

## Persistence & I/O

File system only — targeted line/block deletions in active `.zig` files and `build.zig`. No database, network, or external API is touched.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Audit checklist removals | Every confirmed-dead symbol from the Phase 0 "Newly Discovered Items" table removed; each removal followed immediately by `zig build test` | `zig build test` exits 0 after all checklist items are processed; human reviews the set of removals |
| 2 | Grep discovery pass | Fresh grep-and-verify sweep over all active `.zig` files; every newly confirmed-dead item removed; each removal followed immediately by `zig build test` | `zig build test` exits 0; grep finds no further unreferenced candidates; human reviews the set of removals |

## Tests

**Unit tests:** N/A — this phase removes dead code; it introduces no new logic.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| Per-removal suite | Full `zig build test` after each symbol removal | Each individual removal leaves the suite green; isolates any accidental live-symbol deletion immediately |
| Post-slice-1 suite | Full `zig build test` | All audit-checklist removals are clean |
| Post-slice-2 suite | Full `zig build test` | Grep-pass removals are clean; initiative is complete |
| No further candidates | `grep -rn "fn " lib/ cmd/ --include="*.zig"` cross-referenced against call sites | No unreferenced functions remain in the active file set |

Run command: `zig build test`

## Open Questions / Spikes

None — phase is fully specified.
