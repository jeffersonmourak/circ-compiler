# Archived plan: dead-code-removal

**Canonical commit:** `cf0a34a1c8ae8aad373ccf099fdc0c8c98a097a8` (pre-squash, not in history; the work landed as `30cf95a`) (`cf0a34a Remove dead code from \`lib/log.zig\` and delete unused \`lib/syntax/helpers.zig\``)
**Archived on:** 2026-05-04
**Plan duration:** 2026-05-04 → 2026-05-04

> This file is a highlight view. The plan bundle (plan prompt, phase plans, STATUS log) lived on a branch that was squash-merged as `30cf95a` (`Add dead code removal planning documentation (#1)`); the pre-squash commit named above is not in this repository's history, so the unabridged source is not recoverable from git.

## Goal & scope

The initiative removes all dead code from the `circ-compiler` codebase inherited from its previous identity as `circ-renderer-z` — a dynamic browser rendering library that was re-architected into a static CLI compiler. Dead surface removed: the browser-facing dynamic API layer (`lib/wasm.zig`), legacy executables and debug harnesses (`main.zig`, `lib/compiler.zig`), the full TypeScript/browser application (`src/`, `example/`, frontend tooling), commented-out build wiring in `build.zig`, and orphaned symbols in otherwise-live modules. The initiative is complete when every symbol, file, and build target not reachable from `cmd/circ-compile/main.zig` or the active test suite has been deleted and `zig build test` passes clean. Architectural constraints held throughout: the simulation engine (`lib/circuit.zig`) stays WASM/JS-agnostic; the compiler pipeline is the production code path; frozen v0 export names and diagnostic codes are untouched; the `getTopology()` placeholder payload is intentional scaffolding and was never removed.

## Phase-by-phase highlights

### Phase 0 — Audit

Produce a written dead-code inventory before any deletions begin, mapping every suspect file, build target, and symbol to live/dead status.

- **Known-suspects table completed:** 14 items classified — `lib/wasm.zig` (dead), `lib/transport.zig` (live via `lib/circuit.zig::encodeState`), `main.zig` / `lib/compiler.zig` (dead), `src/` / `example/` / `package.json` / `tsconfig.json` / `bun.lock` / `node_modules/` (dead), `wasm` / `wasm_step` build targets (dead), legacy build steps (dead), commented-out `build.zig` wiring (Phase 3).
- **Newly-discovered items table:** 5 items confirmed live — `cmd/circ-compile/main.zig`, `orchestrator_embed_module.zig`, `lib/orchestrator/embed.zig`, `templates/build.zig`, `templates/main.zig`.
- Audit written retroactively (Phases 1–2 had already landed); `lib/transport.zig` retained after confirming `lib/circuit.zig` dependency — Phase 2 note updated accordingly.

### Phase 1 — Browser layer removal

Remove the TypeScript/browser application tree and the WASM Zig library; `zig build wasm` must fail with "no step named 'wasm'".

- Deleted frontend tree: `src/`, `example/`, `package.json`, `tsconfig.json`, `bun.lock`, `node_modules/`.
- Deleted `lib/wasm.zig`; removed `circ-renderer-lib-wasm` executable, its `b.installArtifact`, install paths under `zig-out`, former `example/` wasm copy, and the `wasm` step from `build.zig`.

### Phase 2 — Legacy Zig binaries

Remove the legacy debug harness and compiler prototype; `zig build logic-sim` / `zig build run` must fail with "no step named".

- Removed `logic-sim`, `compiler`, `compiler:run`, `run` steps and their exclusive `b.installArtifact` / step wiring from `build.zig`.
- Deleted `main.zig` (repo root) and `lib/compiler.zig`; dropped `unit_tests` / `run_unit_tests` from the `test` step (no `test` blocks lived in `main.zig`).
- `lib/transport.zig` retained — `lib/circuit.zig::encodeState` is a live caller.

### Phase 3 — Stubs and placeholders

Strip all commented-out lines from `build.zig`; document intentional WIP stubs; correct stale architecture docs.

- Removed all full-line `//` comments from `build.zig` (file banner, section dividers, commented `parser_lib.step.dependOn`); `grep -n '^\s*//' build.zig` → zero matches.
- Corrected stale "WIP / not yet connected" description of `lib/syntax/` in `DOCS/architecture.md` (the syntax layer is fully connected and tested).
- WIP inventory appended to STATUS for intentional `getTopology()` / `getPendingEvents` scaffolding in `lib/emit/main.zig`, `lib/emit/project.zig`, `lib/emit/runtime.zig` (static placeholder payloads; frozen API surface — see papercuts below).
- `lib/parser.c` and `lib/parser.h` untouched (vendored generated sources, required at build time).

### Phase 4 — Surgical dead symbols

Grep-and-verify pass over all active `.zig` files; remove every confirmed orphan.

- **Audit checklist:** all 5 "Newly Discovered" rows from Phase 0 confirmed live — no removals.
- **Grep discovery:** deleted `lib/syntax/helpers.zig` (zero `@import` references anywhere in the tree); trimmed `lib/log.zig` — removed unused `bufPrint` binding and never-called `clearLogArena` / `deinitLogArena` / `clearLogPointer` (legacy WASM host hooks, no remaining callers after browser-WASM removal), plus stale commented-out blocks.

## Diagnostic / API surface

This initiative made no changes to the diagnostic codes, WASM export surface, or CLI flags. The frozen v0 surface (diagnostics `E001`–`E013`, `W001`–`W003`; WASM runtime exports; CLI flags and modes) is documented in [`DOCS/archive/plan-v0.md`](plan-v0.md).

## Known papercuts carried forward

- **`lib/emit/main.zig`, `lib/emit/project.zig`, `lib/emit/runtime.zig` — static `topology_blob` / `empty_pending`.** `getTopology()` serves a static literal `"debug-paths-v1"` payload; `getPendingEvents()` emits an empty buffer. These are intentional scaffolding for the frozen v0 export surface — do not remove. A future initiative must implement real topology serialisation before removing the stubs.
- **`lib/transport.zig` retained.** `lib/circuit.zig::encodeState` is a live caller; `transport.zig` was out of scope for removal. Future: relocate `encodeState` (and related types) into `lib/circuit.zig` or a dedicated `lib/circuit/encode.zig`, then delete `transport.zig` in a focused slice.

## Decisions & specs that survived the plan

Authoritative docs remain outside this archive:

- `DOCS/architecture.md`
- `DOCS/circuit-format.md`
- `DOCS/wasm-api.md`
- `DOCS/simulation-engine.md`
- `DOCS/decisions/` (see `DOCS/decisions/index.md`)
