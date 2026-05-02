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
