# Phase 1 — Vendor the langlang-generated Zig parser; retire Go

> **Dependencies:** Phase 0 (`tests/helpers/ast_dump.zig` prints the trailing `Errors (n)` section, the ~11 `tests/fixtures/circuits/recovery_*.circ` fixtures with Go-generated `expected-ast` goldens, `tests/analyze/analyze_golden_test.zig` + `expected-analyze/*.json`) — those goldens are the acceptance oracle this phase replays against the Zig parser. External prerequisite, **already satisfied on this machine**: the fork's hand-over (`~/circus/langlang/go/zig/CIRC.md`) with `langlang v0.0.13-zig.2` installed (`langlang -version` → `Version: v0.0.13-zig.2 (github.com/jeffersonmourak/langlang/go)`) and `CIRC_ROOT=<this checkout> go/zig/scripts/diff-circ.sh -v` at **0 mismatches: 144/144 `TestGenZigDifferentialCorpus/*.circ` PASS, `TestGenZigTablesMatchVendoredGo` PASS** (run 2026-09-08 against `3b84bcb` and re-run independently during review with the same 144 PASS / 0 FAIL; every file in `tests/fixtures/circuits/` is in the corpus, `ls | wc -l` = 144).
> **Warnings:** (1) **`CIRC.md`'s libc claim is wrong, audit result below.** `tests/helpers/golden.zig` does not `@cImport` — it reads `std.posix.getenv("UPDATE_GOLDENS")` (`golden.zig:4`), which has a no-libc branch (`std/posix.zig:2036` is the libc arm, the fallthrough walks `std.os.environ`). The `@cImport` of `setenv/unsetenv` is in `tests/helpers/golden_test.zig:5-7`, whose module already carries `.link_libc = true` (`build.zig:87`) and never had `linkParserArchive`. The only other libc symbol in the tree is `std.c.getpid()` at `tests/helpers/wasm_run.zig:12` (`else` arm of an OS switch, hit on Linux and macOS), imported by exactly two artifacts: `emit_behavior_tests` (`build.zig:520`) and `project_behavior_tests` (`:1035`). Keep `.linkLibC()` on those two (`:527`, `:1042`); delete the other 25. macOS always links libSystem (`std.Target.requiresLibC`, `std/Target.zig:2009-2013` lists `.macos`), so a green local run proves nothing about libc — **only the Linux CI job proves the audit**. (2) **`zig build parser:gen` must pass the grammar path relative to the build root.** The generated header line 2 is `// Source File: <the -grammar argument verbatim>`; generating with an absolute path yields a file that differs on that line only (verified: `diff` shows `2c2`). Today's step already passes `GRAMMAR_FILE = "lib/grammar/proto-circ.peg"` (`build.zig:3`, `:23`) from the build root; keep that. Two relative-path runs are byte-identical (`cmp` clean, sha256 prefix `61daddd228c39aeb`). (3) **Rebase collision with PR #79 — wider than the plan prompt says.** `DOCS/PLANS_PROMPT.md` claims #79 touches none of Phase 0/1's files; `git diff main...memories --stat` (branch `memories` at `2e15e97`) shows it does: (a) `build.zig` gains a 28th `linkParserArchive(b, sim_golden_tests, …)` + `.linkLibC()` + two `addIncludePath` lines (hunk `@@ -1526,6 +1541,33 @@`), and seven earlier hunks (`-197`, `-204`, `-262`, `-269`, `-301`, `-971`) shift every `build.zig` cite from `:301` on by +10 to +15 lines (`:986` becomes ≈`:1000`, the sim block's archive lines sit at ≈`:1541-1570`); (b) `tests/syntax/translate_test.zig` gains `rom-basic`/`ram-basic` rows at `:28-37` (29 fixtures, every inline test +10 lines); (c) **`CLAUDE.md:7` is rewritten by #79** (hunk `@@ -4,7 +4,7 @@`, the "pure Zig … c-archive linked in" sentence) — the same line slice 2 edits, so a textual conflict is guaranteed and must be resolved by keeping #79's memory-export wording and swapping only the parenthetical; (d) `README.md` hunks at `:1`, `:12`, `:65`, `:77` and `DOCS/index.md` hunks at `:3`, `:29`, `:91` do not overlap slice 2's `README.md:40-41` / `DOCS/index.md:85-88` but sit within context distance; (e) `tests/helpers/wasm_run.zig` gains one line at `:22` (`"memimage.zig"` in `engine_files`), so the `:12` `std.c.getpid` cite holds; (f) `lib/analyze/analyze.zig` grows by 94 lines (Phase 2 territory; the `:141-176` cites drift). After the rebase the sim block loses its four archive lines mechanically and the two extra `expected-ast` goldens must replay byte-identically (Go-generated on the memories branch; the fork's `TestGenZigDifferential/grammars/circ` corpus already includes a `rom.circ` input at `go/tests/circ/inputs/rom.circ`, and `diff-circ.sh` will pick up `rom_basic.circ`/`ram_basic.circ` from the merged `tests/fixtures/circuits/`). Also: the plan prompt's Recurring Trap "links `parser.a` into 55 sites" is the 27 archive links plus the 28 include-path pairs; the counts below are the authoritative ones. (4) **Message-table divergence is real but unobservable.** `shim.go:50` binds `trailing` to `"unexpected input; expected a declaration, input, output, or import"`; `translate.zig:642` to `"unexpected input; expected a declaration"`. Only the shim's text can reach users, and only through the hard-failure path (`parseSourceCapturing` → `ParseFailure.message` → `analyze.zig:158`), which is unreachable: `Program` (`proto-circ.peg:1`) absorbs any line through `RecoverLine` and `EndOfInput` throws `trailing` whose recovery is `(![\n] .)*`, so `parse` never returns `ParseFailed` on any input — `edge_parse_empty.circ` (0 bytes) fails at `translate.zig:702` (`TreeRoot` false), not in the VM. No golden or test asserts the shim wording; collapsing onto translate's is a no-op for every pinned output. (5) `lib/parser/parser.a` (4,401,856 B) and `parser.h` are **untracked** (`.gitignore:6-7`; `git ls-files lib/parser` lists only `go.mod`, `parser.go`, `shim/shim.go`) — `git rm` the three tracked files, `rm` the two build products, delete the two `.gitignore` lines (line 7 has no trailing newline). (6) Never run `parser:gen` with upstream `go/v0.0.12` on `PATH`: it rejects `-output-language zig`; the new version gate (Data & State) turns that into a loud build error, honouring the decision at `DOCS/decisions/tooling.md:31-37` that `build.zig` never implemented. (7) `translate_mod` is imported by name at 18 `addImport("translate", translate_mod)` sites — untouched; the module gains one import (`parser`) and loses its two `addIncludePath` lines (`build.zig:101-102`). (8) All `file:line` cites are against branch `libcirc` at `3b84bcb` (== `main` + two doc commits) unless a path under `~/circus/langlang` is named.

