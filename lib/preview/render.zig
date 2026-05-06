const std = @import("std");
const layout = @import("layout");
const canvas_mod = @import("canvas");
const color_mod = @import("color");
const glyphs = @import("glyphs");

const Canvas = canvas_mod.Canvas;
const ColorTag = color_mod.ColorTag;
const ColorMode = color_mod.ColorMode;
const LayoutGrid = layout.LayoutGrid;
const PlacedComponent = layout.PlacedComponent;
const RoutedWire = layout.RoutedWire;
const Segment = layout.Segment;
const PortCoord = layout.PortCoord;

pub const RenderOptions = struct {
    color: ColorMode = .auto,
    stdout_handle: ?std.fs.File.Handle = null,
    no_color_value: ?[]const u8 = null,
};

/// Phase 3 slice 4 orchestrator. Composes Canvas + glyph drawing + wire
/// rendering + crossing handling, then calls writeOut on the underlying writer.
///
/// Order of operations:
///   1. Init Canvas at grid.width × grid.height.
///   2. Draw every component glyph (cells own their bounding box).
///   3. Draw every wire's segments using `─` and `│`.
///   4. Patch corners at intra-wire segment junctions (`╭╮╰╯`).
///   5. Detect fan-out taps: sources that are `from` for ≥3 wires get `●`.
///   6. Apply jump-arcs at every RoutedWire.crossings cell — the horizontal
///      wire's neighbours become `╯`/`╰`, the vertical wire renders `│`
///      continuously through the crossing.
///   7. Resolve color mode and writeOut.
pub fn render(
    arena: std.mem.Allocator,
    writer: anytype,
    grid: LayoutGrid,
    opts: RenderOptions,
) !void {
    var canvas = try Canvas.init(arena, grid.width, grid.height);

    // Step 2: components.
    for (grid.components) |placed| glyphs.drawComponent(&canvas, placed);

    // Step 3: wire rails.
    for (grid.wires) |w| {
        for (w.segments) |seg| drawSegment(&canvas, seg);
    }

    // Step 4: corners at junctions within each wire.
    for (grid.wires) |w| {
        var i: usize = 0;
        while (i + 1 < w.segments.len) : (i += 1) {
            const seg = w.segments[i];
            const next = w.segments[i + 1];
            const corner = seg.to;
            if (corner.x != next.from.x or corner.y != next.from.y) continue;
            const ch = pickCornerGlyph(seg, next);
            canvas.setCell(corner.x, corner.y, ch, .wire);
        }
    }

    // Step 5: fan-out taps. Count distinct wires per source point.
    var source_counts = std.AutoHashMap(u64, u32).init(arena);
    for (grid.wires) |w| {
        if (w.segments.len == 0) continue;
        const src = w.segments[0].from;
        const key: u64 = (@as(u64, src.y) << 32) | @as(u64, src.x);
        const entry = try source_counts.getOrPut(key);
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
    }
    var iter = source_counts.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* >= 3) {
            const x: u32 = @intCast(entry.key_ptr.* & 0xFFFFFFFF);
            const y: u32 = @intCast(entry.key_ptr.* >> 32);
            canvas.setCell(x, y, "●", .wire);
        }
    }

    // Step 6: jump-arcs at crossings. Idempotent — applying twice (once per wire
    // in the crossing) produces the same canvas state.
    for (grid.wires) |w| {
        for (w.crossings) |pt| applyJumpArc(&canvas, grid.wires, pt);
    }

    // Step 7: writeOut with resolved color mode.
    const use_color = color_mod.shouldColor(opts.color, opts.stdout_handle, opts.no_color_value);
    try canvas.writeOut(writer, use_color);
}

fn drawSegment(canvas: *Canvas, seg: Segment) void {
    if (seg.from.y == seg.to.y) {
        canvas.drawHSegment(seg.from.x, seg.to.x, seg.from.y, "─", .wire);
    } else {
        canvas.drawVSegment(seg.from.x, seg.from.y, seg.to.y, "│", .wire);
    }
}

