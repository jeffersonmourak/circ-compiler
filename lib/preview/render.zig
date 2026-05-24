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
    /// When --expand-display is set, the orchestrator may have laid out an
    /// LED at width >=8 (above the indicator-mode cap). The render pass
    /// notes those instances by writing one warning line per such LED to
    /// this writer. Pass null in tests that don't care about warnings.
    expand_display: bool = false,
};

/// Render orchestrator. Composes Canvas + glyph drawing + wire rendering +
/// crossing handling + monosketch-style port markers, then calls writeOut.
///
/// Order of operations:
///   1. Init Canvas at grid.width × grid.height.
///   2. Draw every component glyph (labeled box; cells own bounding box).
///   3. Draw every wire's segments using `─` and `│`.
///   4. Patch corners at intra-wire segment junctions (`╭╮╰╯`).
///   5. Resolve crossings: each `.crossings` cell becomes `●` (split — wires
///      share a source — or merge — wires share a destination port) or `┼`
///      (true non-connecting cross between unrelated wires).
///   5b. Junction picker: replace `+` corner-fallbacks and re-evaluate `┼`
///       crossings with the glyph implied by neighbour cells. Runs BEFORE
///       step 6 so the picker sees full wire rails, not port arrows — port
///       arrows are uni-directional and would degrade 3-way junctions
///       adjacent to ports into 2-way corners.
///   6. Port markers: `○` at every wire's source-side cell, directional arrow
///      (`▶◀▲▼`) at the sink-side cell pointing into the destination box.
///   7. Fan-out tap (`●`) overwrites `○` where ≥3 wires share a source.
///   8. Resolve color mode and writeOut.
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

    // Step 5: resolve crossings. Each cell registered in any wire's
    // `.crossings` list falls into one of three buckets:
    //   - *Split* — two wires sharing `src_id` + `src_port` cross at the cell
    //     where one fan-out branch leaves the other's path. Stamp `●`.
    //   - *Merge* — two wires sharing `dst_id` + `dst_port` cross at a fan-in
    //     junction. Stamp `●`.
    //   - *True crossing* — unrelated wires pass over each other. Stamp `┼`
    //     (non-connecting cross, standard schematic convention).
    // Dedupe by point so we process each cell once.
    var crossing_seen = std.AutoHashMap(u64, void).init(arena);
    for (grid.wires, 0..) |w, ai| {
        for (w.crossings) |pt| {
            const key: u64 = (@as(u64, pt.y) << 32) | @as(u64, pt.x);
            const seen = try crossing_seen.getOrPut(key);
            if (seen.found_existing) continue;
            if (isSplitPoint(grid.wires, ai, pt) or isMergePoint(grid.wires, ai, pt)) {
                canvas.setCell(pt.x, pt.y, "●", .wire);
            } else {
                canvas.setCell(pt.x, pt.y, "┼", .crossing);
            }
        }
    }

    // Step 5b: junction picker. Inspect every cell currently holding the `+`
    // fallback (from `pickCornerGlyph` when co-linear segments share a corner)
    // OR a `┼` crossing (from step 5). Replace with the glyph implied by 4
    // cardinal neighbours. Runs BEFORE port markers so the picker sees raw
    // wire rails — `▶◀▲▼` would drop the back-side connection (the arrow
    // doesn't extend toward its wire base), which would degrade legit
    // 3-way junctions adjacent to ports into 2-way corners. The cleaner
    // visual at port-adjacent cells comes from the routing layer
    // (`portApproachInRange` keeps unrelated tracks off the port column),
    // not from glyph rewriting.
    pickJunctionsForFallbacks(&canvas);

    // Step 6: port markers. Replace the wire-overwritten box-border cells at
    // both ends of each wire with monosketch-style affordances: `○` at the
    // source-side cell, and a directional arrow (`▶◀▲▼`) at the sink-side cell
    // pointing into the destination box. Walks every wire; later steps may
    // override individual cells (e.g. fan-out's `●` overwrites `○`).
    for (grid.wires) |w| {
        if (w.segments.len == 0) continue;
        const src = w.segments[0].from;
        canvas.setCell(src.x, src.y, "○", .wire);

        const last = w.segments[w.segments.len - 1];
        const sink = last.to;
        canvas.setCell(sink.x, sink.y, sinkArrowFor(last), .wire);
    }

    // Step 7: fan-out taps. Count distinct wires per source point and overlay
    // `●` where ≥3 wires share a source — visually heavier than the `○` placed
    // in step 6, signalling a true branch point.
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

    // Step 8: writeOut with resolved color mode.
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

const Dir = enum { N, E, S, W };

