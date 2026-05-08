# Simulation Engine Reference

Source: [lib/circuit.zig](../lib/circuit.zig)

The engine is a pure Zig library: no WASM, no I/O, no JSON. It models a circuit as a directed graph and advances time with a min-heap event queue. The compiled `.wasm` runtime in `templates/main.zig` and the unit tests in `tests/` are both clients of this same `Circuit` API.

All allocations route through `memory.allocator` from `lib/memory.zig` — there is no per-call allocator parameter on the engine itself. On a WASM target this is `std.heap.wasm_allocator`; on native (`zig build test`) it is a `GeneralPurposeAllocator`.

## Types

### `State`

```zig
pub const State = enum {
    undefined,
    low,
    high,

    pub fn flip(self: State) State;
    pub fn fromInt(int: i32) State;   // 0 → low, 1 → high, anything else → undefined
    pub fn toInt(self: State) i32;    // low → 0, high → 1, undefined → 2
};
```

`undefined` models an undriven wire. Logic gates treat `undefined` inputs as absence of signal. `fromInt`/`toInt` are the integer encoding used at the WASM boundary.

### `ComponentType` and `Component.Kind`

```zig
pub const ComponentType = enum {
    input_pin_gate, not_gate, led, and_gate, wire, output_pin
};

const Kind = union(ComponentType) {
    input_pin_gate: struct { inputs: PortMap },
    not_gate:       struct { inputs: PortMap },
    led:            struct { inputs: PortMap, state: State },
    and_gate:       struct { inputs: PortMap },
    wire:           struct { inputs: PortMap },
    output_pin:     struct { inputs: PortMap },
};
```

`PortMap` is `std.StringHashMap(std.ArrayList(*Component))`: backward edges, keyed by named input port. `output_pin` is the sub-circuit/root output primitive — it appears in the IR for every `output …` declaration and acts as a wire-with-a-name.

The integer encoding used by the topology format (`lib/topology/`) and `Component.Kind` constructor is:

```zig
pub fn toKind(kind: u8) !Component.Kind {
    return switch (kind) {
        0 => .input_pin_gate,
        1 => .not_gate,
        2 => .led,
        3 => .and_gate,
        4 => .wire,
        5 => .output_pin,
        else => return error.InvalidComponentKind,
    };
}
```

Per-kind port names:

| Kind             | Input ports     | Output port |
|------------------|-----------------|-------------|
| `input_pin_gate` | `"in"` (sub-circuit only) | `"out"` |
| `not_gate`       | `"in"`          | `"out"`     |
| `and_gate`       | `"a"`, `"b"`    | `"out"`     |
| `wire`           | `"in"`          | `"out"`     |
| `output_pin`     | `"in"`          | `"out"`     |
| `led`            | `"in"`          | `"out"`     |

### `Component`

```zig
pub const Component = struct {
    id: u32,
    kind: Kind,
    output_state: State = .undefined,
    outputs: PortMap,                // forward edges, keyed by output port name

    pub fn init(id: u32, kind: Kind) !*Component;
    pub fn deinit(self: *Component) void;
    pub fn port(self: *Component, portName: []const u8) ComponentPortReference;
};
```

`ComponentPortReference` is a tuple — `pub const ComponentPortReference = struct { *Component, []const u8 }` — produced by `component.port("name")` and consumed by `Circuit.connect`.

### `Event` / `EventQueue`

```zig
pub const Timestamp = u64;

pub const Event = struct {
    timestamp: Timestamp,
    component: *Component,
    new_state: State,
};
```

Events live in a min-heap (`std.PriorityQueue`) ordered by `timestamp`, so the earliest event always fires first.

### `Circuit`

```zig
pub const Circuit = struct {
    nodes: std.ArrayList(*Component),
    event_queue: EventQueue,
    next_id: u32 = 0,
    current_time: Timestamp = 0,
    listener: ?*const fn (component: *Component, new_state: State) void = null,
};
```

`listener` is an optional callback fired by `notifyStateChange` whenever a component's `output_state` changes during propagation. The compiled WASM runtime does **not** install one — hosts poll `getOutputState` instead. The callback is intended for native test harnesses and tooling.

## API

### Construction and teardown

```zig
pub fn init() !Circuit;            // no allocator parameter — uses memory.allocator
pub fn deinit(self: *Circuit) void;
```

`deinit` walks `nodes`, calls `Component.deinit` on each (which frees its port maps), and drops the event queue.

### Component creation

```zig
pub fn createComponent(self: *Circuit, kind: Component.Kind) !*Component;
```

Allocates a `Component`, assigns a monotonically increasing `id`, and appends it to `self.nodes`. The IDs are dense integers `0..nodes.len`, which is what the topology format and the compiled WASM runtime use.

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

`connect` updates **both** directions: `from.outputs[from_port]` gains `to`, and the appropriate per-kind input map on `to` gains `from`. This lets propagation walk forward edges to find downstream components, while gate evaluation walks backward edges to read driving signals.

### Signal injection

```zig
pub fn propagateEvent(
    self: *Circuit,
    component: *Component,
    new_state: State,
) !void;
```

Enqueues an event for `component` at `current_time + PROPAGATION_DELAY`, then immediately calls `propagate()` itself (it does not just enqueue). Used by the runtime's `setPin` glue.

### Simulation step

```zig
pub fn propagate(self: *Circuit) !void;
```

Drains the event queue. For each event:

1. Updates `current_time` to the event's timestamp.
2. Sets `component.output_state = event.new_state` (skipping no-op events).
3. Walks `component.outputs` and calls the internal `recalculateAndReschedule` on each downstream component, then `notifyStateChange` to drive the optional listener.

Stops when the queue is empty.

### Gate evaluation (internal)

```zig
fn recalculateAndReschedule(
    component: *Component,
    queue: *EventQueue,
    current_time: Timestamp,
) !void;
```

Recomputes the expected output of `component` from its current inputs. If the result differs from `component.output_state`, schedules a new event at `current_time + delay(component)`. Per-kind rules:

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

`wire`, `output_pin`, and `led` use the wire delay; everything else uses the gate delay. A chain of `N` gates plus `M` wires/output_pins/leds settles after `N*5 + M*1` time units.

### State snapshot

```zig
pub fn encodeState(self: *Circuit) ![]u8;
```

Allocates and returns a buffer encoding every component's `(state, kind, id)` triplet via `lib/transport.zig`. Caller owns the slice and must free it with the engine's allocator. Used by tooling and tests; not yet wired into the production WASM runtime.

### Pin assertions

```zig
pub fn assertValidInputPin(component: *Component, pin: u32) !void;
pub fn assertValidOutputPin(component: *Component, portName: []const u8) !void;
```

Used by `connect` and other guards; surface `InvalidInputPin` / `InvalidOutputPort` on misuse.

## Dominant state rule

```zig
fn calculateDominantState(input_comp_list: std.ArrayList(*Component)) State;
```

Used by every multi-driver port read:

- Returns `high` if **any** driver is `high` (wired-OR bus behaviour).
- Otherwise returns the last seen non-`undefined` state during the scan.
- Returns `undefined` if every driver is `undefined`.
