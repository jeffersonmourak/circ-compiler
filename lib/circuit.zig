const std = @import("std");
pub const memory = @import("memory.zig");
const transport = @import("transport.zig");

const log = @import("log.zig");

/// Compile-time switch to include benchmark counters on `Circuit`. The
/// `build_options` module is supplied by `build.zig` per consumer: native and
/// WASM builds wire it to `false`; the `zig build bench` runner wires it to
/// `true`. When false, `Circuit.metrics` is `void` and every counter bump is
/// dead code stripped — production and test builds are byte-identical to a
/// metrics-free engine.
pub const COLLECT_METRICS: bool = @import("build_options").collect_metrics;

pub const Metrics = struct {
    events_popped: u64 = 0,
    events_committed: u64 = 0,
    recalcs: u64 = 0,
    peak_queue: u64 = 0,
    final_time: u64 = 0,
};

const PROPAGATION_DELAY: Timestamp = 5;
const WIRE_PROPAGATION_DELAY: Timestamp = 1;

const IN_PORT_NAME = "in";
const A_PORT_NAME = "a";
const B_PORT_NAME = "b";
const OUT_PORT_NAME = "out";
const OUTPUT_PIN_IN_PORT_NAME = "in";
const OUTPUT_PIN_OUT_PORT_NAME = "out";

fn calculateDominantState(input_comp_list: std.ArrayList(*Component)) State {
    var dominant_state: State = .undefined;
    for (input_comp_list.items) |input_comp| {
        if (input_comp.output_state == .high) {
            return .high;
        }

        dominant_state = input_comp.output_state;
    }
    return dominant_state;
}

fn recalculateAndReschedule(
    component: *Component,
    queue: *EventQueue,
    current_time: Timestamp,
) !void {
    var calculated_state: State = .undefined;

    switch (component.kind) {
        .not_gate => |gate| {
            calculated_state = calculateDominantState(gate.inputs).flip();
        },
        .and_gate => |gate| {
            const aValue = calculateDominantState(gate.inputs_a);
            const bValue = calculateDominantState(gate.inputs_b);

            if (aValue == .low or bValue == .low) {
                calculated_state = .low;
            } else if (aValue == .undefined or bValue == .undefined) {
                calculated_state = .undefined;
            } else {
                calculated_state = .high;
            }
        },
        .led => |led_internals| {
            calculated_state = calculateDominantState(led_internals.inputs);
            if (calculated_state != component.output_state) {
                if (comptime log.enabled(.info)) {
                    log.info("💡 LED (id={d}) state will be {s}", .{ component.id, @tagName(calculated_state) });
                }
            }
        },
        .wire => |wire| {
            // Wire relays the first non-null input to the output
            // If multiple inputs are connected, the wire takes the first defined state
            for (wire.inputs.items) |input_comp| {
                if (input_comp.output_state != .undefined) {
                    calculated_state = calculateDominantState(wire.inputs);
                    break;
                }
            }
        },
        .output_pin => |output_pin| {
            calculated_state = calculateDominantState(output_pin.inputs);
        },
        .input_pin_gate => |gate| {
            if (gate.inputs.items.len == 0) return;
            calculated_state = calculateDominantState(gate.inputs);
        },
    }

    if (component.output_state != calculated_state) {
        if (comptime log.enabled(.info)) {
            log.info(" - Component (id={d}, type={s}) output changed from {s} -> {s}. Scheduling new event.", .{ component.id, @tagName(component.kind), @tagName(component.output_state), @tagName(calculated_state) });
        }

        const delay = switch (component.kind) {
            .wire, .output_pin, .led => WIRE_PROPAGATION_DELAY,
            else => PROPAGATION_DELAY,
        };

        try queue.add(.{
            .timestamp = current_time + delay,
            .component = component,
            .new_state = calculated_state,
        });
    }
}

