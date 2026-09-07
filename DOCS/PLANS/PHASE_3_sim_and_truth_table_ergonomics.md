# Phase 3 — --sim and --truth-table memory ergonomics

> **Dependencies:** Phases 0, 1, and 2 complete. This phase consumes the engine hooks (`Circuit.memoryLoadImage/memoryStoreImage/memoryWriteWord/memoryClear`, the `.memory` payload with `MemCells` planes), the `lib/memimage.zig` codec (`bytesPerWord`, `maxImageSize`, `MemoryImageError`), and the v03 full topology (`ComponentKind.rom/.ram`, `Aux.memory { addr_width }`, `PortName.addr..clk`, the `Session.build` arms for both kinds). Nothing here compiles until Phase 2's `engine_session.zig` arms exist.
> **Warnings:** (1) The `ready` block stays byte-identical for every circuit — `ready` + `pin` lines + `diag` lines (`lib/sim/loop.zig:90-96`); memories are discovered with the `mems` verb, never with a new handshake line type, and `proto` stays `1` (`loop.zig:10-12`). (2) `--sim` stdout is the protocol channel: every preload failure goes to **stderr with exit 2 before any handshake byte**, mirroring `input file not found` (`cmd/circ-compile/main.zig:181-188`), not the exit-1 `topology build failed` class (`main.zig:284-292`). (3) `load`/`save` are the drive loop's first filesystem access — today `lib/sim/*.zig` and `lib/engine_session.zig` contain zero `std.fs` references; the only CLI file-read precedent is `main.zig:181`. (4) `Args.parse` is allocator-free and returned by value (`lib/cli/args.zig:123-138`); the preload list is a fixed `[16]` array, never a slice that needs an allocator. (5) `serve`'s signature changes (a `preloads` parameter): its only callers are `main.zig:296` and the in-file `runScript` helper (`loop.zig:268-272`); Phase 4's `expected-sim` driver must call the new shape. (6) The tokenizer splits on space/tab (`lib/sim/protocol.zig:85`): paths with whitespace are unsupported and documented as such — no quoting is invented. (7) `cmd/circ-compile/main.zig` imports neither `engine_session` nor `circuit` (`build.zig:876-889, 1077-1079, 1112, 1166, 1213, 1230, 1244, 1258, 1272, 1423-1424` is the complete `circ_compile_mod.addImport` list; `engine_session_mod` is imported only by `sim_loop_mod` at `:1209` and `truth_table_builder_mod` at `:1229`). Every session/codec name main.zig needs is therefore **re-exported through `lib/sim/loop.zig`** (the way `builder.zig:35` re-exports `PinRef`), so `build.zig` stays untouched. (8) `std.fs.Dir.readFileAlloc` returns `error.FileTooBig` when the file is larger than `max_bytes` (Zig 0.15.1 `std/fs/Dir.zig:1981-2012`), so a read cap equal to the image capacity would make `TooManyWords` unreachable; both `--mem` and `load` read with the CLI's existing 16 MiB cap (`main.zig:181`) and let the codec report over-capacity images.

## Goal

A user runs `circ-compile cpu.circ --sim --mem=code=prog.bin` and the ROM named `code` already holds `prog.bin` when the byte-identical `ready` handshake appears; `mems` lists every root-level memory as `mem code rom 8 4`; `load`, `save`, `peek`, `poke`, `mem`, and `clear` read and write memory contents by declared name with hex replies in the same `(value, mask)` encoding as `get`; `reset` returns the session to "CLI preloads applied, nothing else"; a wrong name, missing file, or malformed image on `--mem` exits 2 with `--mem code=prog.bin: no memory named 'code' (declared memories: rom prog[8, 4])` on stderr and nothing on stdout. `circ-compile lut.circ --truth-table --mem=code=table.bin` tabulates the preloaded ROM (unloaded cells print `?`, `--strict` fails them), and a RAM-bearing circuit — root-level or nested — is refused with a one-line explanation naming the RAM. `DOCS/sim-protocol.md` documents all of it, including that `E_NOSETTLE` is declared but never emitted.

## Scope

**In scope:**
- `--mem=<name>=<path>` in `lib/cli/args.zig`: repeatable, split at the first `=` after the prefix, `Args.mem_preloads: [16]MemPreload` + `mem_preload_count: u8`, `ParseError.TooManyMemPreloads`, `parseErrorMessage` arm, help text line, help-needle entry, post-loop scoping to `.sim` and `.truth_table`.
- `engine_session.zig`: `MemRef`, `Preload`, `collectMemories(alloc, topology)`, `validateImage(mem, bytes)` (codec-only, no `Circuit`), `Session.memories` (root-level only, `origin.len == 0`), `findMemory(name)`, `applyImage(mem, bytes) !usize`.
- `lib/sim/loop.zig` re-exports for the CLI: `Preload`, `MemRef`, `collectMemories`, `validateImage`, `MemoryImageError`, and the shared `writeImageError` formatter so `--mem` and `load` print identical reasons.
- Pre-handshake preload resolution in `main.zig` shared by the sim and truth-table arms: name lookup, file read (16 MiB cap), codec validation; stderr + exit 2 on any failure.
- `serve` gains `preloads`; applies them after `Session.build` and re-applies them after `reset` rebuilds the session; mid-session `load`/`poke` are dropped by `reset`.
- Verbs `mems`, `load`, `save`, `peek`, `poke`, `mem`, `clear` in `protocol.Command` + `parseLine`, dispatch arms in `serve`; error codes `E_NOMEM`, `E_IO`, `E_MEMFMT`, `E_ADDR` appended to `protocol.ErrorCode` + `tag()`; `E_WIDTH`/`E_BADVAL`/`E_PROTO` reused for `poke`.
- `--truth-table` honours `--mem` for ROM via `BuildOptions.preloads`; the RAM rejection runs on every record regardless of `origin` and the CLI names the offending RAM; `tests/fixtures/truth_table/rom_lookup.truth.golden`; CLI tests for the unloaded-ROM `?`/`--strict` path and the RAM rejection message.
- Tests: protocol parse tests, `loop.zig` serve tests over hand-built rom/ram `FullTopology` values with `std.testing.tmpDir` image files covering every verb and every error code, args tests, `engine_session` and builder unit tests, in-process `main.zig` tests for every exit-2 message.
- `DOCS/sim-protocol.md`: verbs, codes, `--mem`, reset semantics, path rules, `E_NOSETTLE` honesty; `DOCS/STATUS.md` entries.

