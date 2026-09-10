//! Stage 5: channel routing. Every wire is routed per inter-layer gap,
//! globally, from the layered graph and the coordinates:
//!
//!   - **Nets.** In gap `k` (between layers `k` and `k+1`) every layer-adjacent
//!     edge belongs to the net of its source node and port; a dummy's out-edge
//!     belongs to the net of the wire it carries. A net has one source
//!     terminal on the left edge of the gap and one or more sink terminals on
//!     the right edge, each at its port's absolute row.
//!   - **Tracks.** A net whose terminals all share one row is a straight
//!     horizontal and takes no track. Every other net gets a vertical track
//!     inside the gap covering its terminal rows; tracks are assigned by the
//!     left-edge algorithm — nets in topological order of the constraint
//!     graph, lowest track whose occupied row intervals do not touch the
//!     net's. The constraint graph has an arc `A → B` (A's track left of
//!     B's) whenever A's source rail and B's sink rail share a row, so their
//!     horizontals never overlap and no net corners on another net's cell.
//!   - **Doglegs.** A cycle in the constraint graph is broken by splitting
//!     the widest net on the cycle into two pieces joined by a horizontal jog
//!     on a row no net of the gap has a terminal on; when no such row exists
//!     a spacer row is inserted and the gap is planned again.
//!   - **Return lanes.** A back edge leaves its source down a track of the
//!     gap after its source's layer to a return row below the diagram, runs
//!     along that row to a track of the gap before its sink's layer, and
//!     rises to the sink's port row. Return-lane verticals are tracks like
//!     any other.
//!   - **Widths.** A gap is `tracks + 2` cells wide (the source marker column,
//!     the tracks, the sink marker column), never narrower than the old
//!     gutter of five, and is fed back into the coordinate stage's columns.
//!
//! `plan` decides all of the above on the first-pass coordinates (rows only);
//! `emit` turns the plan and the second-pass coordinates (columns from the
//! measured widths) into `RoutedWire`s in the shape `render.zig` reads.
const std = @import("std");
const full_format = @import("full_format");
const layout = @import("layout");
const types = @import("layout_types");
const ports = @import("ports");
const coords_stage = @import("coords");

const VirtualGraph = types.VirtualGraph;
const LayeredGraph = types.LayeredGraph;
const Ordering = types.Ordering;
const Coords = types.Coords;
const ChannelWidths = types.ChannelWidths;
const Terminal = types.Terminal;
const Piece = types.Piece;
const Jog = types.Jog;
const Net = types.Net;
const Gap = types.Gap;
const RoutePlan = types.RoutePlan;

/// A gap is never narrower than the old gutter: `○───▶` needs five cells.
pub const MIN_GAP_WIDTH: u32 = 5;

// ---------- Nets ----------

/// Absolute row of an input port on a node (a dummy's own row).
fn inputRow(graph: VirtualGraph, layered: LayeredGraph, coords: Coords, ni: u32, dst_port: u8) ?u32 {
    const ln = layered.nodes[ni];
    if (ln.real) |ri| {
        const node = graph.nodes[ri];
        const s = ports.slotIndex(node, dst_port) orelse return null;
        return coords.y[ni] + ports.inputSlots(node)[s].row;
    }
    return coords.y[ni];
}

/// Absolute row of a node's output port (a dummy's own row).
fn outputRow(graph: VirtualGraph, layered: LayeredGraph, coords: Coords, ni: u32) u32 {
    const ln = layered.nodes[ni];
    if (ln.real) |ri| return coords.y[ni] + ports.outputRow(graph.nodes[ri], coords.h[ni]);
    return coords.y[ni];
}

/// The real source node and port of the wire an edge belongs to.
fn netIdentity(layered: LayeredGraph, e: types.LayerEdge) struct { real: usize, port: u8 } {
    const o = layered.originals[e.original];
    return .{ .real = o.src, .port = o.src_port };
}

fn lessTerminalByRow(_: void, a: Terminal, b: Terminal) bool {
    if (a.row != b.row) return a.row < b.row;
    return a.node < b.node;
}

