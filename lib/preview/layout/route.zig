const std = @import("std");
const full_format = @import("full_format");
const layout = @import("layout");
const types = @import("layout_types");

const VirtualGraph = types.VirtualGraph;
const PlacedComponent = layout.PlacedComponent;
const PortCoord = layout.PortCoord;
const Segment = layout.Segment;
const RoutedWire = layout.RoutedWire;
const PortSlot = layout.PortSlot;

pub const RouteResult = struct {
    wires: []const RoutedWire,
    width: u32,
    height: u32,
};

const PendingWire = struct {
    src_id: u32,
    src_port: u8,
    dst_id: u32,
    dst_port: u8,
    sx: u32,
    sy: u32,
    dx: u32,
    dy: u32,
    track_x: u32 = 0,
    segments: []const Segment = &.{},
};

/// One source's fan-out family. Every wire sharing `(sx, src_id, src_port)`
/// gets routed onto this trunk's `track_x`, so the verticals collapse into a
/// single shared column with branches splitting off via `●` taps.
const Trunk = struct {
    sx: u32,
    sy: u32,
    src_id: u32,
    src_port: u8,
    y_min: u32,
    y_max: u32,
    wires: std.ArrayList(usize),
    track_x: u32,
};

/// One vertical track shared by trunks whose y-ranges chain (touch at one
/// row). Visually a super-trunk reads as a single continuous bus column even
/// though it carries multiple distinct signals (each member's `┼`-marked
/// crossings indicate the touching points).
const SuperTrunk = struct {
    members: std.ArrayList(usize), // indices into the `trunks` list
    y_min: u32,
    y_max: u32,
};

fn isSuperTrunkBilateral(st: SuperTrunk, trunks: []const Trunk) bool {
    var min_sy: u32 = std.math.maxInt(u32);
    var max_sy: u32 = 0;
    for (st.members.items) |ti| {
        const sy = trunks[ti].sy;
        if (sy < min_sy) min_sy = sy;
        if (sy > max_sy) max_sy = sy;
    }
    return st.y_min < min_sy and st.y_max > max_sy;
}

const SRC_OUT: u8 = @intFromEnum(full_format.PortName.out);

