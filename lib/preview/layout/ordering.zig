//! Stage 3: the order of nodes inside each layer.
//!
//! `countCrossings` is the measure: over every pair of adjacent layers, the
//! number of pairs of layer-adjacent edges that cross when drawn straight
//! between the two layers' current orders, with a node's input ports
//! distinguished (an edge into `a` and an edge into `b` of one `and` cross
//! when their sources are ordered the other way round). The key of an edge
//! end is `pos * SLOT_KEY_BASE + slot`, so the comparison is integer only.
//!
//! `fromRows` lifts the old `RowAssignment` into an `Ordering` so the
//! measure has a baseline before the sweeps replace it: real nodes in row
//! order, dummies after them in the order of their source's position.
const std = @import("std");
const full_format = @import("full_format");
const types = @import("layout_types");
const ports = @import("ports");

const VirtualGraph = types.VirtualGraph;
const LayeredGraph = types.LayeredGraph;
const LayerEdge = types.LayerEdge;
const Ordering = types.Ordering;
const RowAssignment = types.RowAssignment;

/// Sort key of an edge end inside its layer: the node's position, then the
/// port's slot on that node (0 for an output, a dummy, or an unknown port).
fn endKey(graph: VirtualGraph, layered: LayeredGraph, pos: []const u32, node: u32, dst_port: ?u8) u64 {
    const ln = layered.nodes[node];
    var slot_idx: u32 = 0;
    if (dst_port) |dp| {
        if (ln.real) |ri| {
            if (ports.slotIndex(graph.nodes[ri], dp)) |s| slot_idx = s;
        }
    }
    return @as(u64, pos[node]) * ports.SLOT_KEY_BASE + slot_idx;
}

/// Crossings between layers `l` and `l + 1` under `pos`.
fn countBilayer(arena: std.mem.Allocator, graph: VirtualGraph, layered: LayeredGraph, pos: []const u32, l: u32, scratch: *std.ArrayList([2]u64)) !u64 {
    scratch.clearRetainingCapacity();
    for (layered.edges) |e| {
        if (layered.nodes[e.src].layer != l) continue;
        try scratch.append(arena, .{
            endKey(graph, layered, pos, e.src, null),
            endKey(graph, layered, pos, e.dst, e.dst_port),
        });
    }
    var n: u64 = 0;
    const items = scratch.items;
    for (items, 0..) |a, i| {
        for (items[i + 1 ..]) |b| {
            if ((a[0] < b[0] and a[1] > b[1]) or (a[0] > b[0] and a[1] < b[1])) n += 1;
        }
    }
    return n;
}

pub fn countCrossings(arena: std.mem.Allocator, graph: VirtualGraph, layered: LayeredGraph, ordering: Ordering) !u64 {
    var scratch: std.ArrayList([2]u64) = .{};
    var total: u64 = 0;
    var l: u32 = 0;
    while (l + 1 < layered.num_layers) : (l += 1) {
        total += try countBilayer(arena, graph, layered, ordering.pos, l, &scratch);
    }
    return total;
}

/// The old row assignment as an `Ordering` (the Phase 1 baseline): real
/// nodes by `row_of`, then each layer's dummies ordered by their source
/// node's final position (ties by `LayerNode` index), so a long edge is
/// counted as running straight out of its source.
pub fn fromRows(arena: std.mem.Allocator, layered: LayeredGraph, rows: RowAssignment) !Ordering {
    const n = layered.nodes.len;
    const pos = try arena.alloc(u32, n);
    @memset(pos, 0);
    const order = try arena.alloc([]u32, layered.num_layers);

    var l: u32 = 0;
    while (l < layered.num_layers) : (l += 1) {
        var reals: std.ArrayList(u32) = .{};
        var dummies: std.ArrayList(u32) = .{};
        for (layered.nodes, 0..) |ln, i| {
            if (ln.layer != l) continue;
            if (ln.real != null) try reals.append(arena, @intCast(i)) else try dummies.append(arena, @intCast(i));
        }
        std.mem.sort(u32, reals.items, rows, struct {
            fn lt(r: RowAssignment, a: u32, b: u32) bool {
                if (r.row_of[a] != r.row_of[b]) return r.row_of[a] < r.row_of[b];
                return a < b;
            }
        }.lt);
        for (reals.items, 0..) |ni, p| pos[ni] = @intCast(p);
        order[l] = reals.items;
        // Dummies are placed once every real node in every layer has a
        // position, below.
        if (dummies.items.len > 0) {
            var merged: std.ArrayList(u32) = .{};
            try merged.appendSlice(arena, reals.items);
            try merged.appendSlice(arena, dummies.items);
            order[l] = merged.items;
        }
    }

    // Dummy order: by source position, walking layers left to right so a
    // chain of dummies inherits its head's position.
    l = 0;
    while (l < layered.num_layers) : (l += 1) {
        const layer_order = order[l];
        var first_dummy: usize = 0;
        while (first_dummy < layer_order.len and layered.nodes[layer_order[first_dummy]].real != null) first_dummy += 1;
        if (first_dummy == layer_order.len) continue;
        const dummies = layer_order[first_dummy..];
        const Ctx = struct { layered: LayeredGraph, pos: []const u32 };
        std.mem.sort(u32, dummies, Ctx{ .layered = layered, .pos = pos }, struct {
            fn srcPos(ctx: Ctx, d: u32) u32 {
                for (ctx.layered.edges) |e| {
                    if (e.dst == d) return ctx.pos[e.src];
                }
                return 0;
            }
            fn lt(ctx: Ctx, a: u32, b: u32) bool {
                const pa = srcPos(ctx, a);
                const pb = srcPos(ctx, b);
                if (pa != pb) return pa < pb;
                return a < b;
            }
        }.lt);
        for (layer_order, 0..) |ni, p| pos[ni] = @intCast(p);
    }

    return .{ .order = order, .pos = pos, .rounds = 0 };
}

