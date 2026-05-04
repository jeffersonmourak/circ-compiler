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
