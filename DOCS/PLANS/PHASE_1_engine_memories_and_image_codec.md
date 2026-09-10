# Phase 1 — Engine memories + image codec

> **Dependencies:** Phase 0 (Language front door) shipped — its `error.MemoryNotYetSupported` rejection in both topology serializers stays in place for the whole of this phase, so nothing here is user-visible. The engine code itself has no dependency on Phase 0's IR.
> **Warnings:** (1) **The engine's inline tests do not run today.** `lib/circuit.zig` is only ever a *dependency* module (`build.zig:816-821` native, `:734-739` wasm, `:1603-1608` bench); no `addTest` roots at it, and Zig collects `test` decls only from the root module. Verified empirically: `zig build test --summary all` reports `397/397 tests passed` with zero `circuit.test.*` lines, while running `circuit.zig` as a root collects 50 tests and **one already fails** (`lib/circuit.zig:1925` expects `result.value == 0b11`, but `Pool.write` canonicalises undefined value bits to 0 at `:569`, so the engine returns `0b01`). Slice 1 adds the test root and fixes that assertion before any memory test is written; otherwise every test in this phase would silently never execute. (2) `recalculateAndReschedule` takes `circuit: *const Circuit` and `component: *Component` (`lib/circuit.zig:59-64`): the RAM write must mutate the payload through a `|*m|` capture (precedent `deinit`'s `|*g|` at `:418-419`), never through `Circuit.writeState`. (3) `Component.Kind` is a *private* `const` (`:385`); callers build kinds with anonymous literals (`interpreter.zig:60`, `engine_session.zig:85`), so every new payload type a later phase must name (`MemoryMode`, `MemCells`) is a top-level `pub` decl. (4) `memory.allocator` is an `ArenaAllocator` over `page_allocator` on every target (`lib/memory.zig:65-71`); planes are allocated once per component and `--sim reset` (`lib/sim/loop.zig:139-145`) leaks them — accepted for v1 per the plan prompt. (5) `isHigh`/`isLow` assert `width == 1` (`:264-273`); the RAM arm uses width-agnostic bit tests instead (decision 5). (6) `std.PriorityQueue` orders by timestamp only (`:346-348`): the memory kind must never enqueue divergent same-timestamp events for one component — it only ever enqueues from the (idempotent) recalc arm and from `memoryRefresh` on an empty queue. (7) `toKind` is quoted verbatim in `DOCS/simulation-engine.md:93-107` and the eight-kind count lives in `DOCS/architecture.md:60` — a `.zig`-only grep misses both; slice 3 corrects them together with `CLAUDE.md:109`.

## Goal

A library client — the engine's own unit tests now, `templates/interpreter.zig` / `lib/engine_session.zig` in Phase 2 — can call `circuit.createComponent(.{ .memory = .{ .mode = .rom, .cells = .{ .addr_width = 4 } } }, 8)`, wire `addr` (and, for `.ram`, `din`/`we`/`clk`) with `Circuit.connect`, drive the address through the ordinary `propagateEvent` path, and read the addressed word on the component's single `out` slot after gate delay; an unloaded or unwritten cell reads fully undefined, and any undefined address bit yields a fully undefined `out`. A `.ram` commits `din` into `cells[addr]` exactly once per defined-low→defined-high `clk` transition with `we` defined-high and `addr` fully defined, even when the engine recalculates it several times in one timestep. Host hooks `memoryWriteWord`/`memoryClear`/`memoryLoadImage`/`memoryStoreImage` mutate or export contents and resynchronise `out` through one `memoryRefresh` that enqueues only when `out` actually changes under `BitVecState.equals`, so a load that does not touch the presented word leaves `current_time` untouched. `lib/memimage.zig` decodes and encodes the locked headerless little-endian raw image (`ceil(W/8)` bytes per word, strict padding bits, replace-all) and rejects malformed images without touching a single cell. `zig build test` runs all of it, and `zig build` still produces the runtime `.wasm` with no change to `build.zig`'s module graph (verified: a wasm32-freestanding object build of `circuit.zig` importing `memimage.zig` relatively through the exact `build.zig:734-768` graph succeeds; removing the file fails with `FileNotFound` at the import, proving the relative resolution is what is exercised).

## Scope

