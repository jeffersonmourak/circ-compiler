# Simulation Engine Reference

Source: [lib/circuit.zig](../lib/circuit.zig)

## Types

### `State`

```zig
pub const State = enum { undefined, low, high };
```

`undefined` models an undriven wire. Logic gates treat `undefined` inputs as absence of signal. `low` / `high` map to Boolean 0 / 1. Integer encoding used at the WASM boundary: `low = 0`, `high = 1`, `undefined = 2`.

### `Component`

A `Component` wraps one gate instance:

```zig
pub const Component = struct {
    id: u32,
    kind: Kind,
    output_state: State = .undefined,

    // Adjacency: port name → downstream components
    outputs: std.StringHashMap(std.ArrayList(*Component)),
};
```

`outputs` stores forward edges. Each entry is a named output port (e.g. `"out"`) mapped to the list of `Component` pointers that receive its signal.

### `Kind` — Gate Variants

```zig
pub const Kind = union(enum) {
    input_pin_gate: struct { state: State },
    not_gate:       struct { inputs: PortMap },
    led:            struct { inputs: PortMap, state: State },
    and_gate:       struct { inputs: PortMap },
    wire:           struct { inputs: PortMap },
};
```

`PortMap` is `std.StringHashMap(std.ArrayList(*Component))`. It stores backward edges: the named input ports and the components driving each port.

Named port constants used by each gate type:

| Gate         | Input ports | Output ports |
|-------------|-------------|--------------|
| `input_pin` | —           | `"out"`      |
| `not_gate`  | `"in"`      | `"out"`      |
| `and_gate`  | `"a"`, `"b"`| `"out"`      |
| `led`       | `"in"`      | —            |
| `wire`      | `"in"`      | `"out"`      |

### `Event`

```zig
const Event = struct {
    timestamp: Timestamp,    // u64
    component: *Component,
    new_state: State,
};
```

Events are stored in a min-heap priority queue ordered by `timestamp`, so the earliest event is always processed first.

### `Circuit`

```zig
pub const Circuit = struct {
    nodes: std.ArrayList(*Component),
    event_queue: EventQueue,
    next_id: u32,
    current_time: Timestamp,
    listener: ?*const fn (*Component) void,
};
```

`listener` is an optional callback invoked whenever a component's `output_state` changes after event processing. The WASM layer installs its own listener here to forward state changes to JavaScript.

## API

### Initialisation

```zig
pub fn init(allocator: std.mem.Allocator) !Circuit
pub fn deinit(self: *Circuit) void
```

`deinit` frees all component memory and the event queue.

### Component Creation

```zig
pub fn createComponent(self: *Circuit, kind: Kind) !*Component
```

Allocates a new `Component`, assigns a monotonically increasing `id`, and appends it to `self.nodes`. Returns a pointer to the heap-allocated component.

Component kinds are created by the WASM layer using the integer-to-`Kind` mapping in `wasm.zig`.

### Connections

```zig
pub fn connect(
    self: *Circuit,
    from: *Component,
    from_port: []const u8,
    to: *Component,
    to_port: []const u8,
) !void
```

Establishes a directed edge: `from.outputs[from_port]` gains `to`, and `to.kind.inputs[to_port]` gains `from`. Both forward and backward adjacency are updated so that:

- During propagation, the engine can walk `from.outputs` to find downstream components.
- During gate evaluation, the engine can walk `to.kind.inputs` to read driving signals.

### Signal Injection

```zig
pub fn propagateEvent(
    self: *Circuit,
    component: *Component,
    new_state: State,
) !void
```

Enqueues an event for `component` at `current_time + delay`. This is the external entry point used by JavaScript to drive input pins.

### Simulation Step

```zig
pub fn propagate(self: *Circuit) !void
```

Drains the event queue. For each event:

1. Sets `component.output_state = event.new_state`.
2. Calls `self.listener(component)` if set.
3. Walks `component.outputs` and calls `recalculateAndReschedule` on each downstream.

Stops when the queue is empty (all events settled).

### Gate Evaluation (internal)

```zig
fn recalculateAndReschedule(self: *Circuit, component: *Component) !void
```

Recomputes the expected output of `component` based on its current inputs. If the result differs from `component.output_state`, enqueues a new event at `current_time + delay(component)`. Does nothing if the output would be unchanged.

The evaluation rules per kind:

```
not_gate  → output = NOT readPort("in")
and_gate  → output = readPort("a") AND readPort("b")
led       → output = readPort("in")      (terminal)
wire      → output = readPort("in")      (relay)
input_pin → (never recalculated, driven by propagateEvent)
```

`readPort(name)` collapses all components on that port using `calculateDominantState`.

### State Query

```zig
pub fn getComponentState(self: *Circuit, component: *Component) State
```

Returns the current `output_state` of the component without advancing simulation.

### State Snapshot

```zig
pub fn encodeState(self: *Circuit, buffer: []u8) void
```

Writes one 9-byte `EncodedState` record per component into `buffer`. Format: 1-byte state, 1-byte kind, 4-byte ID (little-endian). Used by the WASM layer to snapshot the full circuit state into a buffer readable from JavaScript.

## Propagation Delays

```zig
const GATE_DELAY: Timestamp = 5;
const WIRE_DELAY: Timestamp = 1;
```

`Timestamp` is `u64`. Delays are additive: a chain of N gates plus M wires settles after `N×5 + M×1` time units. Multiple `propagate()` calls are not needed — a single call drains all cascaded events.

## Dominant State Rule

```zig
fn calculateDominantState(components: []*Component) State
```

Used when multiple components drive the same input port:

- Returns `high` if any driver is `high`.
- Otherwise returns the first non-`undefined` state.
- Returns `undefined` if all drivers are `undefined`.

This models wired-OR bus behaviour.