/// Does `glyph` extend toward direction `dir`? Used by the junction picker to
/// determine whether a neighbour cell connects to the cell under inspection.
/// Treats box-drawing characters and wire characters identically — they share
/// the same glyph repertoire and the same connection semantics.
///
/// Port markers split into two classes:
///   - **Sink arrows** `▶◀▲▼` extend ONLY toward where they point (their tip).
///     They don't extend back toward their wire base, so a `┼` immediately
///     adjacent to an arrow's base downgrades to a T-junction (the arrow is
///     a wire terminator, not a fourth crossing direction).
///   - **Source / fan-out markers** `○ ●` are bidirectional — they extend in
///     all four directions. They sit on a wire's source cell where one or
///     more wires emerge in arbitrary directions, so the picker shouldn't
///     drop a connection just because a neighbour is a marker rather than a
///     rail.
fn cellExtendsToward(glyph: []const u8, dir: Dir) bool {
    if (std.mem.eql(u8, glyph, "○") or std.mem.eql(u8, glyph, "●")) return true;
    return switch (dir) {
        .N => isOneOf(glyph, &.{ "│", "╰", "╯", "┴", "├", "┤", "┼", "▲" }),
        .E => isOneOf(glyph, &.{ "─", "╭", "╰", "┬", "┴", "├", "┼", "▶" }),
        .S => isOneOf(glyph, &.{ "│", "╭", "╮", "┬", "├", "┤", "┼", "▼" }),
        .W => isOneOf(glyph, &.{ "─", "╮", "╯", "┬", "┴", "┤", "┼", "◀" }),
    };
}

fn isOneOf(needle: []const u8, haystack: []const []const u8) bool {
    for (haystack) |s| if (std.mem.eql(u8, needle, s)) return true;
    return false;
}

/// Choose the wire glyph implied by a connection set. T-junctions and the
/// 4-way cross are added on top of the corner picker's repertoire so genuine
/// branch points get the right shape instead of `+`. Empty connection sets
/// fall back to `─` — caller shouldn't invoke for unconnected cells.
fn pickJunctionGlyph(conn_w: bool, conn_e: bool, conn_n: bool, conn_s: bool) []const u8 {
    const ns = conn_n and conn_s;
    const we = conn_w and conn_e;
    if (we and ns) return "┼";
    if (we and conn_s) return "┬";
    if (we and conn_n) return "┴";
    if (ns and conn_e) return "├";
    if (ns and conn_w) return "┤";
    if (we) return "─";
    if (ns) return "│";
    if (conn_e and conn_s) return "╭";
    if (conn_w and conn_s) return "╮";
    if (conn_e and conn_n) return "╰";
    if (conn_w and conn_n) return "╯";
    if (conn_w or conn_e) return "─";
    if (conn_n or conn_s) return "│";
    return "+"; // genuinely unconnected — leave the visible warning glyph
}

fn pickJunctionsForFallbacks(canvas: *Canvas) void {
    const w = canvas.width;
    const h = canvas.height;
    var y: u32 = 0;
    while (y < h) : (y += 1) {
        var x: u32 = 0;
        while (x < w) : (x += 1) {
            const idx = @as(usize, y) * @as(usize, w) + @as(usize, x);
            const cell = canvas.cells[idx];
            const is_fallback = std.mem.eql(u8, cell, "+");
            const is_cross = std.mem.eql(u8, cell, "┼");
            if (!is_fallback and !is_cross) continue;

            const conn_w = (x > 0) and cellExtendsToward(canvas.cells[idx - 1], .E);
            const conn_e = (x + 1 < w) and cellExtendsToward(canvas.cells[idx + 1], .W);
            const conn_n = (y > 0) and cellExtendsToward(canvas.cells[idx - w], .S);
            const conn_s = (y + 1 < h) and cellExtendsToward(canvas.cells[idx + w], .N);

            if (is_fallback) {
                // `+` is a corner-picker fallback; trust whatever junctionGlyph
                // computes from the neighbours.
                canvas.setCell(x, y, pickJunctionGlyph(conn_w, conn_e, conn_n, conn_s), .wire);
                continue;
            }

            // `┼` was stamped at a crossing detected by route.zig's segment
            // pair-checker. After step 6 stamps port arrows, the actual
            // connection set at this cell may be smaller than 4: a port
            // arrow's base side doesn't extend back, and corners/endpoints
            // of one of the two wires can leave a side dangling. Trust
            // `pickJunctionGlyph` to map any connection set to the right
            // glyph — `┼` for genuine 4-ways, `┬┴├┤` for 3-ways, corners
            // `╭╮╰╯` for 2-ways. Keep the `.crossing` tag so non-trivial
            // junctions still read as signal-boundary points.
            canvas.setCell(x, y, pickJunctionGlyph(conn_w, conn_e, conn_n, conn_s), .crossing);
        }
    }
}