**In scope:**
- `lib/circuit.zig`: `ComponentType.memory`; `pub const MemoryMode`, `pub const MemCells`, `pub const MAX_ADDR_WIDTH = 16`, `pub const MemoryError`; the `memory` payload on `Component.Kind`; plane allocation in `createComponent` (`error.InvalidAddrWidth` for `A ∉ 1..16`, planes always allocated there); `deinit` arm; `connect` arms for `addr`/`din`/`we`/`clk` (rom rejects the three write ports); the `.memory` recalc arm = optional RAM edge-write block + `memoryReadOut`; gate delay through the existing `else`; `pub fn memoryReadOut`, `pub fn memoryCells`, `Circuit.memoryWriteWord`, `Circuit.memoryClear`, `Circuit.memoryLoadImage`, `Circuit.memoryStoreImage`, private `Circuit.memoryRefresh`; deletion of dead `toKind` (`:353-365`, zero callers — `grep -rn toKind --include='*.zig'` hits only the definition; the two prose copies in `DOCS/` are corrected below).
- `lib/transport.zig`: `kindByte` arm mapping `mode` → 8/9.
- `lib/memimage.zig`: `bytesPerWord`, `maxImageSize`, `validate`, `decode`, `encode`, `MemoryImageError`, private `wordMask`.
- `build.zig`: one `addTest` root over the existing native `circuit_mod` so the engine's inline tests (and, through `test { _ = ...; }` hooks, `transport.zig`'s and `memimage.zig`'s) run under `zig build test`. This is **not** a module-graph change; decision 2's "build.zig untouched" is about the runtime module set, which stays byte-identical. Resolved, not open: `addTest` roots are the repo's standard test mechanism (`CLAUDE.md:34`: the suite is "aggregated from many per-module `addTest` artifacts in `build.zig`", ~40 roots today), and a module used both as an import and as an `addTest` root builds and runs under 0.15.1 (scratch check `scratchpad/modchk`: `6/6 steps succeeded; 2/2 tests passed`).
- Fix of the latent assertion at `lib/circuit.zig:1925` and its explanatory comment at `:1920-1922`.
- `CLAUDE.md:109`: kind list gains `memory`; the wrong `led=2/and=3/wire=4` numbering (it was `toKind`'s, which this phase deletes) is replaced by `format.zig:6-27`'s `and_gate=2/wire=3/led=4` (plan-prompt constraint: "corrected in the same change").
- `DOCS/simulation-engine.md:62-107` and `DOCS/architecture.md:60-70`: the two other places that quote `toKind` / count eight kinds — corrected in the same slice so no doc describes deleted code.
- Unit tests for every behaviour named in the phase index row.

**Explicitly deferred:**
- Wire kinds 8/9, `PortName` 4..7, v03 records, interpreter/engine_session arms, the eight WASM exports, preview, truth-table RAM rejection, emit-zig rejection, `expected-wasm` harness (Phase 2). `--mem`, sim verbs, `Session.memories` (Phase 3). Goldens and user-facing docs (Phase 4).
- `CLAUDE.md:118` allocator paragraph and the 8/9 rows in its kind table (Phase 2, with the wire bump).
- A `Circuit.reset()` that reuses planes (plan-prompt trap "the arena never frees").
- Multi-driver dominance on memory ports: `connect` keeps the last driver, exactly as `slice.from` does (`:709`); E003 forbids multiple drivers upstream.
- `transport.zig`'s legacy 3-byte state encoding is width-1 only (`toTransportByte` asserts at `:285`); `encodeState` over a multi-bit memory `out` would trap, as it already does for every multi-bit component — pre-existing, not on the host path.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| engine | `lib/memimage.zig` | Headerless raw image codec (decision 2). Imports only `std`; reached as a plain relative `@import("memimage.zig")` from `circuit.zig`, so it rides inside `circuit_mod`, `circuit_mod_for_wasm` and `bench_circuit_mod` with no `build.zig` registration. Owns a private `wordMask(W)` (W=64 branch) because `circuit.widthMask` (`lib/circuit.zig:333-337`) is not `pub`. Inline tests for every error and the round-trip. |
| plans | `DOCS/PLANS/PHASE_1_engine_memories_and_image_codec.md` (this file), `DOCS/STATUS.md` entries | Plan artifacts. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| engine | `lib/circuit.zig:2-3` | Add `pub const memimage = @import("memimage.zig");` (pub, next to `pub const memory` at :2 — every later consumer reaches the codec as `engine.memimage`, never by a second relative import); add `test { _ = memimage; _ = transport; }` so both files' tests are collected (transport's single test at `:59-72` is not collected today because nothing in a test path references the file). |
| engine | `lib/circuit.zig:26-31` | Add `ADDR_PORT_NAME = "addr"`, `DIN_PORT_NAME = "din"`, `WE_PORT_NAME = "we"`, `CLK_PORT_NAME = "clk"` beside the existing port-name constants. |
| engine | `lib/circuit.zig:71-146` (exhaustive, no `else`) | New `.memory => \|*m\|` arm: RAM edge-write block guarded by `m.mode == .ram`, then `calculated_state = memoryReadOut(circuit, component)`. Pseudocode under *Execution & Concurrency Model*. |
| engine | `lib/circuit.zig:154-157` (`else`-guarded delay switch) | **Deliberate no-change**: memories fall into `else => PROPAGATION_DELAY` (gate class). Add a comment naming `.memory` so the next reader sees the decision. |
| engine | `lib/circuit.zig:170` | Add `pub const MAX_ADDR_WIDTH: u8 = 16;` beside `MAX_WIDTH`. |
| engine | `lib/circuit.zig:351` | `ComponentType` gains `memory` (last). |
| engine | `lib/circuit.zig:353-365` | Delete `toKind` (dead; its numbering contradicts `format.zig:6-27`). |
| engine | `lib/circuit.zig:385-408` | `Kind` union gains the `memory` payload (see *Data & State*); `MemoryMode`/`MemCells`/`MemoryError` declared `pub` at file scope above `Component`. |
| engine | `lib/circuit.zig:416-432` (exhaustive) | `deinit`: `.memory => \|*m\| { free(m.cells.values); free(m.cells.defined); }`. |
| engine | `lib/circuit.zig:660-669` | `createComponent`: after `Component.init`, `switch (new_component.kind) { .memory => \|*m\| { if A ∉ 1..MAX_ADDR_WIDTH return error.InvalidAddrWidth; std.debug.assert(m.cells.values.len == 0 and m.cells.defined.len == 0); allocate both planes (`1 << A` u64, zeroed) }, else => {} }`. Planes are **always** allocated here (PLANS_PROMPT.md Phase 1 row: "planes allocated in `createComponent`"); a caller-supplied slice is a programming error, never a supported path, so no length mismatch can reach the recalc arm's `cells[idx]` indexing. The `out` slot is still allocated by `allocateStateSlot(width)` at `:665`, so `width = state_handle.tier` (`:68`) holds; `W` is never stored on the payload. |
| engine | `lib/circuit.zig:671-724` (exhaustive) | `connect`: `.memory` arm accepting `addr` for both modes and `din`/`we`/`clk` only when `m.mode == .ram`; anything else `error.InvalidInputPort`. Note `:677` appends to `fromComponent.outputs` *before* the switch for every kind — pre-existing, unchanged. |
| engine | `lib/circuit.zig:797-826` | After `propagateEvent`: `memoryWriteWord`, `memoryClear`, `memoryLoadImage`, `memoryStoreImage`, private `memoryRefresh`. File-scope `pub fn memoryReadOut` and `pub fn memoryCells` next to `calculateDominantState` (`:33`). |
| engine | `lib/circuit.zig:1920-1925` | Fix the latent expectation to `0b01` **and** rewrite the comment at `:1921` (which currently derives `output value=(0b0110 >> 1) & 0b11 = 0b11`) to: "raw shift gives 0b11; the pool canonicalises `value & defined` (`Pool.write` `:569`) so the committed value is 0b01". Without the comment rewrite the assertion and its own explanation contradict each other. |
| engine | `lib/transport.zig:7-18` (exhaustive) | `kindByte`: `.memory => \|m\| switch (m.mode) { .rom => 8, .ram => 9 }` — the same numbers `format.ComponentKind` will take in Phase 2. |
| build | `build.zig:1548-1559` (next to the interpreter tests) | `const engine_tests = b.addTest(.{ .root_module = circuit_mod });` + `test_step.dependOn(&b.addRunArtifact(engine_tests).step);` (`test_step` declared at `:967`). No new `createModule`, no `addImport`. |
| docs | `CLAUDE.md:109` | "Nine component kinds … `memory`"; numbering corrected to `format.zig`'s (`and_gate=2`, `wire=3`, `led=4`); note that the engine kind carries `mode` while the wire keeps two kinds (numbers land in Phase 2). |
| docs | `DOCS/simulation-engine.md:62-107` | Add `memory` to the quoted `ComponentType` (`:64-66`) and `Kind` (`:68-82`) listings (payload as in *Data & State*); replace the `toKind` block (`:91-107`, "The integer encoding used by the topology format … is:") with a pointer to `lib/topology/format.zig:6-27` (`and=2`, `wire=3`, `led=4`) and one sentence that the engine kind carries `mode` while the wire keeps two kinds (`rom=8`/`ram=9`, allocated in Phase 2). Delivered in slice 3 with the `CLAUDE.md:109` edit. |
| docs | `DOCS/architecture.md:60-70` | "There are nine kinds"; add a `memory` row: inputs `"addr"` (+ `"din"`, `"we"`, `"clk"` for `.ram`), output `"out"`, note "asynchronous read; `.ram` writes on the defined rising edge of `clk`". Delivered in slice 3. |