**Explicitly deferred:**
- `expected-sim/<name>.txt` transcript goldens driven through `serve` (Phase 4 — the first fixture-based `--sim` coverage). This phase's coverage is inline `loop.zig` tests, matching today's pattern (`loop.zig:252-327`).
- Getting-started recipes (`printf`/`xxd` image authoring, `poke`-then-`save`), decision records, `--analyze addr_width` (Phase 4).
- Memories inside imported/macro sub-circuits are not name-addressable (`origin.len != 0`, same rule as pins at `engine_session.zig:42,55`); hosts reach them by id through the `.full` section. (They are still *rejected* by `--truth-table`, see below — rejection and addressability are different questions.)
- Quoting for paths with whitespace; a `Circuit.reset()` that reuses planes (every `reset` still leaks planes into the arena — `lib/memory.zig:65-71`, plan-prompt trap).
- `-Werror` in `--sim` (returns at `main.zig:278-301` before the check at `:305`; pre-existing).
- Adding `engine_session`/`circuit` imports to `circ_compile_mod` in `build.zig` — deliberately avoided via the `sim_loop` re-exports (Warning 7).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| fixtures | `tests/fixtures/truth_table/rom_lookup.truth.golden` | Markdown truth table of `tests/fixtures/circuits/rom_lookup.circ` (Phase 2 fixture: `input[4] pc` · `rom code[8, 4](addr = pc.out)` · `output[8] out(in = code.out)`) preloaded with a 16-word image written to a `tmpDir` by the test (no binary blob committed). Regenerate with `UPDATE_GOLDENS=1 zig build test`; diff before committing. |
| plans | `DOCS/PLANS/PHASE_3_sim_and_truth_table_ergonomics.md` (this file) | Plan artifact. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| cli | `lib/cli/args.zig` | `Args` (:42-55) gains `mem_preloads: [MAX_MEM_PRELOADS]MemPreload = undefined`, `mem_preload_count: u8 = 0`, and `pub fn memPreloads(self) []const MemPreload`; `ParseError` (:57-66) gains `TooManyMemPreloads`; `help_text` (:96-108): new group `  Sim and truth-table:` with `--mem=<name>=<path>` above `Truth-table-only:`; parse loop: a `startsWith(token, "--mem=")` branch after `--truth-table-cap=` (:240-249) and before `-o` (:250) — `indexOfScalar(value, '=')` (first `=`, so paths may contain `=`), empty name or path → `InvalidFlagValue`, count == 16 → `TooManyMemPreloads`; post-loop guard next to :272-276: `if (args.mem_preload_count != 0 and args.mode != .sim and args.mode != .truth_table) return error.InvalidFlagValue;`; needle test (:506-519) gains `"--mem="`; new tests after :606. The `Mode` tripwire (:281-293) is untouched — no new mode. |
| cli | `cmd/circ-compile/main.zig` | `parseErrorMessage` (:104-114, `else`-guarded — must gain a deliberate arm): `error.TooManyMemPreloads => "too many --mem flags (max 16)"`. New `fn resolvePreloads(allocator, args, topology, stderr_writer) !?[]const sim_loop.Preload` (returns null after printing one stderr line; caller returns 2) using `sim_loop.collectMemories`, `std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024)`, `sim_loop.validateImage`, and `sim_loop.writeImageError` (`error.FileTooBig` from `readFileAlloc` is passed straight into it — its parameter type is `sim_loop.ImageError`) — **no new imports** (Warning 7). Sim arm: call `resolvePreloads` between `defer topology.deinit` (:293) and the stdin reader (:295); pass the slice into `sim_loop.serve` (:296). Truth-table arm: call it after `defer topology.deinit` (:449), before the cap pre-flight (:454); pass `.preloads` in the `BuildOptions` literal (:463-465); the `catch |err|` at :465-468 already maps `error.StatefulComponent` through Phase 2's `firstRamName` (origin-agnostic) and prints the `truth-table: ram '<name>' is stateful …` line — unchanged here; add only `error.BadPreload => "truth-table: preload failed"` (unreachable after pre-flight; kept for the library path). New tests next to :1061-1128 and :1838-1863 (`runTruthTableWithArgs` precedent). |
| session | `lib/engine_session.zig` | After `PinRef` (:8-12): `MemRef`, `Preload`. `Session` (:28-32) gains `memories: []const MemRef`. New `pub fn collectMemories(alloc, topology) SessionError![]const MemRef` — a pure walk of `topology.components` (`origin.len == 0`, kind `.rom`/`.ram`, `data_width = comp.width`, `addr_width` from `comp.aux` `.memory` arm, `else => error.InvalidTopology` exactly like the slice aux guard at :80-83). New `pub fn validateImage(mem: MemRef, bytes: []const u8) engine.memimage.MemoryImageError!usize { return engine.memimage.validate(bytes, mem.data_width, mem.addr_width); }` — Phase 1's check-only codec entry, no `Circuit` involved; used by main.zig's pre-flight. `build` calls `collectMemories` and stores the result (return literal :111-116). `findMemory` after `findOutput` (:130-135). `applyImage(self, mem, bytes) (engine.memimage.MemoryImageError || std.mem.Allocator.Error)!usize` — body: `return self.circuit.memoryLoadImage(self.nodeById(mem.component_id).?, bytes) catch |err| switch (err) { error.NotAMemory, error.AddressOutOfRange, error.BufferTooSmall, error.InvalidAddrWidth => unreachable, else => |e| return e };` (the node is a memory by construction of `MemRef`; Phase 1's hook error set is wider than the codec's). `doLoad` maps `OutOfMemory` to `E_IO <path>: OutOfMemory`; `builder.zig`'s `catch return error.BadPreload` is unaffected. `portByteToName` (:138-146) already has its `addr/din/we/clk` arms from Phase 2. Tests after :199. |
| sim | `lib/sim/protocol.zig` | `ErrorCode` (:5-11) appends `nomem, io, memfmt, addr`; `tag()` (:13-22, exhaustive — compile-forced) appends `E_NOMEM/E_IO/E_MEMFMT/E_ADDR`. `Command` (:35-47) gains seven variants (see Data & State). `parseLine` (:88-155): `mems`/`clear` next to the zero-/one-arg verbs, `load`/`save`/`peek` on the strict-arity pattern of `get` (:93-97), `poke` on the optional-mask pattern of `set` (:105-115), `mem` with 0..2 optional numeric args. Tests after :228. |
| sim | `lib/sim/loop.zig` | Top of file, next to `PROTO_VERSION` (:12): `pub const Preload = engine_session.Preload; pub const MemRef = engine_session.MemRef; pub const collectMemories = engine_session.collectMemories; pub const validateImage = engine_session.validateImage; pub const MemoryImageError = engine.memimage.MemoryImageError; pub const ImageError = MemoryImageError || error{FileTooBig}; pub const IMAGE_READ_CAP: usize = 16 * 1024 * 1024;` and `pub fn writeImageError(writer, err: ImageError, mem: MemRef, len: usize) !void` (the four-reason formatter shared by `--mem` and `load`). `writeErr` (:21-23) gets a sibling `writeErrFmt(writer, code, comptime fmt, args)`. `serve` (:71-78) gains `preloads: []const Preload` after `diags`; applies them after `Session.build` (:84) via `applyPreloads(&session, preloads)`; `reset` (:139-145) calls `applyPreloads` again after rebuilding. `switch (cmd)` (:126-150, exhaustive — compile-forced) gains `.mems/.load/.save/.peek/.poke/.mem/.clear` arms calling `doMems/doLoad/doSave/doPeek/doPoke/doMemDump/doClear`. The `pins` reply (:131-134) and handshake (:90-96) are untouched. `runScript` (:268-272) gains a `preloads` argument; new topologies and tests after :327. |
| truth_table | `lib/truth_table/builder.zig` | `BuildOptions` (:76-81) gains `preloads: []const engine_session.Preload = &.{}` — the same `engine_session_mod` instance `sim_loop_mod` imports (`build.zig:1209,1229`), so `sim_loop.Preload` and `truth_table_builder.BuildOptions.preloads` are one type; bench's `.{}` literal at `tools/bench/main.zig:1300` is unaffected even though `bench_truth_table_builder_mod` binds a different `engine_session` (`build.zig:1629`). `BuildError` (:83-88) gains `BadPreload` (`StatefulComponent` is Phase 2's). RAM rejection is Phase 2's origin-agnostic walk before :125 (`for (topology.components) |comp| if (comp.kind == .ram) return error.StatefulComponent;`) — unchanged here; this slice adds `truth_table_build_rejects_nested_ram` as a regression test only. After `Session.build` (:138) and before the row loop (:142): `for (options.preloads) |p| { const mem = session.findMemory(p.name) orelse return error.BadPreload; _ = session.applyImage(mem, p.bytes) catch return error.BadPreload; }`. `countInputBits` (:100-108) is untouched — memory contents never count toward the 2^N cap. |
| docs | `DOCS/sim-protocol.md` | The 1:1 mapping sentence (:10-12) gains `load → memLoad`, `save → memStore`, `poke → setMemWord`, `peek → getMemValue/getMemDefined`, `clear → memClear`; Commands table (:61-70) gains seven rows; error-code paragraph (:72-74) lists all nine codes with `E_NOSETTLE` marked "declared, never emitted (`run` swallows propagate errors, `loop.zig:136`)"; new section "Memories" (image format pointer to `circuit-format.md`/`wasm-api.md`, `--mem`, reset semantics, the warnings-suppressed-on-preload-failure note, cwd-relative whitespace-free paths, the 16 MiB read cap); the example session (:86-104) gains a second, **path-free** memory transcript (`mems`, `set`, `get`, `poke`, `peek`, `mem`, `clear`, `reset`) plus a separate non-transcript `load`/`save` snippet. `E001`-`E016` at :46 was already `E018` after Phase 0. |
| plans | `DOCS/STATUS.md` | One entry per slice (plan-prompt template). |

