# Phase 2 — Fast path in root build

> **Superseded (2026-05):** Prebuilt `libinprocess` / lazy `zig_compiler` graph is gone. **Archival** spec only; see `DOCS/decisions/compiler-pipeline.md`.

> **Dependencies:** Phase 0 (`inprocess-lib`), Phase 1 (stub + link proof). `build.zig` already uses `b.lazyDependency("zig_compiler", …)` in the current tree — this phase **refines** when that lazy dep activates vs when the stub + prebuilt archive path is used.
> **Warnings:** Changing lazy dependency behavior affects **install**, `circ-compile` step, and `test` step dependencies (`grep maybe_zig_compiler_dep build.zig`). Review all conditional blocks.

## Goal

When the **fast path** is enabled (concrete trigger to be implemented: e.g. `-Dcirc-prebuilt-inprocess` **and** `prebuilt/libinprocess.a` exists, or **file-detect alone** per team choice), **`circ-compile` is built without** adding `zig_compiler` as an `addImport` on `circ_compile_mod` or the orchestrator’s in-process module graph. `zig build circ-compile --summary all` shows the vendored compiler **not** compiled as part of the main exe graph (only `libinprocess` link line).

`wasm_compiler_rt` generation (`zig build-lib` for wasm32 `compiler_rt`) and `zig_lib_dir` options attach to the **stub module** / root options in a way that **does not** require resolving `lazyDependency("zig_compiler")` — so cold CI can run “small” steps first, then link.

Full **`zig build test`** and orchestrator behavior remain correct for both modes.

## Scope

**In scope:**

- User-visible option(s) in `build.zig` (`b.option`) and/or filesystem probe under `b.path("prebuilt/")` for `libinprocess.a` (name per Phase 0).
- Conditional module roots: `inprocess_mod` root = `inprocess_stub.zig` vs `inprocess.zig`; `circ_compile_mod` **no** `zig_compiler` import on fast path.
- `maybe_zig_compiler_dep` / `lazyDependency` logic: fast path must **not** need to fetch/compile vendor for the main exe; slow path unchanged.
- Ensure `test` step: inprocess tests that need full compiler either **skip** on fast-only CI configuration or still build slow-path test binary — `TODO(phase2):` document chosen policy (recommended: default `zig build test` still builds slow path for coverage unless `-Dfast-ci` explicitly set).

**Explicitly deferred:**

- Polished contributor script (Phase 3).
- GitHub Actions YAML details beyond what’s needed to keep main green.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|----------------|
| (optional) | `lib/orchestrator/inprocess_facade.zig` | If used: re-exports `compile` from correct backend; else omit. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| Build | `build.zig` | Options, `prebuilt/` detection, conditional `addImport`, `wasm_compiler_rt` step dependency ordering for stub-only graph, `installArtifact` / `circ-compile` step always usable when fast or slow produces an exe. |
| CLI | `cmd/circ-compile/main.zig` | Remove or `if` any **direct** `@import("zig_compiler")` (grep project); today may only be via orchestrator — keep single path. |

**New dependencies:** None.

## Data & State

**Build-time options (illustrative — exact names in implementation):**

```zig
const use_prebuilt_inprocess = b.option(
    bool,
    "circ-prebuilt-inprocess",
    "Link prebuilt libinprocess.a; skip vendored zig_compiler in main exe graph",
) orelse false;
```

- **Interaction with lazy dep:** When fast path on, `lazyDependency("zig_compiler")` should not be activated for `circ_compile_exe` / `inprocess_mod` main graph; `TODO(phase2):` if Zig’s lazy API requires explicit `false` branch, document pattern used.

**Runtime:** Unchanged user CLI; only **build** of `circ-compile` differs.

## Execution & Concurrency Model

Unchanged at runtime. Build graph parallelism: `wasm_compiler_rt` system command may run in parallel with other steps once it does not sit behind `zig_compiler` lazy resolution.

## Persistence & I/O

- **Read:** `prebuilt/libinprocess.a` from workspace (gitignored).
- **Write:** Same as today for tests and emitted wasm.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Option + detection | `b.option` + existence check wired. | `zig build` parses help / options without error. |
| 2 | Conditional imports | Fast path: no `zig_compiler` on `circ_compile_mod` / orchestrator chain. | `--summary` shows expected steps; `nm` on `circ-compile` optional spike. |
| 3 | wasm_rt for stub | `build_wasm_compiler_rt` + options reachable without lazy zig_compiler. | `zig build test` passes default; fast path build passes smoke. |
| 4 | Install / step hygiene | `zig build circ-compile` works in both modes. | Both configurations succeed on developer machine. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| (as needed) | build graph | N/A at unit level. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `zig build test` | Full suite | Pass with **default** (slow or hybrid) CI configuration. |
| `inprocess_test` / `main_test` | WASM output | Valid wasm / behavior unchanged. |
| Fast path smoke | Manual or CI job | With prebuilt present + flag, `circ-compile` builds and runs minimal compile fixture. |

Run command: `zig build test` and `zig build circ-compile -Dcirc-prebuilt-inprocess=true` (exact flags per final `build.zig`)

## Open Questions / Spikes

- **Default for local dev:** File-detect vs explicit `-D` — pick one and document (`TODO(phase2):` resolve in first slice).
- **`zig build test` vs fast path:** Whether CI runs two jobs (fast + full) or only full; avoid silently dropping inprocess coverage.
