# STATUS

Append-only log of phase slices shipped. Newest entries at the bottom.

## 2026-05-04 — Phase 0 — Slice 1: Scaffold spike

**What shipped:** New `spike/` directory with its own `build.zig` and `src/main.zig`. The build resolves the system Zig lib dir via `b.graph.zig_lib_directory` and exposes it to `main.zig` through a generated `build_options` module. The stub `main` prints `spike ok` plus the resolved lib dir path and exits 0. `spike/out/` added to `.gitignore` ahead of Slice 2.
**Files touched:** `spike/build.zig` (new), `spike/src/main.zig` (new), `.gitignore`
**Tests:** ran `cd spike && zig build run` — exit 0, stdout `spike ok` followed by `zig_lib_dir: /Users/jeffersonmourak/.asdf/installs/zig/0.15.1/lib`.
**Next slice:** Phase 0 Slice 2 — wire `Compilation.create()` targeting `wasm32-freestanding` and emit `spike/out/add.wasm`.
**Notes:** Zig 0.15.1 is the pinned host toolchain (matches the 0.15.x range in `PLANS_PROMPT.md`). Important finding for Slice 2: the binary distribution at `~/.asdf/installs/zig/0.15.1/lib/` ships `std/`, `compiler/` (aro, build_runner, etc.), and `compiler_rt/`, but does **not** ship the Zig self-hosted compiler's own `src/Compilation.zig`. Calling `Compilation.create()` in-process therefore cannot rely on the installed `lib_dir` alone — Slice 2 will need either a Zig source checkout pointed at by env (e.g. `ZIG_SRC_DIR`) or the Phase 1 vendor drop brought forward as a read-only reference. Re-confirm before starting Slice 2 and update the spike accordingly. The `build_options.zig_lib_dir` path is wired through and ready for use by `Compilation.create()` regardless.