**New dependencies:** None. `lib/sim/loop.zig` and `lib/engine_session.zig` reach the codec through the engine module (`engine.memimage`, re-exported by `lib/circuit.zig` the way `pub const memory = @import("memory.zig")` is at `circuit.zig:2`); `cmd/circ-compile/main.zig` reaches the session and codec types only through `sim_loop`'s re-exports; `build.zig` module wiring (`build.zig:1176-1235`) is untouched.

## Data & State

Interfaces this phase **consumes** (fixed cross-phase vocabulary): `engine.ComponentType.memory` payload `{ mode: MemoryMode, cells: MemCells { addr_width, values: []u64, defined: []u64 }, ... }`; `Circuit.memoryLoadImage(comp, bytes) !usize` (words loaded, replace-all), `Circuit.memoryStoreImage(comp, buf) !usize` (bytes written, `value & defined`), `Circuit.memoryWriteWord(comp, addr, state)`, `Circuit.memoryClear(comp)` — each ends in `memoryRefresh`, so every verb settles like `set`; `memimage.bytesPerWord(W)`, `memimage.maxImageSize(W, A) = bytesPerWord(W) << A`, `MemoryImageError { LengthNotWordMultiple, WordExceedsWidth, TooManyWords }`; `full_format.ComponentKind.rom/.ram`, `Aux.memory { addr_width }`, `FullComponentRecord.name` (populated from `instance_name` for every component, `full_serializer.zig`). Interfaces this phase **exposes** to Phase 4: `engine_session.Preload` (= `sim_loop.Preload`), `sim_loop.serve(alloc, topology, path, diags, preloads, reader, writer)`, the verb/reply grammar below, `truth_table.BuildOptions.preloads`.

