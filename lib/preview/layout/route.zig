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

    // ---------- 3. Allocate vertical tracks per source-x channel ----------
    // For each source x value, collect wires originating there and assign each
    // an offset (track index) so their vertical legs don't share a column when
    // their y-ranges overlap.
    var sx_buckets = std.AutoHashMap(u32, std.ArrayList(usize)).init(arena);
    for (pending.items, 0..) |w, i| {
        const entry = try sx_buckets.getOrPut(w.sx);
        if (!entry.found_existing) entry.value_ptr.* = .{};
        try entry.value_ptr.append(arena, i);
    }

    var bucket_iter = sx_buckets.iterator();
    while (bucket_iter.next()) |entry| {
        const sx = entry.key_ptr.*;
        const indices = entry.value_ptr.items;
        // Assign tracks: greedy first-fit by ascending wire index (deterministic).
        // tracks[i] holds the y-range [y_min, y_max] of the wire on that track.
        var tracks: std.ArrayList(struct { y_min: u32, y_max: u32 }) = .{};
        for (indices) |wi| {
            const w = &pending.items[wi];
            const y_min = @min(w.sy, w.dy);
            const y_max = @max(w.sy, w.dy);
            // Find first track with no overlap.
            var assigned: ?usize = null;
            for (tracks.items, 0..) |t, ti| {
                if (y_max < t.y_min or y_min > t.y_max) {
                    assigned = ti;
                    break;
                }
            }
            const track_idx = if (assigned) |ti| blk: {
                // Extend track's range.
                const t = &tracks.items[ti];
                t.y_min = @min(t.y_min, y_min);
                t.y_max = @max(t.y_max, y_max);
                break :blk ti;
            } else blk: {
                try tracks.append(arena, .{ .y_min = y_min, .y_max = y_max });
                break :blk tracks.items.len - 1;
            };
            w.track_x = sx + 1 + @as(u32, @intCast(track_idx));
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

    // Both wires use track at x = sx + 1 = 6 (same track index 0 since y-disjoint).
    try std.testing.expectEqual(@as(u32, 6), result.wires[0].segments[0].to.x);
    try std.testing.expectEqual(@as(u32, 6), result.wires[1].segments[0].to.x);

    // No crossings.
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
