const std = @import("std");
const engine = @import("circuit");
const full_format = @import("full_format");

/// A pin on the root circuit, addressable by its source name. `component_id`
/// is the topology id of the underlying `input_pin`/`output_pin` primitive;
/// `nodeById` maps it to the live engine node.
pub const PinRef = struct {
    name: []const u8,
    component_id: u32,
    width: u8,
};

pub const SessionError = error{
    OutOfMemory,
    InvalidTopology,
};

/// A live `engine.Circuit` built from a `FullTopology`, with its root-level
/// input and output pins resolved by name. The truth-table builder enumerates
/// `inputs` exhaustively; `--sim` drives author-supplied vectors against the
/// same construction. Macro-expanded sub-pins (non-empty `origin`) are wired
/// through but are not independently addressable, matching the truth table.
///
/// The caller owns the `engine.Circuit` so it is never moved after its nodes
/// are created; `build` only populates it. `inputs`, `outputs`, and the id→node
/// map are allocated from the caller-supplied allocator.
pub const Session = struct {
    circuit: *engine.Circuit,
    inputs: []const PinRef,
    outputs: []const PinRef,
    id_to_node: std.AutoHashMap(u32, *engine.Component),

    pub fn build(
        alloc: std.mem.Allocator,
        circuit: *engine.Circuit,
        topology: full_format.FullTopology,
    ) SessionError!Session {
        var input_count: usize = 0;
        var output_count: usize = 0;
        for (topology.components) |comp| {
            if (comp.origin.len != 0) continue;
            switch (comp.kind) {
                .input_pin => input_count += 1,
                .output_pin => output_count += 1,
                else => {},
            }
        }

        const inputs = try alloc.alloc(PinRef, input_count);
        const outputs = try alloc.alloc(PinRef, output_count);
        var i_idx: usize = 0;
        var o_idx: usize = 0;
        for (topology.components) |comp| {
            if (comp.origin.len != 0) continue;
            switch (comp.kind) {
                .input_pin => {
                    inputs[i_idx] = .{ .name = comp.name, .component_id = comp.id, .width = comp.width };
                    i_idx += 1;
                },
                .output_pin => {
                    outputs[o_idx] = .{ .name = comp.name, .component_id = comp.id, .width = comp.width };
                    o_idx += 1;
                },
                else => {},
            }
        }

        var id_to_node = std.AutoHashMap(u32, *engine.Component).init(alloc);
        try id_to_node.ensureTotalCapacity(@intCast(topology.components.len));
        for (topology.components) |comp| {
            const node = switch (comp.kind) {
                .input_pin => circuit.createComponent(.{ .input_pin_gate = .{} }, comp.width),
                .not_gate => circuit.createComponent(.{ .not_gate = .{} }, comp.width),
                .and_gate => circuit.createComponent(.{ .and_gate = .{} }, comp.width),
                .wire => circuit.createComponent(.{ .wire = .{} }, comp.width),
                .led => circuit.createComponent(.{ .led = .{} }, comp.width),
                .output_pin => circuit.createComponent(.{ .output_pin = .{} }, comp.width),
                .slice => blk: {
                    const aux = switch (comp.aux) {
                        .slice => |s| s,
                        else => return error.InvalidTopology,
                    };
                    break :blk circuit.createComponent(
                        .{ .slice = .{ .lo = aux.lo, .hi = aux.hi } },
                        comp.width,
                    );
                },
                .concat => circuit.createComponent(.{ .concat = .{} }, comp.width),
            } catch return error.InvalidTopology;
            node.id = comp.id;
            id_to_node.putAssumeCapacity(comp.id, node);
        }

        for (topology.connections) |conn| {
            const from_node = id_to_node.get(conn.from_id) orelse return error.InvalidTopology;
            const to_node = id_to_node.get(conn.to_id) orelse return error.InvalidTopology;
            // Concat destinations interpret the port byte as an operand index,
            // not a `PortName`; format it back into the `operand_<N>` string the
            // engine's `connect()` expects.
            if (to_node.kind == .concat) {
                var port_buf: [16]u8 = undefined;
                const port_str = std.fmt.bufPrint(&port_buf, "operand_{d}", .{conn.port}) catch return error.InvalidTopology;
                circuit.connect(.{ from_node, "out" }, .{ to_node, port_str }) catch return error.InvalidTopology;
            } else {
                const port_str = portByteToName(conn.port) catch return error.InvalidTopology;
                circuit.connect(.{ from_node, "out" }, .{ to_node, port_str }) catch return error.InvalidTopology;
            }
        }

        return .{
            .circuit = circuit,
            .inputs = inputs,
            .outputs = outputs,
            .id_to_node = id_to_node,
        };
    }

    pub fn nodeById(self: *const Session, id: u32) ?*engine.Component {
        return self.id_to_node.get(id);
    }

    pub fn findInput(self: *const Session, name: []const u8) ?PinRef {
        for (self.inputs) |pin| {
            if (std.mem.eql(u8, pin.name, name)) return pin;
        }
        return null;
    }

    pub fn findOutput(self: *const Session, name: []const u8) ?PinRef {
        for (self.outputs) |pin| {
            if (std.mem.eql(u8, pin.name, name)) return pin;
        }
        return null;
    }
};

