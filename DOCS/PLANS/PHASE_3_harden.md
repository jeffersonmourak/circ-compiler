# Phase 3 — Harden

> **Dependencies:** Phase 2 (Integrate) must be complete — `circ-compile` must use the in-process compilation path before this phase begins. The binary must be self-contained with no runtime Zig dependency.
> **Warnings:** The stripped-PATH test is only meaningful if Phase 2's in-process path is fully wired. Running this workflow against a Phase 1 binary will always fail; running it against a Phase 2 binary that still falls back to subprocess will produce a misleading pass on machines where Zig happens to be installed outside PATH.

## Goal

A dedicated GitHub Actions workflow runs `circ-compile` end-to-end on macOS arm64 and Linux x86_64 runners with Zig stripped from PATH after the build step. The workflow passes on both platforms, proving the binary has no runtime Zig dependency. `DOCS/decisions/compiler-pipeline.md` is updated to record the revised decision (embedding viable, LLVM-free confirmed), and `DOCS/getting-started.md` no longer lists Zig as an installation prerequisite.

## Scope

**In scope:**
- `.github/workflows/e2e.yml` — new workflow, push/PR triggered, macOS arm64 + Linux x86_64 matrix
- Stripping Zig from PATH after the build step, before the end-to-end test
- Running `circ-compile tests/fixtures/circuits/inverter.circ -o out.wasm` and asserting exit 0 + valid WASM magic bytes
- Updating `DOCS/decisions/compiler-pipeline.md` to record the revised compiler-pipeline decision
- Updating `DOCS/getting-started.md` to remove the Zig installation prerequisite

**Explicitly deferred:**
- Windows matrix (not in the Phase 3 requirement; add separately if needed)
- Binary distribution or release automation changes
- Artifact upload on failure
- Cache seeding or Zig cache pre-warming for the e2e runner
- Performance benchmarking of the in-process path vs. the subprocess

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| CI | `.github/workflows/e2e.yml` | Push/PR-triggered workflow; builds `circ-compile`, strips Zig from PATH, runs end-to-end test on macOS arm64 and Linux x86_64 |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| docs | `DOCS/decisions/compiler-pipeline.md` | Record revised decision: embedding approach adopted, LLVM-free confirmed in Phase 0, Zig subprocess eliminated in Phase 2; note version-lock tradeoff |
| docs | `DOCS/getting-started.md` | Remove Zig installation prerequisite and any instructions that reference `zig` as a runtime dependency |

**New dependencies:** None.

## Data & State

Not applicable. Phase 3 introduces no new runtime types, interfaces, or data structures. The binary under test is the Phase 2 artifact unchanged.

## Execution & Concurrency Model

Not applicable. Phase 3 introduces no runtime code changes. GitHub Actions matrix jobs run in parallel by default — that is the CI platform's concern, not the application's.

## Persistence & I/O

- The e2e workflow writes `out.wasm` to the runner's working directory during the test step; it is not uploaded or retained after the job completes.
- No artifact uploads configured. The job log is sufficient for debugging failures.
- No external APIs, databases, or network I/O beyond GitHub Actions infrastructure.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | e2e workflow | `.github/workflows/e2e.yml` with build step, PATH-strip step, and end-to-end test step; macOS arm64 + Linux x86_64 matrix | Workflow file is valid YAML; CI passes on both matrix targets (or is reviewable locally via `act` if available) |
| 2 | Update decision doc | `DOCS/decisions/compiler-pipeline.md` updated to record the revised decision: embedding adopted, LLVM-free, version-lock tradeoff accepted | Doc accurately reflects the outcome of Phases 0–2; no stale references to the subprocess approach as the current path |
| 3 | Update getting-started | `DOCS/getting-started.md` updated to remove Zig installation prerequisite and any runtime `zig` references | No mention of Zig as a user-facing install requirement remains in the doc |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| — | — | Not applicable — Phase 3 has no new runtime code |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `e2e no-zig PATH — macOS arm64` | `.github/workflows/e2e.yml` | `circ-compile inverter.circ -o out.wasm` exits 0 and `out.wasm` begins with `\0asm` on a macOS arm64 runner with Zig stripped from PATH |
| `e2e no-zig PATH — Linux x86_64` | `.github/workflows/e2e.yml` | Same assertion on a Linux x86_64 runner |

Run command: workflow triggered automatically on push/PR; the relevant test step within the workflow is:

```bash
# Strip Zig from PATH
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v zig | tr '\n' ':')

# Confirm Zig is gone
if command -v zig &>/dev/null; then echo "::error::Zig still in PATH"; exit 1; fi

# Run end-to-end
./zig-out/bin/circ-compile tests/fixtures/circuits/inverter.circ -o out.wasm
xxd out.wasm | head -1 | grep -q "00 61 73 6d" || (echo "::error::Invalid WASM magic bytes"; exit 1)
```

## Open Questions / Spikes

```
TODO(phase3): Confirm the exact runner labels for macOS arm64 in GitHub Actions.
              As of 2026-05, `macos-latest` resolves to arm64 on GitHub-hosted runners,
              but verify this against the current GitHub Actions runner image docs before
              committing to a label.

TODO(phase3): Confirm that the stripped-PATH step does not accidentally remove other
              tools needed by the test step (e.g. xxd, grep). Test the PATH-strip
              command locally against the runner's default PATH before merging.

TODO(phase3): If the Zig cache (~/.cache/zig/) is present on the runner from the build
              step, confirm whether circ-compile's in-process Compilation.create() silently
              depends on it at runtime. If so, add a cache-clear step between build and
              test (per the cache-seeding TODO in Phase 2).
```
