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

*Tables below were completed 2026-05-04. Phase 1 deletions had already landed in the repo before this audit file was filled; rows still record the correct classification and the phase that owns removal (or **Phase 1 (shipped)** where applicable).*

### Baseline

```
zig build test result: PASS (exit 0)
Date: 2026-05-04
Runner: Zig 0.15.x via `zig build test` (full suite registered in build.zig)
```

### Known Suspects

| Item | Type | Status | Reachable From | Phase That Deletes It |
|------|------|--------|----------------|-----------------------|
| `lib/wasm.zig` | file | dead | none (was `build.zig` wasm executable only; also `lib/wasm.zig` internal imports) | Phase 1 (shipped) |
| `lib/transport.zig` | file | live | `lib/circuit.zig` (`encodeState`), `lib/orchestrator/embed.zig` (@embedFile), `tests/helpers/wasm_run.zig` (fixture path string) | kept (live) — optional future removal after moving encoding off `transport` |
| `main.zig` (repo root) | file | dead | none | Phase 2 (shipped) |
| `lib/compiler.zig` | file | dead | none | Phase 2 (shipped) |
| `src/` | directory | dead | none (TypeScript/browser tree; not on compiler path) | Phase 1 (shipped) |
| `example/` | directory | dead | none (browser demo; often gitignored; wasm install step used it pre–Phase 1) | Phase 1 (shipped) |
| `package.json` | file | dead | none | Phase 1 (shipped) |
| `tsconfig.json` | file | dead | none | Phase 1 (shipped) |
| `bun.lock` | file | dead | none | Phase 1 (shipped) |
| `node_modules/` | directory | dead | none | Phase 1 (shipped) |
| `wasm` user step (`zig build wasm`) | build-target | dead | none (step removed with wasm artifact) | Phase 1 (shipped) |
| `wasm_step` (PLAN name for same step; Zig identifier `wasm_step` in pre-removal `build.zig`) | build-target | dead | none | Phase 1 (shipped) |
| `logic-sim` executable / step | build-target | live | `build.zig` | Phase 2 (pending) |
| `compiler` step | build-target | live | `build.zig` | Phase 2 (pending) |
| `compiler:run` step | build-target | live | `build.zig` | Phase 2 (pending) |
| `run` step | build-target | live | `build.zig` | Phase 2 (pending) |
| Commented-out lines in `build.zig` (e.g. `parser_lib.step.dependOn`, `compiler_step.dependOn` / `run_step` / old wasm deps, `wasm_lib.linkSystemLibrary`) | symbol | live | `build.zig` (inactive build wiring, still present as comments) | Phase 3 |

### Newly Discovered Items

*Independent discovery: high-value paths not named in `PLANS_PROMPT.md` suspect list but relevant to reachability and later phases.*

| Item | Type | Status | Reachable From | Phase That Deletes It |
|------|------|--------|----------------|-----------------------|
| `cmd/circ-compile/main.zig` | file | live | Production CLI entry (and `build.zig` `circ-compile` target) | kept (live) |
| `orchestrator_embed_module.zig` | file | live | `build.zig` (orchestrator / embed test module graph) | kept (live) — see PLAN recurring traps |
| `lib/orchestrator/embed.zig` | file | live | `orchestrator_embed_module.zig`, tests | kept (live) |
| `templates/build.zig` | file | live | `lib/orchestrator/embed.zig` (@embedFile) | kept (live) |
| `templates/main.zig` | file | live | `lib/orchestrator/embed.zig` (@embedFile) | kept (live) |

## Audit sign-off (Slice 4)

**Execution agent:** tables above are complete (no empty cells); `zig build test` passed on 2026-05-04 after documentation update.

**Human reviewer:** please explicitly approve this inventory (reply or commit note) before treating Phase 0 as formally closed. **Phase 2 (2026-05-04):** retained `lib/transport.zig` per live `circuit` dependency; legacy `main.zig` / `lib/compiler.zig` removed.

## Open Questions / Spikes

- **Optional:** Relocate `transport.encodeState` if the project later wants a single file to own all simulation encoding; not required for Phases 1–3 of the dead-code initiative.
