# Status Log

## 2026-05-01 — Phase 0 — Slice 0.1 build test step

**What shipped:** Added an explicit `test` build step in `build.zig` so `zig build test` is the canonical test-suite entry point. This establishes the first scaffolding slice for Phase 0 with an initially empty suite.
**Files touched:** `build.zig`, `DOCS/STATUS.md`
**Tests:** added none, ran `zig build test`, result pass
**Next slice:** Create the fixed `tests/` fixture layout and `tests/README.md` for Slice 0.2.
**Notes:** `DOCS/STATUS.md` did not previously exist; this entry initializes session tracking as required by `DOCS/PLANS_PROMPT.md`.

## 2026-05-01 — Phase 0 — Slice 0.2 fixture layout and README

**What shipped:** Added the Phase 0 fixture tree under `tests/fixtures/` grouped by artifact kind and documented conventions in `tests/README.md`. This locks in fixture placement and naming before helper/test implementation in later slices.
**Files touched:** `tests/README.md`, `tests/fixtures/circuits/.gitkeep`, `tests/fixtures/expected-zig/.gitkeep`, `tests/fixtures/expected-wasm/.gitkeep`, `tests/fixtures/expected-diagnostics/.gitkeep`, `DOCS/STATUS.md`
**Tests:** added none, ran `zig build test`, result pass
**Next slice:** Implement `tests/helpers/golden.zig` and `tests/helpers/golden_test.zig` for Slice 0.3.
**Notes:** `UPDATE_GOLDENS=1` behavior is now documented in `tests/README.md` and will be implemented in the helper in the next slice.

## 2026-05-01 — Phase 0 — Slice 0.3 golden helper and tests

**What shipped:** Implemented `expectGolden(actual, fixture_path)` with compare mode and `UPDATE_GOLDENS=1` update mode, including explicit missing-fixture and mismatch errors. Added helper tests covering match, mismatch, missing fixture, create-on-update, and overwrite-on-update behavior using temporary fixture paths.
**Files touched:** `tests/helpers/golden.zig`, `tests/helpers/golden_test.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added `expectGolden` helper tests in `tests/helpers/golden_test.zig`, ran `zig build test`, result pass
**Next slice:** Start Phase 1 Slice 1.1 by adding `output_pin` type/constants and wasm kind mapping.
**Notes:** `zig build test` now executes both the existing unit-test target and the new golden helper tests via the `test` step.

## 2026-05-01 — Phase 1 — Slice 1.1 output_pin type and mapping

**What shipped:** Added `output_pin` to the circuit kind/tag model with dedicated input/output port constants and threaded the new variant through all required kind switches for compilation. Wired `lib/wasm.zig` kind mapping so dynamic component creation now accepts kind id `5` as `output_pin`, and added a compile-time construction test for the new variant.
**Files touched:** `lib/circuit.zig`, `lib/wasm.zig`, `DOCS/STATUS.md`
**Tests:** added `test "output_pin kind exists and constructs"` in `lib/circuit.zig`, ran `zig build test`, result pass
**Next slice:** Implement Phase 1 Slice 1.2 pass-through `output_pin` propagation behavior and timing tests.
**Notes:** Slice 1.1 intentionally leaves `output_pin` behavior as no-op in recalculation; behavior is deferred to Slice 1.2 per the phase plan.

## 2026-05-01 — Phase 1 — Slice 1.2 output_pin pass-through behavior

**What shipped:** Implemented `output_pin` recalculation as pass-through from the `in` port and scheduled output changes using wire-equivalent delay. Added coverage for low/high propagation, undefined no-op behavior, low-to-high transition timing, and chained output-pin cumulative delay.
**Files touched:** `lib/circuit.zig`, `DOCS/STATUS.md`
**Tests:** added `test "output_pin: passes input through"` in `lib/circuit.zig`, ran `zig build test`, result pass
**Next slice:** Implement Phase 1 Slice 1.3 transport snapshot encoding support for `output_pin`.
**Notes:** `output_pin` now uses `WIRE_PROPAGATION_DELAY` in scheduling, matching the phase delay decision.

## 2026-05-01 — Phase 1 — Slice 1.3 transport output_pin encoding

**What shipped:** Added explicit transport kind-byte mapping including `output_pin` and wired `encodeState` through that mapping so encoded snapshots recognize the new primitive. Added a transport test that constructs a single `output_pin`, encodes state bytes, and asserts the expected state/kind/id-byte layout.
**Files touched:** `lib/transport.zig`, `DOCS/STATUS.md`
**Tests:** added `test "transport: encodes output_pin state"` in `lib/transport.zig`, ran `zig build test`, result pass
**Next slice:** Begin Phase 2 parser and AST/IR work from the active Phase 2 plan.
**Notes:** Phase 1 baseline slices (1.1 to 1.3) are now implemented and passing as a set.

## 2026-05-01 — Phase 2 — Slice 2.1 AST types and span module

**What shipped:** Added a dedicated `Span` type and a new typed AST module covering the Phase 2 syntax constructs (`File`, `Import`, `InputDecl`, `OutputDecl`, `ComponentInstance`, `PortConnection`, `SignalSource`, `NamedSignalRef`, `Identifier`, `StringLiteral`). The AST includes spans on every node and uses a tagged union for signal sources.
**Files touched:** `lib/syntax/span.zig`, `lib/syntax/ast.zig`, `DOCS/STATUS.md`
**Tests:** added `test "ast nodes carry span data"` in `lib/syntax/ast.zig`, ran `zig test lib/syntax/ast.zig` and `zig build test`, result pass
**Next slice:** Implement Phase 2 Slice 2.2 parse-tree to AST translation using the new typed AST.
**Notes:** `SignalSource.anonymous` is represented as `*const ComponentInstance` to avoid recursive-by-value type cycles while preserving inline-component structure.

## 2026-05-01 — Phase 2 — Slice 2.2 parse tree to typed AST

**What shipped:** Rewrote parser translation to produce `ast.File` from langlang parse trees with spans populated from parser ranges, including imports, input declarations, output declarations, component instances, bus-port mappings, named references, and anonymous inline components. Added deterministic AST dump helper plus fixture-based golden tests, introduced new `tests/fixtures/expected-ast/` goldens, and updated test/build wiring to execute translator fixtures under `zig build test`.
**Files touched:** `lib/syntax/translate.zig`, `lib/syntax/nodes/declaration.zig`, `lib/compiler.zig`, `lib/transport.zig`, `build.zig`, `tests/helpers/ast_dump.zig`, `tests/syntax/translate_test.zig`, `tests/README.md`, `tests/fixtures/circuits/empty_ish.circ`, `tests/fixtures/circuits/and_two_inputs.circ`, `tests/fixtures/circuits/anonymous_nested.circ`, `tests/fixtures/circuits/with_import.circ`, `tests/fixtures/circuits/multi_output.circ`, `tests/fixtures/expected-ast/empty_ish.txt`, `tests/fixtures/expected-ast/and_two_inputs.txt`, `tests/fixtures/expected-ast/anonymous_nested.txt`, `tests/fixtures/expected-ast/with_import.txt`, `tests/fixtures/expected-ast/multi_output.txt`, `DOCS/STATUS.md`
**Tests:** added fixture-driven translator golden test in `tests/syntax/translate_test.zig`, generated AST goldens with `UPDATE_GOLDENS=1 zig build test`, ran `zig build test`, result pass
**Next slice:** Implement Phase 2 Slice 2.3 IR type layer under `lib/ir/` with construction/readback tests.
**Notes:** During slice work, `lib/transport.zig` was adjusted to avoid referencing private `Component.Kind` in non-test builds; this unblocks `zig build compiler:run` while preserving existing kind-byte behavior.

## 2026-05-01 — Phase 2 — Slice 2.3 IR types

**What shipped:** Added the initial IR type layer under `lib/ir/types.zig`, including typed ID wrappers (`FileId`, `InputId`, `OutputId`, `ComponentId`), module-level structures (`Module`, `Component`, `Connection`, `InputPin`, `OutputPin`, `UnresolvedImport`), and component kind modeling (`primitive`, `sub_circuit_ref`, `unresolved_name`). This slice introduces data structures only; no resolver behavior yet.
**Files touched:** `lib/ir/types.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added `test "ir types construct and round-trip fields"` in `lib/ir/types.zig`, wired IR tests into `zig build test`, result pass
**Next slice:** Implement Phase 2 Slice 2.4 AST to IR resolver (single-file) and IR golden dumps.
**Notes:** IR tests import `Span` via module wiring in `build.zig` (`span` import), keeping IR types decoupled from relative source-path imports.

