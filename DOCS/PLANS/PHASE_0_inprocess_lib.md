# Phase 0 — `inprocess-lib` build

> **Superseded (2026-05):** This initiative is no longer implemented. The orchestrator runs **`zig build wasm` via subprocess**; see `DOCS/decisions/compiler-pipeline.md` and `DOCS/PLANS_PROMPT.md`. Treat the rest of this file as **archival** spec only.

> **Dependencies:** None (first phase in the initiative).
> **Warnings:** Read `DOCS/PLANS_PROMPT.md` and `DOCS/decisions/compiler-pipeline.md`. `lib/orchestrator/inprocess_ffi.zig` must compile cleanly as a **library** root (export + internal helpers). Same `zig_compiler` build options as the root build’s vendor path.

## Goal

A maintainer can run a **dedicated build step** (concretely: `zig build inprocess-lib`, unless a short alias is chosen and documented) and obtain a **native static archive** that contains `circ_inprocess_compile` plus the full vendored `zig_compiler` graph compiled for that target and optimize mode. The artifact path and naming are **documented in-repo** (e.g. under `zig-cache` / `zig-out` conventions or an explicit `-p` prefix). No change yet to how `circ-compile` is produced by default.

## Scope

**In scope:**

- Add `addStaticLibrary` (or equivalent) in root `build.zig` whose **root module** is `lib/orchestrator/inprocess_ffi.zig`.
- Wire `b.dependency("zig_compiler", .{ .target = target, .optimize = optimize })` **only** for this artifact (not lazy-gated the same way as the optional fast path if that would block this step; this step must always be able to build the fat lib when invoked).
- Expose a top-level step `inprocess-lib` that depends on compiling + emitting the static library to a predictable location (install step or `getEmittedBin`).
- Fix any compile errors in `inprocess_ffi.zig` uncovered by building as `lib` root (e.g. error handling in `export` vs `compileImpl`, missing `try` paths, `Cache.Path` for `compiler_rt`).

**Explicitly deferred:**

- Linking that archive into `circ-compile` (Phase 1).
- `prebuilt/` directory, CI cache, contributor script (Phase 3).
- Swapping orchestrator / lazy dependency behavior for the default CLI (Phase 2).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|----------------|
| (optional) | `DOCS/PLANS/` (this file) | Already present; execution updates `DOCS/STATUS.md` only. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| Build | `build.zig` | Add `inprocess_lib` static artifact, `zig_compiler` + `aro` imports mirroring vendor `build.zig` expectations, step `inprocess-lib`. |
| Orchestrator | `lib/orchestrator/inprocess_ffi.zig` | Ensure valid library root: C export, error paths, alignment with `inprocess.zig` behavior. |

**New dependencies:** None beyond existing `build.zig.zon` → `zig_compiler` (already declared).

## Data & State

**C ABI (stable boundary for later phases):**

```zig
export fn circ_inprocess_compile(
    workspace_path_z: [*:0]const u8,
    zig_lib_dir_z: [*:0]const u8,
    compiler_rt_z: [*:0]const u8,
) callconv(.C) c_int;
```

- **Return:** `0` success, non-zero (e.g. `-1`) failure; diagnostics on failure remain on **stderr** (match `inprocess.zig` / `error_bundle.renderToStdErr` behavior).
- **Strings:** NUL-terminated; callee must not retain pointers after return.
- **Internal:** Same `zc.Compilation.Config` / `Directories` / `link_inputs` shape as `lib/orchestrator/inprocess.zig`, but `zig_lib_dir` and `compiler_rt` come from parameters, not `build_options`.

**Build artifact naming (to be fixed in implementation, document in STATUS):**

- Library name: `inprocess` → Zig emits `libinprocess.a` (Unix) / platform-specific on Windows if supported.

## Execution & Concurrency Model

This phase is **fully synchronous** at build time: `zig build inprocess-lib` runs the compiler once and writes the archive. Inside `circ_inprocess_compile`, the same **thread pool + arena** model as `inprocess.zig` applies (`track_ids = true` on the pool); no new background workers beyond what the vendored compiler already uses during `comp.update`.

## Persistence & I/O

- **Read:** Zig lib dir and `compiler_rt` archive paths passed as arguments (validated by opening `compiler_rt` like today).
- **Write:** `workspace_path`/… per existing contract (`zig-out/bin/compiled.wasm`).
- **Build output:** Static `.a` (or platform lib) under the build’s install or emitted-bin path; **not** committed to git in this phase.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Static lib target | `addStaticLibrary` + module imports (`zig_compiler`, aro chain as required by vendor `build.zig`) compile. | `zig build inprocess-lib` exits 0. |
| 2 | Step + path docs | Named step `inprocess-lib`; artifact path discoverable (README slice or comment in `build.zig` + STATUS note). | Human or CI can find `libinprocess.a` without reading all of `build.zig`. |
| 3 | FFI correctness | `inprocess_ffi.zig` matches `inprocess.zig` semantics for happy path + error rendering. | Optional: small Zig test exe in Phase 1; for Phase 0, `zig build inprocess-lib` + manual smoke of export symbols (`nm` / `llvm-nm` on the `.a` shows `circ_inprocess_compile`) if available on the host. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| (deferred to Phase 1–2) | — | Link test calling `circ_inprocess_compile` from a tiny driver. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `zig build inprocess-lib` | Build | Produces static library without building full `circ-compile`. |

Run command: `zig build inprocess-lib`

## Open Questions / Spikes

- **Exact emitted path** on each OS: document after implementation (`TODO(phase0):` replace with concrete path in contributor doc in Phase 3).
- **Windows static lib** naming if the project officially supports Windows builds for this initiative; if unsupported, state “Unix-only for prebuilt lib” in scope.
