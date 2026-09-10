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
};

pub const TrackError = error{ ConstraintCycle, OutOfMemory };

pub const TrackResult = union(enum) {
    tracks: u32,
    /// The constraint graph is cyclic; `net` is the widest net among the
    /// units Kahn's order could not reach (on or downstream of a cycle).
    cycle: struct { net: u32, lo: u32, hi: u32 },
};

/// Assign every non-straight net's pieces to tracks; returns the track
/// count. `error.ConstraintCycle` when the constraint graph is cyclic —
/// the caller breaks the cycle with a dogleg or a spacer row.
pub fn assignTracks(arena: std.mem.Allocator, nets: []Net) TrackError!u32 {
    return switch (try tryAssignTracks(arena, nets)) {
        .tracks => |t| t,
        .cycle => error.ConstraintCycle,
    };
}

pub fn tryAssignTracks(arena: std.mem.Allocator, nets: []Net) !TrackResult {
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
            });
        }
    }
    const n = units.items.len;
    if (n == 0) return .{ .tracks = 0 };

    // Constraint arcs: a → b when a has a left rail on a row where b has a
    // right rail (a's track must be left of b's), plus a return lane's down
    // half left of its up half in the same gap.
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
        const i = picked orelse {
            var widest: ?usize = null;
            for (0..n) |j| {
                if (done[j]) continue;
                const u = units.items[j];
                if (widest == null or (u.hi - u.lo) > (units.items[widest.?].hi - units.items[widest.?].lo)) widest = j;
            }
            const u = units.items[widest.?];
            return .{ .cycle = .{ .net = u.net, .lo = u.lo, .hi = u.hi } };
        };
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
    // Jogs: from the track of each piece to the next's.
    for (nets) |*net| {
        if (net.jogs.len == 0) continue;
        for (net.jogs, 0..) |*jog, ji| {
            jog.from_track = net.pieces[ji].track;
            jog.to_track = net.pieces[ji + 1].track;
        }
    }
    return .{ .tracks = @intCast(tracks.items.len) };
}

pub fn gapWidth(tracks: u32) u32 {
    return @max(MIN_GAP_WIDTH, tracks + 2);
}

// ---------- Doglegs, spacer rows, return lanes: the plan ----------

/// A row in `(lo, hi)` of a gap on which no net has a terminal and no jog
/// lies — where a dogleg's jog may run — nearest the middle, or null.
fn freeJogRow(nets: []const Net, lo: u32, hi: u32) ?u32 {
    if (hi <= lo + 1) return null;
    const mid = (lo + hi) / 2;
    var d: u32 = 0;
    while (true) : (d += 1) {
        const below = mid + d;
        const above = if (mid >= d) mid - d else 0;
        var tried = false;
        if (below < hi and below > lo) {
            tried = true;
            if (rowIsFree(nets, below)) return below;
        }
        if (d > 0 and above > lo and above < hi) {
            tried = true;
            if (rowIsFree(nets, above)) return above;
        }
        if (!tried and (below >= hi) and (above <= lo)) return null;
    }
}

fn rowIsFree(nets: []const Net, row: u32) bool {
    for (nets) |net| {
        if (net.src.row == row) return false;
        for (net.sinks) |t| if (t.row == row) return false;
        for (net.jogs) |j| if (j.row == row) return false;
    }
    return true;
}

/// Split `net` at `row`: the piece containing the row becomes two pieces
/// joined by a jog on that row.
fn splitNet(arena: std.mem.Allocator, net: *Net, row: u32) !void {
    if (net.pieces.len == 0) {
        const one = try arena.alloc(Piece, 1);
        one[0] = .{ .track = 0, .lo = net.lo, .hi = net.hi };
        net.pieces = one;
    }
    var idx: ?usize = null;
    for (net.pieces, 0..) |pc, i| {
        if (pc.lo < row and row < pc.hi) idx = i;
    }
    const i = idx orelse return error.NoPieceToSplit;
    const pieces = try arena.alloc(Piece, net.pieces.len + 1);
    @memcpy(pieces[0..i], net.pieces[0..i]);
    pieces[i] = .{ .track = 0, .lo = net.pieces[i].lo, .hi = row };
    pieces[i + 1] = .{ .track = 0, .lo = row, .hi = net.pieces[i].hi };
    @memcpy(pieces[i + 2 ..], net.pieces[i + 1 ..]);
    net.pieces = pieces;
    const jogs = try arena.alloc(Jog, net.jogs.len + 1);
    @memcpy(jogs[0..i], net.jogs[0..i]);
    jogs[i] = .{ .row = row, .from_track = 0, .to_track = 0 };
    @memcpy(jogs[i + 1 ..], net.jogs[i..]);
    net.jogs = jogs;
}