## 2026-05-01 — Phase 2 — Slice 2.4 AST to IR resolver

**What shipped:** Implemented a single-file AST→IR resolver in `lib/ir/resolver.zig` that synthesizes input/output components, resolves primitive vs import-alias vs unresolved component kinds, flattens anonymous inline components into concrete IR components, materializes connections, and carries unresolved imports forward for later phases. Added deterministic IR dump tooling plus fixture-driven golden tests covering primitive resolution, anonymous flattening, unresolved-name markers, import-alias markers, and output-driver synthesis.
**Files touched:** `lib/ir/resolver.zig`, `lib/ir/types.zig`, `lib/syntax/translate.zig`, `build.zig`, `tests/helpers/ir_dump.zig`, `tests/ir/resolver_test.zig`, `tests/fixtures/circuits/unknown_component.circ`, `tests/fixtures/expected-ir/and_two_inputs.txt`, `tests/fixtures/expected-ir/anonymous_nested.txt`, `tests/fixtures/expected-ir/unknown_component.txt`, `tests/fixtures/expected-ir/with_import.txt`, `tests/fixtures/expected-ir/multi_output.txt`, `tests/README.md`, `DOCS/STATUS.md`
**Tests:** added resolver fixture test `test "resolve ast to ir fixtures"` in `tests/ir/resolver_test.zig`, generated IR goldens with `UPDATE_GOLDENS=1 zig build test`, ran `zig build test`, result pass
**Next slice:** Begin Phase 3 semantic validation from the active Phase 3 plan.
**Notes:** `tests/helpers/golden.zig` now keeps expected-failure test paths silent, so the resolver/translator golden suites run without intentional stderr noise.

## 2026-05-01 — Phase 3 — Slice 3.1 diagnostic types and code table