/// Stage 5: route every edge in `graph` as a sequence of axis-aligned segments
/// over the cell coordinates baked into `placed`. Allocates a vertical "track"
/// for each wire's middle leg via interval-greedy packing within the channel
/// to the right of the source column.
///
/// Segment shape is the canonical 3-leg L: horizontal from source to track_x,
/// vertical from source y to destination y, horizontal from track_x to
/// destination. When source and destination y are equal (already aligned) the
/// vertical leg has zero length and only one horizontal segment is emitted.
///
/// Crossings are detected pairwise: a wire's vertical segment crosses another
/// wire's horizontal segment when their occupied cells overlap. The crossing
/// point lands on each wire's `crossings` list (a wire can collect multiple).
pub fn route(arena: std.mem.Allocator, graph: VirtualGraph, placed: []const PlacedComponent) !RouteResult {
    // ---------- 1. Build id → placed lookup ----------
    var placed_by_id = std.AutoHashMap(u32, *const PlacedComponent).init(arena);
    for (placed) |*p| try placed_by_id.put(p.id, p);

    // ---------- 2. Pre-compute endpoints for every wire ----------
    var pending: std.ArrayList(PendingWire) = .{};
    for (graph.nodes) |node| {
        const src_p = placed_by_id.get(node.id) orelse continue;
        for (node.outputs) |edge| {
            const dst_p = placed_by_id.get(edge.dst_id) orelse continue;
            const dst_coord = portCoordOf(dst_p.*, edge.dst_port) orelse PortCoord{ .x = dst_p.x, .y = dst_p.y };
            try pending.append(arena, .{
                .src_id = node.id,
                .src_port = SRC_OUT,
                .dst_id = edge.dst_id,
                .dst_port = edge.dst_port,
                .sx = src_p.out_port.x,
                .sy = src_p.out_port.y,
                .dx = dst_coord.x,
                .dy = dst_coord.y,
            });
        }
    }

    // ---------- 3. Group wires into trunks by (sx, src_id, src_port) ----------
    // A *trunk* is the family of fan-out wires sharing one source. They share
    // a single vertical track so the fan-out reads as one branch point with
    // signals diverging up and/or down, rather than as N parallel verticals.
    var trunks: std.ArrayList(Trunk) = .{};
    for (pending.items, 0..) |w, i| {
        const y_min = @min(w.sy, w.dy);
        const y_max = @max(w.sy, w.dy);
        var found: ?usize = null;
        for (trunks.items, 0..) |t, ti| {
            if (t.sx == w.sx and t.src_id == w.src_id and t.src_port == w.src_port) {
                found = ti;
                break;
            }
        }
        if (found) |ti| {
            const t = &trunks.items[ti];
            t.y_min = @min(t.y_min, y_min);
            t.y_max = @max(t.y_max, y_max);
            try t.wires.append(arena, i);
        } else {
            var nt = Trunk{
                .sx = w.sx,
                .sy = w.sy,
                .src_id = w.src_id,
                .src_port = w.src_port,
                .y_min = y_min,
                .y_max = y_max,
                .wires = .{},
                .track_x = 0,
            };
            try nt.wires.append(arena, i);
            try trunks.append(arena, nt);
        }
    }

    // ---------- 4. Build super-trunks and allocate one unique track each ----
    // Within each sx-bucket, trunks whose y-ranges *touch* (one's y_max equals
    // another's y_min) form a chained vertical bus and are merged into one
    // super-trunk. Each super-trunk gets a unique track-x — different signals
    // never share a column. Within a bucket the sort is bilateral first
    // (super-trunks whose combined range straddles all member sources go to
    // the closer track), then by lowest member sy ascending.
    var sx_buckets = std.AutoHashMap(u32, std.ArrayList(usize)).init(arena);
    for (trunks.items, 0..) |t, ti| {
        const entry = try sx_buckets.getOrPut(t.sx);
        if (!entry.found_existing) entry.value_ptr.* = .{};
        try entry.value_ptr.append(arena, ti);
    }

    const ChainSortCtx = struct { trunks: []const Trunk };
    var bucket_iter = sx_buckets.iterator();
    while (bucket_iter.next()) |entry| {
        const trunk_indices = entry.value_ptr.items;

        // Sort trunks by y_min ascending so consecutive scan can detect
        // chains (touching ranges) in one pass.
        std.mem.sort(usize, trunk_indices, ChainSortCtx{ .trunks = trunks.items }, struct {
            fn lt(ctx: ChainSortCtx, a: usize, b: usize) bool {
                const ta = ctx.trunks[a];
                const tb = ctx.trunks[b];
                if (ta.y_min != tb.y_min) return ta.y_min < tb.y_min;
                return a < b;
            }
        }.lt);

        // Build super-trunks: append each trunk to the last super-trunk if
        // ranges are *contiguous* — touching (`prev.y_max == curr.y_min`) or
        // adjacent (`prev.y_max + 1 == curr.y_min`, no rows between). Trunks
        // separated by ≥1 empty row get their own super-trunk so each owns a
        // visually distinct vertical bus.
        var supers: std.ArrayList(SuperTrunk) = .{};
        for (trunk_indices) |ti| {
            const t = trunks.items[ti];
            if (supers.items.len > 0) {
                const last = &supers.items[supers.items.len - 1];
                const contiguous = t.y_min >= last.y_max and t.y_min <= last.y_max + 1;
                if (contiguous) {
                    if (t.y_max > last.y_max) last.y_max = t.y_max;
                    try last.members.append(arena, ti);
                    continue;
                }
            }
            var nst = SuperTrunk{ .members = .{}, .y_min = t.y_min, .y_max = t.y_max };
            try nst.members.append(arena, ti);
            try supers.append(arena, nst);
        }

        // Sort super-trunks: bilateral first, then min-member-sy ascending.
        var super_order: std.ArrayList(usize) = .{};
        for (supers.items, 0..) |_, i| try super_order.append(arena, i);

        const SuperSortCtx = struct {
            supers: []const SuperTrunk,
            trunks: []const Trunk,
        };
        std.mem.sort(usize, super_order.items, SuperSortCtx{ .supers = supers.items, .trunks = trunks.items }, struct {
            fn lt(ctx: SuperSortCtx, a: usize, b: usize) bool {
                const sa = ctx.supers[a];
                const sb = ctx.supers[b];
                const a_bi = isSuperTrunkBilateral(sa, ctx.trunks);
                const b_bi = isSuperTrunkBilateral(sb, ctx.trunks);
                if (a_bi != b_bi) return a_bi;
                // Smaller y-extent first → compact trunks claim the inner
                // tracks closer to the source channel.
                const a_spread = sa.y_max - sa.y_min;
                const b_spread = sb.y_max - sb.y_min;
                if (a_spread != b_spread) return a_spread < b_spread;
                return a < b;
            }
        }.lt);

        // Assign each super-trunk a unique track. Walk east from `sx + 1`,
        // skipping any candidate that would:
        //   - Already be `taken` by an earlier super-trunk in this bucket.
        //   - Fall inside a component's bounding box at any row in the
        //     trunk's y-range (the V leg would overdraw `│NOT│`).
        //   - Land on a port cell or its port-1 neighbour for a port whose
        //     row sits in the trunk's y-range. The port cell itself collides
        //     with the `▶` arrow; the port-1 cell is where the port-bound
        //     wire's last horizontal lives, and a foreign track there
        //     produces a `┼` adjacent to `▶` that reads as two unrelated
        //     wires both terminating at the same port.
        var taken: std.AutoHashMap(u32, void) = .init(arena);
        for (super_order.items) |st_idx| {
            const st = &supers.items[st_idx];
            const sx = trunks.items[st.members.items[0]].sx;
            var candidate: u32 = sx + 1;
            while (taken.contains(candidate) or
                bboxBlocksColumn(placed, candidate, st.y_min, st.y_max) or
                portApproachInRange(placed, candidate, st.y_min, st.y_max))
            {
                candidate += 1;
            }
            try taken.put(candidate, {});
            for (st.members.items) |ti| {
                trunks.items[ti].track_x = candidate;
                for (trunks.items[ti].wires.items) |wi| {
                    pending.items[wi].track_x = candidate;
                }
            }
        }
    }

    // ---------- 4. Generate segments ----------
    // Compute placement bounds so the detour search has a finite ceiling.
    var placement_max_y: u32 = 0;
    for (placed) |p| {
        if (p.y + p.height > placement_max_y) placement_max_y = p.y + p.height;
    }

    for (pending.items) |*w| {
        const tx = w.track_x;
        var segs: std.ArrayList(Segment) = .{};

        // Special-case nearly-direct wire — still split for axis-aligned shape.
        const adjacent_direct = w.sy == w.dy and tx == w.sx + 1 and tx + 1 == w.dx;

        // The natural path is the canonical 3-leg L through the source's
        // allocated track `tx`. It works whenever the wire moves
        // left-to-right AND every leg's cell range stays clear of any
        // component body (excluding the wire's own endpoints).
        const can_use_l_at_tx = w.dx > w.sx and
            !isHSegBlocked(placed, w.sx, tx, w.sy) and
            !isVSegBlocked(placed, tx, w.sy, w.dy) and
            !isHSegBlocked(placed, tx, w.dx, w.dy);

        // Fallback track: the gutter cell immediately west of the
        // destination. When the source bucket has many trunks, `tx` can
        // land at or past `dst.x` (inside the destination's column), which
        // both blocks the natural L *and* would force the detour to
        // backtrack east-then-west on `sy`. Try a 3-leg L through `tx_dst`
        // before reaching for the 5-leg path. This sacrifices same-source
        // trunk coalescing for *this* wire, which is the right trade when
        // the trunk's column can't reach the destination cleanly anyway.
        const tx_dst: u32 = if (w.dx >= 1) w.dx - 1 else w.dx;
        const can_use_l_at_tx_dst = w.dx > w.sx and tx_dst != tx and tx_dst > w.sx and
            !isHSegBlocked(placed, w.sx, tx_dst, w.sy) and
            !isVSegBlocked(placed, tx_dst, w.sy, w.dy) and
            !isHSegBlocked(placed, tx_dst, w.dx, w.dy);

        if (adjacent_direct) {
            try segs.append(arena, .{
                .from = .{ .x = w.sx, .y = w.sy },
                .to = .{ .x = w.dx, .y = w.dy },
            });
        } else if (can_use_l_at_tx) {
            // Three-leg L: horizontal source → track_x, vertical track_x at sy → dy,
            // horizontal track_x → destination.
            try segs.append(arena, .{
                .from = .{ .x = w.sx, .y = w.sy },
                .to = .{ .x = tx, .y = w.sy },
            });
            if (w.sy != w.dy) {
                try segs.append(arena, .{
                    .from = .{ .x = tx, .y = w.sy },
                    .to = .{ .x = tx, .y = w.dy },
                });
            }
            try segs.append(arena, .{
                .from = .{ .x = tx, .y = w.dy },
                .to = .{ .x = w.dx, .y = w.dy },
            });
        } else if (can_use_l_at_tx_dst) {
            // Three-leg L through `tx_dst` — used when the source's
            // bucket-allocated track is unreachable.
            try segs.append(arena, .{
                .from = .{ .x = w.sx, .y = w.sy },
                .to = .{ .x = tx_dst, .y = w.sy },
            });
            if (w.sy != w.dy) {
                try segs.append(arena, .{
                    .from = .{ .x = tx_dst, .y = w.sy },
                    .to = .{ .x = tx_dst, .y = w.dy },
                });
            }
            try segs.append(arena, .{
                .from = .{ .x = tx_dst, .y = w.dy },
                .to = .{ .x = w.dx, .y = w.dy },
            });
        } else {
            // Five-leg detour: source's east gutter → free row → dest's west
            // gutter → dest. `tx_dst` (declared above) sits one cell west of
            // the destination port, in the gutter that owns the dst column's
            // left boundary. For column-0 destinations dx may be 0 (in_port
            // saturated by place.zig's `x -| 1`); in that pathological case
            // there is no west-gutter cell to anchor the detour, so we fall
            // back to the straight 3-leg L and accept the body crossing —
            // the layout is already malformed there.
            const have_room = w.dx >= 1;
            const x_lo = @min(tx, tx_dst);
            const x_hi = @max(tx, tx_dst);

            const free_y_opt = if (have_room)
                findFreeY(placed, x_lo, x_hi, tx, tx_dst, w.sy, w.dy, placement_max_y)
            else
                null;

            if (free_y_opt) |free_y| {
                // (sx, sy) → (tx, sy)
                try segs.append(arena, .{
                    .from = .{ .x = w.sx, .y = w.sy },
                    .to = .{ .x = tx, .y = w.sy },
                });
                // (tx, sy) → (tx, free_y)
                if (free_y != w.sy) {
                    try segs.append(arena, .{
                        .from = .{ .x = tx, .y = w.sy },
                        .to = .{ .x = tx, .y = free_y },
                    });
                }
                // (tx, free_y) → (tx_dst, free_y)
                if (tx != tx_dst) {
                    try segs.append(arena, .{
                        .from = .{ .x = tx, .y = free_y },
                        .to = .{ .x = tx_dst, .y = free_y },
                    });
                }
                // (tx_dst, free_y) → (tx_dst, dy)
                if (free_y != w.dy) {
                    try segs.append(arena, .{
                        .from = .{ .x = tx_dst, .y = free_y },
                        .to = .{ .x = tx_dst, .y = w.dy },
                    });
                }
                // (tx_dst, dy) → (dx, dy)
                if (tx_dst != w.dx) {
                    try segs.append(arena, .{
                        .from = .{ .x = tx_dst, .y = w.dy },
                        .to = .{ .x = w.dx, .y = w.dy },
                    });
                }
            } else {
                // No free row found — fall back to straight 3-leg L.
                try segs.append(arena, .{
                    .from = .{ .x = w.sx, .y = w.sy },
                    .to = .{ .x = tx, .y = w.sy },
                });
                if (w.sy != w.dy) {
                    try segs.append(arena, .{
                        .from = .{ .x = tx, .y = w.sy },
                        .to = .{ .x = tx, .y = w.dy },
                    });
                }
                try segs.append(arena, .{
                    .from = .{ .x = tx, .y = w.dy },
                    .to = .{ .x = w.dx, .y = w.dy },
                });
            }
        }
        w.segments = try segs.toOwnedSlice(arena);
    }

    // ---------- 5. Detect crossings pairwise ----------
    var crossings_per_wire = try arena.alloc(std.ArrayList(PortCoord), pending.items.len);
    for (crossings_per_wire) |*c| c.* = .{};

    for (pending.items, 0..) |a, ai| {
        for (pending.items[ai + 1 ..], ai + 1..) |b, bi| {
            for (a.segments) |seg_a| {
                for (b.segments) |seg_b| {
                    if (segmentCross(seg_a, seg_b)) |pt| {
                        try crossings_per_wire[ai].append(arena, pt);
                        try crossings_per_wire[bi].append(arena, pt);
                    }
                }
            }
        }
    }

    // ---------- 6. Materialize RoutedWire list ----------
    const wires = try arena.alloc(RoutedWire, pending.items.len);
    for (pending.items, 0..) |w, i| {
        wires[i] = .{
            .src_id = w.src_id,
            .src_port = w.src_port,
            .dst_id = w.dst_id,
            .dst_port = w.dst_port,
            .segments = w.segments,
            .crossings = try crossings_per_wire[i].toOwnedSlice(arena),
        };
    }

    // ---------- 7. Compute grid dimensions ----------
    var max_x: u32 = 0;
    var max_y: u32 = 0;
    for (placed) |p| {
        if (p.x + p.width > max_x) max_x = p.x + p.width;
        if (p.y + p.height > max_y) max_y = p.y + p.height;
    }
    for (wires) |w| {
        for (w.segments) |seg| {
            if (seg.from.x + 1 > max_x) max_x = seg.from.x + 1;
            if (seg.to.x + 1 > max_x) max_x = seg.to.x + 1;
            if (seg.from.y + 1 > max_y) max_y = seg.from.y + 1;
            if (seg.to.y + 1 > max_y) max_y = seg.to.y + 1;
        }
    }

    return .{ .wires = wires, .width = max_x, .height = max_y };
}

