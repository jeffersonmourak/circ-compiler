# STATUS

Append-only log of phase slices shipped. Newest entries at the bottom.

## 2026-05-04 — Phase 0 — Slice 1: Scaffold spike

**What shipped:** New `spike/` directory with its own `build.zig` and `src/main.zig`. The build resolves the system Zig lib dir via `b.graph.zig_lib_directory` and exposes it to `main.zig` through a generated `build_options` module. The stub `main` prints `spike ok` plus the resolved lib dir path and exits 0. `spike/out/` added to `.gitignore` ahead of Slice 2.
**Files touched:** `spike/build.zig` (new), `spike/src/main.zig` (new), `.gitignore`
**Tests:** ran `cd spike && zig build run` — exit 0, stdout `spike ok` followed by `zig_lib_dir: /Users/jeffersonmourak/.asdf/installs/zig/0.15.1/lib`.
**Next slice:** Phase 0 Slice 2 — wire `Compilation.create()` targeting `wasm32-freestanding` and emit `spike/out/add.wasm`.
**Notes:** Zig 0.15.1 is the pinned host toolchain (matches the 0.15.x range in `PLANS_PROMPT.md`). Important finding for Slice 2: the binary distribution at `~/.asdf/installs/zig/0.15.1/lib/` ships `std/`, `compiler/` (aro, build_runner, etc.), and `compiler_rt/`, but does **not** ship the Zig self-hosted compiler's own `src/Compilation.zig`. Calling `Compilation.create()` in-process therefore cannot rely on the installed `lib_dir` alone — Slice 2 will need either a Zig source checkout pointed at by env (e.g. `ZIG_SRC_DIR`) or the Phase 1 vendor drop brought forward as a read-only reference. Re-confirm before starting Slice 2 and update the spike accordingly. The `build_options.zig_lib_dir` path is wired through and ready for use by `Compilation.create()` regardless.

## 2026-05-04 — Phase 0 — Slice 2 (PARTIAL): Embedding hard-stop confirmed LLVM-free

