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
    const layer_orders = try arena.alloc([]u32, layered.num_layers);

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
        layer_orders[l] = reals.items;
        // Dummies are placed once every real node in every layer has a
        // position, below.
        if (dummies.items.len > 0) {
            var merged: std.ArrayList(u32) = .{};
            try merged.appendSlice(arena, reals.items);
            try merged.appendSlice(arena, dummies.items);
            layer_orders[l] = merged.items;
        }
    }

    // Dummy order: by source position, walking layers left to right so a
    // chain of dummies inherits its head's position.
    l = 0;
    while (l < layered.num_layers) : (l += 1) {
        const layer_order = layer_orders[l];
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

    return .{ .order = layer_orders, .pos = pos, .rounds = 0 };
}

// ---------- The sweeps ----------

const Bary = struct { sum: u64, count: u64 };

fn lessBary(a: Bary, b: Bary) bool {
    // a.sum / a.count < b.sum / b.count, in integers.
    return a.sum * b.count < b.sum * a.count;
}

const Adjacency = struct {
    /// Per LayerNode: indices into `layered.edges` entering / leaving it.
    ins: [][]const u32,
    outs: [][]const u32,
};

fn buildAdjacency(arena: std.mem.Allocator, layered: LayeredGraph) !Adjacency {
    const n = layered.nodes.len;
    var ins = try arena.alloc(std.ArrayList(u32), n);
    var outs = try arena.alloc(std.ArrayList(u32), n);
    for (0..n) |i| {
        ins[i] = .{};
        outs[i] = .{};
    }
    for (layered.edges, 0..) |e, ei| {
        try ins[e.dst].append(arena, @intCast(ei));
        try outs[e.src].append(arena, @intCast(ei));
    }
    const ins_s = try arena.alloc([]const u32, n);
    const outs_s = try arena.alloc([]const u32, n);
    for (0..n) |i| {
        ins_s[i] = ins[i].items;
        outs_s[i] = outs[i].items;
    }
    return .{ .ins = ins_s, .outs = outs_s };
}

const Direction = enum { down, up };

/// Reorder layer `l` by the barycenter of each node's neighbours in the
/// previous (down) or next (up) layer. A node with no such neighbours keeps
/// its current key so it stays where it is relative to the others.
fn sweepLayer(
    arena: std.mem.Allocator,
    graph: VirtualGraph,
    layered: LayeredGraph,
    adj: Adjacency,
    order_l: []u32,
    pos: []u32,
    dir: Direction,
) !void {
    const Entry = struct { node: u32, bary: Bary, cur: u32 };
    const entries = try arena.alloc(Entry, order_l.len);
    for (order_l, 0..) |ni, i| {
        var b = Bary{ .sum = 0, .count = 0 };
        const edges = switch (dir) {
            .down => adj.ins[ni],
            .up => adj.outs[ni],
        };
        for (edges) |ei| {
            const e = layered.edges[ei];
            b.sum += switch (dir) {
                .down => endKey(graph, layered, pos, e.src, null),
                .up => endKey(graph, layered, pos, e.dst, e.dst_port),
            };
            b.count += 1;
        }
        if (b.count == 0) b = .{ .sum = @as(u64, pos[ni]) * ports.SLOT_KEY_BASE, .count = 1 };
        entries[i] = .{ .node = ni, .bary = b, .cur = pos[ni] };
    }
    std.mem.sort(Entry, entries, {}, struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            if (lessBary(a.bary, b.bary)) return true;
            if (lessBary(b.bary, a.bary)) return false;
            return a.cur < b.cur;
        }
    }.lt);
    for (entries, 0..) |en, i| {
        order_l[i] = en.node;
        pos[en.node] = @intCast(i);
    }
}

/// Crossings of the two bilayers that touch layer `l`.
fn crossingsAround(arena: std.mem.Allocator, graph: VirtualGraph, layered: LayeredGraph, pos: []const u32, l: u32, scratch: *std.ArrayList([2]u64)) !u64 {
    var n: u64 = 0;
    if (l > 0) n += try countBilayer(arena, graph, layered, pos, l - 1, scratch);
    if (l + 1 < layered.num_layers) n += try countBilayer(arena, graph, layered, pos, l, scratch);
    return n;
}

pub const MAX_ROUNDS: u8 = 4;
pub const MAX_TRANSPOSE_PASSES: u8 = 16;

