# Phase 0 — Parser Contract Pins (Go is the oracle)

> **Dependencies:** None (first phase of the libcirc initiative; see `DOCS/PLANS_PROMPT.md`). Runs on today's Go/cgo parser (`lib/parser/parser.a` via `lib/syntax/CParser.zig`) — that parser is the oracle every golden in this phase is generated from and hand-reviewed against.
> **Warnings:** (1) Phase 0 touches only `tests/`, `tests/fixtures/`, `lib/syntax` *tests* (none exist as separate files today — `translate.zig` has no inline tests, so nothing under `lib/syntax/` changes at all), and the test wiring in `build.zig`. Zero changes to `lib/grammar/proto-circ.peg`, `lib/syntax/translate.zig`, `lib/analyze/analyze.zig`, or `lib/cli/inspect_dump.zig` (that file is a *copy* of `ast_dump.zig` without widths, `lib/cli/inspect_dump.zig:74-116`; the `--inspect` text is frozen by `DOCS/decisions/cli.md` and `tests/fixtures/expected-inspect/*`, so it does **not** gain an `Errors` section). (2) Parser quirks are pinned, never fixed — every golden below records what the Go parser does today, including four behaviours the plan prompt describes inaccurately (see *Data & State*, "Oracle corrections"). (3) `UPDATE_GOLDENS=1 zig build test` regenerates **every** golden family in the fast suite (`tests/helpers/golden.zig:11-17` writes unconditionally), not only `expected-ast`; after each regeneration `git status --short tests/fixtures` must list only the files this phase names. (4) PR #79 (`memories`, worktree `../memories`, merge-base `78dfc3f`) also creates `DOCS/STATUS.md` and `DOCS/PLANS/*`; this phase creates the first `DOCS/STATUS.md` on this branch, so the archive-then-rebase order in the plan prompt's first Recurring Trap applies when #79 merges. **The plan prompt's claim that #79 touches nothing Phase 0 touches is wrong** (`git diff --stat 78dfc3f memories` in that worktree): it inserts two `fixtures` entries (`rom-basic`, `ram-basic`) mid-table after `anonymous-nested` in `tests/syntax/translate_test.zig:28`, adds `tests/fixtures/expected-ast/{rom_basic,ram_basic}.txt` (29 goldens post-merge, both **without** an `Errors (0)` line), adds 18 `tests/fixtures/circuits/*.circ`, inserts three lines into `tests/README.md` right after the `expected-diagnostics/` entry (`:15`), and changes `lib/analyze/analyze.zig` (+94: `addr_width` is emitted **only** for memory symbols, so the four `expected-analyze` goldens here — no memories — stay byte-identical) and `lib/resolver/scan_imports.zig:33` (reserved aliases gain `rom`/`ram`). After the rebase: run `UPDATE_GOLDENS=1 zig build test` once more, expect exactly `rom_basic.txt`/`ram_basic.txt` to gain `Errors (0)` and nothing else to move, and re-verify the four JSON goldens; the fixture-table count becomes 41 and the corpus 174 files. (5) `recovery_busvalue_eof.circ` must not end in a newline — editors add one silently, and the marks move from `2:9` to `3:1` when it happens; slice 2 adds a test that guards the byte.

## Goal