/// The forward nets of gap `k`, sorted by `(lo, src_real, src_port)`.
pub fn extractNets(arena: std.mem.Allocator, graph: VirtualGraph, layered: LayeredGraph, coords: Coords, k: u32) ![]Net {
    // Group the gap's edges by net identity, in edge order (deterministic).
    const Key = struct { real: usize, port: u8, src_node: u32 };
    var keys: std.ArrayList(Key) = .{};
    var sinks_of: std.ArrayList(std.ArrayList(Terminal)) = .{};
    for (layered.edges) |e| {
        if (layered.nodes[e.src].layer != k) continue;
        const id = netIdentity(layered, e);
        var idx: ?usize = null;
        for (keys.items, 0..) |key, i| {
            if (key.real == id.real and key.port == id.port and key.src_node == e.src) {
                idx = i;
                break;
            }
        }
        if (idx == null) {
            try keys.append(arena, .{ .real = id.real, .port = id.port, .src_node = e.src });
            try sinks_of.append(arena, .{});
            idx = keys.items.len - 1;
        }
        const row = inputRow(graph, layered, coords, e.dst, e.dst_port) orelse continue;
        try sinks_of.items[idx.?].append(arena, .{ .node = e.dst, .port = e.dst_port, .row = row, .rail = .right });
    }

    var nets: std.ArrayList(Net) = .{};
    for (keys.items, 0..) |key, i| {
        const sinks = sinks_of.items[i].items;
        if (sinks.len == 0) continue;
        std.mem.sort(Terminal, sinks, {}, lessTerminalByRow);
        const src_row = outputRow(graph, layered, coords, key.src_node);
        var lo = src_row;
        var hi = src_row;
        var straight = true;
        for (sinks) |t| {
            if (t.row < lo) lo = t.row;
            if (t.row > hi) hi = t.row;
            if (t.row != src_row) straight = false;
        }
        try nets.append(arena, .{
            .src_real = key.real,
            .src_port = key.port,
            .src = .{ .node = key.src_node, .port = key.port, .row = src_row, .rail = .left },
            .sinks = sinks,
            .lo = lo,
            .hi = hi,
            .straight = straight,
            .pieces = &.{},
            .jogs = &.{},
            .back = false,
            .fallback = false,
        });
    }
    std.mem.sort(Net, nets.items, {}, lessNet);
    return nets.toOwnedSlice(arena);
}

fn lessNet(_: void, a: Net, b: Net) bool {
    if (a.lo != b.lo) return a.lo < b.lo;
    if (a.src_real != b.src_real) return a.src_real < b.src_real;
    return a.src_port < b.src_port;
}

// ---------- Tracks ----------

/// Row intervals two pieces may not share on one track. Touching at a row
/// is sharing: that cell would belong to both.
fn overlaps(a_lo: u32, a_hi: u32, b_lo: u32, b_hi: u32) bool {
    return a_lo <= b_hi and b_lo <= a_hi;
}

/// One track-taking unit: a whole net, or a piece of a split net. Carries
/// the rails that piece owns for the constraint graph.
const Unit = struct {
    net: u32,
    piece: u32,
    lo: u32,
    hi: u32,
    /// Rows on which this unit's net has a source rail / sink rail.
    left_rows: []const u32,
    right_rows: []const u32,
    /// The other piece of the same net this one must sit left of (a dogleg
    /// keeps its jog running rightwards), or null.
    left_of: ?u32,
};

pub const TrackError = error{ ConstraintCycle, OutOfMemory };

