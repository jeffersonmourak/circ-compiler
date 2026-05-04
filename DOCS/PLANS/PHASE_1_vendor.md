# Phase 1 — Vendor

> **Dependencies:** Phase 0 (Spike) must be complete and confirmed LLVM-free before vendoring begins.
> **Warnings:** The file set to vendor is derived from the spike's build cache — do not begin this phase until the spike has run successfully and `spike/zig-cache/` is populated. The vendored source must be pinned to the exact Zig commit used to build `circ-compile`, not just the minor version.

## Goal

A curated subset of the Zig 0.15.x compiler source — limited to the WASM output path — is checked into `vendor/zig-compiler/` and exposed as a named `build.zig` module. `circ-compile` links against this module and all existing tests pass. The `zig build` subprocess call is not replaced in this phase; the vendored symbols are linked but unused at runtime. A SHA256 manifest guards against accidental modification of vendored files.

## Scope

**In scope:**
- Enumerating the exact source files needed via the spike's build cache (`spike/zig-cache/`)
- Copying that curated file set into `vendor/zig-compiler/`
- Writing `vendor/zig-compiler/build.zig` that exposes the files as a module named `zig-compiler`
- Writing `vendor/zig-compiler/version.zig` with a pinned version constant
- Generating `vendor/zig-compiler/MANIFEST` (SHA256 per file)
- Wiring the `zig-compiler` module into the repo root `build.zig` so `circ-compile` links against it
- Confirming all existing tests pass

**Explicitly deferred:**
- Replacing the `zig build` subprocess call with an in-process API call (Phase 2)
- Any wrapper types or interface shims over the Zig compiler API
- A re-vendor script or automated upgrade tooling
- CI matrix / cross-platform verification (Phase 3)

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| vendor | `vendor/zig-compiler/build.zig` | Declares the `zig-compiler` module; exposes vendored source files for import |
| vendor | `vendor/zig-compiler/version.zig` | `pub const vendored_zig_version = "0.15.x-<commit-sha>";` — pinned version identifier |
| vendor | `vendor/zig-compiler/MANIFEST` | SHA256 checksum per vendored file; used to detect accidental modifications |
| vendor | `vendor/zig-compiler/<source files>` | Curated Zig compiler source (WASM path only), copied from spike build cache |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| repo root | `build.zig` | Wire in `vendor/zig-compiler/build.zig` as a dependency; add `zig-compiler` module to `circ-compile` link step |

**New dependencies:** None — all source is vendored in-repo; no new package manager entries.

## Data & State

No new runtime types or data structures are introduced. The only additions are build-time:

```zig
// vendor/zig-compiler/version.zig
pub const vendored_zig_version = "0.15.x-<commit-sha>";
```

The module name `zig-compiler` is the canonical import handle Phase 2 will use:

```zig
// Phase 2 will call this — not in scope for Phase 1
const Compilation = @import("zig-compiler").Compilation;
```

No interface shims or wrapper types. Phase 2 calls the Zig compiler's internal API directly.

## Execution & Concurrency Model

Not applicable. Phase 1 is a build-time change only. No new code executes at runtime — `circ-compile` continues to shell out to `zig build` as before. The vendored symbols are linked but never called.

## Persistence & I/O

- **`vendor/zig-compiler/MANIFEST`** — generated once during vendoring; one line per file: `<sha256>  <relative-path>`. Verified at the start of each test run via `sha256sum --check`.
- No runtime I/O changes. `circ-compile`'s behavior is identical to pre-Phase-1.
- No external APIs, network I/O, or database operations.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Enumerate and copy | Inspect `spike/zig-cache/` to identify compiler source files (WASM path only); copy them into `vendor/zig-compiler/`; generate `vendor/zig-compiler/MANIFEST` | `sha256sum --check vendor/zig-compiler/MANIFEST` exits 0 |
| 2 | Module definition | Write `vendor/zig-compiler/build.zig` (module named `zig-compiler`) and `vendor/zig-compiler/version.zig` (pinned version constant) | `zig build` inside `vendor/zig-compiler/` exits 0 with no errors |
| 3 | Wire into circ-compile | Update repo root `build.zig` to depend on `vendor/zig-compiler/build.zig` and link `zig-compiler` into `circ-compile`; confirm full test suite passes | `sha256sum --check vendor/zig-compiler/MANIFEST && zig build test` exits 0 |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| — | — | No new unit tests; correctness is proven by the existing suite passing after the module is linked |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| MANIFEST integrity | `vendor/zig-compiler/` | All vendored files match their recorded SHA256 checksums |
| Full test suite | repo root | All pre-existing `circ-compile` tests pass with the vendored module linked |

Run command: `sha256sum --check vendor/zig-compiler/MANIFEST && zig build test`

## Open Questions / Spikes

```
TODO(phase1): After enumerating the spike build cache, do a manual trim pass to confirm
              no build-host-only files (e.g. build runner machinery) were included.
              Only compiler source files needed at runtime should be vendored.

TODO(phase1): Record the exact Zig commit SHA in vendor/zig-compiler/version.zig once
              the Zig 0.15.x pinned version is confirmed. "0.15.x" is a placeholder.

TODO(phase1): Confirm the repo root build.zig API for adding a module dependency in
              Zig 0.15.x (b.addModule / b.dependency syntax may differ from 0.13.x).
```