fn portCoordOf(pc: PlacedComponent, dst_port: u8) ?PortCoord {
    for (pc.in_ports) |slot| {
        if (portByteOf(slot.port_name) == dst_port) return slot.coord;
    }
    return null;
}

fn portByteOf(name: []const u8) u8 {
    if (std.mem.eql(u8, name, "in")) return @intFromEnum(full_format.PortName.in);
    if (std.mem.eql(u8, name, "a")) return @intFromEnum(full_format.PortName.a);
    if (std.mem.eql(u8, name, "b")) return @intFromEnum(full_format.PortName.b);
    if (std.mem.eql(u8, name, "out")) return @intFromEnum(full_format.PortName.out);
    return 0xFF;
}

/// True when any component's bounding box covers column `x` at some row in
/// `[y_min, y_max]`. Used by trunk allocation to keep a vertical track from
/// running through a gate body — the V leg's `│` would overdraw the box label
/// (`│NOT│` etc.).
fn bboxBlocksColumn(placed: []const PlacedComponent, x: u32, y_min: u32, y_max: u32) bool {
    for (placed) |p| {
        if (x < p.x or x >= p.x + p.width) continue;
        const py_top = p.y;
        const py_bot = if (p.height > 0) p.y + p.height - 1 else p.y;
        if (y_min > py_bot) continue;
        if (y_max < py_top) continue;
        return true;
    }
    return false;
}