const GapOutcome = union(enum) {
    tracks: u32,
    /// Insert a spacer row here and plan everything again.
    spacer: u32,
    /// No dogleg or spacer resolved it within the bound.
    unroutable: u32, // the net
};

/// Tracks for one gap, breaking constraint cycles by doglegs; asks for a
/// spacer row when a cycle's net has no free row to jog on.
fn planGap(arena: std.mem.Allocator, nets: []Net) !GapOutcome {
    // Bounded: every iteration adds a piece to some net.
    var budget: usize = nets.len * 2 + 2;
    while (budget > 0) : (budget -= 1) {
        switch (try tryAssignTracks(arena, nets)) {
            .tracks => |t| return .{ .tracks = t },
            .cycle => |c| {
                const net = &nets[c.net];
                if (freeJogRow(nets, c.lo, c.hi)) |row| {
                    try splitNet(arena, net, row);
                } else {
                    return .{ .spacer = (c.lo + c.hi) / 2 + 1 };
                }
            },
        }
    }
    const last = switch (try tryAssignTracks(arena, nets)) {
        .tracks => |t| return .{ .tracks = t },
        .cycle => |c| c.net,
    };
    return .{ .unroutable = last };
}

/// The plan: nets and tracks for every gap, return lanes for every back
/// edge, spacer rows inserted into `coords` as needed. Rows are final when
/// this returns; columns are the caller's to recompute from `widths`.
pub fn plan(arena: std.mem.Allocator, graph: VirtualGraph, layered: LayeredGraph, coords: *Coords) !RoutePlan {
    const num_layers = layered.num_layers;
    var spacer_rows: std.ArrayList(u32) = .{};
    var fallbacks: u32 = 0;

    // Back edges, in `originals` order: one return row each, below the
    // diagram (rows are re-derived after every spacer).
    var back_edges: std.ArrayList(u32) = .{};
    for (layered.originals, 0..) |o, oi| {
        if (o.back) try back_edges.append(arena, @intCast(oi));
    }

    // Bounded restart loop: each restart follows one spacer insertion, and
    // a gap asks for at most one spacer per net.
    var restarts: usize = 0;
    const max_restarts: usize = layered.edges.len + back_edges.items.len + 1;
    while (restarts <= max_restarts) : (restarts += 1) {
        // One gap after every layer; the last one exists only for the down
        // halves of back edges that leave the last layer, and is 0 wide
        // otherwise.
        const gaps = try arena.alloc(Gap, num_layers);
        var need_spacer: ?u32 = null;
        var k: u32 = 0;
        while (k < num_layers) : (k += 1) {
            var nets: std.ArrayList(Net) = .{};
            try nets.appendSlice(arena, try extractNets(arena, graph, layered, coords.*, k));
            try appendReturnLaneNets(arena, graph, layered, coords.*, back_edges.items, k, &nets);
            const items = try nets.toOwnedSlice(arena);
            switch (try planGap(arena, items)) {
                .tracks => |t| gaps[k] = .{ .after_layer = k, .nets = items, .tracks = t, .width = if (k + 1 < num_layers or items.len > 0) gapWidth(t) else 0 },
                .spacer => |row| {
                    need_spacer = row;
                    break;
                },
                .unroutable => |ni| {
                    // Counted, and left without a track: `emit` routes it
                    // as a plain L and the invariants show the damage.
                    items[ni].fallback = true;
                    fallbacks += 1;
                    const t = switch (try tryAssignTracksIgnoring(arena, items, ni)) {
                        .tracks => |t| t,
                        .cycle => return error.UnroutableGap,
                    };
                    gaps[k] = .{ .after_layer = k, .nets = items, .tracks = t, .width = gapWidth(t) };
                },
            }
        }
        if (need_spacer) |row| {
            coords_stage.insertSpacerRow(coords, row);
            try spacer_rows.append(arena, row);
            continue;
        }
        coords_stage.reserveReturnRows(coords, @intCast(back_edges.items.len));
        return .{
            .gaps = gaps,
            .return_rows = @intCast(back_edges.items.len),
            .spacer_rows = try spacer_rows.toOwnedSlice(arena),
            .fallbacks = fallbacks,
        };
    }
    return error.SpacerLoopExceeded;
}

