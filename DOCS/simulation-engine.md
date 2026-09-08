# Simulation Engine Reference

Source: [lib/circuit.zig](../lib/circuit.zig)

The engine is a pure Zig library: no WASM, no I/O, no JSON. It models a circuit as a directed graph and advances time with a min-heap event queue. The compiled `.wasm` runtime in `templates/main.zig` and the unit tests in `tests/` are both clients of this same `Circuit` API.

All allocations route through `memory.allocator` from `lib/memory.zig`. There is no per-call allocator parameter on the engine itself. On a WASM target this is `std.heap.wasm_allocator`; on native (`zig build test`) it is a `GeneralPurposeAllocator`.

## Why the storage and value layers are split

Wire state used to live inline on every `Component` as a single-bit `State` enum. That worked for width-1 wires but baked the storage layout into the propagator. The engine has since been refactored into two layers:

- A **value type**, `BitVecState`, that carries `(value, defined, width)` and is the currency of every event, dedup check, gate evaluation, and listener callback.
- A **width-tiered Structure-of-Arrays pool** owned by `Circuit`, addressed by an opaque `PoolHandle`. Components carry a `state_handle` instead of an inline state field; reads and writes go through `Circuit.readState` / `Circuit.writeState`.

Widths 1 through 64 are all wired today; the engine allocates a pool tier on demand the first time a component of that width is created. Lazy tier init keeps single-bit circuits at one allocated pool instead of 64. Most callers only need `readState` / `writeState` plus the `BitVecState` constructors and predicates; `Pool` is exposed but rarely used directly.

## Types

### `BitVecState`

```zig
pub const BitVecState = struct {
    value: u64,
    defined: u64,
    width: u8,

    pub fn undefined_(width: u8) BitVecState;
    pub fn low(width: u8)        BitVecState;
    pub fn high(width: u8)       BitVecState;

    /// General constructor used at the WASM host boundary (`setPin`); each
    /// bit of `defined` says whether the matching `value` bit is meaningful.
    pub fn fromRaw(value: u64, defined: u64, width: u8) BitVecState;

    pub fn equals(self: BitVecState, other: BitVecState) bool;
    pub fn flip(self: BitVecState) BitVecState;

    pub fn isHigh(self: BitVecState) bool;       // width=1 only
    pub fn isLow(self: BitVecState)  bool;       // width=1 only
    pub fn isUndefined(self: BitVecState) bool;  // any width

    pub fn fromInt(int: i32, width: u8) BitVecState;  // 0→low, 1→high, else→undefined (width=1)
    pub fn toInt(self: BitVecState) i32;              // low=0, high=1, undefined=2
    pub fn toTransportByte(self: BitVecState) u8;     // undefined=0, low=1, high=2 (declaration order)
    pub fn tagName(self: BitVecState) []const u8;     // "low" | "high" | "undefined"
};

pub const MAX_WIDTH: u8 = 64;
```

`undefined` models an undriven wire. Logic gates treat undefined inputs as absence of signal. Equality treats two undefined slots as equal regardless of the bits in `value`:

```
(a.defined == b.defined) AND ((a.value & a.defined) == (b.value & b.defined))
```