/// True when column `x` is a port-approach cell (`port.coord.x`) for any
/// in_port whose row sits within `[y_min, y_max]`. Used by trunk allocation
/// to keep vertical tracks off the port cell itself — a track there would
/// collide with the `▶` arrow that step 6 stamps.
fn portApproachInRange(placed: []const PlacedComponent, x: u32, y_min: u32, y_max: u32) bool {
    for (placed) |p| {
        for (p.in_ports) |port| {
            if (port.coord.x != x) continue;
            if (port.coord.y >= y_min and port.coord.y <= y_max) return true;
        }
    }
    return false;
}

/// True when `(x, y)` lies inside any placed component's bounding box. We don't
/// special-case the wire's own src/dst because both endpoints sit ONE cell
/// outside their owning box (the port marker `○` lives east of source's right
/// border, the arrow `▶` west of dest's left border) — so the natural wire
/// path never enters either component's bounding box, and excluding them
/// would let leftward wires think the destination's body is empty.
fn isCellBlocked(
    placed: []const PlacedComponent,
    x: u32,
    y: u32,
) bool {
    for (placed) |p| {
        if (x < p.x or x >= p.x + p.width) continue;
        if (y < p.y or y >= p.y + p.height) continue;
        return true;
    }
    return false;
}

fn isHSegBlocked(
    placed: []const PlacedComponent,
    x_a: u32,
    x_b: u32,
    y: u32,
) bool {
    const lo = @min(x_a, x_b);
    const hi = @max(x_a, x_b);
    var x = lo;
    while (x <= hi) : (x += 1) {
        if (isCellBlocked(placed, x, y)) return true;
    }
    return false;
}

