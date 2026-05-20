const std = @import("std");
const engine = @import("circuit");
const full_format = @import("full_format");

pub const State = enum(u2) {
    low = 0,
    high = 1,
    undef = 2,

    fn fromEngine(s: engine.State) State {
        return switch (s) {
            .low => .low,
            .high => .high,
            .undefined => .undef,
        };
    }
};

pub const PinRef = struct {
    name: []const u8,
    component_id: u32,
};

pub const Header = struct {
    inputs: []const PinRef,
    outputs: []const PinRef,
};

pub const Row = struct {
    input_bits: u64,
    outputs: []const State,
};

pub const Table = struct {
    arena: std.heap.ArenaAllocator,
    header: Header,
    rows: []const Row,
    /// Engine-level counters captured from the underlying Circuit just
    /// before it was deinit'd. Populated only when the linked engine module
    /// has `COLLECT_METRICS=true` (i.e. inside `zig build bench`); zero
    /// elsewhere. Consumers that don't care about benchmarking can ignore.
    metrics: engine.Metrics = .{},
    /// Wall-clock nanoseconds spent in the `2^N` vector drive loop only,
    /// excluding circuit construction and connection wiring. Lets the bench
    /// separate engine throughput from one-shot setup cost. Always populated
    /// (the timestamp call is cheap); consumers can ignore.
    drive_ns: u64 = 0,

    pub fn deinit(self: *Table) void {
        self.arena.deinit();
    }
};

pub const BuildOptions = struct {
    max_inputs: u6 = 16,
};

pub const BuildError = error{
    TooManyInputs,
    NoOutputs,
    OutOfMemory,
    InvalidTopology,
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

pub fn build(
    parent_allocator: std.mem.Allocator,
    topology: full_format.FullTopology,
    options: BuildOptions,
) BuildError!Table {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena.deinit();
    const arena_alloc = arena.allocator();

    // Only the root circuit's pins matter for the truth table. Macro-expanded
    // sub-circuits also emit input_pin / output_pin primitives, but those are
    // wired through to root drivers and aren't independent test vectors. The
    // origin chain is empty exactly for root-level components.
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
    if (input_count > options.max_inputs) return error.TooManyInputs;
    if (output_count == 0) return error.NoOutputs;

    var inputs = try arena_alloc.alloc(PinRef, input_count);
    var outputs = try arena_alloc.alloc(PinRef, output_count);
    var i_idx: usize = 0;
    var o_idx: usize = 0;
    for (topology.components) |comp| {
        if (comp.origin.len != 0) continue;
        switch (comp.kind) {
            .input_pin => {
                inputs[i_idx] = .{ .name = comp.name, .component_id = comp.id };
                i_idx += 1;
            },
            .output_pin => {
                outputs[o_idx] = .{ .name = comp.name, .component_id = comp.id };
                o_idx += 1;
            },
            else => {},
        }
    }

    var circuit = engine.Circuit.init() catch return error.InvalidTopology;
    defer circuit.deinit();

    var id_to_node = std.AutoHashMap(u32, *engine.Component).init(arena_alloc);
    try id_to_node.ensureTotalCapacity(@intCast(topology.components.len));
    for (topology.components) |comp| {
        const node = switch (comp.kind) {
            .input_pin => circuit.createComponent(.{ .input_pin_gate = .{} }),
            .not_gate => circuit.createComponent(.{ .not_gate = .{} }),
            .and_gate => circuit.createComponent(.{ .and_gate = .{} }),
            .wire => circuit.createComponent(.{ .wire = .{} }),
            .led => circuit.createComponent(.{ .led = .{} }),
            .output_pin => circuit.createComponent(.{ .output_pin = .{} }),
        } catch return error.InvalidTopology;
        node.id = comp.id;
        id_to_node.putAssumeCapacity(comp.id, node);
    }

    for (topology.connections) |conn| {
        const from_node = id_to_node.get(conn.from_id) orelse return error.InvalidTopology;
        const to_node = id_to_node.get(conn.to_id) orelse return error.InvalidTopology;
        const port_str = portByteToName(conn.port) catch return error.InvalidTopology;
        circuit.connect(.{ from_node, "out" }, .{ to_node, port_str }) catch return error.InvalidTopology;
    }

    const row_count: usize = if (input_count == 0) 1 else (@as(usize, 1) << @intCast(input_count));
    var rows = try arena_alloc.alloc(Row, row_count);

    const drive_start = std.time.nanoTimestamp();
    var mask: u64 = 0;
    while (mask < row_count) : (mask += 1) {
        for (inputs, 0..) |pin, idx| {
            const bit = (mask >> @intCast(idx)) & 1;
            const new_state: engine.State = if (bit == 1) .high else .low;
            const node = id_to_node.get(pin.component_id) orelse return error.InvalidTopology;
            circuit.propagateEvent(node, new_state) catch return error.InvalidTopology;
        }

        const row_outputs = try arena_alloc.alloc(State, output_count);
        for (outputs, 0..) |pin, idx| {
            const node = id_to_node.get(pin.component_id) orelse return error.InvalidTopology;
            row_outputs[idx] = State.fromEngine(node.output_state);
        }
        rows[mask] = .{ .input_bits = mask, .outputs = row_outputs };
    }
    const drive_ns: u64 = @intCast(std.time.nanoTimestamp() - drive_start);

    const metrics_snapshot: engine.Metrics = if (engine.COLLECT_METRICS) circuit.metrics else .{};

    return .{
        .arena = arena,
        .header = .{ .inputs = inputs, .outputs = outputs },
        .rows = rows,
        .metrics = metrics_snapshot,
        .drive_ns = drive_ns,
    };
}

// ---------- Tests ----------

const test_alloc = std.testing.allocator;
const FullTopology = full_format.FullTopology;
const FullComponentRecord = full_format.FullComponentRecord;
const FullConnectionRecord = full_format.FullConnectionRecord;

fn topo(components: []const FullComponentRecord, connections: []const FullConnectionRecord) FullTopology {
    return .{ .components = components, .connections = connections };
}

test "truth_table_build_and_two_inputs" {
    // a (id=0, input_pin) → and.a, b (id=1, input_pin) → and.b, and(id=2) → out(id=3, output_pin)
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .name = "a", .origin = &.{} },
        .{ .id = 1, .kind = .input_pin, .name = "b", .origin = &.{} },
        .{ .id = 2, .kind = .and_gate, .name = "g", .origin = &.{} },
        .{ .id = 3, .kind = .output_pin, .name = "result", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 2, .port = @intFromEnum(full_format.PortName.a) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.b) },
        .{ .from_id = 2, .to_id = 3, .port = @intFromEnum(full_format.PortName.in) },
    };

    var table = try build(test_alloc, topo(&components, &connections), .{});
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.header.inputs.len);
    try std.testing.expectEqualStrings("a", table.header.inputs[0].name);
    try std.testing.expectEqualStrings("b", table.header.inputs[1].name);
    try std.testing.expectEqual(@as(usize, 1), table.header.outputs.len);
    try std.testing.expectEqualStrings("result", table.header.outputs[0].name);

    try std.testing.expectEqual(@as(usize, 4), table.rows.len);
    // mask=0 (a=0, b=0) → 0
    try std.testing.expectEqual(State.low, table.rows[0].outputs[0]);
    // mask=1 (a=1, b=0) → 0
    try std.testing.expectEqual(State.low, table.rows[1].outputs[0]);
    // mask=2 (a=0, b=1) → 0
    try std.testing.expectEqual(State.low, table.rows[2].outputs[0]);
    // mask=3 (a=1, b=1) → 1
    try std.testing.expectEqual(State.high, table.rows[3].outputs[0]);
}

