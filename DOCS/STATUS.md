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
**Notes:** `templates/main.zig` uses `@hasDecl(compiled, "is_prebuilt_runtime")` to conditionally export the generic runtime API. In the next slice, the dummy `compiled.zig` must export `pub const is_prebuilt_runtime = true;` to activate this generic runtime API.

