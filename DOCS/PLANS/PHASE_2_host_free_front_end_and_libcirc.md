# Phase 2 — Host-free front end, `lib/libcirc.zig` driver, native static library

> **Dependencies:** Phase 0 (the `Errors (n)` AST-dump section, the recovery fixtures, and `tests/analyze/analyze_golden_test.zig` with its `expected-analyze/*.json` goldens — this phase must leave them byte-identical) and Phase 1 (the langlang-generated `lib/parser/parser.zig`, a `parser` module imported by `translate_mod`, Go and `linkParserArchive` gone from `build.zig`). **PR #79 (`memories`) must be merged first**: every line number below that names `cmd/circ-compile/main.zig`, `lib/truth_table/builder.zig`, `lib/engine_session.zig`, `lib/analyze/analyze.zig`, or `build.zig` was read on the `memories` worktree (`/Users/jeffersonmourak/circus/worktrees/v0.0.3/memories`, HEAD `2e15e97`), which is the post-merge shape of those files. Phase 1 deletes `build.zig:9-12` and `:19-77` (the Go block), so `build.zig` line numbers after `:77` shift up by roughly 70 on the tree this phase edits — re-grep the anchors named in each row (`const circ_compile_mod`, `const analyze_mod`, `const build_info`, …) before editing.
> **Warnings:** (1) `main.zig` is the stderr/exit-code contract: `tests/cli/integration_test.zig` (20 tests, spawns `zig-out/bin/circ-compile` after running `zig build circ-compile` itself in `buildCli`, `:44-49`) and `tests/e2e/cli_e2e_test.zig` (5 tests) are frozen by `DOCS/PLANS_PROMPT.md` and must not change; the 99 in-process `test` blocks in `main.zig` (preview/truth-table goldens, `--mem` exit-2 messages, `--truth-table-cap` messages) are the finer guard and also stay untouched. Every label the CLI prints on a pipeline failure lives in one place after this phase (`frontend.Stage.cliLabel`) and is listed verbatim in Data & State. (2) **Type identity across module objects.** After `build/frontend_modules.zig` exists, the CLI, `libcirc`, and every test that imports `libcirc` must reach each front-end file through the helper's module object, never through the `build.zig` originals that the per-module tests keep using: `args.color` (`lib/cli/args.zig:13`, `ColorMode = render_color.ColorMode`) is passed straight into `preview_render.RenderOptions.color` (`main.zig:505`), and `sim_loop.Preload` (`lib/sim/loop.zig:17`) is passed into `truth_table_builder.BuildOptions.preloads` (`main.zig:555`) — a second `preview_render_color` or `engine_session` module object in the same compilation is a type error, and a second module for the same file is `file exists in modules 'x' and 'x0'`. The same rule already governs `build_options` (`build.zig:734-746`) and now governs `build_info`: materialise it once (`build_info.createModule()`) and `addImport` it into both the CLI and `libcirc`; today's `circ_compile_mod.addOptions("build_info", build_info)` (`build.zig:904`) must go. (3) **Overlay-first changes one observable thing on native**: `files[].path` for an overlay-keyed file is now the normalised overlay key, not `realpath` (`file_loader.zig:44`). For circ-lsp this is a fix — today an overlay for a file that *exists on disk* under a symlinked directory (`/var/x.circ` on macOS) is realpathed to `/private/var/x.circ` at `:44`, misses the `/var/x.circ` overlay key at `:51`, and the unsaved edits are silently ignored (a never-saved path takes the `FileNotFound` fallback at `:45` and still matches) — but it is a behaviour change under symlinked directories and must be written into `DOCS/analyze-api.md`. (4) `std.fs.path.resolve` (`file_loader.zig:70`) is `resolvePosix` on macOS/Linux, so the switch is byte-identical there; on Windows the joined path is now POSIX-normalised before `realpathAlloc`, which Windows accepts, and nothing tests Windows beyond `cli-tag.yml`'s build. (5) **Freestanding errors are analysis-time** (plan-prompt trap): the guards this phase adds — `color.zig:62`, `builder.zig:172,197`, `resolve_bodies.zig:327`, `file_loader.zig:4-8,44,72`, `log.zig:12` — are the known set from reading every `std.fs`/`std.posix`/`std.time`/`std.debug` reference under `lib/` (the grep in Persistence & I/O lists all 15 hits; `lib/sim/loop.zig` and `lib/emit/project.zig` are CLI-only and are never linked into `libcirc`). Phase 3 will surface any survivor. (6) `memory.reset()` is the one engine change; `bench-golden-gate.yml` hard-fails PRs whose counters drift, so `zig build bench` runs before the phase closes (the counter wrapper at `lib/memory.zig:23-62` is untouched by `reset`). (7) `lib/log.zig:12` builds its `wasmLogArena` **over `memory.allocator`**; once `memory.reset(.free_all)` exists, that arena's chunk list would dangle on wasm after the first reset — re-parent it to `std.heap.page_allocator` (which is `WasmAllocator` on wasm32, `std/heap.zig:346-352` — the same backing `lib/memory.zig:65` already uses) in the guard slice, before Phase 3 can hit it. (8) A `u32` cannot hold a 64-bit pointer: the C ABI is declared with `[*]u8`/`usize`, which *is* `i32` in the wasm32 export signature decision 3 describes and `uint8_t*`/`size_t` in `include/libcirc.h` on native (recorded in Open Questions). (9) `zig build libcirc` must name the artifact `"circ"` — `b.addLibrary` prefixes `lib`, so `.name = "circ"` yields `zig-out/lib/libcirc.a`. (10) The `--analyze` stdin contract (`{"root_path","overlays"}`, `DOCS/analyze-api.md:25-38`, the `AnalyzeRequest` interface at `circ-lsp/src/analyzer.ts:58-61`, spawned with `--analyze` at `:65` and written to stdin at `:83`) is **not** the libcirc request shape (`{"root","files","options"}`); `runAnalyze` (`main.zig:630-685`) keeps its own `std.json` parsing and its six `analyze: …` stderr strings and calls the Zig API, so nothing the LSP sees changes.

## Goal

A host program — a Zig test, a C program linked against `zig-out/lib/libcirc.a` with `zig-out/include/libcirc.h`, and in Phase 3 a wasm loader — hands the compiler an in-memory project (`{"root": "/playground/main.circ", "files": {"/playground/main.circ": "…", "/playground/dep.circ": "…"}, "options": {…}}`) and gets back exactly what the CLI prints today: `circ_compile` returns the self-contained `.wasm` bytes that `circ-compile in.circ -o out.wasm` writes (byte-identical, proven by comparing against the CLI in-process and by driving `expected-wasm` vectors through Node), `circ_preview` returns the `--preview --color=never` text, `circ_truth_table` returns the `--truth-table` markdown/CSV/JSON (with `rom` preloads), and `circ_analyze` returns the `--analyze` JSON, all with no disk access when every file is in the overlay — a root plus an overlay-only sibling import resolves without `E009`. Front-end errors come back as status `1` with `{"files":[…],"diagnostics":[…]}` in the analyze-api shape; a RAM-bearing or over-cap truth table is status `3` with the CLI's own message. `circ-compile` itself is re-based on the same Zig API and every stderr string, exit code, golden, and the import-free fast path are unchanged (`zig build test-all` green with no fixture touched).

## Scope

**In scope:**
- `lib/resolver/file_loader.zig` overlay-first (`decision 4`): `resolveImportPath` gains an `overlay` parameter, joins with `std.fs.path.resolvePosix`, returns the key when the overlay holds it, else `realpath` on native, else `error.FileNotFound` (so `scan_imports.zig:172-183` keeps emitting `E009`); `loadFileWithOverlay` consults the overlay by the normalised key *before* `realpathAlloc`; disk branches compiled out on `.freestanding`.
- Freestanding guards: `lib/preview/render/color.zig:62` (`.auto` is `false` on freestanding), `lib/truth_table/builder.zig:172,197` (`drive_ns = 0`), `lib/resolver/resolve_bodies.zig:327` (`std.debug.print` → `std.log.scoped(.resolver).warn`), `lib/log.zig:12` (arena re-parented); `lib/memory.zig` gains `pub fn reset()`.
- `build/frontend_modules.zig`: one function that creates the ~45 front-end module objects (parser through preview render) and the `libcirc` module; the CLI is re-wired onto it in the same slice (no behaviour change).
- `lib/libcirc.zig` + `lib/libcirc/{frontend,modes,json,c_api}.zig`: the Zig API (`frontend.run`, `modes.*`, `libcirc.{compile,preview,truthTable,analyze,version}`), the JSON request/response codec, and the ten `circ_*` exports with status codes 0–5.
- `cmd/circ-compile/main.zig` re-based on `libcirc.frontend`/`libcirc.modes` for compile, preview, truth-table, sim's topology build, and `--analyze`; `--inspect`, `--emit-zig`, `--sim`, `scanStrict`, `resolvePreloads`, and every message string stay in `main.zig`.
- `zig build libcirc` → `zig-out/lib/libcirc.a` + `zig-out/include/libcirc.h`; `zig build libcirc-smoke` compiles and runs `examples/c/analyze.c` against the archive.
- `tests/libcirc/driver_test.zig`, `tests/libcirc/c_api_test.zig`, a file-loader overlay-only sibling test, a `scan_imports` sibling test, an `analyze` inline sibling test, a `circuit.zig` `memory.reset` test, a `builder.zig` `drive_ns` test, `json.zig` inline tests.
- `DOCS/analyze-api.md` overlay semantics (the `overlays` bullet, `:38`) and the stale "Behavior on invalid input" section (`:72-81`) rewritten; `DOCS/libcirc-api.md` started (request, status codes, C ABI, memory model); CLAUDE.md build table rows; `DOCS/STATUS.md` entries.

