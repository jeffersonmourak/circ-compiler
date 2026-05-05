# Phase 1 — Stub + link

> **Superseded (2026-05):** Stub / FFI link path was removed with the subprocess migration. See `DOCS/decisions/compiler-pipeline.md`. **Archival** spec only.

> **Dependencies:** Phase 0 — `inprocess-lib` build (`DOCS/PLANS/PHASE_0_inprocess_lib.md`) complete: `zig build inprocess-lib` produces `libinprocess.a` (or documented equivalent).
> **Warnings:** `std.fs.selfExePath` and allocator behavior must match production expectations when the stub is linked into the real `circ-compile` binary (see `DOCS/PLANS_PROMPT.md` recurring traps).

## Goal

The repository contains a **thin Zig module** (`inprocess_stub.zig` or agreed name) that:

1. Declares `extern fn circ_inprocess_compile(...) callconv(.C) c_int` (matching Phase 0).
2. Implements `pub fn compile(allocator, workspace_path, stderr_writer) !void` **or** the same surface as `lib/orchestrator/inprocess.zig`’s `compile` so `orchestrator_main` can swap imports without API churn.
3. Converts caller paths to sentinel C strings, calls the extern, maps non-zero to `error.ZigBuildFailed` (or existing error set).

Additionally, a **development-only** or **explicit-flag** path in `build.zig` links `circ_compile_exe` (or a duplicate test exe) against the **prebuilt** static library produced by Phase 0, proving the link succeeds. Default `circ-compile` behavior may still use the slow path (`inprocess.zig` + `zig_compiler` in-module) until Phase 2.

## Scope

**In scope:**

- New stub module + `build.zig` wiring: `linkLibrary` the static artifact when building the proof executable (path from Phase 0’s install/emitted output, or `b.path("prebuilt/libinprocess.a")` **optional** for local dev only — file may be absent on CI until Phase 3).
- `orchestrator_main.zig`: introduce an indirection so **either** `orchestrator_inprocess` resolves to stub or full module (comptime flag, separate import name, or thin `inprocess_facade.zig` — implementation choice documented in STATUS).
- Ensure `stderr_writer` parameter remains in the public API even if stub ignores it (diagnostics via stderr from compiler, consistent with today).

**Explicitly deferred:**

- Automatic detection of prebuilt vs source (Phase 2).
- CI script and cache (Phase 3).
- Removing `zig_compiler` from `circ_compile_mod` in the default configuration (Phase 2).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|----------------|
| Orchestrator | `lib/orchestrator/inprocess_stub.zig` | `@extern` + `compile()` wrapper; may `@import("build_options")` for `zig_lib_dir` / `wasm_compiler_rt` when built as main graph module. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| Orchestrator | `lib/orchestrator/main.zig` | Route compile through stub or inprocess based on chosen indirection (feature flag / module alias). |
| Build | `build.zig` | Optional test exe or gated `circ-compile` variant linking `libinprocess`; stub module + `addOptions` for paths used by stub. |

**New dependencies:** None.

## Data & State

**Stub public API (must mirror `inprocess.zig` for drop-in):**

```zig
pub fn compile(
    allocator: std.mem.Allocator,
    workspace_path: []const u8,
    stderr_writer: anytype,
) !void;
```

- **Implementation:** Duplicate workspace to absolute if needed; `allocator` may wrap thread-safe allocator for C/Zig boundary if the FFI uses `c_allocator` internally (document choice; prefer matching `inprocess.zig`’s TSA pattern if calling Zig code from stub before FFI).
- **FFI call:** Stack or arena buffers for `[*:0]const u8` arguments; `zig_lib_dir` / `compiler_rt` from `build_options` (Phase 1) until Phase 2 moves options to shared non-lazy wiring.

**Link-time symbol:** `circ_inprocess_compile` must be **undefined** in the stub object and **defined** in `libinprocess.a`.

## Execution & Concurrency Model

Fully **synchronous** from the orchestrator’s perspective: `compile` blocks until the FFI returns. Concurrency inside the vendored compiler unchanged. No new global `std.Progress` roots.

## Persistence & I/O

Same as today: workspace temp dirs, wasm output path, stderr for diagnostics. Stub adds **no** new files beyond existing orchestrator layout.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Stub module | `inprocess_stub.zig` compiles; implements `compile`. | `zig build` compiles modules that import stub (or dedicated test step). |
| 2 | Link proof | Executable or test binary links `libinprocess.a` + stub; calls into workspace compile path. | `zig build test` subset or new step `stub-link-smoke` exits 0 when `.a` present. |
| 3 | Orchestrator indirection | `main.zig` can select stub vs inprocess at build time (`-D` option). | Orchestrator tests pass for **slow** path default; optional job documents stub path. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| (optional) `inprocess stub forwards paths` | `tests/orchestrator/…` | If feasible without `.a`: mock skipped; else deferred to integration. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| Existing `inprocess_test.zig` | Slow path | Still passes when stub path disabled. |
| `orchestrator_main_test.zig` | Full pipeline | Still passes default configuration. |
| Stub link smoke | New step or CI-only | With `libinprocess.a` on disk, compile + link succeeds. |

Run command: `zig build test` (and any new step name documented in STATUS)

## Open Questions / Spikes

- **Single vs dual `compile` entrypoints:** Prefer one `orchestrator_inprocess` module whose **root file** is chosen by `build.zig` (`inprocess.zig` vs `inprocess_stub.zig`) to avoid import churn in `main.zig` — `TODO(phase1):` confirm with implementation agent.