**What shipped:** Added validator diagnostic foundations with stable code allocation and message table (`E001`-`E008`, `W001`-`W002`), plus diagnostic structures (`Diagnostic`, `DiagnosticNote`, `DiagnosticList`) and a formatter that emits `<file>:<line>:<col>: <level>: <code>: <message>`. This locks the diagnostic contract used by all validation passes.
**Files touched:** `lib/validator/codes.zig`, `lib/validator/diagnostics.zig`, `tests/validator/diagnostics_test.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added diagnostic formatting/code-table tests in `tests/validator/diagnostics_test.zig`, ran `zig build test`, result pass
**Next slice:** Implement Phase 3 Slice 3.2 name-resolution and name-collision passes with per-code fixtures.
**Notes:** Diagnostic level uses `err`/`warning` internally to avoid Zig keyword conflicts while preserving formatted output text as `error`/`warning`.

## 2026-05-01 — Phase 3 — Slice 3.2 name resolution and collision passes

**What shipped:** Added validator pass implementations for unresolved names (`E001`), duplicate instance names (`E005`), and built-in shadowing (`E006`) with diagnostic notes for duplicate declarations. Added fixture-driven diagnostics tests that parse source, resolve IR, run the two passes, and compare deterministic diagnostics dumps against expected snapshots.
**Files touched:** `lib/validator/passes/name_resolution.zig`, `lib/validator/passes/name_collision.zig`, `tests/validator/name_passes_test.zig`, `tests/fixtures/circuits/E001_undeclared.circ`, `tests/fixtures/circuits/E005_duplicate_name.circ`, `tests/fixtures/circuits/E006_shadows_builtin.circ`, `tests/fixtures/expected-diagnostics/E001_undeclared.txt`, `tests/fixtures/expected-diagnostics/E005_duplicate_name.txt`, `tests/fixtures/expected-diagnostics/E006_shadows_builtin.txt`, `tests/fixtures/expected-diagnostics/clean.txt`, `build.zig`, `lib/validator/diagnostics.zig`, `lib/ir/resolver.zig`, `DOCS/STATUS.md`
**Tests:** added `test "name resolution and collision passes fixtures"` in `tests/validator/name_passes_test.zig`, generated expected diagnostics with `UPDATE_GOLDENS=1 zig build test`, ran `zig build test`, result pass
**Next slice:** Implement Phase 3 Slice 3.3 port validation, multi-driver, required-input, and output-assignment passes.
**Notes:** Name-pass diagnostics currently sort by source location and code for stable snapshots, with duplicate-name diagnostics including a `note:` line pointing to the first declaration span.

## 2026-05-01 — Phase 3 — Slice 3.3 structural validation passes

**What shipped:** Added structural validation passes for unknown ports (`E002`), multi-driver inputs (`E003`), missing required inputs (`E004`), and unassigned outputs (`E007`), plus fixture-driven diagnostics coverage including a composite multi-diagnostic case. Updated resolver/translation glue so unresolved signal references are preserved into validation instead of crashing resolution, enabling proper pass-level diagnostics.
**Files touched:** `lib/validator/passes/port_validation.zig`, `lib/validator/passes/multi_driver.zig`, `lib/validator/passes/required_input.zig`, `lib/validator/passes/output_assignment.zig`, `tests/validator/structural_passes_test.zig`, `tests/fixtures/circuits/E002_unknown_port.circ`, `tests/fixtures/circuits/E003_multi_driver.circ`, `tests/fixtures/circuits/E004_unconnected_required_input.circ`, `tests/fixtures/circuits/E007_unassigned_output.circ`, `tests/fixtures/circuits/multi_diagnostic.circ`, `tests/fixtures/expected-diagnostics/E002_unknown_port.txt`, `tests/fixtures/expected-diagnostics/E003_multi_driver.txt`, `tests/fixtures/expected-diagnostics/E004_unconnected_required_input.txt`, `tests/fixtures/expected-diagnostics/E007_unassigned_output.txt`, `tests/fixtures/expected-diagnostics/multi_diagnostic.txt`, `build.zig`, `lib/ir/resolver.zig`, `lib/ir/types.zig`, `lib/syntax/translate.zig`, `DOCS/STATUS.md`
**Tests:** added `test "structural validation passes fixtures"` in `tests/validator/structural_passes_test.zig`, generated diagnostics snapshots with `UPDATE_GOLDENS=1 zig build test`, ran `zig build test`, result pass
**Next slice:** Implement Phase 3 Slice 3.4 combinational-loop detection pass and fixtures.
**Notes:** `E007` fixture now parses as a single top-level declaration due translator support for non-sequence `Program` payloads; output driver absence is represented via `InvalidComponentId` and diagnosed in the output-assignment pass.

## 2026-05-01 — Phase 3 — Slice 3.4 combinational-loop pass

**What shipped:** Added a combinational-loop validation pass with cycle detection over the non-cycle-breaking connection graph, including explicit self-loop handling and cycle-note emission per participating component. Added fixture-driven loop tests for simple loop, wire-only loop, clean gated feedback, and multi-cycle reporting.
**Files touched:** `lib/validator/passes/combinational_loop.zig`, `tests/validator/loop_passes_test.zig`, `tests/fixtures/circuits/E008_simple_loop.circ`, `tests/fixtures/circuits/E008_wire_loop.circ`, `tests/fixtures/circuits/clean_gated_feedback.circ`, `tests/fixtures/circuits/E008_two_cycles.circ`, `tests/fixtures/expected-diagnostics/E008_simple_loop.txt`, `tests/fixtures/expected-diagnostics/E008_wire_loop.txt`, `tests/fixtures/expected-diagnostics/clean_gated_feedback.txt`, `tests/fixtures/expected-diagnostics/E008_two_cycles.txt`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added `test "combinational loop pass fixtures"` in `tests/validator/loop_passes_test.zig`, generated expected diagnostics with `UPDATE_GOLDENS=1 zig build test`, ran `zig build test`, result pass
**Next slice:** Implement Phase 3 Slice 3.5 warning passes (`W001`, `W002`) and top-level validator driver.
**Notes:** Loop diagnostics include `note:` lines naming each cycle node (`component <id>`), and cycle deduping is keyed by sorted component-id sets to avoid duplicate reports from DFS back-edge permutations.

## 2026-05-01 — Phase 3 — Slice 3.5 warning pass and validator driver

**What shipped:** Added dead-code warning pass (`W001`) with single-file `W002` intentionally reserved/no-op, and introduced a top-level validator driver that orchestrates all passes in pipeline order. Added validator end-to-end fixture tests for warning-only, reserved-W002 behavior, clean output, and mixed error+warning accumulation.
**Files touched:** `lib/validator/passes/dead_code.zig`, `lib/validator/run.zig`, `tests/validator/run_test.zig`, `tests/fixtures/circuits/W001_unused_input.circ`, `tests/fixtures/circuits/W002_dangling_output.circ`, `tests/fixtures/circuits/clean_warning.circ`, `tests/fixtures/circuits/errors_and_warnings.circ`, `tests/fixtures/expected-diagnostics/W001_unused_input.txt`, `tests/fixtures/expected-diagnostics/W002_dangling_output.txt`, `tests/fixtures/expected-diagnostics/clean_warning.txt`, `tests/fixtures/expected-diagnostics/errors_and_warnings.txt`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added `test "validator run fixtures"` in `tests/validator/run_test.zig`, generated diagnostics snapshots with `UPDATE_GOLDENS=1 zig build test`, ran `zig build test`, result pass
**Next slice:** Begin Phase 4 emission work from the active Phase 4 plan.
**Notes:** In single-file mode `W002` remains intentionally silent (reserved for Phase 7 multi-file context) per the phase plan’s open-question recommendation.

## 2026-05-01 — Phase 4 — Slice 4.1 writer and buildCircuit emission

**What shipped:** Added an emission writer utility for indentation, Zig string literal escaping, and Zig identifier escaping, then implemented `buildCircuit` snippet emission from validated IR. Added fixture-driven golden tests for build-function output covering empty-ish wiring, multi-primitive wiring, anonymous components, and Zig keyword-sensitive instance naming.
**Files touched:** `lib/emit/writer.zig`, `lib/emit/build_fn.zig`, `tests/emit/build_fn_test.zig`, `tests/fixtures/circuits/keyword_instance_name.circ`, `tests/fixtures/expected-zig/empty_ish_build_fn.zig`, `tests/fixtures/expected-zig/and_two_inputs_build_fn.zig`, `tests/fixtures/expected-zig/anonymous_nested_build_fn.zig`, `tests/fixtures/expected-zig/keyword_instance_name_build_fn.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added `test "buildCircuit emitter fixtures"` in `tests/emit/build_fn_test.zig`, generated Zig snippet goldens with `UPDATE_GOLDENS=1 zig build test`, ran `zig build test`, result pass
**Next slice:** Implement Phase 4 Slice 4.2 file-info and debug-paths emission modules with golden coverage.
**Notes:** Build-function emission currently rejects unresolved/sub-circuit component kinds (`error.UnresolvedComponentName`, `error.UnsupportedSubCircuitInPhase4`) to keep Phase 4 single-file primitive-only constraints explicit.

## 2026-05-01 — Phase 4 — Slice 4.2 file-info and debug-paths emission

**What shipped:** Added a locked binary file-info encoding module with encode/decode helpers and emitted-file blob generation, plus a debug-paths emitter that outputs per-component source-path tables for single-file circuits. Added metadata emitter tests that golden-check file-info/debug-path snippets across fixtures and validate file-info blob round-trip decode for a representative circuit.
**Files touched:** `lib/emit/file_info_format.zig`, `lib/emit/file_info.zig`, `lib/emit/debug_paths.zig`, `tests/emit/metadata_test.zig`, `tests/fixtures/expected-zig/empty_ish_file_info.zig`, `tests/fixtures/expected-zig/empty_ish_debug_paths.zig`, `tests/fixtures/expected-zig/and_two_inputs_file_info.zig`, `tests/fixtures/expected-zig/and_two_inputs_debug_paths.zig`, `tests/fixtures/expected-zig/anonymous_nested_file_info.zig`, `tests/fixtures/expected-zig/anonymous_nested_debug_paths.zig`, `build.zig`, `lib/emit/build_fn.zig`, `DOCS/STATUS.md`
**Tests:** added `test "file info and debug path emitters fixtures"` and `test "file info blob round trip"` in `tests/emit/metadata_test.zig`, generated metadata goldens with `UPDATE_GOLDENS=1 zig build test`, ran `zig build test`, result pass
**Next slice:** Implement Phase 4 Slice 4.3 runtime exports emission and top-level file stitching (`lib/emit/runtime.zig`, `lib/emit/main.zig`) with full-file golden coverage.
**Notes:** `lib/emit/writer.zig` is now consumed via shared module import (`emit_writer`) to avoid Zig module-path collisions when multiple emitter modules are linked in one test target.

