# Phase 0 — Project Scaffolding

## Goal

Stand up the test infrastructure and fixture layout that every later phase will depend on. After this phase, `zig build test` runs a working (initially empty) suite, and the convention for adding new tests + golden-file fixtures is fixed.

This phase produces no user-visible features. Its deliverable is the *workbench* that the rest of the project is built on. Skipping or rushing it makes every later phase harder.

## Scope

In scope:

- A `tests/` tree at the repo root organised by *artifact kind* (not by phase).
- A small Zig golden-file helper that compares produced output to a fixture file and supports a `--update-goldens` mode for regenerating expected output after intentional changes.
- A `zig build test` target that finds and runs every test in the project.
- A `tests/README.md` (short — under 50 lines) documenting the fixture layout and how to add tests, so subsequent phases follow the same convention.
- Sanity tests proving the helper itself works — `--update-goldens` rewrites the expected file, normal mode fails on mismatch and passes on match.

Out of scope:

- CI configuration. The user will set up GitHub Actions later; this phase only ensures `zig build test` is the canonical local command.
- Any test for actual project code. Phase 1 is the first phase that adds real engine tests.
- A WASM-runtime test runner. The Phase 4 behavioural tests will shell out to `node`; that wiring is set up in Phase 4 against this phase's helper, not pre-built here.
- Documentation beyond `tests/README.md`. The end-user README is a Phase 9 deliverable.

## Architectural anchors recap

- Fixtures are organised by *artifact kind*, not by phase. The same `.circ` source may be referenced from parser tests, validator tests, emission tests, and end-to-end tests.
- The golden-file helper is the foundation of every later phase's tests. Treat its API as stable from this phase forward — breaking it later means rewriting test fixtures across the codebase.

## Fixture layout

The directory structure below is fixed by this phase:

```
tests/
  README.md                     # how to add tests / fixtures
  helpers/
    golden.zig                  # golden-file comparison helper
    golden_test.zig             # sanity tests for the helper itself
  fixtures/
    circuits/                   # .circ source files (input)
    expected-zig/               # expected emitted Zig source (golden)
    expected-wasm/              # expected WASM behaviour fixtures (Phase 4+)
    expected-diagnostics/       # expected diagnostic output (Phase 3+)
```

`tests/fixtures/` directories under `expected-*/` may be empty in this phase — they exist so later phases drop new fixtures in without re-deciding the layout.

## Golden-file helper API

The helper exposes a single function that does the right thing in both modes:

```
fn expectGolden(
    actual: []const u8,
    fixture_path: []const u8,
) !void
```

Behaviour:

- If the env var `UPDATE_GOLDENS=1` (or a build flag of equivalent effect) is set, the helper writes `actual` to `fixture_path` and returns success. Creates the file if it doesn't exist.
- Otherwise, the helper reads `fixture_path` and compares it byte-for-byte to `actual`. On mismatch, the test fails with a diff (or at minimum, a clear "expected vs actual" message that points at the first divergent byte/line).
- If `fixture_path` doesn't exist and `UPDATE_GOLDENS` isn't set, the test fails with a message instructing the user to run with `UPDATE_GOLDENS=1` to create it.

The helper takes only these two arguments. Format-specific helpers (e.g. "compare with whitespace normalisation") are deferred — when a future phase needs them, it adds a wrapper.

## Slices

### Slice 0.1 — Build target + empty test suite

**What ships.** `build.zig` gains a `test` build step (`zig build test`) that discovers and runs every `test "..."` block in the project. Initially the suite is empty (no tests exist yet) and the command exits 0 with "all 0 tests passed."

**Tests.** None — there is nothing to test yet. The deliverable is verifiable by running `zig build test` and observing it succeed.

**Files touched.** `build.zig`.

**Why this slice exists alone.** The `build.zig` test step shape determines how every later test file is discovered. Getting it right (and proven to work on an empty suite) before any test exists prevents a "tests exist but aren't run" silent failure mode.

### Slice 0.2 — Fixture directory layout + README

**What ships.** The `tests/` directory tree as specified above, with empty subdirectories for each `expected-*/` category. A `tests/README.md` documenting:

- Where fixtures go (one paragraph per directory).
- How to add a new test (one paragraph).
- How `UPDATE_GOLDENS=1` works (one paragraph).
- The convention for fixture naming (`<feature>.circ` paired with `<feature>.zig`, `<feature>.diagnostics`, etc.).

`.gitkeep` (or similar) files in empty subdirectories so the layout survives in version control.

**Tests.** None — directories and docs are not tested.

**Files touched.** `tests/README.md`, `tests/fixtures/circuits/.gitkeep`, `tests/fixtures/expected-zig/.gitkeep`, `tests/fixtures/expected-wasm/.gitkeep`, `tests/fixtures/expected-diagnostics/.gitkeep`.

### Slice 0.3 — Golden-file helper implementation

**What ships.** `tests/helpers/golden.zig` exporting `expectGolden(actual, fixture_path)` per the API above. Implementation handles both compare and update modes, reads the env var (or flag) to decide which mode it's in, and produces useful failure messages.

**Tests.** `tests/helpers/golden_test.zig` covering:

- `expectGolden` with matching content passes.
- `expectGolden` with mismatching content fails with a message identifying the divergence.
- `expectGolden` with missing fixture and no update-mode fails with the "run with UPDATE_GOLDENS=1" hint.
- `expectGolden` in update mode writes the file and returns success.
- `expectGolden` in update mode overwrites an existing file.

These tests use a temp directory (`std.testing.tmpDir()` or equivalent) for fixture paths so they don't pollute the real `tests/fixtures/` tree.

**Files touched.** `tests/helpers/golden.zig`, `tests/helpers/golden_test.zig`, possibly `build.zig` if the test step needs to be told about the new directory.

## Definition of done for Phase 0

- `zig build test` runs and reports a passing suite.
- The `tests/` tree exists with all subdirectories from the layout spec.
- `tests/README.md` documents the conventions later phases will follow.
- `tests/helpers/golden.zig` is callable from any future test file via `@import("../helpers/golden.zig")` (or whatever the project's import path convention is — set it now).
- Running with `UPDATE_GOLDENS=1` regenerates fixtures; running without it compares.

## Open questions to resolve at slice time

- The exact mechanism for `UPDATE_GOLDENS` — env var read at runtime, or a Zig build option that sets a comptime flag. Env var is simpler (no build re-config to flip the mode); pick that unless there's a reason not to.
- The path-resolution convention for `fixture_path`. Two options: caller passes a path relative to the repo root (helper resolves via a known anchor), or caller passes an absolute path the test computed itself. Pick the first — the helper centralises path logic so test files stay terse.
- Whether to vendor a diff library for nicer mismatch messages or hand-roll a "first-diverging-line" report. Hand-roll for v0; "few dependencies" applies here too.

## Notes for the next phase

Phase 1 is the first phase to *use* the golden-file helper, but its tests are mostly straightforward `try testing.expectEqual(...)` — pass-through behaviour and snapshot bytes. The golden helper earns its keep starting in Phase 2 (AST dumps) and Phase 4 (emitted Zig source). Phase 1 still benefits from the `zig build test` infrastructure standing up here.
