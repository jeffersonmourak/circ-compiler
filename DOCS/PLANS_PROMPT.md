# Plan Prompt — Prebuilt inprocess library (FFI split)

## What Is Being Built

Circuit compilation today pulls the full vendored Zig compiler (`vendor/zig-compiler`) into the **same** compilation unit as `circ-compile` via `@import("zig_compiler")`, which makes **cold** and **invalidated** `zig build circ-compile` runs very slow.

This initiative introduces a **split compile**: a **static library** (`libinprocess`) built from `lib/orchestrator/inprocess_ffi.zig`, exporting a **narrow C ABI** (`circ_inprocess_compile` with NUL-terminated paths). That archive contains the vendored compiler and the compilation driver. The main `circ-compile` executable uses a **thin Zig stub** that declares the C symbol, supplies `zig_lib_dir` and wasm `compiler_rt` paths (still produced or resolved by the **main** `build.zig`—that step stays small), and links the prebuilt archive when enabled.

**Definition of done:** With the fast path enabled and a matching `libinprocess` present on disk (built locally or restored from CI cache), `zig build circ-compile` **does not** pull `zig_compiler` into the main executable’s Zig module graph; `zig build test` and existing E2E workflows still pass; refresh of the library is documented and reproducible (pinned Zig 0.15.1). **Prebuilt `*.a` files are not committed** to the main branch: `prebuilt/` is ignored by git; CI may cache build outputs; optional release binaries are out of scope unless added later.

**Anchors:** Runtime behavior stays aligned with `DOCS/decisions/compiler-pipeline.md` (in-process `Compilation.create` / `comp.update`, wasm32-freestanding, no subprocess `zig` on the compile path). The FFI boundary is an implementation detail for **build-time** speed; it must not regress the user-facing contract of `circ-compile`.

## Tech Stack

- **Language:** Zig 0.15.1 (pinned; must match vendored compiler slice and the toolchain used to build `libinprocess`).
- **Build:** Root `build.zig` / `build.zig.zon`; nested or sibling `zig build inprocess-lib` (exact step name as implemented in Phase 0).
- **Vendored compiler:** `vendor/zig-compiler` (unchanged semantics; only **where** it is compiled moves for the fast path).
- **Tests:** `zig build test`; orchestrator / inprocess tests; CLI integration tests as already wired.
- **E2E:** Linux Docker flow under `tests/e2e/linux-docker/` (must keep passing once CI uses the fast path or builds the lib first).
- **Artifacts:** Static archives per native target (and optimize mode if multiple are supported); **not** stored in git.

## Architectural Constraints

- **`DOCS/decisions/compiler-pipeline.md`:** Pipeline remains parse → IR Zig → in-process compilation → wasm; no requirement for `zig` on PATH at circuit-compile time for the default path.
- **Same Zig version** for building `libinprocess` and building `circ-compile`; mismatches are unsupported and should be documented as a recurring trap.
- **`compiler_rt` for wasm32:** Still supplied as today (host `zig build-lib` of `compiler_rt`); paths may be passed at runtime into the FFI entry rather than only `@import("build_options")` inside the fat library.
- **Thread pool / allocator / `Progress`:** Preserve the invariants already established in `lib/orchestrator/inprocess.zig` (e.g. `track_ids = true`, avoid nested `std.Progress` misuse in tests) when logic lives in `inprocess_ffi.zig` or the stub.
- **No `git write` / `gh` from the execution agent** (per working loop below).

## Phase Index

| Phase | Name | What Ships |
|-------|------|------------|
| 0 | `inprocess-lib` build | A dedicated `build.zig` step (e.g. `zig build inprocess-lib`) produces a static library from `inprocess_ffi.zig` + `zig_compiler` dependency; observable proof: successful build and documented output path / naming. |
| 1 | Stub + link | `inprocess_stub.zig` (or equivalent) calls `circ_inprocess_compile`; orchestrator compile path can call stub when selected; proof: link-only main module compiles when lib path is provided (may still use slow path by default in this phase). |
| 2 | Fast path in root build | Explicit option and/or `prebuilt/` detection wires `circ-compile` to **skip** `zig_compiler` `addImport` on the main module when the archive exists; `wasm_compiler_rt` / options wired so the stub path does not depend on the fat module graph; proof: `zig build circ-compile --summary` shows no full vendored compile on fast path; full `zig build test` passes. |
| 3 | Tooling, gitignore, CI | `tools/build-inprocess-lib.sh` (or Zig-native equivalent), `prebuilt/.gitignore`, contributor docs; CI builds or caches `libinprocess` before `circ-compile`; proof: clean CI with cache miss documented; no `*.a` in repository. |

Phases are ordered by dependency, not by priority. Each phase must be fully shippable before the next begins.

## Working Loop

The execution agent follows this loop every session without exception:

### On Cold Start

1. Read this file (`DOCS/PLANS_PROMPT.md`) in full.
2. Read `DOCS/STATUS.md` (if it exists). The latest entry defines what was last shipped and what comes next.
3. Run `git log --oneline -10` and `git status`. If STATUS claims a slice is committed but it does not appear in `git log`, the human has not committed yet — **do not begin a new slice**. Stop and say so.
4. Read the active phase plan (`DOCS/PLANS/PHASE_<N>_<name>.md`) for the current phase.
5. Implement the next slice per the phase plan. Do not start a second slice until the first is reviewed and committed.

### Each Slice

1. Implement the full slice as specified. Do not stop mid-slice.
2. Run the project's test command for the affected modules. Do not ship a slice that breaks the suite.
3. Append a STATUS entry (template below).
4. **Stop.** Wait for human review and commit before beginning the next slice.

### Git Rules

- Do **not** commit, push, or run any write `git` or `gh` command on the human's behalf.
- Read-only git commands (`status`, `log`, `diff`) are encouraged for situational awareness.

## STATUS Entry Template

Append to `DOCS/STATUS.md` at the end of every slice. Never overwrite or edit prior entries.

```
## YYYY-MM-DD — Phase N — <slice title>

**What shipped:** <one or two sentences>
**Files touched:** `<file>`, `<file>`
**Tests:** added <names>, ran `<command>`, result <pass/fail>
**Next slice:** <one sentence>
**Notes:** <anything the next session needs that isn't obvious from the code>
```

## Recurring Traps

- **`libinprocess` and `circ-compile` must be built with the same Zig patch** (0.15.1); upgrading either side without the other is undefined.
- **`std.fs.selfExePath`** in code linked into the archive resolves to the **final** executable when merged—verify behavior after linking, not only in the standalone lib test.
- **`std.Build.Cache.Path` / `compiler_rt` path:** absolute vs CWD-relative paths must match what `Compilation.create` expects; mirror proven behavior from `inprocess.zig`.
- **Logic duplication:** `inprocess.zig` vs `inprocess_ffi.zig` can drift; prefer shared helpers only if they remain on the **slow-path-only** side, or add tests that exercise **both** paths until unified.
- **Static linking on macOS:** watch for duplicate symbols or missing libc if the fat lib and exe both link runtime differently.
- **Do not commit `prebuilt/*.a`**; ensure `.gitignore` and code review catch accidental adds.
- **CI cache keys** must include inputs that invalidate the lib (e.g. hash of `inprocess_ffi.zig`, relevant `vendor/zig-compiler` paths, Zig version).