**New dependencies:** None.

## Data & State

```zig
// lib/circuit.zig (file scope, all pub — Component.Kind itself stays private)
pub const MAX_ADDR_WIDTH: u8 = 16;              // 65,536 words; PLANS_PROMPT width bound
pub const MemoryMode = enum { rom, ram };

/// Cell planes, one u64 per word, length `1 << addr_width`. Allocated by
/// createComponent only (callers leave the slices empty). Canonical form
/// mirrors Pool.write (:569-570): `values[i] & ~defined[i] == 0`, bits ≥ W
/// zero. All-zero planes == every cell undefined (unloaded/unwritten).
pub const MemCells = struct {
    addr_width: u8,
    values: []u64 = &.{},
    defined: []u64 = &.{},
    pub fn wordCount(self: MemCells) usize { return @as(usize, 1) << @intCast(self.addr_width); }
};

// inside `const Kind = union(ComponentType)` (lib/circuit.zig:385-408), after `concat`:
memory: struct {
    mode: MemoryMode,
    cells: MemCells,
    /// Single driver per port (slice `from` precedent, :401/:709). `din`,
    /// `we`, `clk` stay null on a rom — `connect` refuses to set them.
    addr: ?*Component = null,
    din: ?*Component = null,
    we: ?*Component = null,
    clk: ?*Component = null,
    /// Last committed clk state, stored *before* acting (decision 5).
    /// Initial undefined ⇒ the first defined-high clk is not an edge.
    prev_clk: BitVecState = BitVecState.undefined_(1),
},

/// Declared in slice 3 (createComponent already returns InvalidAddrWidth there).
pub const MemoryError = error{ NotAMemory, AddressOutOfRange, BufferTooSmall, InvalidAddrWidth };

/// Shared by the recalc arm and every host hook. Precondition (Debug assert):
/// `comp.kind == .memory` — hosts reach it only through the hooks, which
/// return NotAMemory first. addr null or any undefined address bit ⇒
/// undefined_(W); else cells[addr.value & widthMask(A)].
pub fn memoryReadOut(circuit: *const Circuit, comp: *const Component) BitVecState;
/// null when `comp.kind != .memory`; Phase 2's getMemValue/getMemDefined and
/// Phase 3's peek/mem read the planes through this, never through the pool.
pub fn memoryCells(comp: *const Component) ?*const MemCells;

// Circuit methods (host hooks). Precondition for all mutators: event queue
// empty (true after every propagateEvent/propagate return).
pub fn memoryWriteWord(self: *Circuit, comp: *Component, addr: usize, state: BitVecState) (MemoryError || std.mem.Allocator.Error)!void;
pub fn memoryClear(self: *Circuit, comp: *Component) (MemoryError || std.mem.Allocator.Error)!void;
pub fn memoryLoadImage(self: *Circuit, comp: *Component, bytes: []const u8) (MemoryError || memimage.MemoryImageError || std.mem.Allocator.Error)!usize; // words loaded
pub fn memoryStoreImage(self: *const Circuit, comp: *const Component, buf: []u8) MemoryError!usize; // bytes written = bpw << A
fn memoryRefresh(self: *Circuit, comp: *Component) std.mem.Allocator.Error!void;
```