pub const State = enum {
    undefined,
    low,
    high,

    pub fn flip(self: State) State {
        return switch (self) {
            .low => .high,
            .high => .low,
            .undefined => .undefined,
        };
    }

    pub fn fromInt(int: i32) State {
        if (int == 0) return .low;
        if (int == 1) return .high;
        return .undefined;
    }

    pub fn toInt(self: State) i32 {
        return switch (self) {
            .low => 0,
            .high => 1,
            else => 2,
        };
    }
};

pub const Timestamp = u64;

pub const Event = struct {
    timestamp: Timestamp,
    component: *Component,
    new_state: State,

    pub fn lessThan(_: void, lhs: Event, rhs: Event) std.math.Order {
        return std.math.order(lhs.timestamp, rhs.timestamp);
    }
};

pub const ComponentType = enum { input_pin_gate, not_gate, led, and_gate, wire, output_pin };

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

pub const ComponentPortReference = struct { *Component, []const u8 };

pub const Component = struct {
    id: u32,
    kind: Kind,
    output_state: State = .undefined,
    /// Flat list of downstream components. Every component kind has exactly
    /// one output port (`"out"`), so the per-port map collapses to a single
    /// slice. Phase 2 of propagate walks this list directly.
    outputs: std.ArrayList(*Component) = .{},

    const Kind = union(ComponentType) {
        input_pin_gate: struct { inputs: std.ArrayList(*Component) = .{} },
        not_gate: struct { inputs: std.ArrayList(*Component) = .{} },
        led: struct { inputs: std.ArrayList(*Component) = .{} },
        /// AND is the only kind with two distinct input ports; everything
        /// else uses a single `inputs` field.
        and_gate: struct {
            inputs_a: std.ArrayList(*Component) = .{},
            inputs_b: std.ArrayList(*Component) = .{},
        },
        wire: struct { inputs: std.ArrayList(*Component) = .{} },
        output_pin: struct { inputs: std.ArrayList(*Component) = .{} },
    };

    pub fn init(id: u32, kind: Kind) !*Component {
        const self = try memory.allocator.create(Component);
        self.* = .{ .id = id, .output_state = .undefined, .kind = kind, .outputs = .{} };
        return self;
    }

    pub fn deinit(self: *Component) void {
        self.outputs.deinit(memory.allocator);
        switch (self.kind) {
            .and_gate => |*g| {
                g.inputs_a.deinit(memory.allocator);
                g.inputs_b.deinit(memory.allocator);
            },
            .not_gate => |*g| g.inputs.deinit(memory.allocator),
            .led => |*g| g.inputs.deinit(memory.allocator),
            .wire => |*g| g.inputs.deinit(memory.allocator),
            .output_pin => |*g| g.inputs.deinit(memory.allocator),
            .input_pin_gate => |*g| g.inputs.deinit(memory.allocator),
        }
        memory.allocator.destroy(self);
    }

    pub fn port(self: *Component, portName: []const u8) ComponentPortReference {
        return .{ self, portName };
    }
};

const EventQueue = struct {
    heap: std.PriorityQueue(Event, void, Event.lessThan),

    pub fn init() EventQueue {
        return .{ .heap = std.PriorityQueue(Event, void, Event.lessThan).init(memory.allocator, {}) };
    }

    pub fn deinit(self: *EventQueue) void {
        self.heap.deinit();
    }

    pub fn add(self: *EventQueue, event: Event) !void {
        try self.heap.add(event);
    }

    pub fn pop(self: *EventQueue) ?Event {
        return self.heap.removeOrNull();
    }

    pub fn peek(self: *EventQueue) ?Event {
        return self.heap.peek();
    }
};