// ---------- Tests ----------

const VirtualNode = types.VirtualNode;
const InputEdge = types.InputEdge;
const OutputEdge = types.OutputEdge;
const NodeKind = types.NodeKind;
const layering = @import("layering");
const SRC_OUT: u8 = @intFromEnum(full_format.PortName.out);
const DST_IN: u8 = @intFromEnum(full_format.PortName.in);
const DST_A: u8 = @intFromEnum(full_format.PortName.a);
const DST_B: u8 = @intFromEnum(full_format.PortName.b);

fn mk(id: u32, kind: NodeKind, inputs: []const InputEdge, outputs: []const OutputEdge) VirtualNode {
    return .{ .id = id, .kind = kind, .name = "", .origin = &.{}, .inputs = inputs, .outputs = outputs };
}

/// Two pins feeding two NOTs; `rows` decides whether the wires cross.
fn twoByTwo(a: std.mem.Allocator, rows_col1: [2]u32) !struct { graph: VirtualGraph, layered: LayeredGraph, ordering: Ordering } {
    const nodes = try a.alloc(VirtualNode, 4);
    nodes[0] = mk(0, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{.{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN }}));
    nodes[1] = mk(1, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN }}));
    nodes[2] = mk(2, .{ .primitive = .not_gate }, try a.dupe(InputEdge, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}), &.{});
    nodes[3] = mk(3, .{ .primitive = .not_gate }, try a.dupe(InputEdge, &.{.{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN }}), &.{});
    const graph = VirtualGraph{ .nodes = nodes, .next_id = 4 };
    const layered = try layering.layer(a, graph);
    const row_of = try a.dupe(u32, &.{ 0, 1, rows_col1[0], rows_col1[1] });
    const ordering = try fromRows(a, layered, .{ .row_of = row_of, .num_rows = 2 });
    return .{ .graph = graph, .layered = layered, .ordering = ordering };
}

test "ordering: countCrossings is 1 on a crossed pair and 0 on an uncrossed one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const crossed = try twoByTwo(a, .{ 1, 0 });
    try std.testing.expectEqual(@as(u64, 1), try countCrossings(a, crossed.graph, crossed.layered, crossed.ordering));
    const straight = try twoByTwo(a, .{ 0, 1 });
    try std.testing.expectEqual(@as(u64, 0), try countCrossings(a, straight.graph, straight.layered, straight.ordering));
}

test "ordering: a and b ports crossed by source order count" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // pin0 → and.b, pin1 → and.a with pin0 above pin1: the wires cross.
    const nodes = try a.alloc(VirtualNode, 3);
    nodes[0] = mk(0, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{.{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_B }}));
    nodes[1] = mk(1, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{.{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_A }}));
    nodes[2] = mk(2, .{ .primitive = .and_gate }, try a.dupe(InputEdge, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_B },
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_A },
    }), &.{});
    const graph = VirtualGraph{ .nodes = nodes, .next_id = 3 };
    const layered = try layering.layer(a, graph);
    const o1 = try fromRows(a, layered, .{ .row_of = try a.dupe(u32, &.{ 0, 1, 0 }), .num_rows = 2 });
    try std.testing.expectEqual(@as(u64, 1), try countCrossings(a, graph, layered, o1));
    const o2 = try fromRows(a, layered, .{ .row_of = try a.dupe(u32, &.{ 1, 0, 0 }), .num_rows = 2 });
    try std.testing.expectEqual(@as(u64, 0), try countCrossings(a, graph, layered, o2));
}

test "ordering: fromRows places dummies after real nodes by source position" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // pin0 → not (layer 1) → led (layer 2); pin1 → led2 directly (dummy in layer 1).
    const nodes = try a.alloc(VirtualNode, 5);
    nodes[0] = mk(0, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{.{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN }}));
    nodes[1] = mk(1, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{.{ .dst_id = 4, .src_port = SRC_OUT, .dst_port = DST_IN }}));
    nodes[2] = mk(2, .{ .primitive = .not_gate }, try a.dupe(InputEdge, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}), try a.dupe(OutputEdge, &.{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN }}));
    nodes[3] = mk(3, .{ .primitive = .led }, try a.dupe(InputEdge, &.{.{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN }}), &.{});
    nodes[4] = mk(4, .{ .primitive = .led }, try a.dupe(InputEdge, &.{.{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN }}), &.{});
    const graph = VirtualGraph{ .nodes = nodes, .next_id = 5 };
    const layered = try layering.layer(a, graph);
    try std.testing.expectEqual(@as(usize, 6), layered.nodes.len);
    const o = try fromRows(a, layered, .{ .row_of = try a.dupe(u32, &.{ 0, 1, 0, 0, 1 }), .num_rows = 2 });
    try std.testing.expectEqualSlices(u32, &.{ 2, 5 }, o.order[1]); // not, then the dummy
    try std.testing.expectEqual(@as(u32, 1), o.pos[5]);
    try std.testing.expectEqual(@as(u64, 0), try countCrossings(a, graph, layered, o));
}
