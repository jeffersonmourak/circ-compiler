# Phase 3 — `zig build libcirc-wasm`: freestanding module, Node harness, size budget

> **Dependencies:** Phase 1 (the langlang-generated `lib/parser/parser.zig` — there is no Go route to `wasm32-freestanding`) and Phase 2 (the host-free front end: `file_loader.zig` overlay-first, the freestanding guards in `color.zig`/`builder.zig`/`resolve_bodies.zig`, `lib/memory.zig` `pub fn reset()`, `lib/libcirc.zig` + `lib/libcirc/{frontend,modes,json,c_api}.zig`, `build/frontend_modules.zig`, and the ten `circ_*` exports already proven natively by `tests/libcirc/c_api_test.zig`). Both phases land after PR #79 (`memories`) merges; every `build.zig` line below is the **post-merge** number from the `memories` worktree, with the `main` number in parentheses where they differ.
> **Warnings:** (1) The runtime follows the global `-Doptimize` (`build.zig:725`, `:711` on main: "follow global optimize option") and is unstripped: 933,072 B Debug vs 19,628 B ReleaseSmall on `main` (47×, almost all DWARF and name sections). `-Dwasm-optimize` must land in slice 1 before any size number is written into STATUS. (2) `build_options` is materialised once (`build.zig:744-746`, comment at `:734-743`) — the wasm graph imports `circuit_options_default_mod` by object; **`build_info` is still `addOptions`-style at `:904`** (`circ_compile_mod.addOptions("build_info", build_info)`), so Phase 2 must have switched it to `build_info.createModule()` once and passed that object to every importer: the error "file exists in modules 'build_info' and 'build_info0'" fires inside any single compilation that reaches the options file through two `Module` objects (the CLI importing libcirc's `version()` while still calling `addOptions` itself is the case that bites; the wasm graph is a separate compilation and only needs the shared object). (3) Freestanding failures are analysis-time (Zig 0.15.1 `std/posix.zig:44-56` stubs `fd_t = void`; `std.log.defaultLog` at `std/log.zig:145-157` calls `std.debug.lockStderrWriter` (`std/debug.zig:214`) → `std.Progress.lockStderrWriter` (`std/Progress.zig:651`, whose `stderr_file_writer` global at `:641` is initialised with `File.stderr()`) → `std/fs/File.zig:192` → `posix.STDERR_FILENO` (`std/posix.zig:110`), which the freestanding `system` stub does not define — a compile error, not a link error): the library root **must** install `std_options.logFn` or the first `std.log.err` in the graph fails analysis. Today no file under `lib/` calls `std.log` (only `lib/log.zig` names the type); the one caller arrives when Phase 2 turns `resolve_bodies.zig:327`'s `std.debug.print` into scoped `std.log`, and `std.log.log` (`std/log.zig:122-124`) only invokes `logFn` for levels that pass `logEnabled`, so `.log_level = .err` compiles every `info`/`debug` call out and `logFn` need only swallow `err`. (4) `lib/log.zig:7-8` declares `extern fn onDebugLog`/`debugEnabled`; on wasm `log.enabled()` is always true (`:108-111`) and `printOnBrowser` **formats into `memory.allocator` before asking `debugEnabled()`** (`:45-52`), so linking `circuit.zig` for truth tables (a) adds two `env` imports the harness and worker must stub (`tests/harness/loader.js:14-19`) and (b) grows the global arena on every engine log line until `memory.reset()`. (5) `std.heap.page_allocator` **is** `WasmAllocator` on wasm (`std/heap.zig:346-353`), so `lib/memory.zig:65`'s arena already sits on the right allocator; `arena.reset(.free_all)` hands its buffers back to WasmAllocator's free lists, which is what keeps the 50-compile test bounded — but `Component.deinit`/`Circuit.deinit` must have run first (plan-prompt trap: `deinit` takes the arena by value). (6) `WebAssembly.Memory.buffer` detaches on every `memory.grow`: a `Uint8Array` view taken before a `circ_*` call is stale after it; the loader re-reads `exports.memory.buffer` for every copy. (7) Linux Node fails the runtime's `init()` (`tests/e2e/topology_protocol_test.zig:8-13`; `.github/workflows/pr-tests.yml:41-48` sets `SKIP_WASM_E2E=1`) — `init_impl` swallows its own errors (`templates/main.zig:30-48`: every `catch` is a bare `return`), so "hang" is a silent `runtime_initialized == false`. Do not claim CI coverage for `libcirc.wasm`; every new test honours `SKIP_WASM_E2E`. (8) `topology_protocol_tests_mod.addImport("format", format_mod_for_wasm)` at `build.zig:842` (`:828`) imports a **wasm-target** module into a native test; once that module is ReleaseSmall+strip it still links, but slice 1 re-points it at a native `format` module so the native test is not silently built from a stripped ReleaseSmall unit. (9) `wasm-opt` exists on this machine (`/usr/local/bin/wasm-opt`) but is not a build dependency; `wasm-strip` is absent. All stripping is Zig's `Module.strip` (`std/Build/Module.zig:20,545` → `-fstrip`). (10) The renderer/site are not touched here; `site/public/wasm/*.wasm` (11 files, ~921 KB each) stay Debug until Phase 4 regenerates them.

## Goal

A developer runs `zig build libcirc-wasm` and gets `zig-out/lib/libcirc.wasm`: one `wasm32-freestanding` module, ReleaseSmall and stripped by default, whose export section is exactly `memory` plus the ten `circ_*` names of decision 3, whose only imports are `env.debugEnabled` and `env.onDebugLog`, and which embeds the same `circ-runtime.wasm` bytes the CLI of that build embeds. `zig build test` (macOS, Node 24) instantiates it in Node, compiles the inverter, `four_bit_adder`, `slice_basic`, and the two-file `projects/full_adder` from an in-memory `{root, files}` request, instantiates the returned artifact bytes with the topology host protocol and drives their `expected-wasm` vectors to the expected outputs, proves that analyze / preview / truth-table / compile results are byte-identical to the native `circ_*` functions for five fixtures, gets status `1` plus analyze-shaped JSON for an `E004` source, status `2` for malformed JSON and status `3` for a 17-bit truth table, shows that 50 repeated compiles and 50 repeated truth tables leave `memory.buffer.byteLength` where it was after the fifth call, and fails if the module exceeds 3 MB while logging its raw and gzip sizes. `-Dwasm-optimize=<mode>` governs both wasm builds independently of `-Doptimize`, and `DOCS/libcirc-api.md` documents the module, the request/response protocol, the status codes, the memory contract, and the Node/browser loading recipe so Phase 4 can write the worker from the doc alone.

## Scope

**In scope:**
- `-Dwasm-optimize` (`std.builtin.OptimizeMode`, default `.ReleaseSmall`) and a derived `wasm_strip = wasm_optimize != .Debug`, applied to all eight wasm-target modules at `build.zig:722-795` (`:708-780`) and to the new libcirc graph; the runtime artifact keeps `entry = .disabled` + `rdynamic = true` (`:807-808`).
- A native `topology_format_native_mod` for `tests/e2e/topology_protocol_test.zig` (Warning 8).
- `runtime_embed_wasm_mod`: a second `createModule` over the same `embed_zig_file` (`build.zig:817-819`) with `wasm_target`, so `libcirc.wasm` embeds byte-for-byte the runtime just built.
- `lib/libcirc/wasm_root.zig` (root of `libcirc.wasm`): `std_options` with a silent `logFn` and `log_level = .err`; a `comptime` anchor that takes the address of each of the ten `c_api` exports; nothing else.
- `lib/libcirc/c_api.zig` adjustments (Phase 2 owns the file; this phase adds only what wasm needs): backing allocator chosen by `builtin.target.cpu.arch.isWasm()` (`std.heap.wasm_allocator` on wasm, `std.heap.page_allocator` natively), a per-call `ArenaAllocator` over it, a library-owned result buffer replaced on every call, `memory.reset()` after `truthTable` returns (no `Circuit`/`Session` alive: `builder.zig:159-161` deinit the circuit before returning).
- `lib/log.zig:45-52`: check `debugEnabled()` **before** formatting (one reorder; stops disabled engine logs from allocating).
- `build.zig`: `libcirc_wasm_mod` (root `wasm_root.zig`, `export_symbol_names` = the ten names), `b.addExecutable(.{ .name = "libcirc" })` with `entry = .disabled` and **no** `rdynamic`, installed to `zig-out/lib/libcirc.wasm`, step `libcirc-wasm`; a `libcirc_wasm_embed` module for the test; `run_libcirc_wasm_tests` on the `test` step.
- `tests/harness/libcirc_loader.js` (env stubs as `loader.js:14-19`, a `circ` helper that owns the alloc/copy/call/read protocol) and `tests/e2e/libcirc_wasm_test.zig` with the tests listed under Tests.
- `tests/e2e/linux-docker/run.sh` gains `WASM_OPTIMIZE`/`NODE_IMAGE` pass-through and a `drive-libcirc.mjs` step, used by the bounded bisect slice; findings recorded in STATUS and in the comments at `topology_protocol_test.zig:8-13` / `pr-tests.yml:41-46`.
- `DOCS/libcirc-api.md` completed; CLAUDE.md and README build tables gain `zig build libcirc-wasm` and `-Dwasm-optimize`.

**Explicitly deferred:**
- Unskipping `SKIP_WASM_E2E` in `pr-tests.yml` — only if slice 5 root-causes the Linux failure; otherwise proof stays macOS-only (plan-prompt trap).
- `site/scripts/build-libcirc.ts`, `libcirc.manifest.json`, the worker, and regenerating `site/public/wasm` (Phase 4).
- `circ_inspect`, `--sim`, `--emit-zig` through the library (decision 10).
- Any `wasm-opt`/`wasm-strip` post-processing; `import_memory`/`max_memory` linker limits (`std/Build/Step/Compile.zig:44-52`) — the page decides memory policy, the module does not.
- Moving the native test wiring onto `build/frontend_modules.zig` (Phase 5's optional slice).
- Decision records (`DOCS/decisions/libcirc.md`, Phase 5).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| libcirc | `lib/libcirc/wasm_root.zig` | Root source of `libcirc.wasm`. Declares `pub const std_options: std.Options = .{ .log_level = .err, .logFn = silentLog }` (silences every `std.log` call reachable from the front end; `lib/log.zig` on wasm never touches `std.log`, it calls the `env` imports) and `comptime { _ = &c_api.circ_alloc; … _ = &c_api.circ_reset; }` (ten lines) so each export is analysed even though `c_api.zig` is not the root file; `--export=<name>` then fails the link loudly if any is missing. No allocator, no state, no other decls. |
| harness | `tests/harness/libcirc_loader.js` | `node tests/harness/libcirc_loader.js <libcirc.wasm> <script_base64>` (same argv contract as `tests/harness/loader.js:4-12`). Instantiates with `{ env: { debugEnabled: () => 0, onDebugLog: () => {} } }`, builds the `circ` helper (Data & State), runs `new Function("circ", "wasm", "mod", script)`; `process.exit(1)` with the stack on any throw (`loader.js:31-35`). |
| e2e | `tests/e2e/libcirc_wasm_test.zig` | The Node-driven proof for `libcirc.wasm`: writes the embedded module and a runner script into `std.testing.tmpDir`, spawns Node, compares stdout/files against native `c_api` results and `expected-wasm` vectors. Skips under `SKIP_WASM_E2E=1` or without `node` (copy of `topology_protocol_test.zig:7-40`). |
| e2e | `tests/e2e/linux-docker/drive-libcirc.mjs` | Container-side script for slice 5: loads `/test/libcirc.wasm`, compiles `/test/inverter.circ` via `circ_compile`, instantiates the result and drives `a=0→1`, `a=1→0` exactly like `drive-inverter.mjs:36-62` (same `env` stub set as `:17-26`, same two `console.log` lines and exit check). |
| docs | `DOCS/PLANS/PHASE_3_libcirc_wasm.md` (this file) | Plan artifact. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| build | `build.zig` | Next to `optimize` (`:17`): `const wasm_optimize = b.option(std.builtin.OptimizeMode, "wasm-optimize", "Optimize mode for circ-runtime.wasm and libcirc.wasm (default ReleaseSmall)") orelse .ReleaseSmall; const wasm_strip: bool = wasm_optimize != .Debug;`. The eight wasm-target modules — `runtime_module` `:722`, the `compiled.zig` dummy `:728`, `circuit_mod_for_wasm` `:748`, `memory_mod_for_wasm` `:755`, `transport_mod_for_wasm` `:764`, `log_mod_for_wasm` `:770`, `interpreter_mod_for_wasm` `:784`, `format_mod_for_wasm` `:790` (`:708-780` on main) — get `.optimize = wasm_optimize, .strip = wasm_strip`; the `:725` comment is replaced. Before `:836`: `const topology_format_native_mod = b.createModule(.{ .root_source_file = b.path("lib/topology/format.zig"), .target = target, .optimize = optimize });` and `:842` becomes `topology_protocol_tests_mod.addImport("format", topology_format_native_mod);`. After `runtime_embed_mod` (`:821-825`): `const runtime_embed_wasm_mod = b.createModule(.{ .root_source_file = embed_zig_file, .target = wasm_target, .optimize = wasm_optimize, .strip = wasm_strip });`. After Phase 2's native `frontend_modules.create(...)` call: the wasm graph (Data & State), `libcirc_wasm_mod`, `libcirc_wasm` artifact, `install_libcirc_wasm` (`.dest_dir = .{ .override = .{ .custom = "lib" } }`, the runtime's pattern at `:811-813`), `const libcirc_wasm_step = b.step("libcirc-wasm", "Build libcirc.wasm (wasm32-freestanding, -Dwasm-optimize)")`, a `libcirc_wasm_embed_mod` (WriteFiles copy of `libcirc_wasm.getEmittedBin()` as `libcirc.wasm` + `pub const wasm = @embedFile("libcirc.wasm");`, the `:815-825` pattern), `libcirc_wasm_tests` importing `libcirc_wasm_embed`, the native `c_api` module, `serializer` (`topology_serializer_tests_mod`, as `:1507`), `scan_imports`/`import_cycle`/`resolve_bodies`/`validator_run_project`/`diagnostics` (as `:1502-1506`), with `run_libcirc_wasm_tests.step.dependOn(&install_libcirc_wasm.step)` and `test_step.dependOn(&run_libcirc_wasm_tests.step)` next to `:1009`. |
| libcirc | `lib/libcirc/c_api.zig` | Backing allocator by target; per-call arena; result buffer ownership; `memory.reset()` after the truth-table path; status `4` when the arena or the result copy fails with `OutOfMemory`. Signatures unchanged from Phase 2 (Data & State restates the ABI). |
| engine | `lib/log.zig` | `printOnBrowser` (`:45-52`): `if (!debugEnabled()) return;` before `printType.format(...)`. Native path (`:87-90`) untouched; no golden or bench counter can move (the bench links the native logger). |
| e2e | `tests/e2e/linux-docker/run.sh` | `:23` → `zig build -Doptimize=ReleaseFast "-Dwasm-optimize=${WASM_OPTIMIZE:-ReleaseSmall}" "-Dtarget=x86_64-linux-gnu" circ-compile libcirc-wasm`; stage `zig-out/lib/libcirc.wasm` and `drive-libcirc.mjs` next to the five existing `cp` lines (`:34-38`); `docker build` (`:46-48`) gains `--build-arg "NODE_IMAGE=${NODE_IMAGE:-node:22-bookworm-slim}"`. |
| e2e | `tests/e2e/linux-docker/Dockerfile` | `:6` `FROM node:22-bookworm-slim` → `ARG NODE_IMAGE=node:22-bookworm-slim` / `FROM ${NODE_IMAGE}`; `COPY libcirc.wasm /test/libcirc.wasm`, `COPY drive-libcirc.mjs /test/drive-libcirc.mjs` next to `:10-13`. |
| e2e | `tests/e2e/linux-docker/container-e2e.sh` | New block `--- libcirc ---` after `--- node drive ---` (`:38-39`): `node /test/drive-libcirc.mjs /test/libcirc.wasm /test/inverter.circ`. |
| e2e | `tests/e2e/topology_protocol_test.zig` | Comment at `:8-13` rewritten with slice 5's finding (or "still open, matrix results in STATUS <date>"); code unchanged. |
| ci | `.github/workflows/pr-tests.yml` | Comment at `:41-46` updated the same way; `SKIP_WASM_E2E: "1"` stays unless slice 5 root-causes the failure. |
| docs | `DOCS/libcirc-api.md` | Completed (Persistence & I/O lists the sections). |
| docs | `CLAUDE.md`, `README.md` | Build-command table: `zig build libcirc-wasm` row; a `-Dwasm-optimize` sentence under the table ("default ReleaseSmall + strip for both wasm artifacts; `-Dwasm-optimize=Debug` keeps names and DWARF for bisecting"). |
| plans | `DOCS/STATUS.md` | One entry per slice (plan-prompt template), including measured sizes. |

**New dependencies:** None. Node stays a test-time prerequisite (already required by `zig build test`, `pr-tests.yml:36-38`); Docker remains optional (`zig build e2e-linux-docker`, `build.zig:1717-1725`).

## Data & State

Interfaces this phase **consumes** (fixed by earlier phases): the ten-export C ABI of decision 3 as Phase 2 declares it in `lib/libcirc/c_api.zig`; the request JSON `{ "root": "<key>", "files": { "<key>": "<text>" }, "options": { … } }` with keys normalised by `std.fs.path.resolvePosix` (decision 4); Phase 2's `build/frontend_modules.zig`; `runtime_embed`'s `runtime_wasm` (`build.zig:817-819`); the topology host protocol (`DOCS/wasm-api.md` §"Exports": `topology_alloc` → copy → `init` → `setPin`/`run`/`getOutputValue`/`getOutputDefined`); `expected-wasm/*.txt` vectors (`section_writer_fixtures_test.zig:51-72` `parseAssignment`: MSB-first `0/1/?` state tokens; post-merge line numbers throughout, the file gained a `mem` preamble in PR #79). Interfaces this phase **exposes** to Phase 4: `zig-out/lib/libcirc.wasm`, the `circ` helper protocol below (the worker reimplements it verbatim), `-Dwasm-optimize`.

```zig
// lib/libcirc/wasm_root.zig — the whole file
const std = @import("std");
const c_api = @import("c_api");

pub const std_options: std.Options = .{
    .log_level = .err,          // ReleaseSmall's default is .info (std/log.zig:102-105); .err keeps arg tuples dead
    .logFn = silentLog,         // never reach defaultLog → lockStderrWriter → File.stderr() (unlinkable on freestanding)
};

fn silentLog(
    comptime _: std.log.Level,
    comptime _: @Type(.enum_literal),
    comptime _: []const u8,
    _: anytype,
) void {}

comptime {
    // Address-of forces analysis of each `export fn` in a non-root file;
    // `export_symbol_names` (--export=<name>) then refuses to link a missing one.
    _ = &c_api.circ_alloc;
    _ = &c_api.circ_free;
    _ = &c_api.circ_version;
    _ = &c_api.circ_analyze;
    _ = &c_api.circ_compile;
    _ = &c_api.circ_preview;
    _ = &c_api.circ_truth_table;
    _ = &c_api.circ_result_ptr;
    _ = &c_api.circ_result_len;
    _ = &c_api.circ_reset;
}
```

```zig
// lib/libcirc/c_api.zig — the ABI as this phase relies on it (Phase 2 declares it; wasm32
// pointers cross as i32, so the header's `uint8_t *` / `uint32_t` is one surface for both builds)
pub export fn circ_alloc(len: u32) ?[*]u8;                 // request buffers; caller frees with circ_free
pub export fn circ_free(ptr: [*]u8, len: u32) void;
pub export fn circ_version() i32;                          // result = {"version","revision","topology_version","full_version","parser","grammar_sha256"}
pub export fn circ_analyze(req: [*]const u8, len: u32) i32;
pub export fn circ_compile(req: [*]const u8, len: u32) i32;
pub export fn circ_preview(req: [*]const u8, len: u32) i32;
pub export fn circ_truth_table(req: [*]const u8, len: u32) i32;
pub export fn circ_result_ptr() [*]const u8;               // library-owned; valid until the next circ_* call
pub export fn circ_result_len() u32;
pub export fn circ_reset() void;                           // frees the result buffer, calls memory.reset()

// Status (decision 3): 0 ok · 1 front-end diagnostics ({"files":[…],"diagnostics":[…]}) · 2 bad request
// ({"error":…}) · 3 mode refusal ({"error":…}: input-bit cap, RAM truth table, layout failure) · 4 OOM · 5 internal.

// Allocation model this phase fixes:
const backing: std.mem.Allocator = if (builtin.target.cpu.arch.isWasm()) std.heap.wasm_allocator else std.heap.page_allocator;
var result_buf: []u8 = &.{};                // owned here; freed and replaced by every circ_* call that produces a result
fn run(op: Mode, req: []const u8) i32 {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();                    // every compiler allocation for this call dies here
    // … Phase 2 driver …; on the truth-table path, after render: memory.reset();   // no Circuit/Session alive (builder.zig:159-161)
    // copy the output into a fresh backing.alloc, free the old result_buf, return the status
}
```

```zig
// build.zig — libcirc.wasm graph (after Phase 2's native `frontend_modules.create`)
const circ_exports = [_][]const u8{
    "circ_alloc", "circ_free", "circ_version", "circ_analyze", "circ_compile",
    "circ_preview", "circ_truth_table", "circ_result_ptr", "circ_result_len", "circ_reset",
};
const fe_wasm = frontend_modules.create(b, .{
    .target = wasm_target,
    .optimize = wasm_optimize,
    .strip = wasm_strip,
    .circuit_options_mod = circuit_options_default_mod, // build.zig:746 — imported by object, never addOptions twice
    .build_info_mod = build_info_mod,                    // Phase 2: `build_info.createModule()` materialised once
    .runtime_embed_mod = runtime_embed_wasm_mod,
});
const libcirc_wasm_mod = b.createModule(.{
    .root_source_file = b.path("lib/libcirc/wasm_root.zig"),
    .target = wasm_target,
    .optimize = wasm_optimize,
    .strip = wasm_strip,                                 // Module.CreateOptions.strip (std/Build/Module.zig:241) → Module.strip (:20) → -fstrip (:545)
});
libcirc_wasm_mod.addImport("c_api", fe_wasm.c_api);
libcirc_wasm_mod.export_symbol_names = &circ_exports;   // std/Build/Module.zig:39 → `--export=<name>` per entry (:607)
const libcirc_wasm = b.addExecutable(.{ .name = "libcirc", .root_module = libcirc_wasm_mod });
libcirc_wasm.entry = .disabled;                          // -fno-entry; NO rdynamic: only the ten names + `memory` are exported
```

`frontend_modules.create` returns at least `.c_api` (the module rooted at `lib/libcirc/c_api.zig`) — `TODO(phase3): align the `Options` field names above with the shape Phase 2 actually shipped in `build/frontend_modules.zig`; the requirement is only that one call produces the whole front-end graph for `(wasm_target, wasm_optimize, wasm_strip)` with the three shared modules passed in by object.`

```js
// tests/harness/libcirc_loader.js — the `circ` helper handed to the script (Phase 4's worker copies this protocol)
const circ = {
  exports: () => WebAssembly.Module.exports(mod).map(e => e.name).sort(),
  imports: () => WebAssembly.Module.imports(mod).map(i => `${i.module}.${i.name}`).sort(),
  memoryBytes: () => wasm.memory.buffer.byteLength,
  version() { const status = wasm.circ_version(); return { status, bytes: this.result() }; },
  reset: () => wasm.circ_reset(),
  result() {                                  // copy out: the buffer is only valid until the next circ_* call
    const ptr = wasm.circ_result_ptr(), len = wasm.circ_result_len();
    return Buffer.from(new Uint8Array(wasm.memory.buffer, ptr, len));   // re-read memory.buffer: it detaches on grow
  },
  call(op, request) {                          // op ∈ analyze | compile | preview | truth_table
    const req = Buffer.from(JSON.stringify(request), "utf8");
    const ptr = wasm.circ_alloc(req.length);
    if (ptr === 0) throw new Error("circ_alloc failed");
    new Uint8Array(wasm.memory.buffer).set(req, ptr);
    const status = wasm["circ_" + op](ptr, req.length);
    wasm.circ_free(ptr, req.length);
    return { status, bytes: this.result() };
  },
};
```

Request shapes the tests send (keys are the normalised virtual paths of decision 4):

```json
{"root":"/playground/main.circ","files":{"/playground/main.circ":"<fixture source>"}}
{"root":"/playground/root.circ","files":{"/playground/root.circ":"<projects/full_adder/root.circ>","/playground/half_adder.circ":"<projects/full_adder/half_adder.circ>"}}
{"root":"/playground/main.circ","files":{…},"options":{"color":"never"}}          // preview
{"root":"/playground/main.circ","files":{…},"options":{"format":"json"}}          // truth table
```

`root.circ`'s `import half_adder "half_adder.circ"` (`tests/fixtures/projects/full_adder/root.circ:1`) resolves to `/playground/half_adder.circ` via `resolvePosix(dirname(root), "half_adder.circ")`. `TODO(phase3): the option key names (`color`, `format`, `values`, `cap`, `strict`) are whatever Phase 2 wrote into `DOCS/libcirc-api.md`; the tests use only `color:"never"` and `format:"json"` and must be renamed to match.`

State ownership inside the module: `result_buf` (one per module instance), the engine's global arena (`lib/memory.zig:65`, reset after every truth table), `lib/log.zig:12`'s `wasmLogArena` (grows only when `debugEnabled()` returns non-zero after the reorder), and `templates/main.zig` state does **not** exist in `libcirc.wasm` — the runtime is embedded as bytes (`runtime_embed_wasm_mod`), never linked as code.

## Execution & Concurrency Model

This phase is fully synchronous. No background threads, workers, or async exports are introduced. Each `circ_*` call runs to completion on the caller's thread inside one `ArenaAllocator` that is destroyed before the call returns; the only state that survives a call is `result_buf` (until the next call) and the engine arena (until `memory.reset()` at the end of every truth-table call or an explicit `circ_reset`). A `WebAssembly.Instance` is single-threaded by construction, so there is nothing to guard; a host that wants isolation instantiates twice (Phase 4 runs one instance inside one Web Worker, so the `2^bits` enumeration never blocks the page — that is the worker's concurrency, not the module's). The Node harness is one process per test that runs its script to completion; the Zig test waits on `std.process.Child.run` (`topology_protocol_test.zig:77-80`). The build introduces one new artifact in the graph: `libcirc_wasm` depends on the runtime artifact through `embed_zig_file` (`build.zig:815-819`), so `zig build libcirc-wasm` always rebuilds the runtime first; the test's run step depends on `install_libcirc_wasm` exactly as the protocol test depends on `install_runtime` (`:848`).

## Persistence & I/O

- **Build outputs:** `zig-out/lib/circ-runtime.wasm` (already installed, `build.zig:811-813`) and `zig-out/lib/libcirc.wasm` (new). No other file is written by the build. `libcirc.wasm` is **not** added to the default `install` step; `zig build libcirc-wasm` and the `test` step produce it. Phase 4 copies it into `site/public/wasm` — nothing in this phase touches `site/`.
- **Tests:** every Node run writes `libcirc.wasm`, `runner.js`, and any result files (`compile.bin`, `analyze.json`, `preview.txt`, `tt.json`, `status1.json`) under `std.testing.tmpDir` (`.zig-cache/tmp/<random>/`, `std/testing.zig:633-636`, cleaned by `defer tmp_dir.cleanup()`); fixture sources are read from `tests/fixtures/circuits/*.circ` and `tests/fixtures/projects/full_adder/*.circ` with `std.fs.cwd().readFileAlloc` (cwd is the repo root under `zig build`, as `section_writer_fixtures_test.zig:258` assumes). The native `c_api` runs in-process; the harness's Node process is the only subprocess.
- **Environment:** `SKIP_WASM_E2E=1` skips every test in `libcirc_wasm_test.zig` with the `SKIPPED (SKIP_WASM_E2E=1 set in environment)` line (`topology_protocol_test.zig:17`); a missing `node` skips with `SKIPPED (node not found on PATH)` (`:27`). Neither is a failure.
- **Linux bisect (slice 5):** `zig build e2e-linux-docker` builds an x86_64 ELF plus `libcirc.wasm` on the host and runs inside `node:22-bookworm-slim` or `node:24-bookworm-slim` (Docker required; not in CI). Results are recorded in STATUS only — no CI file changes beyond comments unless the root cause is proven.
- **`DOCS/libcirc-api.md`** (completed here) carries these sections in this order: Building (`zig build libcirc`, `zig build libcirc-wasm`, `-Dwasm-optimize`, artifact paths); Exports (the ten names with signatures, plus `memory`); Host imports (`env.debugEnabled`, `env.onDebugLog`, stub recipe); Request schema (keys, normalisation rule, options per mode); Status codes 0–5 with the result shape of each; Memory contract (request buffers caller-owned, result buffer library-owned until the next call, `circ_reset`, growth behaviour, "the buffer detaches on grow"); Loading from Node (the `circ` helper verbatim) and from a Worker (`instantiateStreaming` note, transfer the result copy); Version handshake (`circ_version` fields, `topology_version`/`full_version` = `0x03` after PR #79, `parser` = the `Runtime: … abi=N sha256=…` header line from `lib/parser/parser.zig`); Size budget and how to measure (`stat -f%z`, `gzip -9 -c | wc -c`); Not exported (decision 10). No other doc is created; `DOCS/STATUS.md` is appended by the execution agent.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | `-Dwasm-optimize` decoupled from `-Doptimize` | `build.zig`: the option + `wasm_strip`; the eight wasm modules at `:722-795` switched; `topology_format_native_mod` and `:842` re-pointed; `runtime_embed_wasm_mod` created (unused until slice 2 — a `_ = runtime_embed_wasm_mod;` keeps the build warning-free); CLAUDE.md/README one-line mention. Commit: `build: decouple wasm optimize mode from -Doptimize`. | `zig build && stat -f%z zig-out/lib/circ-runtime.wasm` prints a value ≤ 25,600 (19,628 B / 8,716 B gzip on `main` before PR #79's eight memory exports — re-measured on the planner's `zig-out/lib/circ-runtime.wasm`; record the post-merge number in STATUS with `gzip -9 -c zig-out/lib/circ-runtime.wasm \| wc -c`); `zig build -Dwasm-optimize=Debug && stat -f%z zig-out/lib/circ-runtime.wasm` prints ≥ 900,000 (the `memories` worktree's Debug runtime measured 976,946 B raw / 345,817 B gzip on 2026-09-08 — the eight memory exports add ~44 KB of Debug code, so the Debug floor is 900,000, not 933,072); `zig build -Doptimize=ReleaseFast` leaves the runtime at the ReleaseSmall size (decoupling proven); `zig build test-all` green on the ReleaseSmall runtime — `section_writer: circuits fixtures behavioral correctness` (43 fixtures post-merge, `section_writer_fixtures_test.zig` `circuit_fixtures`; 41 on `main`), `section_writer: project fixtures behavioral correctness` (12, `project_fixtures`), `topology host protocol: inverter round-trip via Node` (`topology_protocol_test.zig:133`), and `topology host protocol: memory exports over a hand-built v03 payload` (`:177`) all PASS; every golden byte-identical (`git status` shows only `build.zig`, `CLAUDE.md`, `README.md`, `DOCS/STATUS.md`). |
| 2 | `libcirc.wasm` freestanding module | `lib/libcirc/wasm_root.zig`; `c_api.zig` backing allocator + per-call arena + result buffer + `memory.reset()` after truth tables; `lib/log.zig:45-52` reorder; `build.zig` wasm graph, `libcirc_wasm` artifact (`entry = .disabled`, `export_symbol_names = &circ_exports`, no `rdynamic`), `install_libcirc_wasm`, `libcirc-wasm` step. Commit: `feat(libcirc): build libcirc.wasm as a freestanding wasm32 module`. | `zig build libcirc-wasm` emits `zig-out/lib/libcirc.wasm`; `node -e 'const m=new WebAssembly.Module(require("fs").readFileSync("zig-out/lib/libcirc.wasm"));console.log(WebAssembly.Module.exports(m).map(e=>e.name).sort().join(" "));console.log(WebAssembly.Module.imports(m).map(i=>i.module+"."+i.name).sort().join(" "))'` prints exactly `circ_alloc circ_analyze circ_compile circ_free circ_preview circ_reset circ_result_len circ_result_ptr circ_truth_table circ_version memory` then `env.debugEnabled env.onDebugLog`; a manual `circ_version` call through a five-line script returns status 0 and JSON whose `topology_version` is `3`; `stat -f%z` ≤ 3,145,728 (log raw + gzip in STATUS against the 600 KB / 200 KB budget); `zig build test-all` still green (native `tests/libcirc/c_api_test.zig` and `driver_test.zig` byte-identical — the `log.zig` reorder and allocator switch are invisible natively); `zig build bench` counters unchanged (`lib/log.zig` native path untouched; `lib/memory.zig` untouched). |
| 3 | Node harness and behavioural proof | `tests/harness/libcirc_loader.js`; `tests/e2e/libcirc_wasm_test.zig` with the first six tests of the Tests table (surface, version, compile+drive, byte-equality ×5, E004 → 1, 2/3 statuses); `build.zig` `libcirc_wasm_embed_mod`, `libcirc_wasm_tests` + imports, `test_step` wiring. Commit: `test(libcirc): drive libcirc.wasm through a Node harness`. | `zig build test --summary all` lists `libcirc_wasm_tests` PASS on macOS/Node 24 with every assertion in the Tests table; `SKIP_WASM_E2E=1 zig build test` prints `SKIPPED (SKIP_WASM_E2E=1 set in environment)` once per test and passes; `PATH=/usr/bin zig build test` (no node) prints `SKIPPED (node not found on PATH)` for these and the existing Node tests. |
| 4 | Memory bound and size gate | The last two tests of the Tests table; STATUS records `raw=<n> gzip=<n>` and the after-5/after-50 memory numbers for both loops. Commit: `test(libcirc): bound libcirc.wasm memory growth and size`. | `zig build test` green; the test's stderr carries `SIZE raw=<n> gzip=<n>` and `MEM compile after5=<n> after50=<n>` / `MEM truth_table after5=<n> after50=<n>` lines; `after50 <= after5 + 65536` for both loops; deliberately setting the hard cap to `1` in a scratch run fails with the actual size in the message (then restored — never committed). |
| 5 | Bounded bisect of the Linux Node `init()` failure | `run.sh`/`Dockerfile`/`container-e2e.sh` pass-through + `drive-libcirc.mjs`; a matrix run `WASM_OPTIMIZE ∈ {Debug, ReleaseSafe, ReleaseSmall} × NODE_IMAGE ∈ {node:22-bookworm-slim, node:24-bookworm-slim}` (six `zig build e2e-linux-docker` invocations, each ≈ one Docker build); if Debug fails and Release passes, one extra run with `runtime_artifact.use_llvm = true` (`std/Build/Step/Compile.zig:193`) under Debug to separate "self-hosted wasm backend" from "optimize mode"; comments at `topology_protocol_test.zig:8-13` and `pr-tests.yml:41-46` rewritten with the outcome; STATUS table of the seven results. Time box: one session; no further hypotheses are chased in this phase. Commit: `test(e2e): drive libcirc.wasm in the Linux Docker e2e and record the wasm init matrix`. | `zig build e2e-linux-docker` passes end to end for at least the `ReleaseSmall × node:22` cell (the cell that matches the default build), including the new `--- libcirc ---` block printing `a=0 -> NOT a = 1` / `a=1 -> NOT a = 0`; the STATUS matrix has seven rows with PASS/FAIL and, for FAIL, the first diverging observation (`init()` left `runtime_initialized` false vs. instantiate error vs. wrong outputs). If every cell passes, STATUS says so and proposes (does not do) the `pr-tests.yml` unskip as a Phase 5 follow-up; the `SKIP_WASM_E2E` env stays. |
| 6 | `DOCS/libcirc-api.md` completed | The section list under Persistence & I/O; CLAUDE.md build table row `zig build libcirc-wasm`; README build section mirror; `DOCS/index.md` row. Commit: `docs(libcirc): document the wasm module, host protocol, and size budget`. | `zig build test` unaffected; the doc's Node example is the `circ` helper copied from `tests/harness/libcirc_loader.js` and a `libcirc_wasm_test.zig` test (`libcirc.wasm: doc example loads and compiles the inverter`) extracts the fenced `js` block titled `// libcirc-api.md: Node example` from the doc, runs it through the loader and expects `PASS\n` — the doc and the harness cannot drift. `cli_args_help_text_mentions_every_mode_and_flag` unchanged (no CLI flag is added). |

Slices are ordered by dependency. Each slice must be fully reviewable on its own. Slice 1 is deliberately build-only so the size decoupling can be reviewed against the 55 existing Node-driven fixture runs (43 circuits + 12 projects post-merge) before any new code exists; slice 2 cannot be split ("module without exports" has no proof); slices 3 and 4 share a test file but 4 adds only two tests and the STATUS numbers.

## Tests

Fixtures used (all pre-existing): `tests/fixtures/circuits/{inverter,four_bit_adder,slice_basic,chain,builtin_xor,alu_4bit_multibit,E004_unconnected_required_input}.circ`, `tests/fixtures/projects/full_adder/{root,half_adder}.circ`, vectors `tests/fixtures/expected-wasm/{inverter,four_bit_adder,slice_basic}.txt` and `expected-wasm/projects/full_adder.txt`. `inverter.txt` = 2 vectors; `slice_basic.txt` = 4 vectors crossing a 4-bit input and a 2-bit output (the multi-bit codec); `four_bit_adder.txt` = 5 vectors over 8 width-1 inputs (`a0..a3`, `b0..b3`) and 5 outputs through the `xor`/`and`/`or` builtin macros (project resolution via `<builtin>/`); `projects/full_adder.txt` = 8 vectors; `E004_unconnected_required_input.circ` = `input a` / `and gate(a=a)` / `output out(in=gate.out)` whose golden line (`tests/fixtures/expected-diagnostics/E004_unconnected_required_input.txt`) is `…circ:2:1: error: E004: required input 'b' is unconnected`. Expected-output formatting reuses the `fmtState` JS and the `p<idx>` line protocol from `section_writer_fixtures_test.zig:281-327`; pin ids come from `serializer.serializeProjectFull(...).input_ids/output_ids` over the fixture path (`:252`, `serializer.zig:75-84`).

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `log: wasm printOnBrowser skips formatting when debugEnabled is false` | `lib/log.zig` | No native test can reach `printOnBrowser`: `lib/log.zig:87-90` selects `std.log.scoped(.log)` on every non-wasm target and the `extern fn` pair (`:7-8`) is only referenced from the wasm branch, so a native test binary cannot define stubs for it. The assertion is therefore structural — `zig build test-all` green (native path untouched) plus the wasm memory-bound test below, which without the reorder would grow the engine arena by one formatted line per engine log call (`:24-28` allocate from `memory.allocator` and `wasmLogArena` before `debugEnabled()` is consulted at `:49`). No new native test function; noted here so the reorder is not "untested" by accident. |
| `c_api: result buffer replaced per call and freed by circ_reset` | `tests/libcirc/c_api_test.zig` (Phase 2 file, one new test) | Two consecutive `circ_analyze` calls return different `circ_result_ptr()` values or identical content; after `circ_reset()`, `circ_result_len() == 0`; a third call succeeds (the reset did not poison the backing allocator). |
| `c_api: truth table path resets the engine arena` | same | Natively: `memory.snapshotAllocMetrics()` is zero outside bench, so the assertion is indirect — call `circ_truth_table` on `builtin_xor` 20 times and check `std.testing.allocator` sees no leak (the per-call arena is over `page_allocator`, so this proves only the driver frees its own buffers); the wasm-side growth test is the real proof. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `libcirc.wasm: export surface is exactly memory plus the ten circ_ names` | `tests/e2e/libcirc_wasm_test.zig` (Node) | `circ.exports().join(" ")` is `circ_alloc circ_analyze circ_compile circ_free circ_preview circ_reset circ_result_len circ_result_ptr circ_truth_table circ_version memory`; `circ.imports().join(" ")` is `env.debugEnabled env.onDebugLog`; `WebAssembly.validate(bytes)` true. |
| `libcirc.wasm: circ_version JSON matches native` | same | Status 0; result parses; key set is exactly `version, revision, topology_version, full_version, parser, grammar_sha256`; `topology_version === 3 && full_version === 3`; `version` equals the `VERSION` file (`0.0.2` at planning time); bytes equal the native `c_api.circ_version()` result (`circ_result_ptr()[0..circ_result_len()]`) byte-for-byte. |
| `libcirc.wasm: compile inverter, slice_basic, four_bit_adder, full_adder project and drive expected-wasm vectors` | same | For each of the four requests: status 0; result bytes written to `<tmp>/<name>.wasm` equal the native `circ_compile` bytes for the same request (`std.testing.expectEqualSlices(u8, …)`); `WebAssembly.Module.customSections(mod, "circ.topology.v0.min").length === 1` and `…("circ.topology.v0.full").length === 1`; the `.min` section bytes equal `serializer.serializeProjectFull(...).payload` from the native pipeline over the fixture path (ids therefore agree); instantiate with the runtime stubs (`section_writer_fixtures_test.zig:267-274`), `topology_alloc` + copy + `init` (`:278-280`), then every vector line: `setPin(id, value, defined)` per input, `run()`, `p<idx>` output line — stdout equals the expected text built from the `.txt` (`:303-332`), e.g. `out=1\nout=0\n` for the inverter and `o=10\no=11\no=00\no=01\n` for `slice_basic`. `TODO(phase3): if `.min` equality fails on a project fixture because overlay keys order files differently from disk discovery, drop that one assertion and derive ids by decoding the artifact's `.full` section with `lib/topology/full_decoder.zig:46` instead; the vector drive remains the proof.` |
| `libcirc.wasm: analyze, preview, and truth table are byte-equal to native for five fixtures` | same | Fixtures `chain`, `builtin_xor`, `alu_4bit_multibit`, `four_bit_adder`, `slice_basic`; ops `analyze` (no options), `preview` (`{"color":"never"}`), `truth_table` (default markdown) and `truth_table` (`{"format":"json"}`): status 0 in wasm and native, and the 20 result files equal the native results byte-for-byte; additionally `chain` preview equals `tests/fixtures/preview/renders/chain.preview.golden` and `builtin_xor` truth tables equal `tests/fixtures/truth_table/builtin_xor.truth.golden` / `builtin_xor.json.golden` through `golden.expectGolden` (the CLI's own goldens at `main.zig:753,1215,1562`), tying the wasm build to the CLI, not only to the native library. |
| `libcirc.wasm: E004 source returns status 1 with analyze-shaped diagnostics` | same | `circ_compile` over `E004_unconnected_required_input.circ` → status 1; result parses; `files[0].path === "/playground/main.circ"`; `diagnostics.length === 1`; `diagnostics[0]` has `severity "error"`, `code "E004"`, `message "required input 'b' is unconnected"`, `range.start_line === 2`, `range.start_col === 1`; bytes equal the native status-1 result; `circ_analyze` on the same request returns status 0 and its `diagnostics` array equals the status-1 `diagnostics` array (same `renderJson` path, `analyze.zig:398` onwards; `writeRange` at `:391-396` emits `start_line`/`start_col`/`end_line`/`end_col`, matching `DOCS/analyze-api.md:63`). |
| `libcirc.wasm: bad request → 2, cap refusal → 3` | same | `circ_compile` with the body `{` → status 2 and result `{"error":…}` (non-empty string); a zero-length request → 2; a request whose `root` is not in `files` → 2; `circ_truth_table` over the inline source `input[17] a\noutput[17] o(in=a)\n` with no options → status 3 and `JSON.parse(result).error` contains `17` (the default cap is 16: `lib/cli/args.zig:40` `truth_table_cap_default`, `builder.zig:82` `max_input_bits: u8 = 16`; the cap message names the bit count, as the CLI does at `main.zig:544-551`); `circ_compile` on the same 17-bit source → status 0 (only the truth-table mode refuses). |
| `libcirc.wasm: 50 repeated compiles and 50 repeated truth tables keep linear memory bounded` | same | Loop A: `circ.call("compile", four_bit_adder)` ×50, `after5 = circ.memoryBytes()` after the 5th, `after50` after the 50th; Loop B: `circ.call("truth_table", builtin_xor, {"format":"json"})` ×50 the same way; prints `MEM compile after5=<n> after50=<n>` and `MEM truth_table after5=<n> after50=<n>`; the Zig side parses both lines and asserts `after50 <= after5 + 65536` (one wasm page of slack for WasmAllocator size-class rounding) and `after50 <= 64 * 1024 * 1024`; every call returned status 0. |
| `libcirc.wasm: size gate` | same | `libcirc_wasm_embed.wasm.len <= 3 * 1024 * 1024` (hard fail with the actual size in the message); the Node script prints `SIZE raw=<len> gzip=<zlib.gzipSync(bytes,{level:9}).length>`; the Zig test re-prints the line via `std.debug.print` so it lands in the STATUS entry; the 600 KB / 200 KB budget is recorded, not asserted (plan prompt: "budget revised in STATUS if measurement disagrees"). |
| `libcirc.wasm: doc example loads and compiles the inverter` (slice 6) | same | The fenced block after the marker line `// libcirc-api.md: Node example` in `DOCS/libcirc-api.md`, run verbatim through the loader, prints `PASS`. |
| Existing suites | whole tree | `zig build test-all` green after every slice; `section_writer` (55 fixture runs post-merge: 43 circuits + 12 projects) and both `topology host protocol` tests pass against the ReleaseSmall runtime from slice 1 on; `tests/cli/integration_test.zig` (spawns `zig build circ-compile`, `buildCli` at `:43-49`) unchanged; `zig build bench` counters unchanged after slice 2. |

Run command: `zig build test` (the `libcirc_wasm_tests` artifact is on the `test` step; `zig build test --summary all` shows it by name). `zig build test-all` before closing slices 1, 2 and 6; `zig build bench` after slice 2; `zig build e2e-linux-docker` (Docker) is slice 5's only proof and is not part of any test step.

## Open Questions / Spikes

- `TODO(phase3): Phase 2's `build/frontend_modules.zig` signature.` The Data & State block assumes `create(b, .{ target, optimize, strip, circuit_options_mod, build_info_mod, runtime_embed_mod }) → struct { c_api: *Module, … }`. Adapt the call, not the requirement: one call, three shared modules by object, no `addOptions` inside the helper.
- `TODO(phase3): request option key names` (`color`, `format`) — take them from Phase 2's `DOCS/libcirc-api.md`; only two are used here.
- `TODO(phase3): native `c_api` signatures.` The tests call `c_api.circ_compile(ptr, len)` in-process and read `circ_result_ptr()[0..circ_result_len()]`; if Phase 2 declared `len`/return types as `usize` rather than `u32`, the test casts, the wasm ABI is unchanged (wasm32 `usize` is 32-bit).
- `TODO(phase3): `.min` byte-equality for the project fixture` — see the compile test row; the fallback is `full_decoder.decode` over the artifact's `.full` section.
- `TODO(phase3): export-section exactness.` If wasm-ld exports an extra symbol despite `-fno-entry` and no `-rdynamic` (e.g. `__indirect_function_table` when a function pointer escapes), the surface test's expected list is extended by that one name and the reason recorded in STATUS — never by adding `rdynamic`, which would export every `export fn` in the graph.
- The Linux `init()` failure is a spike by design (slice 5); its outcome does not gate slices 1–4 or 6. Hypotheses to record against the matrix: (a) optimize mode (Debug-only), (b) the self-hosted wasm backend vs LLVM (`use_llvm` flip), (c) Node major version, (d) host-built bytes differing between macOS and Linux — (d) is out of the time box; STATUS notes the sha256 of the macOS-built `circ-runtime.wasm` so a later CI run can compare.
- None otherwise — decisions 3, 5, 6 and 10 in `DOCS/PLANS_PROMPT.md` fix every other choice this phase makes.