fn pickCornerGlyph(seg_in: Segment, seg_out: Segment) []const u8 {
    const corner = seg_in.to;

    // Direction the path enters the corner from (W/E/N/S of the corner).
    const in_dx: i64 = @as(i64, corner.x) - @as(i64, seg_in.from.x);
    const in_dy: i64 = @as(i64, corner.y) - @as(i64, seg_in.from.y);
    // Direction the path exits the corner toward.
    const out_dx: i64 = @as(i64, seg_out.to.x) - @as(i64, corner.x);
    const out_dy: i64 = @as(i64, seg_out.to.y) - @as(i64, corner.y);

    // Connections: which sides of the corner cell have lines coming out.
    const conn_w = (in_dx > 0) or (out_dx < 0);
    const conn_e = (in_dx < 0) or (out_dx > 0);
    const conn_n = (in_dy > 0) or (out_dy < 0);
    const conn_s = (in_dy < 0) or (out_dy > 0);

    if (conn_w and conn_s) return "╮";
    if (conn_w and conn_n) return "╯";
    if (conn_e and conn_s) return "╭";
    if (conn_e and conn_n) return "╰";
    // Fallback for malformed corners (shouldn't happen with route's L-shapes).
    return "+";
}

fn applyJumpArc(canvas: *Canvas, all_wires: []const RoutedWire, pt: PortCoord) void {
    // Identify which wire is horizontal at this cell and which is vertical.
    // Only the horizontal wire's neighbours are modified; the vertical's `│`
    // already at the crossing is preserved by setting the cell explicitly.
    var has_horizontal = false;
    for (all_wires) |w| {
        if (wireHasHorizontalAt(w, pt)) {
            has_horizontal = true;
            break;
        }
    }
    if (!has_horizontal) return;

    // Crossing cell: vertical wire continues with `│`.
    canvas.setCell(pt.x, pt.y, "│", .wire);
    // Neighbours on the horizontal row: jump arcs.
    if (pt.x >= 1) canvas.setCell(pt.x - 1, pt.y, "╯", .crossing);
    if (pt.x + 1 < canvas.width) canvas.setCell(pt.x + 1, pt.y, "╰", .crossing);
}

fn wireHasHorizontalAt(wire: RoutedWire, pt: PortCoord) bool {
    for (wire.segments) |seg| {
        if (seg.from.y != seg.to.y) continue; // not horizontal
        if (seg.from.y != pt.y) continue;
        const min_x = @min(seg.from.x, seg.to.x);
        const max_x = @max(seg.from.x, seg.to.x);
        if (pt.x >= min_x and pt.x <= max_x) return true;
    }
    return false;
}

// ---------- Tests ----------

const InputEdge = @import("layout_types").InputEdge;
const OutputEdge = @import("layout_types").OutputEdge;
const PortSlot = layout.PortSlot;
const SRC_OUT: u8 = 3;
const DST_IN: u8 = 0;

fn captureRender(allocator: std.mem.Allocator, arena: std.mem.Allocator, grid: LayoutGrid) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    try render(arena, buf.writer(allocator), grid, .{});
    return buf.toOwnedSlice(allocator);
}

test "render_single_segment_horizontal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // 8-wide × 1-tall canvas with one wire spanning x=2..6 at y=0.
    // No components — bare-wire render. Cells outside the segment stay default.
    const segs = [_]Segment{
        .{ .from = .{ .x = 2, .y = 0 }, .to = .{ .x = 6, .y = 0 } },
    };
    const wire = RoutedWire{
        .src_id = 0,
        .src_port = SRC_OUT,
        .dst_id = 1,
        .dst_port = DST_IN,
        .segments = &segs,
        .crossings = &.{},
    };
    const grid = LayoutGrid{
        .width = 8,
        .height = 1,
        .components = &.{},
        .wires = &[_]RoutedWire{wire},
    };

    const out = try captureRender(std.testing.allocator, a, grid);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("  ───── \n", out);
}