```zig
// lib/cli/args.zig
pub const MAX_MEM_PRELOADS: u8 = 16;

/// One `--mem=<name>=<path>`. Both slices borrow argv (like `output_path`),
/// so `parse` stays allocator-free and returned by value.
pub const MemPreload = struct { name: []const u8, path: []const u8 };

pub const Args = struct {
    // ... existing fields ...
    mem_preloads: [MAX_MEM_PRELOADS]MemPreload = undefined,
    mem_preload_count: u8 = 0,
    pub fn memPreloads(self: *const Args) []const MemPreload {
        return self.mem_preloads[0..self.mem_preload_count];
    }
};
// ParseError += TooManyMemPreloads  → "usage error: too many --mem flags (max 16)", exit 2
```

```zig
// lib/engine_session.zig
/// A root-level memory addressable by its declared name. `kind` is the
/// wire kind (.rom or .ram); widths come from the .full record
/// (`width` = W, `aux.memory.addr_width` = A).
pub const MemRef = struct {
    name: []const u8,
    component_id: u32,
    kind: full_format.ComponentKind,
    data_width: u8,
    addr_width: u8,
};

/// A validated image bound to a memory name. Bytes are owned by the caller
/// (main.zig's arena) and outlive the session so `reset` can re-apply them.
pub const Preload = struct { name: []const u8, bytes: []const u8 };

pub const Session = struct {
    circuit: *engine.Circuit,
    inputs: []const PinRef,
    outputs: []const PinRef,
    memories: []const MemRef,           // new; root-level only
    id_to_node: std.AutoHashMap(u32, *engine.Component),

    pub fn findMemory(self: *const Session, name: []const u8) ?MemRef;
    /// Replace-all load through the engine hook; settles via memoryRefresh.
    pub fn applyImage(self: *const Session, mem: MemRef, bytes: []const u8) (engine.memimage.MemoryImageError || std.mem.Allocator.Error)!usize;
};
/// Pure topology walk shared by `Session.build` and main.zig's pre-flight
/// (which must validate names before any Circuit or handshake exists).
pub fn collectMemories(alloc: std.mem.Allocator, topology: full_format.FullTopology) SessionError![]const MemRef;
/// Codec-only check (no Circuit): returns the word count a load would
/// produce, or the same error `applyImage` would raise. main.zig uses it
/// through `sim_loop.validateImage` before the handshake.
pub fn validateImage(mem: MemRef, bytes: []const u8) engine.memimage.MemoryImageError!usize;
```

```zig
// lib/sim/loop.zig — re-exports so cmd/circ-compile/main.zig needs no new imports
pub const Preload = engine_session.Preload;
pub const MemRef = engine_session.MemRef;
pub const collectMemories = engine_session.collectMemories;
pub const validateImage = engine_session.validateImage;
pub const MemoryImageError = engine.memimage.MemoryImageError;
pub const ImageError = MemoryImageError || error{FileTooBig};   // FileTooBig comes from readFileAlloc, not the codec
pub const IMAGE_READ_CAP: usize = 16 * 1024 * 1024;   // same cap as main.zig:181
/// Writes one E_MEMFMT reason (no code, no newline) for `err` on `mem`
/// given the image length; shared by `--mem` (stderr) and `load` (E_MEMFMT).
pub fn writeImageError(writer: anytype, err: ImageError, mem: MemRef, len: usize) !void;
```

