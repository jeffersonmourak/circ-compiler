const std = @import("std");
const transport = @import("transport.zig");
const memory = @import("memory.zig");
const log = @import("log.zig");

const Circuit = @import("circuit.zig").Circuit;
const State = @import("circuit.zig").State;
const Component = @import("circuit.zig").Component;
const toKind = @import("circuit.zig").toKind;

export var circuit: *Circuit = undefined;

var components_hash_map: std.AutoHashMap(i32, *Component) = undefined;
var next_component_id: i32 = 1;

export var state_snapshot: *[]u8 = undefined;
export var state_snapshot_len: usize = 0;

extern fn onStateChange() void;

fn notifyStateChange(_: *Component, _: State) void {
    onStateChange();
}

export fn init() void {
    components_hash_map = std.AutoHashMap(i32, *Component).init(memory.allocator);

    circuit = memory.allocator.create(Circuit) catch {
        return;
    };

    state_snapshot = memory.allocator.create([]u8) catch {
        return;
    };
    state_snapshot.* = undefined;

    circuit.* = Circuit.init() catch {
        memory.allocator.destroy(circuit);
        return;
    };

    circuit.listener = notifyStateChange;
}

export fn deinit() void {
    circuit.deinit();
    components_hash_map.deinit();
    memory.allocator.destroy(state_snapshot);
    memory.deinit();
}

export fn createComponent(kind_int: u8) i32 {
    var component: *Component = memory.allocator.create(Component) catch {
        return -1;
    };

    switch (kind_int) {
        0 => {
            component = circuit.createComponent(.{ .input_pin_gate = .{} }) catch {
                memory.allocator.destroy(component);
                return -1;
            };
        },
        1 => {
            component = circuit.createComponent(.{ .not_gate = .{} }) catch {
                memory.allocator.destroy(component);
                return -1;
            };
        },
        2 => {
            component = circuit.createComponent(.{ .led = .{} }) catch {
                memory.allocator.destroy(component);
                return -1;
            };
        },
        3 => {
            component = circuit.createComponent(.{ .and_gate = .{ .inputs = .{ null, null } } }) catch {
                memory.allocator.destroy(component);
                return -1;
            };
        },
        4 => {
            component = circuit.createComponent(.{ .wire = .{ .inputs = .{} } }) catch {
                memory.allocator.destroy(component);
                return -1;
            };
        },
        else => {
            memory.allocator.destroy(component);
            return -1;
        },
    }

    components_hash_map.put(next_component_id, component) catch {
        memory.allocator.destroy(component);
        return -1;
    };

    next_component_id += 1;
    return next_component_id - 1;
}

export fn connect(component1_id: i32, pin1: u32, component2_id: i32, pin2: u32) void {
    const component1 = components_hash_map.get(component1_id);
    const component2 = components_hash_map.get(component2_id);

    if (component1 == null or component2 == null) return;

    circuit.connect(component1.?, pin1, component2.?, pin2) catch {
        return;
    };
}

export fn propagateEvent(component_id: i32, state_int: i32) void {
    const state = State.fromInt(state_int);

    const component = components_hash_map.get(component_id);
    if (component == null) return;

    circuit.propagateEvent(component.?, state) catch {
        return;
    };
}

export fn propagate() void {
    circuit.propagate() catch {
        return;
    };
}

export fn getComponentState(component_id: i32) i32 {
    const component = components_hash_map.get(component_id);
    if (component == null) return 0;

    const state = component.?.output_state;
    return State.toInt(state);
}

export fn freeLogMessage(ptr: *const u8, len: usize) void {
    log.clearLogPointer(ptr, len);
}