After this phase, the parser's observable contract is pinned on circ's side independently of langlang: every `expected-ast` golden ends with an `Errors (n)` section listing each `ast.File.errors` entry as `  Error "<message>" [f<id>:<sl>:<sc>-<el>:<ec>]` with the *raw* span (zero-width marks print as `[f0:2:9-2:9]`); twelve `tests/fixtures/circuits/recovery_*.circ` sources, generated through the Go parser and hand-reviewed line by line against the expectations in this document, pin the `ErrorMark` spans and messages of label recovery (`busname`/`busassign`/`busvalue`/`busclose`), `RecoverLine`, and the seven silent-drop/keyword-prefix/whitespace/byte-column quirks; four `tests/fixtures/expected-analyze/*.json` goldens pin the exact `--analyze` JSON (`analyze.renderJson`) that `circ-lsp` and the playground consume for the clean, truncated, junk-line and empty overlays from `lib/analyze/analyze.zig:452/:467/:576/:538`; and the misleading comment at `tests/syntax/translate_test.zig:286-292` states the real cause (auto-inserted Spacing before `BaseRef`'s failed `('.' Identifier)?`, not an ignored `#`). When Phase 1 swaps the parser, `zig build test` green plus `git diff --stat tests/fixtures` empty is the acceptance — no golden may move.

## Scope

**In scope:**
- `tests/helpers/ast_dump.zig::dumpFile` gains a trailing `Errors ({d})` section (after `Components`, `:152-155`), one line per `file.errors` entry, printed with the existing `writeSpan` (`:10-18`) so zero-width and multi-line spans are reproduced verbatim.
- Regeneration of the 27 existing `tests/fixtures/expected-ast/*.txt` goldens (27 table entries at `tests/syntax/translate_test.zig:12-148`, 27 files in the directory) — each diff is exactly `+Errors (0)` as the new last line.
- Twelve new recovery/quirk fixtures `tests/fixtures/circuits/recovery_<name>.circ` with `tests/fixtures/expected-ast/recovery_<name>.txt` goldens, appended to the `fixtures` table in `translate_test.zig`, plus three small inline translate tests (error-mark count on a clean and a truncated source; whitespace-only → `error.InvalidProgram`; the no-trailing-newline guard).
- `tests/analyze/analyze_golden_test.zig` + `tests/fixtures/expected-analyze/{clean,truncated,junk_line,empty}.json`, wired into `build.zig` as `analyze_golden_tests` next to `analyze_tests` (`build.zig:914-921`) and added to `test_step` (declared at `:967`; its first contiguous `dependOn` block is `:968-994`, and 59 `test_step.dependOn` lines in total run through `:1559`).
- The comment fix at `translate_test.zig:286-292` and the test's title.
- One line in `tests/README.md` listing `tests/fixtures/expected-analyze/` (inserted directly after the `expected-ast/` entry at `:11`, which keeps it clear of PR #79's hunk after `:15`).
- `DOCS/STATUS.md` entries per slice (the plan prompt's working loop), and running the fork's `go/zig/scripts/diff-circ.sh` over this checkout at the end (read-only for circ; its corpus glob `tests/fixtures/circuits/*.circ` at `diff-circ.sh:17` picks up the new fixtures automatically).

**Explicitly deferred:**
- Any change to `lib/syntax/translate.zig`, `lib/analyze/analyze.zig` (the `end_col <= start_col` widening at `:164-166` stays; the goldens record its output), `lib/cli/inspect_dump.zig`, the grammar, or `DOCS/analyze-api.md` (its stale "Behavior on invalid input" section, `:71-80`, is rewritten in Phase 2 per the Phase Index — against the post-#79 file, which #79 also edits).
- Fixing any quirk pinned here (keyword-prefix split, trailing-whitespace `BaseRef`, `import x ""` → path `"`, width literals > 255, `output o()` cascade, `Connection` lines vanishing). Each is a later grammar initiative (`edit .peg → zig build parser:gen → review goldens`).
- The corpus/mutation/fuzz machinery and an asm dump (dropped by the plan prompt; the fork's `TestGenZigDifferential` and `TestGenZigDifferentialCorpus` at `langlang/go/genzig_diff_test.go:167/:295` cover parity with node ids).
- Removing `linkParserArchive`/`linkLibC` from the new `analyze_golden_tests` artifact — Phase 1 does that; note for Phase 1: this phase raises the `linkParserArchive(b, …)` call count from 27 to 28 (`grep -c 'linkParserArchive(b, ' build.zig`; a bare `grep -c linkParserArchive` reads one higher because of the `fn` definition at `build.zig:9`) and the `tests/helpers/golden.zig` module creations from 13 to 14 (`grep -c 'tests/helpers/golden.zig' build.zig`). `golden.zig` itself needs no libc (`std.posix.getenv`, `golden.zig:4`); only `tests/helpers/golden_test.zig:5` `@cImport`s `setenv`/`unsetenv` (`build.zig:79-89`), so the new artifact's `.linkLibC()` exists solely for `CParser.zig`.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| fixtures | `tests/fixtures/circuits/recovery_busvalue_eof.circ` (16 B, **no trailing newline**) | `input a\nand g(a=` — `busvalue` then `busclose` throw at EOF; both marks zero-width at `2:9`; the component is dropped (`translate.zig:375-380` sees an Error node where `PortRef` is expected → `error.InvalidBusType` → `:696 catch {}`). Same text as the `analyze.zig:552` overlay. |
| fixtures | `tests/fixtures/circuits/recovery_busvalue_newline.circ` (17 B) | `input a\nand g(a=\n` — identical to the `analyze.zig:467` overlay; Spacing eats the newline before `PortRef` is tried, so both marks sit at `3:1`, one line *past* the declaration. The playground's squiggle lands there; pinned so nobody "fixes" the LSP client instead of the grammar. |
| fixtures | `tests/fixtures/circuits/recovery_busclose_midline.circ` (23 B) | `input a\nand g(a=a b=a)\n` (fork input `busclose_midline.circ`) — zero-width `busclose` at `2:11`, then `RecoverLine` over `b=a)`; `g` survives with one port whose `NamedRef` absorbs the trailing space (`[f0:2:9-2:11]`). |
| fixtures | `tests/fixtures/circuits/recovery_busclose_newline.circ` (37 B) | `input a\nand g(a=a\noutput o(in=g.out)\n` — `NamedRef a.out` spans `[f0:2:9-3:1]` (the newline is absorbed), the component spans `[f0:2:1-3:1]`, and the single `busclose` mark is at `3:1`; the following `output` still parses. |
| fixtures | `tests/fixtures/circuits/recovery_empty_ports.circ` (27 B) | `input a\noutput o()\nand g()\n` — the `busname` recovery eats `)`, the `busassign` recovery then eats the **entire next line** (`and g()`), and `busvalue`/`busclose` land zero-width at `4:1`; both declarations vanish. Four marks. |
| fixtures | `tests/fixtures/circuits/recovery_junk_line.circ` (56 B) | `input a\n%%% junk %%%\nand g(a=a, b=a)\noutput o(in=g.out)\n` (fork `recover.circ`, `analyze.zig:576`) — one `RecoverLine` mark `[f0:2:1-2:13]`, every declaration around it kept. |
| fixtures | `tests/fixtures/circuits/recovery_keyword_prefix.circ` (25 B) | `input a\nandx g(a=a, b=a)\n` — grammar line 13 has no word boundary: `and` + `IdentList` `x` (`translate.zig:622-631`), then `RecoverLine` over `g(a=a, b=a)` at `[f0:2:6-2:17]`. |
| fixtures | `tests/fixtures/circuits/recovery_connection_line.circ` (36 B) | `input a, b\na.out <> b.in\ng(a=a b=a)\n` — line 2 parses as `Connection` and is dropped without a mark (`translateTopLevel` `:686-697` ignores it); line 3 throws `busclose` *inside* `Connection → PortRef → BaseRef → AnonDecl → BusType`, the alternative then fails on `'.'`, and the discarded capture leaves **exactly one** `RecoverLine` mark `[f0:3:1-3:11]` — the backtracking trap from the plan prompt, pinned. |
| fixtures | `tests/fixtures/circuits/recovery_import_empty_path.circ` (35 B) | `import x ""\ninput a\noutput o(in=a)\n` — the import is **kept** with `path="` (child 3 of the `ImportDecl` sequence is the closing quote when the path is empty; `translate.zig:426-429`), `Errors (0)`. |
| fixtures | `tests/fixtures/circuits/recovery_width_overflow.circ` (62 B) | `input[300] a\ninput[255] b\nand[300] g(a=b)\noutput o(in=b[300])\n` — `parseInt(u8)` at `translate.zig:161` fails for 300 in all three positions (`WidthAnnot`, call width, `Subscript`), each declaration is dropped silently (`:694`, `:696`), `input[255] b` survives with `width=[255]`, `Errors (0)`. |
| fixtures | `tests/fixtures/circuits/recovery_multibyte_columns.circ` (57 B, UTF-8) | `input a // comentário ✓\nand ✓ g(a=a)\noutput o(in=a)\n` — line 2 is 14 bytes / 12 code points; the `RecoverLine` mark ends at byte column 15 (`[f0:2:1-2:15]`), proving `offsetToLineCol` (`translate.zig:48-61`) and langlang's charsets are byte-based. |
| fixtures | `tests/fixtures/circuits/recovery_trailing_ws_baseref.circ` (63 B) | `input a\noutput o1(in=a )\noutput o2(in=a [2])\nand g(a=a , b=a )\n` — `NamedRef` spans absorb trailing whitespace (`[f0:2:14-2:16]`, `[f0:4:9-4:11]`, `[f0:4:15-4:17]`) and `a [2]` is `Indexed bit=2`; the fixture that makes the corrected `translate_test.zig:286-292` comment checkable. |
| fixtures | `tests/fixtures/expected-ast/recovery_*.txt` (12 files) | Goldens; expected content listed verbatim under *Data & State*. |
| tests | `tests/analyze/analyze_golden_test.zig` | Table-driven test: build an `analyze.Overlay`, call `analyze.analyze(a, root, overlay)`, render with `analyze.renderJson` into an `ArrayList(u8)`, `golden.expectGolden(json, path)`. |
| fixtures | `tests/fixtures/expected-analyze/{clean,truncated,junk_line,empty}.json` | Exact single-line JSON + `\n` (renderJson ends with `"]}\n"`, `analyze.zig:441`); expected bytes under *Data & State*. |
| plans | `DOCS/PLANS/PHASE_0_parser_contract_pins.md` (this file), `DOCS/STATUS.md` (first entry) | Plan artifacts. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| tests/helpers | `tests/helpers/ast_dump.zig` | In `dumpFile` after the `Components` loop (`:152-155`) and before `return` (`:157`): `try writer.print("Errors ({d})\n", .{file.errors.len}); for (file.errors) |mark| { try writer.print("  Error \"{s}\" ", .{mark.message}); try writeSpan(writer, mark.span); try writer.writeByte('\n'); }`. No other output changes; `writeSpan` prints the raw span (no widening). |
| tests/syntax | `tests/syntax/translate_test.zig` | `fixtures` table (`:12-148`) gains 12 `recovery_*` entries (names `recovery-<name>`); new tests `errors: clean source has no marks`, `errors: truncated bus carries busvalue then busclose marks`, `edge: whitespace-only .circ is InvalidProgram`, `recovery: busvalue_eof fixture has no trailing newline`; test at `:286` renamed to `subscript: name [i] with space parses as indexed (Spacing before BaseRef's failed optional)` and its comment (`:287-292`) rewritten (text under *Data & State*). |
| fixtures | `tests/fixtures/expected-ast/*.txt` (27 files) | Regenerated: each gains the single trailing line `Errors (0)`. |
| build | `build.zig` | After `run_analyze_tests` (`:921`): create `analyze_golden_tests_mod` (root `tests/analyze/analyze_golden_test.zig`, imports `analyze` = `analyze_mod` from `:836`, `golden` = a fresh `createModule` over `tests/helpers/golden.zig` exactly as `:954-958`), `b.addTest(.{ .name = "analyze_golden_tests", .root_module = … })` — the one deviation from the template: every existing `addTest` leaves `name` at its default `"test"` (`std/Build.zig:857`), so without `.name` the step is not identifiable in `--summary all` — the two `addIncludePath` lines, `linkParserArchive(b, analyze_golden_tests, build_archive_cmd)`, `.linkLibC()` (needed today because `translate_mod` reaches `CParser.zig`'s `@cImport` of `parser/parser.h`, `translate_mod.addIncludePath` at `:101-102`), `addRunArtifact`; then `test_step.dependOn(&run_analyze_golden_tests.step);` immediately after `:978`. Template: the `validator_codes_snapshot_tests` block at `:941-966`. |
| tests | `tests/README.md` | Add `- tests/fixtures/expected-analyze/: expected --analyze JSON for in-memory overlays.` to the fixture-directory list (`:10-15`), directly after the `expected-ast/` line (`:11`). |

**New dependencies:** None. (The fork's `diff-circ.sh` cross-check runs in the langlang checkout with Go; it is a verification step, not a circ build dependency.)

## Data & State

### `Errors (n)` section — the only permitted `ast_dump` change

```zig
// tests/helpers/ast_dump.zig — appended inside dumpFile after the Components loop
try writer.print("Errors ({d})\n", .{file.errors.len});
for (file.errors) |mark| {
    try writer.print("  Error \"{s}\" ", .{mark.message});
    try writeSpan(writer, mark.span); // [f{d}:{d}:{d}-{d}:{d}], raw span, no widening
    try writer.writeByte('\n');
}
```

Format facts: two-space indent like every other entry line; the message is double-quoted with no escaping (all five messages, `translate.zig:641-648`, contain only `'` and ASCII); the span is `ast.ErrorMark.span` untouched (`lib/syntax/ast.zig:9-12`), so zero-width marks print as `[f0:2:9-2:9]` — `analyze.zig:164-166` widens those to `end_col = start_col + 1` for the JSON, which is why the analyze goldens show `2:9-2:10`/`3:1-3:2` where the AST goldens show `2:9-2:9`/`3:1-3:1`. Mark order is tree order (`collectErrorMarks`, `:654-672`, pre-order walk): in a `BusType`, `busname → busassign → busvalue → busclose`, and a `RecoverLine` on the same line follows the `busclose` mark.

### Oracle corrections (the goldens pin these; the plan prompt's wording is off)

Measured on `zig-out/bin/circ-compile` built from this branch (`3b84bcb`), via `--inspect` for the AST and `--analyze` with a `/virtual/…` overlay for the marks:

| Plan prompt says | Go parser does | Pinned by |
|---|---|---|
| "`import x ""` drops the import (`:427`)" | Kept: `Import alias=x path="` — with an empty path the `ImportDecl` sequence is `['import', Identifier, '"', '"']` (4 children), so `seq_len < 4` is false and child 3 is the closing quote. `--analyze` then reports `E009 import not found '"'`. | `recovery_import_empty_path` |
| "`output o()` drops the output (`:582`)" | Worse: `busname`'s recovery eats `)`, `busassign`'s recovery eats the whole **next** line, `busvalue`/`busclose` land at the following line start; both declarations vanish. | `recovery_empty_ports` |
| Truncated bus marks "at the stall point" | With a trailing newline the marks are at `3:1` (newline eaten by Spacing before `PortRef`); without one they are at `2:9`. | `recovery_busvalue_newline`, `recovery_busvalue_eof`, `expected-analyze/truncated.json` |
| `BaseRef` absorbs trailing *whitespace* | Including the newline: `NamedRef a.out [f0:2:9-3:1]` when `)` is missing at end of line. | `recovery_busclose_newline` |

### Expected `expected-ast/recovery_*.txt` contents (hand-review checklist)

Each block is the whole file; every line ends with `\n`. Deviations after `UPDATE_GOLDENS=1` are a finding, not something to accept silently.

`recovery_busvalue_eof.txt`
```
File [f0:1:1-2:9]
Imports (0)
Inputs (1)
  Input a [f0:1:1-1:8]
Outputs (0)
Components (0)
Errors (2)
  Error "expected a signal reference after '='" [f0:2:9-2:9]
  Error "expected ')' to close the connection list" [f0:2:9-2:9]
```

`recovery_busvalue_newline.txt`
```
File [f0:1:1-3:1]
Imports (0)
Inputs (1)
  Input a [f0:1:1-1:8]
Outputs (0)
Components (0)
Errors (2)
  Error "expected a signal reference after '='" [f0:3:1-3:1]
  Error "expected ')' to close the connection list" [f0:3:1-3:1]
```

`recovery_busclose_midline.txt`
```
File [f0:1:1-3:1]
Imports (0)
Inputs (1)
  Input a [f0:1:1-1:8]
Outputs (0)
Components (1)
  Component type=and instance=g [f0:2:1-2:11]
    Port a [f0:2:7-2:8]
      NamedRef a.out [f0:2:9-2:11]
Errors (2)
  Error "expected ')' to close the connection list" [f0:2:11-2:11]
  Error "unexpected input; expected a declaration" [f0:2:11-2:15]
```

`recovery_busclose_newline.txt`
```
File [f0:1:1-4:1]
Imports (0)
Inputs (1)
  Input a [f0:1:1-1:8]
Outputs (1)
  Output o [f0:3:1-3:19]
    NamedRef g.out [f0:3:13-3:18]
Components (1)
  Component type=and instance=g [f0:2:1-3:1]
    Port a [f0:2:7-2:8]
      NamedRef a.out [f0:2:9-3:1]
Errors (1)
  Error "expected ')' to close the connection list" [f0:3:1-3:1]
```

`recovery_empty_ports.txt`
```
File [f0:1:1-4:1]
Imports (0)
Inputs (1)
  Input a [f0:1:1-1:8]
Outputs (0)
Components (0)
Errors (4)
  Error "expected a port name" [f0:2:10-2:11]
  Error "expected '=' after the port name" [f0:3:1-3:8]
  Error "expected a signal reference after '='" [f0:4:1-4:1]
  Error "expected ')' to close the connection list" [f0:4:1-4:1]
```

`recovery_junk_line.txt`
```
File [f0:1:1-5:1]
Imports (0)
Inputs (1)
  Input a [f0:1:1-1:8]
Outputs (1)
  Output o [f0:4:1-4:19]
    NamedRef g.out [f0:4:13-4:18]
Components (1)
  Component type=and instance=g [f0:3:1-3:16]
    Port a [f0:3:7-3:8]
      NamedRef a.out [f0:3:9-3:10]
    Port b [f0:3:12-3:13]
      NamedRef a.out [f0:3:14-3:15]
Errors (1)
  Error "unexpected input; expected a declaration" [f0:2:1-2:13]
```

`recovery_keyword_prefix.txt`
```
File [f0:1:1-3:1]
Imports (0)
Inputs (1)
  Input a [f0:1:1-1:8]
Outputs (0)
Components (1)
  Component type=and instance=x [f0:2:1-2:5]
Errors (1)
  Error "unexpected input; expected a declaration" [f0:2:6-2:17]
```

`recovery_connection_line.txt`
```
File [f0:1:1-4:1]
Imports (0)
Inputs (1)
  Input a, b [f0:1:1-1:11]
Outputs (0)
Components (0)
Errors (1)
  Error "unexpected input; expected a declaration" [f0:3:1-3:11]
```

`recovery_import_empty_path.txt`
```
File [f0:1:1-4:1]
Imports (1)
  Import alias=x path=" [f0:1:1-1:12]
Inputs (1)
  Input a [f0:2:1-2:8]
Outputs (1)
  Output o [f0:3:1-3:15]
    NamedRef a.out [f0:3:13-3:14]
Components (0)
Errors (0)
```

`recovery_width_overflow.txt`
```
File [f0:1:1-5:1]
Imports (0)
Inputs (1)
  Input b width=[255] [f0:2:1-2:13]
Outputs (0)
Components (0)
Errors (0)
```

`recovery_multibyte_columns.txt`
```
File [f0:1:1-4:1]
Imports (0)
Inputs (1)
  Input a [f0:1:1-1:8]
Outputs (1)
  Output o [f0:3:1-3:15]
    NamedRef a.out [f0:3:13-3:14]
Components (0)
Errors (1)
  Error "unexpected input; expected a declaration" [f0:2:1-2:15]
```

`recovery_trailing_ws_baseref.txt` (the `Indexed` span is the `Subscript` node span, `translate.zig:306`; `--inspect`'s dump omits it, but `lib/ir/resolver.zig:222` passes that same `idx.span` to `synthesizeSlice`, which stores it as the slice component's span (`:145`), and the oracle's `--analyze` reports `E002 3:16-3:19 slice range [2..3) exceeds source width 1` plus a reference with range `3:16-3:19` on that construct — so `[f0:3:16-3:19]` is measured, not inferred)
```
File [f0:1:1-5:1]
Imports (0)
Inputs (1)
  Input a [f0:1:1-1:8]
Outputs (2)
  Output o1 [f0:2:1-2:17]
    NamedRef a.out [f0:2:14-2:16]
  Output o2 [f0:3:1-3:20]
    Indexed bit=2 [f0:3:16-3:19]
      NamedRef a.out [f0:3:14-3:16]
Components (1)
  Component type=and instance=g [f0:4:1-4:18]
    Port a [f0:4:7-4:8]
      NamedRef a.out [f0:4:9-4:11]
    Port b [f0:4:13-4:14]
      NamedRef a.out [f0:4:15-4:17]
Errors (0)
```

### Existing goldens

All 27 files (`and_two_inputs`, `anonymous_nested`, `empty_ish`, `multi_output`, `multibit_{and,input,led,not,output,wire}`, `param_{callsite_ident,callsite_multi,callsite_single,input_multi,input_single,used_as_width,whitespace}`, `portref_{compose,concat_mixed,concat_nested,concat_simple,concat_whitespace,index,slice}`, `width_edges`, `width_whitespace`, `with_import`) already end with `\n` after `Components`/last component line (audited with `tail -c 1`), so the regenerated diff for each is exactly one added line `Errors (0)` and `git diff --stat tests/fixtures/expected-ast` reads `27 files changed, 27 insertions(+)`.

### Analyze golden test

```zig
// tests/analyze/analyze_golden_test.zig
const std = @import("std");
const analyze = @import("analyze");
const golden = @import("golden");

const Case = struct {
    name: []const u8,
    overlay_path: []const u8, // absolute-looking, never on disk → file_loader.zig:44-47 falls back to the key
    source: []const u8,       // verbatim copy of the analyze.zig inline-test overlay it mirrors
    expected_json_path: []const u8,
};

const cases = [_]Case{
    .{ .name = "clean",     .overlay_path = "/virtual/clean.circ",     .source = "input a\ninput b\nand g(a=a, b=b)\noutput out(in=g.out)\n",              .expected_json_path = "tests/fixtures/expected-analyze/clean.json" },     // analyze.zig:452
    .{ .name = "truncated", .overlay_path = "/virtual/truncated.circ", .source = "input a\nand g(a=\n",                                                      .expected_json_path = "tests/fixtures/expected-analyze/truncated.json" }, // analyze.zig:467
    .{ .name = "junk_line", .overlay_path = "/virtual/junk_line.circ", .source = "input a\n%%% junk %%%\nand g(a=a, b=a)\noutput o(in=g.out)\n",            .expected_json_path = "tests/fixtures/expected-analyze/junk_line.json" }, // analyze.zig:576
    .{ .name = "empty",     .overlay_path = "/virtual/empty.circ",     .source = "",                                                                          .expected_json_path = "tests/fixtures/expected-analyze/empty.json" },     // analyze.zig:538
};

test "analyze json goldens for the lsp overlays" {
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var overlay = analyze.Overlay{};
        try overlay.put(a, case.overlay_path, case.source);
        const result = try analyze.analyze(a, case.overlay_path, overlay);
        var out: std.ArrayList(u8) = .{};
        try analyze.renderJson(out.writer(a), result);
        golden.expectGolden(out.items, case.expected_json_path) catch |err| {
            std.debug.print("Analyze golden failed: {s}\n", .{case.name});
            return err;
        };
    }
}
```

The `files` array is machine-independent: `files[0].path` is the overlay key (realpath of `/virtual/…` fails with `FileNotFound` and `file_loader.zig:44-47` keeps the given path), and the five `<builtin>/…` entries are the implicit macro imports appended by `scan_imports.zig:234-263`. Expected bytes (each file is this line plus one `\n`; sizes 1320 / 959 / 1387 / 101 bytes):

`clean.json`
```
{"files":[{"file_id":0,"path":"/virtual/clean.circ"},{"file_id":1,"path":"<builtin>/or.circ"},{"file_id":2,"path":"<builtin>/nand.circ"},{"file_id":3,"path":"<builtin>/nor.circ"},{"file_id":4,"path":"<builtin>/xor.circ"},{"file_id":5,"path":"<builtin>/xnor.circ"}],"diagnostics":[],"symbols":[{"file_id":0,"name":"a","kind":"input","width":1,"range":{"start_line":1,"start_col":7,"end_line":1,"end_col":8}},{"file_id":0,"name":"b","kind":"input","width":1,"range":{"start_line":2,"start_col":7,"end_line":2,"end_col":8}},{"file_id":0,"name":"out","kind":"output","width":1,"range":{"start_line":4,"start_col":1,"end_line":4,"end_col":21}},{"file_id":0,"name":"g","kind":"and","width":1,"range":{"start_line":3,"start_col":1,"end_line":3,"end_col":16}}],"references":[{"file_id":0,"range":{"start_line":3,"start_col":7,"end_line":3,"end_col":8},"target_file":0,"target_range":{"start_line":1,"start_col":1,"end_line":1,"end_col":8},"hover":"input a"},{"file_id":0,"range":{"start_line":3,"start_col":12,"end_line":3,"end_col":13},"target_file":0,"target_range":{"start_line":2,"start_col":1,"end_line":2,"end_col":8},"hover":"input b"},{"file_id":0,"range":{"start_line":4,"start_col":1,"end_line":4,"end_col":21},"target_file":0,"target_range":{"start_line":3,"start_col":1,"end_line":3,"end_col":16},"hover":"and g"}]}
```

`truncated.json` (note the `W001` *before* the two `syntax` entries — `appendSyntaxDiags` runs last, `analyze.zig:217-222` — and the widened `3:1-3:2` ranges)
```
{"files":[{"file_id":0,"path":"/virtual/truncated.circ"},{"file_id":1,"path":"<builtin>/or.circ"},{"file_id":2,"path":"<builtin>/nand.circ"},{"file_id":3,"path":"<builtin>/nor.circ"},{"file_id":4,"path":"<builtin>/xor.circ"},{"file_id":5,"path":"<builtin>/xnor.circ"}],"diagnostics":[{"file_id":0,"severity":"warning","code":"W001","range":{"start_line":1,"start_col":7,"end_line":1,"end_col":8},"message":"input 'a' is declared but never used","related":[]},{"file_id":0,"severity":"error","code":"syntax","range":{"start_line":3,"start_col":1,"end_line":3,"end_col":2},"message":"expected a signal reference after '='","related":[]},{"file_id":0,"severity":"error","code":"syntax","range":{"start_line":3,"start_col":1,"end_line":3,"end_col":2},"message":"expected ')' to close the connection list","related":[]}],"symbols":[{"file_id":0,"name":"a","kind":"input","width":1,"range":{"start_line":1,"start_col":7,"end_line":1,"end_col":8}}],"references":[]}
```

`junk_line.json`
```
{"files":[{"file_id":0,"path":"/virtual/junk_line.circ"},{"file_id":1,"path":"<builtin>/or.circ"},{"file_id":2,"path":"<builtin>/nand.circ"},{"file_id":3,"path":"<builtin>/nor.circ"},{"file_id":4,"path":"<builtin>/xor.circ"},{"file_id":5,"path":"<builtin>/xnor.circ"}],"diagnostics":[{"file_id":0,"severity":"error","code":"syntax","range":{"start_line":2,"start_col":1,"end_line":2,"end_col":13},"message":"unexpected input; expected a declaration","related":[]}],"symbols":[{"file_id":0,"name":"a","kind":"input","width":1,"range":{"start_line":1,"start_col":7,"end_line":1,"end_col":8}},{"file_id":0,"name":"o","kind":"output","width":1,"range":{"start_line":4,"start_col":1,"end_line":4,"end_col":19}},{"file_id":0,"name":"g","kind":"and","width":1,"range":{"start_line":3,"start_col":1,"end_line":3,"end_col":16}}],"references":[{"file_id":0,"range":{"start_line":3,"start_col":7,"end_line":3,"end_col":8},"target_file":0,"target_range":{"start_line":1,"start_col":1,"end_line":1,"end_col":8},"hover":"input a"},{"file_id":0,"range":{"start_line":3,"start_col":12,"end_line":3,"end_col":13},"target_file":0,"target_range":{"start_line":1,"start_col":1,"end_line":1,"end_col":8},"hover":"input a"},{"file_id":0,"range":{"start_line":4,"start_col":1,"end_line":4,"end_col":19},"target_file":0,"target_range":{"start_line":3,"start_col":1,"end_line":3,"end_col":16},"hover":"and g"}]}
```

`empty.json` (no builtins: the root's parse fails, `scan_imports.zig:141 catch continue`, so the implicit-import loop never runs; `analyze.zig:142` skips the syntax pass)
```
{"files":[{"file_id":0,"path":"/virtual/empty.circ"}],"diagnostics":[],"symbols":[],"references":[]}
```

### New inline translate tests

```zig
test "errors: clean source has no marks" {
    // "input a\noutput o(in=a)\n" → parsed.errors.len == 0
}
test "errors: truncated bus carries busvalue then busclose marks" {
    // "input a\nand g(a=" → errors.len == 2; [0].message == "expected a signal reference after '='",
    // [1].message == "expected ')' to close the connection list"; both spans start_line 2, start_col 9, end_col 9
}
test "edge: whitespace-only .circ is InvalidProgram" {
    // "\n  \n" → expectError(error.InvalidProgram, parseSource(...)); translate.zig:720-723 (root payload is a String)
}
test "recovery: busvalue_eof fixture has no trailing newline" {
    // read tests/fixtures/circuits/recovery_busvalue_eof.circ; expect source[source.len - 1] == '='
}
```

### Corrected comment at `translate_test.zig:286-292`

```zig
test "subscript: name [i] with space parses as indexed (Spacing before BaseRef's failed optional)" {
    // `IndexedRef <- BaseRef #Subscript?` was written expecting `#` to forbid
    // whitespace before the subscript. langlang v0.0.12 inserts Spacing between
    // every sequence element; `BaseRef`'s `('.' Identifier)?` consumes that
    // Spacing, fails on `[`, and the failed optional does not rewind it — the
    // BaseRef span absorbs the trailing whitespace (expected-ast
    // recovery_trailing_ws_baseref.txt: `NamedRef a.out [f0:3:14-3:16]`) and
    // `Subscript?` then matches `[2]` directly. `#` is not what is ignored;
    // pinned as a parser quirk, fixable only by a grammar change + parser:gen.
```

## Execution & Concurrency Model

This phase is fully synchronous. No background threads or workers are introduced. Each test artifact runs its fixture table in a single thread; `golden.expectGolden` reads and writes fixtures inline. The only process spawning is what `zig build test` already does (per-artifact test binaries; `tests/cli/integration_test.zig:41-49` runs a nested `zig build circ-compile`, untouched).

## Persistence & I/O

Fixture reads are relative to the process cwd (`std.fs.cwd().readFileAlloc(…, "tests/fixtures/…")`, `translate_test.zig:156`; `golden.zig:19-23`), so every test command runs from the repo root. `UPDATE_GOLDENS=1` makes `expectGolden` write instead of compare (`golden.zig:11-17`) and `makePath`s the parent (`:9`), which is how `tests/fixtures/expected-analyze/` comes into existence on the first regeneration. No other filesystem, network, or external process I/O. Verification-only I/O outside circ: the fork's `go/zig/scripts/diff-circ.sh` reads this checkout's grammar, `tests/fixtures/circuits/*.circ`, and `lib/parser/parser.go` (`diff-circ.sh:15-19`) and writes nothing here.

### Golden regeneration procedure (used by slices 1–4)

1. From the repo root: `UPDATE_GOLDENS=1 zig build test` (never `test-all` — `test-emit` spawns nested wasm builds and rewrites nothing relevant).
2. `git status --short tests/fixtures` — only the files the slice names may appear. Any change under `truth_table/`, `preview/`, `expected-diagnostics/`, `expected-ir/`, `expected-wasm/`, `expected-zig/`, `expected-inspect/` means a regeneration side effect: `git checkout -- <path>` those and investigate before continuing.
3. `git diff tests/fixtures/expected-ast` (slice 1: every hunk is `+Errors (0)` as the new last line; `git diff --stat` = `27 files changed, 27 insertions(+)`).
4. For each new golden, compare against the expected block in this document line by line; explain any difference from the oracle (`zig-out/bin/circ-compile <fixture> --inspect` for the AST half; `printf '%s\n' '{"root_path":"/virtual/x.circ","overlays":{"/virtual/x.circ":"<source>"}}' | zig-out/bin/circ-compile --analyze` for the marks, remembering the JSON widens zero-width spans).
5. `zig build test` without the variable — green.
6. Stage by path (`git add tests/… build.zig DOCS/STATUS.md`), propose the commit message, wait.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | `Errors (n)` section in the AST dump | `tests/helpers/ast_dump.zig::dumpFile` gains the trailing `Errors ({d})` block; 27 goldens regenerated; `translate_test.zig` gains `errors: clean source has no marks` and `errors: truncated bus carries busvalue then busclose marks` (the latter proves the section prints `[f0:2:9-2:9]` unwidened without waiting for slice 2's fixtures). Commit: `test(syntax): dump recovered error marks in the ast golden`. | `zig build test` green; `git diff --stat tests/fixtures/expected-ast` = `27 files changed, 27 insertions(+)` and `git diff tests/fixtures/expected-ast | grep '^+' | grep -v '^+++' | sort -u` prints exactly `+Errors (0)`; `git status --short` shows nothing else under `tests/fixtures`; `tests/fixtures/expected-inspect/*.txt` untouched (the CLI copy of the dump is not modified). |
| 2 | Label-recovery fixtures | Five fixtures + goldens: `recovery_busvalue_eof` (no trailing newline), `recovery_busvalue_newline`, `recovery_busclose_midline`, `recovery_busclose_newline`, `recovery_empty_ports`; table entries in `translate_test.zig`; new tests `recovery: busvalue_eof fixture has no trailing newline` and `edge: whitespace-only .circ is InvalidProgram`. Commit: `test(syntax): pin label-recovery error marks with go-parser goldens`. | `zig build test` green; the five goldens match the blocks under *Data & State* byte for byte (`diff <(cat tests/fixtures/expected-ast/recovery_busvalue_eof.txt) …` against the doc during review); `wc -c tests/fixtures/circuits/recovery_busvalue_eof.circ` = 16; `git status --short tests/fixtures` lists exactly 10 new files. STATUS entry lists each fixture's mark count and spans (2/2/2/1/4). |
| 3 | RecoverLine and quirk fixtures + comment fix | Seven fixtures + goldens: `recovery_junk_line`, `recovery_keyword_prefix`, `recovery_connection_line`, `recovery_import_empty_path`, `recovery_width_overflow`, `recovery_multibyte_columns`, `recovery_trailing_ws_baseref`; table entries; the `:286-292` test renamed and its comment rewritten as specified. Commit: `test(syntax): pin recovery-line and parser-quirk goldens`. | `zig build test` green; goldens match the seven blocks under *Data & State* — in particular `recovery_connection_line.txt` has `Errors (1)` (backtracking discarded the inner `busclose` capture), `recovery_multibyte_columns.txt` ends its mark at byte col 15, `recovery_import_empty_path.txt` shows `path="` with `Errors (0)`, `recovery_width_overflow.txt` shows only `Input b width=[255]`; `git status --short tests/fixtures` lists exactly 14 new files. Fixture table now has 39 entries (`grep -c 'expected_ast_path = "' tests/syntax/translate_test.zig` = 39; 41 once PR #79's two entries land). |
| 4 | `--analyze` JSON goldens + build wiring + fork cross-check | `tests/analyze/analyze_golden_test.zig`; `tests/fixtures/expected-analyze/{clean,truncated,junk_line,empty}.json`; `build.zig` `analyze_golden_tests` block after `:921` (with `.name = "analyze_golden_tests"`) and `test_step.dependOn` after `:978`; `tests/README.md` line. Then run the fork's differential over this checkout: `CIRC_ROOT=/Users/jeffersonmourak/circus/worktrees/v0.0.3/libcirc /Users/jeffersonmourak/circus/langlang/go/zig/scripts/diff-circ.sh -v` (from any cwd; the script `cd`s into the fork's `go/`) and record the mismatch count in STATUS. Commit: `test(analyze): golden the --analyze json for the lsp overlays`. | `zig build test` green with the new artifact in the run (`zig build test --summary all` shows a `run analyze_golden_tests` step — the name comes from the `.name` above); the four JSON files equal the byte strings under *Data & State* (`wc -c` = 1320 / 959 / 1387 / 101); `git status --short` = the test file, the four goldens, `build.zig`, `tests/README.md`, `DOCS/STATUS.md`; `diff-circ.sh` reports `TestGenZigDifferentialCorpus` and `TestGenZigTablesMatchVendoredGo` PASS with 0 mismatches over the corpus — `tests/fixtures/circuits/` holds 144 `.circ` files today (only 27 of them are in the `expected-ast` table; the rest serve the diagnostics/IR/wasm/preview suites), 156 after this phase — the 12 `recovery_*.circ` are picked up by the `*.circ` glob at `diff-circ.sh:17`. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own: slice 1 changes the dump format (a 27-file mechanical diff that must be reviewed as "one line per file, nothing else"); slices 2 and 3 add only fixtures and are reviewed against the expected blocks in this document; slice 4 is the only one touching `build.zig`.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `errors: clean source has no marks` | `tests/syntax/translate_test.zig` | `parseSource(…, "input a\noutput o(in=a)\n").errors.len == 0`. |
| `errors: truncated bus carries busvalue then busclose marks` | `tests/syntax/translate_test.zig` | `"input a\nand g(a="` → two marks in that order, messages equal `translate.zig:645`/`:646` strings, each span `start_line=2,start_col=9,end_line=2,end_col=9`, and `parsed.components.len == 0`. |
| `edge: whitespace-only .circ is InvalidProgram` | `tests/syntax/translate_test.zig` | `parseSource(…, "\n  \n")` → `error.InvalidProgram` (oracle: `circ-compile ws.circ --inspect` prints `parse failed: InvalidProgram`); complements the existing `edge: completely empty .circ fails parse` (`error.ParsingFailed`, `:167-174`). |
| `recovery: busvalue_eof fixture has no trailing newline` | `tests/syntax/translate_test.zig` | Last byte of `tests/fixtures/circuits/recovery_busvalue_eof.circ` is `=`; guards the fixture against editor auto-newline (which would move both marks to `3:1`). |
| `subscript: name [i] with space parses as indexed (Spacing before BaseRef's failed optional)` | `tests/syntax/translate_test.zig` (renamed `:286`) | Unchanged assertion (`a [2]` → `.indexed`); comment corrected. |
| `analyze json goldens for the lsp overlays` | `tests/analyze/analyze_golden_test.zig` | For each of the four overlays, `renderJson(analyze(...))` equals the committed `expected-analyze/<name>.json` byte for byte. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|--------|----------------|
| `translate parse tree to typed ast fixtures` (existing, `translate_test.zig:150-165`) | 39 fixtures through `parseSource` → `ast_dump.dumpFile` → `expectGolden` | Every clean golden ends in `Errors (0)`; the twelve `recovery_*` goldens equal the blocks in *Data & State* (spans, messages, order, kept/dropped declarations). |
| `expectGolden …` (existing, `tests/helpers/golden_test.zig`) | golden helper | Unchanged; proves the update-mode semantics slices 1–4 rely on. |
| `run with --inspect on existing fixture` (existing, `cmd/circ-compile/main.zig:617`) and `tests/fixtures/expected-inspect/*` | CLI | Unchanged output — proves `inspect_dump.zig` was not touched. |
| Whole suite | `zig build test` after every slice; `zig build test-all` once before closing the phase | Green; `git status --short tests/fixtures` lists only files named by the slice. |
| Fork differential (`TestGenZigDifferentialCorpus`, `TestGenZigTablesMatchVendoredGo`) | `langlang/go/genzig_diff_test.go:295/:362` via `go/zig/scripts/diff-circ.sh` | 0 mismatches over `tests/fixtures/circuits/*.circ` (156 files after this phase: 144 today + 12 `recovery_*`) with the `LANGLANG_DIFF_LABELS` wording (`diff-circ.sh:18`) that equals `translate.zig:641-648`; the Zig backend's `code` table byte-equals the vendored `parser.go`. Result recorded in STATUS, not asserted by circ's suite. |

Run command: `zig build test` (fast suite; single modules via `zig test tests/syntax/translate_test.zig` are **not** usable here because `translate_mod` needs the `parser.a` link and the `golden`/`ast_dump`/`analyze` module imports from `build.zig` — use `zig build test` or, to iterate on one artifact, temporarily comment other `test_step.dependOn` lines locally without committing). Regeneration: `UPDATE_GOLDENS=1 zig build test` followed by the six-step procedure under *Persistence & I/O*. Full gate before closing: `zig build test-all`.

## Open Questions / Spikes

- Resolved: the `Indexed bit=2 [f0:3:16-3:19]` span in `recovery_trailing_ws_baseref.txt` is not printed by `--inspect` (`lib/cli/inspect_dump.zig:33-37` omits it), but it is the same `idx.span` field the resolver copies onto the synthesized slice (`lib/ir/resolver.zig:222` → `synthesizeSlice` `:145`), and the oracle's `--analyze` reports `E002` and a reference at `3:16-3:19` for that construct. Every span in this document is therefore oracle-measured; a regeneration that disagrees is a finding.
- None otherwise — every span and byte string above was produced by the Go-backed `zig-out/bin/circ-compile` on this branch.