```zig
// lib/memimage.zig — headerless raw image (decision 2). Imports only std.
pub const MemoryImageError = error{ LengthNotWordMultiple, WordExceedsWidth, TooManyWords };

/// Private twin of circuit.widthMask (:333-337, not pub): maxInt(u64) for
/// W == 64, else (1 << W) - 1 — never shifts a u64 by 64.
fn wordMask(data_width: u8) u64;
pub fn bytesPerWord(data_width: u8) usize;                 // (W + 7) / 8, W ∈ 1..64
pub fn maxImageSize(data_width: u8, addr_width: u8) usize; // bytesPerWord(W) << A
/// Pure check; returns the word count n. Order of checks: len % bpw
/// (LengthNotWordMultiple) → n ≤ 2^A (TooManyWords) → every word's bits ≥ W
/// are zero (WordExceedsWidth; vacuous for W = 64). Does not touch any plane.
pub fn validate(bytes: []const u8, data_width: u8, addr_width: u8) MemoryImageError!usize;
/// validate, then REPLACE-ALL: values[i] = word_i, defined[i] = wordMask(W)
/// for i < n; both planes zeroed for i ≥ n (short image ⇒ tail undefined;
/// empty image ⇒ clear). A failed validate leaves the planes byte-identical.
pub fn decode(bytes: []const u8, data_width: u8, addr_width: u8, values: []u64, defined: []u64) MemoryImageError!usize;
/// Writes every word as `values[i] & defined[i]` little-endian (undefined
/// bits become 0 — definedness is not representable on disk). Asserts
/// buf.len ≥ values.len * bpw; returns bytes written.
pub fn encode(values: []const u64, defined: []const u64, data_width: u8, buf: []u8) usize;
```

Image layout (locked): word `i` occupies `[i*bpw, (i+1)*bpw)`; byte `b` of a word carries bits `8b..8b+7`; no magic, no header, no sniffing. `maxImageSize(64, 16) = 524,288` bytes; the planes for the same memory are 2 × 512 KiB.

**Interfaces consumed from earlier phases:** none in code. Phase 0's `error.MemoryNotYetSupported` (serializers) keeps every CLI mode rejecting memories, which is what makes this phase a pure library change.

**Interfaces exposed to later phases (fixed vocabulary):**