/// `tryAssignTracks` with one net treated as straight (it takes no track).
fn tryAssignTracksIgnoring(arena: std.mem.Allocator, nets: []Net, skip: u32) !TrackResult {
    const was = nets[skip].straight;
    nets[skip].straight = true;
    defer nets[skip].straight = was;
    return tryAssignTracks(arena, nets);
}

/// The two halves of every back edge that touch gap `k`: the down half in
/// the gap after the source's layer, the up half in the gap before the
/// sink's layer. Return row `i` is `coords.height + i` (before the rows are
/// reserved, which `plan` does once all gaps are settled).
fn appendReturnLaneNets(
    arena: std.mem.Allocator,
    graph: VirtualGraph,
    layered: LayeredGraph,
    coords: Coords,
    back_edges: []const u32,
    k: u32,
    nets: *std.ArrayList(Net),
) !void {
    for (back_edges, 0..) |oi, i| {
        const o = layered.originals[oi];
        const src_node: u32 = @intCast(o.src);
        const dst_node: u32 = @intCast(o.dst);
        const l_src = layered.nodes[src_node].layer;
        const l_dst = layered.nodes[dst_node].layer;
        if (l_dst == 0) return error.BackEdgeIntoLayerZero;
        const return_row = coords.height + @as(u32, @intCast(i));
        const src_row = outputRow(graph, layered, coords, src_node);
        const dst_row = inputRow(graph, layered, coords, dst_node, o.dst_port) orelse continue;
        if (l_src == k) {
            const sinks = try arena.alloc(Terminal, 1);
            sinks[0] = .{ .node = dst_node, .port = o.dst_port, .row = return_row, .rail = .none };
            try nets.append(arena, .{
                .src_real = o.src,
                .src_port = o.src_port,
                .src = .{ .node = src_node, .port = o.src_port, .row = src_row, .rail = .left },
                .sinks = sinks,
                .lo = @min(src_row, return_row),
                .hi = @max(src_row, return_row),
                .straight = false,
                .pieces = &.{},
                .jogs = &.{},
                .back = true,
                .fallback = false,
            });
        }
        if (l_dst - 1 == k) {
            const sinks = try arena.alloc(Terminal, 1);
            sinks[0] = .{ .node = dst_node, .port = o.dst_port, .row = dst_row, .rail = .right };
            try nets.append(arena, .{
                .src_real = o.src,
                .src_port = o.src_port,
                .src = .{ .node = src_node, .port = o.src_port, .row = return_row, .rail = .none },
                .sinks = sinks,
                .lo = @min(dst_row, return_row),
                .hi = @max(dst_row, return_row),
                .straight = false,
                .pieces = &.{},
                .jogs = &.{},
                .back = true,
                .fallback = false,
            });
        }
    }
}

/// The per-gap widths for the coordinate stage's second pass.
pub fn widths(arena: std.mem.Allocator, p: RoutePlan, num_layers: u32) !ChannelWidths {
    const after = try arena.alloc(u32, num_layers);
    @memset(after, 0);
    for (p.gaps) |g| after[g.after_layer] = g.width;
    return .{ .after = after };
}

// ---------- Emission ----------

pub const RouteResult = struct {
    wires: []const layout.RoutedWire,
    width: u32,
    height: u32,
};

const Segment = layout.Segment;
const PortCoord = layout.PortCoord;

fn seg(x0: u32, y0: u32, x1: u32, y1: u32) Segment {
    return .{ .from = .{ .x = x0, .y = y0 }, .to = .{ .x = x1, .y = y1 } };
}

/// The x of track `t` in gap `k` under the second-pass coordinates.
fn trackX(coords: Coords, k: u32, t: u32) u32 {
    return coords.channel_x[k] + 1 + t;
}