/// Assign every non-straight net's pieces to tracks; returns the track
/// count. `error.ConstraintCycle` when the constraint graph is cyclic —
/// the caller breaks the cycle with a dogleg or a spacer row.
pub fn assignTracks(arena: std.mem.Allocator, nets: []Net) TrackError!u32 {
    // Units.
    var units: std.ArrayList(Unit) = .{};
    for (nets, 0..) |*net, ni| {
        if (net.straight) continue;
        if (net.pieces.len == 0) {
            const pieces = try arena.alloc(Piece, 1);
            pieces[0] = .{ .track = 0, .lo = net.lo, .hi = net.hi };
            net.pieces = pieces;
        }
        for (net.pieces, 0..) |pc, pi| {
            var left: std.ArrayList(u32) = .{};
            var right: std.ArrayList(u32) = .{};
            if (net.src.rail == .left and net.src.row >= pc.lo and net.src.row <= pc.hi) try left.append(arena, net.src.row);
            for (net.sinks) |t| {
                if (t.rail == .right and t.row >= pc.lo and t.row <= pc.hi) try right.append(arena, t.row);
            }
            try units.append(arena, .{
                .net = @intCast(ni),
                .piece = @intCast(pi),
                .lo = pc.lo,
                .hi = pc.hi,
                .left_rows = left.items,
                .right_rows = right.items,
                .left_of = if (pi + 1 < net.pieces.len) @as(?u32, @intCast(units.items.len + 1)) else null,
            });
        }
    }
    const n = units.items.len;
    if (n == 0) return 0;

    // Constraint arcs: a → b when a has a left rail on a row where b has a
    // right rail (a's track must be left of b's), plus dogleg piece order,
    // plus a return lane's down half left of its up half in the same gap.
    const preds = try arena.alloc(std.ArrayList(u32), n);
    const indeg = try arena.alloc(u32, n);
    @memset(indeg, 0);
    for (0..n) |i| preds[i] = .{};
    var succs = try arena.alloc(std.ArrayList(u32), n);
    for (0..n) |i| succs[i] = .{};
    const addArc = struct {
        fn f(a: std.mem.Allocator, s: []std.ArrayList(u32), p: []std.ArrayList(u32), d: []u32, from: u32, to: u32) !void {
            for (s[from].items) |t| if (t == to) return;
            try s[from].append(a, to);
            try p[to].append(a, from);
            d[to] += 1;
        }
    }.f;
    for (units.items, 0..) |ua, ia| {
        for (units.items, 0..) |ub, ib| {
            if (ia == ib) continue;
            if (ua.net == ub.net) continue;
            for (ua.left_rows) |r| {
                for (ub.right_rows) |rb| {
                    if (r == rb) try addArc(arena, succs, preds, indeg, @intCast(ia), @intCast(ib));
                }
            }
        }
        if (ua.left_of) |b| try addArc(arena, succs, preds, indeg, @intCast(ia), b);
    }
    for (nets, 0..) |net, ni| {
        if (!net.back or net.src.rail != .left) continue;
        // The down half: its up half (same src, `rail == .none` source) in
        // the same gap must sit to its right.
        for (nets, 0..) |other, oi| {
            if (oi == ni or !other.back or other.src.rail != .none) continue;
            if (other.src_real != net.src_real or other.src_port != net.src_port) continue;
            var ua: ?u32 = null;
            var ub: ?u32 = null;
            for (units.items, 0..) |u, ui| {
                if (u.net == ni) ua = @intCast(ui);
                if (u.net == oi) ub = @intCast(ui);
            }
            if (ua != null and ub != null) try addArc(arena, succs, preds, indeg, ua.?, ub.?);
        }
    }

    // Kahn's order, ties by (lo, net, piece) — units are already in that order.
    const order = try arena.alloc(u32, n);
    var count: usize = 0;
    const done = try arena.alloc(bool, n);
    @memset(done, false);
    while (count < n) {
        var picked: ?usize = null;
        for (0..n) |i| {
            if (!done[i] and indeg[i] == 0) {
                picked = i;
                break;
            }
        }
        const i = picked orelse return error.ConstraintCycle;
        done[i] = true;
        order[count] = @intCast(i);
        count += 1;
        for (succs[i].items) |s| indeg[s] -= 1;
    }

    // Left-edge assignment in that order.
    const track_of = try arena.alloc(u32, n);
    var tracks: std.ArrayList(std.ArrayList(u32)) = .{}; // per track: unit indices
    for (order) |ui| {
        const u = units.items[ui];
        var min_track: u32 = 0;
        for (preds[ui].items) |p| {
            if (track_of[p] + 1 > min_track) min_track = track_of[p] + 1;
        }
        var t: u32 = min_track;
        while (true) : (t += 1) {
            if (t >= tracks.items.len) {
                try tracks.append(arena, .{});
            }
            var free = true;
            for (tracks.items[t].items) |o| {
                const ou = units.items[o];
                if (overlaps(u.lo, u.hi, ou.lo, ou.hi)) {
                    free = false;
                    break;
                }
            }
            if (free) break;
        }
        track_of[ui] = t;
        try tracks.items[t].append(arena, ui);
        nets[u.net].pieces[u.piece].track = t;
    }
    return @intCast(tracks.items.len);
}