| Consumer | Uses |
|----------|------|
| Phase 2 `templates/interpreter.zig:44-65`, `lib/engine_session.zig:72-93` | `createComponent(.{ .memory = .{ .mode, .cells = .{ .addr_width } } }, W)` — one node per record, planes allocated inside `createComponent`; `connect(.., .{ mem, "addr" \| "din" \| "we" \| "clk" })` after the five port mappers learn `PortName` 4..7. |
| Phase 2 `templates/main.zig` exports | `memoryCells` (→ `getMemInfo` kind/W/A, `getMemValue`/`getMemDefined`), `memimage.maxImageSize` (→ `memBuffer` size), `memoryLoadImage` (→ `memLoad`, errors → `-2/-3/-4`), `memoryStoreImage` (→ `memStore`), `memoryClear` (→ `memClear`), `memoryWriteWord` with `BitVecState.fromRaw(value, defined, W)` (→ `setMemWord`; `AddressOutOfRange` → `-7`, `NotAMemory` → `-1`). |
| Phase 3 `engine_session.Session.applyImage`, sim verbs | `memoryLoadImage` (`load`, `--mem`; `MemoryImageError` → `E_MEMFMT`), `memoryStoreImage` (`save`), `memoryWriteWord` (`poke`; `AddressOutOfRange` → `E_ADDR`), `memoryClear` (`clear`), `memoryCells` (`peek`, `mem`). |
| Phase 2 `transport`/docs | `transport.kindByte` 8/9 already agrees with the wire numbers Phase 2 allocates in `format.ComponentKind`. |
| Phase 2/3 `engine.memimage` | `pub const memimage` re-export: `bytesPerWord`, `maxImageSize`, `validate`, `MemoryImageError` — the only route to the codec outside `circuit.zig` (Zig rejects a file imported into two modules). |

## Execution & Concurrency Model

This phase is fully synchronous. No background threads or workers are introduced. All new state is owned by the `Component` payload (planes, port pointers, `prev_clk`) or is a stack value; the pool keeps owning the single `out` slot.

**Recalc arm** (`lib/circuit.zig:71-146`, runs in Phase 2 of `propagate()` at `:769-778` with every same-timestamp event already committed at `:756-763`):

```zig
.memory => |*m| {
    if (m.mode == .ram) {
        const now = if (m.clk) |c| circuit.readState(c.state_handle) else BitVecState.undefined_(1);
        const rising = bit0High(now) and bit0Low(m.prev_clk);   // defined-low → defined-high only
        m.prev_clk = now;                                         // BEFORE acting: idempotent per step
        if (rising) {
            const we = if (m.we) |w| circuit.readState(w.state_handle) else BitVecState.undefined_(1);
            if (bit0High(we)) if (m.addr) |a| {
                const as = circuit.readState(a.state_handle);
                const am = widthMask(m.cells.addr_width);
                if ((as.defined & am) == am) {
                    const idx: usize = @intCast(as.value & am);
                    const d = if (m.din) |x| circuit.readState(x.state_handle) else BitVecState.undefined_(width);
                    const wm = widthMask(width);
                    m.cells.defined[idx] = d.defined & wm;               // partial-X din stored as-is
                    m.cells.values[idx] = d.value & d.defined & wm;      // canonical, like Pool.write :569
                }
            };
        }
    }
    calculated_state = memoryReadOut(circuit, component);
},
```

`bit0High(s) = (s.defined & 1) != 0 and (s.value & 1) != 0`, `bit0Low(s) = (s.defined & 1) != 0 and (s.value & 1) == 0` — private helpers, width-agnostic (decision 5's graft), so a non-width-1 driver on `we`/`clk` (impossible after Phase 0's `E014`, but reachable from a hand-built topology) reads bit 0 instead of tripping the `width == 1` asserts at `:265/:271`. Compare/enqueue at `:148-164` is unchanged: `out` moves at `current_time + PROPAGATION_DELAY` only when it differs.

Why this is correct under the two-phase engine:
- *Idempotency.* Phase 2 recalculates a node once per changed upstream *and* once per `outputs` entry (`:677` appends per connection, `:770` iterates all of them); a RAM whose `clk` and `din` come from one input is recalculated ≥ 2× in a step. Because `prev_clk` is stored before the write, the second call sees `prev == now` and cannot fire; because all same-T commits precede Phase 2, both calls read identical `din`/`we`/`addr`, so the double recalc is not black-box observable through the cells — the tests below observe it through `prev_clk` and through a later level change instead.
- *Level-insensitivity.* `prev_clk` is updated on every recalc, not only on writes; a `din`/`we` change while `clk` stays high sees `prev == now` — no write. (Updating `prev_clk` only inside the write branch would turn a `we`-low edge into a pending write that fires on the next `din` change — the bug the "updated before acting, unconditionally" wording forbids.)
- *No missed edge.* Every `clk` transition is a committed state change that puts the RAM in the upstream's `outputs`; no-op host drives never enter the queue (`:813-817`).
- *Zero setup/hold.* `din`/`we`/`addr` committed at the same T as `clk` are visible (all committed in Phase 1 before any Phase-2 recalc).
- *Timing.* Cell write is immediate at T; if `addr` presents the written word, `out` shows it at T+5 through the normal enqueue. ROM: addr change at T → out at T+5. Downstream `output_pin` +1.
- *`*const Circuit`.* The arm mutates only `m.cells`/`m.prev_clk` through the pointer capture; the pool is untouched until the scheduled event commits at `:762`.
- *Heap ordering.* The arm enqueues at most one event per call and every call in a step computes the same `calculated_state`, so no divergent same-T events for one component ever exist (trap noted in the plan prompt).

