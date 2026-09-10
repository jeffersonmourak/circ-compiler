//! Stage 2: layer assignment with dummy nodes for long edges.
//!
//! Layers are what `columns.zig` called columns, computed the same way so
//! the rewrite's first step moves no box:
//!   - every wire of the collapsed graph is an `OriginalEdge`, enumerated in
//!     node order and each node's `outputs` order;
//!   - a DFS over output edges marks the edges that close a cycle as `back`
//!     (cross-coupled latches are legal in the engine and must lay out);
//!   - a fixed-point longest-path sweep over the non-back edges puts every
//!     `input_pin` at layer 0 and every other node one past its furthest
//!     upstream; a node whose only inputs are back edges is bumped to layer 1
//!     so the return lane has a gutter to its left; `led` and `output_pin`
//!     are forced to the last layer.
//! Then every non-back edge spanning `k > 1` layers is split into `k`
//! layer-adjacent `LayerEdge`s through `k - 1` dummy nodes, so the ordering,
//! coordinate and channel stages see an edge between adjacent layers for
//! every wire and nothing else. Back edges — cycle-closing edges, and any
//! edge that sink-forcing turned leftward — get no dummies and no
//! `LayerEdge`; they stay in `originals` for the router's return lanes.
const std = @import("std");
const full_format = @import("full_format");
const types = @import("layout_types");

const VirtualGraph = types.VirtualGraph;
const VirtualNode = types.VirtualNode;
const LayerNode = types.LayerNode;
const OriginalEdge = types.OriginalEdge;
const LayerEdge = types.LayerEdge;
const LayeredGraph = types.LayeredGraph;

pub fn layer(arena: std.mem.Allocator, graph: VirtualGraph) !LayeredGraph {
    const n = graph.nodes.len;

    var index_of = std.AutoHashMap(u32, usize).init(arena);
    for (graph.nodes, 0..) |node_, i| try index_of.put(node_.id, i);

    // ---- originals, in node order then outputs order ----
    var originals: std.ArrayList(OriginalEdge) = .{};
    // `first_original[i]` + the count of valid outputs before output `k`
    // gives output k's index into `originals`; an output whose destination is
    // not in the graph produces no original (and the DFS skips it too).
    const first_original = try arena.alloc(u32, n);
    for (graph.nodes, 0..) |node_, i| {
        first_original[i] = @intCast(originals.items.len);
        for (node_.outputs) |e| {
            const dst = index_of.get(e.dst_id) orelse continue;
            try originals.append(arena, .{ .src = i, .src_port = e.src_port, .dst = dst, .dst_port = e.dst_port, .back = false });
        }
    }

    // ---- back edges: iterative DFS, roots in node order (deterministic) ----
    {
        const Color = enum(u8) { white, gray, black };
        const color = try arena.alloc(Color, n);
        @memset(color, .white);
        const Frame = struct { node_idx: usize, next_output: usize, next_original: u32 };
        var stack: std.ArrayList(Frame) = .{};
        for (0..n) |start| {
            if (color[start] != .white) continue;
            color[start] = .gray;
            try stack.append(arena, .{ .node_idx = start, .next_output = 0, .next_original = first_original[start] });
            while (stack.items.len > 0) {
                const top = &stack.items[stack.items.len - 1];
                const node_ = graph.nodes[top.node_idx];
                if (top.next_output >= node_.outputs.len) {
                    color[top.node_idx] = .black;
                    _ = stack.pop();
                    continue;
                }
                const e = node_.outputs[top.next_output];
                top.next_output += 1;
                const dst = index_of.get(e.dst_id) orelse continue;
                const oi = top.next_original;
                top.next_original += 1;
                switch (color[dst]) {
                    .gray => originals.items[oi].back = true,
                    .white => {
                        color[dst] = .gray;
                        try stack.append(arena, .{ .node_idx = dst, .next_output = 0, .next_original = first_original[dst] });
                    },
                    .black => {},
                }
            }
        }
    }

    // ---- longest path over the non-back originals ----
    const layer_of = try arena.alloc(u32, n);
    @memset(layer_of, 0);
    const is_back_dst = try arena.alloc(bool, n);
    @memset(is_back_dst, false);
    for (originals.items) |o| {
        if (o.back) is_back_dst[o.dst] = true;
    }
    var changed = true;
    var iter: usize = 0;
    while (changed and iter <= n + 1) : (iter += 1) {
        changed = false;
        for (graph.nodes, 0..) |node_, i| {
            if (isInputPin(node_)) {
                if (layer_of[i] != 0) {
                    layer_of[i] = 0;
                    changed = true;
                }
                continue;
            }
            var want: u32 = 0;
            for (originals.items) |o| {
                if (o.back or o.dst != i) continue;
                const cand = layer_of[o.src] + 1;
                if (cand > want) want = cand;
            }
            if (want == 0 and is_back_dst[i]) want = 1;
            if (want != layer_of[i]) {
                layer_of[i] = want;
                changed = true;
            }
        }
    }
    var num_layers: u32 = 1;
    for (layer_of) |l| {
        if (l + 1 > num_layers) num_layers = l + 1;
    }
    for (graph.nodes, 0..) |node_, i| {
        if (isSink(node_)) layer_of[i] = num_layers - 1;
    }
    // Forcing a sink to the last layer can turn one of its own outputs into a
    // leftward wire (an `led` driving a gate, `regression_led_out_drives_gate`).
    // Such an edge is not a DFS back edge but must be routed like one: flag
    // it so it gets no dummies and no layer-adjacent segment.
    for (originals.items) |*o| {
        if (!o.back and layer_of[o.dst] <= layer_of[o.src]) o.back = true;
    }

    // ---- nodes: real first, then dummies; edges: per original, per segment ----
    var nodes: std.ArrayList(LayerNode) = .{};
    for (0..n) |i| try nodes.append(arena, .{ .real = i, .layer = layer_of[i], .carries = null });

    var edges: std.ArrayList(LayerEdge) = .{};
    for (originals.items, 0..) |o, oi_usize| {
        const oi: u32 = @intCast(oi_usize);
        if (o.back) continue;
        const l_src = layer_of[o.src];
        const l_dst = layer_of[o.dst];
        std.debug.assert(l_dst > l_src);
        var prev: u32 = @intCast(o.src);
        var prev_port: u8 = o.src_port;
        var l = l_src + 1;
        while (l < l_dst) : (l += 1) {
            const dummy: u32 = @intCast(nodes.items.len);
            try nodes.append(arena, .{ .real = null, .layer = l, .carries = oi });
            try edges.append(arena, .{ .src = prev, .dst = dummy, .src_port = prev_port, .dst_port = 0, .original = oi });
            prev = dummy;
            prev_port = 0;
        }
        try edges.append(arena, .{ .src = prev, .dst = @intCast(o.dst), .src_port = prev_port, .dst_port = o.dst_port, .original = oi });
    }

    return .{
        .nodes = try nodes.toOwnedSlice(arena),
        .edges = try edges.toOwnedSlice(arena),
        .originals = try originals.toOwnedSlice(arena),
        .num_layers = num_layers,
    };
}

