## 2026-05-05 — Phase 0 — Format spec

**What shipped:** Defined the `circ.topology` binary format as Zig types and constants.
**Files touched:** `lib/topology/format.zig`, `build.zig`
**Tests:** added `format: ComponentKind values are stable`, `format: PortName values are stable`, ran `zig build test`, result pass
**Next slice:** Interpreter + runtime changes
**Notes:** 
## 2026-05-05 — Phase 0 — Interpreter + runtime changes

**What shipped:** Implemented `templates/interpreter.zig` to decode `circ.topology` bytes and instantiate `circuit.zig`. Added `topology_alloc`, `topo_ptr`, `topo_len` to `templates/main.zig` and conditionally added generic WASM API wrapper functions (like `init`, `run`, `setPin`) which are enabled when building the pre-built WASM. Verified the old orchestrator compilation path is untouched.
**Files touched:** `templates/interpreter.zig`, `templates/main.zig`, `build.zig`, `lib/orchestrator/embed.zig`
**Tests:** added `interpreter: single not-gate topology`, `interpreter: rejects wrong magic`, `interpreter: rejects unknown version`, `interpreter: rejects truncated payload`, ran `zig build test`, result pass
**Next slice:** Pre-built runtime embed
## 2026-05-05 — Phase 0 — Node integration test

**What shipped:** Added a Zig integration test that hand-crafts a binary `circ.topology` payload, wraps it in a WASM custom section, appends it to the pre-built runtime WASM, and drives it via Node.js using the defined host protocol. This proves that the pre-built runtime with the interpreter is fully functional.
**Files touched:** `tests/e2e/phase0_node_test.zig`, `build.zig`
**Tests:** added `phase0: inverter round-trip via Node`, ran `zig build test`, result pass
**Next slice:** Topology serializer (Phase 1, Slice 1)
**Notes:** Phase 0 is now complete. The `circ-runtime.wasm` is pre-compiled and embedded in the CLI, and the Host Protocol for loading topology has been verified in Node.js.


## 2026-05-05 — Phase 1 — Single-file serializer

**What shipped:** Implemented `serializeModule` in `lib/topology/serializer.zig` which encodes a flat `ir.Module` into the `circ.topology` binary format.
**Files touched:** `lib/topology/serializer.zig`, `build.zig`
**Tests:** added `serialize: inverter module bytes`, `serialize: unknown port name returns error`, ran `zig build test`, result pass
**Next slice:** Recursive expander + project serializer
**Notes:** 


## 2026-05-05 — Phase 1 — Recursive expander + project serializer

**What shipped:** Implemented `serializeProject` and the recursive expander in `lib/topology/serializer.zig`. The expander flattens sub-circuit hierarchies into primitive records with globally-unique IDs and rewires input/output boundaries.
**Files touched:** `lib/topology/serializer.zig`
**Tests:** added `serialize: half-adder project flat`, ran `zig build test`, result pass
**Next slice:** Integration tests against all fixtures
**Notes:** 


## 2026-05-06 — Phase 1 — Integration tests against all fixtures

**What shipped:** Added `tests/e2e/phase1_node_test.zig` with 20 circuit and 12 project fixture tests. Each test runs the full pipeline (scan → cycle → resolve → validate → serialize → combine WASM → Node.js) and compares simulation output against expected values. Also added `serializeProjectFull` to `lib/topology/serializer.zig` to expose root pin ID mappings, and fixed two bugs in `lib/circuit.zig`: `State.flip(.undefined)` was returning Zig's `undefined` keyword (uninitialized memory) instead of the `.undefined` enum variant, and the AND gate was treating both-undefined inputs as HIGH instead of `.undefined`.
**Files touched:** `tests/e2e/phase1_node_test.zig`, `lib/topology/serializer.zig`, `lib/circuit.zig`, `build.zig`
**Tests:** added `phase1: circuits fixtures via Node` (20 fixtures), `phase1: project fixtures via Node` (12 fixtures), ran `zig build test`, result 123/123 pass
**Next slice:** Phase 2 Slice 1 — Section writer + unit tests
**Notes:** Phase 1 is complete. The `circuit.zig` undefined-state fixes are load-bearing for circuits with nested builtins (XOR, OR, NAND etc.) — without them, sequential `setPin` calls during multi-step tests produce wrong intermediate states that persist.


## 2026-05-06 — Phase 2 — Section writer + unit tests

**What shipped:** Implemented `lib/topology/section_writer.zig` with a public `combine(allocator, runtime_wasm, topology_payload) ![]u8` function and an internal LEB128 encoder. Validates WASM magic and minimum topology length. Six unit tests verify byte-exact encoding, LEB128 single/multi-byte cases, and error paths.
**Files touched:** `lib/topology/section_writer.zig`, `build.zig`
**Tests:** added `section_writer: custom section bytes are correct`, `section_writer: runtime bytes are preserved verbatim`, `section_writer: leb128 single byte`, `section_writer: leb128 multi byte`, `section_writer: rejects invalid runtime magic`, `section_writer: rejects short topology`, ran `zig build test`, result 129/129 pass
**Next slice:** Phase 2 Slice 2 — Integration tests (`WebAssembly.validate()` + full behavioral fixture tests via Node using `section_writer.combine`)
**Notes:** 


## 2026-05-06 — Phase 2 — Integration tests

**What shipped:** Added `tests/e2e/phase2_node_test.zig` with three tests: structural validity (`WebAssembly.validate()` for all 32 fixtures), and behavioral correctness for 20 circuit and 12 project fixtures. All tests use `section_writer.combine` to build the WASM and include a `WebAssembly.validate()` assertion at the start of every Node script.
**Files touched:** `tests/e2e/phase2_node_test.zig`, `build.zig`, `DOCS/STATUS.md`
**Tests:** added `phase2: combined wasm is structurally valid`, `phase2: circuits fixtures behavioral correctness`, `phase2: project fixtures behavioral correctness`, ran `zig build test`, result 132/132 pass
**Next slice:** Phase 3 Slice 1 — CLI wiring (`cmd/circ-compile/main.zig` calls `section_writer.combine` instead of `orchestrator.compile`)
**Notes:** Phase 2 is complete. `section_writer.combine` is the stable surface Phase 3 will call.

