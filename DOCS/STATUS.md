# Status log

Append-only entries for plan-driven work (`DOCS/PLANS_PROMPT.md`). Newest at the bottom.

## 2026-05-04 — Phase 0 — Static lib target (`inprocess-lib`)

**What shipped:** Root `build.zig` defines a static `inprocess` library from `lib/orchestrator/inprocess_ffi.zig` with a non-lazy `zig_compiler` dependency; `zig build inprocess-lib` installs `libinprocess.a` under the build prefix (`zig-out/lib/` with default `-p`). Fixed `callconv(.C)` → `callconv(.c)` for Zig 0.15.1.
**Files touched:** `build.zig`, `lib/orchestrator/inprocess_ffi.zig`
**Tests:** none added; ran `zig build inprocess-lib`, result pass; ran `zig build test`, result pass
**Next slice:** Phase 0 slice 2 — document artifact path (comment + STATUS / getting-started pointer) and optional `nm` smoke for `circ_inprocess_compile`.
**Notes:** Default `zig build` / `zig build test` do not build `inprocess-lib`; only the named step does.

## 2026-05-04 — Phase 0 — Step + path docs (`inprocess-lib`)

**What shipped:** `build.zig` documents install layout `<PREFIX>/lib/libinprocess.a`, default `-p` / `zig-out/`, and clarifies the `inprocess-lib` step description.
**Files touched:** `build.zig`
**Tests:** ran `zig build inprocess-lib -p /tmp/circ-inprocess-smoke`, result pass; confirmed `/tmp/circ-inprocess-smoke/lib/libinprocess.a` exists
**Next slice:** Phase 0 slice 3 — FFI comment parity / symbol smoke.
**Notes:** Human chose to continue without committing; follow-up commits may bundle Phase 0 slices.

## 2026-05-04 — Phase 0 — FFI parity + symbol smoke

**What shipped:** `inprocess_ffi.zig` doc comments aligned with `inprocess.zig` (`linker_import_symbols` rationale, path semantics, allocator note). Verified `nm <prefix>/lib/libinprocess.a` shows defined symbol `_circ_inprocess_compile` (Darwin).
**Files touched:** `lib/orchestrator/inprocess_ffi.zig`
**Tests:** `nm …/lib/libinprocess.a | grep circ_inprocess` after install, saw `T _circ_inprocess_compile`; ran `zig build test`, result pass
**Next slice:** Phase 1 slice 1 — `inprocess_stub.zig` + link proof (`DOCS/PLANS/PHASE_1_stub_link.md`).
**Notes:** Phase 0 plan slices 1–3 complete from a spec perspective; optional `getting-started.md` pointer deferred to Phase 3 tooling.
