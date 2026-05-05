# Status log

Append-only entries for plan-driven work (`DOCS/PLANS_PROMPT.md`). Newest at the bottom.

**Current pipeline:** WASM is built with **`zig build wasm` in a subprocess** (no compiler sources in this repo). Optional **`zig build inprocess-lib`** produces **`libinprocess.a`** using a **separate ziglang/zig source checkout** plus the **installed Zig `lib/`** (see `zig env`). Entries from **Phase 0 through Phase 3** below are **historical** (superseded vendor/prebuilt initiative); the **Subprocess Zig** entry describes the default orchestrator path today.

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

## 2026-05-04 — Phase 3 — Tooling + CI + docs

**What shipped:** Added executable `tools/build-inprocess-lib.sh` (tmp prefix + `zig build inprocess-lib` + copy to `prebuilt/libinprocess.a`, forwards extra args). Documented fast path in `DOCS/getting-started.md` and one-line pointer in `DOCS/PLANS_PROMPT.md`. `.github/workflows/e2e.yml`: `actions/cache` on `prebuilt/libinprocess.a` with key including platform, Zig version, `inprocess_ffi.zig`, `MANIFEST`, `build.zig`/`build.zig.zon`; cache-miss step runs the script; `circ-compile` uses `-Dcirc-prebuilt-inprocess=true`. `tests/e2e/linux-docker/run.sh` uses the script + fast path for the host-built Linux ELF.
**Files touched:** `tools/build-inprocess-lib.sh`, `DOCS/getting-started.md`, `DOCS/PLANS_PROMPT.md`, `DOCS/STATUS.md`, `.github/workflows/e2e.yml`, `tests/e2e/linux-docker/run.sh`
**Tests:** `bash tools/build-inprocess-lib.sh`, pass; `zig build test` (default), pass
**Next slice:** Planned phases 0–3 complete; optional: `cli-tag.yml` prebuilt matrix or Windows.
**Notes:** `cli-tag.yml` unchanged (cross-target release builds still full compile). Cold E2E cache miss pays one `inprocess-lib` build before fast `circ-compile`.

## 2026-05-04 — Subprocess Zig (remove vendor / in-process compiler)

**What shipped:** Orchestrator runs `zig build wasm` in the workspace via `subprocess.zig` instead of in-process `Compilation`. Removed `vendor/zig-compiler`, `build.zig.zon` dependency, `inprocess*.zig`, FFI/stub/prebuilt build options, `tools/build-inprocess-lib.sh`, and related tests. `circ-compile` handles `error.ZigBinaryNotFound`. E2E workflow no longer strips `zig` from PATH (compile requires `zig`). Updated `DOCS/decisions/compiler-pipeline.md`, `DOCS/getting-started.md`, `DOCS/PLANS_PROMPT.md` (archived prior plan).
**Files touched:** `lib/orchestrator/main.zig`, `build.zig`, `build.zig.zon`, `cmd/circ-compile/main.zig`, `.github/workflows/e2e.yml`, `tests/e2e/linux-docker/run.sh`, docs; deleted `vendor/zig-compiler/`, `lib/orchestrator/inprocess*.zig`, `tests/orchestrator/inprocess_test.zig`, `tests/orchestrator/stub_link_smoke_main.zig`, `tools/build-inprocess-lib.sh`
**Tests:** ran `zig build test`, pass
**Next slice:** None for this migration; re-pin `build.zig.zon` fingerprint if Zig prompts after dependency removal.
**Notes:** Prebuilt `DOCS/PLANS/PHASE_*.md` describe obsolete workstreams. Release download text now assumes users have Zig 0.15.x on PATH for wasm compilation.

## 2026-05-05 — libinprocess via ziglang checkout + installed lib dir

**What shipped:** Restored **`zig build inprocess-lib`** with **`lib/orchestrator/inprocess_ffi.zig`** and **`lib/zig_compiler_exports/zig_compiler_exports.zig`**. Compiler modules resolve against **`ZIG_COMPILER_SRC`** / **`-Dzig-compiler-src`** (ziglang/zig tree matching 0.15.x); **`circ_zig_compiler_exports.zig`** is auto-copied into that checkout’s **`src/`** when missing. No **`vendor/zig-compiler`** or **`build.zig.zon`** dependency. Default **`circ-compile`** path unchanged (subprocess).
**Files touched:** `build.zig`, `lib/orchestrator/inprocess_ffi.zig`, `lib/zig_compiler_exports/zig_compiler_exports.zig`, `DOCS/decisions/compiler-pipeline.md`, `DOCS/getting-started.md`, `DOCS/STATUS.md`
**Tests:** ran `zig build test`, pass; `zig build inprocess-lib -Dzig-compiler-src=…` against ziglang/zig 0.15.1 checkout, pass; `nm` shows **`circ_inprocess_compile`**
**Next slice:** None required for this slice.
**Notes:** Zig’s install **`lib/`** (e.g. asdf `…/lib`) has **std / compiler_rt / tools** but **not** **`src/Compilation.zig`**; embedding still needs a source checkout.

## 2026-05-05 — Restore pre-subprocess orchestrator wiring (external zig_compiler only)

**What shipped:** Reapplied **`inprocess.zig`**, **`inprocess_stub.zig`**, **`inprocess_test`**, **`stub-link-smoke`**, **`linkInprocessForStub`**, **`addInprocessWasmBuildOptions`**, stub/prebuilt **`build.zig`** flags, and conditional **`zig_compiler`** **`circ-compile`** import — all using **`zig_compiler_embed_mod`** from **`ZIG_COMPILER_SRC`** (no **`lazyDependency`**). **`lib/orchestrator/main.zig`** reads **`orchestrator_build_options.use_subprocess_for_wasm`** (default subprocess; **`-Dorchestrator-use-inprocess`** opts into embedded path). Restored **`tools/build-inprocess-lib.sh`** as a thin **`zig build inprocess-lib`** wrapper.
**Files touched:** `build.zig`, `lib/orchestrator/main.zig`, `lib/orchestrator/inprocess.zig`, `lib/orchestrator/inprocess_stub.zig`, `tests/orchestrator/inprocess_test.zig`, `tests/orchestrator/stub_link_smoke_main.zig`, `tools/build-inprocess-lib.sh`, `DOCS/decisions/compiler-pipeline.md`, `DOCS/STATUS.md`
**Tests:** ran `zig build test`, pass (without **`ZIG_COMPILER_SRC`**; **`inprocess_test`** skipped unless stub/compiler graph enabled)
**Next slice:** None.
**Notes:** **`stub-link-smoke`** / **`inprocess-lib`** still require **`ZIG_COMPILER_SRC`** (or prebuilt archive for stub-only links).