## 2026-05-01 — Phase 4 — Slice 4.3 runtime exports emission and full-file stitch

**What shipped:** Added a runtime emitter that outputs all v0 exports (`init`, `deinit`, `reset`, `run`, `stop`, `setPin`, `getOutputState`, `getStateSnapshot`, `getTopology`, `getPendingEvents`, `getFileInfo`, `freeBuffer`) and emits per-circuit input/output id tables for pin validation. Added top-level module emitter stitching header/imports, `buildCircuit`, file-info blob, debug-path table, and runtime section into a full `compiled.zig` source string.
**Files touched:** `lib/emit/runtime.zig`, `lib/emit/main.zig`, `tests/emit/full_emit_test.zig`, `tests/fixtures/expected-zig/empty_ish.zig`, `tests/fixtures/expected-zig/and_two_inputs.zig`, `tests/fixtures/expected-zig/anonymous_nested.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added `test "full emitter fixture files"` in `tests/emit/full_emit_test.zig`, generated full-file emission goldens with `UPDATE_GOLDENS=1 zig build test`, ran `zig build test`, result pass
**Next slice:** Implement Phase 4 Slice 4.4 behavioral harness (`tests/helpers/wasm_run.zig`, `tests/harness/build.zig`, `tests/harness/loader.js`) and first end-to-end wasm behavior test.
**Notes:** `getTopology()` currently surfaces a static placeholder payload (`topology_blob`) while keeping the runtime export/wire format stable for the upcoming harness phase.

## 2026-05-01 — Phase 4 — Slice 4.4 behavioral harness and first e2e wasm behavior test

**What shipped:** Added a fixed WASM harness (`tests/harness/build.zig`, `tests/harness/loader.js`) and a reusable Zig helper (`tests/helpers/wasm_run.zig`) that emits source into a temp dir, compiles `compiled.wasm`, executes it under `node`, and captures stdout. Added a first end-to-end behavioral test for an inverter fixture that drives input states via runtime exports and asserts observed output transitions from Node (`0`, then `1`).
**Files touched:** `tests/helpers/wasm_run.zig`, `tests/harness/build.zig`, `tests/harness/loader.js`, `tests/emit/behavior_test.zig`, `tests/fixtures/circuits/inverter.circ`, `build.zig`, `tests/README.md`, `lib/emit/runtime.zig`, `tests/fixtures/expected-zig/empty_ish.zig`, `tests/fixtures/expected-zig/and_two_inputs.zig`, `tests/fixtures/expected-zig/anonymous_nested.zig`, `lib/circuit.zig`, `DOCS/STATUS.md`
**Tests:** added `test "behavioral harness: inverter responds to pin toggles"` in `tests/emit/behavior_test.zig`, ran `UPDATE_GOLDENS=1 zig build test` during iteration for emission fixture sync, then ran `zig build test`, result pass
**Next slice:** Implement Phase 4 Slice 4.5 behavioral fixture table coverage (`inverter`, `and_gate`, `and_of_not`, `chain`, `unused_input`) driven by the harness.
**Notes:** Harness integration required runtime emitter compatibility fixes for Zig 0.15 (`callconv(.c)`, nullable ptr/len struct) and surfaced a functional NOT-gate issue in engine propagation (`not_gate` now correctly flips input state).

## 2026-05-01 — Phase 4 — Slice 4.5 behavioral fixture matrix

**What shipped:** Expanded behavioral coverage from a single inverter check to a fixture-driven matrix powered by `expected-wasm` specs. Added circuits and truth-table specs for `inverter`, `and_gate`, `and_of_not`, `chain`, and `unused_input`, and updated the behavioral test to parse fixture rows (`pin=state ... => pin=state ...`), map pin names to emitted component IDs via IR, execute each step through the wasm harness, and assert output lines deterministically.
**Files touched:** `tests/emit/behavior_test.zig`, `tests/fixtures/circuits/and_gate.circ`, `tests/fixtures/circuits/and_of_not.circ`, `tests/fixtures/circuits/chain.circ`, `tests/fixtures/circuits/unused_input.circ`, `tests/fixtures/expected-wasm/inverter.txt`, `tests/fixtures/expected-wasm/and_gate.txt`, `tests/fixtures/expected-wasm/and_of_not.txt`, `tests/fixtures/expected-wasm/chain.txt`, `tests/fixtures/expected-wasm/unused_input.txt`, `tests/README.md`, `DOCS/STATUS.md`
**Tests:** replaced the single behavior test with fixture-backed tests (`behavior fixture: inverter`, `and gate`, `and of not`, `chain`, `unused input`) in `tests/emit/behavior_test.zig`, ran `zig build test`, result pass
**Next slice:** Begin Phase 5 build orchestration from the active Phase 5 plan.
**Notes:** The fixture parser intentionally ignores blank/comment lines, so `expected-wasm` specs remain human-editable while still producing strict deterministic assertions.

## 2026-05-01 — Phase 5 — Slice 5.1 embed manifest and templates

**What shipped:** Added production orchestration templates (`templates/build.zig`, `templates/main.zig`) and introduced the runtime embed manifest in `lib/orchestrator/embed.zig` with `@embedFile` records for build/main plus engine sources (`circuit`, `memory`, `log`, `transport`). Added orchestrator embed tests asserting non-empty embedded content and required manifest names.
**Files touched:** `templates/build.zig`, `templates/main.zig`, `lib/orchestrator/embed.zig`, `tests/orchestrator/embed_test.zig`, `orchestrator_embed_module.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added `runtime embed manifest has non-empty content` and `runtime embed manifest contains expected names` in `tests/orchestrator/embed_test.zig`, ran `zig build test`, result pass
**Next slice:** Implement Phase 5 Slice 5.2 workspace creation and runtime/emitted-source writing helpers in `lib/orchestrator/workspace.zig`.
**Notes:** To satisfy Zig package-path rules for `@embedFile` while keeping `lib/orchestrator/embed.zig` as the manifest source, tests compile it through a workspace-root wrapper module (`orchestrator_embed_module.zig`).

## 2026-05-01 — Phase 5 — Slice 5.2 workspace creation and runtime extraction

