# Phase 1 — Shared Workspace

> **Dependencies:** Phase 0 (baseline timing numbers must exist in `DOCS/STATUS.md` before this phase can declare victory — the speedup is measured against them)
> **Warnings:** The only file changed is `tests/helpers/wasm_run.zig`. No test logic, fixture files, harness build, or build.zig entries change. If any test fails after this phase, the workspace implementation is the cause.

## Goal

After this phase, `zig build test` completes in under 60 seconds on a warm machine. The change is entirely inside `tests/helpers/wasm_run.zig`: `compileAndRun` replaces its per-call `std.testing.TmpDir` (a randomly-named directory with an empty `.zig-cache`) with a single persistent workspace at `.zig-cache/test-wasm-workspace`. Because the path is stable, Zig's content-addressed cache accumulates compiled engine objects across all 32 fixture calls. Every subsequent call only recompiles the changed `compiled.zig` and re-links. All existing test assertions pass unchanged.

## Scope

**In scope:**
- Replace `std.testing.TmpDir` usage in `compileAndRun` with a fixed workspace directory.
- Refactor `copyTextFile` to accept a `std.fs.Dir` instead of `*std.testing.TmpDir` (the signature change required by removing TmpDir).
- Verify all 32 WASM behavior fixtures pass (`zig build test` exits 0).
- Measure warm `zig build test` time and record it in `DOCS/STATUS.md` alongside the Phase 0 baseline.

**Explicitly deferred:**
- Batching multiple Node.js invocations into a single process (a further optimization, not required to hit the <60 s target).
- Pre-compiling engine sources into a static WASM object/archive (would reduce the first cold build; out of scope).
- Any parallelism of test binaries (sequentiality is a hard constraint for the shared workspace — see Concurrency Model).
- Changes to any test file other than `wasm_run.zig`.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|----------------|------|----------------|
| *(runtime artifact)* | `.zig-cache/test-wasm-workspace/` | Persistent build workspace; created at runtime by `compileAndRun`, never committed |

**Modified files:**

| Module/Package | File | Change |
|----------------|------|--------|
| Test helper | `tests/helpers/wasm_run.zig` | Replace `TmpDir` with fixed workspace path; refactor `copyTextFile` signature |
| Documentation | `DOCS/STATUS.md` | Append Phase 1 STATUS entry with before/after timing |

**New dependencies:** None

## Data & State

The workspace is a directory on the filesystem. Its layout after a build:

```
.zig-cache/test-wasm-workspace/
├── build.zig          ← copied from tests/harness/build.zig each call
├── compiled.zig       ← overwritten each call with the current fixture's emitted source
├── circuit.zig        ← copied from lib/ each call
├── memory.zig         ← copied from lib/ each call
├── transport.zig      ← copied from lib/ each call
├── log.zig            ← copied from lib/ each call
├── .zig-cache/        ← accumulated by zig build; persists across calls (the key optimization)
└── zig-out/
    └── bin/
        └── compiled.wasm  ← output; overwritten each call; read by Node before next call
```

The `compileAndRun` function signature is **unchanged**:

```zig
pub fn compileAndRun(
    allocator: std.mem.Allocator,
    emitted_source: []const u8,   // the compiled.zig source for this fixture
    script: []const u8,            // the Node.js driver script for this fixture
) ![]u8  // returns Node stdout (caller owns memory)
```

The internal `copyTextFile` helper changes its second parameter from `*std.testing.TmpDir` to `std.fs.Dir`:

```zig
// Before
fn copyTextFile(allocator, source_path, tmp: *std.testing.TmpDir, destination_name) !void

// After
fn copyTextFile(allocator, source_path, dest_dir: std.fs.Dir, destination_name) !void
```

The constant for the workspace path:

```zig
const WORKSPACE = ".zig-cache/test-wasm-workspace";
```

## Execution & Concurrency Model

This phase is fully synchronous within each test binary. No background threads or workers are introduced.