/// The sink marker column of gap `k`: the cell before layer `k + 1`.
fn sinkX(coords: Coords, k: u32) u32 {
    return coords.layer_x[k + 1] - 1;
}

/// Source port cell x of a node in layer `k` (a dummy: the gap's first cell).
fn sourceX(layered: LayeredGraph, coords: Coords, ni: u32, k: u32) u32 {
    if (layered.nodes[ni].real != null) return coords.x[ni] + coords.w[ni];
    return coords.channel_x[k];
}

fn findNet(gap: Gap, src_node: u32, src_real: usize, src_port: u8, want_back: bool, rail_left: bool) ?*Net {
    for (gap.nets) |*net| {
        if (net.back != want_back) continue;
        if (net.src_real != src_real or net.src_port != src_port) continue;
        if (!want_back and net.src.node != src_node) continue;
        if (want_back and (net.src.rail == .left) != rail_left) continue;
        return net;
    }
    return null;
}

fn pieceContaining(net: *const Net, row: u32) ?usize {
    for (net.pieces, 0..) |pc, i| {
        if (pc.lo <= row and row <= pc.hi) return i;
    }
    return null;
}

/// Append the vertical run of `net` from `from_row` to `to_row` through its
/// pieces and jogs, in gap `k`; returns the x it ends on.
fn appendVertical(arena: std.mem.Allocator, out: *std.ArrayList(Segment), net: *const Net, coords: Coords, k: u32, from_row: u32, to_row: u32, start_x: u32) !u32 {
    var pi = pieceContaining(net, from_row) orelse return error.RowOutsideNet;
    const target = pieceContaining(net, to_row) orelse return error.RowOutsideNet;
    // A row on a jog belongs to two pieces; take the one on the way.
    if (net.pieces.len > 1 and pi > target and net.pieces[pi].lo == from_row) pi -= 1;
    var x = start_x;
    var row = from_row;
    if (trackX(coords, k, net.pieces[pi].track) != x) {
        try out.append(arena, seg(x, row, trackX(coords, k, net.pieces[pi].track), row));
        x = trackX(coords, k, net.pieces[pi].track);
    }
    while (pi != target) {
        const step_down = target > pi;
        const next = if (step_down) pi + 1 else pi - 1;
        const jog = net.jogs[if (step_down) pi else next];
        if (jog.row != row) try out.append(arena, seg(x, row, x, jog.row));
        row = jog.row;
        const nx = trackX(coords, k, net.pieces[next].track);
        if (nx != x) try out.append(arena, seg(x, row, nx, row));
        x = nx;
        pi = next;
    }
    if (to_row != row) try out.append(arena, seg(x, row, x, to_row));
    return x;
}

/// Merge consecutive collinear segments and drop zero-length ones.
fn mergeSegments(arena: std.mem.Allocator, segs: []const Segment) ![]Segment {
    var out: std.ArrayList(Segment) = .{};
    for (segs) |s| {
        if (s.from.x == s.to.x and s.from.y == s.to.y) continue;
        if (out.items.len > 0) {
            const last = &out.items[out.items.len - 1];
            const last_h = last.from.y == last.to.y;
            const s_h = s.from.y == s.to.y;
            if (last_h == s_h and last.to.x == s.from.x and last.to.y == s.from.y) {
                last.to = s.to;
                continue;
            }
        }
        try out.append(arena, s);
    }
    return out.toOwnedSlice(arena);
}