**What shipped:** Added orchestrator workspace helpers in `lib/orchestrator/workspace.zig` for creating build workspaces (`createWorkspace`), materializing embedded runtime files (`writeRuntime`), and writing emitted source (`writeEmittedSource`). Workspace creation supports either a generated `/tmp/circ-compile-<rand>` path with `cleanup_on_success=true` or a caller-supplied override path with `cleanup_on_success=false`, and ensures the `src/` layout exists in both cases.
**Files touched:** `lib/orchestrator/workspace.zig`, `tests/orchestrator/workspace_test.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added unit tests in `tests/orchestrator/workspace_test.zig` for temp workspace creation, override behavior, runtime file write/byte-match against embed manifest, and emitted-source write path; ran `zig build test`, result pass
**Next slice:** Implement Phase 5 Slice 5.3 subprocess wrapper in `lib/orchestrator/subprocess.zig` with success/failure capture and failure-header behavior.
**Notes:** Workspace helpers intentionally handle both absolute and relative paths so test fixtures can use `std.testing.tmpDir()`-relative paths while production defaults remain absolute under `/tmp`.

## 2026-05-01 — Phase 5 — Slice 5.3 subprocess wrapper

**What shipped:** Added `lib/orchestrator/subprocess.zig` with a captured-output subprocess wrapper (`runCommand`) returning term, normalized exit code, stdout, and stderr. On non-zero exit the wrapper writes `zig build failed in <build-dir>:` to the provided stderr writer and streams captured stderr/stdout afterward; it also maps missing `zig` executable to `error.ZigBinaryNotFound` for clearer caller handling.
**Files touched:** `lib/orchestrator/subprocess.zig`, `tests/orchestrator/subprocess_test.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added `subprocess wrapper succeeds for zig version` and `subprocess wrapper captures failure and prints header` in `tests/orchestrator/subprocess_test.zig`, ran `zig build test`, result pass
**Next slice:** Implement Phase 5 Slice 5.4 output copy and cleanup helpers in `lib/orchestrator/finalize.zig`.
**Notes:** The subprocess wrapper intentionally accepts an arbitrary stderr writer so higher-level orchestration can stream failure headers to real stderr in production and in-memory buffers in tests.

## 2026-05-01 — Phase 5 — Slice 5.4 output copy and cleanup

**What shipped:** Added orchestrator finalize helpers in `lib/orchestrator/finalize.zig`: `copyOutput(workspace, target_path)` copies the deterministic build artifact from `<workspace>/zig-out/bin/compiled.wasm` to the requested output path (creating parent directories as needed), and `cleanup(workspace)` deletes the workspace only when `cleanup_on_success` is true.
**Files touched:** `lib/orchestrator/finalize.zig`, `tests/orchestrator/finalize_test.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added finalize unit tests in `tests/orchestrator/finalize_test.zig` for successful copy, missing-artifact error (`error.MissingCompiledWasm`), cleanup delete-on-true, and cleanup no-op-on-false; ran `zig build test`, result pass
**Next slice:** Implement Phase 5 Slice 5.5 top-level orchestrator `compile(...)` and subprocess-path end-to-end tests.
**Notes:** `copyOutput` uses explicit file streaming rather than relying on path-specific stdlib copy helpers so relative and absolute workspace/output paths follow the same behavior in production and tests.

## 2026-05-01 — Phase 5 — Slice 5.5 top-level orchestrator and e2e subprocess path

**What shipped:** Added `lib/orchestrator/main.zig` exposing `compile(allocator, emitted_zig_source, options)` and composing workspace setup, runtime extraction, emitted-source write, subprocess build, artifact copy, and success cleanup policy into one orchestrated flow. Also added `compileWithStderrWriter(...)` for test-time stderr capture while keeping production `compile(...)` behavior unchanged (writes subprocess failure headers to stderr).
**Files touched:** `lib/orchestrator/main.zig`, `tests/orchestrator/main_test.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added orchestrator end-to-end tests in `tests/orchestrator/main_test.zig` for (1) successful compile producing wasm magic bytes with temp-dir cleanup, (2) override `build_dir` preservation with generated workspace contents, and (3) invalid Zig source failure preserving build dir; ran `zig build test`, result pass
**Next slice:** Begin Phase 6 CLI surface work from the active Phase 6 plan.
**Notes:** Failure-path tests use the writer-injected entrypoint to keep expected failing `zig build` stderr output captured/silent in test logs while still verifying preserve-on-failure behavior.

## 2026-05-01 — Phase 6 — Slice 6.1 argument parser

**What shipped:** Added a hand-rolled single-pass CLI argument parser in `lib/cli/args.zig` with `Mode`, `Args`, `ParseError`, and `parse(argv)` covering compile, `--emit-zig`, and `--inspect` modes plus `--warnings-as-errors`/`-Werror`, `-o`, and `--build-dir`. The parser enforces mutually exclusive mode flags, required `-o` for compile/emit-zig, rejects unknown flags, and rejects `--build-dir` outside compile mode.
**Files touched:** `lib/cli/args.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added parser unit tests in `lib/cli/args.zig` covering all planned happy-path and error-path argv shapes for Slice 6.1, wired parser tests into `zig build test`, ran `zig build test`, result pass
**Next slice:** Implement Phase 6 Slice 6.2 CLI entry point and pipeline driver (`cmd/circ-compile/main.zig`) and wire the `circ-compile` executable target in root `build.zig`.
**Notes:** Current parser behavior keeps `--inspect` without `-o` valid and does not yet enforce `-o` rejection in inspect mode; that mode-specific policy is deferred to later integration slices per the phase open question.

## 2026-05-01 — Phase 6 — Slice 6.2 CLI entry point and pipeline driver

**What shipped:** Added the user-facing CLI entry point at `cmd/circ-compile/main.zig` and wired a new `circ-compile` executable target in root `build.zig`. The driver now composes parse/read/translate/resolve/validate/emit/orchestrate across modes: default compile (`-o` -> wasm via orchestrator), `--emit-zig` (`-o` -> emitted Zig file), and `--inspect` (prints parse tree, resolved IR, diagnostics, and summary sections). It prints diagnostics in Phase 3 format (including notes), enforces exit code semantics (`0` success, `1` hard pipeline failures, `2` usage/input errors), and honors `--warnings-as-errors` for non-inspect modes.
**Files touched:** `cmd/circ-compile/main.zig`, `lib/cli/inspect_dump.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** no new dedicated tests in this slice (per plan), but `zig build test` now compiles `circ-compile` as a test-step dependency and passed; additionally ran `zig build circ-compile`, result pass
**Next slice:** Implement Phase 6 Slice 6.3 CLI integration tests for default compile mode (`tests/cli/integration_test.zig`).
**Notes:** Added `compileWithStderrWriter(...)` in orchestrator previously to keep expected failing subprocess output silent in tests; CLI production path still uses real stderr via `compile(...)`.

## 2026-05-01 — Phase 6 — Slice 6.3 integration tests for default mode