```zig
// lib/sim/protocol.zig
pub const ErrorCode = enum {
    proto, nopin, notin, width, badval, nosettle,
    nomem,   // no root-level memory of that name        -> E_NOMEM
    io,      // open/read/write failure on load/save     -> E_IO
    memfmt,  // image violates the raw-image rules       -> E_MEMFMT
    addr,    // address >= 2^A                            -> E_ADDR
};

pub const MemAddr = struct { mem: []const u8, addr: u64 };

pub const Command = union(enum) {
    pins, set: Assign, get: []const u8, dump: Which, run, eval: ..., reset, quit,
    mems,
    load: struct { mem: []const u8, path: []const u8 },
    save: struct { mem: []const u8, path: []const u8 },
    peek: MemAddr,
    poke: struct { mem: []const u8, addr: u64, value: u64, mask: ?u64 },
    mem: struct { mem: []const u8, start: ?u64, count: ?u64 },
    clear: []const u8,
};
```

```zig
// lib/truth_table/builder.zig
pub const BuildOptions = struct {
    max_input_bits: u8 = 16,
    preloads: []const engine_session.Preload = &.{},   // applied after Session.build, before the drive loop
};
pub const BuildError = error{ TooManyInputs, NoOutputs, OutOfMemory, InvalidTopology, StatefulComponent, BadPreload };
```

Reply grammar (cell values, masks and cell addresses are hex via `protocol.writeHex` — `ok 0xab 0xff`, `0x2 0xab 0xff`, `E_ADDR code 0x10`; counts (`mems <N>`, `cells <N>`, `words=<n>`) and the `<W> <A>` columns of `mem` lines are decimal, like `pins=` and `pin <name> in <width>` in the handshake, `loop.zig:37-38`; `<mask>` defaults to fully defined; `peek`/`mem` canonicalise like `readPin` at `loop.zig:43-49`: `value & defined`):

| Command | Reply | Errors (first match wins) |
|---|---|---|
| `mems` | `mems <N>` block, then `mem <name> <rom\|ram> <W> <A>` per root memory in topology order | — |
| `load <mem> <path>` | `ok words=<n>` (`n` = words loaded; cells `n..2^A-1` become undefined; empty file ≡ `clear`) | `E_NOMEM <mem>`; `E_IO <path>: <errname>`; `E_MEMFMT <path>: <reason>` |
| `save <mem> <path>` | `ok words=<2^A>` (file is `2^A * bpw` bytes of `value & defined`) | `E_NOMEM`; `E_IO <path>: <errname>` |
| `peek <mem> <addr>` | `ok <value> <mask>` | `E_NOMEM`; `E_BADVAL`; `E_ADDR <mem> <addr>` |
| `poke <mem> <addr> <value> [<mask>]` | `ok` (word written, `out` resynced and settled) | `E_NOMEM`; `E_BADVAL`; `E_ADDR`; `E_WIDTH <mem>` (value or mask bits ≥ W) |
| `mem <mem> [<start> [<count>]]` | `cells <N>` block, then `<addr> <value> <mask>` lines | `E_NOMEM`; `E_BADVAL`; `E_ADDR` when `start >= 2^A`; `count` clipped to `2^A - start` (default: whole range); `count = 0` replies `cells 0` with no lines |
| `clear <mem>` | `ok` (every cell undefined, settled) | `E_NOMEM` |

`E_MEMFMT` reasons (produced by `writeImageError`, identical on stderr for `--mem`): `length <n> is not a multiple of <bpw> byte(s)` (`LengthNotWordMultiple`), `<n> words exceed capacity <2^A>` (`TooManyWords`), `a word has bits set beyond data width <W>` (`WordExceedsWidth`), and `image exceeds 16 MiB` (`error.FileTooBig` from `readFileAlloc` with `IMAGE_READ_CAP`; the largest legal image is `8 << 16` = 512 KiB, so every over-capacity-but-under-16-MiB file reaches the codec and reports `TooManyWords`). Name spaces do not overlap: `set`/`get`/`eval` on a memory name stay `E_NOPIN`; `peek`/`load`/… on a pin name are `E_NOMEM`. Wrong arity on any verb is `E_PROTO malformed command`, as today (`loop.zig:115-118`). `--mem` pre-flight messages (stderr, exit 2), one line per failing flag, first failure wins: `--mem <name>=<path>: no memory named '<name>' (declared memories: rom code[8, 4], ram data[8, 4])` (`none` when the circuit has no memories), `--mem <name>=<path>: file not found`, `--mem <name>=<path>: failed reading file: <errname>`, and the four `E_MEMFMT` reasons with the same wording. Path resolution is `std.fs.cwd()`-relative for both the flag and the verbs (absolute paths pass through), identical to the input path at `main.zig:181`.

## Execution & Concurrency Model