pub fn emit(arena: std.mem.Allocator, graph: VirtualGraph, layered: LayeredGraph, coords: Coords, p: RoutePlan) !RouteResult {
    var wires: std.ArrayList(layout.RoutedWire) = .{};
    var back_index: u32 = 0;

    for (layered.originals, 0..) |o, oi| {
        var segs: std.ArrayList(Segment) = .{};
        const src_node: u32 = @intCast(o.src);
        const dst_node: u32 = @intCast(o.dst);
        if (o.back) {
            const j = layered.nodes[src_node].layer;
            const i = layered.nodes[dst_node].layer;
            const return_row = coords.height - p.return_rows + back_index;
            back_index += 1;
            const down = findNet(p.gaps[j], src_node, o.src, o.src_port, true, true) orelse return error.MissingNet;
            const up = findNet(p.gaps[i - 1], src_node, o.src, o.src_port, true, false) orelse return error.MissingNet;
            // Several back edges from one source share the down halves'
            // identity; pick the halves whose return row is this edge's.
            const d = pickHalf(p.gaps[j], o, true, return_row) orelse down;
            const u = pickHalf(p.gaps[i - 1], o, false, return_row) orelse up;
            const src_row = d.src.row;
            const dst_row = u.sinks[0].row;
            const x_s = sourceX(layered, coords, src_node, j);
            const t1 = trackX(coords, j, d.pieces[0].track);
            const t2 = trackX(coords, i - 1, u.pieces[0].track);
            try segs.append(arena, seg(x_s, src_row, t1, src_row));
            try segs.append(arena, seg(t1, src_row, t1, return_row));
            try segs.append(arena, seg(t1, return_row, t2, return_row));
            try segs.append(arena, seg(t2, return_row, t2, dst_row));
            try segs.append(arena, seg(t2, dst_row, sinkX(coords, i - 1), dst_row));
        } else {
            // Walk the chain of layer-adjacent edges of this original.
            var cur: u32 = src_node;
            var k = layered.nodes[src_node].layer;
            while (true) {
                var edge: ?types.LayerEdge = null;
                for (layered.edges) |e| {
                    if (e.original == oi and e.src == cur) {
                        edge = e;
                        break;
                    }
                }
                const e = edge orelse break;
                const net = findNet(p.gaps[k], cur, o.src, o.src_port, false, true) orelse return error.MissingNet;
                const src_row = net.src.row;
                var dst_row: u32 = 0;
                for (net.sinks) |t| {
                    if (t.node == e.dst and t.port == e.dst_port) dst_row = t.row;
                }
                const x_s = sourceX(layered, coords, cur, k);
                const x_d = sinkX(coords, k);
                if (net.straight or net.fallback) {
                    if (src_row == dst_row) {
                        try segs.append(arena, seg(x_s, src_row, x_d, dst_row));
                    } else {
                        // Fallback L on the first track column.
                        const tx = trackX(coords, k, 0);
                        try segs.append(arena, seg(x_s, src_row, tx, src_row));
                        try segs.append(arena, seg(tx, src_row, tx, dst_row));
                        try segs.append(arena, seg(tx, dst_row, x_d, dst_row));
                    }
                } else {
                    const x_end = try appendVertical(arena, &segs, net, coords, k, src_row, dst_row, x_s);
                    try segs.append(arena, seg(x_end, dst_row, x_d, dst_row));
                }
                cur = e.dst;
                k += 1;
                if (layered.nodes[cur].real != null) break;
                // Across the dummy's layer column to the next gap's first cell.
                try segs.append(arena, seg(x_d, dst_row, coords.channel_x[k], dst_row));
            }
        }
        const merged = try mergeSegments(arena, segs.items);
        try wires.append(arena, .{
            .src_id = graph.nodes[o.src].id,
            .src_port = o.src_port,
            .dst_id = graph.nodes[o.dst].id,
            .dst_port = o.dst_port,
            .segments = merged,
            .crossings = &.{},
        });
    }

    const wire_slice = try wires.toOwnedSlice(arena);
    try computeCrossings(arena, wire_slice);

    var width = coords.width;
    var height = coords.height;
    for (wire_slice) |w| {
        for (w.segments) |s| {
            if (s.from.x + 1 > width) width = s.from.x + 1;
            if (s.to.x + 1 > width) width = s.to.x + 1;
            if (s.from.y + 1 > height) height = s.from.y + 1;
            if (s.to.y + 1 > height) height = s.to.y + 1;
        }
    }
    return .{ .wires = wire_slice, .width = width, .height = height };
}

/// The return-lane half of `o` whose return row is `row` (several back
/// edges from one source have halves that share every other field).
fn pickHalf(gap: Gap, o: types.OriginalEdge, down: bool, row: u32) ?*Net {
    for (gap.nets) |*net| {
        if (!net.back) continue;
        if (net.src_real != o.src or net.src_port != o.src_port) continue;
        if (down and net.src.rail == .left and net.sinks[0].row == row and net.sinks[0].node == o.dst and net.sinks[0].port == o.dst_port) return net;
        if (!down and net.src.rail == .none and net.src.row == row and net.sinks[0].node == o.dst and net.sinks[0].port == o.dst_port) return net;
    }
    return null;
}