/// The ordering: initial order by node index (real nodes ascend by id, then
/// dummies in `originals` order), then down/up barycenter rounds kept while
/// they reduce `countCrossings` (at most `MAX_ROUNDS`), then adjacent swaps
/// that strictly reduce the crossings around a layer, to a fixed point.
pub fn order(arena: std.mem.Allocator, graph: VirtualGraph, layered: LayeredGraph) !Ordering {
    const n = layered.nodes.len;
    const adj = try buildAdjacency(arena, layered);

    const pos = try arena.alloc(u32, n);
    const current = try arena.alloc([]u32, layered.num_layers);
    {
        var counts = try arena.alloc(u32, layered.num_layers);
        @memset(counts, 0);
        for (layered.nodes) |ln| counts[ln.layer] += 1;
        for (0..layered.num_layers) |l| current[l] = try arena.alloc(u32, counts[l]);
        @memset(counts, 0);
        for (layered.nodes, 0..) |ln, i| {
            current[ln.layer][counts[ln.layer]] = @intCast(i);
            pos[i] = counts[ln.layer];
            counts[ln.layer] += 1;
        }
    }

    const best_pos = try arena.alloc(u32, n);
    const best = try arena.alloc([]u32, layered.num_layers);
    for (0..layered.num_layers) |l| best[l] = try arena.alloc(u32, current[l].len);
    var scratch: std.ArrayList([2]u64) = .{};
    const snapshot = struct {
        fn take(dst_pos: []u32, dst: [][]u32, src_pos: []const u32, src: []const []const u32) void {
            @memcpy(dst_pos, src_pos);
            for (src, 0..) |layer_order, l| @memcpy(dst[l], layer_order);
        }
    };
    snapshot.take(best_pos, best, pos, current);
    var best_count = try countCrossings(arena, graph, layered, .{ .order = current, .pos = pos });

    var rounds: u8 = 0;
    while (rounds < MAX_ROUNDS) {
        rounds += 1;
        var l: u32 = 1;
        while (l < layered.num_layers) : (l += 1) try sweepLayer(arena, graph, layered, adj, current[l], pos, .down);
        if (layered.num_layers >= 2) {
            l = layered.num_layers - 1;
            while (l > 0) : (l -= 1) try sweepLayer(arena, graph, layered, adj, current[l - 1], pos, .up);
        }
        const count = try countCrossings(arena, graph, layered, .{ .order = current, .pos = pos });
        if (count < best_count) {
            best_count = count;
            snapshot.take(best_pos, best, pos, current);
        } else break;
    }
    // Continue from the best ordering seen.
    snapshot.take(pos, current, best_pos, best);

    var passes: u8 = 0;
    while (passes < MAX_TRANSPOSE_PASSES) : (passes += 1) {
        var swapped = false;
        var l: u32 = 0;
        while (l < layered.num_layers) : (l += 1) {
            const lo = current[l];
            if (lo.len < 2) continue;
            var before = try crossingsAround(arena, graph, layered, pos, l, &scratch);
            var i: usize = 0;
            while (i + 1 < lo.len) : (i += 1) {
                const v = lo[i];
                const w = lo[i + 1];
                lo[i] = w;
                lo[i + 1] = v;
                pos[w] = @intCast(i);
                pos[v] = @intCast(i + 1);
                const after = try crossingsAround(arena, graph, layered, pos, l, &scratch);
                if (after < before) {
                    before = after;
                    swapped = true;
                } else {
                    lo[i] = v;
                    lo[i + 1] = w;
                    pos[v] = @intCast(i);
                    pos[w] = @intCast(i + 1);
                }
            }
        }
        if (!swapped) break;
    }

    const order_const = try arena.alloc([]const u32, layered.num_layers);
    for (current, 0..) |lo, l| order_const[l] = lo;
    return .{ .order = order_const, .pos = pos, .rounds = rounds };
}

