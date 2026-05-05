# Phase 3 — Tooling, gitignore, CI

> **Dependencies:** Phase 2 — fast path in root build (`DOCS/PLANS/PHASE_2_fast_path.md`) complete and verified locally.
> **Warnings:** Do **not** commit `*.a` binaries. `.gitignore` + PR review discipline. Cache keys must include Zig version + relevant source hashes (`DOCS/PLANS_PROMPT.md` recurring traps).

## Goal

Contributors and CI have a **documented, repeatable** way to (1) build `libinprocess`, (2) place or cache it under `prebuilt/` (gitignored), (3) build `circ-compile` with the fast path, and (4) run the full test suite / E2E as required by project policy. A small **shell or Zig-native script** lives under `tools/` (name per implementation, e.g. `tools/build-inprocess-lib.sh`). GitHub Actions (or equivalent) **restores or builds** the prebuilt lib before linking `circ-compile` when using the fast job, with **cache keys** that invalidate correctly on vendor or FFI changes.

## Scope

**In scope:**

- `prebuilt/.gitignore` ignoring `*.a` and other emitted artifacts; optional `prebuilt/README.md` **only if** `DOCS/getting-started.md` or main README would become too long (prefer updating existing docs per project style).
- `tools/build-inprocess-lib.sh` (or `build-inprocess-lib.zig` run via `zig run`): invokes `zig build inprocess-lib`, copies/links artifact into `prebuilt/` with documented name.
- Update `.github/workflows/*.yml` (and Docker E2E if it builds `circ-compile`) so pipelines either build the lib first or restore cache; document **cold miss** behavior (expected time).
- Cross-link from `DOCS/PLANS_PROMPT.md` / `DOCS/getting-started.md` (or `README`) — minimal pointer: “fast builds: see …”.

**Explicitly deferred:**

- Release binaries / Git LFS for `libinprocess` (explicitly out of initiative per plan prompt).
- Windows CI runners unless already in matrix.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|----------------|
| Tooling | `tools/build-inprocess-lib.sh` | Wrap `zig build inprocess-lib`; copy to `prebuilt/`. |
| Repo hygiene | `prebuilt/.gitignore` | Ignore `*.a`, `*.lib`, temp files. |
| Docs | `DOCS/getting-started.md` or `README.md` | Short “Fast rebuild” subsection. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| CI | `.github/workflows/*.yml` | Cache + build order for `inprocess-lib` / fast `circ-compile`. |
| E2E | `tests/e2e/linux-docker/Dockerfile` or `run.sh` | If image builds `circ-compile`, ensure `inprocess-lib` runs first or cache is baked. |

**New dependencies:** None.

## Data & State

**Cache key inputs (document as list in workflow comments):**

- Zig version string (`zig version`).
- Hash or file-set: `lib/orchestrator/inprocess_ffi.zig`, `vendor/zig-compiler/` (narrow to `MANIFEST` or full tree per pragmatism).
- Target triple + optimize mode.

**Artifact layout (convention):**

```
prebuilt/
  .gitignore
  libinprocess.a   # present locally or in CI cache only; never committed
```

## Execution & Concurrency Model

Scripts and CI jobs are **sequential** within a job: `inprocess-lib` → copy → `circ-compile`. No in-process concurrency changes.

## Persistence & I/O

- **Filesystem:** Write under `prebuilt/` during dev/CI; read during `zig build circ-compile` fast path.
- **Network:** CI cache restore (GitHub `actions/cache` or similar); optional `zig fetch` unchanged.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | `prebuilt/.gitignore` | No accidental commits of binaries. | `git check-ignore -v prebuilt/libinprocess.a` works when file present. |
| 2 | Build script | One command builds + copies lib. | Maintainer runs script; `zig build circ-compile` fast path succeeds. |
| 3 | Docs | Getting started / README updated. | New contributor can follow steps without reading `build.zig`. |
| 4 | CI | Workflow green; cache hit/miss documented. | PR CI passes; optional follow-up issue for cache tuning only. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| — | — | None required beyond prior phases. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `zig build test` | Local + CI | Still passes on default configuration. |
| E2E Docker | `tests/e2e/linux-docker` | End-to-end still produces expected artifacts after workflow/Docker changes. |

Run command: `zig build test`; plus `bash tests/e2e/linux-docker/run.sh` (or CI equivalent) after Docker changes.

## Open Questions / Spikes

- **Docker image size / time:** If baking `libinprocess` into image, measure tradeoff vs building each CI run — `TODO(phase3):` pick per team tolerance.
- **musl vs glibc** on Linux CI if linking matters for static lib produced on different distro — spike only if link errors appear.
