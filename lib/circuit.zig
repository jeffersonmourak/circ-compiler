const std = @import("std");
const memory = @import("memory.zig");
const transport = @import("transport.zig");

const log = @import("log.zig");

const PROPAGATION_DELAY: Timestamp = 5;
const WIRE_PROPAGATION_DELAY: Timestamp = 1;

const IN_PORT_NAME = "in";
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
            if (gate.inputs.get(IN_PORT_NAME)) |input_comp_list| {
                calculated_state = calculateDominantState(input_comp_list).flip();
            }
        },
        .and_gate => |gate| {
            const aPortComponents = gate.inputs.get("a") orelse return error.InvalidInputPort;

            const bPortComponents = gate.inputs.get("b") orelse return error.InvalidInputPort;

            const aValue = calculateDominantState(aPortComponents);
            const bValue = calculateDominantState(bPortComponents);

            if (aValue == .low or bValue == .low) {
                calculated_state = .low;
            } else {
                calculated_state = .high;
            }
        },
        .led => |*led_internals| {
            const inputPortComponents = led_internals.inputs.get(IN_PORT_NAME) orelse return error.InvalidInputPort;

            const inputState = calculateDominantState(inputPortComponents);

            const currentLedState = component.output_state;
            if (currentLedState != inputState) {
                component.output_state = inputState;
                log.info("💡 LED (id={d}) state is now {s}", .{ component.id, @tagName(component.output_state) });
            }
            return;
        },
        .wire => |*wire| {
            // Wire relays the first non-null input to the output
            // If multiple inputs are connected, the wire takes the first defined state

            const inputs = wire.inputs.get(IN_PORT_NAME) orelse return error.InvalidInputPort;

            for (inputs.items) |input_comp| {
                if (input_comp.output_state != .undefined) {
                    calculated_state = calculateDominantState(inputs);
                    break;
                }
            }
        },
        .output_pin => |*output_pin| {
            const inputs = output_pin.inputs.get(OUTPUT_PIN_IN_PORT_NAME) orelse return;
            calculated_state = calculateDominantState(inputs);
        },
        .input_pin_gate => return,
    }

    if (component.output_state != calculated_state) {
        log.info(" - Component (id={d}, type={s}) output changed from {s} -> {s}. Scheduling new event.", .{ component.id, @tagName(component.kind), @tagName(component.output_state), @tagName(calculated_state) });

        const delay = switch (component.kind) {
            .wire, .output_pin => WIRE_PROPAGATION_DELAY,
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
            else => undefined,
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
    const PortMap = std.StringHashMap(std.ArrayList(*Component));

    id: u32,
    kind: Kind,
    output_state: State = .undefined,
    outputs: PortMap,

    const Kind = union(ComponentType) {
        input_pin_gate: struct { state: State = .undefined },
        not_gate: struct { inputs: PortMap = PortMap.init(memory.allocator) },
        led: struct { inputs: PortMap = PortMap.init(memory.allocator), state: State = .undefined },
        and_gate: struct { inputs: PortMap = PortMap.init(memory.allocator) },
        wire: struct { inputs: PortMap = PortMap.init(memory.allocator) },
        output_pin: struct { inputs: PortMap = PortMap.init(memory.allocator) },
    };

    pub fn init(id: u32, kind: Kind) !*Component {
        const self = try memory.allocator.create(Component);

        var outputsMap: PortMap = PortMap.init(memory.allocator);

        switch (kind) {
            .input_pin_gate, .not_gate, .and_gate, .wire, .output_pin => {
                const output_port = switch (kind) {
                    .output_pin => OUTPUT_PIN_OUT_PORT_NAME,
                    else => OUT_PORT_NAME,
                };
                const result = try outputsMap.getOrPut(output_port);

                if (!result.found_existing) {
                    result.value_ptr.* = try std.ArrayList(*Component).initCapacity(memory.allocator, 0);
                }
            },
            .led => {},
        }

        self.* = .{ .id = id, .output_state = .undefined, .kind = kind, .outputs = outputsMap };

        switch (self.kind) {
            .and_gate => |*gate| {
                gate.inputs = std.StringHashMap(std.ArrayList(*Component)).init(memory.allocator);
            },
            .wire => |*wire| {
                wire.inputs = std.StringHashMap(std.ArrayList(*Component)).init(memory.allocator);
            },
            .not_gate => |*gate| {
                gate.inputs = std.StringHashMap(std.ArrayList(*Component)).init(memory.allocator);
            },
            .led => |*led| {
                led.inputs = PortMap.init(memory.allocator);
            },
            .output_pin => |*output_pin| {
                output_pin.inputs = PortMap.init(memory.allocator);
            },
            else => {},
        }

        return self;
    }

    pub fn deinit(self: *Component) void {
        var outputsIterator = self.outputs.valueIterator();
        while (outputsIterator.next()) |list| {
            list.deinit(memory.allocator);
        }
        self.outputs.deinit();

        switch (self.kind) {
            .wire => |*wire| {
                var wireInputsIterator = wire.inputs.valueIterator();
                while (wireInputsIterator.next()) |list| {
                    list.deinit(memory.allocator);
                }
                wire.inputs.deinit();
            },
            .not_gate => |*gate| {
                var notGateInputsIterator = gate.inputs.valueIterator();
                while (notGateInputsIterator.next()) |list| {
                    list.deinit(memory.allocator);
                }
                gate.inputs.deinit();
            },
            .and_gate => |*gate| {
                var andGateInputsIterator = gate.inputs.valueIterator();
                while (andGateInputsIterator.next()) |list| {
                    list.deinit(memory.allocator);
                }
                gate.inputs.deinit();
            },
            .led => |*led| {
                var ledInputsIterator = led.inputs.valueIterator();
                while (ledInputsIterator.next()) |list| {
                    list.deinit(memory.allocator);
                }
                led.inputs.deinit();
            },
            .output_pin => |*output_pin| {
                var outputPinInputsIterator = output_pin.inputs.valueIterator();
                while (outputPinInputsIterator.next()) |list| {
                    list.deinit(memory.allocator);
                }
                output_pin.inputs.deinit();
            },
            .input_pin_gate => {},
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
};

pub fn assertValidInputPin(component: *Component, pin: u32) !void {
    const inputs_len = switch (component.kind) {
        .not_gate => |gate| gate.inputs.len,
        .and_gate => |gate| gate.inputs.len,
        .led => |led| led.inputs.len,
        .wire => |wire| wire.inputs.items.len,
        .output_pin => |output_pin| output_pin.inputs.len,
        .input_pin_gate => 0,
    };
    if (pin >= inputs_len) return error.InvalidInputPin;
}

pub fn assertValidOutputPin(component: *Component, portName: []const u8) !void {
    _ = component.outputs.get(portName) orelse return error.InvalidOutputPort;
}

pub const Circuit = struct {
    nodes: std.ArrayList(*Component),
    event_queue: EventQueue,
    next_id: u32 = 0,
    current_time: Timestamp = 0,
    listener: ?*const fn (component: *Component, new_state: State) void = null,

    pub fn init() !Circuit {
        return .{
            .nodes = try std.ArrayList(*Component).initCapacity(memory.allocator, 0),
            .event_queue = EventQueue.init(),
            .listener = null,
        };
    }

    pub fn deinit(self: *Circuit) void {
        for (self.nodes.items) |node| {
            node.deinit();
        }
        self.nodes.deinit(memory.allocator);
        self.event_queue.deinit();
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

        const fromComponent, const fromPort = from;
        const toComponent, const toPort = to;

        try assertValidOutputPin(fromComponent, fromPort);

        const fromPortResult = try fromComponent.outputs.getOrPut(fromPort);
        if (!fromPortResult.found_existing) {
            return error.InvalidOutputPort;
        }

        try fromPortResult.value_ptr.*.append(memory.allocator, toComponent);

        switch (toComponent.kind) {
            .not_gate => |*gate| {
                const toPortResult = try gate.inputs.getOrPut(toPort);
                if (!toPortResult.found_existing) {
                    toPortResult.value_ptr.* = try std.ArrayList(*Component).initCapacity(memory.allocator, 0);
                }
                try toPortResult.value_ptr.*.append(memory.allocator, fromComponent);
            },
            .led => |*led| {
                const toPortResult = try led.inputs.getOrPut(toPort);
                if (!toPortResult.found_existing) {
                    toPortResult.value_ptr.* = try std.ArrayList(*Component).initCapacity(memory.allocator, 0);
                }
                try toPortResult.value_ptr.*.append(memory.allocator, fromComponent);
            },
            .and_gate => |*gate| {
                const toPortResult = try gate.inputs.getOrPut(toPort);
                if (!toPortResult.found_existing) {
                    toPortResult.value_ptr.* = try std.ArrayList(*Component).initCapacity(memory.allocator, 0);
                }
                try toPortResult.value_ptr.*.append(memory.allocator, fromComponent);
            },
            .wire => |*wire| {
                const toPortResult = try wire.inputs.getOrPut(toPort);
                if (!toPortResult.found_existing) {
                    toPortResult.value_ptr.* = try std.ArrayList(*Component).initCapacity(memory.allocator, 0);
                }
                try toPortResult.value_ptr.*.append(memory.allocator, fromComponent);
            },
            .output_pin => |*output_pin| {
                const toPortResult = try output_pin.inputs.getOrPut(toPort);
                if (!toPortResult.found_existing) {
                    toPortResult.value_ptr.* = try std.ArrayList(*Component).initCapacity(memory.allocator, 0);
                }
                try toPortResult.value_ptr.*.append(memory.allocator, fromComponent);
            },
            .input_pin_gate => return error.InvalidConnection,
        }
    }

    pub fn propagate(self: *Circuit) !void {
        while (self.event_queue.pop()) |event| {
            self.current_time = event.timestamp;
            const component = event.component;

            if (component.output_state == event.new_state) continue;

            log.info("[Time: {d}] Updating component id={d} to {s}", .{ self.current_time, component.id, @tagName(event.new_state) });
            component.output_state = event.new_state;

            var outputsIterator = component.outputs.valueIterator();
            while (outputsIterator.next()) |output_list| {
                for (output_list.items) |output| {
                    log.info("  -> Notifying downstream component id={d}", .{output.id});
                    try recalculateAndReschedule(output, &self.event_queue, self.current_time);

                    self.notifyStateChange(output, output.output_state);
                }
            }
        }
    }

    pub fn propagateEvent(self: *Circuit, component: *Component, new_state: State) !void {
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
}