That preserves the old `State.undefined == State.undefined` rule, which the Phase-1 dedup in `propagate()` relies on (see the [Simulation step](#simulation-step) section below).

Note that `toInt` and `toTransportByte` use **different** encodings. Neither is on the host-facing WASM API path anymore: the boundary now crosses `BitVecState` halves directly via `setPin(id, value, defined)` and the paired `getOutputValue(id)` / `getOutputDefined(id)` getters. `toInt` (`low=0, high=1, undefined=2`) survives as a width-1 convenience mirror of the historical `State` enum, used only by tests. `toTransportByte` is byte-identical to the old `@intFromEnum(State)` mapping (`undefined=0, low=1, high=2`) and is used by `lib/transport.zig` so the topology snapshot format does not have to learn new bytes.

### `ComponentType` and `Component.Kind`

```zig
pub const ComponentType = enum {
    input_pin_gate, not_gate, led, and_gate, wire, output_pin, slice, concat, memory,
};

pub const MemoryMode = enum { rom, ram };

/// Cell planes, one u64 per word, length `1 << addr_width`; allocated by
/// `Circuit.createComponent`. All-zero planes mean every cell is undefined.
pub const MemCells = struct { addr_width: u8, values: []u64, defined: []u64 };

const Kind = union(ComponentType) {
    input_pin_gate: struct { inputs: std.ArrayList(*Component) = .{} },
    not_gate:       struct { inputs: std.ArrayList(*Component) = .{} },
    led:            struct { inputs: std.ArrayList(*Component) = .{} },
    and_gate:       struct {
        inputs_a: std.ArrayList(*Component) = .{},
        inputs_b: std.ArrayList(*Component) = .{},
    },
    wire:           struct { inputs: std.ArrayList(*Component) = .{} },
    output_pin:     struct { inputs: std.ArrayList(*Component) = .{} },
    slice:          struct { from: ?*Component = null, lo: u8 = 0, hi: u8 = 0 },
    concat:         struct { operands: std.ArrayList(*Component) = .{} },
    memory:         struct {
        mode: MemoryMode,
        cells: MemCells,
        addr: ?*Component = null,
        din: ?*Component = null,   // ram only
        we: ?*Component = null,    // ram only
        clk: ?*Component = null,   // ram only
        prev_clk: BitVecState = BitVecState.undefined_(1),
    },
};
```

Backward edges are flat `std.ArrayList(*Component)` lists for the eight-input gates (`and_gate` uses `inputs_a` / `inputs_b`; every other "input-based" kind uses a single `inputs` list keyed by `"in"`). `output_pin` is the sub-circuit/root output primitive: it appears in the IR for every `output …` declaration and acts as a wire-with-a-name.

`slice` and `concat` are bit-shape kinds, not user-written primitives. The resolver lowers the language-level `a[lo..hi]`, `a[i]`, and `{a, b, ...}` signal sources into these kinds; users never write them directly.

- A `slice` reads `from`'s current state, masks to bits `[lo, hi)`, and shifts right by `lo`. The output's width is `hi - lo`. Bit-index `a[i]` lowers to a slice with `hi = lo + 1`.
- A `concat` ORs each operand into a running bit-position. Operands listed low-on-left: bits `[0, op0.width)` come from `op0`, bits `[op0.width, op0.width + op1.width)` from `op1`, and so on. The output's width is the sum of operand widths.

`memory` is the native `rom`/`ram` primitive. The engine has one kind carrying a `mode`; the wire format keeps two kinds (`rom=8`, `ram=9`). Its cells are two `u64` planes on the payload (never pool slots), and the pool slot holds the word presented on `out`: `cells[addr]` when every address bit is defined, otherwise fully undefined (`memoryReadOut`). Reads are asynchronous — an `addr` change re-evaluates `out` at gate delay.

The integer encoding used by the topology format is owned by `lib/topology/format.zig` (`ComponentKind`: `input_pin=0`, `not_gate=1`, `and_gate=2`, `wire=3`, `led=4`, `output_pin=5`, `slice=6`, `concat=7`, with `rom=8` and `ram=9` reserved for memories); the runtime interpreter maps those bytes onto `Component.Kind` when it materialises the topology.

Per-kind port names:

| Kind             | Input ports                                | Output port |
|------------------|--------------------------------------------|-------------|
| `input_pin_gate` | `"in"` (sub-circuit only)                  | `"out"`     |
| `not_gate`       | `"in"`                                     | `"out"`     |
| `and_gate`       | `"a"`, `"b"`                               | `"out"`     |
| `wire`           | `"in"`                                     | `"out"`     |
| `output_pin`     | `"in"`                                     | `"out"`     |
| `led`            | `"in"`                                     | `"out"`     |
| `slice`          | `"in"`                                     | `"out"`     |
| `concat`         | `"operand_0"`, `"operand_1"`, … one per op | `"out"`     |

### `Component`

```zig
pub const Component = struct {
    id: u32,
    kind: Kind,
    /// Opaque handle into the width-tiered pool owned by `Circuit`. Reads
    /// and writes go through `Circuit.readState` / `Circuit.writeState`.
    /// Populated by `Circuit.createComponent` after `Component.init` returns.
    state_handle: PoolHandle = .{ .tier = 0, .slot = std.math.maxInt(u32) },
    /// Forward edges. Every kind has exactly one output port (`"out"`), so
    /// the per-port map collapses to a single slice.
    outputs: std.ArrayList(*Component) = .{},

    pub fn init(id: u32, kind: Kind) !*Component;
    pub fn deinit(self: *Component) void;
    pub fn port(self: *Component, portName: []const u8) ComponentPortReference;
};
```

The `state_handle` default (`slot = maxInt(u32)`) is a sentinel: reads against it trap with an out-of-bounds panic in `Pool.read`. This catches the "constructed a Component without going through `Circuit.createComponent`" mistake.

There is no `output_state` field on `Component` anymore. To read a component's current wire value, use `circuit.readState(component.state_handle)`.

`ComponentPortReference` is a tuple (`pub const ComponentPortReference = struct { *Component, []const u8 }`) produced by `component.port("name")` and consumed by `Circuit.connect`.

### `Event` / `EventQueue`

```zig
pub const Timestamp = u64;

pub const Event = struct {
    timestamp: Timestamp,
    component: *Component,
    new_state: BitVecState,
};
```

Events live in a min-heap (`std.PriorityQueue`) ordered by `timestamp`, so the earliest event always fires first.

### `PoolHandle` and `Pool`

```zig
pub const PoolHandle = struct {
    tier: u8,
    slot: u32,
};

pub const Pool = struct {
    width: u8,
    next_slot: u32 = 0,
    values:  std.ArrayList(u64) = .{},
    defined: std.ArrayList(u64) = .{},

    pub fn init(width: u8) Pool;
    pub fn deinit(self: *Pool) void;
    pub fn allocateSlot(self: *Pool) !u32;
    pub fn read(self: *const Pool, slot: u32) BitVecState;
    pub fn write(self: *Pool, slot: u32, state: BitVecState) void;
};
```

The pool packs 64 slots per `u64` word across two parallel buffers (one for value bits, one for defined bits). The two buffers grow together; `allocateSlot` is the only growth site and always appends to both, so length-mismatch is structurally impossible.

`PoolHandle.tier` selects which pool to dispatch to. The convention is `tier == width`; tier 0 is unused and tiers 1..64 each carry their own pool, lazily allocated the first time a component of that width is created. Width is recovered from the handle's tier, not stored on the handle's body, so handles stay 8 bytes.

You rarely construct `Pool` or `PoolHandle` directly; `Circuit.createComponent` allocates a slot and stamps the handle onto the new component.

### `Circuit`

```zig
pub const Circuit = struct {
    nodes: std.ArrayList(*Component),
    event_queue: EventQueue,
    next_id: u32 = 0,
    current_time: Timestamp = 0,
    listener: ?*const fn (component: *Component, new_state: BitVecState) void = null,
    /// Scratch buffer reused across propagate() calls so the first append in
    /// each propagation does not reallocate from zero capacity.
    changed_at_step: std.ArrayList(*Component) = .{},
    /// Width-tiered SoA pool for wire state. Each entry is `?Pool`, lazily
    /// allocated the first time a component of that width is created.
    /// Indexed by tier where `tier == width`; tier 0 is unused.
    tiers: [MAX_WIDTH + 1]?Pool,
    /// Benchmark counters. Zero-sized (`void`) outside the bench build, so
    /// shipping and test builds carry zero bytes and zero instructions on
    /// the metrics path.
    metrics: if (COLLECT_METRICS) Metrics else void,
};
```

`listener` is an optional callback fired by `notifyStateChange` once per Phase-2 visit of a downstream component during propagation, regardless of whether the visit actually flipped the component's stored state. The compiled WASM runtime does **not** install one; hosts poll `getOutputValue` / `getOutputDefined` after `run()` returns. The callback is intended for native test harnesses and tooling.

### `Metrics`

```zig
pub const COLLECT_METRICS: bool = @import("build_options").collect_metrics;

pub const Metrics = struct {
    events_popped: u64    = 0,
    events_committed: u64 = 0,
    recalcs: u64          = 0,
    peak_queue: u64       = 0,
    final_time: u64       = 0,
};
```

`COLLECT_METRICS` is `true` only for `zig build bench`; production WASM and `zig build test` get the `void` branch and dead-code-strip every counter bump. Outside an `if (COLLECT_METRICS)` block, touching `circuit.metrics.foo` is a compile error (the comptime gate enforces itself).

See `DOCS/benchmark.md` for what the bench does with these counters.

## API

### Construction and teardown

```zig
pub fn init() !Circuit;            // no allocator parameter; uses memory.allocator
pub fn deinit(self: *Circuit) void;
```

`deinit` walks `nodes` and calls `Component.deinit` on each (which frees its input lists), drops the event queue, releases the `changed_at_step` scratch buffer, and iterates the `tiers: [MAX_WIDTH + 1]?Pool` array tearing down every lazily-allocated tier in place.

### State storage

```zig
pub fn allocateStateSlot(self: *Circuit, width: u8) !PoolHandle;
pub fn readState(self: *const Circuit, handle: PoolHandle) BitVecState;
pub fn writeState(self: *Circuit, handle: PoolHandle, state: BitVecState) void;
```

Tier dispatch happens exactly once per read/write, so every layer above these three functions sees only the value type. Any width in `[1, 64]` is legal; out-of-range widths trap via the dispatcher.

You normally do not call `allocateStateSlot` yourself: `Circuit.createComponent` does it as part of publishing a new component.

### Component creation

```zig
pub fn createComponent(self: *Circuit, kind: Component.Kind, width: u8) !*Component;
```

Allocates a `Component`, assigns a monotonically increasing `id`, allocates its state slot via `allocateStateSlot(width)` (tier `width`), stamps the handle onto the component, and appends it to `self.nodes`. The IDs are dense integers `0..nodes.len`, which is what the topology format and the compiled WASM runtime use.

### Connections

```zig
pub fn connect(
    self: *Circuit,
    from: ComponentPortReference,
    to: ComponentPortReference,
) !void;
```

Idiomatic call form:

```zig
try circuit.connect(producer.port("out"), consumer.port("in"));
```

`connect` updates **both** directions: `to` is appended to `from.outputs`, and the appropriate per-kind input list on `to` (selected by the destination port name: `"in"` for most kinds, `"a"` / `"b"` for `and_gate`) gains `from`. This lets propagation walk forward edges to find downstream components while gate evaluation walks backward edges to read driving signals.

Invalid destination port names return `error.InvalidInputPort`.

### Signal injection

```zig
pub fn propagateEvent(
    self: *Circuit,
    component: *Component,
    new_state: BitVecState,
) !void;
```

Enqueues an event for `component` at `current_time + PROPAGATION_DELAY`, then immediately calls `propagate()` itself (it does not just enqueue). Used by the runtime's `setPin` glue.

**No-op short-circuit.** When `readState(component.state_handle).equals(new_state)`, the call skips both the enqueue and the propagate pass, only advancing `current_time` by `PROPAGATION_DELAY`. The timing model and `final_time` counter still match what a full enqueue-and-drain would have produced. This matters in practice because the truth-table corpus driver writes every input pin on every vector; without the short-circuit, fixtures like `and_6bit` spend the majority of pops on events that would not have changed state.

### Simulation step

```zig
pub fn propagate(self: *Circuit) !void;
```

Drains the event queue in **two-phase batches per timestamp**. For each distinct timestamp `T` in ascending order:

1. **Phase 1 (commit):** advance `current_time = T`, pop every queued event at timestamp `T`, write `event.new_state` to the component's pool slot via `writeState` (skipping no-op events whose new state already matches under `BitVecState.equals`), and remember the components that actually changed in `changed_at_step`.
2. **Phase 2 (notify):** walk every changed component's `outputs` list, call the internal `recalculateAndReschedule` on each downstream component, then fire `notifyStateChange` for the optional listener.

The batching is load-bearing: a downstream gate with multiple upstream events at the same `T` would otherwise read partially-updated upstream state in step 2, compute a transient value, and let the next event's dedup check (`if readState(c.state_handle).equals(event.new_state) continue`) silently drop the corrective re-enqueue, leaving the gate stuck on the wrong final value. The bug manifests in deep-fanout circuits where one control bit drives many parallel gates whose outputs feed a serial carry chain (e.g. a 4-bit ALU with shared `nx`/`ny` normalization).

Stops when the queue is empty.

### Gate evaluation (internal)

```zig
fn recalculateAndReschedule(
    circuit: *const Circuit,
    component: *Component,
    queue: *EventQueue,
    current_time: Timestamp,
) !void;
```

Takes the circuit as its first parameter so it can resolve input components' `state_handle`s through `circuit.readState`. Recomputes the expected output of `component` from its current inputs. If the result differs from the component's stored state (read via `readState`), schedules a new event at `current_time + delay(component)`. Per-kind rules:

```
not_gate    → flip(dominant("in"))
and_gate    → low if either of "a"/"b" is low
              undefined if either is undefined
              else high
wire        → first defined input on "in" (collapsed via dominant)
output_pin  → dominant("in")
input_pin   → dominant("in") if wired (sub-circuit case); host-driven otherwise
led         → mirrors dominant("in"); propagates downstream like a wire
```

Delays:

```zig
const PROPAGATION_DELAY: Timestamp = 5;
const WIRE_PROPAGATION_DELAY: Timestamp = 1;
```

`wire`, `output_pin`, `led`, `slice`, and `concat` use the wire delay; everything else uses the gate delay. A chain of `N` gates plus `M` wire-delay components (`wire`, `output_pin`, `led`, `slice`, `concat`) settles after `N*5 + M*1` time units.

### State snapshot

```zig
pub fn encodeState(self: *Circuit) ![]u8;
```

Allocates and returns a buffer encoding every component's `(state, kind, id)` triplet via `lib/transport.zig`. Caller owns the slice and must free it with the engine's allocator. Used by tooling and the experimental `--emit-zig` runtime (`lib/emit/runtime.zig`'s `getStateSnapshot`); not wired into the default-compile WASM artifact.

### Debug printing

```zig
pub fn printState(self: *Circuit) void;
```

Iterates `nodes` and logs `(id, kind, tagName)` for each via `lib/log.zig`. Diagnostic helper; not part of any host-visible contract.

## Dominant state rule

```zig
fn calculateDominantState(
    circuit: *const Circuit,
    input_comp_list: std.ArrayList(*Component),
    width: u8,
) BitVecState;
```

Used by every multi-driver port read:

- Returns `high` immediately if **any** driver reads as `high` (wired-OR bus behaviour).
- Otherwise returns the last seen state during the scan (the loop unconditionally overwrites `dominant_state` on each iteration, so the final iteration wins among the non-`high` drivers).
- Returns `undefined` if every driver is `undefined`.

The width=1 helpers (`isHigh`, `isLow`) are the comparison currency on scalar buses (the most common case). Multi-bit fan-in works the same way per bit: any `defined` bit set to high across the drivers wins; the dominant state is computed bit-parallel against the BitVecState `value` and `defined` fields.