**Host hooks** (`Circuit` methods, called between drives when the queue is empty — true after every `propagateEvent`/`propagate` return, `:825`/`:739`):

```zig
fn memoryRefresh(self: *Circuit, comp: *Component) !void {
    std.debug.assert(self.event_queue.peek() == null);
    const next = memoryReadOut(self, comp);
    if (!self.readState(comp.state_handle).equals(next)) try self.propagateEvent(comp, next);
}
```
`propagateEvent` enqueues at `current_time + 5` and drains (`:819-825`), so downstream consumers resync through the existing machinery. The guard must be `BitVecState.equals` — the same predicate as the dedup at `:756` — because an unconditional call bumps `current_time` at `:814` even when nothing changes, and a looser compare would enqueue an event that `propagate` dedups only after `current_time` was already set at `:741`. `memoryWriteWord` masks `state` to `widthMask(W)` and canonicalises (`value & defined`), checks `addr < wordCount()` (`AddressOutOfRange`), writes both planes, then refreshes. `memoryClear` zeroes both planes, then refreshes. `memoryLoadImage` calls `memimage.decode` (validate-then-write, so a rejected image leaves cells untouched and does **not** refresh), then refreshes. `memoryStoreImage` needs no refresh; it returns `BufferTooSmall` when `buf.len < maxImageSize(W, A)`. All four return `NotAMemory` when `comp.kind != .memory` (Phase 2 maps it to `-1`) — this check runs before anything reaches `memoryReadOut`, whose own `comp.kind == .memory` precondition is a Debug assert only.

## Persistence & I/O