**Status:** **PARTIAL** — the LLVM hard-stop test (the slice's primary spike question) is conclusively answered, but the slice's stated WASM-emit deliverable (`spike/out/add.wasm`) is not yet produced. Recommend splitting slice 2 in `DOCS/PLANS/PHASE_0_spike.md` before continuing — see "Recommendation" below.

**What shipped:** `spike/build.zig` now embeds the Zig 0.15.1 self-hosted compiler source as an in-process Zig module: it loads the source tree from `$ZIG_SRC_DIR`, mirrors Zig's own `addCompilerMod` (root = a small `spike_exports.zig` placed inside `<ZIG_SRC>/src/`; `aro` and `aro_translate_c` modules wired; `link_libc` enabled), and feeds the embedded compiler the full `build_options` set Zig itself uses (`have_llvm = false`, `dev = .wasm`, `value_interpret_mode = .direct`, `version = "0.15.1"`, semver, all tracy/debug flags off). `spike/src/main.zig` references `Compilation.create`, `Compilation.update`, and `Package.Module.create` by address (`@intFromPtr(&fn)`) to force comptime analysis through their full bodies and prevent dead-code elimination by the linker.

**Files touched:** `spike/build.zig`, `spike/src/main.zig`. Out-of-tree: `/tmp/zig-spike-src/zig-0.15.1/` (extracted Zig 0.15.1 source tarball — required by `ZIG_SRC_DIR`) plus a re-export shim at `/tmp/zig-spike-src/zig-0.15.1/src/spike_exports.zig`.

**Tests:**
- `ZIG_SRC_DIR=/tmp/zig-spike-src/zig-0.15.1 cd spike && zig build run` — exit 0; prints `spike ok` plus runtime addresses for `Compilation.create`, `Compilation.update`, `Package.Module.create`. The build links cleanly even with the full function bodies of those entry points reachable.
- `nm spike/zig-out/bin/spike | grep -cE '_LLVMInitialize|_LLVMCreate|_LLVMContext|_LLVMTarget|__ZN4llvm'` returns **0**. The only `nm` hits matching `llvm` are `std.zig.llvm.Builder` (a pure-Zig LLVM IR builder type in stdlib — no C/C++ LLVM library dependency).
- `ls -lh spike/zig-out/bin/spike` — 18 MB binary (the full self-hosted compiler is now compiled into the spike executable).

**Recommendation (plan revision needed):** Slice 2 in `DOCS/PLANS/PHASE_0_spike.md` should be split. As written it bundles two qualitatively different efforts: (a) prove the embedding strategy compiles & links LLVM-free, and (b) construct enough state to drive `Compilation.create()` end-to-end and emit a real WASM artifact. Step (a) is what shipped here. Step (b) requires standing up `Compilation.Directories.init`, a `Compilation.Config` (resolved from `Config.Options`), a `Package.Module` tree (root_mod, std_mod, main_mod with `Paths`, `Inherited`, target/optimize, and parent linkage), a `ThreadPool`, plus a 50+-field `CreateOptions` literal — i.e. a stripped-down replica of significant portions of Zig's `src/main.zig`. That is its own slice (or its own sub-phase), not a continuation of (a). Suggested split:
- **Slice 2a (this commit):** "Verify embedded compiler compiles & links LLVM-free."
- **Slice 2b:** "Construct minimum-viable `Compilation.Config` + `Package.Module` root + `Directories` and instantiate `Compilation.create()` (no emit yet)."
- **Slice 2c:** "Drive `comp.update()` and write `spike/out/add.wasm` with WASM magic check."

**Findings to carry forward:**
- LLVM hard stop is **not** triggered. `Compilation.zig` references `LlvmObject = @import("codegen/llvm.zig").Object`, but `codegen/llvm.zig` itself gates the LLVM bindings behind `if (build_options.have_llvm) @import("llvm/bindings.zig") else @compileError("LLVM unavailable")`. With `have_llvm = false` and `dev = .wasm`, no LLVM-bindings code path is reachable, and Zig's lazy comptime evaluation prunes it cleanly.
- Zig source size: 8103 lines for `Compilation.zig` alone, 1486 lines for Zig's own `build.zig`, 6000+ lines in `src/main.zig`. Phase 1 vendoring will need to be selective even with the WASM-only path constraint.
- Required transitive modules beyond `src/`: `lib/compiler/aro/aro.zig` and `lib/compiler/aro_translate_c.zig` must be registered as separate Zig modules even when not actually used at runtime, because `src/translate_c.zig` and `src/libs/mingw.zig` `@import("aro")` (only inside function bodies, but the module-resolution layer needs the names registered so type-checking doesn't fail when those bodies are analyzed).
- The shim `spike_exports.zig` lives inside `<ZIG_SRC>/src/` because Zig modules resolve relative `@import` paths from the module root's directory; placing the shim outside `src/` breaks `@import("Compilation.zig")` resolution.
- Phase 1 should plan for a roughly 18 MB embedded compiler at link time (release mode may shrink this; this measurement is ReleaseSafe-by-default).

**Next slice:** Slice 2b (per recommended split) — minimum-viable `Compilation.create()` instance with no emit, to flush out the runtime-config wiring before attempting WASM emission in Slice 2c.

## 2026-05-04 — Phase 0 — Slice 2 (FULL): `Compilation.create()` emits `add.wasm`

**Status:** **COMPLETE** — supersedes the partial slice 2 entry above. Slice 2 is fully shipped per the original `DOCS/PLANS/PHASE_0_spike.md` deliverable; no plan revision needed. The spike binary now drives `Compilation.create()` end-to-end and emits a real WASM artifact.

**What shipped:** `spike/src/main.zig` now performs the full in-process compilation: stages a hardcoded `pub export fn add(a: i32, b: i32) i32 { return a + b; }` source under `spike/out/work/add.zig`, initializes a `std.Thread.Pool` (with `track_ids = true`, required by Zig's compiler workers), constructs `Compilation.Directories` against the host Zig lib dir, resolves `wasm32-freestanding` via `std.zig.parseTargetQueryOrReportFatalError`, builds a `Compilation.Config` with `output_mode = .Exe`, `use_llvm = false`, `use_lib_llvm = false`, `use_lld = false`, creates a root `Package.Module` rooted at the staged source dir, and calls `Compilation.create()` with `cache_mode = .none`, `emit_bin = .{ .yes_path = ... }`, and `entry = .disabled` (since the export is a library function, not a `_start` program). Then drives `comp.update(progress)`, surfaces any `getAllErrorsAlloc()` errors via `renderToStdErr`, and verifies the output's WASM magic bytes (`\x00asm`).

The embedded compiler's `build_options` were also tightened: `dev = .full` (the spike's input compiles through `Air.legalize`, which `Env.wasm` does not gate as supported in Zig 0.15.1 even though the wasm backend's `legalizeFeatures()` returns non-null — see Findings) and `enable_debug_extensions = true` (required because non-wasm backend code paths in `dev = .full` reference `build_options.enable_debug_extensions` at comptime via `Air/print.zig`).

**Files touched:** `spike/build.zig`, `spike/src/main.zig`. (No new files in the repo; `/tmp/zig-spike-src/zig-0.15.1/` and its `src/spike_exports.zig` shim remain the same.)

**Tests:**
- `ZIG_SRC_DIR=/tmp/zig-spike-src/zig-0.15.1 zig build run` (in `spike/`): exit 0, prints `emit ok=true, size=901 bytes, path=…/spike/out/add.wasm`.
- `xxd spike/out/add.wasm | head -1` → `00000000: 0061 736d 0100 0000 …` — WASM magic `\0asm` confirmed.
- `nm spike/zig-out/bin/spike | grep -cE '_LLVMInitialize|_LLVMCreate|_LLVMContext|_LLVMTarget|__ZN4llvm'` → **0** (no LLVM C/C++ library symbols; the slice-3 hard-stop check passes ahead of slice 3).
- `ls -lh spike/out/add.wasm` → 901 bytes; `ls -lh spike/zig-out/bin/spike` → 57 MB Debug build (the embedded compiler is heavy in Debug; ReleaseFast/Small expected to shrink substantially).

**Findings to carry forward (additions / updates beyond the partial entry above):**
- `Compilation.CreateOptions.entry` defaults to `.default`, which requires a `_start` symbol on freestanding WASM `Exe` output. Use `.disabled` for library-style `pub export fn` outputs (matches `-fno-entry`).
- `output_mode = .Obj` for `wasm32-freestanding` is **not viable in Zig 0.15.1**: `src/link/Wasm.zig:3462` panics `TODO` when `comp.zcu != null and is_obj`. Use `.Exe` with `entry = .disabled` instead.
- `std.Thread.Pool` must be initialized with `.track_ids = true` for the Zig compiler — workers unwrap `id.?` unconditionally in their runFn, so `track_ids = false` panics on first task dispatch.
- `dev.Env.wasm` is missing the `legalize` feature in Zig 0.15.1 even though `arch/wasm/CodeGen.zig:legalizeFeatures()` returns non-null (so `runCodegenInner` always calls `air.legalize`). For now, set `dev = .full` for the spike. For Phase 1 vendoring, either patch `dev.zig` to add `.legalize` to `Env.wasm`'s feature set, or vendor against `.full` and rely on the runtime `use_llvm = false` / `use_lld = false` config to keep LLVM/LLD code paths unreached. The empirical `nm` check shows zero LLVM C/C++ symbols in the linked binary regardless.
- `dev = .full` pulls AArch64/x86_64/etc. backend modules into comptime analysis. Several of those backends gate code on `build_options.enable_debug_extensions` (e.g. `Air/print.zig:63 comptime assert(build_options.enable_debug_extensions)`). Set `enable_debug_extensions = true` in the embedded compiler's `build_options`.
- `Compilation.update(progress)` requires a `std.Progress.Node`. `std.Progress.start(.{ .disable_printing = true })` returns one suitable for the embedded use case; no terminal output is produced.
- The spike's binary grew from 18 MB (when only addresses of `Compilation.create`/`update`/`Module.create` were forced into reachability) to 57 MB once the full `dev = .full` codegen surface is reachable. ReleaseSafe/ReleaseFast builds will likely halve or quarter this; Phase 1 should re-measure.
- The hardcoded source compiles through Zig's standard pipeline (AstGen → Sema → AIR → wasm CodeGen → Wasm linker) and the resulting `add.wasm` exports the `add` function (visible as the literal string `add` at offset 0x29 in `xxd` output).

**Next slice:** Phase 0 Slice 3 — symbol inspection (`nm` check is already passing, just needs to be wired into a build step), then update `DOCS/STATUS.md` with a dedicated Phase 0 conclusion entry summarising whether to proceed to Phase 1 vendoring. The recommended slice-2 split in the partial entry above is **withdrawn** — slice 2 as originally written is shippable in one slice.

## 2026-05-04 — Phase 0 — Slice 3: Validate, document, and conclude Phase 0

**Status:** **COMPLETE**. Phase 0 ends here. The recommendation to the human is **proceed to Phase 1 (vendoring)** — embedding Zig's self-hosted compiler into a third-party `.wasm`-emitting binary is empirically viable on Zig 0.15.1, with no LLVM dependency.

**What shipped:** Wired the slice's symbol-inspection check into the spike's build system as a reproducible `zig build verify` step. The step shells out to `nm` + `grep -cE` against the installed binary and fails the build if any of `_LLVMInitialize*`, `_LLVMCreate*`, `_LLVMContext*`, `_LLVMTarget*`, or Itanium-mangled `llvm::` namespace symbols (`__ZN4llvm`) are present. PHASE_0_spike.md's literal test (`grep -i llvm`) was deliberately not used because Zig stdlib has a pure-Zig LLVM IR builder type at `std.zig.llvm.Builder` whose name unavoidably matches a case-insensitive `llvm` substring even though no LLVM C/C++ library is linked. The verify step targets the spike's actual hard-stop concern (LLVM library linkage) rather than the literal-but-misleading text.

**Files touched:** `spike/build.zig` (added `verify` step + a comment explaining the `grep -i llvm` discrepancy).

**Tests:**
- `cd spike && ZIG_SRC_DIR=/tmp/zig-spike-src/zig-0.15.1 zig build verify` → exit 0, prints `OK: 0 LLVM C/C++ library symbols in …/spike/zig-out/bin/spike`.
- `cd spike && ZIG_SRC_DIR=/tmp/zig-spike-src/zig-0.15.1 zig build run` (regression check) → still exit 0, still emits `spike/out/add.wasm` with valid WASM magic.

### Phase 0 conclusion

The single empirical question Phase 0 was designed to answer was: *can the Zig 0.15.1 self-hosted compiler be called in-process to emit a `wasm32-freestanding` `.wasm` artifact, with zero runtime LLVM dependency?* The answer is **yes**, with these caveats for Phase 1:

1. The spike must be configured with `have_llvm = false` in the embedded compiler's `build_options`, runtime `Compilation.Config` must set `use_llvm = false`, `use_lib_llvm = false`, and `use_lld = false`, and the WASM target plus `entry = .disabled` for library-style exports. With this configuration Zig's lazy comptime evaluation and the `if (build_options.have_llvm) … else @compileError` gate in `src/codegen/llvm.zig` keep all LLVM-bindings code paths unreachable.
2. `dev = .full` is required (not `.wasm`) because Zig 0.15.1's `Env.wasm` does not list `legalize` as supported even though `arch/wasm/CodeGen.zig:legalizeFeatures()` returns non-null. `.full` pulls in unrelated backend modules at comptime; that's tolerable at this stage but Phase 1 should consider patching `dev.zig` to add `.legalize` to `Env.wasm`'s feature set so a tighter compile-time surface is possible.
3. `enable_debug_extensions = true` is required when `dev = .full` because some non-wasm backend modules (`Air/print.zig`) `comptime assert(build_options.enable_debug_extensions)` — turning this off causes a comptime failure even when the runtime config never reaches those backends.
4. `output_mode = .Obj` for `wasm32-freestanding` with a Zig source ZCU is **not viable in 0.15.1** (`src/link/Wasm.zig:3462` panics `TODO`). Phase 1 must use `.Exe` with `entry = .disabled` for library-style outputs.
5. `std.Thread.Pool` must be initialized with `.track_ids = true`; Zig's compiler workers unwrap `id.?` unconditionally.
6. The 18 MB → 57 MB binary growth between "compiler embedded but not driven" and "compiler driven end-to-end" is from `dev = .full` Debug-mode codegen surface. Phase 1 should re-measure with ReleaseFast/ReleaseSmall and a tightened dev env. The current ~57 MB Debug binary is **larger than the entire current `circ-compile` shipping bundle**, so Phase 1's success criterion should include a release-mode size budget.
7. Phase 1's vendoring scope must include, at minimum: all of `src/` (8000+ lines in `Compilation.zig` alone, plus `Package.zig`, `Zcu.zig`, `Sema.zig`, `link.zig`, `link/Wasm.zig`, `arch/wasm/CodeGen.zig`, `target.zig`, `dev.zig`, `introspect.zig`, the `libs/` subtree, the `Compilation/` and `Package/` subtrees), `lib/compiler/aro/` and `lib/compiler/aro_translate_c.zig` (referenced inside function bodies even when not used at runtime), and the host Zig lib dir (`std/`, `compiler_rt/`, builtin headers — needed by `Compilation.Directories` for std module resolution at compile time of the user's source).
8. The vendored Zig source must be pinned to **0.15.1 exactly**; per `PLANS_PROMPT.md` recurring traps, internal compiler APIs change between patch releases. Any future host-toolchain bump in this repo must re-vendor the matching Zig source.

**Recommendation:** Begin Phase 1 (vendor a curated subset of Zig 0.15.1 source under `vendor/zig-compiler/`). Use the spike's `build.zig` as a starting point for the vendored module's build wiring; the `spike_exports.zig` shim can become a permanent `vendor/zig-compiler/exports.zig`. The entire `circ-compile` codebase will then drop the `zig build` subprocess shellout in Phase 2.

**Next slice:** Phase 1 Slice 1, per `DOCS/PLANS/PHASE_1_vendor.md` (initial vendor drop + project `build.zig` wiring; existing tests must continue to pass).

## 2026-05-04 — Phase 1 — Slice 1: Enumerate and copy vendor source

**What shipped:** Zig 0.15.1 compiler source vendored into `vendor/zig-compiler/`. The copy includes all 170 `.zig` files from `src/` (LLVM/Clang C/C++ bindings excluded: `zig_llvm.cpp`, `zig_llvm.h`, `zig_clang.cpp`, `zig_clang.h`, `zig_clang_cc1_main.cpp`, `zig_clang_cc1as_main.cpp`, `zig_clang_driver.cpp`, `zig_llvm-ar.cpp`), the `lib/compiler/aro/` subtree (aro C parser, required as a named module by `translate_c.zig`), and `lib/compiler/aro_translate_c.zig`. The spike's `spike_exports.zig` shim was renamed to `vendor/zig-compiler/src/exports.zig` and updated to remove spike-specific comments. A `vendor/zig-compiler/MANIFEST` (SHA256 per file, 235 entries, paths relative to repo root) guards against accidental modification.
**Files touched:** `vendor/zig-compiler/src/` (new, 170 `.zig` files + subdirs), `vendor/zig-compiler/lib/compiler/aro/` (new), `vendor/zig-compiler/lib/compiler/aro_translate_c.zig` (new), `vendor/zig-compiler/src/exports.zig` (new), `vendor/zig-compiler/MANIFEST` (new)
**Tests:** `sha256sum --check vendor/zig-compiler/MANIFEST` → 235 OK, exit 0.
**Next slice:** Phase 1 Slice 2 — write `vendor/zig-compiler/build.zig` (module named `zig-compiler`) and `vendor/zig-compiler/version.zig` (pinned version constant); verify `zig build` inside `vendor/zig-compiler/` exits 0.

## 2026-05-04 — Phase 1 — Slice 2: Module definition

**What shipped:** `vendor/zig-compiler/build.zig` defines the public `zig-compiler` module accessible to parent builds via `dep.module("zig-compiler")`. It re-creates the spike's module wiring: `aro` and `aro_translate_c` as private sub-modules, full 20-field `build_options` set (`have_llvm = false`, `dev = .full`, `enable_debug_extensions = true`, `version = "0.15.1"`, etc.), and `mod.link_libc = true`. The `DevEnv` and `ValueInterpretMode` enums are declared locally and matched to the Zig compiler source by field name (the compiler's `dev.zig` uses `@field(Env, @tagName(build_options.dev))` for type-safe name-based coercion). `vendor/zig-compiler/version.zig` exposes `pub const vendored_zig_version = "0.15.1";`. The MANIFEST was regenerated (237 entries) to include both new files.
**Files touched:** `vendor/zig-compiler/build.zig` (new), `vendor/zig-compiler/version.zig` (new), `vendor/zig-compiler/MANIFEST` (updated, 235 → 237 entries)
**Tests:** `cd vendor/zig-compiler && zig build` → exit 0 (no steps ran; module registered, no artifacts). `sha256sum --check vendor/zig-compiler/MANIFEST` → 237 OK, exit 0.
**Next slice:** Phase 1 Slice 3 — add `vendor/zig-compiler/build.zig.zon` and root `build.zig.zon`, wire `zig-compiler` module into `circ_compile_mod` in the repo root `build.zig`, and confirm the full test suite passes: `sha256sum --check vendor/zig-compiler/MANIFEST && zig build test`.
**Notes:** Parent `build.zig` in Slice 3 should use `b.dependency("zig-compiler", .{ .target = target, .optimize = optimize })` then `dep.module("zig-compiler")`. This requires two `build.zig.zon` files: one at the repo root (declares the path dep) and one at `vendor/zig-compiler/` (package identity). The vendor's `.zig-cache/` is already gitignored by the root `.gitignore` rule `.zig-cache/`; the MANIFEST `find` command must exclude `*/.zig-cache/*` and `*/zig-out/*` paths. The `circ_compile_exe` already calls `linkLibC()` in the root build.zig so no additional linkage step is needed for the `mod.link_libc = true` flag; the Slice 3 diff should be minimal (add dep + addImport).
**Notes:** With `dev = .full` required (see Phase 0 Slice 3 findings), the full `src/` tree is needed at comptime — no backend can be trimmed without patching `dev.zig`. The manual trim pass noted in `PHASE_1_vendor.md`'s TODO is deferred to a follow-on slice after Phase 1 core is confirmed working. The `exports.zig` module root lives inside `src/` so that `@import("Compilation.zig")` and siblings resolve as relative paths from the module root directory — identical to how `spike_exports.zig` worked in the spike. Total vendor size: 27MB (235 files). The `zig-compiler` module's `build.zig` (Slice 2) must wire the `aro` and `aro_translate_c` sub-modules exactly as the spike does, and supply the same `build_options` set (`have_llvm = false`, `dev = .full`, `enable_debug_extensions = true`, etc.).
