## 2026-05-05 — Phase 0 — Format spec

**What shipped:** Defined the `circ.topology` binary format as Zig types and constants.
**Files touched:** `lib/topology/format.zig`, `build.zig`
**Tests:** added `format: ComponentKind values are stable`, `format: PortName values are stable`, ran `zig build test`, result pass
**Next slice:** Interpreter + runtime changes
**Notes:** 