fn portByteToName(port: u8) ![]const u8 {
    const port_name = std.meta.intToEnum(full_format.PortName, port) catch return error.InvalidTopology;
    return switch (port_name) {
        .in => "in",
        .a => "a",
        .b => "b",
        .out => "out",
    };
}

// ---------- Tests ----------

const test_alloc = std.testing.allocator;
const FullComponentRecord = full_format.FullComponentRecord;
const FullConnectionRecord = full_format.FullConnectionRecord;

// a (id=0) → and.a, b (id=1) → and.b, and(id=2) → out(id=3, output_pin)
const and_components = [_]FullComponentRecord{
    .{ .id = 0, .kind = .input_pin, .width = 1, .name = "a", .origin = &.{} },
    .{ .id = 1, .kind = .input_pin, .width = 1, .name = "b", .origin = &.{} },
    .{ .id = 2, .kind = .and_gate, .width = 1, .name = "g", .origin = &.{} },
    .{ .id = 3, .kind = .output_pin, .width = 1, .name = "out", .origin = &.{} },
};
const and_connections = [_]FullConnectionRecord{
    .{ .from_id = 0, .to_id = 2, .port = @intFromEnum(full_format.PortName.a) },
    .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.b) },
    .{ .from_id = 2, .to_id = 3, .port = @intFromEnum(full_format.PortName.in) },
};

test "session resolves root pins by name" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    var session = try Session.build(arena.allocator(), &circuit, .{ .components = &and_components, .connections = &and_connections });

    try std.testing.expectEqual(@as(usize, 2), session.inputs.len);
    try std.testing.expectEqual(@as(usize, 1), session.outputs.len);
    try std.testing.expect(session.findInput("a") != null);
    try std.testing.expect(session.findInput("b") != null);
    try std.testing.expect(session.findInput("missing") == null);
    const out = session.findOutput("out").?;
    try std.testing.expect(session.nodeById(out.component_id) != null);
}

test "session drives and reads through the engine" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    var session = try Session.build(arena.allocator(), &circuit, .{ .components = &and_components, .connections = &and_connections });

    const a = session.findInput("a").?;
    const b = session.findInput("b").?;
    const out = session.findOutput("out").?;
    try circuit.propagateEvent(session.nodeById(a.component_id).?, .{ .value = 1, .defined = 1, .width = 1 });
    try circuit.propagateEvent(session.nodeById(b.component_id).?, .{ .value = 1, .defined = 1, .width = 1 });

    const s = circuit.readState(session.nodeById(out.component_id).?.state_handle);
    try std.testing.expectEqual(@as(u64, 1), s.value);
    try std.testing.expectEqual(@as(u64, 1), s.defined);
}
