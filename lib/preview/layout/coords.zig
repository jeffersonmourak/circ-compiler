//! Stage 4: coordinates. Every node — real box or dummy row — gets its own
//! `y`, chosen so the wire feeding its first input port arrives straight
//! whenever the packing allows; columns get their `x` from cumulative box
//! widths plus per-gap channel widths.
//!
//! Rows, walking layers left to right and each layer's nodes in the ordering:
//!   1. Preferred row. A real node with in-edges takes the one whose input
//!      port sits highest on its border (`a` before `b`); the wire is straight
//!      when the node's top is that source's port row minus the port's own
//!      row offset. A dummy prefers its source's port row exactly. Nodes with
//!      no in-edge from the previous layer (layer 0, back-edge-only sinks)
//!      have no preference.
//!   2. Packing. Nodes are placed top to bottom at `max(cursor, preferred)`
//!      (or `cursor` with no preference), `cursor` advancing past the box plus
//!      `ROW_GUTTER`, so the ordering is preserved and boxes never touch.
//!   3. Reverse pass (slice 3) and dummy straightening.
//!   4. Columns: a layer is as wide as its widest box; the gap after it is
//!      `widths.after[layer]` (a stub of the old `COL_GUTTER` until the
//!      channel stage supplies demand).
//! `insertSpacerRow` is the one door the channel stage uses to make room.
const std = @import("std");
const full_format = @import("full_format");
const layout = @import("layout");
const types = @import("layout_types");
const boxes = @import("boxes");
const ports = @import("ports");

const VirtualGraph = types.VirtualGraph;
const LayeredGraph = types.LayeredGraph;
const Ordering = types.Ordering;
const Coords = types.Coords;
const ChannelWidths = types.ChannelWidths;
const PlacedComponent = layout.PlacedComponent;

/// Rows between two boxes in one layer.
pub const ROW_GUTTER: u32 = 1;
/// The old gutter, used for every gap until Phase 3 measures demand.
pub const STUB_CHANNEL_WIDTH: u32 = 5;

pub fn stubWidths(arena: std.mem.Allocator, num_layers: u32) !ChannelWidths {
    const after = try arena.alloc(u32, num_layers);
    @memset(after, STUB_CHANNEL_WIDTH);
    return .{ .after = after };
}

const Adjacency = struct { ins: [][]const u32 };

fn buildIns(arena: std.mem.Allocator, layered: LayeredGraph) ![][]const u32 {
    const n = layered.nodes.len;
    var lists = try arena.alloc(std.ArrayList(u32), n);
    for (0..n) |i| lists[i] = .{};
    for (layered.edges, 0..) |e, ei| try lists[e.dst].append(arena, @intCast(ei));
    const out = try arena.alloc([]const u32, n);
    for (0..n) |i| out[i] = lists[i].items;
    return out;
}

pub fn assign(
    arena: std.mem.Allocator,
    graph: VirtualGraph,
    layered: LayeredGraph,
    ordering: Ordering,
    opts: layout.LayoutOptions,
    widths: ChannelWidths,
) !Coords {
    const n = layered.nodes.len;
    const num_layers = layered.num_layers;

    // Box sizes: real nodes from `boxes`, dummies 0 wide and 1 tall.
    const w = try arena.alloc(u32, n);
    const h = try arena.alloc(u32, n);
    for (layered.nodes, 0..) |ln, i| {
        if (ln.real) |ri| {
            const sz = boxes.sizeOf(graph.nodes[ri], opts);
            w[i] = sz.width;
            h[i] = sz.height;
        } else {
            w[i] = 0;
            h[i] = 1;
        }
    }

    const ins = try buildIns(arena, layered);
    const y = try arena.alloc(u32, n);
    @memset(y, 0);

    // Rows: layer by layer, preferred row then packing.
    var l: u32 = 0;
    while (l < num_layers) : (l += 1) {
        var cursor: u32 = 0;
        for (ordering.order[l]) |ni| {
            const preferred = preferredRow(graph, layered, ins, y, h, ni);
            const top = if (preferred) |p| @max(cursor, p) else cursor;
            y[ni] = top;
            cursor = top + h[ni] + ROW_GUTTER;
        }
    }

    // Columns.
    const layer_w = try arena.alloc(u32, num_layers);
    @memset(layer_w, 0);
    for (layered.nodes, 0..) |ln, i| {
        if (w[i] > layer_w[ln.layer]) layer_w[ln.layer] = w[i];
    }
    for (layer_w) |*lw| {
        if (lw.* == 0) lw.* = 1; // a layer of dummies still needs a cell
    }
    const layer_x = try arena.alloc(u32, num_layers);
    const channel_x = try arena.alloc(u32, num_layers);
    var acc: u32 = 0;
    for (0..num_layers) |k| {
        layer_x[k] = acc;
        channel_x[k] = acc + layer_w[k];
        acc += layer_w[k] + widths.after[k];
    }
    const x = try arena.alloc(u32, n);
    var width: u32 = 0;
    var height: u32 = 0;
    for (layered.nodes, 0..) |ln, i| {
        x[i] = layer_x[ln.layer];
        if (x[i] + w[i] > width) width = x[i] + w[i];
        if (y[i] + h[i] > height) height = y[i] + h[i];
    }

    return .{
        .x = x,
        .y = y,
        .w = w,
        .h = h,
        .layer_x = layer_x,
        .layer_w = layer_w,
        .channel_x = channel_x,
        .width = width,
        .height = height,
    };
}

