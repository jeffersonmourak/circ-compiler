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