fn isVSegBlocked(
    placed: []const PlacedComponent,
    x: u32,
    y_a: u32,
    y_b: u32,
) bool {
    const lo = @min(y_a, y_b);
    const hi = @max(y_a, y_b);
    var y = lo;
    while (y <= hi) : (y += 1) {
        if (isCellBlocked(placed, x, y)) return true;
    }
    return false;
}

/// Walk outward from `prefer_y` to find a row where the entire 5-leg detour
/// stays clear of every non-endpoint component. We need three legs to pass:
/// the cross-channel horizontal at the candidate row, and the two vertical
/// risers anchoring tx and tx_dst from sy/dy down or up to the candidate.
/// The search prefers rows close to sy so the detour doesn't dive
/// unnecessarily far across the canvas. `bound` is the placement extent —
/// rows beyond it are still allowed (the canvas grows to accommodate the
/// wire), but the search scope is capped at `bound + 16` so we don't loop
/// forever on truly stuck circuits.
fn findFreeY(
    placed: []const PlacedComponent,
    x_lo: u32,
    x_hi: u32,
    tx: u32,
    tx_dst: u32,
    sy: u32,
    dy: u32,
    bound: u32,
) ?u32 {
    const search_limit = bound + 16;
    var radius: u32 = 0;
    while (radius <= search_limit) : (radius += 1) {
        if (radius > 0) {
            const below = sy + radius;
            if (below <= search_limit and detourYIsClear(placed, x_lo, x_hi, tx, tx_dst, sy, dy, below)) {
                return below;
            }
        }
        if (sy >= radius) {
            const above = sy - radius;
            if (detourYIsClear(placed, x_lo, x_hi, tx, tx_dst, sy, dy, above)) {
                return above;
            }
        }
    }
    return null;
}

fn detourYIsClear(
    placed: []const PlacedComponent,
    x_lo: u32,
    x_hi: u32,
    tx: u32,
    tx_dst: u32,
    sy: u32,
    dy: u32,
    candidate: u32,
) bool {
    if (isHSegBlocked(placed, x_lo, x_hi, candidate)) return false;
    if (isVSegBlocked(placed, tx, sy, candidate)) return false;
    if (isVSegBlocked(placed, tx_dst, candidate, dy)) return false;
    return true;
}

fn segmentCross(a: Segment, b: Segment) ?PortCoord {
    const a_horiz = a.from.y == a.to.y;
    const b_horiz = b.from.y == b.to.y;
    if (a_horiz == b_horiz) return null; // parallel; ignore for crossing detection

    const horiz = if (a_horiz) a else b;
    const vert = if (a_horiz) b else a;

    const h_y = horiz.from.y;
    const h_x_min = @min(horiz.from.x, horiz.to.x);
    const h_x_max = @max(horiz.from.x, horiz.to.x);
    const v_x = vert.from.x;
    const v_y_min = @min(vert.from.y, vert.to.y);
    const v_y_max = @max(vert.from.y, vert.to.y);

    // Inclusive bounds: a horizontal rail touching another wire's corner counts
    // as a crossing because the renderer has to choose between drawing the rail's
    // glyph or the corner's glyph at that cell.
    if (v_x < h_x_min or v_x > h_x_max) return null;
    if (h_y < v_y_min or h_y > v_y_max) return null;
    return PortCoord{ .x = v_x, .y = h_y };
}

