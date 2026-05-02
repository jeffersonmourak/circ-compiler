# Archived plan: v0

**Canonical commit:** `e9fb9da40d338d58dc893134b5caadd0caac0f9e` (`e9fb9da Rename project from `circ-renderer-z` to `circ-compiler` and update license to GPL-3.0`)
**Archived on:** 2026-05-02
**Plan duration:** 2026-05-01 → 2026-05-02

> This file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the commit referenced above. Check that commit out (`git show e9fb9da40d338d58dc893134b5caadd0caac0f9e:DOCS/PLANS_PROMPT.md`, etc.) when you need the unabridged source.

## Goal & scope

`circ-compiler` is a Zig CLI that parses `.circ` sources, validates them, lowers them to IR and emitted Zig (one `buildFile_<id>` / `buildXxx` function per source file), and runs `zig build` to produce a self-contained `.wasm` whose topology and wiring are fixed at compile time (no runtime graph mutation). The simulation engine stays unaware of source files; debug paths and file-info blobs live in the emitted artifact. The compiled runtime is pull-based (fixed exports, no dynamic `createComponent` / callback shape from the browser library). langlang-generated parser sources are vendored; the CLI embeds engine + templates via `@embedFile` and writes a temp workspace before the subprocess build. Hard errors block emission; built-in gates (`or`, `nand`, `nor`, `xor`, `xnor`) are normal `.circ` modules on a virtual `<builtin>/` path through the same pipeline as user code.

## Phase-by-phase highlights

### Phase 0 — Scaffolding

Stand up `zig build test`, the `tests/fixtures/{circuits,expected-zig,expected-wasm,expected-diagnostics}` layout, `tests/README.md`, and `tests/helpers/golden.zig` with `expectGolden` plus `UPDATE_GOLDENS=1` update mode (`tests/helpers/golden_test.zig`).

### Phase 1 — Engine baseline

Add `output_pin` to `lib/circuit.zig` / `lib/wasm.zig`, wire-equivalent pass-through and scheduling (`test "output_pin: passes input through"`), and `lib/transport.zig` encoding (`test "transport: encodes output_pin state"`).

### Phase 2 — Parser & AST/IR

Typed AST + `Span` (`lib/syntax/ast.zig`, `lib/syntax/span.zig`); parse-tree → AST with golden dumps (`tests/syntax/translate_test.zig`, `tests/fixtures/expected-ast/*.txt`); IR types (`lib/ir/types.zig`); single-file AST→IR resolver with flattening and unresolved markers (`lib/ir/resolver.zig`, `tests/ir/resolver_test.zig`, `tests/fixtures/expected-ir/*.txt`).

### Phase 3 — Semantic validation

Stable codes `E001`–`E008`, `W001`–`W002` plus formatter in `lib/validator/codes.zig` / `lib/validator/diagnostics.zig` (`tests/validator/diagnostics_test.zig`); name passes (`tests/validator/name_passes_test.zig` with `E001_undeclared.circ`, `E005_duplicate_name.circ`, `E006_shadows_builtin.circ`); structural passes (`tests/validator/structural_passes_test.zig` for `E002`–`E004`, `E007`, `multi_diagnostic.circ`); combinational loop pass (`tests/validator/loop_passes_test.zig`, `E008_simple_loop.circ`, `E008_wire_loop.circ`, `clean_gated_feedback.circ`, `E008_two_cycles.circ`); dead-code / driver `W001`, reserved single-file `W002`, orchestrated `lib/validator/run.zig` (`tests/validator/run_test.zig`).

**Deviation:** Phase 3 plan assumed `W002` dangling output in single-file; shipped as reserved/no-op in single-file until Phase 7 multi-file context (`W002_dangling_output.circ` documents that).

### Phase 4 — Emission

Emitter stack: `lib/emit/writer.zig`, `build_fn.zig` (`tests/emit/build_fn_test.zig`, `keyword_instance_name.circ`); `file_info_format.zig`, `file_info.zig`, `debug_paths.zig` (`tests/emit/metadata_test.zig`); `runtime.zig` + `main.zig` full stitch (`tests/emit/full_emit_test.zig`). WASM harness (`tests/helpers/wasm_run.zig`, `tests/harness/build.zig`, `tests/harness/loader.js`) and behaviour matrix (`tests/emit/behavior_test.zig`, `tests/fixtures/expected-wasm/*.txt`).

