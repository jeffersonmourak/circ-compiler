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