/// Absolute row of a node's output port (a dummy's own row).
fn outputPortRow(graph: VirtualGraph, layered: LayeredGraph, y: []const u32, h: []const u32, ni: u32) u32 {
    const ln = layered.nodes[ni];
    if (ln.real) |ri| return y[ni] + ports.outputRow(graph.nodes[ri], h[ni]);
    return y[ni];
}

/// The top row that makes the node's highest input wire straight, if it has
/// an in-edge from the previous layer.
fn preferredRow(graph: VirtualGraph, layered: LayeredGraph, ins: [][]const u32, y: []const u32, h: []const u32, ni: u32) ?u32 {
    const ln = layered.nodes[ni];
    const edges = ins[ni];
    if (edges.len == 0) return null;
    if (ln.real) |ri| {
        const node = graph.nodes[ri];
        var best_slot: ?u8 = null;
        var best_edge: u32 = 0;
        for (edges) |ei| {
            const e = layered.edges[ei];
            const s = ports.slotIndex(node, e.dst_port) orelse continue;
            if (best_slot == null or s < best_slot.?) {
                best_slot = s;
                best_edge = ei;
            }
        }
        const s = best_slot orelse return null;
        const e = layered.edges[best_edge];
        const src_row = outputPortRow(graph, layered, y, h, e.src);
        const port_row = ports.inputSlots(node)[s].row;
        return src_row -| port_row;
    }
    // A dummy: straight from its source.
    return outputPortRow(graph, layered, y, h, layered.edges[edges[0]].src);
}

/// Every node at or below row `at` moves down one row; the grid grows by one.
pub fn insertSpacerRow(coords: *Coords, at: u32) void {
    for (coords.y) |*yy| {
        if (yy.* >= at) yy.* += 1;
    }
    coords.height += 1;
}

/// The `PlacedComponent` list for the real nodes, in `VirtualGraph` order —
/// what the router and the render read.
pub fn toPlaced(
    arena: std.mem.Allocator,
    graph: VirtualGraph,
    layered: LayeredGraph,
    coords: Coords,
    opts: layout.LayoutOptions,
) ![]PlacedComponent {
    const placed = try arena.alloc(PlacedComponent, graph.nodes.len);
    for (layered.nodes, 0..) |ln, i| {
        const ri = ln.real orelse continue;
        const node = graph.nodes[ri];
        const px = coords.x[i];
        const py = coords.y[i];
        const pw = coords.w[i];
        const ph = coords.h[i];
        const pc = try boxes.resolvePortCoords(arena, node, px, py, pw, ph);
        placed[ri] = .{
            .id = node.id,
            .kind = node.kind,
            .name = node.name,
            .origin = node.origin,
            .x = px,
            .y = py,
            .width = pw,
            .height = ph,
            .in_ports = pc.in_ports,
            .out_port = pc.out_port,
            .signal_width = node.signal_width,
            .display_label = try boxes.composeDisplayLabel(arena, node, opts),
        };
    }
    return placed;
}

// ---------- Tests ----------

const layering = @import("layering");
const ordering_stage = @import("ordering");
const VirtualNode = types.VirtualNode;
const InputEdge = types.InputEdge;
const OutputEdge = types.OutputEdge;
const NodeKind = types.NodeKind;
const SRC_OUT: u8 = @intFromEnum(full_format.PortName.out);
const DST_IN: u8 = @intFromEnum(full_format.PortName.in);
const DST_A: u8 = @intFromEnum(full_format.PortName.a);
const DST_B: u8 = @intFromEnum(full_format.PortName.b);

fn mk(a: std.mem.Allocator, id: u32, kind: NodeKind, inputs: []const InputEdge, outputs: []const OutputEdge) !VirtualNode {
    return .{ .id = id, .kind = kind, .name = "", .origin = &.{}, .inputs = try a.dupe(InputEdge, inputs), .outputs = try a.dupe(OutputEdge, outputs) };
}

const Built = struct { graph: VirtualGraph, layered: LayeredGraph, ordering: Ordering, coords: Coords };

