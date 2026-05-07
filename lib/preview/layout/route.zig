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

        // Assign each super-trunk a unique track in allocation order.
        for (super_order.items, 0..) |st_idx, alloc_order| {
            const st = &supers.items[st_idx];
            const sx = trunks.items[st.members.items[0]].sx;
            const tx: u32 = sx + 1 + @as(u32, @intCast(alloc_order));
            for (st.members.items) |ti| {
                trunks.items[ti].track_x = tx;
                for (trunks.items[ti].wires.items) |wi| {
                    pending.items[wi].track_x = tx;
                }
            }
        }
    }

    // ---------- 4. Generate segments ----------
    for (pending.items) |*w| {
        const tx = w.track_x;
        var segs: std.ArrayList(Segment) = .{};
        if (w.sy == w.dy and tx == w.sx + 1 and tx + 1 == w.dx) {
            // Special-case nearly-direct wire — still split for axis-aligned shape.
            try segs.append(arena, .{
                .from = .{ .x = w.sx, .y = w.sy },
                .to = .{ .x = w.dx, .y = w.dy },
            });
        } else {
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
