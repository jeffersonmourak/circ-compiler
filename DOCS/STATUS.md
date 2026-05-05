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

## 2026-05-04 — Phase 1 — Stub + link + orchestrator wiring

**What shipped:** Added `lib/orchestrator/inprocess_stub.zig` (`compile` → `circ_inprocess_compile`), refactored wasm `compiler_rt` + `build_options` into `addInprocessWasmBuildOptions`, `-Dorchestrator-inprocess-stub` switches `inprocess_mod` root to the stub and links `inprocess_static_lib` into `circ-compile` / orchestrator tests; `circ_compile` skips `zig_compiler` import in stub mode. Added `tests/orchestrator/stub_link_smoke_main.zig` and `zig build stub-link-smoke` (always uses stub + fat lib, independent of `-D`). `lib/orchestrator/main.zig` unchanged — indirection is **module root swap** in `build.zig` only.
**Files touched:** `build.zig`, `lib/orchestrator/inprocess_stub.zig`, `tests/orchestrator/stub_link_smoke_main.zig`
**Tests:** ran `zig build test` (default), pass; `zig build stub-link-smoke`, pass; `zig build test -Dorchestrator-inprocess-stub=true`, pass
**Next slice:** Phase 2 — fast path / `prebuilt/` detection (`DOCS/PLANS/PHASE_2_fast_path.md`).
**Notes:** Stub mode still compiles `libinprocess` via the existing `inprocess_static_lib` step in the graph (same artifact as `zig build inprocess-lib`); Phase 2 can prefer a path-only prebuilt when present.

## 2026-05-04 — Phase 2 — Prebuilt fast path (`circ-prebuilt-inprocess`)

**What shipped:** `-Dcirc-prebuilt-inprocess=true` when `prebuilt/libinprocess.a` exists enables stub graph **without** compiling the fat `inprocess_static_lib` into `circ-compile` / orchestrator tests (link via `root_module.addObjectFile`). Unified flag `use_stub_inprocess_graph` = `-Dorchestrator-inprocess-stub` OR prebuilt fast path. Configure-time `@panic` if flag set but archive missing. Added `linkInprocessForStub` helper and `prebuilt/.gitignore` for `*.a` / `*.lib`.
**Files touched:** `build.zig`, `prebuilt/.gitignore`
**Tests:** `zig build test` (default), pass; `zig build circ-compile -Dcirc-prebuilt-inprocess=true --summary all` with prebuilt present, pass (link line includes `prebuilt/libinprocess.a`, no vendored `zig_compiler` module); `zig build test -Dcirc-prebuilt-inprocess=true`, pass
**Next slice:** Phase 3 — `tools/build-inprocess-lib.sh`, CI cache, contributor docs (`DOCS/PLANS/PHASE_3_tooling_ci.md`).
**Notes:** Fast path requires copying `zig-out/lib/libinprocess.a` (or other `-p`) to `prebuilt/libinprocess.a` after `zig build inprocess-lib`. Sandbox builds can hit `PermissionDenied` on Zig global cache when linking the exe; run the same command with full permissions if needed.