This phase is fully synchronous. No background threads or workers are introduced. The drive loop stays one request → one reply on a single thread (`loop.zig:102-151`); every memory verb runs to quiescence before replying because the engine hooks end in `memoryRefresh` → `propagateEvent` → `propagate` (verified precondition: the event queue is empty between commands, since `set`/`eval`/`run` all drain — `loop.zig:136,180,233`). `serve` owns the `preloads` slice for its lifetime; `reset` re-applies it after `Session.build` and before writing `ok`, so a client never observes an intermediate empty memory. The truth-table builder applies preloads once, before the 2^N drive loop, and never resets between rows (`builder.zig:142-169`), which is exactly why RAM is refused — at any origin depth, since a nested RAM's `clk`/`we` are still driven from the enumerated root inputs.

## Persistence & I/O

This is the phase that introduces filesystem access inside `--sim`:

- **CLI preloads** (`main.zig` pre-flight): `std.fs.cwd().readFileAlloc(allocator, path, sim_loop.IMAGE_READ_CAP)` per `--mem` after the topology is built. `FileNotFound` → the `file not found` line; `FileTooBig` → the `image exceeds 16 MiB` line; any other error → `failed reading file: <errname>`. The bytes are then checked with `sim_loop.validateImage` (codec rules, no `Circuit`) before any handshake byte and kept in the CLI arena for the session's lifetime. Hard errors still come first: a circuit with `E`-diagnostics emits the `error diags=` handshake (`main.zig:279-282`) regardless of `--mem`. Warnings do **not**: in `--sim` they are only ever printed as `diag` lines inside `ready` (`loop.zig:94-96`), and the preload pre-flight (`:293-295`) runs before `serve`, so on a preload failure the warnings that would have appeared in the handshake are not printed anywhere — fix the `--mem` flag and re-run (documented in the `--mem` section of `DOCS/sim-protocol.md`).
- **`load`**: `readFileAlloc(scratch, path, IMAGE_READ_CAP)` into the per-line scratch arena (`loop.zig:98,112`); `FileTooBig` → `E_MEMFMT <path>: image exceeds 16 MiB`, any other read error → `E_IO`; the bytes are consumed by `applyImage` within the same line, whose codec error is formatted by `writeImageError`.
- **`save`**: buffer of `memimage.maxImageSize(W, A)` from scratch (exact by construction), `memoryStoreImage` fills it, then `std.fs.cwd().createFile(path, .{ .truncate = true })` + `writeAll` (pattern `main.zig:72-74`). Failure at any step is `E_IO <path>: <errname>`; a failed write may leave a partial file — documented, not mitigated (no temp-and-rename).
- No other persistence. `DOCS/STATUS.md` is appended by the execution agent.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Memories by name in the session | `engine_session.zig`: `MemRef`, `Preload`, `collectMemories`, `validateImage`, `Session.memories`, `findMemory`, `applyImage`; hand-built rom (`code[8,4]`) and ram (`data[8,4]`) topologies in the test section. Commit: `feat(session): expose root-level memories by name`. | Inline tests: `memories` holds exactly the root records in topology order with `data_width`/`addr_width` from `width`/`aux`; a record with non-empty `origin` is skipped; a `.rom` record with `aux == .none` yields `error.InvalidTopology`; `validateImage` with 4 bytes returns 4 without a `Circuit`; `applyImage` with 4 bytes returns 4 and `cells` show words 0..3 defined, 4..15 undefined; 17 bytes → `error.TooManyWords` from both. `zig build test` green. |
| 2 | `--mem` preloads for `--sim` and `--truth-table` | `args.zig` flag + `TooManyMemPreloads` + help + needle + scoping; `loop.zig` re-exports + `IMAGE_READ_CAP` + `writeImageError`; `main.zig` `parseErrorMessage` arm, `resolvePreloads`, both mode arms wired (`error.BadPreload` arm added; the `StatefulComponent` arm and `firstRamName` are Phase 2's); `serve` `preloads` parameter with re-apply on `reset`; `BuildOptions.preloads` + `BadPreload`; `rom_lookup.truth.golden`; `truth_table_build_rejects_nested_ram` regression test. Commit: `feat(cli): preload memory images with --mem in --sim and --truth-table`. | args tests (below). `loop.zig`: with a preload, `ready proto=1 pins=2 warnings=0` is the first line and no `mem` line precedes the first command; `set addr 2` / `get out` returns the preloaded word; after `reset` the word is still there. `builder.zig`: preloaded table rows equal the image; unknown name → `error.BadPreload`; a `.ram` record with one `OriginFrame` → `error.StatefulComponent`. `main.zig`: `rom_lookup` golden matches; unloaded ROM prints `?` and `--strict` exits 1 with `undefined output at row 0`; `ram_basic.circ --truth-table` exits 1 with `ram 'data' is stateful` on stderr; `--sim --mem=nope=<f>` exits 2, stdout empty, stderr contains `no memory named 'nope' (declared memories: rom code[8, 4])`; missing file and a 17-byte image (`17 words exceed capacity 16`) each exit 2 with stdout empty. |
| 3 | Memory verbs and error codes | `protocol.zig` variants, codes, `tag()`, parse tests; `loop.zig` seven `do*` handlers, `writeErrFmt`, dispatch arms; tmpDir-backed tests for every verb and every code. Commit: `feat(sim): add mems/load/save/peek/poke/mem/clear verbs`. | Tests below; `E_NOMEM`, `E_IO`, `E_MEMFMT` (all three codec reasons), `E_ADDR`, `E_WIDTH`, `E_BADVAL`, `E_PROTO` each appear in at least one assertion (the `image exceeds 16 MiB` reason is asserted only through a unit test of `writeImageError`, not by writing a 16 MiB file); existing six `serve` tests byte-stable. |
| 4 | Protocol docs | `DOCS/sim-protocol.md` per the Modified-files row; CLAUDE.md `--sim` row mentions `--mem` (one clause). Commit: `docs(sim): document memory verbs, --mem preloads, and error codes`. | `cli_args_help_text_mentions_every_mode_and_flag` still passes; the doc's path-free memory transcript is reproduced by a `loop.zig` test (`serve: doc example session`) that strips the leading `$ circ-compile …` line and compares the rest byte-for-byte, so the two cannot drift. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own. Slice 3 cannot be split into "protocol then loop": `serve`'s `switch (cmd)` is exhaustive, so a `Command` variant without a loop arm does not compile.

## Tests

Fixture shapes (owned by Phase 2): `rom_basic.circ` and `rom_lookup.circ` are both `input[4] pc` · `rom code[8, 4](addr = pc.out)` · `output[8] out(in = code.out)`; `ram_basic.circ` declares `ram data[8, 4]`. The hand-built `loop.zig`/`engine_session` topologies in this phase name their pin `addr` deliberately (to prove a pin name is not a memory name) and are independent of the fixtures.

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `session collects root memories` | `lib/engine_session.zig` | rom+ram topology → `memories.len == 2`, `findMemory("data").?.kind == .ram`, `addr_width == 4`, `findMemory("addr") == null` (a pin name is not a memory). |
| `session skips nested memories` | same | A `.rom` record with one `OriginFrame` is absent from `memories` but present in `id_to_node`. |
| `session validateImage matches applyImage` | same | 4-byte image on `[8,4]`: both return 4; 17-byte: both `error.TooManyWords`; 3-byte on `[12,2]`: both `error.LengthNotWordMultiple`. |
| `session applyImage short image` | same | 4-byte image on `[8,4]` returns 4; `cells.defined[3] == 0xff`, `cells.defined[4] == 0`. |
| `parse --mem single, repeated, first-equals split` | `lib/cli/args.zig` | `--mem=code=a.bin --mem=data=b=c.bin` → count 2, `[1].path == "b=c.bin"`. |
| `--mem rejects empty name/path and missing '='` | same | `--mem=code=`, `--mem==x`, `--mem=code` → `InvalidFlagValue`. |
| `--mem 17 flags → TooManyMemPreloads` | same | 16 accepted, the 17th returns `error.TooManyMemPreloads`. |
| `--mem rejects outside sim/truth-table` | same | With `--preview`, `--inspect`, `-o out.wasm` → `InvalidFlagValue`; with `--sim` and `--truth-table` → ok. |
| `help text mentions --mem=` | same (:506-519) | Needle `"--mem="` present. |
| `parseLine memory verbs` | `lib/sim/protocol.zig` | `mems` → `.mems`; `load code p.bin` → mem/path; `load code` → `Malformed`; `peek code 0x3` → addr 3; `peek code zz` → `BadValue`; `poke code 1 0xab` mask null; `poke code 1 0xab 0xf0` mask; `poke code 1` → `Malformed`; `mem code`, `mem code 4`, `mem code 4 2` → start/count optional; `mem code 1 2 3` → `Malformed`; `clear code` / `clear` → ok / `Malformed`. |
| `tag() for new codes` | same | `.nomem/.io/.memfmt/.addr` → `E_NOMEM/E_IO/E_MEMFMT/E_ADDR`. |
| `writeImageError reasons` | `lib/sim/loop.zig` | On `[12,2]`: `LengthNotWordMultiple` with len 3 → `length 3 is not a multiple of 2 byte(s)`; `TooManyWords` with len 10 → `5 words exceed capacity 4`; `WordExceedsWidth` → `a word has bits set beyond data width 12`; `error.FileTooBig` path → `image exceeds 16 MiB`. |
| `serve: handshake unchanged with memories` | same | rom topology → output starts with `ready proto=1 pins=2 warnings=0\npin addr in 4\npin out out 8\n` and the next line is the first reply. |
| `serve: mems lists rom and ram` | same | `mems 1` + `mem code rom 8 4`; ram topology → `mem data ram 8 4`. |
| `serve: load then read through addr` | same (tmpDir) | Write `\x10\x20\x30\x40` to `.zig-cache/tmp/<sub>/img.bin`; `load code <path>` → `ok words=4`; `set addr 1` / `get out` → `ok 0x20 0xff`; `set addr 7` / `get out` → `ok 0x0 0x0`. |
| `serve: load refreshes presented address` | same | `set addr 1` first, then `load` → `get out` is `0x20 0xff` without another `set` (memoryRefresh path). |
| `serve: peek/poke/mem/clear` | same | `peek code 2` on unloaded → `ok 0x0 0x0`; `poke code 2 0xab` → `ok`, `peek code 2` → `ok 0xab 0xff`, `set addr 2`/`get out` → `ok 0xab 0xff`; `poke code 3 0 0` → `peek` `0x0 0x0`; `mem code 0 3` → `cells 3` then `0x0 …`, `0x1 …`, `0x2 0xab 0xff`; `mem code` → `cells 16`; `mem code 0xe` → `cells 2`; `mem code 0 0` → `cells 0`; `clear code` → `get out` `0x0 0x0`. |
| `serve: save round-trips` | same (tmpDir) | `poke` two words, `save code <p>` → `ok words=16`; file is 16 bytes with those two values and zeros elsewhere; `clear`, `load code <p>` → `ok words=16` and `peek` matches. |
| `serve: ram write then peek` | same | ram topology with preload; `set addr 5`, `set din 0x2a`, `set we 1`, `set clk 0`, `set clk 1` → `peek data 5` → `ok 0x2a 0xff`; `get out` → `ok 0x2a 0xff`. |
| `serve: reset re-applies preloads and drops poke` | same | preload word 0 = 0x11; `poke code 0 0x22`; `reset`; `peek code 0` → `ok 0x11 0xff`; `poke code 9 0x33`; `reset`; `peek code 9` → `ok 0x0 0x0`. |
| `serve: memory error replies` | same (tmpDir) | `peek addr 0` → `err E_NOMEM addr`; `set code 1` → `err E_NOPIN code`; `load code nope.bin` → `err E_IO nope.bin: FileNotFound`; on `[12,2]` topology: 3-byte file → `err E_MEMFMT <p>: length 3 is not a multiple of 2 byte(s)`, 10-byte file → `… 5 words exceed capacity 4`, 8-byte file with word `0xffff` → `… a word has bits set beyond data width 12`; `peek code 0x10` → `err E_ADDR code 0x10`; `mem code 0x10` → `err E_ADDR code 0x10`; `poke code 0 0x100` → `err E_WIDTH code`; `poke code 0 1 0x100` → `err E_WIDTH code`; `peek code zz` → `err E_BADVAL …`; `load code` → `err E_PROTO malformed command`. |
| `serve: doc example session` | same | The path-free memory transcript in `DOCS/sim-protocol.md` (with its leading `$ circ-compile …` line stripped) matches byte-for-byte (slice 4). |
| `truth_table_build_applies_rom_preload` | `lib/truth_table/builder.zig` | rom topology + `preloads = &.{ .{ .name = "code", .bytes = img } }` → `rows[i].outputs[0].value == img[i]`, defined `0xff`; unknown name → `error.BadPreload`; unloaded → every row `isUndefined()`. |
| `truth_table_build_rejects_nested_ram` | same | A `.ram` record with one `OriginFrame` (plus a root input/output) → `error.StatefulComponent`, proving the check ignores `origin`. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `truth_table_rom_lookup_preloaded` | `cmd/circ-compile/main.zig` (in-process `run`, tmpDir image) | Exit 0; stdout equals `tests/fixtures/truth_table/rom_lookup.truth.golden`. |
| `truth_table_rom_unloaded_is_undefined_and_strict_fails` | same | Without `--mem`: exit 0 and every output cell is `?`; with `--strict`: exit 1 and stderr has `undefined output at row 0`. |
| `truth_table_rejects_ram` | same | `ram_basic.circ --truth-table` → exit 1, stdout empty, stderr contains `ram 'data' is stateful` and `--sim`. A nested-RAM project fixture (if Phase 2 shipped one) asserts the same message with the nested instance's name. |
| `sim_mem_unknown_name_exits_2_before_handshake` | same | `rom_basic.circ --sim --mem=nope=<img>` → exit 2, `stdout.len == 0`, stderr `no memory named 'nope' (declared memories: rom code[8, 4])`. |
| `sim_mem_missing_file_exits_2` / `sim_mem_bad_image_exits_2` | same | FileNotFound → `file not found`; 17-byte image on `[8,4]` → `17 words exceed capacity 16`; both exit 2 with empty stdout (stdin is never read, so the in-process test cannot block). |
| `truth_table_mem_unknown_name_exits_2` | same | Same message style on the truth-table arm; exit 2. |
| `usage error for too many --mem` | same | 17 flags → exit 2, stderr `usage error: too many --mem flags (max 16)`. |
| Existing suites | whole tree | `zig build test` green; `tests/fixtures/truth_table/*.golden` and every other golden byte-identical (`git status` shows only the files listed above). |

Run command: `zig build test` (the sim, session, builder, and CLI test modules are aggregated there — `build.zig:1176-1235`; `zig test lib/sim/loop.zig` alone cannot resolve its `--dep` imports). `zig build test-all` before the final slice.

## Open Questions / Spikes

- Resolved by Phases 1–2 (no spike needed): the codec's check-only entry is `engine.memimage.validate(bytes, W, A) MemoryImageError!usize`, reachable because `lib/circuit.zig` exports `pub const memimage`; `MemoryImageError` is a plain error set, so `WordExceedsWidth` carries no word index (`writeImageError` says `a word has bits …`); Phase 2's `StatefulComponent` walk in `builder.zig` is already origin-agnostic.
- Decided here, flagged for reviewer confirmation because `design.md` said "start/count clipped": `mem <mem> <start>` with `start >= 2^A` replies `E_ADDR` (same predicate as `peek`), and only `count` is clipped — a typo'd start should not silently yield `cells 0` (an explicit `count = 0` does).
- None otherwise — decisions 3, 7, and 8 in `DOCS/PLANS_PROMPT.md` fix every other choice this phase makes.