**Sequential safety guarantee:** In `build.zig`, every `run_*` test artifact is wired into `test_step` via `test_step.dependOn`. Zig's build runner executes these steps in dependency order, one at a time. `run_emit_behavior_tests` and `run_project_behavior_tests` are therefore never concurrent. Within a single binary, Zig's test runner executes tests sequentially by default.

Consequence: the shared workspace has exactly one writer at any moment. The `compiled.wasm` output at the fixed path is never overwritten while Node is reading it, because `std.process.Child.run` is synchronous — `compileAndRun` does not return until the Node process exits.

**If parallelism is ever introduced** (e.g., `--test-threads N` or parallel build steps), the workspace becomes unsafe. The "Recurring Traps" section of `DOCS/PLANS_PROMPT.md` documents this. No guard is added now; the sequential guarantee is sufficient.

## Persistence & I/O

**Workspace creation (once per run, idempotent):**
```
std.fs.cwd().makePath(WORKSPACE)
```
`makePath` succeeds whether or not the directory already exists.

**Per-call writes (each invocation of `compileAndRun`):**
1. Open `std.fs.Dir` handle to the workspace.
2. Write `compiled.zig` (overwrite).
3. Copy `tests/harness/build.zig` → `workspace/build.zig` (overwrite).
4. Copy `lib/circuit.zig`, `lib/memory.zig`, `lib/transport.zig`, `lib/log.zig` → workspace root (overwrite).
5. Spawn `zig build wasm -Doptimize=Debug` with `cwd = WORKSPACE`. Wait for exit.
6. Spawn `node tests/harness/loader.js {WORKSPACE}/zig-out/bin/compiled.wasm {encoded_script}` with `cwd = "."`. Wait for exit.
7. Return Node stdout.

**No cleanup.** The workspace and its `.zig-cache` persist indefinitely. This is intentional — cache persistence is the optimization. The directory is inside `.zig-cache/`, which is already gitignored and understood by developers as ephemeral build output.

**Error paths:** If `zig build wasm` exits non-zero, print stdout/stderr and return `error.SubprocessFailed` — same behaviour as before. If Node exits non-zero, same. The workspace is left in place (safe: Zig's cache tolerates partial builds).

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Rewrite `wasm_run.zig` | `compileAndRun` uses `WORKSPACE` constant instead of `TmpDir`; `copyTextFile` takes `std.fs.Dir`; workspace is created with `makePath`; no `defer tmp.cleanup()` | `zig build test` exits 0; warm run measured and recorded in `DOCS/STATUS.md` |

This phase is a single atomic slice: the code change and its verification are inseparable. Do not stop between writing the code and running the tests.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|-----------------|
| *(none new)* | — | No new unit tests; the existing behavior fixtures are the proof |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| All 13 fixtures in `behavior_test.zig` | `tests/emit/behavior_test.zig` | WASM compiles and produces correct signal outputs for single-file circuits |
| All 19 fixtures in `project_behavior_test.zig` | `tests/emit/project_behavior_test.zig` | WASM compiles and produces correct signal outputs for multi-file projects |

Run command: `zig build test`

After the run, record the warm wall-clock time in `DOCS/STATUS.md` and confirm it is below 60 seconds. If it is not below 60 seconds, investigate before closing the phase — possible causes are listed in Open Questions.

## Open Questions / Spikes

- **`makePath` vs `makeDir` API availability in Zig 0.15.** `std.fs.Dir.makePath` (or `std.fs.cwd().makePath`) creates intermediate directories and is idempotent. Verify the exact API name in the installed Zig version; the fallback is `makeDir` with an explicit `catch |e| if (e != error.PathAlreadyExists) return e`.
- **Warm time still above 60 s.** If the warm run remains slow, the most likely cause is that the workspace `.zig-cache` is being invalidated between calls. Check whether the engine file copy is writing identical bytes (it should — same source content) and whether the `build.zig` being copied is byte-for-byte identical. Zig's cache uses Blake3 hashes of file contents; if content is identical, objects are reused regardless of mtime.
- **`compiled.wasm` path on Windows.** The harness is not tested on Windows; path separator differences are out of scope but noted here for completeness.
