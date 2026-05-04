# Phase 0 — Audit

> **Dependencies:** None
> **Warnings:** No code changes in this phase. Any file that appears dead must be confirmed against `cmd/circ-compile/main.zig` reachability and the active test suite before being marked dead — do not guess.

## Goal

The execution agent traces the full reachability graph from `cmd/circ-compile/main.zig` and the active test suite, classifies every suspect file, build target, and symbol as live or dead, and produces a signed-off inventory table in this file. Once this phase is complete, every item the plan prompt names — plus any newly discovered dead items — has an explicit status and a `phase-that-deletes-it` assignment (or is confirmed live). No code is changed. The deliverable is this document, reviewed and approved by the human.

## Scope

**In scope:**
- Classify all files, build targets, and symbols explicitly named as suspects in `DOCS/PLANS_PROMPT.md`
- Independent discovery: symbol-trace from `cmd/circ-compile/main.zig` outward; grep all `.zig` files for unreferenced functions, unused imports, and orphaned test fixtures
- Newly discovered dead items listed in a separate table, clearly distinguished from known suspects
- Baseline `zig build test` run to confirm the suite starts green

**Explicitly deferred:**
- All deletions, edits, and code changes — those belong to Phases 1–4
- Deciding exact deletion order within a phase (that is each phase spec's job)

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|----------------|------|----------------|
| DOCS/PLANS | `DOCS/PLANS/PHASE_0_audit.md` | This spec; also the home of the completed inventory table |

**Modified files:** None — this phase is read-only.

**New dependencies:** None

## Data & State

The inventory is a Markdown table. Two tables are produced: one for **known suspects** (items named in `DOCS/PLANS_PROMPT.md`) and one for **newly discovered items** (found only via independent discovery). Schema is identical for both:

```
| Item | Type | Status | Reachable From | Phase That Deletes It |
|------|------|--------|----------------|-----------------------|
```

Field definitions:

- **Item** — file path, build target name, or `file.zig::symbol_name`
- **Type** — `file`, `directory`, `build-target`, or `symbol`
- **Status** — `dead`, `live`, or `uncertain` (needs a spike)
- **Reachable From** — the nearest live caller/importer, or `none` if dead
- **Phase That Deletes It** — `Phase 1`, `Phase 2`, `Phase 3`, `Phase 4`, or `kept (live)` / `kept (uncertain — spike required)`

Every row must have a non-empty value in every field before the phase is considered complete.

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines, workers, or build steps are introduced. The agent reads files, runs read-only shell commands, and writes this document.

## Persistence & I/O

The sole I/O is:
- Read: all `.zig` source files, `build.zig`, frontend tooling files (`package.json`, `tsconfig.json`), and any file the discovery pass surfaces
- Write: this file (`DOCS/PLANS/PHASE_0_audit.md`) — the completed inventory tables are appended in Slice 3

No database, network, or external API is touched.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Baseline green | Run `zig build test`; record pass/fail in a "Baseline" section appended to this file | `zig build test` exits 0 |
| 2 | Known-suspect inventory | Classify every item named in `DOCS/PLANS_PROMPT.md` (files, directories, build targets, commented-out wiring) against the schema; append the **Known Suspects** table to this file | All rows have non-empty fields; human reviews table |
| 3 | Discovery pass | Symbol-trace from `cmd/circ-compile/main.zig`; grep all `.zig` files for unreferenced exports, unused imports, orphaned fixtures; append the **Newly Discovered Items** table | Newly discovered table is non-empty or explicitly states "none found"; human reviews table |
| 4 | Finalize & sign-off | Ensure every row in both tables has `phase-that-deletes-it` populated or `kept`; no `uncertain` rows remain unaddressed; human approves | Human explicit approval; `zig build test` still exits 0 |

## Tests

**Unit tests:** N/A — this phase produces a document, not code.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| Baseline suite | Full `zig build test` | All registered test binaries pass before any changes are made; establishes the green baseline that all subsequent phases must preserve |
| Final suite check | Full `zig build test` | Suite still passes after Slice 4 (no accidental edits crept in during the audit) |

Run command: `zig build test`

## Inventory Tables

*The execution agent appends these tables during Slices 1–3. They are empty until the phase is executed.*

### Baseline

```
zig build test result: TODO(phase0)
Date: TODO(phase0)
```

### Known Suspects

| Item | Type | Status | Reachable From | Phase That Deletes It |
|------|------|--------|----------------|-----------------------|
| `lib/wasm.zig` | file | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `lib/transport.zig` | file | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `main.zig` (repo root) | file | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `lib/compiler.zig` | file | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `src/` | directory | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `example/` | directory | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `package.json` | file | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `tsconfig.json` | file | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `bun.lock` | file | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `node_modules/` | directory | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `wasm` build target | build-target | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `wasm_step` build target | build-target | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `logic-sim` build target | build-target | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `compiler` build target | build-target | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `compiler:run` build target | build-target | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| `run` build target | build-target | TODO(phase0) | TODO(phase0) | TODO(phase0) |
| Commented-out lines in `build.zig` (parser-gen step, `wasm_lib.linkSystemLibrary`, etc.) | symbol | TODO(phase0) | TODO(phase0) | TODO(phase0) |

### Newly Discovered Items

*To be populated by the discovery pass (Slice 3). Any item found here that was not in the Known Suspects table above must be listed with full schema fields.*

| Item | Type | Status | Reachable From | Phase That Deletes It |
|------|------|--------|----------------|-----------------------|
| | | | | |

## Open Questions / Spikes

None — phase is fully specified.