pub const Circuit = struct {
    nodes: std.ArrayList(*Component),
    event_queue: EventQueue,
    next_id: u32 = 0,
    current_time: Timestamp = 0,
    listener: ?*const fn (component: *Component, new_state: State) void = null,
    /// Scratch buffer reused across `propagate()` calls. Hoisted onto the
    /// circuit so the first append in each propagation doesn't reallocate
    /// from zero capacity; instead the previous run's capacity is retained
    /// (length reset to 0 at the end of each per-timestamp iteration).
    changed_at_step: std.ArrayList(*Component) = .{},
    /// Benchmark counters. Present only when `COLLECT_METRICS` is true so
    /// shipping builds carry zero bytes and zero instructions for the
    /// metrics path. The conditional type is `void` (zero-sized) otherwise,
    /// so `circuit.metrics.foo` outside an `if (COLLECT_METRICS)` block is
    /// a compile error — the compiler enforces the gating for us.
    metrics: if (COLLECT_METRICS) Metrics else void = if (COLLECT_METRICS) Metrics{} else {},

    pub fn init() !Circuit {
        return .{
            .nodes = .{},
            .event_queue = EventQueue.init(),
            .listener = null,
            .changed_at_step = .{},
            .metrics = if (COLLECT_METRICS) Metrics{} else {},
        };
    }

    pub fn deinit(self: *Circuit) void {
        for (self.nodes.items) |node| {
            node.deinit();
        }
        self.nodes.deinit(memory.allocator);
        self.event_queue.deinit();
        self.changed_at_step.deinit(memory.allocator);
    }

    pub fn notifyStateChange(self: *Circuit, component: *Component, new_state: State) void {
        if (self.listener) |listener| {
            listener(component, new_state);
        }
    }

    pub fn createComponent(self: *Circuit, kind: Component.Kind) !*Component {
        const new_component = try Component.init(self.next_id, kind);
        self.next_id += 1;
        try self.nodes.append(memory.allocator, new_component);
        return new_component;
    }

    pub fn connect(self: *Circuit, from: ComponentPortReference, to: ComponentPortReference) !void {
        _ = self;

        const fromComponent, _ = from;
        const toComponent, const toPort = to;

        try fromComponent.outputs.append(memory.allocator, toComponent);

        switch (toComponent.kind) {
            .and_gate => |*g| {
                if (std.mem.eql(u8, toPort, A_PORT_NAME)) {
                    try g.inputs_a.append(memory.allocator, fromComponent);
                } else if (std.mem.eql(u8, toPort, B_PORT_NAME)) {
                    try g.inputs_b.append(memory.allocator, fromComponent);
                } else return error.InvalidInputPort;
            },
            .not_gate => |*g| {
                if (!std.mem.eql(u8, toPort, IN_PORT_NAME)) return error.InvalidInputPort;
                try g.inputs.append(memory.allocator, fromComponent);
            },
            .led => |*g| {
                if (!std.mem.eql(u8, toPort, IN_PORT_NAME)) return error.InvalidInputPort;
                try g.inputs.append(memory.allocator, fromComponent);
            },
            .wire => |*g| {
                if (!std.mem.eql(u8, toPort, IN_PORT_NAME)) return error.InvalidInputPort;
                try g.inputs.append(memory.allocator, fromComponent);
            },
            .output_pin => |*g| {
                if (!std.mem.eql(u8, toPort, IN_PORT_NAME)) return error.InvalidInputPort;
                try g.inputs.append(memory.allocator, fromComponent);
            },
            .input_pin_gate => |*g| {
                if (!std.mem.eql(u8, toPort, IN_PORT_NAME)) return error.InvalidInputPort;
                try g.inputs.append(memory.allocator, fromComponent);
            },
        }
    }

    pub fn propagate(self: *Circuit) !void {
        // Two-phase processing per timestamp: first commit ALL state changes
        // at time T, then walk every changed component's outputs to schedule
        // downstream events. Without this batching, a downstream gate's
        // recalculateAndReschedule could read partially-updated upstream
        // state when multiple upstream events fire at the same timestamp,
        // computing an intermediate value that then gets dedup'd by the
        // "if state == new_state, continue" check, leaving the gate stuck
        // at the wrong final value. Manifests in deep-fanout circuits where
        // a single control bit drives many parallel gates whose outputs
        // converge into a serial carry chain (e.g. 4-bit ALU with shared
        // nx/ny normalization).

        while (self.event_queue.peek()) |first| {
            const step_time = first.timestamp;
            self.current_time = step_time;

            // Phase 1: drain all events at this timestamp, applying state
            // changes immediately. Components whose state actually flipped
            // get queued for downstream notification.
            while (self.event_queue.peek()) |next_event| {
                if (next_event.timestamp != step_time) break;
                const event = self.event_queue.pop().?;
                if (COLLECT_METRICS) self.metrics.events_popped += 1;
                const component = event.component;

                if (component.output_state == event.new_state) continue;
                if (COLLECT_METRICS) self.metrics.events_committed += 1;

                if (comptime log.enabled(.info)) {
                    log.info("[Time: {d}] Updating component id={d} to {s}", .{ self.current_time, component.id, @tagName(event.new_state) });
                }
                component.output_state = event.new_state;
                try self.changed_at_step.append(memory.allocator, component);
            }

            // Phase 2: with all state at this timestamp committed, walk
            // outputs of every changed component. Now downstream recalcs
            // see consistent upstream state.
            for (self.changed_at_step.items) |component| {
                for (component.outputs.items) |output| {
                    if (comptime log.enabled(.info)) {
                        log.info("  -> Notifying downstream component id={d}", .{output.id});
                    }
                    if (COLLECT_METRICS) self.metrics.recalcs += 1;
                    try recalculateAndReschedule(output, &self.event_queue, self.current_time);

                    self.notifyStateChange(output, output.output_state);
                }
            }
            self.changed_at_step.clearRetainingCapacity();

            // Sample queue depth after Phase 2. This IS the iteration's true
            // peak: Phase 1 only pops (queue monotonically shrinks), Phase 2
            // only adds (queue monotonically grows), so end-of-Phase-2 is
            // always the per-iteration maximum. Also equals the next
            // iteration's start-of-iteration depth (nothing happens between
            // iterations), so a second sample there would be redundant.
            if (COLLECT_METRICS) {
                const depth: u64 = @intCast(self.event_queue.heap.items.len);
                if (depth > self.metrics.peak_queue) self.metrics.peak_queue = depth;
            }
        }

        if (COLLECT_METRICS) self.metrics.final_time = self.current_time;
    }

    pub fn propagateEvent(self: *Circuit, component: *Component, new_state: State) !void {
        // Short-circuit no-op events: when the caller drives a component to
        // its current state, the event would just be popped and skipped at
        // Phase 1 (the `component.output_state == event.new_state` check
        // inside propagate), wasting a queue insertion plus a pop. Skip the
        // enqueue, but still advance `current_time` by the propagation delay
        // so the timing model — and the `final_time` counter — match what
        // the original behavior would have produced.
        //
        // Dominates the pop-inefficiency picture on the truth-table corpus:
        // the bench's driver unconditionally writes every input pin on every
        // vector, so for fixtures like and_6bit ~71% of pops used to be
        // no-ops where the requested state already matched. With this short-
        // circuit, the only events that enter the queue from the outside
        // are the ones that genuinely change state; pop efficiency lifts
        // toward 100% across the corpus.
        if (component.output_state == new_state) {
            self.current_time += PROPAGATION_DELAY;
            if (COLLECT_METRICS) self.metrics.final_time = self.current_time;
            return;
        }

        try self.event_queue.add(.{
            .timestamp = self.current_time + PROPAGATION_DELAY,
            .component = component,
            .new_state = new_state,
        });

        try self.propagate();
    }

    pub fn printState(self: *Circuit) void {
        for (self.nodes.items) |node| {
            log.info("Component id={d} type={s} state={s}", .{ node.id, @tagName(node.kind), @tagName(node.output_state) });
        }
    }

    pub fn encodeState(self: *Circuit) ![]u8 {
        var buffer = try std.ArrayList(u8).initCapacity(memory.allocator, 0);
        defer buffer.deinit(memory.allocator);

        const len_u32: u8 = @intCast(self.nodes.items.len);
        try buffer.appendSlice(memory.allocator, std.mem.asBytes(&len_u32));

        for (self.nodes.items) |node| {
            const encoded_state = try transport.encodeState(node).encode(memory.allocator);
            defer memory.allocator.free(encoded_state);

            try buffer.appendSlice(memory.allocator, encoded_state);
        }

        return buffer.toOwnedSlice(memory.allocator);
    }
};