## Goal

`zig build`, `zig build circ-compile`, and `zig build test-all` succeed on a machine whose `PATH` has no `go`, producing a `circ-compile` that parses `.circ` through `lib/parser/parser.zig` — a langlang-generated, vendored Zig file whose header records `Runtime: langlang_runtime.zig abi=1 sha256=007bc7864beb8c39960a00e87f52b19f4f3e7c334516168cc78285b3b094ec06` — with every golden in `tests/fixtures/` byte-identical to the Go-parser output: the 27 `expected-ast` dumps (plus Phase 0's recovery goldens and `expected-analyze` JSON), 16 `expected-ir`, 14 `expected-zig`, 42 `expected-wasm`, 31 `expected-diagnostics`, 25 preview renders, 56 truth tables. `lib/parser/` holds exactly one file; `lib/syntax/CParser.zig`, `lib/syntax/nodes/declaration.zig`, `fn linkParserArchive`, the `parser:archive` step, the `GOOS/GOARCH/CC` block and every `parser.a` link line are gone from the tree; `zig build parser:gen` on the unchanged grammar rewrites `lib/parser/parser.zig` with zero diff; the GitHub PR job runs the full suite with Go pruned from `PATH` and asserts `command -v go` fails; the `cli-tag.yml` matrix (`x86_64-linux-gnu`, `aarch64-macos`, `x86_64-windows-gnu`, ReleaseFast) cross-compiles from one Zig install with no C archive, and `circ-compile` loses the ~2 MB Go runtime (Debug binary today: 2,186,432 B; new size recorded in STATUS).

## Scope

**In scope:**
- `lib/parser/parser.zig`: generated by `langlang -grammar lib/grammar/proto-circ.peg -disable-capture-spaces -output-language zig -output-path lib/parser/parser.zig` (1,639 lines, 75,915 bytes; `Rule` enum with 13 entries, `entry_rule = .Program` at address 5, `left_recursive_rules.len == 0`, `bytecode.abi = 1`, `rxps` has recovery addresses for string ids 1–5 = `trailing 1344 / busname 1352 / busassign 1360 / busvalue 1368 / busclose 1376`); passes `zig fmt --check`, its own `test "langlang tables"`, and the fork's `testdata/circ_shape_test.zig` (5/5 = its four tests plus the generated file's `langlang tables`, pulled in through `@import("parser.zig")`) against this exact output; links into a `wasm32-freestanding` ReleaseSmall module of **18,491 bytes** with the fork's `testdata/wasm_entry.zig` (`zig build-exe wasm_entry.zig -target wasm32-freestanding -O ReleaseSmall -fno-entry --export=parse --export=alloc`, the recipe at `go/genzig_test.go:235`; the fork's `TestGenZigCompiles/wasm-smoke` logs the same 18,491 on this machine) — all re-verified during review on 2026-09-08.
- `build.zig`: `parser:gen` re-pointed at the command above behind a `langlang -version` gate; a `parser_mod` created over the vendored file (via a small `createParserModule(b, target, optimize)` helper so Phase 2's `build/frontend_modules.zig` can mint the wasm-target twin without duplicating the literal); `translate_mod.addImport("parser", parser_mod)`; a `parser_tests` artifact wired into `test`; deletion of `fn linkParserArchive` (`:5-12`), the `parser_archive` step + `build_archive_cmd` + `goarch/goos/cc_value` (`:38-77`), all 27 `linkParserArchive(b, …)` calls, 25 of the 27 paired `.linkLibC()` calls, and all 28 `addIncludePath(b.path("."))`/`addIncludePath(b.path("./lib"))` pairs.
- `lib/syntax/translate.zig`: re-target the six accessors and `TranslationContext` to `parser.runtime.Tree`; `translateTree` root lookup; `parseSourceCapturing` on `parser.Parser`; single `circ_label_messages` table with comptime guards; delete `translate()` (`:738-751`).
- Deletions: `lib/parser/{go.mod,parser.go,shim/shim.go}` (tracked), `lib/parser/{parser.a,parser.h}` (untracked build products), `lib/syntax/CParser.zig`, `lib/syntax/nodes/declaration.zig` (dead: the only references are its own `C_Parser` import and no importer anywhere — `grep -rn 'declaration.zig\|nodes/'` over `lib cmd tests tools build.zig` is empty), `.gitignore:6-7`.
- Docs that state the prerequisite: `CLAUDE.md:7,24,26,38,39,72`, `README.md:40-41`, `DOCS/index.md:85-88`.
- CI: `.github/workflows/pr-tests.yml` gains a PATH-prune step before `Run all tests`; `.github/workflows/cli-tag.yml` needs no edit (its matrix already names the three targets; the archive step it silently depended on is simply gone) — the three cross-builds are run locally as the proof.
- `DOCS/STATUS.md` entries per slice.

**Explicitly deferred:**
- `DOCS/decisions/tooling.md` (new entry superseding `:5-29`), `DOCS/decisions/index.md:46-48`, `DOCS/architecture.md:12-15,131-133`, `DOCS/circuit-format.md:132`, `site/src/pages/reference/circuit-format.md:136`, `CLAUDE.md`'s pipeline diagram wording beyond the one line at `:72`, and the `.peg` header comment → Phase 5 (its proof `rg` must then return only the decision record).
- Any wasm-target `translate`/`parser` module twin (Phase 3 needs it; Phase 2's `build/frontend_modules.zig` creates it by calling the helper introduced here).
- Fixing parser quirks (keyword-prefix splitting, `u8` width literals, silent drops) — pinned by Phase 0, untouched here.
- Switching `wasm_run.zig:12` from `std.c.getpid` to `std.os.linux.getpid` so the last two `.linkLibC()` calls can go (see Open Questions).
- Using `Tree.message(id)` for error marks instead of `labelMessage(name)` — rejected: `Tree.message` falls back to the label *name* when no message is bound (`langlang_runtime.zig:297-306`), whereas translate's fallback is `"syntax error"` (`translate.zig:647`); keeping `labelMessage` keeps the fallback and the byte-identity argument trivial.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| parser | `lib/parser/parser.zig` | Generated (`// Code generated by langlang (unknown commit hash), DO NOT EDIT.` / `// Source File: lib/grammar/proto-circ.peg` / `// Runtime: langlang_runtime.zig abi=1 sha256=007bc786… (Zig 0.15.1, native + wasm32-freestanding, no libc)`), then `pub const runtime = struct { … }` (the pasted VM, `langlang_runtime.zig` verbatim minus its `std` import), `pub const bytecode = runtime.Bytecode{ .abi = 1, .code = …, .strs = …, .sets = …, .rxps = …, .srcm = null }`, `pub const Rule = enum(u16) { Program = 5, AnonDecl = 734, ComponentType = 753, PortRef = 921, Concat = 940, IndexedRef = 995, BaseRef = 1104, BusType = 1182, trailing = 1344, busname = 1352, busassign = 1360, busvalue = 1368, busclose = 1376 }`, `pub const entry_rule: Rule = .Program`, `pub const left_recursive_rules = [_]Rule{}`, `pub const Parser = runtime.Interpreter(bytecode, Rule, &left_recursive_rules)`, `test "langlang tables"`. Never hand-edited; regenerated only by `zig build parser:gen`. |
| plans | `DOCS/PLANS/PHASE_1_vendor_zig_parser.md` (this file) | Plan artifact. |
| status | `DOCS/STATUS.md` | Created by slice 1's entry if Phase 0 has not created it. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| build | `build.zig` | **`:3`** keep `GRAMMAR_FILE`. **`:5-12`** replace `fn linkParserArchive` with `fn createParserModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module` returning `b.createModule(.{ .root_source_file = b.path("lib/parser/parser.zig"), .target = target, .optimize = optimize })`. **`:19-36`** `parser_gen`: description `"Regenerate lib/parser/parser.zig from lib/grammar/proto-circ.peg (needs the langlang fork on PATH)"`; a `check_langlang = b.addSystemCommand(&.{ "langlang", "-version" })` with `check_langlang.addCheck(.{ .expect_stdout_match = "v0.0.13-zig.2" })` and `check_langlang.has_side_effects = true`; `generate_parser_cmd` argv becomes `langlang -grammar <GRAMMAR_FILE> -disable-capture-spaces -output-language zig -output-path lib/parser/parser.zig` (the `-go-package parser` / `-go-parser Parser` pairs at `:30-33` go), `generate_parser_cmd.step.dependOn(&check_langlang.step)`. **`:38-77`** delete `parser_archive`, the `goarch`/`goos` switches with both `@panic` arms, `zig_triple`/`cc_value`, `build_archive_cmd` and its four `setEnvironmentVariable` calls. **`:96-102`** after `translate_mod` is created: `const parser_mod = createParserModule(b, target, optimize); translate_mod.addImport("parser", parser_mod);` and delete `translate_mod.addIncludePath(b.path("."))` / `("./lib")` (`:101-102`); add `const parser_tests = b.addTest(.{ .root_module = parser_mod }); const run_parser_tests = b.addRunArtifact(parser_tests);` and `test_step.dependOn(&run_parser_tests.step)` next to `:968`. **Delete all 27** `linkParserArchive(b, <artifact>, build_archive_cmd);` lines: `:120 translate_tests`, `:161 resolver_tests`, `:301 validator_name_passes_tests`, `:327 validator_structural_tests`, `:349 validator_loop_tests`, `:371 validator_run_tests`, `:453 emit_build_fn_tests`, `:479 emit_metadata_tests`, `:502 emit_full_tests`, `:526 emit_behavior_tests`, `:611 resolver_scan_imports_tests`, `:635 resolver_import_cycle_tests`, `:664 resolver_resolve_bodies_tests`, `:679 resolver_builtins_tests`, `:694 resolver_file_loader_tests`, `:898 circ_compile_exe`, `:909 circ_compile_tests`, `:919 analyze_tests`, `:938 validator_project_passes_tests`, `:964 validator_codes_snapshot_tests`, `:1017 emit_project_tests`, `:1041 project_behavior_tests`, `:1451 preview_layout_integration_tests`, `:1476 topology_full_emit_integration_tests`, `:1500 section_writer_fixtures_tests`, `:1523 serializer_fixtures_tests`, `:1654 bench_exe`. **Delete 25 of 27** `.linkLibC()` lines (`:121 162 302 328 350 372 454 480 503 612 636 665 680 695 899 910 920 939 965 1018 1452 1477 1501 1524 1655`); **keep `:527`** (`emit_behavior_tests`) **and `:1042`** (`project_behavior_tests`) with a one-line comment naming `tests/helpers/wasm_run.zig:12` (`std.c.getpid`). **Delete all 28** `addIncludePath` pairs (`:101-102, 118-119, 159-160, 299-300, 325-326, 347-348, 369-370, 451-452, 477-478, 500-501, 524-525, 609-610, 633-634, 662-663, 677-678, 692-693, 896-897, 907-908, 917-918, 936-937, 962-963, 1015-1016, 1039-1040, 1449-1450, 1474-1475, 1498-1499, 1521-1522, 1652-1653`) — nothing but `CParser.zig`'s `#include "parser/parser.h"` ever used them. `golden_tests`' `.link_libc = true` (`:87`) stays. Net: `grep -c "linkParserArchive\|parser\.a\|addIncludePath\|GOARCH" build.zig` → 0; `grep -c "linkLibC()" build.zig` → 2. |
| syntax | `lib/syntax/translate.zig` | **`:4`** `const C_Parser = @import("CParser.zig").C_Parser;` → `const parser = @import("parser");`. **`:8-23`** replace the four `NodeType_*: u8` consts and the `c_int` `Range` with `const NodeType = parser.runtime.NodeType;` (values are identical: `string=0, sequence=1, node=2, err=3`, `langlang_runtime.zig:213-218`) and `const Range = parser.runtime.Range;` (`usize`, `:239-242`). **`:25-31`** `TranslationContext.handle: @TypeOf(C_Parser.ParserNew())` → `tree: *const parser.runtime.Tree`. **`:33-46, 78-96`** the six wrappers become one-liners over the tree (Data & State). **`:63-66`** `nodeSpan` drops the two `@intCast(@max(…, 0))`. **8 sites** drop `@intCast` on `range.start/end` and `path_range.start/end` (`:108-109, :158-159, :216-217, :434-435`) — `Range` fields are already `usize`. **49** `NodeType_String/Sequence/Node/Error` comparisons on 48 lines (`grep -o "NodeType_[A-Za-z]*" | wc -l` = 54 minus the four `const` definitions at `:11-14` and the comment at `:10`; `:664` holds two) become `.string/.sequence/.node/.err` (the `switch` at `:323-361` keeps its `else`). **`:641-648`** `labelMessage` becomes a loop over a new `pub const circ_label_messages` array (translate's five strings) plus two `comptime` guards. **`:700-702`** `var root: u32 = undefined; if (!C_Parser.TreeRoot(ctx.handle, &root)) return error.ParsingFailed;` → `const root = ctx.tree.root() orelse return error.ParsingFailed;`. **`:738-751`** delete `pub fn translate(allocator, handle, file_id)` (no callers: `grep -rn '\.translate(' lib cmd tests tools` is empty). **`:769-807`** `parseSourceCapturing` rewritten on `parser.Parser` (Data & State). `parseSource` (`:761-763`), `ParseFailure` (`:753-759`), `offsetToLineCol` (`:48-61`), `collectErrorMarks` (`:654-672`, including the literal RecoverLine message at `:661`) and every parse function are otherwise untouched, so the frozen signatures used at `scan_imports.zig:139`, `resolve_bodies.zig:426`, `analyze.zig:145`, `main.zig:190` and the 12 test files stay valid. |
| vcs | `.gitignore` | Delete lines 6–7 (`lib/parser/parser.a`, `lib/parser/parser.h`); file ends after `.claude/` with a newline. |
| docs | `CLAUDE.md` | `:7` "(the parser is a langlang-generated Go CGo c-archive linked in)" → "(the parser is a langlang-generated Zig file, `lib/parser/parser.zig`, vendored)"; `:24` delete the Go bullet; `:26` keep the fork install line, reword to "regenerates `lib/parser/parser.zig`"; `:38` delete the `parser:archive` row; `:39` "Regenerates `lib/parser/parser.zig` … requires the langlang fork (`v0.0.13-zig.2`) on `PATH`; the step refuses any other version"; `:72` `PEG parser (vendored C, generated from` → `PEG parser (vendored Zig, generated from`. |
| docs | `README.md` | `:40` delete the Go bullet; `:41` "regenerate `lib/parser/parser.zig`" and note the version gate. |
| docs | `DOCS/index.md` | `:85-86` `parser/  Vendored langlang-generated Zig parser (parser.zig; runtime + bytecode tables)`; `:88` `syntax/  Parse tree → AST translation over the generated Tree API`. |
| ci | `.github/workflows/pr-tests.yml` | Between `Install Node` (`:36-38`) and `Run all tests` (`:40-53`): a `Remove Go from PATH` step that drops every `PATH` entry containing an executable `go`, exports the pruned `PATH` through `$GITHUB_ENV`, and fails the job if `command -v go` still resolves (Data & State). The existing `test-all` step (with `SKIP_WASM_E2E=1`) then runs Go-free, which subsumes the index row's "`zig build circ-compile` step" (`test_step` depends on `circ_compile_exe.step`, `build.zig:986`, and `tests/cli/integration_test.zig:46` spawns `zig build circ-compile` itself). |
| ci | `.github/workflows/cli-tag.yml` | No edit. Proof is local: the three `zig build -Doptimize=ReleaseFast -Dtarget=<t> circ-compile` commands from `:40`. Optional one-line comment above `:39` noting the build is pure Zig. |
| docs | `DOCS/STATUS.md` | One entry per slice (template in `DOCS/PLANS_PROMPT.md:93-101`), recording sizes and the `diff-circ.sh` numbers. |
| syntax | `lib/parser/go.mod`, `lib/parser/parser.go`, `lib/parser/shim/shim.go`, `lib/syntax/CParser.zig`, `lib/syntax/nodes/declaration.zig` | **Deleted** (`git rm`). `lib/parser/parser.a`, `lib/parser/parser.h`: removed from the working tree (`rm`), never tracked. `lib/syntax/nodes/` directory disappears with its only file. |

**New dependencies:** None at build time — that is the point. `langlang` (the fork, `go install github.com/jeffersonmourak/langlang/go/cmd/langlang@v0.0.13-zig.2`) remains an offline, grammar-change-only tool, now version-gated by `parser:gen`. Go is no longer required for anything in this repository.

## Data & State

The generated module's surface consumed by circ (all names spelled through `parser.runtime.*` — nothing is re-exported, `go/zig/README.md:61-64`):

```zig
// lib/parser/parser.zig (generated) — what translate.zig uses
pub const runtime = struct {
    pub const NodeId = u32;                                            // :209
    pub const NodeType = enum(u8) { string = 0, sequence = 1, node = 2, err = 3 }; // :213
    pub const Range = struct { start: usize, end: usize };             // :239, end exclusive
    pub const LabelMessage = struct { label: []const u8, message: []const u8 }; // :244
    pub const Tree = struct {
        pub fn root(t: *const Tree) ?NodeId;                           // null on empty input
        pub fn typ(t: *const Tree, id: NodeId) NodeType;
        pub fn name(t: *const Tree, id: NodeId) []const u8;            // rule name, or the label for .err; "" when unnamed
        pub fn range(t: *const Tree, id: NodeId) Range;
        pub fn child(t: *const Tree, id: NodeId) ?NodeId;              // .node/.err only
        pub fn childrenLen(t: *const Tree, id: NodeId) usize;          // 0 string / N sequence / 0|1 node,err
        pub fn childAt(t: *const Tree, id: NodeId, i: usize) ?NodeId;
    };
    pub const ParseError = struct { label_id: u32 = 0, start: u32 = 0, end: i32 = -1, …,
        pub fn messageAlloc(e: ParseError, gpa: std.mem.Allocator, bc: *const Bytecode, messages: []const ?[]const u8) std.mem.Allocator.Error![]u8; };
    pub const Error = error{ ParseFailed, OutOfMemory, InvalidBytecode };
};
pub const bytecode: runtime.Bytecode;   // .strs (names + labels), .rxps (recovery address per string id, -1 = none)
pub const Parser = runtime.Interpreter(bytecode, Rule, &left_recursive_rules); // Interpreter: langlang_runtime.zig:1372-1461 (generated file :1378-1467)
//   pub fn init(gpa) Allocator.Error!Parser; pub fn deinit(*Parser); pub fn setLabelMessages(*Parser, []const LabelMessage);
//   pub fn parse(*Parser, input: []const u8) Error!*const Tree;   // tree owned by the parser, reset by the next parse
//   pub fn lastError(*const Parser) ParseError; pub fn messages(*const Parser) []const ?[]const u8;
//   pub fn labelId(name: []const u8) ?u16;   // static (no self), a plain loop over bc.strs (:1404-1409) — comptime-callable, which the guards below rely on
```

`translate.zig` after the switch — every change is confined to these blocks:

```zig
const std = @import("std");
const ast = @import("ast.zig");
const Span = @import("span.zig").Span;
const parser = @import("parser");                      // was: @import("CParser.zig").C_Parser

pub const Ast = ast;

const NodeType = parser.runtime.NodeType;              // .string/.sequence/.node/.err — same numbering as the Go iota
const Range = parser.runtime.Range;                    // usize offsets; no @max/@intCast needed

const TranslationContext = struct {
    allocator: std.mem.Allocator,
    tree: *const parser.runtime.Tree,                  // was: handle: @TypeOf(C_Parser.ParserNew())
    source: []const u8,
    file_id: u32,
    anonymous_counter: usize = 0,
};

fn nodeType(ctx: *const TranslationContext, node_id: u32) NodeType { return ctx.tree.typ(node_id); }
fn nodeName(ctx: *const TranslationContext, node_id: u32) []const u8 { return ctx.tree.name(node_id); }
fn nodeRange(ctx: *const TranslationContext, node_id: u32) Range { return ctx.tree.range(node_id); }
fn childAt(ctx: *const TranslationContext, parent: u32, index: usize) !u32 {
    return ctx.tree.childAt(parent, index) orelse error.InvalidChildIndex;
}
fn childCount(ctx: *const TranslationContext, parent: u32) usize { return ctx.tree.childrenLen(parent); }
fn firstChild(ctx: *const TranslationContext, parent: u32) !u32 {
    return ctx.tree.child(parent) orelse error.InvalidChild;
}

/// The one label→message table. Bound into every Parser (so a hard failure's
/// ParseFailure carries the same text) and consulted by collectErrorMarks.
pub const circ_label_messages = [_]parser.runtime.LabelMessage{
    .{ .label = "trailing", .message = "unexpected input; expected a declaration" },
    .{ .label = "busname", .message = "expected a port name" },
    .{ .label = "busassign", .message = "expected '=' after the port name" },
    .{ .label = "busvalue", .message = "expected a signal reference after '='" },
    .{ .label = "busclose", .message = "expected ')' to close the connection list" },
};

fn labelMessage(label: []const u8) []const u8 {
    for (&circ_label_messages) |lm| if (std.mem.eql(u8, lm.label, label)) return lm.message;
    return "syntax error";
}

comptime {
    // Every bound label must exist in the grammar's string table …
    for (&circ_label_messages) |lm| if (parser.Parser.labelId(lm.label) == null)
        @compileError("translate.zig binds a label the grammar does not define: " ++ lm.label);
    // … and every label with a recovery production must be bound (a new ^label in the .peg fails here, not at runtime).
    for (parser.bytecode.rxps, 0..) |addr, i| if (addr != -1 and std.mem.eql(u8, labelMessage(parser.bytecode.strs[i]), "syntax error"))
        @compileError("grammar label without a message in circ_label_messages: " ++ parser.bytecode.strs[i]);
    std.debug.assert(parser.entry_rule == .Program);
    std.debug.assert(parser.left_recursive_rules.len == 0);   // the LR opcodes never appear in the shipped bytecode
}

fn translateTree(ctx: *TranslationContext) !ast.File {
    const root = ctx.tree.root() orelse return error.ParsingFailed;   // empty file: no capture → no root → same error as TreeRoot=false
    try expectNamedNode(ctx, root, "Program");
    … unchanged …
}

pub fn parseSourceCapturing(allocator: std.mem.Allocator, file_id: u32, source: []const u8, failure_out: ?*ParseFailure) !ast.File {
    var p = try parser.Parser.init(allocator);
    defer p.deinit();                                  // ast.File never aliases tree memory: identifiers slice ctx.source (:111, :160, :218, :440)
    p.setLabelMessages(&circ_label_messages);
    const tree = p.parse(source) catch |e| switch (e) {
        error.ParseFailed => {
            if (failure_out) |out| {
                const le = p.lastError();
                const start: usize = le.start;                          // u32
                const end: usize = @intCast(@max(le.end, 0));           // i32, -1 when nothing failed — same clamp as :780-781
                const start_lc = offsetToLineCol(source, start);
                const end_lc = offsetToLineCol(source, end);
                out.* = .{
                    .start_line = start_lc.line, .start_col = start_lc.col,
                    .end_line = end_lc.line, .end_col = end_lc.col,
                    .message = try le.messageAlloc(allocator, &parser.bytecode, p.messages()),  // allocator-owned, survives p.deinit()
                };
            }
            return error.ParsingFailed;
        },
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidBytecode => unreachable,           // verifyTables runs in the generated file's own test
    };
    var ctx = TranslationContext{ .allocator = allocator, .tree = tree, .source = source, .file_id = file_id };
    return translateTree(&ctx);
}
```

Behavioural equivalences the goldens rest on (all reproduced by the VM port, proven by the differential): byte-based cursors and charsets (multibyte input matched byte by byte, so `offsetToLineCol` columns are unchanged); `childrenLen == 1` for `.node`/`.err` with a child and `childAt(id, 1) == null` (the `TreeChildrenAt` false case at `:80-82`); a `busclose` throw yields a zero-width `.err` at the cursor (grammar `:37` is empty; `analyze.zig:164-166` widens it); `tree.name(err_id)` is the label name, so `labelMessage(nodeName(...))` at `:657` is unchanged; `RecoverLine` nodes keep their literal message at `:661`.

`build.zig` additions:

```zig
fn createParserModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return b.createModule(.{ .root_source_file = b.path("lib/parser/parser.zig"), .target = target, .optimize = optimize });
}
// in build():
const parser_gen = b.step("parser:gen", "Regenerate lib/parser/parser.zig from lib/grammar/proto-circ.peg (needs the langlang fork on PATH)");
const check_langlang = b.addSystemCommand(&.{ "langlang", "-version" });
check_langlang.addCheck(.{ .expect_stdout_match = "v0.0.13-zig.2" });   // upstream go/v0.0.12 prints no such string and rejects -output-language zig
//   Zig 0.15.1 std/Build/Step/Run.zig: addCheck (:543) flips stdio from .infer_from_args to .check (:547-549);
//   a stdout check makes stdout a pipe (:1449); with no expect_term the exit code must be 0 (:1377).
//   The fork prints "Version: v0.0.13-zig.2 (github.com/jeffersonmourak/langlang/go)" on stdout, nothing on stderr (verified).
check_langlang.has_side_effects = true;                                 // hasSideEffects() (:598) then bypasses the cache hit at :797 — never serve the check from the cache after a langlang swap
const generate_parser_cmd = b.addSystemCommand(&.{
    "langlang", "-grammar", GRAMMAR_FILE, "-disable-capture-spaces",
    "-output-language", "zig", "-output-path", "lib/parser/parser.zig",
});                                                                     // GRAMMAR_FILE stays relative: it is copied into the header's "Source File:" line
generate_parser_cmd.step.dependOn(&check_langlang.step);
parser_gen.dependOn(&generate_parser_cmd.step);
…
const parser_mod = createParserModule(b, target, optimize);
translate_mod.addImport("parser", parser_mod);
const parser_tests = b.addTest(.{ .root_module = parser_mod });         // runs the generated `test "langlang tables"` (verifyTables)
const run_parser_tests = b.addRunArtifact(parser_tests);
… test_step.dependOn(&run_parser_tests.step);
```

`pr-tests.yml` step (inserted before `Run all tests`):

```yaml
      - name: Remove Go from PATH (the build must not need it)
        # ubuntu-latest ships a Go toolchain, so the plain job could never prove
        # independence. Drop every PATH entry that resolves `go`, then assert.
        run: |
          set -euo pipefail
          pruned=""
          IFS=: read -ra dirs <<< "$PATH"
          for d in "${dirs[@]}"; do
            if [[ -x "$d/go" ]]; then echo "dropping $d (has go)"; else pruned="${pruned:+$pruned:}$d"; fi
          done
          echo "PATH=$pruned" >> "$GITHUB_ENV"
          if PATH="$pruned" command -v go >/dev/null 2>&1; then echo "::error::go still resolves on PATH"; exit 1; fi
          PATH="$pruned" zig version && PATH="$pruned" node --version
```

**Consumed from Phase 0:** `ast_dump`'s `Errors (n)` section and the regenerated 27 goldens; `recovery_*.txt` goldens pinning `ErrorMark` spans/messages; `expected-analyze/*.json`. **Exposed to later phases:** `createParserModule` (Phase 2 calls it with `wasm_target` for the twin; Phase 3 links it into `libcirc.wasm`); `translate.circ_label_messages` (public, so a future `circ_inspect` or the LSP can print the table); the generated header's `sha256=` line as the skew signal Phase 5's `tooling.md` entry cites.

## Execution & Concurrency Model

This phase is fully synchronous. No background threads or workers are introduced. Each `parseSource`/`parseSourceCapturing` call constructs one `parser.Parser` on the caller's allocator (`Machine.init` allocates its stack and node arena from that allocator, `langlang_runtime.zig:773`), parses, translates, and `deinit`s on return — there is no process-wide parser state, unlike the cgo handle table (`shim.go:20-38`) and its per-handle `nameCache`. The tree is owned by the parser and valid only until `p.deinit()`; `translateTree` runs entirely inside that window and `ast.File` copies nothing from it (identifier text is sliced from `source`; `ErrorMark.message` points at comptime string literals). The compile pipeline, the `--analyze` loop (`analyze.zig:141-176`), and every test remain single-threaded; `zig build test`'s parallel test binaries each hold their own parsers.

## Persistence & I/O

Build-time only. `zig build parser:gen` (opt-in) runs `langlang -version` and then overwrites `lib/parser/parser.zig` in the source tree; nothing else in the build spawns a subprocess for the parser (the `go build` Run step with its `lib/parser` cwd and `GOARCH/GOOS/CGO_ENABLED/CC` environment, `build.zig:63-75`, is deleted). At compile time the parser is ordinary Zig source in the module graph — no `@embedFile`, no archive, no include paths. The CLI's runtime I/O (reading `.circ` files, writing `.wasm`) is untouched. Tests read the same fixture files as before. `DOCS/STATUS.md` gains one entry per slice.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Cut over to the generated Zig parser | Run `zig build parser:gen` (new step) to vendor `lib/parser/parser.zig`, or copy the file generated while planning (identical bytes, sha256 prefix `61daddd228c39aeb`); `build.zig`: `createParserModule`, version-gated `parser:gen`, `parser_mod` + `translate_mod.addImport("parser", …)`, `parser_tests` in `test`, delete `linkParserArchive` + `parser:archive` + the `GOOS/GOARCH/CC` block, the 27 archive-link calls, 25 `.linkLibC()` calls, 28 `addIncludePath` pairs; `translate.zig` re-targeted per Data & State with `circ_label_messages` + comptime guards and `translate()` deleted. `lib/parser/parser.go`, `shim/`, `CParser.zig` stay on disk this slice (dead, unreferenced) so the review diff is the switch alone. Commit: `feat(parser): vendor the langlang-generated Zig parser` (54 chars; CLAUDE.md caps titles under 70). | `zig build test` green: `translate parse tree to typed ast fixtures` passes with all 27 `expected-ast` goldens byte-identical (`git status --porcelain tests/fixtures` empty, no `UPDATE_GOLDENS`), Phase 0's `recovery_*` and `expected-analyze` goldens unchanged, `edge: completely empty .circ fails parse` still yields `error.ParsingFailed`; the new `parser_tests` artifact runs `langlang tables` OK; `zig build test-all` green (the `emit` smoke proves the two kept `linkLibC` lines suffice); `rm -rf .zig-cache zig-out && zig build circ-compile` on this machine never invokes `go` (`ps`/`zig build --verbose` shows no `go build`); `zig build parser:gen && git diff --exit-code lib/parser/parser.zig` exits 0; `CIRC_ROOT=<checkout> go/zig/scripts/diff-circ.sh -v` still 144/144 + `TestGenZigTablesMatchVendoredGo` PASS (run now, while `parser.go` still exists — see Open Questions); `ls -l zig-out/bin/circ-compile` size recorded in STATUS against today's 2,186,432 B. |
| 2 | Delete the Go sources, drop the prerequisite from docs, prove it in CI | `git rm lib/parser/go.mod lib/parser/parser.go lib/parser/shim/shim.go lib/syntax/CParser.zig lib/syntax/nodes/declaration.zig`; `rm lib/parser/parser.a lib/parser/parser.h`; `.gitignore:6-7` removed; `CLAUDE.md:7,24,26,38,39,72`, `README.md:40-41`, `DOCS/index.md:85-88` per the Modified table; `pr-tests.yml` PATH-prune step; STATUS entry with the three cross-build results. Commit: `chore(parser): drop the Go sources and toolchain prerequisite` (61 chars). | `git ls-files lib/parser` prints exactly `lib/parser/parser.zig`; `ls lib/syntax` = `ast.zig span.zig translate.zig`; `grep -rn "CGo\|parser\.a\|CParser\|go build\|parser:archive\|Go 1\.21" CLAUDE.md README.md build.zig .gitignore DOCS/index.md .github` is empty; local Go-free replay of the CI recipe: `PATH=$(echo "$PATH" | tr : '\n' | grep -v "$(dirname "$(command -v go)")" | paste -sd: -) sh -c '! command -v go && zig build test-all --summary all'` green; the three tag-matrix builds succeed locally: `zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu circ-compile`, `… -Dtarget=aarch64-macos …`, `… -Dtarget=x86_64-windows-gnu …` each producing `zig-out/bin/circ-compile[.exe]` (sizes in STATUS); the PR's `zig build test` job shows the `Remove Go from PATH` step dropping at least one directory and `Run all tests` green. |

Slices are ordered by dependency. Slice 1 is the whole behavioural change and is self-contained (the tree builds without Go from that commit on); slice 2 is a pure deletion/documentation sweep whose review is `git diff --stat`. Rebasing onto a merged PR #79 between or after the slices adds the mechanical edits in Warning 3.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `langlang tables` | `lib/parser/parser.zig` (generated; new `parser_tests` artifact in `zig build test`) | `runtime.verifyTables(bytecode)` succeeds — opcode stream, string table and `rxps` are well-formed for `abi = 1`; the `Interpreter` comptime check refuses any other ABI at compile time (`langlang_runtime.zig:1373-1377`). |
| `translate parse tree to typed ast fixtures` | `tests/syntax/translate_test.zig:150` | All 27 fixtures (`:12-148`) dump byte-identically to `tests/fixtures/expected-ast/*.txt` through the Zig tree, including Phase 0's trailing `Errors (0)` line; Phase 0's `recovery_*` rows pin `ErrorMark` spans/messages (`busclose` zero-width, `RecoverLine` lines, multibyte columns). |
| `edge: completely empty .circ fails parse` | `tests/syntax/translate_test.zig:167` | `edge_parse_empty.circ` (0 bytes) → `error.ParsingFailed`, now via `tree.root() == null` at the rewritten `:702`. |
| `width: …`, `param: …`, `callwidths: …`, `subscript: …`, `concat: …`, `slice: …` (19 inline tests starting at `:188` through `:360`; the file has 21 `test` blocks in 368 lines) | `tests/syntax/translate_test.zig` | Inline-source behaviour unchanged: `input[100] a` keeps `literal = 100`, `a [2]` still binds indexed (`:286-298`, comment corrected by Phase 0), open-ended slices/empty concat still fail or produce no node. |
| comptime label guards | `lib/syntax/translate.zig` (`comptime {}` block) | Compile-time: each of the five bound labels resolves via `Parser.labelId`; every string id with `rxps != -1` (ids 1–5 today) has a message; `entry_rule == .Program`; `left_recursive_rules.len == 0`. Proof during slice 1: temporarily misspell `"busclose"` → build fails with the `@compileError` text; revert. |
| `translate_tests` module build | `build.zig` | `translate_mod` compiles with `@import("parser")` resolved through `addImport` (Zig rejects `@import("../parser/parser.zig")` across module roots — the reason the module exists). |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| Golden families through the new parser | `zig build test-all` | Byte-identical: 16 `expected-ir` (`tests/ir/resolver_test.zig`), 14 `expected-zig` (`tests/emit/*`), 42 `expected-wasm` (`tests/e2e/serializer_fixtures_test.zig`, `section_writer_fixtures_test.zig`), 31 `expected-diagnostics` (`tests/validator/*`), 25 `tests/fixtures/preview/renders` (`cmd/circ-compile/main.zig:658-690` and `tests/preview/layout_integration_test.zig`), 56 `tests/fixtures/truth_table`; `git status --porcelain tests/fixtures` empty afterwards. |
| `analyze` recovery + `expected-analyze` goldens | `lib/analyze/analyze.zig` tests, `tests/analyze/analyze_golden_test.zig` (Phase 0) | `code: "syntax"` diagnostics for the clean/truncated/junk-line/empty overlays are byte-identical JSON — the `ErrorMark` path through `:160-175` is unchanged; the blank-source short-circuit at `:142` still precedes the parser. |
| CLI integration with a nested Go-free build | `tests/cli/integration_test.zig:44-49` (`buildCli`; the comment explaining the once-only build is `:38-42`) | `buildCli()` spawns `zig build circ-compile` and expects exit 0; under the pruned-`PATH` CI job this is the index row's "`zig build circ-compile` step with Go removed". |
| `zig build parser:gen` idempotence | `build.zig` `parser:gen` | Two consecutive runs on the unchanged grammar leave `git diff --exit-code lib/parser/parser.zig` at 0 (verified while planning: relative-path regenerations are `cmp`-clean); the gate step fails with `expect_stdout_match` when `langlang -version` does not contain `v0.0.13-zig.2`. |
| Fork-side differential (external oracle) | `~/circus/langlang/go/zig/scripts/diff-circ.sh -v` with `CIRC_ROOT=<this checkout>` | `TestGenZigDifferentialCorpus/<name>.circ` PASS for all 144 fixture files with the five circ label messages bound (`diff-circ.sh:18`), and `TestGenZigTablesMatchVendoredGo` PASS against `lib/parser/parser.go` (`:19`) — run after slice 1, before slice 2 deletes `parser.go`. |
| Go-free full suite in CI | `.github/workflows/pr-tests.yml` | The `Remove Go from PATH` step logs at least one `dropping …` line and its `command -v go` assertion passes; `zig build test-all --summary all` (with `SKIP_WASM_E2E=1`, `:47-48`) is green on `ubuntu-latest` — the only run that proves the libc audit (Warning 1). |
| Tag-matrix cross-compiles | `.github/workflows/cli-tag.yml:19-40` (replayed locally) | `x86_64-linux-gnu`, `aarch64-macos`, `x86_64-windows-gnu` ReleaseFast builds of `circ-compile` succeed from one Zig install with no `CC`/`GOOS` plumbing; binaries exist at `zig-out/bin/circ-compile[.exe]`. |
| Size delta | `zig-out/bin/circ-compile` | Debug binary shrinks from 2,186,432 B (today, Go runtime linked via `parser.a`); ReleaseFast sizes for the three targets recorded in STATUS. |

Run command: `zig build test` after every edit (rebuilds the runtime and runs the 27-fixture translate suite, the new `parser_tests`, and every Node harness); `zig build test-all` before each commit; `zig build parser:gen && git diff --exit-code lib/parser/parser.zig` once per slice; `CIRC_ROOT=$PWD ~/circus/langlang/go/zig/scripts/diff-circ.sh -v` after slice 1. Single-module runs (`zig test lib/syntax/translate.zig`) cannot resolve `@import("parser")` — today they cannot resolve `parser/parser.h` either — so use `zig build test`.

## Open Questions / Spikes

- **Decided — no wasm-target twin in this phase.** The only `wasm_target` module graph today is the runtime (`build.zig:699-811`), which never imports `translate`. Phase 2's `build/frontend_modules.zig` calls `createParserModule(b, wasm_target, wasm_optimize)` alongside a wasm `translate_mod` twin for Phase 3's `libcirc.wasm`; the generated file needs no change for that (verified: `wasm32-freestanding` ReleaseSmall link of the fork's `wasm_entry.zig` against this exact `parser.zig` = 18,491 bytes, no libc).
- **Decided — libc audit outcome** (Warning 1): 25 `.linkLibC()` deleted, `:527` and `:1042` kept for `wasm_run.zig:12`, `golden_tests`' `.link_libc = true` untouched. `TODO(phase1)`: if the execution agent prefers zero `linkLibC()` lines, change `wasm_run.zig:12` to `.linux => @bitCast(std.os.linux.getpid()), else => @bitCast(std.c.getpid())` and drop the last two — only if `zig build test-emit` stays green on the Linux CI job in the same PR; otherwise leave for Phase 5's optional wiring slice.
- `TODO(phase1)`: **`diff-circ.sh` after `parser.go` is deleted.** The script hardcodes `CIRC_PARSER_GO="$CIRC_ROOT/lib/parser/parser.go"` (`:19`), so `TestGenZigTablesMatchVendoredGo` cannot run against post-slice-2 checkouts. Run the script after slice 1 and record the numbers in STATUS; for later reruns use `git show 3b84bcb:lib/parser/parser.go > /tmp/parser.go` and point the fork's test at it (a one-line `CIRC_PARSER_GO=${CIRC_PARSER_GO:-…}` default in the fork's script would make this an env override — a langlang-side change, not circ's).
- `TODO(phase1)`: **Exact `langlang -version` line for the gate.** Verified output today: `Version: v0.0.13-zig.2 (github.com/jeffersonmourak/langlang/go)`; `expect_stdout_match = "v0.0.13-zig.2"` is a substring match, so a later tag bump changes this one literal in `build.zig` and the `CLAUDE.md:26`/`README.md:41` install line together.
- `TODO(phase1)`: **Where `go` lives on `ubuntu-latest`.** The prune loop is location-agnostic (it drops any `PATH` directory holding an executable `go`), and the `command -v go` assertion is the real check; if the runner exposes `go` through a directory that also holds `node` or `zig`, replace the drop with a symlink farm (`$RUNNER_TEMP/nogo-bin` containing `zig`, `node`, `git`) and set `PATH` to that directory alone.
- Hard-failure `ParseFailure.message` wording (`Unexpected 'x'` / `Unexpected EOF` from `writeMessage`, `langlang_runtime.zig:470-498`, vs Go's `pe.Error()` fallback at `shim.go:71-73`) is unpinned by any test and unreachable with this grammar (Warning 4); no spike — Phase 0's `expected-analyze` goldens cover every reachable syntax diagnostic.
- None otherwise — decisions 1, 2 and 9 of `DOCS/PLANS_PROMPT.md` fix every other choice this phase makes.