/// `crossings`: every cell two wires of different nets both cover (render
/// draws `┼`), and every cell of one net where one wire corners or ends
/// while another passes straight through (a fan-out tap, render's `●`).
fn computeCrossings(arena: std.mem.Allocator, wires: []layout.RoutedWire) !void {
    const Cell = struct { x: u32, y: u32 };
    const Claim = struct { wire: u32, net_src: u32, net_port: u8, through: bool };
    var claims = std.AutoHashMap(Cell, std.ArrayList(Claim)).init(arena);
    for (wires, 0..) |w, wi| {
        for (w.segments, 0..) |s, si| {
            const horizontal = s.from.y == s.to.y;
            const lo = if (horizontal) @min(s.from.x, s.to.x) else @min(s.from.y, s.to.y);
            const hi = if (horizontal) @max(s.from.x, s.to.x) else @max(s.from.y, s.to.y);
            var i = lo;
            while (i <= hi) : (i += 1) {
                const cell = if (horizontal) Cell{ .x = i, .y = s.from.y } else Cell{ .x = s.from.x, .y = i };
                const at_from = cell.x == s.from.x and cell.y == s.from.y;
                const at_to = cell.x == s.to.x and cell.y == s.to.y;
                // Endpoints are corners (or the wire's ends); segments are
                // merged, so an endpoint is never a collinear join.
                const through = !(at_from or at_to);
                _ = si;
                const entry = try claims.getOrPut(cell);
                if (!entry.found_existing) entry.value_ptr.* = .{};
                try entry.value_ptr.append(arena, .{ .wire = @intCast(wi), .net_src = w.src_id, .net_port = w.src_port, .through = through });
            }
        }
    }
    var lists = try arena.alloc(std.ArrayList(PortCoord), wires.len);
    for (0..wires.len) |i| lists[i] = .{};
    // Deterministic order: sort the cells.
    var cells: std.ArrayList(Cell) = .{};
    var it = claims.keyIterator();
    while (it.next()) |c| try cells.append(arena, c.*);
    std.mem.sort(Cell, cells.items, {}, struct {
        fn lt(_: void, a: Cell, b: Cell) bool {
            if (a.y != b.y) return a.y < b.y;
            return a.x < b.x;
        }
    }.lt);
    for (cells.items) |cell| {
        const list = claims.get(cell).?.items;
        if (list.len < 2) continue;
        var same_net = true;
        var any_through = false;
        var any_corner = false;
        for (list) |c| {
            if (c.net_src != list[0].net_src or c.net_port != list[0].net_port) same_net = false;
            if (c.through) any_through = true else any_corner = true;
        }
        const mark = if (same_net) (any_through and any_corner) else true;
        if (!mark) continue;
        for (list) |c| {
            var dup = false;
            for (lists[c.wire].items) |pc| if (pc.x == cell.x and pc.y == cell.y) {
                dup = true;
            };
            if (!dup) try lists[c.wire].append(arena, .{ .x = cell.x, .y = cell.y });
        }
    }
    for (wires, 0..) |*w, i| w.crossings = lists[i].items;
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

test "channels: a two-net constraint cycle is broken by one dogleg on a free row" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const nets = try a.alloc(Net, 2);
    nets[0] = try mkTestNet(a, 0, 1, &.{5});
    nets[1] = try mkTestNet(a, 1, 5, &.{1});
    const outcome = try planGap(a, nets);
    try std.testing.expectEqual(@as(u32, 3), outcome.tracks);
    // The widest stuck unit is the first net; it is split at row 3.
    try std.testing.expectEqual(@as(usize, 2), nets[0].pieces.len);
    try std.testing.expectEqual(@as(usize, 1), nets[0].jogs.len);
    try std.testing.expectEqual(@as(u32, 3), nets[0].jogs[0].row);
    try std.testing.expectEqual(nets[0].pieces[0].track, nets[0].jogs[0].from_track);
    try std.testing.expectEqual(nets[0].pieces[1].track, nets[0].jogs[0].to_track);
    // A1 (row-1 source) left of B, B left of A2 (row-5 sink).
    try std.testing.expect(nets[0].pieces[0].track < nets[1].pieces[0].track);
    try std.testing.expect(nets[1].pieces[0].track < nets[0].pieces[1].track);
}