// ---------- Tests ----------

test "route_segments_are_axis_aligned" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two placed components with one edge between them; check every produced segment
    // is either horizontal or vertical.
    const pin = PlacedComponent{
        .id = 0,
        .kind = .{ .primitive = .input_pin },
        .name = "p",
        .origin = &.{},
        .x = 0,
        .y = 0,
        .width = 6,
        .height = 1,
        .in_ports = &.{},
        .out_port = .{ .x = 5, .y = 0 },
    };
    const led = PlacedComponent{
        .id = 1,
        .kind = .{ .primitive = .led },
        .name = "l",
        .origin = &.{},
        .x = 10,
        .y = 0,
        .width = 3,
        .height = 3,
        .in_ports = &[_]PortSlot{.{ .port_name = "in", .coord = .{ .x = 10, .y = 1 } }},
        .out_port = .{ .x = 12, .y = 1 },
    };
    const placed = [_]PlacedComponent{ pin, led };

    const pin_node = types.VirtualNode{
        .id = 0,
        .kind = .{ .primitive = .input_pin },
        .name = "p",
        .origin = &.{},
        .inputs = &.{},
        .outputs = &[_]types.OutputEdge{
            .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = @intFromEnum(full_format.PortName.in) },
        },
    };
    const led_node = types.VirtualNode{
        .id = 1,
        .kind = .{ .primitive = .led },
        .name = "l",
        .origin = &.{},
        .inputs = &[_]types.InputEdge{
            .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = @intFromEnum(full_format.PortName.in) },
        },
        .outputs = &.{},
    };
    const nodes = [_]types.VirtualNode{ pin_node, led_node };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 2 };

    const result = try route(a, graph, &placed);
    try std.testing.expectEqual(@as(usize, 1), result.wires.len);

    for (result.wires[0].segments) |seg| {
        const horiz = seg.from.y == seg.to.y;
        const vert = seg.from.x == seg.to.x;
        try std.testing.expect(horiz or vert);
    }
}

test "route_two_wires_no_crossing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two pins at the same x but different y; each drives a separate led
    // at different y. Disjoint y-intervals → both wires share track 0.
    const pin0 = PlacedComponent{
        .id = 0,
        .kind = .{ .primitive = .input_pin },
        .name = "p0",
        .origin = &.{},
        .x = 0,
        .y = 0,
        .width = 6,
        .height = 1,
        .in_ports = &.{},
        .out_port = .{ .x = 5, .y = 0 },
    };
    const pin1 = PlacedComponent{
        .id = 1,
        .kind = .{ .primitive = .input_pin },
        .name = "p1",
        .origin = &.{},
        .x = 0,
        .y = 10,
        .width = 6,
        .height = 1,
        .in_ports = &.{},
        .out_port = .{ .x = 5, .y = 10 },
    };
    const led0 = PlacedComponent{
        .id = 2,
        .kind = .{ .primitive = .led },
        .name = "l0",
        .origin = &.{},
        .x = 10,
        .y = 0,
        .width = 3,
        .height = 1,
        .in_ports = &[_]PortSlot{.{ .port_name = "in", .coord = .{ .x = 10, .y = 0 } }},
        .out_port = .{ .x = 12, .y = 0 },
    };
    const led1 = PlacedComponent{
        .id = 3,
        .kind = .{ .primitive = .led },
        .name = "l1",
        .origin = &.{},
        .x = 10,
        .y = 10,
        .width = 3,
        .height = 1,
        .in_ports = &[_]PortSlot{.{ .port_name = "in", .coord = .{ .x = 10, .y = 10 } }},
        .out_port = .{ .x = 12, .y = 10 },
    };
    const placed = [_]PlacedComponent{ pin0, pin1, led0, led1 };

    const nodes = [_]types.VirtualNode{
        .{
            .id = 0,
            .kind = .{ .primitive = .input_pin },
            .name = "p0",
            .origin = &.{},
            .inputs = &.{},
            .outputs = &[_]types.OutputEdge{.{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = @intFromEnum(full_format.PortName.in) }},
        },
        .{
            .id = 1,
            .kind = .{ .primitive = .input_pin },
            .name = "p1",
            .origin = &.{},
            .inputs = &.{},
            .outputs = &[_]types.OutputEdge{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = @intFromEnum(full_format.PortName.in) }},
        },
        .{ .id = 2, .kind = .{ .primitive = .led }, .name = "l0", .origin = &.{}, .inputs = &.{}, .outputs = &.{} },
        .{ .id = 3, .kind = .{ .primitive = .led }, .name = "l1", .origin = &.{}, .inputs = &.{}, .outputs = &.{} },
    };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 4 };

    const result = try route(a, graph, &placed);
    try std.testing.expectEqual(@as(usize, 2), result.wires.len);

    // Each super-trunk gets its own column even when y-ranges are disjoint:
    // pin0's super-trunk lands on track 0 (x=6), pin1's on track 1 (x=7).
    // Lower-sy first by tie-break, so pin0 (sy=0) gets the closer column.
    try std.testing.expectEqual(@as(u32, 6), result.wires[0].segments[0].to.x);
    try std.testing.expectEqual(@as(u32, 7), result.wires[1].segments[0].to.x);

    // No crossings (geometries don't intersect).
    try std.testing.expectEqual(@as(usize, 0), result.wires[0].crossings.len);
    try std.testing.expectEqual(@as(usize, 0), result.wires[1].crossings.len);
}

