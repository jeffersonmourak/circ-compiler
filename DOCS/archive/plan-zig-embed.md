# Archived plan: zig-embed

**Canonical commit:** `d24a641d74c91f51e306b1f4c2621bcfe3f1370f` (`d24a641 Refactor PATH management in GitHub Actions workflow to enhance Zig binary handling`)
**Archived on:** 2026-05-04
**Plan duration:** 2026-05-04 → 2026-05-04

> This file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the commit referenced above. Check that commit out (`git show d24a641d74c91f51e306b1f4c2621bcfe3f1370f:DOCS/PLANS_PROMPT.md`, etc.) when you need the unabridged source.

## Goal & scope

Replace the circuit-compile-time `zig build` subprocess with Zig’s self-hosted compiler linked in-process so end users do not need `zig` in `PATH` to produce `.wasm` from emitted Zig. The output contract stays a single self-contained `.wasm` per `.circ` source (`DOCS/decisions/compiler-pipeline.md`). Vendored compiler source is pinned to **Zig 0.15.1**; only the WASM/self-hosted path is in scope, with **no LLVM C/C++ library** at link time (`have_llvm = false`, runtime `use_llvm = false`, `use_lib_llvm = false`, `use_lld = false`). `--emit-zig`, `--inspect`, and `--build-dir` semantics must remain unchanged.

**Deviation from plan prompt:** Original definition of done required byte-for-byte `.wasm` parity with the subprocess path; Phase 2 proved that unachievable (LLD subprocess vs Zig self-hosted WASM linker). Functional equivalence is validated by the full test suite and behavior harness instead.

## Phase-by-phase highlights

### Phase 0 — Spike (`DOCS/PLANS/PHASE_0_spike.md`)

**Goal (one sentence):** Prove `Compilation.create()` in-process on `wasm32-freestanding` emits real WASM with zero LLVM library symbols.

**What shipped (from STATUS):**

- `spike/` scaffold: `spike/build.zig`, `spike/src/main.zig`, `build_options` wiring for `zig_lib_dir`, `spike/out/` gitignored.
- Full slice-2 path: staged `add.zig`, `Compilation.create()` / `comp.update()`, `emit_bin` to `spike/out/add.wasm`, WASM magic `\x00asm`, `nm` shows **0** matches for `_LLVMInitialize|_LLVMCreate|_LLVMContext|_LLVMTarget|__ZN4llvm`.
- Slice 3: `zig build verify` encodes the `nm` + `grep -cE` check (explicitly **not** `grep -i llvm` because `std.zig.llvm.Builder` matches case-insensitive `llvm`).
- Phase 0 conclusion documents: `dev = .full` + `enable_debug_extensions = true` required for 0.15.1; `output_mode = .Exe` + `entry = .disabled` for library-style exports; `.Obj` panics `TODO` in `src/link/Wasm.zig:3462`; `std.Thread.Pool` needs `track_ids = true`; `ZIG_SRC_DIR` / full `src/` scope for Phase 1.

**Deviations / open questions:** Plan assumed synchronous spike; actual compiler uses internal `ThreadPool` — wired correctly. Spike relied on out-of-tree Zig source + `vendor/zig-compiler/src/exports.zig` pattern carried into Phase 1.

### Phase 1 — Vendor (`DOCS/PLANS/PHASE_1_vendor.md`)

**Goal (one sentence):** Check Zig 0.15.1 compiler sources into `vendor/zig-compiler/` as a build module without changing runtime behavior yet.

**What shipped:**

- Copy of 170 `src/*.zig` (LLVM/Clang C++ bridges excluded), `lib/compiler/aro/`, `lib/compiler/aro_translate_c.zig`, `vendor/zig-compiler/src/exports.zig` (ex-`spike_exports`), `vendor/zig-compiler/MANIFEST` with `sha256sum --check`.
- `vendor/zig-compiler/build.zig` + `version.zig` (`vendored_zig_version = "0.15.1"`), `build.zig.zon` / root `build.zig.zon`, root `build.zig` wires `b.dependency("zig_compiler", …)` and `addImport("zig_compiler", …)` — bare identifier required by Zig 0.15.x for package/module names.
- Slice 3: module linked into `circ_compile_mod`; `zig build test` + MANIFEST check pass.

**Deviations:** Phase 1 plan said “linked but unused”; Phase 2 immediately imports — fine. `aro_translate_c/ast.zig` was missing from first drop; added in Phase 2 Slice 2. “Manual trim” of `dev.zig` / backend surface deferred per STATUS notes.

### Phase 2 — Integrate (`DOCS/PLANS/PHASE_2_integrate.md`)

**Goal (one sentence):** Swap orchestrator subprocess for `lib/orchestrator/inprocess.zig` calling vendored `zc.Compilation`.

**What shipped:**

- `lib/orchestrator/inprocess.zig` with `compile(allocator, workspace_path, stderr_writer) !void`: thread pool `track_ids = true`, `Compilation.Directories`, `wasm32-freestanding`, `cache_mode = .none`, `emit_bin = .{ .yes_path = …/zig-out/bin/compiled.wasm }`, `error_bundle.renderToStdErr`, `std.Progress.Node.none` (avoid second `std.Progress.start` in tests).
- `tests/orchestrator/inprocess_test.zig` — asserts output WASM magic after `inprocess.compile`.
- `lib/orchestrator/main.zig` calls `inprocess_mod.compile` instead of `subprocess_mod.runCommand`.
- Fixes: `std.Build.Cache.Path.initCwd` for object paths, `wasm_compiler_rt` opened relative to cwd, `lib/log.zig` `extern "env"` for WASM imports, `cmd/circ-compile/main.zig` `pub const std_options: std.Options = .{ .log_level = .warn }`, `linker_import_symbols = true` where needed.