/// Pick the directional arrow glyph that matches the *approach* direction
/// of a wire's terminating segment. The arrow points INTO the sink box,
/// i.e. it shows where the signal is going. A horizontal segment moving
/// rightward means the wire approaches the sink from the west, so the
/// arrow is `▶`.
fn sinkArrowFor(last: Segment) []const u8 {
    if (last.from.y == last.to.y) {
        // Horizontal segment.
        if (last.to.x >= last.from.x) return "▶"; // moving east, sink is east → arrow points east
        return "◀";
    }
    // Vertical segment.
    if (last.to.y >= last.from.y) return "▼"; // moving south
    return "▲";
}

/// True when `pt` is a crossing between two wires that both terminate at the
/// same destination port — i.e., a fan-in merge.
fn isMergePoint(all_wires: []const RoutedWire, my_index: usize, pt: PortCoord) bool {
    const me = all_wires[my_index];
    for (all_wires, 0..) |other, oi| {
        if (oi == my_index) continue;
        if (other.dst_id != me.dst_id) continue;
        if (other.dst_port != me.dst_port) continue;
        if (wirePassesThrough(other, pt)) return true;
    }
    return false;
}

/// True when `pt` is a crossing between two wires that share the same source
/// port — i.e., a fan-out branch where one wire diverges from the other.
fn isSplitPoint(all_wires: []const RoutedWire, my_index: usize, pt: PortCoord) bool {
    const me = all_wires[my_index];
    for (all_wires, 0..) |other, oi| {
        if (oi == my_index) continue;
        if (other.src_id != me.src_id) continue;
        if (other.src_port != me.src_port) continue;
        if (wirePassesThrough(other, pt)) return true;
    }
    return false;
}

fn wirePassesThrough(wire: RoutedWire, pt: PortCoord) bool {
    for (wire.segments) |seg| {
        const min_x = @min(seg.from.x, seg.to.x);
        const max_x = @max(seg.from.x, seg.to.x);
        const min_y = @min(seg.from.y, seg.to.y);
        const max_y = @max(seg.from.y, seg.to.y);
        if (pt.x >= min_x and pt.x <= max_x and pt.y >= min_y and pt.y <= max_y) return true;
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
    // Source cell (x=2) → `○`; sink cell (x=6) → `▶` (wire moves east).
    try std.testing.expectEqualStrings("  ○───▶ \n", out);
}

test "render_port_markers: vertical sink directions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Wire moving south: ▼ at sink. Wire moving north: ▲ at sink.
    const south = [_]Segment{.{ .from = .{ .x = 2, .y = 0 }, .to = .{ .x = 2, .y = 3 } }};
    const north = [_]Segment{.{ .from = .{ .x = 5, .y = 3 }, .to = .{ .x = 5, .y = 0 } }};

    const wires = [_]RoutedWire{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_id = 1, .dst_port = DST_IN, .segments = &south, .crossings = &.{} },
        .{ .src_id = 2, .src_port = SRC_OUT, .dst_id = 3, .dst_port = DST_IN, .segments = &north, .crossings = &.{} },
    };
    const grid = LayoutGrid{ .width = 7, .height = 4, .components = &.{}, .wires = &wires };

    const out = try captureRender(std.testing.allocator, a, grid);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "▼") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "▲") != null);
}

test "render_port_markers: fanout dot overrides source circle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Three wires from one source — fan-out tap `●` should win over `○`.
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

    // `●` present at source; `○` would only appear at single-wire sources.
    try std.testing.expect(std.mem.indexOf(u8, out, "●") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "○") == null);
}

test "render_junction_picker: replaces + with continuation when co-linear" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two co-linear horizontal segments meeting at (5, 1) — the corner picker
    // emits `+` (no W/E rule fires); the junction picker should rewrite it to
    // `─` because both neighbours extend horizontally.
    const segs = [_]Segment{
        .{ .from = .{ .x = 2, .y = 1 }, .to = .{ .x = 5, .y = 1 } },
        .{ .from = .{ .x = 5, .y = 1 }, .to = .{ .x = 8, .y = 1 } },
    };
    const wire = RoutedWire{
        .src_id = 0,
        .src_port = SRC_OUT,
        .dst_id = 1,
        .dst_port = DST_IN,
        .segments = &segs,
        .crossings = &.{},
    };
    const grid = LayoutGrid{ .width = 10, .height = 3, .components = &.{}, .wires = &[_]RoutedWire{wire} };

    const out = try captureRender(std.testing.allocator, a, grid);
    defer std.testing.allocator.free(out);

    // No `+` should remain anywhere in the output.
    try std.testing.expect(std.mem.indexOf(u8, out, "+") == null);
}

