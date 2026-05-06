const std = @import("std");
const full_format = @import("full_format");
const layout = @import("layout");
const types = @import("layout_types");
const sizing = @import("sizing");

const VirtualGraph = types.VirtualGraph;
const VirtualNode = types.VirtualNode;
const ColumnAssignment = types.ColumnAssignment;
const RowAssignment = types.RowAssignment;
const PlacedComponent = layout.PlacedComponent;
const PortSlot = layout.PortSlot;
const PortCoord = layout.PortCoord;

/// Spacing between adjacent column cells (used for wire routing).
const COL_GUTTER: u32 = 4;
/// Spacing between adjacent row cells.
const ROW_GUTTER: u32 = 1;

const Ports = struct {
    in_ports: []const PortSlot,
    out_port: PortCoord,
};

/// Stage 4: turn `(VirtualGraph, ColumnAssignment, RowAssignment)` into
/// `[]PlacedComponent` with absolute (x, y) coordinates and per-port slots.
///
/// Layout convention:
///   - Per-column max width determines that column's gutter-anchored x range.
///   - Per-row max height determines that row's y range, applied uniformly
///     across columns so rows align horizontally regardless of column.
///   - Each cell is left-aligned at its column's left edge.
///   - Port coordinates are derived from each kind's published port table
///     (and gates: a top-left, b bottom-left, out middle-right; not gates:
///     in/out at vertical middle; pins/leds: single port at edge).
pub fn place(
    arena: std.mem.Allocator,
    graph: VirtualGraph,
    columns: ColumnAssignment,
    rows: RowAssignment,
) ![]PlacedComponent {
    const n = graph.nodes.len;

    // 1. Compute every node's cell size up front.
    const sizes = try arena.alloc(sizing.PrimitiveSize, n);
    for (graph.nodes, 0..) |node, i| sizes[i] = sizeOf(node);

    // 2. Per-column max width and per-row max height.
    const col_widths = try arena.alloc(u32, columns.num_columns);
    @memset(col_widths, 0);
    const row_heights = try arena.alloc(u32, @max(rows.num_rows, 1));
    @memset(row_heights, 0);

    for (graph.nodes, 0..) |_, i| {
        const col = columns.column_of[i];
        const row = rows.row_of[i];
        if (sizes[i].width > col_widths[col]) col_widths[col] = sizes[i].width;
        if (sizes[i].height > row_heights[row]) row_heights[row] = sizes[i].height;
    }

    // 3. Cumulative left-edge x per column, top-edge y per row.
    const col_x = try arena.alloc(u32, columns.num_columns);
    {
        var x_acc: u32 = 0;
        for (col_widths, 0..) |w, k| {
            col_x[k] = x_acc;
            x_acc += w + COL_GUTTER;
        }
    }
    const row_y = try arena.alloc(u32, row_heights.len);
    {
        var y_acc: u32 = 0;
        for (row_heights, 0..) |h, k| {
            row_y[k] = y_acc;
            y_acc += h + ROW_GUTTER;
        }
    }

    // 4. Build PlacedComponent list.
    const placed = try arena.alloc(PlacedComponent, n);
    for (graph.nodes, 0..) |node, i| {
        const col = columns.column_of[i];
        const row = rows.row_of[i];
        const x = col_x[col];
        const y = row_y[row];
        const w = sizes[i].width;
        const h = sizes[i].height;

        const ports = try resolvePortCoords(arena, node, x, y, w, h);

        placed[i] = .{
            .id = node.id,
            .kind = node.kind,
            .name = node.name,
            .origin = node.origin,
            .x = x,
            .y = y,
            .width = w,
            .height = h,
            .in_ports = ports.in_ports,
            .out_port = ports.out_port,
        };
    }

    return placed;
}

fn sizeOf(node: VirtualNode) sizing.PrimitiveSize {
    return switch (node.kind) {
        .primitive => |p| sizing.primitive_sizing.get(p),
        .subcircuit => |sub| sizing.macroSize(sub.len + node.name.len + 3), // [, :, ]
    };
}

