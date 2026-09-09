# Status — libcirc (compiler front end as a library)

Append-only log, one entry per shipped slice. Newest at the bottom. See `DOCS/PLANS_PROMPT.md` for the phase index and `DOCS/PLANS/PHASE_<N>_*.md` for each phase's spec.

## 2026-09-08 — Phase 0 — Slice 1: `Errors (n)` section in the AST dump

**What shipped:** `tests/helpers/ast_dump.zig::dumpFile` prints a trailing `Errors (n)` block, one `  Error "<message>" [f<id>:<sl>:<sc>-<el>:<ec>]` line per `ast.File.errors` entry with the raw span (zero-width marks stay `[f0:2:9-2:9]`; the `--analyze` widening is not applied). The 27 `expected-ast` goldens were regenerated; every diff is the single new last line `Errors (0)`.
**Files touched:** `tests/helpers/ast_dump.zig`, `tests/syntax/translate_test.zig`, `tests/fixtures/expected-ast/*.txt` (27), `DOCS/STATUS.md` (new).
**Tests:** added `errors: clean source has no marks` and `errors: truncated bus carries busvalue then busclose marks` (the latter pins the unwidened `2:9-2:9` spans on `input a\nand g(a=` without a trailing newline). `zig build test` green; `git diff --stat tests/fixtures/expected-ast` = 27 files, 27 insertions; `git diff … | grep '^+' | sort -u` = exactly `+Errors (0)`; nothing else under `tests/fixtures` moved; `expected-inspect/*` untouched (`lib/cli/inspect_dump.zig` is the CLI copy and does not gain the section).
**Next slice:** Slice 2 — the five label-recovery fixtures (`recovery_busvalue_eof` with no trailing newline, `recovery_busvalue_newline`, `recovery_busclose_midline`, `recovery_busclose_newline`, `recovery_empty_ports`) with goldens reviewed against the blocks in `PHASE_0`, plus the whitespace-only `InvalidProgram` test and the no-trailing-newline guard.
**Notes:** None.
