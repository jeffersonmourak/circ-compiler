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
/// Sized to fit `[├][○][─][─][─][▶][┤]` — one source marker, ≥1 wire body
/// cell, one sink marker — between two adjacent boxes' border cells.
const COL_GUTTER: u32 = 5;
/// Spacing between adjacent row cells.
const ROW_GUTTER: u32 = 1;

pub const Ports = struct {
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
    opts: layout.LayoutOptions,
) ![]PlacedComponent {
    const n = graph.nodes.len;

    // 1. Compute every node's cell size up front.
    const sizes = try arena.alloc(sizing.PrimitiveSize, n);
    for (graph.nodes, 0..) |node, i| sizes[i] = sizeOf(node, opts);

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

        const display_label = try composeDisplayLabel(arena, node, opts);

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
            .signal_width = node.signal_width,
            .display_label = display_label,
        };
    }

    return placed;
}

/// Pre-compose the displayed label for a node so its memory is arena-owned
/// (the canvas stores slice pointers, not copies — see the canvas note in
/// glyphs.zig). Pins gain a `name[N]` suffix at multi-bit widths; LEDs gain
/// a `0x???...` hex or `·` row display per S11.2 decision #12; everything
/// else falls back to its bare name.
fn composeDisplayLabel(
    arena: std.mem.Allocator,
    node: VirtualNode,
    opts: layout.LayoutOptions,
) ![]const u8 {
    return switch (node.kind) {
        .primitive => |p| switch (p) {
            .input_pin, .output_pin => if (node.signal_width > 1)
                try std.fmt.allocPrint(arena, "{s}[{d}]", .{ node.name, node.signal_width })
            else
                node.name,
            .led => try composeLedLabel(arena, node.signal_width, opts.expand_display),
            .rom, .ram => try std.fmt.allocPrint(arena, "{s} {s}[{d},{d}]", .{ @tagName(p), node.name, node.signal_width, node.addr_width }),
            else => node.name,
        },
        .subcircuit => node.name,
    };
}

/// LED display label for a static preview (no runtime state — all bits
/// undefined). Width 1 keeps the literal "LED" tag. Width 2..7 with
/// expand_display becomes a row of `·` indicators (LSB on the left).
/// Anything else, including width >=8 with expand_display, becomes a hex
/// numeric display `0x?...?` with one `?` per nibble.
fn composeLedLabel(arena: std.mem.Allocator, width: u8, expand_display: bool) ![]const u8 {
    if (width <= 1) return "LED";
    if (expand_display and width < 8) {
        const buf = try arena.alloc(u8, @as(usize, width) * "·".len);
        var idx: usize = 0;
        var i: u8 = 0;
        while (i < width) : (i += 1) {
            @memcpy(buf[idx .. idx + "·".len], "·");
            idx += "·".len;
        }
        return buf;
    }
    // Numeric: one '?' per nibble of the value.
    const nibbles = (@as(usize, width) + 3) / 4;
    const buf = try arena.alloc(u8, 2 + nibbles); // "0x" + N '?'
    buf[0] = '0';
    buf[1] = 'x';
    var k: usize = 0;
    while (k < nibbles) : (k += 1) buf[2 + k] = '?';
    return buf;
}

fn sizeOf(node: VirtualNode, opts: layout.LayoutOptions) sizing.PrimitiveSize {
    return switch (node.kind) {
        .primitive => |p| switch (p) {
            .input_pin, .output_pin => sizing.pinSize(node.name.len, node.signal_width),
            .led => sizing.ledSize(node.signal_width, opts.expand_display),
            .rom => sizing.memorySize(sizing.memoryLabelLen(3, node.name.len, node.signal_width, node.addr_width), 1),
            .ram => sizing.memorySize(sizing.memoryLabelLen(3, node.name.len, node.signal_width, node.addr_width), 4),
            // Slice and concat are collapsed in stage 1; the layer
            // should never ask for their size. Return the sentinel
            // zero so a stray call doesn't crash.
            .slice, .concat => sizing.primitive_sizing.get(p),
            else => sizing.primitive_sizing.get(p),
        },
        .subcircuit => |sub| sizing.macroSize(
            sub.len + node.name.len + 3, // [, :, ]
            countActiveSubcircuitInputs(node),
        ),
    };
}

fn countActiveSubcircuitInputs(node: VirtualNode) u32 {
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
    var n: u32 = 0;
    if (has_a) n += 1;
    if (has_in) n += 1;
    if (has_b) n += 1;
    return n;
}