fn build(a: std.mem.Allocator, nodes: []VirtualNode) !Built {
    const graph = VirtualGraph{ .nodes = nodes, .next_id = @intCast(nodes.len) };
    const layered = try layering.layer(a, graph);
    const ordering = try ordering_stage.order(a, graph, layered);
    const coords = try assign(a, graph, layered, ordering, .{}, try stubWidths(a, layered.num_layers));
    return .{ .graph = graph, .layered = layered, .ordering = ordering, .coords = coords };
}

test "coords: a NOT feeding an AND's b port sits two rows lower" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // a → and.a, b → not → and.b (the and_of_not shape).
    const nodes = try a.alloc(VirtualNode, 5);
    nodes[0] = try mk(a, 0, .{ .primitive = .input_pin }, &.{}, &.{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_A }});
    nodes[1] = try mk(a, 1, .{ .primitive = .input_pin }, &.{}, &.{.{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN }});
    nodes[2] = try mk(a, 2, .{ .primitive = .not_gate }, &.{.{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_B }});
    nodes[3] = try mk(a, 3, .{ .primitive = .and_gate }, &.{ .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_A }, .{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_B } }, &.{.{ .dst_id = 4, .src_port = SRC_OUT, .dst_port = DST_IN }});
    nodes[4] = try mk(a, 4, .{ .primitive = .output_pin }, &.{.{ .src_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    const b = try build(a, nodes);
    const c = b.coords;
    // Pins: rows 0 and 4. The NOT (layer 1) prefers b's port row (5) minus 1 = 4.
    try std.testing.expectEqual(@as(u32, 0), c.y[0]);
    try std.testing.expectEqual(@as(u32, 4), c.y[1]);
    try std.testing.expectEqual(@as(u32, 4), c.y[2]);
    // The AND (layer 2) has a from a dummy on row 1 (a's port row) → top 0,
    // and its b port at row 3 meets the NOT's output row 5 only if the AND
    // sat at 2; a wins (slot 0), so the AND is at 0 and the NOT is 4 = 0 + 2 + 2.
    try std.testing.expectEqual(@as(u32, 0), c.y[3]);
    try std.testing.expectEqual(@as(u32, 2), c.y[2] - c.y[3] - 2);
}

test "coords: packing never overlaps and never reorders" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // One pin fans out to a NOT, an AND (a), and another NOT: mixed heights in layer 1.
    const nodes = try a.alloc(VirtualNode, 4);
    nodes[0] = try mk(a, 0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_A },
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    nodes[1] = try mk(a, 1, .{ .primitive = .not_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    nodes[2] = try mk(a, 2, .{ .primitive = .and_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_A }}, &.{});
    nodes[3] = try mk(a, 3, .{ .primitive = .not_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    const b = try build(a, nodes);
    const c = b.coords;
    const lo = b.ordering.order[1];
    for (lo[1..], 0..) |ni, i| {
        const prev = lo[i];
        try std.testing.expect(c.y[ni] >= c.y[prev] + c.h[prev] + ROW_GUTTER);
    }
    try std.testing.expectEqual(@as(u32, 0), c.y[lo[0]]);
}

test "coords: layer 0 packs from row 0 with one free row between boxes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const nodes = try a.alloc(VirtualNode, 4);
    nodes[0] = try mk(a, 0, .{ .primitive = .input_pin }, &.{}, &.{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN }});
    nodes[1] = try mk(a, 1, .{ .primitive = .input_pin }, &.{}, &.{});
    nodes[2] = try mk(a, 2, .{ .primitive = .input_pin }, &.{}, &.{});
    nodes[3] = try mk(a, 3, .{ .primitive = .led }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    const b = try build(a, nodes);
    try std.testing.expectEqualSlices(u32, &.{ 0, 4, 8 }, b.coords.y[0..3]);
    try std.testing.expectEqual(@as(u32, 0), b.coords.y[3]);
    try std.testing.expectEqual(@as(u32, 5 + STUB_CHANNEL_WIDTH), b.coords.x[3]);
    try std.testing.expectEqual(@as(u32, 11), b.coords.height);
}

test "coords: insertSpacerRow shifts every node at or below the row and grows height" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const nodes = try a.alloc(VirtualNode, 3);
    nodes[0] = try mk(a, 0, .{ .primitive = .input_pin }, &.{}, &.{});
    nodes[1] = try mk(a, 1, .{ .primitive = .input_pin }, &.{}, &.{});
    nodes[2] = try mk(a, 2, .{ .primitive = .input_pin }, &.{}, &.{});
    const b = try build(a, nodes);
    var c = b.coords;
    insertSpacerRow(&c, 4);
    try std.testing.expectEqualSlices(u32, &.{ 0, 5, 9 }, c.y);
    try std.testing.expectEqual(@as(u32, 12), c.height);
}