**Deviation:** `getTopology()` still serves a static placeholder payload (`topology_blob`) while keeping export names stable (STATUS Phase 4.3).

### Phase 5 — Build orchestration

`lib/orchestrator/embed.zig` manifest + `templates/`; `workspace.zig`, `subprocess.zig` (`zig build failed in <build-dir>:` header), `finalize.zig`; top-level `compile` / `compileWithStderrWriter` in `lib/orchestrator/main.zig` (`tests/orchestrator/main_test.zig`).

### Phase 6 — CLI

`lib/cli/args.zig` parser; `cmd/circ-compile/main.zig` + `lib/cli/inspect_dump.zig`; subprocess integration suite `tests/cli/integration_test.zig` (default compile, `--emit-zig`, `--inspect` goldens under `tests/fixtures/expected-inspect/`).

**Deviation:** Phase 6 plan scoped “CLI today only single-file”; later phases route project pipeline for compile when imports / built-ins require it; `--inspect` remains single-file by design (`cmd/circ-compile/main.zig` skips project resolution in inspect mode — see Phase 9.4 notes).

### Phase 7 — Sub-circuits

`lib/resolver/file_loader.zig`, `scan_imports.zig` (`E009`, `E011`, `tests/resolver/scan_imports_test.zig`); `import_cycle.zig` (`E010`, `tests/resolver/import_cycle_test.zig`); `resolve_bodies.zig` + `ir.Project`; `lib/validator/run_project.zig`, `passes/sub_circuit_validation.zig`, `passes/unused_import.zig` (`E012`, `E013`, cross-boundary `E008`, `W002` dangling sub-circuit output, `W003`); `lib/emit/project.zig` / `emitProjectSource` + project goldens (`tests/emit/project_emit_test.zig`, `tests/emit/project_behavior_test.zig`); hardening fixtures `deep_chain/`, `same_name_half_adder/`, diamond `root.circ` fan-in fix; `input_pin_gate` wired-`in` fan-in + tests in `lib/circuit.zig`.

**Deviation:** `emit_project` uses `threadlocal current_project` during Zig emission for import-table lookups (STATUS 7.5). Plan’s “definition of done” for Phase 7 marked pending human `git` commit in STATUS before rebrand slice; codebase matched DoD.

### Phase 8 — Built-in macros

Embedded sources `lib/resolver/builtin_circ/*.circ` + `lib/resolver/builtins.zig` (`tests/resolver/builtins_test.zig`); virtual paths via `file_loader` (`BuiltinNotFound`); implicit built-in imports in `scan_imports` / `resolve_bodies`, `E011` if user import does not resolve to `<builtin>/<name>.circ`, import-cycle edges from `<builtin>/` excluded from `E010` but included in topo order; truth-table fixtures `builtin_{or,nand,nor,xor,xnor}.circ` (`test "built-in macros: truth tables (or nand nor xor xnor)"`); composition `full_adder_from_builtins.circ`, project `full_adder_ha_or/`; `DOCS/circuit-format.md` updated.

**Deviation:** Built-ins live under `lib/resolver/builtin_circ/` (not `templates/builtins/`) so `@embedFile` stays inside the module tree on Zig 0.15 (STATUS 8.1). Slice numbering in STATUS jumped 8.2 → 8.4 with 8.3 documented as implicit-import slice.

### Phase 9 — Hardening

Edge circuits + `deep_subcircuit_chain/` (`translate_test` `ParsingFailed` for empty parse, LED `.out` fan-out fix, `edge_deep_anonymous` wire workaround); stress `stress_chain_100.circ`, `stress_grid_10x10.circ`, project `stress_deep_subcircuit/`; `tests/validator/codes_snapshot_test.zig` path-normalized snapshots for every `E001`–`E013`, `W001`–`W003`; canonical projects `half_adder/`, `full_adder/`, `and_or_network/` (Phase 9 plan’s “ripple counter” delivered as combinational AND/OR network); `regression_led_out_drives_gate.circ`; `perf smoke: 100-component grid compiles under budget` with `CIRC_SKIP_PERF=1`; `README.md`, `DOCS/getting-started.md`, `DOCS/index.md` row for getting-started.

**Deviations:** Inspect goldens intentionally not shipped for `full_adder/root.circ` and `and_or_network/root.circ` (built-in `or` surfaces as `E001` in single-file `--inspect` — pinning would encode the quirk). README license text later superseded by v0 finalize GPL-3.0 commit.