**What shipped:** Added end-to-end CLI integration coverage in `tests/cli/integration_test.zig` that invokes the real `zig-out/bin/circ-compile` binary via subprocess. The suite now verifies default compile happy path, hard-error failure, warning pass-through, warnings-as-errors failure, missing input handling, unknown flag handling, and `--build-dir` preservation behavior.
**Files touched:** `tests/cli/integration_test.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added 7 CLI integration tests (default mode matrix) in `tests/cli/integration_test.zig`, wired the test target into `zig build test`, ran `zig build test`, result pass
**Next slice:** Implement Phase 6 Slice 6.4 integration tests for `--emit-zig` mode.
**Notes:** The integration tests trigger `zig build circ-compile` before execution so the CLI binary path is deterministic (`zig-out/bin/circ-compile`) regardless of prior manual build state.

## 2026-05-01 — Phase 6 — Slice 6.4 integration tests for --emit-zig mode

**What shipped:** Extended CLI integration coverage with `--emit-zig` mode tests in `tests/cli/integration_test.zig`: successful emit writes Zig output matching the Phase 4 golden fixture, hard semantic errors exit non-zero without creating output, and `--build-dir` usage in emit mode is rejected as a usage error. Also aligned CLI emission metadata to use the input file basename so emitted Zig headers are stable and comparable with existing golden fixtures.
**Files touched:** `tests/cli/integration_test.zig`, `cmd/circ-compile/main.zig`, `DOCS/STATUS.md`
**Tests:** added `cli emit-zig mode writes expected zig file`, `cli emit-zig hard error exits 1 and no output`, and `cli emit-zig rejects build-dir with usage error`; ran `zig build test`, result pass
**Next slice:** Implement Phase 6 Slice 6.5 integration tests for `--inspect` mode (sectioned stdout golden checks and exit semantics).
**Notes:** The emit-zig golden comparison now checks full-file equality against `tests/fixtures/expected-zig/and_two_inputs.zig`, locking the mode output contract beyond simple existence checks.

## 2026-05-01 — Phase 6 — Slice 6.5 integration tests for --inspect mode

**What shipped:** Added inspect-mode integration coverage in `tests/cli/integration_test.zig` and introduced inspect stdout golden fixtures under `tests/fixtures/expected-inspect/`. The CLI is now explicitly strict about inspect-only output (`-o` rejected with usage error), and inspect tests verify sectioned stdout layout/ordering, clean vs error exit semantics, and exact textual output via golden-file comparison.
**Files touched:** `tests/cli/integration_test.zig`, `tests/fixtures/expected-inspect/clean_inverter.txt`, `tests/fixtures/expected-inspect/error_undeclared.txt`, `cmd/circ-compile/main.zig`, `DOCS/STATUS.md`
**Tests:** added `cli inspect clean fixture exits 0 and matches golden stdout`, `cli inspect error fixture exits 1 and matches golden stdout`, and `cli inspect rejects -o flag`; ran `zig build test`, result pass
**Next slice:** Begin Phase 7 sub-circuit support from the active Phase 7 plan.
**Notes:** Inspect diagnostics are now emitted only in the inspect stdout section (not duplicated to stderr), which keeps inspect output script-friendly and aligns with the sectioned golden contract.

## 2026-05-01 — Phase 7 — Slice 7.1 file loader and import scanner

**What shipped:** Added multi-file import scanning foundations under `lib/resolver/`: a filesystem loader (`file_loader.zig`) and a reachable-project import scanner (`scan_imports.zig`) that discovers files from a root entrypoint, resolves import paths relative to the importing file, deduplicates files by canonical absolute path, and builds an import table with resolved target file IDs. The scanner now emits import diagnostics `E009` (missing import) and `E011` (import alias collision / built-in alias collision). Added new project-fixture layout under `tests/fixtures/projects/`.
**Files touched:** `lib/resolver/file_loader.zig`, `lib/resolver/scan_imports.zig`, `tests/resolver/scan_imports_test.zig`, `tests/fixtures/projects/two_file/root.circ`, `tests/fixtures/projects/two_file/child.circ`, `tests/fixtures/projects/diamond/root.circ`, `tests/fixtures/projects/diamond/left.circ`, `tests/fixtures/projects/diamond/right.circ`, `tests/fixtures/projects/diamond/base.circ`, `tests/fixtures/projects/missing_import/root.circ`, `tests/fixtures/projects/missing_import/ok.circ`, `tests/fixtures/projects/alias_collision/root.circ`, `tests/fixtures/projects/alias_collision/a.circ`, `tests/fixtures/projects/alias_collision/b.circ`, `lib/validator/codes.zig`, `lib/validator/diagnostics.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added scanner tests in `tests/resolver/scan_imports_test.zig` covering two-file discovery, diamond dedupe/load, missing import (`E009`), and alias collision (`E011`); ran `zig build test`, result pass
**Next slice:** Implement Phase 7 Slice 7.2 import-cycle detection and topological ordering (`lib/resolver/import_cycle.zig`).
**Notes:** Diagnostic code table was extended to include planned import/sub-circuit codes (`E009`-`E013`, `W003`) so new resolver diagnostics integrate cleanly with existing formatting/tests as Phase 7 continues.

## 2026-05-01 — Phase 7 — Slice 7.2 import-cycle detection and topological sort