fn isInputPin(node_: VirtualNode) bool {
    return switch (node_.kind) {
        .primitive => |p| p == .input_pin,
        .subcircuit => false,
    };
}

fn isSink(node_: VirtualNode) bool {
    return switch (node_.kind) {
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

fn mk(id: u32, kind: NodeKind, inputs: []const InputEdge, outputs: []const OutputEdge) VirtualNode {
    return .{ .id = id, .kind = kind, .name = "", .origin = &.{}, .inputs = inputs, .outputs = outputs };
}

fn layersOf(lg: LayeredGraph, count: usize, out: []u32) void {
    for (lg.nodes[0..count], 0..) |ln, i| out[i] = ln.layer;
}

test "layering: longest path, input pins at 0, sinks last" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // pin → not → and → led, plus a second led fed straight from the pin.
    const pin = mk(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 4, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_n = mk(1, .{ .primitive = .not_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_A },
    });
    const and_n = mk(2, .{ .primitive = .and_gate }, &.{.{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_A }}, &.{
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const led_late = mk(3, .{ .primitive = .led }, &.{.{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    const led_early = mk(4, .{ .primitive = .led }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    const nodes = [_]VirtualNode{ pin, not_n, and_n, led_late, led_early };
    const lg = try layer(a, .{ .nodes = &nodes, .next_id = 5 });

    try std.testing.expectEqual(@as(u32, 4), lg.num_layers);
    var ls: [5]u32 = undefined;
    layersOf(lg, 5, &ls);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 2, 3, 3 }, &ls);
    // pin → led_early spans 3 layers: two dummies in layers 1 and 2, three segments.
    try std.testing.expectEqual(@as(usize, 7), lg.nodes.len);
    try std.testing.expectEqual(@as(u32, 1), lg.nodes[5].layer);
    try std.testing.expectEqual(@as(u32, 2), lg.nodes[6].layer);
    try std.testing.expectEqual(@as(?u32, 1), lg.nodes[5].carries);
    try std.testing.expectEqual(@as(?usize, null), lg.nodes[6].real);
    try std.testing.expectEqual(@as(usize, 6), lg.edges.len); // 3 short + 3 segments
    const segs = lg.edges[1..4];
    try std.testing.expectEqual(@as(u32, 0), segs[0].src);
    try std.testing.expectEqual(@as(u32, 5), segs[0].dst);
    try std.testing.expectEqual(@as(u32, 5), segs[1].src);
    try std.testing.expectEqual(@as(u32, 6), segs[1].dst);
    try std.testing.expectEqual(@as(u32, 6), segs[2].src);
    try std.testing.expectEqual(@as(u32, 4), segs[2].dst);
    try std.testing.expectEqual(DST_IN, segs[2].dst_port);
    try std.testing.expectEqual(@as(u8, 0), segs[1].dst_port);
    for (segs) |s| try std.testing.expectEqual(@as(u32, 1), s.original);
}

test "layering: a back edge is flagged, gets no dummy, and bumps its destination to layer 1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // not_a.out → not_b.in, not_b.out → not_a.in (2-cycle). DFS from not_a
    // classifies not_b → not_a as back; not_a is bumped to layer 1.
    const not_a = mk(0, .{ .primitive = .not_gate }, &.{.{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_b = mk(1, .{ .primitive = .not_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{
        .{ .dst_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const nodes = [_]VirtualNode{ not_a, not_b };
    const lg = try layer(a, .{ .nodes = &nodes, .next_id = 2 });
    try std.testing.expectEqual(@as(usize, 2), lg.originals.len);
    try std.testing.expect(!lg.originals[0].back);
    try std.testing.expect(lg.originals[1].back);
    try std.testing.expectEqual(@as(usize, 2), lg.nodes.len); // no dummies
    try std.testing.expectEqual(@as(usize, 1), lg.edges.len); // only the forward edge
    try std.testing.expectEqual(@as(u32, 1), lg.nodes[0].layer);
    try std.testing.expectEqual(@as(u32, 2), lg.nodes[1].layer);
    try std.testing.expectEqual(@as(u32, 3), lg.num_layers);
}

test "layering: a self loop is a back edge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const g = mk(0, .{ .primitive = .not_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{
        .{ .dst_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const nodes = [_]VirtualNode{g};
    const lg = try layer(a, .{ .nodes = &nodes, .next_id = 1 });
    try std.testing.expect(lg.originals[0].back);
    try std.testing.expectEqual(@as(usize, 0), lg.edges.len);
    try std.testing.expectEqual(@as(u32, 1), lg.nodes[0].layer);
}

test "layering: a sink driving a gate to its left is a back edge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // pin → led; led.out → and.a; pin → and.b; and → out. The led is forced
    // to the last layer, so led → and runs leftward.
    const pin = mk(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_B },
    });
    const led = mk(1, .{ .primitive = .led }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_A },
    });
    const and_n = mk(2, .{ .primitive = .and_gate }, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_A },
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_B },
    }, &.{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN }});
    const out = mk(3, .{ .primitive = .output_pin }, &.{.{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    const nodes = [_]VirtualNode{ pin, led, and_n, out };
    const lg = try layer(a, .{ .nodes = &nodes, .next_id = 4 });
    // originals: pin→led (0), pin→and (1), led→and (2), and→out (3)
    try std.testing.expect(lg.originals[2].back);
    try std.testing.expect(!lg.originals[0].back);
    try std.testing.expectEqual(@as(u32, 3), lg.nodes[1].layer); // led on the last layer
    try std.testing.expectEqual(@as(u32, 2), lg.nodes[2].layer);
    // pin→led spans 3 layers → 2 dummies; pin→and spans 2 → 1 dummy; led→and none.
    try std.testing.expectEqual(@as(usize, 7), lg.nodes.len);
    try std.testing.expectEqual(@as(usize, 6), lg.edges.len);
}

test "layering: a diamond spans one layer per edge and needs no dummies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pin = mk(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const na = mk(1, .{ .primitive = .not_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_A }});
    const nb = mk(2, .{ .primitive = .not_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_B }});
    const and_n = mk(3, .{ .primitive = .and_gate }, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_A },
        .{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_B },
    }, &.{});
    const nodes = [_]VirtualNode{ pin, na, nb, and_n };
    const lg = try layer(a, .{ .nodes = &nodes, .next_id = 4 });
    try std.testing.expectEqual(@as(usize, 4), lg.nodes.len);
    try std.testing.expectEqual(@as(usize, 4), lg.edges.len);
    try std.testing.expectEqual(@as(u32, 3), lg.num_layers);
}
