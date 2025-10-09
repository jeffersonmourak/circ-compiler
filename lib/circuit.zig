const std = @import("std");
const memory = @import("memory.zig");
const transport = @import("transport.zig");

const log = @import("log.zig");

const PROPAGATION_DELAY: Timestamp = 5;
const WIRE_PROPAGATION_DELAY: Timestamp = 1;

fn recalculateAndReschedule(
    component: *Component,
    queue: *EventQueue,
    current_time: Timestamp,
) !void {
    var calculated_state: State = .undefined;

    switch (component.kind) {
        .not_gate => |gate| {
            if (gate.inputs[0]) |input_comp| {
                calculated_state = input_comp.output_state.flip();
            }
        },
        .and_gate => |gate| {
            var result: State = .high;
            for (gate.inputs) |maybe_input_component| {
                if (maybe_input_component) |input_comp| {
                    if (input_comp.output_state == .low) {
                        result = .low;
                        break;
                    }
                    if (input_comp.output_state == .undefined) {
                        result = .undefined;
                    }
                } else {
                    result = .undefined;
                    break;
                }
            }
            calculated_state = result;
        },
        .led => |*led_internals| {
            if (led_internals.inputs[0]) |input_comp| {
                const current_led_state = component.output_state;
                if (current_led_state != input_comp.output_state) {
                    component.output_state = input_comp.output_state;
                    log.info("💡 LED (id={d}) state is now {s}", .{ component.id, @tagName(component.output_state) });
                }
            }
            return;
        },
        .wire => |*wire| {
            // Wire relays the first non-null input to the output
            // If multiple inputs are connected, the wire takes the first defined state
            for (wire.inputs.items) |maybe_input_component| {
                if (maybe_input_component) |input_comp| {
                    if (input_comp.output_state != .undefined) {
                        calculated_state = input_comp.output_state;
                        break;
                    }
                }
            }
        },
        .input_pin_gate => return,
    }

    if (component.output_state != calculated_state) {
        log.info(" - Component (id={d}, type={s}) output changed from {s} -> {s}. Scheduling new event.", .{ component.id, @tagName(component.kind), @tagName(component.output_state), @tagName(calculated_state) });

        const delay = switch (component.kind) {
            .wire => WIRE_PROPAGATION_DELAY,
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

pub const ComponentType = enum { input_pin_gate, not_gate, led, and_gate, wire };

pub fn toKind(kind: u8) !Component.Kind {
    return switch (kind) {
        0 => .input_pin_gate,
        1 => .not_gate,
        2 => .led,
        3 => .and_gate,
        4 => .wire,
        else => return error.InvalidComponentKind,
    };
}

pub const Component = struct {
    id: u32,
    kind: Kind,
    output_state: State = .undefined,
    outputs: std.ArrayList(std.ArrayList(*Component)),

    const Kind = union(ComponentType) {
        input_pin_gate: struct { state: State = .undefined },
        not_gate: struct { inputs: [1]?*Component = .{null} },
        led: struct { inputs: [1]?*Component = .{null}, state: State = .undefined },
        and_gate: struct { inputs: [2]?*Component = .{ null, null } },
        wire: struct { inputs: std.ArrayList(?*Component) },
    };

    pub fn init(id: u32, kind: Kind) !*Component {
        const self = try memory.allocator.create(Component);

        var outputs = try std.ArrayList(std.ArrayList(*Component)).initCapacity(memory.allocator, 1);

        switch (kind) {
            .input_pin_gate, .not_gate, .and_gate, .wire => {
                try outputs.append(memory.allocator, try std.ArrayList(*Component).initCapacity(memory.allocator, 0));
            },
            .led => {},
        }

        self.* = .{ .id = id, .output_state = .undefined, .kind = kind, .outputs = outputs };

        switch (self.kind) {
            .and_gate => |*gate| gate.inputs = .{ null, null },
            .wire => |*wire| {
                wire.inputs = .{};
            },
            else => {},
        }

        return self;
    }

    pub fn deinit(self: *Component) void {
        for (self.outputs.items) |*pin_connections| {
            pin_connections.deinit(memory.allocator);
        }

        self.outputs.deinit(memory.allocator);

        switch (self.kind) {
            .wire => |*wire| {
                wire.inputs.deinit(memory.allocator);
            },
            else => {},
        }

        memory.allocator.destroy(self);
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
        .input_pin_gate => 0,
    };
    if (pin >= inputs_len) return error.InvalidInputPin;
}

pub fn assertValidOutputPin(component: *Component, pin: u32) !void {
    if (pin >= component.outputs.items.len) {
        return error.InvalidOutputPin;
    }
}

pub const Circuit = struct {
    nodes: std.ArrayList(*Component),
    event_queue: EventQueue,
    next_id: u32 = 0,
    current_time: Timestamp = 0,
    listener: *const fn (component: *Component, new_state: State) void = undefined,

    pub fn init() !Circuit {
        return .{
            .nodes = try std.ArrayList(*Component).initCapacity(memory.allocator, 0),
            .event_queue = EventQueue.init(),
            .listener = undefined,
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
        self.listener(component, new_state);
    }

    pub fn createComponent(self: *Circuit, kind: Component.Kind) !*Component {
        const new_component = try Component.init(self.next_id, kind);
        self.next_id += 1;
        try self.nodes.append(memory.allocator, new_component);
        return new_component;
    }

    pub fn connect(self: *Circuit, from: *Component, from_pin: u32, to: *Component, to_pin: u32) !void {
        _ = self;

        try assertValidOutputPin(from, from_pin);
        try from.outputs.items[from_pin].append(memory.allocator, to);

        switch (to.kind) {
            .not_gate => |*gate| {
                try assertValidInputPin(to, to_pin);
                gate.inputs[to_pin] = from;
            },
            .led => |*led| {
                try assertValidInputPin(to, to_pin);
                led.inputs[to_pin] = from;
            },
            .and_gate => |*gate| {
                try assertValidInputPin(to, to_pin);
                gate.inputs[to_pin] = from;
            },
            .wire => |*wire| {
                while (wire.inputs.items.len <= to_pin) {
                    try wire.inputs.append(memory.allocator, null);
                }
                wire.inputs.items[to_pin] = from;
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

            for (component.outputs.items) |output_list| {
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