test "truth_table_build_not_gate" {
    // Single-input NOT: input(0) → not(1) → output_pin(2)
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .name = "in", .origin = &.{} },
        .{ .id = 1, .kind = .not_gate, .name = "n", .origin = &.{} },
        .{ .id = 2, .kind = .output_pin, .name = "out", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.in) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.in) },
    };

    var table = try build(test_alloc, topo(&components, &connections), .{});
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.rows.len);
    try std.testing.expectEqual(State.high, table.rows[0].outputs[0]); // in=0 → out=1
    try std.testing.expectEqual(State.low, table.rows[1].outputs[0]); // in=1 → out=0
}

test "truth_table_build_rejects_too_many_inputs" {
    // 17 input pins exceeds the default 16 cap.
    var components: [17]FullComponentRecord = undefined;
    inline for (0..17) |idx| {
        components[idx] = .{ .id = idx, .kind = .input_pin, .name = "x", .origin = &.{} };
    }
    // Need at least one output so we don't hit NoOutputs first.
    const all_components = components ++ [_]FullComponentRecord{
        .{ .id = 17, .kind = .output_pin, .name = "out", .origin = &.{} },
    };
    const t = topo(&all_components, &.{});
    try std.testing.expectError(error.TooManyInputs, build(test_alloc, t, .{}));
}

test "truth_table_build_rejects_no_outputs" {
    // Inputs only, no outputs.
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .name = "a", .origin = &.{} },
    };
    const t = topo(&components, &.{});
    try std.testing.expectError(error.NoOutputs, build(test_alloc, t, .{}));
}

test "truth_table_build_undefined_for_unconnected_output" {
    // input(0), output(1) but no connection between them. The output_pin has
    // no driver, so its state stays .undefined for every input vector.
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .name = "a", .origin = &.{} },
        .{ .id = 1, .kind = .output_pin, .name = "out", .origin = &.{} },
    };
    const t = topo(&components, &.{});
    var table = try build(test_alloc, t, .{});
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.rows.len);
    try std.testing.expectEqual(State.undef, table.rows[0].outputs[0]);
    try std.testing.expectEqual(State.undef, table.rows[1].outputs[0]);
}
