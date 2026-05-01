# Phase 6 — CLI Surface

## Goal

Wrap the orchestrator from Phase 5 in a user-facing command-line tool. After this phase, a user runs `circ-compile input.circ -o output.wasm` and gets a working WASM artifact, with full support for the three CLI modes, `--warnings-as-errors`, and `--build-dir`.

This is the first phase that produces a binary the user actually invokes. After this phase, the v0 single-file pipeline is *complete* end-to-end from a user's shell.

## Scope

In scope:

- A hand-rolled argument parser under `lib/cli/args.zig` — no third-party dependency.
- The `circ-compile` binary entry point at `cmd/circ-compile/main.zig`.
- Three modes: `-o <path>` (default — produce WASM), `--emit-zig -o <path>` (emit Zig source only), `--inspect` (dump parse tree + IR + diagnostics to stdout).
- The `--warnings-as-errors` (also `-Werror`) flag.
- The `--build-dir <path>` flag, plumbed through to the orchestrator.
- Diagnostic printing to stderr in the format produced by Phase 3 (`<file>:<line>:<col>: <level>: <code>: <message>`).
- Exit codes: 0 on success (with or without warnings), non-zero on hard errors or warnings-promoted-to-errors.
- Unit tests for the arg parser (synthesised `argv` arrays).
- Integration tests that invoke the compiled CLI binary as a subprocess and assert on stdout/stderr/exit-code/output files.

Out of scope:

- A `--help`/`-h` text beyond the minimum needed to not be hostile. Comprehensive help is a post-v0 polish item.
- TypeScript declaration emission (`.d.ts`). Per `decisions/cli.md`, deferred.
- Any color or terminal-detection logic. Diagnostics are plain text on stderr.
- Sub-circuit handling. Phase 7. The CLI today only handles single-file input.
- Built-in macros. Phase 8. The CLI today fails with `E001 undeclared_name` if the user references `or`/`nand`/etc.

## Architectural anchors recap

- Hand-rolled arg parser, no third-party dependency (Q9a, decision (i)).
- Binary name `circ-compile`, entry point at `cmd/circ-compile/main.zig` (Q9b confirmed).
- `--inspect` output uses textual sections with headers (`=== Parse Tree ===`, `=== Resolved IR ===`, `=== Diagnostics ===`), pretty-printed Zig style (Q9c, decision (iii)).
- Unit tests for arg parsing + integration tests for each mode (Q9d, decision (i)).
- Hard errors block emission; the CLI never calls the orchestrator if Phase 3 produced any hard error (or any warning when `--warnings-as-errors` is set).
- Exit 0 on success; non-zero on errors.

## CLI surface

```
circ-compile <input.circ> -o <output.wasm>          # default: produce WASM
circ-compile <input.circ> --emit-zig -o <output.zig> # emit IR Zig source only
circ-compile <input.circ> --inspect                  # dump parse tree / IR to stdout

Optional flags (any mode):
  --warnings-as-errors  (also -Werror)               # promote warnings to errors
  --build-dir <path>                                 # override the temp build directory
                                                     # (only meaningful in default mode)
```

Mode is mutually exclusive: `--emit-zig` and `--inspect` cannot be combined; `-o` is required for default and `--emit-zig` mode but ignored (or rejected) in `--inspect` mode.

## Argument parser shape

```zig
pub const Mode = enum { compile, emit_zig, inspect };

pub const Args = struct {
    input_path:           []const u8,
    mode:                 Mode,
    output_path:          ?[]const u8 = null,         // required for compile/emit_zig
    warnings_as_errors:   bool = false,
    build_dir:            ?[]const u8 = null,
};

pub const ParseError = error{
    MissingInput,
    MissingOutput,
    UnknownFlag,
    ConflictingModes,
    BuildDirInWrongMode,
    InvalidFlagValue,
};

pub fn parse(argv: []const []const u8) ParseError!Args;
```

The parser is a single function that walks `argv` once. No state machine, no help-text generation — just enough to populate `Args` or return a clear error.

## Pipeline driver

The CLI's `main()` function follows this flow:

```
1. Parse argv → Args, or print error to stderr and exit 2.
2. Read input_path. If file doesn't exist, print error and exit 2.
3. Run Phase 2 (parse → AST → IR).
4. Run Phase 3 (validate → DiagnosticList).
5. Print every diagnostic in DiagnosticList to stderr.
6. If any diagnostic is .error level (or any .warning when --warnings-as-errors is set),
   exit with code 1. Do not proceed.
7. Branch on mode:
   - .inspect:  print parse tree + IR + diagnostics summary to stdout. Exit 0.
   - .emit_zig: run Phase 4 (emit Zig source). Write to output_path. Exit 0.
   - .compile:  run Phase 4 (emit Zig source) → run Phase 5 (orchestrator).
                Orchestrator handles its own subprocess error reporting.
                Exit 0 on success, 1 on subprocess failure.
```

Exit codes:
- `0` — success (possibly with non-promoted warnings).
- `1` — semantic errors found in the source, or orchestrator failure.
- `2` — usage error (bad flags, missing input, etc.).

## `--inspect` output format

```
=== Parse Tree ===
<pretty-printed AST dump, same format as Phase 2's golden tests>

=== Resolved IR ===
<pretty-printed IR dump, same format as Phase 2's golden tests>

=== Diagnostics ===
<one diagnostic per line, same format as Phase 3's golden tests>
<empty line if no diagnostics>

=== Summary ===
<N> errors, <M> warnings
```

Sections are always present in the same order, even if empty (so scripts can rely on the layout). Exit 0 if no errors; exit 1 if errors are present (treating `--inspect` as a check tool when wired into CI).

Wait — that conflicts with "the CLI never calls the orchestrator if Phase 3 produced any hard error" (which would mean exit 1 *before* `--inspect` could print). For `--inspect`, the *behaviour* is "print the diagnostics anyway and let the user see what's wrong." So the rule for `--inspect` is: always print all sections, then exit 1 if errors are present, 0 otherwise. The "do not proceed" check from step 6 of the pipeline driver applies only to `compile` and `emit_zig`.

## Slices

### Slice 6.1 — Argument parser

**What ships.** `lib/cli/args.zig` implementing `Args`, `Mode`, `ParseError`, and `parse(argv)`. Hand-rolled, single-pass, no help-text generation.

**Tests.** Unit tests with synthesised `argv` arrays covering:

- `["circ-compile", "in.circ", "-o", "out.wasm"]` → `Args{ mode = compile, ... }`.
- `["circ-compile", "in.circ", "--emit-zig", "-o", "out.zig"]` → `Args{ mode = emit_zig, ... }`.
- `["circ-compile", "in.circ", "--inspect"]` → `Args{ mode = inspect, ... }`.
- `["circ-compile", "in.circ", "-o", "out.wasm", "--warnings-as-errors"]` and the `-Werror` alias.
- `["circ-compile", "in.circ", "-o", "out.wasm", "--build-dir", "/tmp/x"]`.
- Error cases: missing input, missing `-o` in compile mode, conflicting `--emit-zig --inspect`, unknown flag, `--build-dir` in `--emit-zig` mode (rejected with `BuildDirInWrongMode`).

**Files touched.** `lib/cli/args.zig`.

### Slice 6.2 — CLI entry point and pipeline driver

**What ships.** `cmd/circ-compile/main.zig` implementing the pipeline-driver flow above. Wires together arg parsing, file reading, Phase 2, Phase 3, Phase 4, Phase 5, and diagnostic printing. The CLI binary builds via `zig build` and lives at the conventional output path.

The `build.zig` at the repo root is updated to define a `circ-compile` executable target with `cmd/circ-compile/main.zig` as its entry. The existing `compiler` build target from earlier in the project's history is either renamed to `circ-compile` or removed in favor of the new one — pick at slice time.

**Tests.** No unit tests in this slice (the pipeline driver is mostly composition). Coverage comes from slice 6.3's integration tests.

**Files touched.** `cmd/circ-compile/main.zig`, `build.zig`.

### Slice 6.3 — Integration tests for default mode

**What ships.** Integration tests that invoke the compiled CLI binary via `std.process.Child` and assert on outputs:

- Happy path: `circ-compile fixture.circ -o /tmp/test.wasm` exits 0, produces a valid WASM file.
- Hard error: `circ-compile bad-fixture.circ -o /tmp/test.wasm` exits 1, prints `E001` (or whichever) to stderr, no output file.
- Warning (default): `circ-compile warn-fixture.circ -o /tmp/test.wasm` exits 0, prints `W001` to stderr, output file exists.
- Warning + `--warnings-as-errors`: exits 1, prints `W001`, no output file.
- Missing input file: exits 2, helpful error to stderr.
- Unknown flag: exits 2, helpful error to stderr.
- `--build-dir`: build dir is preserved, contains expected files.

**Files touched.** `tests/cli/integration_test.zig`, fixtures.

### Slice 6.4 — Integration tests for `--emit-zig` mode

**What ships.** Integration tests for `--emit-zig`:

- `circ-compile fixture.circ --emit-zig -o /tmp/out.zig` exits 0, produces a Zig file matching the Phase 4 golden fixture for that input.
- Hard error: exits 1, no output.
- `--build-dir` rejected in this mode: exits 2.

**Files touched.** `tests/cli/integration_test.zig` (additions), fixtures.

### Slice 6.5 — Integration tests for `--inspect` mode

**What ships.** Integration tests for `--inspect`:

- Clean fixture: `circ-compile fixture.circ --inspect` exits 0, stdout contains all four sections in order, diagnostics section is empty.
- Hard-error fixture: exits 1, stdout still contains all four sections, diagnostics section lists the error.
- `-o` flag rejected in this mode (or silently ignored — pick at slice time; recommendation: rejected, with `BuildDirInWrongMode`-style error... actually a different error code, `OutputInWrongMode`).

The stdout format is verified via golden-file comparison: a `tests/fixtures/expected-inspect/<name>.txt` file paired with each fixture, compared with the golden helper. Whitespace and section headers must match exactly.

**Files touched.** `tests/cli/integration_test.zig` (additions), `tests/fixtures/expected-inspect/<name>.txt`.

## Definition of done for Phase 6

- All five slices committed.
- `zig build test` passes.
- Running `zig build` produces a `circ-compile` binary at the conventional output location.
- The binary handles all three modes correctly with sensible exit codes.
- `--warnings-as-errors` promotes warnings; `--build-dir` overrides temp dir.
- Integration tests exercise the binary end-to-end, including subprocess invocation.
- The v0 single-file user pipeline is complete: a user can `circ-compile their.circ -o their.wasm` and get a working artifact.

## Open questions to resolve at slice time

- Whether `--inspect` rejects `-o` outright or silently ignores it. Recommendation: reject with a clear error. Silent ignore confuses users who think the file is being written.
- Whether the integration tests build the CLI binary themselves (via `std.Build` step dependencies) or assume `zig build` was run first. Recommendation: declare a build-step dependency so `zig build test` always builds the CLI before running integration tests.
- The exact wording of error messages for `MissingInput`, `MissingOutput`, etc. Pick clear, actionable wording at slice time and lock it in golden tests so it doesn't drift.
- Whether Phase 4's behavioural tests get rewired to use the CLI binary now that it exists, or whether they keep using the in-process harness. Recommendation: keep them on the in-process harness — they're faster, and the CLI's integration tests already cover the subprocess path.
- Whether the existing `lib/compiler.zig` (the WIP entry point from the project's earlier life) is deleted in this phase or retained. Recommendation: delete — the new `cmd/circ-compile/main.zig` supersedes it.

## Notes for the next phase

Phase 7 (sub-circuit support) does not change the CLI surface. It changes what Phase 2's resolver does (multi-file + import resolution) and what Phase 3 validates (import-cycle check). The CLI passes input files to the same Phase 2 → 3 → 4 → 5 pipeline; the pipeline handles imports internally. No CLI flags need to change for Phase 7.

Phase 8 (built-ins) similarly is invisible to the CLI — the resolver gains an implicit `<builtin>/` import, but the user-facing surface is unchanged. The CLI continues to take a single input file.

After Phase 6, the user-facing v0 product is functional for the simplest circuits. Phases 7, 8, 9 expand what circuits can do (sub-circuits, built-ins, hardening) without changing how the user invokes the compiler.
