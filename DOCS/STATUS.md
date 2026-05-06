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
## 2026-05-05 — Phase 0 — Pre-built runtime embed

**What shipped:** Added a `zig build` step to pre-compile the runtime template into a standalone WASM binary and embedded it into the `circ-compile` executable via `lib/topology/runtime_embed.zig`.
**Files touched:** `build.zig`, `lib/topology/runtime_embed.zig`
**Tests:** ran `zig build test`, result pass
**Next slice:** Hand-crafted Node integration test (proving Phase 0)
**Notes:** 