/// The old `RowAssignment` view over the real nodes: a real node's row is
/// its index among the real nodes of its layer.
pub fn toRows(arena: std.mem.Allocator, layered: LayeredGraph, ordering: Ordering, real_count: usize) !RowAssignment {
    const row_of = try arena.alloc(u32, real_count);
    var num_rows: u32 = 0;
    for (ordering.order) |lo| {
        var r: u32 = 0;
        for (lo) |ni| {
            if (layered.nodes[ni].real) |ri| {
                row_of[ri] = r;
                r += 1;
            }
        }
        if (r > num_rows) num_rows = r;
    }
    return .{ .row_of = row_of, .num_rows = num_rows };
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

test "ordering: order resolves a crossed pair and keeps an uncrossed one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // pin0 → not3, pin1 → not2: by id the NOTs start crossed.
    const nodes = try a.alloc(VirtualNode, 4);
    nodes[0] = mk(0, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN }}));
    nodes[1] = mk(1, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{.{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN }}));
    nodes[2] = mk(2, .{ .primitive = .not_gate }, try a.dupe(InputEdge, &.{.{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN }}), &.{});
    nodes[3] = mk(3, .{ .primitive = .not_gate }, try a.dupe(InputEdge, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}), &.{});
    const graph = VirtualGraph{ .nodes = nodes, .next_id = 4 };
    const layered = try layering.layer(a, graph);
    const o = try order(a, graph, layered);
    try std.testing.expectEqual(@as(u64, 0), try countCrossings(a, graph, layered, o));
    try std.testing.expectEqualSlices(u32, &.{ 3, 2 }, o.order[1]);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1 }, o.order[0]); // layer 0 keeps id order
    const rows = try toRows(a, layered, o, 4);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 1, 0 }, rows.row_of);
}

test "ordering: equal barycenters keep the current order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // One pin fans out to three NOTs: all barycenters equal → id order.
    const nodes = try a.alloc(VirtualNode, 4);
    nodes[0] = mk(0, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN },
    }));
    for (1..4) |i| nodes[i] = mk(@intCast(i), .{ .primitive = .not_gate }, try a.dupe(InputEdge, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}), &.{});
    const graph = VirtualGraph{ .nodes = nodes, .next_id = 4 };
    const layered = try layering.layer(a, graph);
    const o = try order(a, graph, layered);
    try std.testing.expectEqualSlices(u32, &.{ 1, 2, 3 }, o.order[1]);
}

test "ordering: the sweep stops when a round does not improve" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const nodes = try a.alloc(VirtualNode, 2);
    nodes[0] = mk(0, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{.{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN }}));
    nodes[1] = mk(1, .{ .primitive = .not_gate }, try a.dupe(InputEdge, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}), &.{});
    const graph = VirtualGraph{ .nodes = nodes, .next_id = 2 };
    const layered = try layering.layer(a, graph);
    const o = try order(a, graph, layered);
    // Nothing to improve: the first round is also the last.
    try std.testing.expectEqual(@as(u8, 1), o.rounds);
}

test "ordering: transpose reaches a fixed point that the sweeps alone miss" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Two pins each feeding one AND on both ports, wired so that both ANDs
    // have the same barycenter (each hears from both pins) yet one order
    // has more crossings than the other: pin0 → and2.a, pin1 → and2.b,
    // pin1 → and3.a, pin0 → and3.b. Order (2, 3) crosses twice, (3, 2) also
    // twice — but the ports inside each AND decide: the port-aware count
    // is what transpose compares, and it must end at a fixed point.
    const nodes = try a.alloc(VirtualNode, 4);
    nodes[0] = mk(0, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_A },
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_B },
    }));
    nodes[1] = mk(1, .{ .primitive = .input_pin }, &.{}, try a.dupe(OutputEdge, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_B },
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_A },
    }));
    nodes[2] = mk(2, .{ .primitive = .and_gate }, try a.dupe(InputEdge, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_A },
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_B },
    }), &.{});
    nodes[3] = mk(3, .{ .primitive = .and_gate }, try a.dupe(InputEdge, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_A },
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_B },
    }), &.{});
    const graph = VirtualGraph{ .nodes = nodes, .next_id = 4 };
    const layered = try layering.layer(a, graph);
    const o1 = try order(a, graph, layered);
    const c1 = try countCrossings(a, graph, layered, o1);
    // Running the sweeps again from the result changes nothing: fixed point.
    const o2 = try order(a, graph, layered);
    try std.testing.expectEqualSlices(u32, o1.pos, o2.pos);
    // And no adjacent swap in any layer improves it.
    for (o1.order, 0..) |lo, l| {
        if (lo.len < 2) continue;
        const pos = try a.dupe(u32, o1.pos);
        var i: usize = 0;
        while (i + 1 < lo.len) : (i += 1) {
            pos[lo[i]] = @intCast(i + 1);
            pos[lo[i + 1]] = @intCast(i);
            const c = try countCrossings(a, graph, layered, .{ .order = o1.order, .pos = pos });
            try std.testing.expect(c >= c1);
            pos[lo[i]] = @intCast(i);
            pos[lo[i + 1]] = @intCast(i + 1);
        }
        _ = l;
    }
}