pub fn resolvePortCoords(arena: std.mem.Allocator, node: VirtualNode, x: u32, y: u32, w: u32, h: u32) !Ports {
    var in_list: std.ArrayList(PortSlot) = .{};
    // Default out_port one cell east of right border, middle row; specific
    // kinds override below.
    var out_port = PortCoord{ .x = x + w, .y = y + h / 2 };

    // Port coordinates live ONE CELL OUTSIDE the box border. This keeps the
    // box rectangle visually intact: the box-border cell at the port row
    // becomes `├` (source) or `┤` (sink) during glyph drawing, and the
    // marker (`○` / `▶◀▲▼`) lives at the adjacent outside cell where the
    // wire actually begins or ends.
    switch (node.kind) {
        .primitive => |p| switch (p) {
            .input_pin => {
                out_port = .{ .x = x + w, .y = y + 1 };
            },
            .output_pin => {
                try in_list.append(arena, .{ .port_name = "in", .coord = .{ .x = x -| 1, .y = y + 1 } });
                // out_port unused on sinks; keep default.
            },
            .not_gate => {
                try in_list.append(arena, .{ .port_name = "in", .coord = .{ .x = x -| 1, .y = y + 1 } });
                out_port = .{ .x = x + w, .y = y + 1 };
            },
            .and_gate => {
                // 5×5 box: inputs on rows 1 & 3 (non-corner), output centered on row 2.
                try in_list.append(arena, .{ .port_name = "a", .coord = .{ .x = x -| 1, .y = y + 1 } });
                try in_list.append(arena, .{ .port_name = "b", .coord = .{ .x = x -| 1, .y = y + 3 } });
                out_port = .{ .x = x + w, .y = y + 2 };
            },
            .led => {
                try in_list.append(arena, .{ .port_name = "in", .coord = .{ .x = x -| 1, .y = y + 1 } });
                // out_port unused on sinks.
            },
            .rom => {
                try in_list.append(arena, .{ .port_name = "addr", .coord = .{ .x = x -| 1, .y = y + 1 } });
                out_port = .{ .x = x + w, .y = y + 1 };
            },
            .ram => {
                // Four inputs on the odd border rows of a 9-tall box, output centered.
                const names = [_][]const u8{ "addr", "din", "we", "clk" };
                for (names, 0..) |name, slot| {
                    try in_list.append(arena, .{ .port_name = name, .coord = .{ .x = x -| 1, .y = y + 1 + 2 * @as(u32, @intCast(slot)) } });
                }
                out_port = .{ .x = x + w, .y = y + h / 2 };
            },
            .wire, .slice, .concat => unreachable, // wires, slices, and concats were collapsed in stage 1.
        },
        .subcircuit => {
            // Active inputs land on consecutive non-corner border rows (y+1, y+3, …)
            // in canonical port order: a, in, b. Box height grows in `sizing.macroSize`
            // to make sure those rows fit between the corners.
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
            var slot_idx: u32 = 0;
            if (has_a) {
                try in_list.append(arena, .{ .port_name = "a", .coord = .{ .x = x -| 1, .y = y + 1 + 2 * slot_idx } });
                slot_idx += 1;
            }
            if (has_in) {
                try in_list.append(arena, .{ .port_name = "in", .coord = .{ .x = x -| 1, .y = y + 1 + 2 * slot_idx } });
                slot_idx += 1;
            }
            if (has_b) {
                try in_list.append(arena, .{ .port_name = "b", .coord = .{ .x = x -| 1, .y = y + 1 + 2 * slot_idx } });
                slot_idx += 1;
            }
            out_port = .{ .x = x + w, .y = y + h / 2 };
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

    const placed = try place(a, graph, cols, rows, .{});
    try std.testing.expectEqual(@as(usize, 2), placed.len);

    // not at col 1 row 0:
    //   col_widths = [pin (anonymous) = 5, not = 5] → col_x = [0, 5+5=10]
    //   row_heights = [max(3, 3) = 3] → row_y = [0]
    // → not.x = 10, not.y = 0, width = 5, height = 3.
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

    const placed = try place(a_alloc, graph, cols, rows, .{});

    // and_gate: col_x[1] = 5 + 5 = 10, row_y[0] = 0 → (10, 0). width=5, height=5
    // (5×5 box: ports on rows 1, 3 with output centered on row 2).
    const and_p = placed[2];
    try std.testing.expectEqual(@as(u32, 10), and_p.x);
    try std.testing.expectEqual(@as(u32, 0), and_p.y);

    // Ports live one cell OUTSIDE the box border:
    //   a at (x-1, y+1) = (9, 1)
    //   b at (x-1, y+3) = (9, 3)
    //   out at (x+w, y+2) = (15, 2)
    try std.testing.expectEqual(@as(usize, 2), and_p.in_ports.len);
    try std.testing.expectEqualStrings("a", and_p.in_ports[0].port_name);
    try std.testing.expectEqual(@as(u32, 9), and_p.in_ports[0].coord.x);
    try std.testing.expectEqual(@as(u32, 1), and_p.in_ports[0].coord.y);
    try std.testing.expectEqualStrings("b", and_p.in_ports[1].port_name);
    try std.testing.expectEqual(@as(u32, 9), and_p.in_ports[1].coord.x);
    try std.testing.expectEqual(@as(u32, 3), and_p.in_ports[1].coord.y);
    try std.testing.expectEqual(@as(u32, 15), and_p.out_port.x);
    try std.testing.expectEqual(@as(u32, 2), and_p.out_port.y);
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

    const placed = try place(a, graph, cols, rows, .{});
    try std.testing.expectEqual(@as(u32, 23), placed[0].width);
    // Subcircuit has 0 inputs in this test → height stays at the 3-row floor.
    try std.testing.expectEqual(@as(u32, 3), placed[0].height);
    // Verify the box widened beyond the 8-char floor.
    try std.testing.expect(placed[0].width > 8);
}