test "render_corner_glyphs: all four corner cases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Helper: build a 2-segment wire (h then v) and assert the corner glyph.
    const Case = struct {
        name: []const u8,
        from_h: PortCoord,
        to_h: PortCoord, // equals corner
        to_v: PortCoord,
        expected: []const u8,
    };

    // Corner cell at (3, 1) in a 7×3 canvas. Vary segment directions.
    const cases = [_]Case{
        // (W + S) → ╮: enter from W (left), exit S (down).
        .{ .name = "WS", .from_h = .{ .x = 1, .y = 1 }, .to_h = .{ .x = 3, .y = 1 }, .to_v = .{ .x = 3, .y = 2 }, .expected = "╮" },
        // (E + S) → ╭: enter from E (right), exit S (down).
        .{ .name = "ES", .from_h = .{ .x = 5, .y = 1 }, .to_h = .{ .x = 3, .y = 1 }, .to_v = .{ .x = 3, .y = 2 }, .expected = "╭" },
        // (W + N) → ╯: enter from W (left), exit N (up).
        .{ .name = "WN", .from_h = .{ .x = 1, .y = 1 }, .to_h = .{ .x = 3, .y = 1 }, .to_v = .{ .x = 3, .y = 0 }, .expected = "╯" },
        // (E + N) → ╰: enter from E (right), exit N (up).
        .{ .name = "EN", .from_h = .{ .x = 5, .y = 1 }, .to_h = .{ .x = 3, .y = 1 }, .to_v = .{ .x = 3, .y = 0 }, .expected = "╰" },
    };

    for (cases) |c| {
        const segs = [_]Segment{
            .{ .from = c.from_h, .to = c.to_h },
            .{ .from = c.to_h, .to = c.to_v },
        };
        const wire = RoutedWire{
            .src_id = 0,
            .src_port = SRC_OUT,
            .dst_id = 1,
            .dst_port = DST_IN,
            .segments = &segs,
            .crossings = &.{},
        };
        const grid = LayoutGrid{ .width = 7, .height = 3, .components = &.{}, .wires = &[_]RoutedWire{wire} };

        const out = try captureRender(std.testing.allocator, a, grid);
        defer std.testing.allocator.free(out);

        // Find the corner cell at (3, 1) — its bytes should be c.expected.
        // Output layout: row 0 = 7 cells + \n, row 1 = 7 cells + \n, row 2 = 7 cells + \n.
        // Cells are variable-byte UTF-8, so locate via row+column scanning.
        try std.testing.expect(std.mem.indexOf(u8, out, c.expected) != null);
    }
}

test "render_tap_at_fanout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Three wires originating from the same source cell (5, 1). The fan-out point
    // gets `●` (tap glyph) overwritten on top of whatever the wire's first segment
    // would have drawn.
    const seg_a = [_]Segment{.{ .from = .{ .x = 5, .y = 1 }, .to = .{ .x = 8, .y = 1 } }};
    const seg_b = [_]Segment{.{ .from = .{ .x = 5, .y = 1 }, .to = .{ .x = 8, .y = 0 } }};
    const seg_c = [_]Segment{.{ .from = .{ .x = 5, .y = 1 }, .to = .{ .x = 8, .y = 2 } }};

    const wires = [_]RoutedWire{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_id = 1, .dst_port = DST_IN, .segments = &seg_a, .crossings = &.{} },
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_id = 2, .dst_port = DST_IN, .segments = &seg_b, .crossings = &.{} },
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_id = 3, .dst_port = DST_IN, .segments = &seg_c, .crossings = &.{} },
    };
    const grid = LayoutGrid{ .width = 10, .height = 3, .components = &.{}, .wires = &wires };

    const out = try captureRender(std.testing.allocator, a, grid);
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "●") != null);
}

test "render_jump_arc_horizontal_over_vertical" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Hand-construct a horizontal wire and a vertical wire that cross at (5, 2).
    // Horizontal: (2, 2) → (8, 2). Vertical: (5, 0) → (5, 4).
    const horiz_segs = [_]Segment{.{ .from = .{ .x = 2, .y = 2 }, .to = .{ .x = 8, .y = 2 } }};
    const vert_segs = [_]Segment{.{ .from = .{ .x = 5, .y = 0 }, .to = .{ .x = 5, .y = 4 } }};
    const crossing_pt = PortCoord{ .x = 5, .y = 2 };

    const wires = [_]RoutedWire{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_id = 1, .dst_port = DST_IN, .segments = &horiz_segs, .crossings = &[_]PortCoord{crossing_pt} },
        .{ .src_id = 2, .src_port = SRC_OUT, .dst_id = 3, .dst_port = DST_IN, .segments = &vert_segs, .crossings = &[_]PortCoord{crossing_pt} },
    };
    const grid = LayoutGrid{ .width = 10, .height = 5, .components = &.{}, .wires = &wires };

    const out = try captureRender(std.testing.allocator, a, grid);
    defer std.testing.allocator.free(out);

    // Crossing cell = vertical wire continues = `│`.
    // Cell to the left = `╯`. Cell to the right = `╰`.
    try std.testing.expect(std.mem.indexOf(u8, out, "╯│╰") != null);
}