test "channels: with no free row a spacer row is requested" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A: 1 → 3 and B: 3 → 1 cycle; C's source sits on row 2, the only row between.
    const nets = try a.alloc(Net, 3);
    nets[0] = try mkTestNet(a, 0, 1, &.{3});
    nets[1] = try mkTestNet(a, 1, 3, &.{1});
    nets[2] = try mkTestNet(a, 2, 2, &.{7});
    const outcome = try planGap(a, nets);
    try std.testing.expectEqual(@as(u32, 3), outcome.spacer);
}

test "channels: a back edge gets two tracks and a return row below the diagram" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // not_a ↔ not_b: not_a at layer 1 (bumped), not_b at layer 2; the back
    // edge not_b → not_a leaves the last layer (trailing gap 2) and returns
    // through gap 0.
    const nodes = try a.alloc(VirtualNode, 2);
    nodes[0] = try mk(a, 0, .{ .primitive = .not_gate }, &.{.{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{.{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN }});
    nodes[1] = try mk(a, 1, .{ .primitive = .not_gate }, &.{.{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }}, &.{.{ .dst_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN }});
    var b = try build(a, nodes);
    const height_before = b.coords.height;
    const p = try plan(a, b.graph, b.layered, &b.coords);
    try std.testing.expectEqual(@as(u32, 1), p.return_rows);
    try std.testing.expectEqual(height_before + 1, b.coords.height);
    try std.testing.expectEqual(@as(usize, 3), p.gaps.len);
    // Down half in the trailing gap, up half in gap 0, forward net in gap 1.
    try std.testing.expectEqual(@as(usize, 1), p.gaps[2].nets.len);
    try std.testing.expect(p.gaps[2].nets[0].back);
    try std.testing.expectEqual(height_before, p.gaps[2].nets[0].hi);
    try std.testing.expectEqual(@as(u32, 5), p.gaps[2].width);
    try std.testing.expectEqual(@as(usize, 1), p.gaps[0].nets.len);
    try std.testing.expect(p.gaps[0].nets[0].back);
    try std.testing.expectEqual(@as(usize, 1), p.gaps[1].nets.len);
    try std.testing.expect(!p.gaps[1].nets[0].back);
    try std.testing.expect(p.gaps[1].nets[0].straight);
    // Emit and check the lane's shape: five legs, ending rightwards into not_a.
    coords_stage.relayoutColumns(&b.coords, b.layered, try widths(a, p, b.layered.num_layers));
    const r = try emit(a, b.graph, b.layered, b.coords, p);
    try std.testing.expectEqual(@as(usize, 2), r.wires.len);
    const lane = r.wires[1];
    try std.testing.expectEqual(@as(u32, 1), lane.src_id);
    try std.testing.expectEqual(@as(usize, 5), lane.segments.len);
    try std.testing.expectEqual(height_before, lane.segments[2].from.y); // the return row
    try std.testing.expect(lane.segments[4].to.x > lane.segments[4].from.x);
    try std.testing.expectEqual(height_before + 1, r.height);
}

fn mkTestNet(al: std.mem.Allocator, id: usize, src_row: u32, sink_rows: []const u32) !Net {
    const sinks = try al.alloc(Terminal, sink_rows.len);
    var lo = src_row;
    var hi = src_row;
    for (sink_rows, 0..) |r, i| {
        sinks[i] = .{ .node = 100 + @as(u32, @intCast(i)), .port = 0, .row = r, .rail = .right };
        if (r < lo) lo = r;
        if (r > hi) hi = r;
    }
    return .{ .src_real = id, .src_port = 3, .src = .{ .node = @intCast(id), .port = 3, .row = src_row, .rail = .left }, .sinks = sinks, .lo = lo, .hi = hi, .straight = false, .pieces = &.{}, .jogs = &.{}, .back = false, .fallback = false };
}