test "output_pin kind exists and constructs" {
    comptime {
        const kind: Component.Kind = .{ .output_pin = .{} };
        _ = kind;
    }
}

test "output_pin: passes input through" {
    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} });
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, .low);

        try std.testing.expectEqual(State.low, output_pin.output_state);
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY + WIRE_PROPAGATION_DELAY), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} });
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, .high);

        try std.testing.expectEqual(State.high, output_pin.output_state);
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY + WIRE_PROPAGATION_DELAY), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} });
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, .undefined);

        try std.testing.expectEqual(State.undefined, output_pin.output_state);
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const output_pin = try circuit.createComponent(.{ .output_pin = .{} });
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, .low);
        try std.testing.expectEqual(State.low, output_pin.output_state);

        try circuit.propagateEvent(input, .high);

        try std.testing.expectEqual(State.high, output_pin.output_state);
        try std.testing.expectEqual(@as(Timestamp, (PROPAGATION_DELAY + WIRE_PROPAGATION_DELAY) * 2), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const output_pin_1 = try circuit.createComponent(.{ .output_pin = .{} });
        const output_pin_2 = try circuit.createComponent(.{ .output_pin = .{} });
        try circuit.connect(input.port(OUT_PORT_NAME), output_pin_1.port(OUTPUT_PIN_IN_PORT_NAME));
        try circuit.connect(output_pin_1.port(OUTPUT_PIN_OUT_PORT_NAME), output_pin_2.port(OUTPUT_PIN_IN_PORT_NAME));

        try circuit.propagateEvent(input, .high);

        try std.testing.expectEqual(State.high, output_pin_1.output_state);
        try std.testing.expectEqual(State.high, output_pin_2.output_state);
        try std.testing.expectEqual(@as(Timestamp, PROPAGATION_DELAY + (WIRE_PROPAGATION_DELAY * 2)), circuit.current_time);
    }

    {
        var circuit = try Circuit.init();
        defer circuit.deinit();

        const upstream = try circuit.createComponent(.{ .input_pin_gate = .{} });
        const downstream = try circuit.createComponent(.{ .input_pin_gate = .{} });
        try circuit.connect(upstream.port(OUT_PORT_NAME), downstream.port(IN_PORT_NAME));

        try circuit.propagateEvent(upstream, .low);
        try std.testing.expectEqual(State.low, downstream.output_state);

        try circuit.propagateEvent(upstream, .high);
        try std.testing.expectEqual(State.high, downstream.output_state);
    }
}

test "led: registers out port and drives downstream output_pin" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input = try circuit.createComponent(.{ .input_pin_gate = .{} });
    const led = try circuit.createComponent(.{ .led = .{} });
    const output_pin = try circuit.createComponent(.{ .output_pin = .{} });
    try circuit.connect(input.port(OUT_PORT_NAME), led.port(IN_PORT_NAME));
    try circuit.connect(led.port(OUT_PORT_NAME), output_pin.port(OUTPUT_PIN_IN_PORT_NAME));

    try circuit.propagateEvent(input, .low);
    try std.testing.expectEqual(State.low, led.output_state);

    try circuit.propagateEvent(input, .high);
    try std.testing.expectEqual(State.high, led.output_state);
}