### Post–phase-index: v0 finalize (same STATUS log)

Project rename to **`circ-compiler`**, `compiler_version` metadata **`circ-compiler/dev`** in CLI + emitter tests + Zig golden headers, `LICENSE` → GPL-3.0, `package.json` name/license URLs; legacy **`circ-renderer-lib`** WASM identifier left unchanged where it denotes the separate browser dynamic API (STATUS “intentionally not renamed”).

## Diagnostic / API surface frozen at v0

### Diagnostic codes (`lib/validator/codes.zig`)

| Code | Default message |
|------|-----------------|
| `E001` | undeclared name |
| `E002` | unknown port |
| `E003` | multiple drivers for input port |
| `E004` | required input is unconnected |
| `E005` | duplicate instance name |
| `E006` | name shadows built-in |
| `E007` | output has no assigned driver |
| `E008` | combinational loop detected |
| `E009` | import not found |
| `E010` | import cycle detected |
| `E011` | import alias collision |
| `E012` | unknown sub-circuit port |
| `E013` | sub-circuit arity mismatch |
| `W001` | unused input declaration |
| `W002` | dangling output declaration |
| `W003` | unused import declaration |

Audited snapshot coverage: `tests/validator/codes_snapshot_test.zig` (single-file `validator_run` + project pipeline); loop extras in `tests/validator/loop_passes_test.zig`; import-graph cases in `tests/resolver/import_cycle_test.zig`.

### WASM runtime exports (compiled artifact)

`init`, `deinit`, `reset`, `run`, `stop`, `setPin`, `getOutputState`, `getStateSnapshot`, `getTopology`, `getPendingEvents`, `getFileInfo`, `freeBuffer`.

### CLI (`circ-compile`)

Modes: default compile `INPUT -o OUTPUT`, `--emit-zig -o OUTPUT`, `--inspect` (no `-o`). Flags: `--warnings-as-errors`, `-Werror`, `--build-dir PATH` (compile mode only). Parser rejects unknown flags and conflicting modes (`lib/cli/args.zig`).

## Known v0 papercuts carried forward

- **Single-file compile path skips `scan_imports`.** Using `or` / `nand` / `nor` / `xor` / `xnor` without any user `import` yields `E001`; `DOCS/getting-started.md` documents explicit `import xor "<builtin>/xor.circ"` as the workaround; v1 candidate runs project pipeline unconditionally.
- **`--inspect` is single-file.** Project roots that instantiate built-in `or` directly show `E001` in inspect output; goldens were not pinned for those roots (Phase 9.4).
- **Discovering root pin / driver IDs in projects.** Flat layout ordering makes IDs non-obvious; hosts probe `getOutputState(i)` or decode `getFileInfo()` — no small programmatic helper yet.
- **No shipped `examples/` tree.** Getting-started paths are illustrative; copy from `tests/fixtures/`.
- **Invalid `<builtin>/unknown.circ`.** Surfaces as `BuiltinNotFound` from `loadFile`, not `E009` (Phase 8.2 notes).
- **Grammar keyword ordering.** `ComponentType` lists `'and'` before `Identifier` (`lib/grammar/proto-circ.peg`); instances like `and_pair` must use import aliases (`paired_and`, `bit_and`).
- **`emit_project` + `threadlocal current_project`.** Single-threaded assumption for emission generation (Phase 7.5).
- **`input_pin_gate` with wired `in`.** Dominance / no `setPin` when `in` is driven from wiring (Phase 7.5).
- **`output … (in=<anonymous …>)`.** Anonymous nested directly under output does not fully materialize inner `in` wires in resolver — `edge_deep_anonymous` uses a `wire` wrapper (Phase 9.1).
- **Stress / perf tests.** `zig build test` wall-clock grows with WASM matrix; `CIRC_SKIP_PERF=1` for flaky CI perf smoke (`perf smoke: 100-component grid compiles under budget`).
- **Legacy browser artifact name.** `circ-renderer-lib` / `circ-renderer-lib.wasm` remains the identifier for the separate dynamic-API library (v0 finalize STATUS).

## Decisions & specs that survived the plan

Authoritative docs remain outside this archive:

- `DOCS/architecture.md`
- `DOCS/circuit-format.md`
- `DOCS/wasm-api.md`
- `DOCS/simulation-engine.md`
- `DOCS/decisions/` (see `DOCS/decisions/index.md`)