**What shipped:** Added `lib/resolver/import_cycle.zig` to analyze the import graph, produce dependency-first topological order (leaves first), and emit `E010` diagnostics for detected cycles. Cycle diagnostics now include a human-readable cycle chain in the main message plus per-file notes naming each member file.
**Files touched:** `lib/resolver/import_cycle.zig`, `tests/resolver/import_cycle_test.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added cycle-analysis tests in `tests/resolver/import_cycle_test.zig` covering linear chain topo order, diamond ordering constraints, self-cycle, indirect cycle, three-node cycle, and multiple distinct cycles; ran `zig build test`, result pass
**Next slice:** Implement Phase 7 Slice 7.3 body resolution and sub-circuit linking (`lib/resolver/resolve_bodies.zig`) to produce project-level IR.
**Notes:** Cycle detection deduplicates repeated DFS back-edge discoveries per cycle path key so each cycle shape is reported once in diagnostics.

## 2026-05-01 — Phase 7 — Slice 7.3 body resolution and sub-circuit linking

**What shipped:** Added `lib/resolver/resolve_bodies.zig` to build project-level IR from import scan + topological order by resolving each file body with the existing single-file resolver, then linking component kinds so `unresolved_name` entries that match import aliases become `sub_circuit_ref`. Extended IR types with `ir.Project` and `ResolvedImport` so multi-file pipeline stages can consume resolved modules, import edges, paths, and retained per-file source blobs.
**Files touched:** `lib/resolver/resolve_bodies.zig`, `lib/ir/types.zig`, `tests/resolver/resolve_bodies_test.zig`, `tests/fixtures/projects/unresolved_name/root.circ`, `tests/fixtures/projects/primitive_preserve/root.circ`, `tests/fixtures/projects/primitive_preserve/child.circ`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added resolver-body tests in `tests/resolver/resolve_bodies_test.zig` covering (1) two-file alias linking to `sub_circuit_ref`, (2) non-imported references remaining `unresolved_name`, and (3) primitive component kinds remaining primitive; ran `zig build test`, result pass
**Next slice:** Implement Phase 7 Slice 7.4 validator extensions for multi-file IR (`E012`, `E013`, cross-subcircuit loop traversal, `W003` and sub-circuit `W002` activation).
**Notes:** `resolve_bodies` currently anchors `sub_circuit_ref.name` to the import alias and carries `ir.Project.import_table` target file IDs as the authoritative file-level linkage for later validation/emission phases.

## 2026-05-01 — Phase 7 — Slice 7.4 validator extensions for multi-file IR

**What shipped:** Full Phase 7 Slice 7.4 — all four validator extensions for multi-file IR:

- `W003 unused_import`: per-module pass in `lib/validator/passes/unused_import.zig` emits W003 for any imported alias never referenced as a `sub_circuit_ref`. Single-file and project-level fixtures both covered.
- `E012 sub_circuit_port_unknown` and `E013 sub_circuit_arity_mismatch`: new project-aware pass `lib/validator/passes/sub_circuit_validation.zig` with `runForModule(project, module, diags)` that looks up target module inputs/outputs via the import table to validate port names and required inputs.
- `E008 cross-boundary loop`: the existing single-file combinational-loop pass already treats `sub_circuit_ref` as non-cycle-breaking, so loops through transparent sub-circuits are detected at the parent-module level without an additional pass. Verified with the `E008_loop_through_subcircuit` project fixture.
- `W002 dangling sub-circuit output`: added to `sub_circuit_validation.runForModule` — emits W002 for any target module output port that is never read by any parent connection.
- `lib/validator/run_project.zig`: new project-level driver composing per-module passes with sub-circuit validation.

**Files touched:** `lib/validator/passes/unused_import.zig`, `lib/validator/passes/sub_circuit_validation.zig`, `lib/validator/run.zig`, `lib/validator/run_project.zig`, `tests/validator/run_test.zig`, `tests/validator/project_passes_test.zig`, `tests/fixtures/circuits/W003_unused_import.circ`, `tests/fixtures/expected-diagnostics/W003_unused_import.txt`, `tests/fixtures/projects/clean_two_file/root.circ`, `tests/fixtures/projects/clean_two_file/child.circ`, `tests/fixtures/projects/E012_unknown_port/root.circ`, `tests/fixtures/projects/E012_unknown_port/child.circ`, `tests/fixtures/projects/E013_missing_input/root.circ`, `tests/fixtures/projects/E013_missing_input/child.circ`, `tests/fixtures/projects/E008_loop_through_subcircuit/root.circ`, `tests/fixtures/projects/E008_loop_through_subcircuit/pass_through.circ`, `tests/fixtures/projects/W003_unused_import/root.circ`, `tests/fixtures/projects/W003_unused_import/unused.circ`, `tests/fixtures/projects/W002_dangling_subcircuit_output/root.circ`, `tests/fixtures/projects/W002_dangling_subcircuit_output/child.circ`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added `W003 unused import` row in `run_test.zig` (golden); added `project validator: clean_two_file`, `E012 unknown sub-circuit port`, `E013 sub-circuit arity mismatch`, `E008 combinational loop through sub-circuit`, `W003 unused import in project`, `W002 dangling sub-circuit output` in `project_passes_test.zig`; ran `zig build test`, result pass
**Next slice:** Implement Phase 7 Slice 7.5 multi-file emission — one `buildXxx` function per source file, sub-circuit call sites, updated runtime/file-info/debug-paths emitters.
**Notes:** `sub_circuit_ref` remains non-cycle-breaking in the single-file combinational-loop pass (correct for transparent sub-circuits). The project-level `run_project.zig` is additive on top of the per-module runner; no existing pass signatures changed.

## 2026-05-01 — Phase 7 — Slice 7.5 multi-file emission

**What shipped:** Wired project emission via `lib/emit/project.zig` (`emitProjectSource`): one `buildFile_<FileId>` per module, hierarchical `computeLayout` (`debug_paths`, `sub_circuits`, stable global IDs), runtime wiring with root `expected_component_count` checks, CLI compile/emit path using project IR when imports exist. **`input_pin_gate`** gained optional wired **`in`** fan-in (`circuit.connect` target) plus dominant-state recalculation so parent→subcircuit signal paths match Phase 7 call-site wiring (`inst.input_x.port("in")`). **`and_pair`** root fixture avoids the `and` keyword split by aliasing **`paired_and`**. Generated missing **`tests/fixtures/expected-zig/projects/{and_pair,nested_invert}/main.zig`** goldens.

**Files touched:** `lib/circuit.zig`, `lib/emit/project.zig`, `lib/emit/main.zig`, `cmd/circ-compile/main.zig`, `build.zig`, `tests/fixtures/projects/and_pair/root.circ`, `tests/emit/project_emit_test.zig`, `tests/emit/project_behavior_test.zig`, `tests/fixtures/expected-zig/projects/and_pair/main.zig`, `tests/fixtures/expected-zig/projects/nested_invert/main.zig`, `tests/fixtures/expected-wasm/projects/*.txt`, `DOCS/STATUS.md`

**Tests:** added `tests/emit/project_emit_test.zig` (golden), `tests/emit/project_behavior_test.zig` (wasm harness specs), `zig build test`; result **pass**. Added **`input_pin_gate` wired-in propagation** regression in `lib/circuit.zig`.

**Next slice:** Phase 7 Slice 7.6 hardening fixtures (diamond / deep-chain / same-name aliases) plus harness coverage per Phase 7 plan.

**Notes:** `emit_project` still uses **`threadlocal current_project`** for import-table lookups during Zig emission generation; callers are single-threaded today. Wired **`input_pin_gate`** ignores host **`setPin`** when **`in`** is connected (combinational dominance over wire); WASM only exposes **`setPin`** for root-listed inputs anyway.

## 2026-05-01 — Phase 7 — Slice 7.6 hardening fixtures

**What shipped:** Added Phase 7.6 regression projects under **`tests/fixtures/projects/`**: **`deep_chain/`** (five-file wrapper chain **`root`→`wrap2`→`wrap3`→`wrap4`→`leaf`**), **`same_name_half_adder/`** (two different **`half_adder.circ`** files in **`path_a/`** vs **`path_b/`**, root distinguishes them by import alias and builds **`out = a & ~b`**). **`diamond/root.circ`** now fans both branches through an **`and`** gate (**`out = l.out & r.out`**) so the shared **`base.circ`** is exercised without **`W002`** on the **`right`** leg. Wired **`tests/emit/project_emit_test.zig`** / **`project_behavior_test.zig`** entries plus **`tests/fixtures/expected-wasm/projects/{diamond,deep_chain,same_name_half_adder}.txt`** and matching **`tests/fixtures/expected-zig/projects/*/main.zig`** goldens. **`expectGolden`** now **`makePath`**'s fixture parents so **`UPDATE_GOLDENS=1`** can create nested **`expected-*`** paths.

**Files touched:** `tests/fixtures/projects/diamond/root.circ`, `tests/fixtures/projects/deep_chain/*.circ`, `tests/fixtures/projects/same_name_half_adder/**/*.circ`, `tests/fixtures/expected-wasm/projects/diamond.txt`, `tests/fixtures/expected-wasm/projects/deep_chain.txt`, `tests/fixtures/expected-wasm/projects/same_name_half_adder.txt`, `tests/fixtures/expected-zig/projects/diamond/main.zig`, `tests/fixtures/expected-zig/projects/deep_chain/main.zig`, `tests/fixtures/expected-zig/projects/same_name_half_adder/main.zig`, `tests/emit/project_emit_test.zig`, `tests/emit/project_behavior_test.zig`, `tests/helpers/golden.zig`, `DOCS/STATUS.md`

**Tests:** extended project emitter golden loop and wasm behavior matrix; **`zig build test`** result **pass**

**Next slice:** Phase 9 start (suite hardening) or Phase 8 built-in macros per **`DOCS/PLANS_PROMPT.md`** index — **`DOCS/STATUS`** should reflect whichever phase is active once Phase 7 is committed as done.

**Notes:** Phase 7 definition-of-done (**`DOCS/PLANS/PHASE_7_SUBCIRCUITS.md`**) is now satisfied by slices 7.1–7.6 in code + tests pending human **`git`** commit.

## 2026-05-01 — Phase 8 — Slice 8.1 built-in sources and embed table

**What shipped:** Added five macro **`.circ`** sources under **`lib/resolver/builtin_circ/`** (comments use **`//`** to match the langlang grammar). Added **`lib/resolver/builtins.zig`** with **`@embedFile`** for each, a **`Name`** enum (public surface name **`or`** maps from tag **`or_gate`** to avoid Zig keyword clashes), **`table`**, **`sourceForName`**, and **`sourceForPathSuffix`**. **`tests/resolver/builtins_test.zig`** asserts every expected name is present with non-empty bytes and that each blob parses through **`translate.parseSource`** with at least one input pin, one **`output`**, and one component instance. **`build.zig`** wires **`resolver_builtins_mod`** and the new test step.