This phase has no persistence or external I/O beyond what prior phases established. `lib/memimage.zig` is a pure `[]const u8` ↔ planes codec; no file, stdin, or network access is added anywhere. The on-disk currency it defines (headerless LE raw image) is consumed by Phase 2's staging buffer and Phase 3's `--mem`/`load`/`save`.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Engine test root | `build.zig`: `engine_tests` over `circuit_mod` wired into `test_step`; `lib/circuit.zig`: `test { _ = transport; }` hook, the `:1925` expectation fix and the `:1921` comment rewrite. Commit: `test(engine): run the engine's inline tests under zig build test`. | `zig build test --summary all` goes from `397/397` to `448/448` (50 engine + 1 transport) and lists `circuit.test.*` lines; the slice test at `:1901-1927` passes with the canonical expectation and a comment that agrees with it. |
| 2 | Raw image codec | `lib/memimage.zig` (incl. private `wordMask`) with inline tests; `lib/circuit.zig` gains the pub relative import (`pub const memimage`) and `test { _ = memimage; }` (nothing else references it yet). Commit: `feat(engine): add headerless raw memory image codec`. | `zig test lib/memimage.zig` and `zig build test` both green with the codec tests listed below; `zig build` still emits `zig-out/lib/circ-runtime.wasm` (proves the wasm module graph resolves the relative import — empirically confirmed before writing this spec). |
| 3 | Memory kind with asynchronous read | `ComponentType.memory`, `MemoryMode`, `MemCells`, `MemoryError`, `MAX_ADDR_WIDTH`, payload, `createComponent` planes (always allocated) + `InvalidAddrWidth`, `deinit`, `connect` arms, recalc arm **without** the RAM block, `memoryReadOut`, `memoryCells`; `transport.kindByte` 8/9; `toKind` deleted; `CLAUDE.md:109`, `DOCS/simulation-engine.md:62-107`, `DOCS/architecture.md:60-70`. Commit: `feat(engine): add memory component kind with asynchronous read`. | Unit tests `memory: unloaded cells read undefined`, `memory: async read through undefined addr`, `memory: connect policy per mode`, `memory: createComponent rejects addr_width out of range`, `memory: delay class is gate delay`, `transport: memory kind bytes`; `grep -rn toKind` empty across the whole tree (`.zig` and `DOCS/`, excluding `PLANS_PROMPT.md`/`PLANS/` which describe the deletion); `zig build` green. |
| 4 | RAM rising-edge write | The `if (m.mode == .ram)` block, `bit0High`/`bit0Low`. Commit: `feat(engine): commit ram writes on the defined rising edge of clk`. | Unit tests `ram: writes only on defined-low to defined-high` (incl. X→1 is not an edge), `ram: requires we high and fully defined addr`, `ram: same-step din is captured`, `ram: no double fire when clk and din change together`, `ram: level changes while clk high do not write`, `ram: partial-X din stored as-is`, `ram: width-agnostic we/clk bit test`. |
| 5 | Host hooks | `memoryWriteWord`, `memoryClear`, `memoryLoadImage`, `memoryStoreImage`, `memoryRefresh` (the error set `MemoryError` already exists from slice 3). Commit: `feat(engine): add host memory hooks with change-guarded refresh`. | Unit tests `memory: host write to presented address resyncs out`, `memory: no-op refresh does not bump current_time`, `memory: load image replaces all cells and resyncs`, `memory: failed load leaves cells untouched`, `memory: store writes value & defined`, `memory: clear undefines every cell`, `memory: hooks reject non-memory and out-of-range`; STATUS entry closes the phase. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own. Slice 1 exists because without it slices 2–5 have no executing tests; keep it to the build wiring plus the one assertion/comment fix so the diff is trivially reviewable.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `memimage: bytesPerWord and maxImageSize` | `lib/memimage.zig` | `bpw(1)=1, bpw(8)=1, bpw(9)=2, bpw(64)=8`; `maxImageSize(8,4)=16`, `maxImageSize(64,16)=8<<16`. |
| `memimage: round-trip` | same | W=12, A=3: encode 8 words → `bpw=2`, 16 bytes; decode into fresh planes → identical `values`, `defined == 0xFFF` for all 8, returns 8. W=64 with `0xDEADBEEF_CAFEBABE` round-trips exactly. |
| `memimage: W=64 has no padding bits` | same | W=64, A=1: all-`0xFF` 16-byte image decodes without `WordExceedsWidth`, `values[i] == maxInt(u64)`, `defined[i] == maxInt(u64)` (exercises the `wordMask` W=64 branch — no shift by 64). |
| `memimage: short image leaves tail undefined` | same | 3 words into A=3 planes pre-filled with garbage → words 0..2 defined, 3..7 `values==0 and defined==0`; returns 3. Empty slice → all zero, returns 0. |
| `memimage: LengthNotWordMultiple` | same | W=12 (`bpw=2`), 3 bytes → error; planes untouched (compare against a copy). |
| `memimage: WordExceedsWidth` | same | W=12, word bytes `0x00 0x10` (bit 12 set) → error; W=8 never errors on any byte; W=1 byte `0x02` → error. Planes untouched. |
| `memimage: TooManyWords` | same | A=2, 5 words → error; exactly 4 words ok. |
| `memimage: encode writes value & defined` | same | `values[0]=0xFF, defined[0]=0x0F` (W=8) encodes byte `0x0F`. |
| `memory: unloaded cells read undefined` | `lib/circuit.zig` | ROM `[8,4]`, `addr` input driven to defined 3 → `out.equals(undefined_(8))`; `memoryCells(rom).?.defined[3] == 0`. |
| `memory: async read through undefined addr` | same | After `memoryLoadImage` of 16 bytes `0..15`: addr `fromRaw(3, 0xF, 4)` → `out == {3, 0xFF}` at `current_time` advanced by 5+5 (input event, then gate delay); addr `fromRaw(3, 0b0111, 4)` (bit 3 undefined) → `out == undefined_(8)`; addr back to fully defined 5 → `out == 5`. |
| `memory: connect policy per mode` | same | rom accepts `addr`, returns `error.InvalidInputPort` for `din`, `we`, `clk`, `in`; ram accepts all four, rejects `in`/`a`/`b`; `memoryReadOut` on a memory with `addr == null` is `undefined_(W)`; `memoryCells` on a `.wire` is `null`. |
| `memory: createComponent rejects addr_width out of range` | same | `addr_width = 0` and `17` → `error.InvalidAddrWidth`; `1` and `16` succeed with `values.len == defined.len == 2` / `65536`, all zero. |
| `memory: delay class is gate delay` | same | ROM `out` changes exactly `PROPAGATION_DELAY` after the input pin's commit (`current_time == 2*PROPAGATION_DELAY` after one `propagateEvent`), not `WIRE_PROPAGATION_DELAY`. |
| `transport: memory kind bytes` | `lib/transport.zig` | `encodeState` on a `.rom` node yields byte 8, on `.ram` byte 9 (W=1 so `toTransportByte` is legal). |
| `ram: writes only on defined-low to defined-high` | `lib/circuit.zig` | RAM `[8,2]`, `we` high, `addr` 1, `din` 0xAB: `clk` undefined→high → cell 1 stays undefined (X→1 is not an edge); `clk` high→low→high → `cells.values[1]==0xAB, defined==0xFF` and `out` (addr presented) `== 0xAB` after the pulse. |
| `ram: requires we high and fully defined addr` | same | Edge with `we` low → no write; `we` undefined → no write; `addr` `fromRaw(1, 0b01, 2)` (one undefined bit) → no write; all three cases leave every cell `defined == 0`. |
| `ram: same-step din is captured` | same | RAM `[1,1]`; one width-1 input `x` connected to **both** `clk` and `din` (so the RAM appears twice in `x.outputs`, `:677`); inputs `we` (defined high) and `addr` (defined 0). Drive `x` low and settle (`prev_clk` becomes defined-low); then drive `x` high in one `propagateEvent` → `cells.values[0] == 1, defined[0] == 1`: the same-timestamp `din` commit (Phase 1, `:756-763`) is visible to the edge write (Phase 2, `:769-778`), and the double recalc does not disturb it. |
| `ram: no double fire when clk and din change together` | same | Same fan-out topology as above, with `we` driven by its own width-1 input. Observables: (a) immediately after the `x` low→high step, `comp.kind.memory.prev_clk.equals(circuit.readState(x.state_handle))` — the detector consumed the edge on the first of the two recalcs; (b) with `clk` held high, toggle `we` high→low→high (each toggle recalculates the RAM) → cell 0 still holds exactly the value captured at the edge (`values[0]==1, defined[0]==1`), and a following `memoryWriteWord`-free check of `cells` shows no other cell touched. |
| `ram: level changes while clk high do not write` | same | Edge with `we` low (no write); then `we`→high while `clk` stays high → still no write; then `clk` low→high → write. |
| `ram: partial-X din stored as-is` | same | `din = {value 0b1010, defined 0b1111_0000}` on W=8 → `cells.defined[a] == 0xF0`, `values[a] == 0x00` (canonical: `value & defined`); `out == {0x00, 0xF0}`. |
| `ram: width-agnostic we/clk bit test` | same | `we` driven by a width-4 input: `fromRaw(0b0001, 0xF, 4)` counts as high (write happens), `fromRaw(0b1110, 0xF, 4)` counts as low (no write); no assertion trips in Debug. |
| `memory: host write to presented address resyncs out` | same | ROM addr = 2, `memoryWriteWord(rom, 2, {0x5A, 0xFF, 8})` → `out == 0x5A`, downstream `output_pin == 0x5A`, `current_time` advanced by exactly `PROPAGATION_DELAY + WIRE_PROPAGATION_DELAY`. |
| `memory: no-op refresh does not bump current_time` | same | addr = 2; `memoryWriteWord(rom, 7, …)`, `memoryLoadImage` with an image whose word 2 equals the current one, `memoryWriteWord(rom, 2, same value)` → `current_time` unchanged after each, queue empty, `out` unchanged. |
| `memory: load image replaces all cells and resyncs` | same | Load 16 words, then load 4 words → cells 4..15 undefined, `out` at addr 9 becomes `undefined_(8)` (time advanced by 5); empty image ≡ `memoryClear`. |
| `memory: failed load leaves cells untouched` | same | After a good load, `memoryLoadImage` with 17 words (A=4) → `error.TooManyWords`; planes equal the pre-call snapshot; `current_time` unchanged. |
| `memory: store writes value & defined` | same | `memoryStoreImage` into `maxImageSize` buffer returns `16`; byte for an undefined cell is `0`, for `{0x5A,0xFF}` is `0x5A`; buffer of 15 bytes → `error.BufferTooSmall`. |
| `memory: clear undefines every cell` | same | After a full load and addr = 9, `memoryClear` → every `defined[i] == 0`, `values[i] == 0`, `out == undefined_(8)`, time advanced by 5. |
| `memory: hooks reject non-memory and out-of-range` | same | Every hook on a `.wire` → `error.NotAMemory`; `memoryWriteWord(rom, 16, …)` on A=4 → `error.AddressOutOfRange`, cells untouched. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `zig build test` | whole tree | Green; summary counts the engine, transport and memimage tests (448 after slice 1, growing with each slice); every existing golden byte-identical (`git status` shows only the files in the topology table). |
| `zig build` (default step) | wasm runtime | `zig-out/lib/circ-runtime.wasm` rebuilds from `circuit_mod_for_wasm` with the new kind and the relative `memimage` import; `zig build test`'s `serializer_fixtures_test`/`cli_e2e_test` still drive the rebuilt runtime for every scalar fixture (no memory reaches it — Phase 0's rejection). |
| `tests/cli/integration_test.zig` rejection cases (Phase 0) | CLI | Unchanged: `rom_basic.circ` in every artifact mode still exits 1 with `rom/ram are not yet supported in this mode` — proof the phase is user-invisible. |
| `zig build bench` | bench engine | `bench_circuit_mod` (`build.zig:1603-1608`) compiles with `COLLECT_METRICS = true`; `engine.bench.golden` counters unchanged (no memory in the corpus). |

Run command: `zig build test` (full fast suite). Single modules: `zig test lib/memimage.zig` (no dependencies), and for the engine `zig test --dep build_options -Mroot=lib/circuit.zig -Mbuild_options=<scratch file containing `pub const collect_metrics = false;`>` — the incantation used to discover the `:1925` failure; after slice 1 `zig build test` is the canonical way. `zig build test-all` before the final slice.

## Open Questions / Spikes

- `TODO(phase1)`: `memoryRefresh` asserts an empty event queue in Debug. Decide whether Phase 2's exports should also guard at runtime (return `-1`) if a host calls a mutator from inside an `onDebugLog` callback mid-propagate; the engine-side assert is enough for this phase.
- None otherwise — decisions 1, 2, 3 and 5 of `DOCS/PLANS_PROMPT.md` fix every semantic choice this phase makes (single kind with `mode`, headerless image, replace-all, defined-edge rule with `prev_clk`-before-act), and the `build.zig` `addTest` question is resolved in *Scope* (repo-standard mechanism, runtime module set untouched, empirically verified).