test "render_junction_picker: 4-way cross when both wires pass through" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Horizontal wire (1,1)→(4,1)→(7,1) — corner picker writes `+` at (4,1).
    // Vertical wire (4,0)→(4,3) passes THROUGH (4,1); endpoints elsewhere
    // avoid the port-marker overlay rewriting (4,1) to `○`/`▼`.
    const seg_we = [_]Segment{
        .{ .from = .{ .x = 1, .y = 1 }, .to = .{ .x = 4, .y = 1 } },
        .{ .from = .{ .x = 4, .y = 1 }, .to = .{ .x = 7, .y = 1 } },
    };
    const seg_v = [_]Segment{.{ .from = .{ .x = 4, .y = 0 }, .to = .{ .x = 4, .y = 3 } }};
    const wires = [_]RoutedWire{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_id = 1, .dst_port = DST_IN, .segments = &seg_we, .crossings = &.{} },
        .{ .src_id = 2, .src_port = SRC_OUT, .dst_id = 3, .dst_port = DST_IN, .segments = &seg_v, .crossings = &.{} },
    };
    const grid = LayoutGrid{ .width = 9, .height = 4, .components = &.{}, .wires = &wires };

    const out = try captureRender(std.testing.allocator, a, grid);
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "┼") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "+") == null);
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

test "render_merge_dot: shared-dst crossings become ● not jump-arc" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two wires that both terminate at dst_id=99, dst_port=DST_IN, crossing
    // at (5, 2). Should render as `●` instead of `╯│╰`.
    const horiz_segs = [_]Segment{.{ .from = .{ .x = 2, .y = 2 }, .to = .{ .x = 8, .y = 2 } }};
    const vert_segs = [_]Segment{
        .{ .from = .{ .x = 5, .y = 0 }, .to = .{ .x = 5, .y = 2 } },
        .{ .from = .{ .x = 5, .y = 2 }, .to = .{ .x = 8, .y = 2 } },
    };
    const crossing_pt = PortCoord{ .x = 5, .y = 2 };

    const wires = [_]RoutedWire{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_id = 99, .dst_port = DST_IN, .segments = &horiz_segs, .crossings = &[_]PortCoord{crossing_pt} },
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_id = 99, .dst_port = DST_IN, .segments = &vert_segs, .crossings = &[_]PortCoord{crossing_pt} },
    };
    const grid = LayoutGrid{ .width = 10, .height = 4, .components = &.{}, .wires = &wires };

    const out = try captureRender(std.testing.allocator, a, grid);
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "●") != null);
    // Jump-arc neighbours `╯│╰` should not appear at the merge.
    try std.testing.expect(std.mem.indexOf(u8, out, "╯│╰") == null);
}

test "render_crossing_uses_plus_glyph: unrelated wires cross with ┼" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Hand-construct a horizontal wire and a vertical wire that cross at (5, 2).
    // Different src AND different dst → not a split, not a merge → `┼`.
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

    // Crossing now stamps single-cell `┼`; jump-arc `╯│╰` is gone.
    try std.testing.expect(std.mem.indexOf(u8, out, "┼") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "╯│╰") == null);
}

test "render_split_dot: shared-src crossings become ● not ┼" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two wires from same src (id=0, SRC_OUT) — one stays horizontal, the
    // other turns down. Their geometries cross at (5, 2). Expect `●`.
    const wire_a_segs = [_]Segment{.{ .from = .{ .x = 2, .y = 2 }, .to = .{ .x = 8, .y = 2 } }};
    const wire_b_segs = [_]Segment{
        .{ .from = .{ .x = 2, .y = 2 }, .to = .{ .x = 5, .y = 2 } },
        .{ .from = .{ .x = 5, .y = 2 }, .to = .{ .x = 5, .y = 4 } },
    };
    const crossing_pt = PortCoord{ .x = 5, .y = 2 };

    const wires = [_]RoutedWire{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_id = 1, .dst_port = DST_IN, .segments = &wire_a_segs, .crossings = &[_]PortCoord{crossing_pt} },
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_id = 2, .dst_port = DST_IN, .segments = &wire_b_segs, .crossings = &[_]PortCoord{crossing_pt} },
    };
    const grid = LayoutGrid{ .width = 10, .height = 5, .components = &.{}, .wires = &wires };

    const out = try captureRender(std.testing.allocator, a, grid);
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "●") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "┼") == null);
}