fn resolvePortCoords(arena: std.mem.Allocator, node: VirtualNode, x: u32, y: u32, w: u32, h: u32) !Ports {
    var in_list: std.ArrayList(PortSlot) = .{};
    // Default out_port at middle-right; specific kinds override below.
    var out_port = PortCoord{ .x = x + w - 1, .y = y + h / 2 };

    switch (node.kind) {
        .primitive => |p| switch (p) {
            .input_pin => {
                out_port = .{ .x = x + w - 1, .y = y };
            },
            .output_pin => {
                try in_list.append(arena, .{ .port_name = "in", .coord = .{ .x = x, .y = y } });
                // out_port unused on sinks; keep default.
            },
            .not_gate => {
                try in_list.append(arena, .{ .port_name = "in", .coord = .{ .x = x, .y = y + 1 } });
                out_port = .{ .x = x + w - 1, .y = y + 1 };
            },
            .and_gate => {
                try in_list.append(arena, .{ .port_name = "a", .coord = .{ .x = x, .y = y } });
                try in_list.append(arena, .{ .port_name = "b", .coord = .{ .x = x, .y = y + 2 } });
                out_port = .{ .x = x + w - 1, .y = y + 1 };
            },
            .led => {
                try in_list.append(arena, .{ .port_name = "in", .coord = .{ .x = x, .y = y + 1 } });
                // out_port unused on sinks.
            },
            .wire => unreachable, // wires were collapsed in stage 1.
        },
        .subcircuit => {
            // Inspect the virtual node's incoming edges to decide which boundary
            // ports to expose. Maps PortName bytes to the same slot positions
            // as gate primitives (in=middle, a=top, b=bottom).
            var has_in = false;
            var has_a = false;
            var has_b = false;
            for (node.inputs) |edge| {
                switch (edge.dst_port) {
                    @intFromEnum(full_format.PortName.in) => has_in = true,
                    @intFromEnum(full_format.PortName.a) => has_a = true,
                    @intFromEnum(full_format.PortName.b) => has_b = true,
                    else => {},
                }
            }
            if (has_a) try in_list.append(arena, .{ .port_name = "a", .coord = .{ .x = x, .y = y } });
            if (has_in) try in_list.append(arena, .{ .port_name = "in", .coord = .{ .x = x, .y = y + h / 2 } });
            if (has_b) try in_list.append(arena, .{ .port_name = "b", .coord = .{ .x = x, .y = y + h - 1 } });
            out_port = .{ .x = x + w - 1, .y = y + h / 2 };
        },
    }

    return .{
        .in_ports = try in_list.toOwnedSlice(arena),
        .out_port = out_port,
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

test "place_cell_sizing: not_gate at column 1 row 0" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two nodes: pin (id=0, col=0, row=0) drives not (id=1, col=1, row=0).
    const pin = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_node = makeNode(1, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});

    const nodes = [_]VirtualNode{ pin, not_node };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 2 };
    const cols = ColumnAssignment{ .column_of = &[_]u32{ 0, 1 }, .num_columns = 2 };
    const rows = RowAssignment{ .row_of = &[_]u32{ 0, 0 }, .num_rows = 1 };

    const placed = try place(a, graph, cols, rows);
    try std.testing.expectEqual(@as(usize, 2), placed.len);

    // not at col 1 row 0:
    //   col_widths = [pin=6, not=5] → col_x = [0, 6+4=10]
    //   row_heights = [max(1, 3)=3] → row_y = [0]
    // → not.x = 10, not.y = 0, width = 5, height = 3
    try std.testing.expectEqual(@as(u32, 10), placed[1].x);
    try std.testing.expectEqual(@as(u32, 0), placed[1].y);
    try std.testing.expectEqual(@as(u32, 5), placed[1].width);
    try std.testing.expectEqual(@as(u32, 3), placed[1].height);
}

test "place_port_coords_and_gate: a, b, out at expected offsets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a_alloc = arena.allocator();

    // pin1 (col 0 row 0), pin2 (col 0 row 1), and_gate (col 1 row 0).
    const pin1 = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_A },
    });
    const pin2 = makeNode(1, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_B },
    });
    const and_gate = makeNode(2, .{ .primitive = .and_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_A },
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_B },
    }, &.{});

    const nodes = [_]VirtualNode{ pin1, pin2, and_gate };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 3 };
    const cols = ColumnAssignment{ .column_of = &[_]u32{ 0, 0, 1 }, .num_columns = 2 };
    const rows = RowAssignment{ .row_of = &[_]u32{ 0, 1, 0 }, .num_rows = 2 };

    const placed = try place(a_alloc, graph, cols, rows);

    // and_gate: col_x[1] = 6 + 4 = 10, row_y[0] = 0 → (10, 0). width=5, height=3.
    const and_p = placed[2];
    try std.testing.expectEqual(@as(u32, 10), and_p.x);
    try std.testing.expectEqual(@as(u32, 0), and_p.y);

    // Ports per spec: a at (x, y), b at (x, y+2), out at (x+4, y+1).
    try std.testing.expectEqual(@as(usize, 2), and_p.in_ports.len);
    try std.testing.expectEqualStrings("a", and_p.in_ports[0].port_name);
    try std.testing.expectEqual(@as(u32, 10), and_p.in_ports[0].coord.x);
    try std.testing.expectEqual(@as(u32, 0), and_p.in_ports[0].coord.y);
    try std.testing.expectEqualStrings("b", and_p.in_ports[1].port_name);
    try std.testing.expectEqual(@as(u32, 10), and_p.in_ports[1].coord.x);
    try std.testing.expectEqual(@as(u32, 2), and_p.in_ports[1].coord.y);
    try std.testing.expectEqual(@as(u32, 14), and_p.out_port.x);
    try std.testing.expectEqual(@as(u32, 1), and_p.out_port.y);
}

test "place_macro_label_width: long subcircuit alias widens the box" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Single subcircuit virtual node: kind = .subcircuit("xor"), name = "longish_combine".
    // Label = "[xor:longish_combine]" → 21 chars; macroSize(21) = max(8, 23) = 23.
    var sub_node = makeNode(0, .{ .subcircuit = "xor" }, &.{}, &.{});
    sub_node.name = "longish_combine";

    const nodes = [_]VirtualNode{sub_node};
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 1 };
    const cols = ColumnAssignment{ .column_of = &[_]u32{0}, .num_columns = 1 };
    const rows = RowAssignment{ .row_of = &[_]u32{0}, .num_rows = 1 };

    const placed = try place(a, graph, cols, rows);
    try std.testing.expectEqual(@as(u32, 23), placed[0].width);
    try std.testing.expectEqual(@as(u32, 3), placed[0].height);
    // Verify the box widened beyond the 8-char floor.
    try std.testing.expect(placed[0].width > 8);
}
