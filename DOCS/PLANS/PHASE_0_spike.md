# Phase 0 — Spike

> **Dependencies:** None
> **Warnings:** If `Compilation.create()` for the WASM target pulls in LLVM symbols at link time, this phase is a hard stop — do not proceed to Phase 1. Document the failure in `DOCS/STATUS.md` and escalate.

## Goal

A standalone Zig binary at `spike/` calls the Zig self-hosted compiler's `Compilation.create()` in-process, targeting `wasm32-freestanding`, and writes a valid `.wasm` artifact to `spike/out/add.wasm`. The binary exits 0, the output file begins with the WASM magic bytes (`\0asm`), and a symbol inspection of the spike binary confirms no LLVM symbols are present. Success proves that the embedding approach is viable and LLVM-free; failure (LLVM symbols present or link failure) is an explicit hard stop documented in `DOCS/STATUS.md`.

## Scope

**In scope:**
- `spike/` directory with its own `build.zig` and `src/main.zig`
- Calling `Compilation.create()` in-process using the self-hosted WASM backend
- Compiling a hardcoded minimal Zig source (`pub export fn add(a: i32, b: i32) i32 { return a + b; }`) to WASM
- Writing output to `spike/out/add.wasm` (hardcoded path)
- Confirming LLVM-free linkage via symbol inspection
- Documenting findings (pass or hard-stop) in `DOCS/STATUS.md`

**Explicitly deferred:**
- Vendoring any Zig compiler source into the repo (Phase 1)
- Integration with `circ-compile` CLI (Phase 2)
- CI / cross-platform matrix (Phase 3)
- CLI argument parsing in the spike binary
- Crash-recovery or temp dir management

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| spike | `spike/build.zig` | Declares spike executable; resolves Zig lib dir via `b.graph.zig_lib_directory` at build time |
| spike | `spike/src/main.zig` | Calls `Compilation.create()`, drives compilation, writes `spike/out/add.wasm`, exits 0 |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| repo root | `.gitignore` | Add `spike/out/` |

**New dependencies:** None — spike references the system Zig installation's internal source via `b.graph.zig_lib_directory`; no new packages introduced.

## Data & State

The spike's configuration for `Compilation.create()` is constrained to:

- **Target:** `wasm32-freestanding`
- **Backend:** self-hosted (no LLVM)
- **Input:** hardcoded Zig source string — `pub export fn add(a: i32, b: i32) i32 { return a + b; }`
- **Output:** `spike/out/add.wasm`

The exact fields of the `Compilation.create()` config struct are Zig-0.15.x-specific and are to be determined during spike execution. Use `TODO(phase0):` markers in the source for any field whose correct value is unclear until the Zig compiler source is consulted.

```
TODO(phase0): document the final Compilation.create() config fields once spike succeeds,
so Phase 1 vendoring targets exactly the right API surface.
```

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines, threads, or workers are introduced by the spike binary. Execution is: start → call `Compilation.create()` → drive compilation to completion → write `spike/out/add.wasm` → exit 0. Any internal threading within the Zig compiler itself is not managed by the spike.

## Persistence & I/O

- **Input:** hardcoded Zig source (no file read)
- **Output:** `spike/out/add.wasm` written to a hardcoded path; `spike/out/` is gitignored
- **No external APIs, network I/O, or database operations**
- **No crash-recovery contract** — the spike is a one-shot dev tool; on failure it exits non-zero

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Scaffold spike | `spike/build.zig` + `spike/src/main.zig` that compiles and links cleanly against the system Zig lib dir (stub `main` that prints "spike ok" and exits 0) | `cd spike && zig build run` exits 0 and prints "spike ok" |
| 2 | Wire `Compilation.create()` | `main.zig` calls `Compilation.create()` targeting `wasm32-freestanding`, drives compilation, writes `spike/out/add.wasm` | `cd spike && zig build run` exits 0; `spike/out/add.wasm` exists; `xxd spike/out/add.wasm \| head -1` shows `00 61 73 6d` (WASM magic) |
| 3 | Validate and document | Symbol inspection confirms no LLVM symbols in spike binary; findings written to `DOCS/STATUS.md` | `nm spike/zig-out/bin/spike \| grep -i llvm` returns empty; `DOCS/STATUS.md` entry appended |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| — | — | No unit tests; spike is exploratory — correctness is validated by observable output |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| WASM magic bytes check | `spike/` | `spike/out/add.wasm` begins with `\0asm` (`00 61 73 6d`) |
| No LLVM symbols | `spike/` | `nm spike/zig-out/bin/spike \| grep -i llvm` is empty |
| Clean exit | `spike/` | `zig build run` in `spike/` exits with code 0 |

Run command: `cd spike && zig build run && xxd out/add.wasm | head -1 && nm zig-out/bin/spike | grep -i llvm || echo "LLVM-free confirmed"`

## Open Questions / Spikes

```
TODO(phase0): Determine the exact Compilation.create() config struct fields for Zig 0.15.x
              targeting wasm32-freestanding with the self-hosted backend. Consult
              src/Compilation.zig in the Zig source tree at the pinned version.

TODO(phase0): Confirm whether Compilation.create() requires a pre-seeded Zig cache
              (~/.cache/zig/) to locate builtin modules, or whether it is fully
              self-contained. Test on a machine with an empty cache.

TODO(phase0): Confirm the correct CPU feature flags for the wasm32-freestanding target
              to match what the current `zig build` subprocess uses in circ-compile.
```
