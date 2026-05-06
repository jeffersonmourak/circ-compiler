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