pub fn gapWidth(tracks: u32) u32 {
    return @max(MIN_GAP_WIDTH, tracks + 2);
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
    const coords = try coords_stage.assign(a, graph, layered, ordering, .{}, try coords_stage.stubWidths(a, layered.num_layers));
    return .{ .graph = graph, .layered = layered, .ordering = ordering, .coords = coords };
}

test "channels: a fan-out is one net with two sinks, and an aligned wire is straight" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // pin0 → not1, pin0 → not2 (fan-out); pin3 → not4 (aligned, straight).
    const nodes = try a.alloc(VirtualNode, 5);
    nodes[0] = try mk(a, 0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    nodes[1] = try mk(a, 1, .{ .primitive = .not_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    nodes[2] = try mk(a, 2, .{ .primitive = .not_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    nodes[3] = try mk(a, 3, .{ .primitive = .input_pin }, &.{}, &.{.{ .dst_id = 4, .src_port = SRC_OUT, .dst_port = DST_IN }});
    nodes[4] = try mk(a, 4, .{ .primitive = .not_gate }, &.{.{ .src_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    const b = try build(a, nodes);
    const nets = try extractNets(a, b.graph, b.layered, b.coords, 0);
    try std.testing.expectEqual(@as(usize, 2), nets.len);
    try std.testing.expectEqual(@as(usize, 0), nets[0].src_real);
    try std.testing.expectEqual(@as(usize, 2), nets[0].sinks.len);
    try std.testing.expect(!nets[0].straight);
    try std.testing.expect(nets[0].sinks[0].row < nets[0].sinks[1].row);
    try std.testing.expectEqual(@as(usize, 3), nets[1].src_real);
    try std.testing.expect(nets[1].straight);
    const tracks = try assignTracks(a, nets);
    try std.testing.expectEqual(@as(u32, 1), tracks);
    try std.testing.expectEqual(@as(u32, 5), gapWidth(tracks));
}

test "channels: a dummy chain is one net per gap with the wire's real source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // pin0 → not → led; pin1 → led2 straight across two gaps.
    const nodes = try a.alloc(VirtualNode, 5);
    nodes[0] = try mk(a, 0, .{ .primitive = .input_pin }, &.{}, &.{.{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN }});
    nodes[1] = try mk(a, 1, .{ .primitive = .input_pin }, &.{}, &.{.{ .dst_id = 4, .src_port = SRC_OUT, .dst_port = DST_IN }});
    nodes[2] = try mk(a, 2, .{ .primitive = .not_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN }});
    nodes[3] = try mk(a, 3, .{ .primitive = .led }, &.{.{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    nodes[4] = try mk(a, 4, .{ .primitive = .led }, &.{.{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{});
    const b = try build(a, nodes);
    const g0 = try extractNets(a, b.graph, b.layered, b.coords, 0);
    const g1 = try extractNets(a, b.graph, b.layered, b.coords, 1);
    try std.testing.expectEqual(@as(usize, 2), g0.len);
    try std.testing.expectEqual(@as(usize, 2), g1.len);
    var found = false;
    for (g1) |net| {
        if (net.src_real == 1) {
            found = true;
            try std.testing.expect(b.layered.nodes[net.src.node].real == null); // a dummy source
        }
    }
    try std.testing.expect(found);
}

test "channels: disjoint intervals share a track, overlapping ones do not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mkNet = struct {
        fn f(al: std.mem.Allocator, id: usize, src_row: u32, sink_rows: []const u32) !Net {
            const sinks = try al.alloc(Terminal, sink_rows.len);
            var lo = src_row;
            var hi = src_row;
            for (sink_rows, 0..) |r, i| {
                sinks[i] = .{ .node = 100, .port = 0, .row = r, .rail = .right };
                if (r < lo) lo = r;
                if (r > hi) hi = r;
            }
            return .{ .src_real = id, .src_port = 3, .src = .{ .node = @intCast(id), .port = 3, .row = src_row, .rail = .left }, .sinks = sinks, .lo = lo, .hi = hi, .straight = false, .pieces = &.{}, .jogs = &.{}, .back = false, .fallback = false };
        }
    }.f;
    // A: rows 1..3, B: rows 5..7 (disjoint), C: rows 2..6 (overlaps both).
    const nets = try a.alloc(Net, 3);
    nets[0] = try mkNet(a, 0, 1, &.{3});
    nets[1] = try mkNet(a, 1, 5, &.{7});
    nets[2] = try mkNet(a, 2, 2, &.{6});
    const tracks = try assignTracks(a, nets);
    try std.testing.expectEqual(@as(u32, 2), tracks);
    try std.testing.expectEqual(nets[0].pieces[0].track, nets[1].pieces[0].track);
    try std.testing.expect(nets[2].pieces[0].track != nets[0].pieces[0].track);
    // Touching at one row is overlapping.
    const touch = try a.alloc(Net, 2);
    touch[0] = try mkNet(a, 0, 1, &.{3});
    touch[1] = try mkNet(a, 1, 3, &.{5});
    // (touch[1]'s source on row 3 and touch[0]'s sink on row 3 also make a
    // constraint: touch[1] left of touch[0].)
    try std.testing.expectEqual(@as(u32, 2), try assignTracks(a, touch));
    try std.testing.expect(touch[1].pieces[0].track < touch[0].pieces[0].track);
}

test "channels: a source on a row is left of a sink on that row, and a cycle is reported" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mkNet = struct {
        fn f(al: std.mem.Allocator, id: usize, src_row: u32, sink_row: u32) !Net {
            const sinks = try al.alloc(Terminal, 1);
            sinks[0] = .{ .node = 100, .port = 0, .row = sink_row, .rail = .right };
            return .{ .src_real = id, .src_port = 3, .src = .{ .node = @intCast(id), .port = 3, .row = src_row, .rail = .left }, .sinks = sinks, .lo = @min(src_row, sink_row), .hi = @max(src_row, sink_row), .straight = false, .pieces = &.{}, .jogs = &.{}, .back = false, .fallback = false };
        }
    }.f;
    // A: 1 → 5; B: 5 → 9. B's source and A's sink share row 5: B left of A.
    const nets = try a.alloc(Net, 2);
    nets[0] = try mkNet(a, 0, 1, 5);
    nets[1] = try mkNet(a, 1, 5, 9);
    _ = try assignTracks(a, nets);
    try std.testing.expect(nets[1].pieces[0].track < nets[0].pieces[0].track);
    // A: 1 → 5 and B: 5 → 1: A left of B (row 1) and B left of A (row 5).
    const cyc = try a.alloc(Net, 2);
    cyc[0] = try mkNet(a, 0, 1, 5);
    cyc[1] = try mkNet(a, 1, 5, 1);
    try std.testing.expectError(error.ConstraintCycle, assignTracks(a, cyc));
}

test "channels: width is tracks plus two, never under five" {
    try std.testing.expectEqual(@as(u32, 5), gapWidth(0));
    try std.testing.expectEqual(@as(u32, 5), gapWidth(3));
    try std.testing.expectEqual(@as(u32, 6), gapWidth(4));
    try std.testing.expectEqual(@as(u32, 22), gapWidth(20));
}