**Deviations:** Byte-for-byte subprocess vs in-process WASM **not** shipped; documented and accepted — `TODO(phase2)` fallback to functional tests (`main_test.zig`, `integration_test.zig`, `inprocess_test.zig`). `lib/orchestrator/subprocess.zig` **not** deleted (explicit deferral).

### Phase 3 — Harden (`DOCS/PLANS/PHASE_3_harden.md`)

**Goal (one sentence):** CI proves no `zig` on `PATH` after build; docs record embedding and user-facing “no Zig for circuit compile.”

**What shipped:**

- `.github/workflows/e2e.yml` — matrix (e.g. `macos-latest`, Linux), install Zig 0.15.1, `ReleaseFast` build, strip `zig` from `PATH`, run `./zig-out/bin/circ-compile tests/fixtures/circuits/inverter.circ -o out.wasm`, Python asserts `\x00asm`.
- `DOCS/decisions/compiler-pipeline.md` — pipeline shape and in-process configuration narrative updated; prior “embedding rejected” superseded.
- `DOCS/getting-started.md` — prebuilt-binary path first; Zig only for building the CLI; no runtime `zig build` for circuits.

**Deviations:** PATH strip validates **no shellout to `zig`**, not “zero Zig files on disk” — `zig_lib_dir` is still resolved from the toolchain at **circ-compile** build time. Full embedding of `std/` + `compiler_rt/` on disk for the CLI binary remains out of scope for these phases.

## Diagnostic / API surface pinned by this initiative

| Kind | Stable references |
|------|-------------------|
| **Validator / circuit diagnostics** | Unchanged by this plan — still `E001`–`E008`, `W001`–`W002` in `lib/validator/codes.zig` (see archived [plan-v0.md](plan-v0.md) for the original v0 highlight list). |
| **In-process compiler config** | `have_llvm = false`, `use_llvm = false`, `use_lib_llvm = false`, `use_lld = false`, `dev = .full`, `enable_debug_extensions = true`, target `wasm32-freestanding`, `output_mode = .Exe`, `entry = .disabled`, `cache_mode = .none`, `std.Thread.Pool` with `track_ids = true` — as recorded in `DOCS/decisions/compiler-pipeline.md`. |
| **Orchestrator API** | `lib/orchestrator/inprocess.zig` — `pub fn compile(allocator: std.mem.Allocator, workspace_path: []const u8, stderr_writer: anytype) !void` |
| **Build / module IDs** | Root `build.zig.zon` dependency key `zig_compiler`; `@import("zig_compiler")` from orchestrator modules; `vendor/zig-compiler/MANIFEST` integrity via `sha256sum --check vendor/zig-compiler/MANIFEST`. |
| **LLVM-free check (spike)** | `cd spike && ZIG_SRC_DIR=… zig build verify` — `nm` + `grep -cE '_LLVMInitialize\|_LLVMCreate\|_LLVMContext\|_LLVMTarget\|__ZN4llvm'` must yield **0**. |
| **Tests (names / areas)** | `tests/orchestrator/inprocess_test.zig` (in-process WASM magic); `tests/orchestrator/main_test.zig`; `tests/cli/integration_test.zig`; full `zig build test`. |
| **CI** | `.github/workflows/e2e.yml` — post-build `PATH` filter removing `zig`, fixture `tests/fixtures/circuits/inverter.circ`, `out.wasm` magic check. |

## Known papercuts carried forward

- **WASM bytes differ by linker:** Subprocess path used LLD; in-process uses Zig’s self-hosted WASM linker — layouts differ; equality test deferred; rely on harness + integration tests.
- **`orchestrator_subprocess` still in tree:** Subprocess module and `build.zig` wiring kept for potential reuse; not the default path.
- **`std.Progress` singleton:** Multiple in-process compilations in one process must not call `std.Progress.start` twice — use `std.Progress.Node.none` (as in `inprocess.zig`).
- **`dev = .full` binary weight:** Pulls broad backend surface at comptime; tightening `Env.wasm` / patching `dev.zig` for `.legalize` deferred to future work.
- **E2E “no Zig” semantics:** Stripping `PATH` does not remove the installed toolchain used to bake `zig_lib_dir` at **build** time; true hermetic “no Zig on disk” for the distributed binary is not claimed.
- **Zig cache:** `cache_mode = .none`; clearing `~/.cache/zig` in CI is a belt-and-suspenders check, not proven mandatory for correctness on all hosts.
- **Plan prompt vs shipped DoD:** “Byte-for-byte identical `.wasm`” in `PLANS_PROMPT.md` was not met; superseded by functional equivalence + docs/decision updates.

## Decisions & specs that survived the plan

Living documentation (not copied here):

- [architecture.md](../architecture.md)
- [circuit-format.md](../circuit-format.md)
- [wasm-api.md](../wasm-api.md)
- [simulation-engine.md](../simulation-engine.md)
- [decisions/index.md](../decisions/index.md) — especially [compiler-pipeline.md](../decisions/compiler-pipeline.md)
- [getting-started.md](../getting-started.md)