**Explicitly deferred:**
- `lib/libcirc/wasm_root.zig`, `-Dwasm-optimize`, the wasm-target `runtime_embed` twin, `tests/harness/libcirc_loader.js`, size gates (Phase 3). `c_api.zig` is written target-agnostic (no `std.fs`, allocators via `std.heap.page_allocator`, which is `WasmAllocator` on wasm32 — `std/heap.zig:346-352`) so Phase 3 adds a root file, not a rewrite.
- `circ_inspect`, `--sim`, `--emit-zig` through the library (decision 10). `sim_loop` and `emit_*` modules are never imported by `libcirc`.
- Migrating the per-module *test* wiring in `build.zig` onto `build/frontend_modules.zig` (Phase 5 optional slice); this phase moves only the CLI and `libcirc`.
- Returning warnings on status 0 (the playground calls `circ_analyze` for them); `color: "auto"` in the library (rejected as status 2; the CLI keeps `.auto` with its real handle and `NO_COLOR`).
- `cli-tag.yml` shipping `libcirc.a` in the release matrix; `DOCS/decisions/libcirc.md` (Phase 5).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| build | `build/frontend_modules.zig` | `pub fn create(b: *std.Build, opts: Options) Modules` — creates, in dependency order, every module the front end needs (`parser` — through Phase 1's `createParserModule(b, target, optimize)` helper, never a second `createModule` over `lib/parser/parser.zig` —, `translate`, `ir_types`, `resolver`, `validator_codes`, `validator_diagnostics`, the 11 validator pass modules `name_resolution … unused_import, memory_validation, sub_circuit_validation` (`build.zig:186-274`), `validator_run`, `validator_run_project`, `builtins`, `file_loader`, `scan_imports`, `import_cycle`, `resolve_bodies`, `analyze`, `format`, `serializer`, `full_format`, `full_serializer`, `section_writer`, `circuit` (native, `build_options` via `opts.build_options_mod`), `engine_session`, `truth_table_builder/markdown/csv/json`, `preview_layout_types/sizing/collapse/columns/rows/place/route`, `preview_layout`, `preview_layout_orchestrator`, `preview_render_color/canvas/glyphs`, `preview_render`, `build_info` (materialised once from `opts.build_info`), and `libcirc` (root `lib/libcirc.zig`, importing all of the above plus `opts.runtime_embed`). Mirrors the `addImport` edges `build.zig` draws today (e.g. `analyze_mod` `:855-862`, `truth_table_builder_mod` `:1242-1244`, `preview_render_mod` `:1414-1418`, `preview_layout_orchestrator_mod` `:1431-1437`); note the native `format`/`serializer` modules are named `topology_format_tests_mod` (`:1062`) and `topology_serializer_tests_mod` (`:1072`, rooted at `lib/topology/serializer.zig` and already the CLI's `serializer` import at `:1092`) despite the `_tests` suffix — `format_mod_for_wasm` (`:790`) is the wasm-target twin and must not be reused natively. No `addTest`, no `addExecutable`, no `addOptions`. |
| libcirc | `lib/libcirc.zig` | Root of the `libcirc` module. Re-exports `frontend`, `modes`, `json`, and the wrapped modules the CLI still names (`pub const truth_table_builder = @import("truth_table_builder")`, `preview_render`, `analyzer`, `engine_session`, `diagnostics`, `ir_types`, `full_format`); defines `Request`, `File`, `Options`, `Status`, `Outcome`; `version()`/`writeVersionJson`; the four request-level entry points `analyze`, `compile`, `preview`, `truthTable` that compose `frontend` + `modes` + `json` into an `Outcome`. |
| libcirc | `lib/libcirc/frontend.zig` | `run(alloc, req, route, failure) FrontError!Front` — the pipeline lifted from `main.zig:266-331` (`parse → resolve → [scan → cycle → bodies → validator_run_project] | validator_run`) with the overlay built from `req.files` by `buildOverlay`; `Stage`, `Failure`, `Front`, `Route`. Never prints. |
| libcirc | `lib/libcirc/modes.zig` | Per-mode steps lifted from `main.zig:415-599`: `buildTopology`, `compile`, `layout`, `renderPreview`, `truthTablePreflight` + `Refusal`, `buildTruthTable`, `renderTruthTable`, `analyze`/`renderAnalysis` (thin over `analyze.zig:181,398`). Each takes a `?*Failure` and never prints. |
| libcirc | `lib/libcirc/json.zig` | `parseRequest(alloc, bytes) ParseError!Request` over `std.json.parseFromSlice(std.json.Value, …)` (the pattern at `main.zig:636-672`), `describe(ParseError)`, `writeError(writer, msg)`, `writeDiagnostics(alloc, writer, *const Front)`, `writeSyntaxFailure(alloc, writer, root, cause)`, `hexToBytes`. |
| libcirc | `lib/libcirc/c_api.zig` | The ten `export fn circ_*` with `callconv(.c)`; library-owned result buffer; per-call arena; `std_options` with a quiet `logFn` (this file is the root of `libcirc.a`, so its `std_options` is the one that counts). Imports only `libcirc`. |
| include | `include/libcirc.h` | Hand-written C header (Data & State), installed by `lib.installHeader(b.path("include/libcirc.h"), "libcirc.h")` (`std/Build/Step/Compile.zig:505`) to `zig-out/include/libcirc.h`. |
| examples | `examples/c/analyze.c` | 40-line smoke: builds the inverter request literal, calls `circ_version` then `circ_analyze`, prints both result buffers, exits non-zero on any status other than 0. Compiled and run by `zig build libcirc-smoke`. |
| tests | `tests/libcirc/driver_test.zig` | Imports `libcirc` **and** `circ_compile` (the CLI root module, whose `pub fn run` at `main.zig:233` is callable in-process) plus `golden`; proves library == CLI byte-for-byte per mode, drives `compile()` artifacts through Node the way `tests/e2e/section_writer_fixtures_test.zig:227-358` does. |
| tests | `tests/libcirc/c_api_test.zig` | Imports `libcirc_c_api` (the archive's root module) and `libcirc`; calls the `export fn`s directly, compares `circ_analyze` bytes with `analyzer.renderJson`, exercises every status code and the result-buffer lifetime. |
| docs | `DOCS/libcirc-api.md` | Request/response reference, status codes, the C ABI, the memory model (decision 5). Phase 3 appends the wasm loading section. |
| plans | `DOCS/PLANS/PHASE_2_host_free_front_end_and_libcirc.md` (this file) | Plan artifact. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| resolver | `lib/resolver/file_loader.zig` | `const builtin = @import("builtin"); const has_disk = builtin.os.tag != .freestanding;`. New `pub fn normalizeKey(alloc, path) ![]u8` = `std.fs.path.resolvePosix(alloc, &.{path})` (`std/fs/path.zig:698`, pure, no syscalls). `loadFileWithOverlay` (`:28-63`): builtin branch (`:29-39`) unchanged; then `key = normalizeKey(path)`; `if (overlay) |ov| if (ov.get(key)) |buf| return .{ .absolute_path = key, .source = dupe(buf) }`; `if (comptime !has_disk) return error.FileNotFound;` then today's realpath-with-`FileNotFound`-fallback (`:44-47`), a second overlay lookup by the realpath (keeps every existing caller's behaviour), then `readAbsoluteFileAlloc` (`:57`). `readAbsoluteFileAlloc` (`:4-8`) wrapped in `if (has_disk)`. `resolveImportPath(alloc, importing, import, overlay: ?Overlay)` (`:65-73`): builtin branch unchanged; `joined = resolvePosix(&.{ dirname(importing) orelse ".", import })` replaces `std.fs.path.resolve` (`:70`); `if (overlay) |ov| if (ov.contains(joined)) return joined;` `if (comptime !has_disk) return error.FileNotFound;` else `realpathAlloc(joined)` (`:72`). Doc comment on `Overlay` (`:17-22`): keys are normalised with `normalizeKey`. |
| resolver | `lib/resolver/scan_imports.zig` | `:172` passes `overlay` as the fourth argument. The only other caller is `tests/resolver/file_loader_test.zig:48`. `E009` path (`:173-181`) untouched. |
| analyze | `lib/analyze/analyze.zig` | `appendDiag` (`:99-116`) split: new `pub fn convertDiagnostics(alloc, items: []const diagnostics.Diagnostic) ![]Diagnostic` (used by `json.writeDiagnostics`), `appendDiag` calls it; `writeJsonString` (`:370`) becomes `pub` (used by `json.writeError`). New inline test `analyze: overlay-only sibling import resolves without E009` after the last test (`:660-686`; the file is 686 lines). `Analysis` (`:71-76`) unchanged. (Line numbers are the `memories` tree's; `main` has them 3 lower because PR #79 added `Symbol.addr_width` at `:57-59`.) |
| preview | `lib/preview/render/color.zig` | `shouldColor` `.auto` arm (`:59-63`): `if (comptime builtin.os.tag == .freestanding) break :blk false;` before `std.posix.isatty(handle)` (`:62`). `stdout_handle: ?std.fs.File.Handle` is `?void` on freestanding (`std/fs/File.zig:21`, `std/posix.zig:53`) and compiles as-is. |
| truth_table | `lib/truth_table/builder.zig` | `const has_clock = builtin.os.tag != .freestanding;` `:172` → `const drive_start: i128 = if (has_clock) std.time.nanoTimestamp() else 0;` `:197` → `const drive_ns: u64 = if (has_clock) @intCast(std.time.nanoTimestamp() - drive_start) else 0;` (`Table.drive_ns` `:69` doc updated: "0 on freestanding"). `nanoTimestamp`'s `else` arm calls `posix.clock_gettime` (`std/time.zig`), which the freestanding stub (`std/posix.zig:44-56`) lacks. |
| resolver | `lib/resolver/resolve_bodies.zig` | `:327` `std.debug.print(...)` → `std.log.scoped(.resolver).warn("specialization failed for '{s}': {s}", .{…})`. `std.debug.print` goes through `lockStderrWriter` → `File.stderr()` → `posix.STDERR_FILENO` (`std/debug.zig`, `std/fs/File.zig:192`), absent on freestanding. The CLI prefix becomes `warning(resolver): ` through `main.zig:15-28`'s `filteredLog`; `rg "specialization failed" tests/ cmd/` is empty, so no test pins the old text. |
| engine | `lib/memory.zig` | After `deinit` (`:73-75`): `pub fn reset() void { _ = arena.reset(.free_all); }` (`std/heap/arena_allocator.zig:102`; `deinit` takes the arena by value, `:51`, so it cannot be used for this). Doc: "only with no `Circuit`/`Session` alive; counters (`:23-62`) are not touched". |
| engine | `lib/log.zig` | `:12` `var wasmLogArena = std.heap.ArenaAllocator.init(memory.allocator);` → `.init(std.heap.page_allocator)` (Warning 7). |
| engine | `lib/circuit.zig` | Test section only: `test "memory.reset frees the arena and the allocator stays usable"`. |
| session | `lib/engine_session.zig` | Move `ImageError` (`loop.zig:23`), `IMAGE_READ_CAP` (`:27`), and `writeImageError(writer, err, mem, len)` (`:34-43`) here from `lib/sim/loop.zig` (they are pure formatters over `MemRef` + the codec's error set; `MemoryImageError` at `:22` comes along as `engine.memimage.MemoryImageError`); `loop.zig` re-exports them (`pub const writeImageError = engine_session.writeImageError;`) so `main.zig:154,165` and the two `loop.zig` call sites (`:238`, `:251`) are untouched. The test `writeImageError reasons` (`loop.zig:745-758`) moves with the function. Needed because `modes.truthTablePreflight` formats `bad_preload` reasons and `libcirc` must not import `sim_loop`. |
| sim | `lib/sim/loop.zig` | `:22-43` become re-exports (see above). No behaviour change; `serve`, verbs, the remaining tests untouched. |
| cli | `cmd/circ-compile/main.zig` | Imports: the 18 front-end imports among `:29-50` (`translate`, `resolver`, `validator_run`, `validator_run_project`, `scan_imports`, `import_cycle`, `resolve_bodies`, `serializer`, `full_serializer`, `section_writer`, `runtime_embed`, `layout_orchestrator`, `preview_render`, `truth_table_builder`, `truth_table_markdown`, `truth_table_csv`, `truth_table_json`, `analyze`) collapse to `const libcirc = @import("libcirc");` (`truth_table_builder.State/PinRef/Row/Table/BitVecState` in `scanStrict` `:81` and `synthTableForStrict` `:1922-1948` become `libcirc.truth_table_builder.*`); `cli_args` (`:2`), `diagnostics` (`:31`), `emit_main` (`:34`), `inspect_dump` (`:35`), `sim_loop` (`:51`), `build_info` (`:52`) and the inline `@import("ir_types")` (`:279`) stay; `preview_dump` (`:43`) is imported but never referenced — drop it together with `build.zig:1181`'s `addImport` (the `preview_dump_mod` tests stay). `run()`: `:266-331` replaced by one `libcirc.frontend.run(allocator, .{ .root = args.input_path, .files = &.{} }, route, &failure)` where `route` is `.single_module` for `.inspect`, `.project_if_imports` for `.compile`/`.emit_zig`, `.project` for `.preview`/`.truth_table`/`.sim` (exactly `needs_project_resolution`, `:286`); on error print `"{s}: {s}\n"` with `failure.stage.cliLabel()` and `@errorName(failure.cause)`, return 1; when `front.early_stop != null` (scan or cycle errors) print `front.diagnostics.items` to stderr via `printDiagnosticSet` and return 1 — today's `:293-296`/`:302-305`, reproduced for every mode including `.sim`. `maybe_project` → `front.project`, `ir_module` → `front.ir_module`, `ast_file` → `front.ast_file`, `diagnostic_list` → `front.diagnostics`. `.compile` arm (`:415-460`): `libcirc.modes.compile(allocator, &front, &failure)` then `writeFileAny`; on error `reportBackendError(stderr_writer, failure.stage.cliLabel(), failure.cause)` (same function `:183-190`, same labels). `.preview` arm (`:463-514`): `modes.buildTopology` → `modes.layout(allocator, topology, .{ .expand_macros, .expand_display }, &failure)` → the `--expand-display` warning loop (`:488-500`) verbatim → `modes.renderPreview(allocator, stdout_writer, grid, .{ .color = args.color, .stdout_handle = stdout_handle, .no_color_value = no_color, .expand_display })` (the CLI keeps `.auto`, the real handle, and `NO_COLOR`, `:502-503`). `.truth_table` arm (`:515-599`): `resolvePreloads` unchanged (`:529`); `modes.truthTablePreflight(allocator, topology, args.truth_table_cap, preloads)` returns `?Refusal` whose `writeCli(stderr_writer, .{ .flag = "--truth-table-cap", .cap_max = cli_args.truth_table_cap_max })` prints the two lines at `:534-537` and `:546-549` byte-for-byte; `modes.buildTruthTable` (`truth-table build failed: X` / `truth-table: preload failed`, `:556-563`); `modes.renderTruthTable(stdout_writer, table, args.truth_table_format, args.truth_table_value_format)` replaces the three `switch`es `:566-585`; `scanStrict` stays. `.sim` arm: `modes.buildTopology` replaces `:359-368`. `runAnalyze` (`:630-685`): parsing and the six `analyze: …` messages unchanged; `analyzer.analyze`/`renderJson` → `libcirc.modes.analyze`/`renderAnalysis`. |
| build | `build.zig` | (a) `build_info` (`:867-883`) gains `grammar_sha256` (hex of `std.crypto.hash.sha2.Sha256` over `GRAMMAR_FILE` read at configure time, `"unknown"` on failure) and `parser_runtime_sha256` (the 64 hex chars after `sha256=` on line 3 of `lib/parser/parser.zig`, `"unknown"` if absent); `build_info_mod = build_info.createModule()` once. (b) `const fe = @import("build/frontend_modules.zig").create(b, .{ .target, .optimize, .build_options_mod = circuit_options_default_mod, .build_info = build_info, .runtime_embed = runtime_embed_mod })` placed after `runtime_embed_mod` (`:821-826`). (c) `circ_compile_mod` (`:885-904`, plus the deferred `addImport`s at `:1092-1093`, `:1127`, `:1181`, `:1228`, `:1245`, `:1259`, `:1273`, `:1287`, `:1438-1439`) imports `libcirc` from `fe.libcirc` and every front-end name from `fe.*`; `addOptions("build_info", …)` → `addImport("build_info", fe.build_info)`. (d) CLI-only modules re-pointed at `fe.*` instances: `cli_args_mod` (`:569-574`, `render_color`), `cli_inspect_dump_mod` (`:575-583`), `emit_*_mod` (`:388-446`, their `ir_types`/`diagnostics`/… imports), `preview_dump_mod` (`:1174-1181`), `sim_protocol_mod`/`sim_loop_mod` (`:1205-1228`, `engine_session`, `circuit`, `full_format`). (e) `libcirc_c_api_mod` rooted at `lib/libcirc/c_api.zig` importing `fe.libcirc`; `const libcirc_lib = b.addLibrary(.{ .linkage = .static, .name = "circ", .root_module = libcirc_c_api_mod })` (`std/Build.zig:824-841`); `libcirc_lib.installHeader(b.path("include/libcirc.h"), "libcirc.h")`; `b.step("libcirc", "Build zig-out/lib/libcirc.a and zig-out/include/libcirc.h")` depending on `b.addInstallArtifact(libcirc_lib, .{})`. (f) `libcirc_smoke_exe` = `b.addExecutable` with `addCSourceFile(.{ .file = b.path("examples/c/analyze.c") })`, `linkLibrary(libcirc_lib)`, `linkLibC()`; `b.step("libcirc-smoke", …)` runs it via `b.addRunArtifact` with `expectExitCode(0)`. (g) `libcirc_driver_tests` (`tests/libcirc/driver_test.zig`; imports `libcirc = fe.libcirc`, `circ_compile = circ_compile_mod`, `golden`) and `libcirc_c_api_tests` (`tests/libcirc/c_api_test.zig`; imports `libcirc_c_api`, `libcirc`), both `test_step.dependOn` and `dependOn(&install_runtime.step)` like `run_circ_compile_tests` (`:925`). (h) Nothing under `zig build bench` changes (`:1649-1704` keeps its own `bench_circuit_mod`). |
| tests | `tests/resolver/file_loader_test.zig` | `:48` gains the `null` overlay argument; three new tests (Tests table). |
| tests | `tests/resolver/scan_imports_test.zig` | One new test: root + overlay-only sibling scans without `E009` (5 tests today, `:20-75`). |
| docs | `DOCS/analyze-api.md` | `:38` (the `overlays` bullet) rewritten: keys are normalised with `resolvePosix`, consulted before disk, sibling imports resolve inside the overlay, `files[].path` is the key; the `:72-81` "Behavior on invalid input" section rewritten to what `appendSyntaxDiags` (`analyze.zig:144-179`) does since recovery landed: one `syntax` diagnostic per recovered `ErrorMark` (`:166-178`), a located one on hard failure (`:148-164`), none for blank sources (`:145`), remove the "future work / Stage 7" sentence. |
| docs | `CLAUDE.md`, `README.md` | Build table gains `zig build libcirc` and `zig build libcirc-smoke`; "Files worth knowing about" gains `lib/libcirc.zig`. |
| plans | `DOCS/STATUS.md` | One entry per slice (plan-prompt template). |

**New dependencies:** None. Everything is `std` (`std.json`, `std.fs.path.resolvePosix`, `std.crypto.hash.sha2.Sha256`, `std.heap.ArenaAllocator.reset`). `examples/c/analyze.c` needs only `<stdio.h>`/`<string.h>` and is compiled by Zig's own C compiler.

## Data & State

Interfaces this phase **consumes** unchanged: `translate.parseSource(alloc, file_id, source) !ast.File` (`lib/syntax/translate.zig:761`, frozen), `resolver.resolve(alloc, file, file_id)` (`lib/ir/resolver.zig:284`), `scan_imports.scanProjectImportsWithOverlay(alloc, root, ?Overlay) !ScanResult` (`:95-99`), `import_cycle.analyzeImports(alloc, file_paths, import_table) !AnalyzeResult` (`:66`), `resolve_bodies.resolveBodiesWithOverlay(alloc, file_paths, import_table, topo_order, *DiagnosticList, ?Overlay) !ir.Project` (`:394-401`), `validator_run.run(alloc, *const Module)` / `validator_run_project.run(alloc, *const Project)` (`lib/validator/run.zig:15`, `run_project.zig:7`), `serializer.serializeModule/serializeProject` (`lib/topology/serializer.zig:5,159`), `full_serializer.buildFromProject/buildFromModule/serializeProjectFull/serializeModuleFull` (`:409,445,436,529`), `section_writer.combineTwo(alloc, runtime, min, full) ![]u8` (`:86-91`), `runtime_embed.runtime_wasm`, `orchestrator.build(arena, topology, layout.LayoutOptions) !LayoutGrid` (`lib/preview/layout/orchestrator.zig:14-18`), `preview_render.render(arena, writer, grid, RenderOptions)` with `RenderOptions{ color, stdout_handle, no_color_value, expand_display }` (`lib/preview/render.zig:16-25,47`), `truth_table_builder.{BuildOptions{max_input_bits, preloads}, BuildError, firstRamName, countInputBits, build, Table}` (`builder.zig:78-209`), `truth_table_{markdown,csv,json}.render(writer, table, ValueFormat)` (`markdown.zig:156`, `csv.zig:99`, `json.zig:92`), `engine_session.{Preload, MemRef, collectMemories, validateImage}` (`:17-68`), `analyzer.{analyze, renderJson, Analysis, Overlay}` (`analyze.zig:181,398,71,23`), `diagnostics.{Diagnostic, DiagnosticList, formatDiagnosticLine}` (`lib/validator/diagnostics.zig:23-31,54`), `format.VERSION`/`full_format.FULL_VERSION` (both `0x03`, `format.zig:4`, `full_format.zig:5`), `build_info.{version, revision}`, `parser.runtime.{langlang_version, abi_version}` (generated header `:24-27`).

```zig
// lib/resolver/file_loader.zig — signatures after this phase
pub const Overlay = std.StringHashMapUnmanaged([]const u8);            // unchanged type (:22); keys normalised
pub fn normalizeKey(allocator: std.mem.Allocator, path: []const u8) ![]u8; // std.fs.path.resolvePosix(allocator, &.{path})
pub fn loadFileWithOverlay(allocator, path: []const u8, overlay: ?Overlay) !LoadedFile; // overlay(key) → [native: realpath → overlay(realpath) → disk] → FileNotFound
pub fn resolveImportPath(allocator, importing_file_path: []const u8, import_path: []const u8, overlay: ?Overlay) ![]u8;
```

```zig
// lib/memory.zig
/// Releases every byte the engine arena holds. Legal only when no
/// `Circuit`/`Session` is alive; `libcirc.truthTable` calls it after the
/// table is rendered. `COLLECT_METRICS` counters are untouched.
pub fn reset() void { _ = arena.reset(.free_all); }
```

```zig
// lib/libcirc.zig
pub const File = struct { path: []const u8, text: []const u8 };
pub const Color = enum { never, always };                         // no `auto`: the library has no TTY
pub const TableFormat = enum { markdown, csv, json };              // = cli_args.TruthTableFormat, by value
pub const ValueFormat = enum { binary, hex, decimal };
pub const Options = struct {
    expand_macros: bool = false,          // preview
    expand_display: bool = false,         // preview
    color: Color = .never,                // preview
    format: TableFormat = .markdown,      // truth table
    value_format: ValueFormat = .binary,  // truth table
    truth_table_cap: u8 = 16,             // truth table; 1..24 (cli_args.truth_table_cap_max)
    preloads: []const engine_session.Preload = &.{}, // truth table, by declared root memory name
    warnings_as_errors: bool = false,     // compile/preview/truth table: W* → status 1
};
pub const Request = struct {
    root: []const u8,                     // key into `files`, or (native) a disk path
    files: []const File = &.{},           // the overlay; keys normalised by file_loader.normalizeKey
    options: Options = .{},
};
pub const Status = enum(u32) { ok = 0, diagnostics = 1, bad_request = 2, refused = 3, out_of_memory = 4, internal = 5 };
pub const Outcome = struct { status: Status, body: []const u8 };  // body from the caller's allocator
pub const Version = struct {
    version: []const u8,            // build_info.version           ("0.0.2")
    revision: []const u8,           // build_info.revision          ("2e15e97")
    topology_version: u8,           // format.VERSION               (3)
    full_version: u8,               // full_format.FULL_VERSION     (3)
    parser: []const u8,             // "langlang " ++ parser.runtime.langlang_version ++ " abi=" ++ abi  ("langlang go/v0.0.12 abi=1")
    parser_runtime_sha256: []const u8, // build_info.parser_runtime_sha256 (header line 3 of lib/parser/parser.zig)
    grammar_sha256: []const u8,     // build_info.grammar_sha256
};
pub fn version() Version;
pub fn writeVersionJson(writer: anytype) !void;   // one line, keys in the order above, no trailing newline
pub fn analyze(alloc, req: Request) std.mem.Allocator.Error!Outcome;     // 0 → analyze-api JSON; 2/5
pub fn compile(alloc, req: Request) std.mem.Allocator.Error!Outcome;     // 0 → .wasm bytes; 1 → diagnostics JSON; 5
pub fn preview(alloc, req: Request) std.mem.Allocator.Error!Outcome;     // 0 → text; 1; 3 (layout); 5
pub fn truthTable(alloc, req: Request) std.mem.Allocator.Error!Outcome;  // 0 → table; 1; 3 (preload/ram/cap); 5; calls memory.reset() after render
```

```zig
// lib/libcirc/frontend.zig
pub const Route = enum { single_module, project_if_imports, project };  // inspect | compile, emit_zig | preview, truth_table, sim, analyze
pub const Stage = enum {
    root_load, parse, resolve, import_scan, import_cycle, body_resolution, project_validation, validation,
    topology_build, topology_serialization, full_topology_serialization, wasm_assembly,
    layout_build, render, truth_table_build,
    /// Exactly the strings main.zig prints today (:267,:272,:290,:299,:315,:320,:327,:361/:465/:518,:419,:433,:450,:480,:510/:587,:560);
    /// `.root_load` is the one label the CLI never reaches (its pre-read at :257-264 exits 2 first) — it reuses :262's wording.
    pub fn cliLabel(self: Stage) []const u8 {
        return switch (self) {
            .root_load => "failed reading input file", .parse => "parse failed", .resolve => "resolve failed", .import_scan => "import scan failed",
            .import_cycle => "import cycle analysis failed", .body_resolution => "body resolution failed",
            .project_validation => "project validation failed", .validation => "validation failed",
            .topology_build => "topology build failed", .topology_serialization => "topology serialization failed",
            .full_topology_serialization => "full topology serialization failed", .wasm_assembly => "wasm assembly failed",
            .layout_build => "layout build failed", .render => "render failed", .truth_table_build => "truth-table build failed",
        };
    }
};
pub const Failure = struct { stage: Stage, cause: anyerror };
pub const FrontError = error{ RootLoadFailed, ParseFailed, ResolveFailed, ImportScanFailed, ImportCycleFailed, BodyResolutionFailed, ProjectValidationFailed, ValidationFailed, OutOfMemory };
pub const Front = struct {
    root_key: []const u8,                 // file_paths[0]
    ast_file: ast.File,
    ir_module: ir.Module,                 // single-module resolve of the root (main.zig:271)
    project: ?ir.Project,                 // null ⇔ the import-free fast path was taken
    file_paths: []const []const u8,       // scan_result.file_paths, or &.{root_key} on the fast path
    diagnostics: diagnostics.DiagnosticList, // scan ∪ cycle ∪ bodies ∪ validator, in that order
    early_stop: ?Stage,                   // .import_scan / .import_cycle when those had errors (main.zig:295,:304)
    errors: usize, warnings: usize,       // = countDiagnostics(diagnostics.items) (main.zig:192-202)
    pub fn deinit(self: *Front, alloc) void; // diagnostics.deinit only (as main.zig:323,:331)
};
pub fn buildOverlay(alloc, files: []const File) !file_loader.Overlay;   // put(normalizeKey(path), text)
pub fn run(alloc, req: Request, route: Route, failure: ?*Failure) FrontError!Front;
// run: overlay = buildOverlay(req.files); root = file_loader.loadFileWithOverlay(req.root, overlay) [.root_load → error.RootLoadFailed;
//      the request-level entry points map a .root_load failure to status 2, body {"error":"failed reading input file: <ErrName>"} —
//      unreachable from the CLI, whose :257-264 pre-read already exited 2]
//      ast = parseSource(0, root.source) [.parse]; module = resolver.resolve [.resolve];
//      project route ⇔ route == .project or (route == .project_if_imports and ast.imports.len > 0);
//      project: scan [.import_scan] → if errors { early_stop=.import_scan; return } → cycle [.import_cycle] → if errors {…}
//               → bodies [.body_resolution] → validator_run_project [.project_validation]
//      else:   validator_run [.validation]
```

```zig
// lib/libcirc/modes.zig
pub const Failed = error{ Failed, OutOfMemory };   // details in *Failure
pub fn buildTopology(alloc, front: *const Front, failure: ?*Failure) Failed!full_format.FullTopology; // buildFromProject | buildFromModule (.topology_build)
pub fn compile(alloc, front: *const Front, failure: ?*Failure) Failed![]u8;  // serializeProject|Module → serializeProjectFull|ModuleFull → combineTwo(runtime_embed.runtime_wasm, min, full)
pub fn layout(alloc, topology, opts: layout_types.LayoutOptions, failure: ?*Failure) Failed!layout_types.LayoutGrid; // .layout_build
pub fn renderPreview(alloc, writer: anytype, grid, opts: preview_render.RenderOptions) !void;                         // .render
pub const Refusal = union(enum) {
    stateful_ram: []const u8,                                    // firstRamName
    too_many_bits: struct { bits: u32, cap: u8 },                // countInputBits > cap
    bad_preload: struct { name: []const u8, reason: []const u8 },// unknown name or codec reason (engine_session.writeImageError text)
    pub const CliText = struct { flag: []const u8, cap_max: u8 };
    /// stateful_ram → "truth-table: ram '<n>' is stateful (its clk/we would be enumerated as inputs and rows would depend on visiting order); use --sim to drive it"
    /// too_many_bits → "truth table requires <bits> input bits, exceeds cap of <cap> (raise with <flag>, max <cap_max>)"
    /// bad_preload   → "truth-table: preload '<name>': <reason>"
    pub fn write(self: Refusal, writer: anytype, text: CliText) !void;   // no trailing newline (the CLI adds it)
};
/// Order matches main.zig:529-551: preloads, then ram, then cap.
pub fn truthTablePreflight(alloc, topology, cap: u8, preloads: []const engine_session.Preload) !?Refusal;
pub fn buildTruthTable(alloc, topology, opts: truth_table_builder.BuildOptions, failure: ?*Failure) Failed!truth_table_builder.Table;
pub fn renderTruthTable(writer: anytype, table, format: TableFormat, value_format: ValueFormat) !void;
pub fn analyze(alloc, root: []const u8, overlay: ?analyzer.Overlay) !analyzer.Analysis;   // = analyzer.analyze
pub fn renderAnalysis(writer: anytype, a: analyzer.Analysis) !void;                       // = analyzer.renderJson
```

```zig
// lib/libcirc/json.zig
pub const ParseError = error{ InvalidJson, NotAnObject, MissingRoot, RootNotString, FilesNotObject, FileTextNotString, FileKeyNotAbsolute, OptionsNotObject, BadOption, PreloadNotHex, CapOutOfRange, OutOfMemory };
pub fn parseRequest(alloc, bytes: []const u8) ParseError!Request;
pub fn describe(err: ParseError) []const u8;     // e.g. MissingRoot → "request missing 'root'", FileKeyNotAbsolute → "files keys must be absolute paths", CapOutOfRange → "options.truth_table_cap must be 1..24", BadOption → "unknown or mistyped option"
pub fn writeError(writer, message: []const u8) !void;                 // {"error":"<escaped>"}
pub fn writeDiagnostics(alloc, writer, front: *const Front) !void;    // analyzer.renderJson(.{ files = front.file_paths, diagnostics = analyzer.convertDiagnostics(front.diagnostics.items), symbols = &.{}, references = &.{} })
pub fn writeSyntaxFailure(alloc, writer, root: []const u8, cause: anyerror) !void; // files=[{0,root}], one {"severity":"error","code":"syntax","range":{1,1,1,2},"message":"parse failed: <ErrName>"}
```

Request JSON (C ABI; every field but `root` optional; unknown option keys → status 2):

```json
{"root": "/playground/main.circ",
 "files": {"/playground/main.circ": "import ha \"half_adder.circ\"\n…", "/playground/half_adder.circ": "…"},
 "options": {"expand_macros": false, "expand_display": false, "color": "never",
             "format": "markdown", "value_format": "binary", "truth_table_cap": 16,
             "preloads": {"code": "00112233445566778899aabbccddeeff"}, "warnings_as_errors": false}}
```

Status → result buffer, per export:

| Export | 0 | 1 | 2 | 3 | 5 |
|---|---|---|---|---|---|
| `circ_version` | `{"version":"0.0.2","revision":"…","topology_version":3,"full_version":3,"parser":"langlang go/v0.0.12 abi=1","parser_runtime_sha256":"…","grammar_sha256":"…"}` | — | — | — | — |
| `circ_analyze` | `analyzer.renderJson` bytes (trailing `\n` as today) | — | `{"error":"…"}` (parse) | — | `{"error":"analyze: <ErrName>"}` |
| `circ_compile` | the `.wasm` bytes (`combineTwo` output) | `{"files":[…],"diagnostics":[…],"symbols":[],"references":[]}` when `front.errors > 0` or (`warnings_as_errors` and `warnings > 0`), or the syntax-failure shape on `.parse` | request errors, incl. a `.root_load` failure (`{"error":"failed reading input file: FileNotFound"}` when `root` is neither a `files` key nor, natively, a readable path) | — | `{"error":"<cliLabel>: <ErrName>"}` |
| `circ_preview` | render text (`color` per options) | same as compile | same | `{"error":"layout build failed: <ErrName>"}` | other stages |
| `circ_truth_table` | markdown/csv/json text | same as compile | same | `Refusal.write` text with `.{ .flag = "options.truth_table_cap", .cap_max = 24 }` | `truth-table build failed: …`, `render failed: …` |

Status 4 is produced only by `c_api.zig` when any `error.OutOfMemory` escapes the Zig API (result buffer empty).

```c
/* include/libcirc.h — hand-written, installed to zig-out/include/libcirc.h */
#ifndef LIBCIRC_H
#define LIBCIRC_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define CIRC_STATUS_OK 0            /* result = artifact bytes / text / JSON        */
#define CIRC_STATUS_DIAGNOSTICS 1   /* result = {"files":[…],"diagnostics":[…],…}   */
#define CIRC_STATUS_BAD_REQUEST 2   /* result = {"error":"…"}                       */
#define CIRC_STATUS_REFUSED 3       /* result = {"error":"…"} (cap, ram, preload, layout) */
#define CIRC_STATUS_OUT_OF_MEMORY 4 /* result empty                                 */
#define CIRC_STATUS_INTERNAL 5      /* result = {"error":"<stage>: <ErrName>"}      */
uint8_t *circ_alloc(size_t len);                      /* request buffers; caller frees with circ_free */
void circ_free(uint8_t *ptr, size_t len);
uint32_t circ_version(void);
uint32_t circ_analyze(const uint8_t *req, size_t len);
uint32_t circ_compile(const uint8_t *req, size_t len);
uint32_t circ_preview(const uint8_t *req, size_t len);
uint32_t circ_truth_table(const uint8_t *req, size_t len);
const uint8_t *circ_result_ptr(void);                 /* library-owned; valid until the next circ_* call */
size_t circ_result_len(void);
uint32_t circ_reset(void);                            /* drops the result buffer, the call arena, and the engine arena (memory.reset) */
#ifdef __cplusplus
}
#endif
#endif
```

```zig
// lib/libcirc/c_api.zig — root module of libcirc.a (Phase 3 imports it from wasm_root.zig)
pub const std_options: std.Options = .{ .log_level = .warn, .logFn = quietLog }; // quietLog: drop everything (no stderr on any target)
var result_buf: std.ArrayListUnmanaged(u8) = .{};                        // std.heap.page_allocator-owned
var call_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);  // reset(.retain_capacity) at the start of every circ_* call
export fn circ_alloc(len: usize) callconv(.c) ?[*]u8;                    // page_allocator.alloc(u8, len)
export fn circ_free(ptr: [*]u8, len: usize) callconv(.c) void;
export fn circ_version() callconv(.c) u32;
export fn circ_analyze(req: [*]const u8, len: usize) callconv(.c) u32;   // dispatch(libcirc.analyze)
export fn circ_compile(req: [*]const u8, len: usize) callconv(.c) u32;
export fn circ_preview(req: [*]const u8, len: usize) callconv(.c) u32;
export fn circ_truth_table(req: [*]const u8, len: usize) callconv(.c) u32;
export fn circ_result_ptr() callconv(.c) [*]const u8;
export fn circ_result_len() callconv(.c) usize;
export fn circ_reset() callconv(.c) u32;                                 // result_buf free, call_arena.reset(.free_all), circuit.memory.reset(); returns 0
// dispatch: arena reset → json.parseRequest (ParseError → 2, body = writeError(describe)) → entry(arena, req) (OutOfMemory → 4)
//           → result_buf.replaceRange(body) → @intFromEnum(status)
```

```zig
// build/frontend_modules.zig
pub const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_mod: *std.Build.Module,   // circuit_options_default.createModule(), made once in build.zig (:744-746)
    build_info: *std.Build.Step.Options,    // materialised here exactly once
    runtime_embed: *std.Build.Module,       // the WriteFiles-backed module from build.zig (:815-826)
};
pub const Modules = struct {
    parser: *Module, translate: *Module, ir_types: *Module, resolver: *Module,
    validator_codes: *Module, diagnostics: *Module, validator_run: *Module, validator_run_project: *Module,
    builtins: *Module, file_loader: *Module, scan_imports: *Module, import_cycle: *Module, resolve_bodies: *Module,
    analyze: *Module, format: *Module, serializer: *Module, full_format: *Module, full_serializer: *Module, section_writer: *Module,
    circuit: *Module, engine_session: *Module,
    truth_table_builder: *Module, truth_table_markdown: *Module, truth_table_csv: *Module, truth_table_json: *Module,
    preview_layout_types: *Module, preview_layout: *Module, preview_layout_orchestrator: *Module, // + sizing/collapse/columns/rows/place/route
    preview_render_color: *Module, preview_render_canvas: *Module, preview_render_glyphs: *Module, preview_render: *Module,
    build_info: *Module, libcirc: *Module,
};
pub fn create(b: *std.Build, opts: Options) Modules;
```

## Execution & Concurrency Model

This phase is fully synchronous. No background threads or workers are introduced. Each `circ_*` call runs the whole pipeline on the caller's thread and returns; the C ABI is **not** thread-safe — `result_buf`, `call_arena`, and the engine arena (`lib/memory.zig:65`) are process globals, and the header says so. Ownership: request bytes belong to the caller (`circ_alloc`/`circ_free`); every allocation a call makes comes from `call_arena` (reset with `.retain_capacity` at the start of the next call, so the previous `Outcome.body` is dead the moment a new call begins — which is why `dispatch` copies the body into `result_buf` before returning); engine nodes come from `memory.allocator` during `buildTruthTable` only, are freed by `build`'s `defer circuit.deinit()` (`builder.zig:160`), and the arena itself is rewound by `memory.reset()` at the end of `libcirc.truthTable` (after `renderTruthTable`, when the `Table`, which lives in the caller arena, no longer references any engine object) and by `circ_reset`. The Zig API takes an explicit allocator for everything but the engine (CLAUDE.md invariant 6). The CLI keeps its single process-lifetime arena (`main.zig:604-606`) and never calls `memory.reset` (it exits). Log routing: `main.zig` remains the CLI root (its `filteredLog`, `:15-28`, still gates `.log`-scope engine noise in `--truth-table`); `c_api.zig` is the archive's root and its `quietLog` drops everything, so a host never sees engine logs on its stderr; in tests the test runner's default log is in effect, and the resolver warning at `resolve_bodies.zig:327` is a `warn` so it would still print there — it is unreachable on any fixture.

## Persistence & I/O

Disk access after this phase, by file, on native:

- `lib/resolver/file_loader.zig` — the **only** place the front end reads source from disk: `realpathAlloc` (`:44`, `:72`) and `openFileAbsolute`+`readToEndAlloc` (`:4-8`), all behind `has_disk`. The 15 host-only references under `lib/` (excluding `lib/parser/`, which Phase 1 replaces) are (from `grep -rn 'nanoTimestamp\|std\.debug\.print\|isatty\|std\.fs\.\|getEnvVar\|std\.process\.' lib/`): `truth_table/builder.zig:172,197`; `sim/loop.zig:235,267,716` (CLI-only, never in `libcirc`); `preview/render.zig:18` and `preview/render/color.zig:53` (type only, `?void` on freestanding), `color.zig:62`; `resolver/resolve_bodies.zig:327`; `resolver/file_loader.zig:5,44,69,70,72` (`:69` `std.fs.path.dirname` and `:70` `resolve` are pure); `emit/project.zig:193` (`std.fs.path.basename`, pure, and CLI-only anyway). Of those, the 6 that need a guard are `builder.zig:172,197`, `color.zig:62`, `resolve_bodies.zig:327`, `file_loader.zig:5` (+ `:44`, `:72`); this is the complete list the Phase 2 guards cover.
- `cmd/circ-compile/main.zig` — unchanged I/O: the root pre-read `:257-264` (kept so `input file not found: <path>` / `failed reading input file: <err>` exit 2 exactly as today, before the frontend re-reads the root through the loader the way `scan_imports.zig:120` already does), `writeFileAny` (`:64-75`), `--mem` images (`:147`), stdin for `--analyze` (`:631`) and `--sim` (`:373`), `NO_COLOR` (`:502`), stdout TTY handle (`:503`).
- `build.zig` — reads `VERSION` (`:869`), runs `git rev-parse` (`:872-876`), and now reads `lib/grammar/proto-circ.peg` and the first three lines of `lib/parser/parser.zig` at configure time.
- The library itself never opens a file, never reads an environment variable, never writes anything: `circ_preview` runs with `stdout_handle = null` and `no_color_value = null`, so `shouldColor` (`color.zig:52-66`) sees only `.always`/`.never`. A request whose `files` do not cover an import falls back to disk on native (this is what makes the CLI's `files = &.{}` request and circ-lsp's partial overlays work) and to `error.FileNotFound` → `E009` on freestanding.
- No new persistence. `DOCS/STATUS.md` is appended by the execution agent.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Overlay-first file loader | `file_loader.zig` per the Modified-files row (`normalizeKey`, overlay before realpath, `resolveImportPath(…, overlay)` with `resolvePosix`, `has_disk` gates); `scan_imports.zig:172` passes `overlay`; `file_loader_test.zig:48` updated; new tests in `file_loader_test.zig`, `scan_imports_test.zig`, and `analyze.zig`; `analyze.zig` also gains `pub fn convertDiagnostics` and `pub fn writeJsonString` (mechanical, needed by slice 4). Commit: `fix(resolver): consult the overlay before realpath in the file loader`. | `resolveImportPath overlay-only sibling returns the key` (overlay `{"/virtual/dep.circ"}`, importing `/virtual/root.circ`, import `"dep.circ"` → `"/virtual/dep.circ"`, no `FileNotFound`); `resolveImportPath normalises dot segments` (`"./sub/../dep.circ"` → `"/virtual/dep.circ"`); `resolveImportPath disk sibling still realpaths` (`tests/fixtures/projects/two_file/root.circ` + its import → absolute path equal to `std.fs.cwd().realpathAlloc`); `loadFileWithOverlay hits the overlay for a never-saved key` (no disk); `scan imports resolves an overlay-only sibling without E009` (files.len == 2 + 5 builtins, diagnostics empty); `analyze: overlay-only sibling import resolves without E009` (root imports `dep.circ`, both in the overlay; no `E009`, `files` contains `/virtual/dep.circ`); `zig build test` green; Phase 0 `expected-analyze` goldens and every `expected-diagnostics` snapshot byte-identical (`git status` shows only the six files above). |
| 2 | Freestanding guards and `memory.reset` | `color.zig:62`, `builder.zig:172,197`, `resolve_bodies.zig:327`, `log.zig:12`, `memory.zig` `reset()`, `circuit.zig` test, `engine_session.zig` gains `ImageError`/`IMAGE_READ_CAP`/`writeImageError` with `sim/loop.zig:21-50` re-exporting them. Commit: `refactor: guard host-only calls for freestanding builds and add memory.reset`. | `memory.reset frees the arena and the allocator stays usable` in `lib/circuit.zig` (build an `and` circuit, `deinit`, `memory.reset()`, `queryCapacity` of the arena is 0, build again and propagate `1 & 1 == 1`); `truth_table_build_records_drive_ns_on_native` (`table.drive_ns > 0` for the 256-row multi-bit fixture at `builder.zig:345`); `color_resolution_auto_no_tty` unchanged; `zig build test` green; `zig build bench` counters byte-identical to `tests/fixtures/bench/engine.bench.golden`; the four `expected-sim` transcripts (`tests/sim/golden_test.zig`) and the `--mem` exit-2 tests in `main.zig:1294-1385` (`truth_table_mem_unknown_name_exits_2`, `sim_mem_unknown_name_exits_2_before_handshake`, `sim_mem_missing_file_and_bad_image_exit_2`, `usage_error_for_too_many_mem_flags`) unchanged (the formatter moved, not changed). |
| 3 | Shared front-end module graph | `build/frontend_modules.zig`; `build.zig` (a)–(d) and (h) from the Modified-files row (the `libcirc` module is created with an empty `lib/libcirc.zig` containing only the re-exports and `version()`, so the graph is complete); `build_info` gains `grammar_sha256`/`parser_runtime_sha256`. Commit: `build: share the front-end module graph through build/frontend_modules.zig`. | `zig build test-all` green with no source change outside `build/`, `build.zig`, `lib/libcirc.zig`; `zig build circ-compile` and `tests/cli/integration_test.zig` unchanged; `sha256sum zig-out/bin/circ-compile` before/after may differ (link order) but `circ-compile --version` output is identical; `zig build --help` lists no new step yet. |
| 4 | The Zig driver | `lib/libcirc/frontend.zig`, `modes.zig`, the four entry points and `Outcome` in `lib/libcirc.zig`, `json.writeDiagnostics`/`writeSyntaxFailure` (the response half of `json.zig`); `tests/libcirc/driver_test.zig` wired into `test`. Commit: `feat(libcirc): add the host-free driver for compile, preview, truth table, analyze`. | The driver tests in the Tests section: preview/truth-table/compile equal the in-process CLI byte-for-byte over the fixture tables; `expected-wasm` vectors pass through Node for five fixtures; status-1 JSON for `E001_undeclared.circ`; syntax-failure JSON for an empty root; refusals for `ram_basic.circ`, an 8-bit input under `truth_table_cap = 4`, a bad preload; two consecutive `truthTable` calls (proves `memory.reset`); `zig build test` green. |
| 5 | CLI on libcirc | `cmd/circ-compile/main.zig` per the Modified-files row; `build.zig` (c) already done, so only `main.zig` and its imports change. Commit: `refactor(cli): dispatch compile, preview, truth-table and analyze through libcirc`. | `zig build test-all` green; `git status` shows only `main.zig` (and `build.zig` if an import edge was missed); `tests/cli/integration_test.zig` (20), `tests/e2e/cli_e2e_test.zig` (5), all 99 `main.zig` tests, every `preview/renders`, `truth_table`, `expected-sim`, `expected-wasm` golden byte-identical; `rg -n '"[a-z -]* failed"' cmd/circ-compile/main.zig` shows only the generic `"{s}: {s}\n"` print plus `failed writing zig output`/`failed writing wasm output`/`strict scan failed`/`failed reading`/`sim:`/`analyze:` (the strings that were never stage labels); the perf smoke (`integration_test.zig:360`) still passes with `front.project == null` on `stress_grid_10x10.circ` (assert via a new `main.zig` test `compile fast path takes no project route` that calls `libcirc.frontend.run` with `.project_if_imports` on that fixture and checks `project == null`). |
| 6 | JSON codec and the C ABI | `json.parseRequest`/`describe`/`writeError`/`hexToBytes` with inline tests; `lib/libcirc/c_api.zig`; `tests/libcirc/c_api_test.zig` wired into `test`. Commit: `feat(libcirc): JSON request codec and the circ_* C ABI`. | The `json` and `c_api` tests in the Tests section; `zig build test` green. |
| 7 | `zig build libcirc` and the C smoke | `build.zig` (e)–(f); `include/libcirc.h`; `examples/c/analyze.c`. Commit: `build: emit libcirc.a and include/libcirc.h from zig build libcirc`. | `zig build libcirc` produces `zig-out/lib/libcirc.a` and `zig-out/include/libcirc.h`; `zig build libcirc-smoke` exits 0 and prints the version JSON followed by the analyze JSON for the inverter (the run step asserts exit 0; STATUS records the printed lines); `nm zig-out/lib/libcirc.a | grep ' T circ_'` lists exactly the ten names; `zig build test-all` still green; sizes of the archive recorded in STATUS. |
| 8 | Docs | `DOCS/analyze-api.md` rewrites, `DOCS/libcirc-api.md`, CLAUDE.md/README rows. Commit: `docs: describe overlay-first analysis and start the libcirc API reference`. | `cli_args_help_text_mentions_every_mode_and_flag` unchanged (no CLI text touched); the request example in `libcirc-api.md` is the literal used by `examples/c/analyze.c` (a `c_api_test` case `c_api: the documented request literal compiles` parses the same bytes, so doc and code cannot drift). |

Slices are ordered by dependency. Each slice must be fully reviewable on its own. Slice 3 before 4 keeps the build refactor separable from behaviour; slice 5 depends on 4's `modes` surface and is the one whose diff must show zero fixture changes.

## Tests

Fixture inventory used below (all existing on the post-#79 tree, counted with `ls | wc -l`): 43 `expected-wasm/*.txt` vectors (the 43 `circuit_fixtures` rows at `section_writer_fixtures_test.zig:360-415`), 26 `preview/renders/*.golden` (25 plain renders + `single_gate.render.color.golden`; all 26 are referenced from `main.zig`), 58 `truth_table/*.golden` (51 `*.truth.golden`, of which `main.zig` drives 48, + `builtin_xor.{csv,json}.golden` + the five `and_4bit_truth.*` goldens) incl. `rom_lookup.truth.golden` with `tests/fixtures/mem/rom_lookup.bin`, 44 `expected-diagnostics/*.txt`, 44 `projects/*` directories. No new fixture files are added by this phase.

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `resolveImportPath overlay-only sibling returns the key` | `tests/resolver/file_loader_test.zig` | Overlay with `/virtual/dep.circ`; `resolveImportPath(alloc, "/virtual/root.circ", "dep.circ", overlay)` == `"/virtual/dep.circ"`. |
| `resolveImportPath normalises dot segments` | same | `"./sub/../dep.circ"` from `/virtual/root.circ` → `"/virtual/dep.circ"`; `"../x.circ"` from `/virtual/a/root.circ` → `"/virtual/x.circ"`. |
| `resolveImportPath disk sibling still realpaths` | same | `two_file/root.circ` + its import string → equals `std.fs.cwd().realpathAlloc(...)` of the sibling; a missing sibling → `error.FileNotFound`. |
| `loadFileWithOverlay hits the overlay for a never-saved key` | same | `/nowhere/x.circ` in overlay → `absolute_path == "/nowhere/x.circ"`, source equal; not in overlay → `error.FileNotFound`. |
| `resolveImportPath leaves builtin paths absolute-virtual` | same (`:43-51`, the call at `:48` gains `null`) | unchanged assertion with the extra `null`. |
| `scan imports resolves an overlay-only sibling without E009` | `tests/resolver/scan_imports_test.zig` | `file_paths.len == 7` (root, dep, 5 builtins), `import_table[0].target_file == 1`, `diagnostics.items.len == 0`. |
| `analyze: overlay-only sibling import resolves without E009` | `lib/analyze/analyze.zig` | No diagnostic with code `E009`; `files` contains `/virtual/dep.circ`; a reference with `hover == "dep"` exists. |
| `memory.reset frees the arena and the allocator stays usable` | `lib/circuit.zig` | See slice 2. |
| `truth_table_build_records_drive_ns_on_native` | `lib/truth_table/builder.zig` | `drive_ns > 0` on the 256-row fixture. |
| `writeImageError reasons` | `lib/engine_session.zig` (moved from `loop.zig:745-758`) | The four reason strings unchanged (`length 3 is not a multiple of 2 byte(s)`, `5 words exceed capacity 4`, `a word has bits set beyond data width 12`, `image exceeds 16 MiB`). |
| `json: parses the full request` | `lib/libcirc/json.zig` | The documented literal → `root`, 2 files (keys normalised), every option field; `preloads.code` decoded to 16 bytes. |
| `json: each error has a message` | same | `"["` → `InvalidJson`; `{}` → `MissingRoot`; `{"root":1}` → `RootNotString`; `files:[]` → `FilesNotObject`; a relative key → `FileKeyNotAbsolute`; `"color":"auto"` → `BadOption`; `"truth_table_cap":25` → `CapOutOfRange`; `"preloads":{"a":"0g"}` → `PreloadNotHex`; every `describe` non-empty. |
| `json: writeError escapes` | same | message `a"b\n` → `{"error":"a\"b\n"}` (uses `analyzer.writeJsonString`). |
| `c_api: circ_version is status 0 with the version JSON` | `tests/libcirc/c_api_test.zig` | Status 0; body parses with `std.json`; `full_version == 3`, `topology_version == 3`, `version == build_info.version`, `grammar_sha256` is 64 hex chars. |
| `c_api: circ_analyze equals analyzer.renderJson` | same | Request over the inline `and` source `analyze.zig:467` already uses (`input a\ninput b\nand g(a=a, b=b)\noutput out(in=g.out)\n`) keyed `/virtual/and.circ`; body bytes == `renderJson(analyzer.analyze(alloc, "/virtual/and.circ", overlay))`. |
| `c_api: bad request statuses` | same | `"not json"` → 2 with `{"error":"invalid request JSON: …"}`; `{}` → 2 `request missing 'root'`; relative key → 2. |
| `c_api: circ_compile returns a wasm module` | same | Status 0; `body[0..4] == "\x00asm"`; `WebAssembly` custom sections not checked here (driver_test does). |
| `c_api: diagnostics status carries E001` | same | `E001_undeclared.circ` text → 1; body contains `"code":"E001"` and `"symbols":[]`. |
| `c_api: truth table ram refusal is status 3` | same | `ram_basic.circ` text → 3; body `{"error":"truth-table: ram 'data' is stateful (…); use --sim to drive it"}`. |
| `c_api: result buffer is replaced by the next call` | same | After `circ_version`, `circ_result_len` > 0; after `circ_compile`, `circ_result_ptr` differs or len differs, and the first body is no longer readable through the API. |
| `c_api: alloc/free round trip and reset` | same | `circ_alloc(1024)` non-null, writable, `circ_free`; `circ_reset()` == 0, then `circ_version()` == 0 again; `circ_result_len() == 0` right after reset. |
| `c_api: the documented request literal compiles` | same (slice 8) | The literal in `DOCS/libcirc-api.md` (kept as a string constant in the test) → `circ_compile` status 0. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|--------|----------------|
| `driver: version reports topology 3 and the grammar sha` | `tests/libcirc/driver_test.zig` | `libcirc.version().full_version == 3`; `grammar_sha256` equals `Sha256` over `lib/grammar/proto-circ.peg` read by the test. |
| `driver: preview equals the CLI for every render golden` | same | For each of the 26 `preview/renders/*.golden` fixtures used by `main.zig` (`chain`, `builtin_xor`, `builtin_xnor`, `single_gate`, `rom_basic`, `ram_basic`, `multibit_*`, `mixed_width_preview`, `led_*` with/without `--expand-display`, `fan_out`, `fan_in`, `multi_led`, `and_of_not`, `clean_gated_feedback`, `parallel_leftward_detours`, `regression_led_out_drives_gate`, `edge_single_component`, `full_adder_from_builtins` + `builtin_xor`/`xnor` with `--expand-macros`): `libcirc.preview(.{ .root = path, .options = .{ .color = .never, .expand_macros, .expand_display } }).body` == `circ_compile.run(&.{"circ-compile", path, "--preview", …})` stdout == the golden (`golden.expectGolden`). Also `--color=always` on `single_gate` equals `single_gate.render.color.golden`. |
| `driver: truth table equals the CLI for every table golden` | same | Markdown for the 48 `*.truth.golden` fixtures `main.zig` drives (`expectTruthTableGolden`, defined `:1440`, called `:1460-1915`, plus the `rom_basic`/`rom_lookup` tests at `:1243-1291`); `builtin_xor.csv/json`; `and_4bit_truth.{binary,hex,decimal}.md`, `.hex.csv`, `.hex.json`; `rom_lookup` with `preloads = &.{ .{ .name = "code", .bytes = <tests/fixtures/mem/rom_lookup.bin> } }` == `rom_lookup.truth.golden`; `rom_basic` unloaded == `rom_basic.truth.golden`. |
| `driver: truth table refusals` | same | `ram_basic` → status 3, body == the CLI's stderr line minus `\n`; `and_4bit_truth` with `truth_table_cap = 4` → 3, `truth table requires 8 input bits, exceeds cap of 4 (raise with options.truth_table_cap, max 24)`; preload `nope` → 3 `truth-table: preload 'nope': no memory named 'nope' (declared memories: rom code[8, 4])`; 17-byte image → 3 `… 17 words exceed capacity 16`. |
| `driver: compile equals the CLI artifact byte-for-byte` | same | For `inverter`, `and_gate`, `full_adder_from_builtins`, `alu_4bit_multibit`, `rom_lookup`, `projects/full_adder/root.circ`: `libcirc.compile(...).body` == the file `run(... "-o", tmp)` wrote. |
| `driver: compile artifact drives expected-wasm vectors` | same | The five single-file fixtures above (incl. `rom_lookup`'s `mem` preamble) instantiated in Node with the script generator copied from `section_writer_fixtures_test.zig:262-334` (env stubs `debugEnabled`/`onDebugLog` at `:273`; the `mem` preamble → `memBuffer`/`memLoad` loop at `:287-301`); stdout equals the expected vector lines. Skips with a printed `SKIPPED` when `node --version` fails (`checkNodeAvailable`, `:148-157`). |
| `driver: analyze equals renderJson` | same | `libcirc.analyze` body == `renderJson(analyzer.analyze(...))` for `tests/fixtures/projects/two_file/root.circ` (disk fallback) and for the in-memory sibling pair. |
| `driver: status 1 result is analyze-api shaped` | same | `E001_undeclared.circ` → status 1; body parses; `diagnostics[0].code == "E001"`, `files[0].path` ends with the fixture path; `W001_unused_input.circ` → status 0, and status 1 with `warnings_as_errors = true`. |
| `driver: an empty root is a syntax failure` | same | `files = {"/v/e.circ": ""}` → status 1; one diagnostic `code == "syntax"`, `message == "parse failed: ParsingFailed"`, range `1:1-1:2`. |
| `driver: consecutive truth tables survive memory.reset` | same | `truthTable` on `alu_4bit` twice; both bodies equal the golden; `queryCapacity` of the engine arena is 0 between calls (exposed as `memory.arenaCapacityForTest()` only under `@import("builtin").is_test`). |
| `driver: root plus overlay-only sibling compiles` | same | `files = {"/p/root.circ": <text of projects/full_adder/root.circ>, "/p/half_adder.circ": <text of its sibling>}` → `compile` status 0 with no `E009`; the bytes equal what the CLI writes for the same two texts copied into a `tmpDir` (`run(&.{…, "<tmp>/root.circ", "-o", out})`), since `.full` records carry `target_file` ids, not paths (`full_serializer.zig:409-529`). |
| `compile fast path takes no project route` | `cmd/circ-compile/main.zig` | See slice 5. |
| `libcirc-smoke` | `zig build libcirc-smoke` | `examples/c/analyze.c` linked against `libcirc.a` exits 0 (run step asserts). |
| Existing suites | whole tree | `zig build test-all` green; `git status` after slice 5 shows no file under `tests/fixtures`. |

Run command: `zig build test` (the `libcirc` driver and C-ABI test binaries are aggregated there and need Node on `PATH` for the vector replay), then `zig build test-all` and `zig build bench` before the final slice; `zig build libcirc && zig build libcirc-smoke` for the archive. `zig test tests/libcirc/driver_test.zig` alone cannot resolve its `--dep` imports (same as every module test in this repo).

## Open Questions / Spikes

- **Pointer width in the C ABI.** Decision 3 says "`u32` ptr/len" for `libcirc.a`; a `u32` cannot hold a 64-bit pointer, so the exports are declared `[*]u8`/`usize` (`uint8_t*`/`size_t` in the header). On wasm32 `usize` is 32-bit, so the Phase 3 export signature is exactly `(i32, i32) -> i32` as decision 3 describes; the wording in `DOCS/decisions/libcirc.md` (Phase 5) should say "pointer-sized". Flagged for the reviewer at slice 6.
- `TODO(phase2)`: `Version.parser` reads `parser.runtime.langlang_version` (`"go/v0.0.12"` in the generated header — the upstream tag the fork pins, not the fork's `v0.0.13-zig.2`). If Phase 1's vendored file exposes the fork version under another name, use that; otherwise the runtime sha (`parser_runtime_sha256`) is the skew signal and the field stays as specified.
- `TODO(phase2)`: `driver: root plus overlay-only sibling compiles` compares against a CLI run over a `tmpDir` copy of the same two files; if `origin` frames or the `.full` section embed anything path-derived that differs between `/p/` and the tmp path, compare the `.min` custom section only and note it. Reading `full_serializer.zig:409-529`, records carry `target_file` ids, not paths, so byte equality is expected.
- Decided here, flagged for review: `color: "auto"` in a request is status 2 rather than silently `never`, and warnings are not returned on status 0 (`circ_analyze` is the warnings channel). Both are one-line changes if the playground wants otherwise.
- Decided here, flagged for review: a root that is neither a `files` key nor (natively) a readable path is `Stage.root_load` → status 2 `{"error":"failed reading input file: <ErrName>"}`, reusing the CLI's `:262` wording; the CLI never reaches it because its own pre-read (`main.zig:257-264`) exits 2 first with `input file not found: <path>` / `failed reading input file: <err>`.
- Cross-phase consistency: `DOCS/PLANS/PHASE_3_libcirc_wasm.md` restates the ABI with `circ_reset() void`; this phase declares `circ_reset() u32` (returns 0) so every export has the same `u32` status shape. Phase 2 owns `c_api.zig` and `include/libcirc.h`; Phase 3's "signatures unchanged from Phase 2" clause means the `u32` form wins and the Phase 3 listing is corrected when that spec is executed.
- None otherwise — decisions 3, 4, 5, and 10 in `DOCS/PLANS_PROMPT.md` fix every other choice this phase makes.
