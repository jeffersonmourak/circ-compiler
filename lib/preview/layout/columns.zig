const std = @import("std");
const full_format = @import("full_format");
const types = @import("layout_types");

const VirtualGraph = types.VirtualGraph;
const VirtualNode = types.VirtualNode;
const ColumnAssignment = types.ColumnAssignment;

/// Stage 2: longest-path column assignment over a `VirtualGraph`.
///
/// Rules:
///   - `input_pin` primitives are pinned at column 0.
///   - For every other node: `column_of[n] = 1 + max(column_of[upstream])`
///     across all incoming edges.
///   - `led` and `output_pin` primitives are then forced to `num_columns - 1`
///     so all sinks line up on the right edge of the diagram.
///
/// Iteration: a fixed-point sweep that converges in at most `nodes.len + 1`
/// passes. The graph is assumed to be a DAG (combinational logic); a cycle
/// would surface as the iteration cap firing without convergence — slice 3
/// does not error on that case explicitly because today's `.circ` sources
/// can't produce one through subcircuit expansion.
pub fn assignColumns(arena: std.mem.Allocator, graph: VirtualGraph) !ColumnAssignment {
    const n = graph.nodes.len;
    const column_of = try arena.alloc(u32, n);
    @memset(column_of, 0);

    var index_of = std.AutoHashMap(u32, usize).init(arena);
    for (graph.nodes, 0..) |node, i| {
        try index_of.put(node.id, i);
    }

    // Fixed-point sweep.
    var iter: usize = 0;
    var changed = true;
    while (changed and iter <= n + 1) : (iter += 1) {
        changed = false;
        for (graph.nodes, 0..) |node, i| {
            if (isInputPin(node)) {
                if (column_of[i] != 0) {
                    column_of[i] = 0;
                    changed = true;
                }
                continue;
            }
            var max_upstream_plus_one: u32 = 0;
            for (node.inputs) |edge| {
                const up_idx = index_of.get(edge.src_id) orelse continue;
                const candidate = column_of[up_idx] + 1;
                if (candidate > max_upstream_plus_one) max_upstream_plus_one = candidate;
            }
            if (max_upstream_plus_one != column_of[i]) {
                column_of[i] = max_upstream_plus_one;
                changed = true;
            }
        }
    }

    // Determine total column count from the longest path.
    var num_columns: u32 = 1;
    for (column_of) |c| {
        if (c + 1 > num_columns) num_columns = c + 1;
    }

    // Force sinks (led, output_pin) to the rightmost column.
    for (graph.nodes, 0..) |node, i| {
        if (isSink(node)) column_of[i] = num_columns - 1;
    }

    return .{ .column_of = column_of, .num_columns = num_columns };
}

fn isInputPin(node: VirtualNode) bool {
    return switch (node.kind) {
        .primitive => |p| p == .input_pin,
        .subcircuit => false,
    };
}

fn isSink(node: VirtualNode) bool {
    return switch (node.kind) {
        .primitive => |p| p == .led or p == .output_pin,
        .subcircuit => false,
    };
}

// ---------- Tests ----------

const InputEdge = types.InputEdge;
const OutputEdge = types.OutputEdge;
const NodeKind = types.NodeKind;
const SRC_OUT: u8 = @intFromEnum(full_format.PortName.out);
const DST_IN: u8 = @intFromEnum(full_format.PortName.in);
const DST_A: u8 = @intFromEnum(full_format.PortName.a);
const DST_B: u8 = @intFromEnum(full_format.PortName.b);

fn makeNode(id: u32, kind: NodeKind, inputs: []const InputEdge, outputs: []const OutputEdge) VirtualNode {
    return .{
        .id = id,
        .kind = kind,
        .name = "",
        .origin = &.{},
        .inputs = inputs,
        .outputs = outputs,
    };
}

test "columns_longest_path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // pin → not → and → led
    // Build inputs/outputs lists to wire the chain.
    const pin = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_node = makeNode(1, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_A },
    });
    const and_node = makeNode(2, .{ .primitive = .and_gate }, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_A },
    }, &.{
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const led = makeNode(3, .{ .primitive = .led }, &.{
        .{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});

    const nodes = [_]VirtualNode{ pin, not_node, and_node, led };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 4 };

    const cols = try assignColumns(a, graph);
    try std.testing.expectEqual(@as(u32, 4), cols.num_columns);
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[0]);
    try std.testing.expectEqual(@as(u32, 1), cols.column_of[1]);
    try std.testing.expectEqual(@as(u32, 2), cols.column_of[2]);
    try std.testing.expectEqual(@as(u32, 3), cols.column_of[3]);
}

test "columns_diamond" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // pin1 fans out to not_a and not_b; both feed an and_gate.
    // Layout: pin=0, not_a=1, not_b=1, and=2.
    const pin = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_a = makeNode(1, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_A },
    });
    const not_b = makeNode(2, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_B },
    });
    const and_node = makeNode(3, .{ .primitive = .and_gate }, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_A },
        .{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_B },
    }, &.{});

    const nodes = [_]VirtualNode{ pin, not_a, not_b, and_node };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 4 };

    const cols = try assignColumns(a, graph);
    try std.testing.expectEqual(@as(u32, 3), cols.num_columns);
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[0]);
    try std.testing.expectEqual(@as(u32, 1), cols.column_of[1]);
    try std.testing.expectEqual(@as(u32, 1), cols.column_of[2]);
    try std.testing.expectEqual(@as(u32, 2), cols.column_of[3]);
}

test "columns_input_pins_at_zero" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two unrelated input pins, no downstream — both must be column 0.
    const pin1 = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{});
    const pin2 = makeNode(1, .{ .primitive = .input_pin }, &.{}, &.{});

    const nodes = [_]VirtualNode{ pin1, pin2 };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 2 };

    const cols = try assignColumns(a, graph);
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[0]);
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[1]);
}

test "columns_leds_rightmost" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // pin → not → and → led_late, plus pin → led_early (would naturally be col 1).
    // The "early" LED should still be forced to the rightmost column.
    const pin = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 4, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_node = makeNode(1, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_A },
    });
    const and_node = makeNode(2, .{ .primitive = .and_gate }, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_A },
    }, &.{
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const led_late = makeNode(3, .{ .primitive = .led }, &.{
        .{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});
    const led_early = makeNode(4, .{ .primitive = .led }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});

    const nodes = [_]VirtualNode{ pin, not_node, and_node, led_late, led_early };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 5 };

    const cols = try assignColumns(a, graph);
    try std.testing.expectEqual(@as(u32, 4), cols.num_columns);
    // Both LEDs land in the rightmost column (3), even though led_early's
    // natural longest-path column would have been 1.
    try std.testing.expectEqual(@as(u32, 3), cols.column_of[3]);
    try std.testing.expectEqual(@as(u32, 3), cols.column_of[4]);
    // Non-sinks keep their longest-path columns.
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[0]);
    try std.testing.expectEqual(@as(u32, 1), cols.column_of[1]);
    try std.testing.expectEqual(@as(u32, 2), cols.column_of[2]);
}