test "route_two_wires_with_crossing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // pin0 at y=0 drives led1 at y=4; pin1 at y=4 drives led0 at y=0.
    // Both source x=5; y-intervals overlap so they get tracks 0 and 1 (x=6 and x=7).
    // The wires' geometry crosses where one's vertical segment overlaps the other's horizontal.
    const pin0 = PlacedComponent{
        .id = 0,
        .kind = .{ .primitive = .input_pin },
        .name = "p0",
        .origin = &.{},
        .x = 0,
        .y = 0,
        .width = 6,
        .height = 1,
        .in_ports = &.{},
        .out_port = .{ .x = 5, .y = 0 },
    };
    const pin1 = PlacedComponent{
        .id = 1,
        .kind = .{ .primitive = .input_pin },
        .name = "p1",
        .origin = &.{},
        .x = 0,
        .y = 4,
        .width = 6,
        .height = 1,
        .in_ports = &.{},
        .out_port = .{ .x = 5, .y = 4 },
    };
    const led0 = PlacedComponent{
        .id = 2,
        .kind = .{ .primitive = .led },
        .name = "l0",
        .origin = &.{},
        .x = 12,
        .y = 0,
        .width = 3,
        .height = 1,
        .in_ports = &[_]PortSlot{.{ .port_name = "in", .coord = .{ .x = 12, .y = 0 } }},
        .out_port = .{ .x = 14, .y = 0 },
    };
    const led1 = PlacedComponent{
        .id = 3,
        .kind = .{ .primitive = .led },
        .name = "l1",
        .origin = &.{},
        .x = 12,
        .y = 4,
        .width = 3,
        .height = 1,
        .in_ports = &[_]PortSlot{.{ .port_name = "in", .coord = .{ .x = 12, .y = 4 } }},
        .out_port = .{ .x = 14, .y = 4 },
    };
    const placed = [_]PlacedComponent{ pin0, pin1, led0, led1 };

    const nodes = [_]types.VirtualNode{
        .{
            .id = 0,
            .kind = .{ .primitive = .input_pin },
            .name = "p0",
            .origin = &.{},
            .inputs = &.{},
            .outputs = &[_]types.OutputEdge{.{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = @intFromEnum(full_format.PortName.in) }},
        },
        .{
            .id = 1,
            .kind = .{ .primitive = .input_pin },
            .name = "p1",
            .origin = &.{},
            .inputs = &.{},
            .outputs = &[_]types.OutputEdge{.{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = @intFromEnum(full_format.PortName.in) }},
        },
        .{ .id = 2, .kind = .{ .primitive = .led }, .name = "l0", .origin = &.{}, .inputs = &.{}, .outputs = &.{} },
        .{ .id = 3, .kind = .{ .primitive = .led }, .name = "l1", .origin = &.{}, .inputs = &.{}, .outputs = &.{} },
    };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 4 };

    const result = try route(a, graph, &placed);
    try std.testing.expectEqual(@as(usize, 2), result.wires.len);

    // Tracks differ: pin0 → led1 takes x=6, pin1 → led0 takes x=7 (or vice versa).
    const a_track_x = result.wires[0].segments[0].to.x;
    const b_track_x = result.wires[1].segments[0].to.x;
    try std.testing.expect(a_track_x != b_track_x);
    try std.testing.expect(a_track_x == 6 or a_track_x == 7);
    try std.testing.expect(b_track_x == 6 or b_track_x == 7);

    // Both wires have at least one crossing recorded.
    try std.testing.expect(result.wires[0].crossings.len > 0);
    try std.testing.expect(result.wires[1].crossings.len > 0);
}