**Files touched:** `lib/resolver/builtins.zig`, `lib/resolver/builtin_circ/*.circ`, `tests/resolver/builtins_test.zig`, `build.zig`, `DOCS/STATUS.md`

**Tests:** `built-in embed table covers or nand nor xor xnor with non-empty sources`, `built-in sources parse with inputs, outputs, and component instances`; **`zig build test`** result **pass**

**Next slice:** Phase 8 Slice 8.2 — dispatch **`<builtin>/`** paths in **`lib/resolver/file_loader.zig`** to the embed table.

**Notes:** Zig 0.15 **`@embedFile`** must stay inside the module tree, so built-ins are vendored under **`lib/resolver/builtin_circ/`** rather than **`templates/builtins/`** until a root-level embed manifest is introduced. Slice 8.2 should load **`xor.circ`** expecting **`nor`**/**`nand`**/**`or`** identifiers in the grammar (already literals in **`proto-circ.peg`**).

## 2026-05-01 — Phase 8 — Slice 8.2 virtual builtin path in file loader

**What shipped:** **`loadFile`** now recognizes paths starting with **`builtin_path_prefix`** (`"<builtin>/"`), resolves the suffix via **`builtins.sourceForPathSuffix`**, duplicates embedded bytes into **`LoadedFile.source`**, and returns **`error.BuiltinNotFound`** for unknown filenames (distinct from disk **`FileNotFound`**). **`resolveImportPath`** duplicates **``<builtin>/...`** import paths verbatim (no **`realpath`** / base-dir join) so scanners can enqueue virtual builtin modules. Wired **`resolver_file_loader_mod.addImport("builtins", resolver_builtins_mod)`**. **`tests/resolver/file_loader_test.zig`** covers embed equality, **`BuiltinNotFound`**, disk regression, and builtin **`resolveImportPath`**.

**Files touched:** `lib/resolver/file_loader.zig`, `build.zig`, `tests/resolver/file_loader_test.zig`, `DOCS/STATUS.md`

**Tests:** file-loader suite above; **`zig build test`** result **pass**

**Next slice:** Phase 8 Slice 8.4 per **`DOCS/PLANS/PHASE_8_BUILTIN_MACROS.md`** ( **`circ-compile`** / remaining macro UX); Slice 8.3 is **`DOCS/STATUS.md`** 2026-05-01 entry.

**Notes:** Invalid **``<builtin>/unknown.circ`** still surfaces as a hard **`loadFile`** error during scan (**`BuiltinNotFound`**) rather than **`E009`**; tightening diagnostics can wait until auto-import UX is finalized.

## 2026-05-01 — Phase 8 — Slice 8.3 implicit built-in macro imports

**What shipped:** After user imports per file, **`scan_imports`** appends **`implicit_builtin`** **`ResolvedImport`** rows for **`or`**/**`nand`**/**`nor`**/**`xor`**/**`xnor`** when that alias is not already declared—skipping only the self-edge (**`<builtin>/or.circ`** does not implicitly import **`or`**). User **`import`** of a macro alias must resolve to **``<builtin>/<name>.circ`** or **`E011`**. **`import_cycle`** excludes edges whose importer path starts with **`"<builtin>/"`** from **`E010`** detection but still traverses every edge for topo order so built-in compositions resolve before dependents. **`resolve_bodies`** loads bodies through **`file_loader.loadFile`** and merges implicit **`ir.UnresolvedImport`** rows (**`implicit_builtin: true`**). **`unused_import`** skips **`W003`** for implicit rows.

**Files touched:** `lib/resolver/scan_imports.zig`, `lib/resolver/import_cycle.zig`, `lib/resolver/resolve_bodies.zig`, `lib/resolver/file_loader.zig`, `lib/ir/types.zig`, `lib/validator/passes/unused_import.zig`, `build.zig`, **`tests/fixtures/projects/macro_import_collision/`**, resolver tests listed below, regenerated **`tests/fixtures/expected-zig/projects/*/main.zig`**.

**Tests:** macro wrong-path (**`E011`**) regression; **`scan_imports`** / **`resolve_bodies`** expectations updated for user + built-in file graph; **`UPDATE_GOLDENS=1 zig build test`** then **`zig build test`** — result **pass**

**Next slice:** Phase 8 Slice 8.5 — composition tests (full adder + user sub-circuit crossover) per **`PHASE_8_BUILTIN_MACROS.md`**.

**Notes:** **`file_loader.builtin_path_prefix`** aliases **`builtins.builtin_vpath_prefix`** so the builtin virtual path stays single-sourced.

## 2026-05-02 — Phase 8 — Slice 8.4 truth-table tests per built-in macro

**What shipped:** Added five single-file **`tests/fixtures/circuits/builtin_{or,nand,nor,xor,xnor}.circ`** fixtures (two inputs, one macro gate, **`output`** driven from the gate) plus matching **`tests/fixtures/expected-wasm/builtin_<name>.txt`** specs (all four input combinations). **`tests/emit/project_behavior_test.zig`** runs them through the same project scan → validate → **`emitProjectSource`** → WASM harness path as other multi-file tests via **`test "built-in macros: truth tables (or nand nor xor xnor)"`**.

**Files touched:** `tests/fixtures/circuits/builtin_*.circ`, `tests/fixtures/expected-wasm/builtin_*.txt`, `tests/emit/project_behavior_test.zig`, `DOCS/STATUS.md`

**Tests:** new looped harness test above; **`zig build test`** — result **pass**

**Next slice:** Phase 8 Slice 8.5 — full-adder + user/built-in composition fixtures and behaviour specs.

**Notes:** No CLI change; single root **`.circ`** still uses the project pipeline (implicit built-ins from slice 8.3).