test "route_detours_around_blocking_component" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Layout mimics the and_of_not bug: a pin at column 0 drives a sink at
    // column 2; a NOT-shaped block sits at column 1 directly on the path's
    // row. Without detour, the wire's horizontal would overdraw the NOT
    // body (`│NOT│`) on row 1.
    const pin = PlacedComponent{
        .id = 0,
        .kind = .{ .primitive = .input_pin },
        .name = "a",
        .origin = &.{},
        .x = 0,
        .y = 0,
        .width = 5,
        .height = 3,
        .in_ports = &.{},
        .out_port = .{ .x = 5, .y = 1 },
    };
    const not_block = PlacedComponent{
        .id = 1,
        .kind = .{ .primitive = .not_gate },
        .name = "n",
        .origin = &.{},
        .x = 10,
        .y = 0,
        .width = 5,
        .height = 3,
        .in_ports = &[_]PortSlot{.{ .port_name = "in", .coord = .{ .x = 9, .y = 1 } }},
        .out_port = .{ .x = 15, .y = 1 },
    };
    const sink = PlacedComponent{
        .id = 2,
        .kind = .{ .primitive = .led },
        .name = "l",
        .origin = &.{},
        .x = 20,
        .y = 0,
        .width = 3,
        .height = 3,
        .in_ports = &[_]PortSlot{.{ .port_name = "in", .coord = .{ .x = 19, .y = 1 } }},
        .out_port = .{ .x = 22, .y = 1 },
    };
    const placed = [_]PlacedComponent{ pin, not_block, sink };

    // pin → sink only — the NOT block is just an obstacle on the path.
    const nodes = [_]types.VirtualNode{
        .{
            .id = 0,
            .kind = .{ .primitive = .input_pin },
            .name = "a",
            .origin = &.{},
            .inputs = &.{},
            .outputs = &[_]types.OutputEdge{
                .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = @intFromEnum(full_format.PortName.in) },
            },
        },
        .{ .id = 1, .kind = .{ .primitive = .not_gate }, .name = "n", .origin = &.{}, .inputs = &.{}, .outputs = &.{} },
        .{ .id = 2, .kind = .{ .primitive = .led }, .name = "l", .origin = &.{}, .inputs = &.{}, .outputs = &.{} },
    };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 3 };

    const result = try route(a, graph, &placed);
    try std.testing.expectEqual(@as(usize, 1), result.wires.len);

    // Detour produces 5 segments (vs 2-3 for the natural L). Walking each
    // segment, no horizontal segment may pass through the NOT block on its
    // body row — that's the bug we're guarding against.
    const wire = result.wires[0];
    try std.testing.expect(wire.segments.len >= 4);
    for (wire.segments) |seg| {
        if (seg.from.y != seg.to.y) continue; // vertical: skip
        const lo = @min(seg.from.x, seg.to.x);
        const hi = @max(seg.from.x, seg.to.x);
        // NOT block occupies x=10..14 on body row y=1. If any horizontal
        // segment overlaps that range AT y=1, the body would be overdrawn.
        if (seg.from.y == 1) {
            try std.testing.expect(hi < 10 or lo > 14);
        }
    }
}

test "route_leftward_wire_uses_5leg_detour" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two NOT gates side-by-side; a feedback wire from gate1.out → gate0.in
    // travels right-to-left. The natural 3-leg L (which assumes dst.x > src.x)
    // would route through both gate bodies; the detour wraps under the row.
    const gate0 = PlacedComponent{
        .id = 0,
        .kind = .{ .primitive = .not_gate },
        .name = "n0",
        .origin = &.{},
        .x = 10,
        .y = 0,
        .width = 5,
        .height = 3,
        .in_ports = &[_]PortSlot{.{ .port_name = "in", .coord = .{ .x = 9, .y = 1 } }},
        .out_port = .{ .x = 15, .y = 1 },
    };
    const gate1 = PlacedComponent{
        .id = 1,
        .kind = .{ .primitive = .not_gate },
        .name = "n1",
        .origin = &.{},
        .x = 20,
        .y = 0,
        .width = 5,
        .height = 3,
        .in_ports = &[_]PortSlot{.{ .port_name = "in", .coord = .{ .x = 19, .y = 1 } }},
        .out_port = .{ .x = 25, .y = 1 },
    };
    const placed = [_]PlacedComponent{ gate0, gate1 };

    // Single edge: gate1.out → gate0.in (leftward).
    const nodes = [_]types.VirtualNode{
        .{ .id = 0, .kind = .{ .primitive = .not_gate }, .name = "n0", .origin = &.{}, .inputs = &.{}, .outputs = &.{} },
        .{
            .id = 1,
            .kind = .{ .primitive = .not_gate },
            .name = "n1",
            .origin = &.{},
            .inputs = &.{},
            .outputs = &[_]types.OutputEdge{
                .{ .dst_id = 0, .src_port = SRC_OUT, .dst_port = @intFromEnum(full_format.PortName.in) },
            },
        },
    };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 2 };

    const result = try route(a, graph, &placed);
    try std.testing.expectEqual(@as(usize, 1), result.wires.len);

    // Leftward path must avoid both gates' body rows. y=1 horizontals would
    // collide with `│NOT│` cells on either gate.
    const wire = result.wires[0];
    for (wire.segments) |seg| {
        if (seg.from.y != seg.to.y) continue;
        const lo = @min(seg.from.x, seg.to.x);
        const hi = @max(seg.from.x, seg.to.x);
        if (seg.from.y == 1) {
            // Allowed to touch the port-adjacent cells (sx=25, dx=9), but no
            // horizontal at y=1 may stray into either gate's body.
            const overlaps_gate0 = !(hi < 10 or lo > 14);
            const overlaps_gate1 = !(hi < 20 or lo > 24);
            try std.testing.expect(!overlaps_gate0);
            try std.testing.expect(!overlaps_gate1);
        }
    }
}
