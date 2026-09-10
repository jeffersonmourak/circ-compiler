//! Render-free layout invariants over a `LayoutGrid`.
//!
//! The counters are the measurement of record for the layout rewrite
//! (`DOCS/PLANS_PROMPT.md`, decision 10). A *net* is everything driven by
//! one source port, `(src_id, src_port)`; wires of one net may share cells
//! freely (that is a fan-out trunk), wires of different nets may only cross
//! perpendicularly.
//!
//!   I0 `body`      wire cells strictly inside a component box (port cells
//!                  sit outside the box, so a correct route never enters).
//!   I1 `shared`    cells covered by two or more nets with the same
//!                  orientation — the fused-rail bug the rewrite exists for.
//!   I2 `junction`  cells where two or more nets meet other than as a clean
//!                  perpendicular pass-through: a corner or an endpoint on
//!                  another net's cell, or three nets in one cell.
//!   I3 `tree`      nets whose cells are not one 4-connected set containing
//!                  the source cell, or whose wires have a segment chain that
//!                  is not contiguous or not axis-aligned.
//!
//! Also reported: `crossings` (clean perpendicular crossings between two
//! nets), `bends` (corners over all wires), `straight` (single-segment wires)
//! and `wires`.
const std = @import("std");
const layout = @import("layout");

const LayoutGrid = layout.LayoutGrid;
const RoutedWire = layout.RoutedWire;
const Segment = layout.Segment;

pub const Report = struct {
    body: u32 = 0,
    shared: u32 = 0,
    junction: u32 = 0,
    tree: u32 = 0,
    crossings: u32 = 0,
    bends: u32 = 0,
    straight: u32 = 0,
    wires: u32 = 0,
};

const Cell = struct { x: u32, y: u32 };
const NetKey = struct { src_id: u32, src_port: u8 };

/// One wire's coverage of one cell. `through` is true when the wire passes
/// straight through the cell (an interior cell, or an endpoint shared with a
/// collinear neighbour segment); a corner or a terminal cell is not through.
const Claim = struct {
    net: NetKey,
    wire: u32,
    horizontal: bool,
    through: bool,
};

const NetState = struct {
    cells: std.AutoHashMap(Cell, void),
    source: ?Cell,
    broken: bool,
};

fn isHorizontal(seg: Segment) bool {
    return seg.from.y == seg.to.y;
}

fn isAxisAligned(seg: Segment) bool {
    return seg.from.x == seg.to.x or seg.from.y == seg.to.y;
}

fn sameCell(a: layout.PortCoord, b: layout.PortCoord) bool {
    return a.x == b.x and a.y == b.y;
}

fn insideAnyBox(grid: LayoutGrid, cell: Cell) bool {
    for (grid.components) |c| {
        if (cell.x >= c.x and cell.x < c.x + c.width and cell.y >= c.y and cell.y < c.y + c.height) return true;
    }
    return false;
}

pub fn check(arena: std.mem.Allocator, grid: LayoutGrid) !Report {
    var report = Report{};
    var claims = std.AutoHashMap(Cell, std.ArrayList(Claim)).init(arena);
    var nets = std.AutoHashMap(NetKey, NetState).init(arena);

    for (grid.wires, 0..) |w, wi| {
        report.wires += 1;
        if (w.segments.len == 1) report.straight += 1;
        if (w.segments.len > 1) report.bends += @intCast(w.segments.len - 1);

        const key = NetKey{ .src_id = w.src_id, .src_port = w.src_port };
        const net_entry = try nets.getOrPut(key);
        if (!net_entry.found_existing) {
            net_entry.value_ptr.* = .{ .cells = std.AutoHashMap(Cell, void).init(arena), .source = null, .broken = false };
        }
        const net = net_entry.value_ptr;

        if (w.segments.len == 0) {
            net.broken = true;
            continue;
        }

        // The net's source cell is where its first wire starts; every other
        // wire of the net must start there too.
        const start = Cell{ .x = w.segments[0].from.x, .y = w.segments[0].from.y };
        if (net.source) |s| {
            if (s.x != start.x or s.y != start.y) net.broken = true;
        } else {
            net.source = start;
        }

        for (w.segments, 0..) |seg, si| {
            if (!isAxisAligned(seg)) {
                net.broken = true;
                continue;
            }
            if (si > 0 and !sameCell(w.segments[si - 1].to, seg.from)) net.broken = true;

            const horizontal = isHorizontal(seg);
            const from_through = si > 0 and isAxisAligned(w.segments[si - 1]) and isHorizontal(w.segments[si - 1]) == horizontal and sameCell(w.segments[si - 1].to, seg.from);
            const to_through = si + 1 < w.segments.len and isAxisAligned(w.segments[si + 1]) and isHorizontal(w.segments[si + 1]) == horizontal and sameCell(w.segments[si + 1].from, seg.to);

            const lo = if (horizontal) @min(seg.from.x, seg.to.x) else @min(seg.from.y, seg.to.y);
            const hi = if (horizontal) @max(seg.from.x, seg.to.x) else @max(seg.from.y, seg.to.y);
            var i = lo;
            while (i <= hi) : (i += 1) {
                const cell = if (horizontal) Cell{ .x = i, .y = seg.from.y } else Cell{ .x = seg.from.x, .y = i };
                const is_from = cell.x == seg.from.x and cell.y == seg.from.y;
                const is_to = cell.x == seg.to.x and cell.y == seg.to.y;
                const through = if (is_from and is_to) false else if (is_from) from_through else if (is_to) to_through else true;

                if (insideAnyBox(grid, cell)) report.body += 1;
                try net.cells.put(cell, {});

                const entry = try claims.getOrPut(cell);
                if (!entry.found_existing) entry.value_ptr.* = .{};
                // A corner cell is claimed twice by the same wire (as the end
                // of one segment and the start of the next), once per
                // orientation; both claims are kept so the cell reads as a
                // corner in the classification below.
                try entry.value_ptr.append(arena, .{ .net = key, .wire = @intCast(wi), .horizontal = horizontal, .through = through });
            }
        }
    }

    // Per-cell classification of every cell two or more nets cover.
    var it = claims.iterator();
    while (it.next()) |entry| {
        const list = entry.value_ptr.items;
        var first_net: ?NetKey = null;
        var net_count: u32 = 0;
        var second_net: ?NetKey = null;
        for (list) |c| {
            if (first_net == null) {
                first_net = c.net;
                net_count = 1;
            } else if (!std.meta.eql(first_net.?, c.net)) {
                if (second_net == null) {
                    second_net = c.net;
                    net_count = 2;
                } else if (!std.meta.eql(second_net.?, c.net)) {
                    net_count = 3;
                }
            }
        }
        if (net_count < 2) continue;

        var all_same = true;
        for (list[1..]) |c| {
            if (c.horizontal != list[0].horizontal) all_same = false;
        }
        if (all_same) {
            report.shared += 1;
            continue;
        }

        if (net_count == 2 and list.len == 2 and list[0].through and list[1].through and list[0].horizontal != list[1].horizontal) {
            report.crossings += 1;
        } else {
            report.junction += 1;
        }
    }

    // Per-net connectivity from the source cell.
    var nit = nets.iterator();
    while (nit.next()) |entry| {
        const net = entry.value_ptr;
        if (net.broken or net.source == null) {
            report.tree += 1;
            continue;
        }
        if (!try connectedFrom(arena, &net.cells, net.source.?)) report.tree += 1;
    }

    return report;
}

/// True when every cell in `cells` is reachable from `start` through
/// 4-neighbour steps that stay inside `cells`.
fn connectedFrom(arena: std.mem.Allocator, cells: *std.AutoHashMap(Cell, void), start: Cell) !bool {
    if (!cells.contains(start)) return false;
    var seen = std.AutoHashMap(Cell, void).init(arena);
    var stack: std.ArrayList(Cell) = .{};
    try stack.append(arena, start);
    try seen.put(start, {});
    while (stack.pop()) |cell| {
        const neighbours = [_]?Cell{
            if (cell.x > 0) Cell{ .x = cell.x - 1, .y = cell.y } else null,
            Cell{ .x = cell.x + 1, .y = cell.y },
            if (cell.y > 0) Cell{ .x = cell.x, .y = cell.y - 1 } else null,
            Cell{ .x = cell.x, .y = cell.y + 1 },
        };
        for (neighbours) |maybe| {
            const n = maybe orelse continue;
            if (!cells.contains(n) or seen.contains(n)) continue;
            try seen.put(n, {});
            try stack.append(arena, n);
        }
    }
    return seen.count() == cells.count();
}

// ---------- Tests ----------

const testing = std.testing;

fn sg(x0: u32, y0: u32, x1: u32, y1: u32) Segment {
    return .{ .from = .{ .x = x0, .y = y0 }, .to = .{ .x = x1, .y = y1 } };
}

fn wire(src_id: u32, dst_id: u32, segments: []const Segment) RoutedWire {
    return .{ .src_id = src_id, .src_port = 3, .dst_id = dst_id, .dst_port = 0, .segments = segments, .crossings = &.{} };
}

fn box(id: u32, x: u32, y: u32, w: u32, h: u32) layout.PlacedComponent {
    return .{ .id = id, .kind = .{ .primitive = .not_gate }, .name = "", .origin = &.{}, .x = x, .y = y, .width = w, .height = h, .in_ports = &.{}, .out_port = .{ .x = x + w, .y = y + 1 } };
}

fn mkGrid(components: []const layout.PlacedComponent, wires: []const RoutedWire) LayoutGrid {
    return .{ .width = 40, .height = 20, .components = components, .wires = wires };
}

test "invariants: empty grid reports zeros" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const r = try check(arena.allocator(), mkGrid(&.{}, &.{}));
    try testing.expectEqual(Report{}, r);
}

test "invariants: a single straight wire is straight and clean" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const segs = [_]Segment{sg(5, 1, 9, 1)};
    const wires = [_]RoutedWire{wire(0, 1, &segs)};
    const r = try check(arena.allocator(), mkGrid(&.{}, &wires));
    try testing.expectEqual(Report{ .straight = 1, .wires = 1 }, r);
}

test "invariants: a wire through a box body counts body cells" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Box occupies x 10..14, y 0..2. The wire runs along y=1 from x=5 to x=20:
    // cells 10..14 are inside → 5 body cells; the port cells 9 and 15 are not.
    const boxes = [_]layout.PlacedComponent{box(7, 10, 0, 5, 3)};
    const segs = [_]Segment{sg(5, 1, 20, 1)};
    const wires = [_]RoutedWire{wire(0, 1, &segs)};
    const r = try check(arena.allocator(), mkGrid(&boxes, &wires));
    try testing.expectEqual(@as(u32, 5), r.body);
    try testing.expectEqual(@as(u32, 0), r.shared);
}

test "invariants: two nets on one row share cells" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = [_]Segment{sg(0, 3, 10, 3)};
    const b = [_]Segment{sg(6, 3, 15, 3)};
    const wires = [_]RoutedWire{ wire(0, 1, &a), wire(2, 3, &b) };
    const r = try check(arena.allocator(), mkGrid(&.{}, &wires));
    try testing.expectEqual(@as(u32, 5), r.shared); // x = 6..10
    try testing.expectEqual(@as(u32, 0), r.junction);
    try testing.expectEqual(@as(u32, 0), r.crossings);
}

test "invariants: a perpendicular pass-through is a crossing, not a junction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const h = [_]Segment{sg(0, 3, 10, 3)};
    const v = [_]Segment{sg(5, 0, 5, 6)};
    const wires = [_]RoutedWire{ wire(0, 1, &h), wire(2, 3, &v) };
    const r = try check(arena.allocator(), mkGrid(&.{}, &wires));
    try testing.expectEqual(@as(u32, 1), r.crossings);
    try testing.expectEqual(@as(u32, 0), r.junction);
    try testing.expectEqual(@as(u32, 0), r.shared);
}

test "invariants: a corner on another net's cell is a junction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const h = [_]Segment{sg(0, 3, 10, 3)};
    // Corners at (5,3), on the other net's row.
    const l = [_]Segment{ sg(5, 0, 5, 3), sg(5, 3, 9, 3) };
    const wires = [_]RoutedWire{ wire(0, 1, &h), wire(2, 3, &l) };
    const r = try check(arena.allocator(), mkGrid(&.{}, &wires));
    try testing.expectEqual(@as(u32, 1), r.junction);
    try testing.expectEqual(@as(u32, 0), r.crossings);
    try testing.expectEqual(@as(u32, 4), r.shared); // x = 6..9 on row 3
}

test "invariants: three nets meeting is a junction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const h = [_]Segment{sg(0, 3, 10, 3)};
    const v = [_]Segment{sg(5, 0, 5, 6)};
    const t = [_]Segment{sg(5, 3, 5, 3)};
    const wires = [_]RoutedWire{ wire(0, 1, &h), wire(2, 3, &v), wire(4, 5, &t) };
    const r = try check(arena.allocator(), mkGrid(&.{}, &wires));
    try testing.expectEqual(@as(u32, 1), r.junction);
    try testing.expectEqual(@as(u32, 0), r.crossings);
}

test "invariants: fan-out sharing its own trunk is not shared" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const up = [_]Segment{ sg(5, 4, 7, 4), sg(7, 4, 7, 1), sg(7, 1, 12, 1) };
    const down = [_]Segment{ sg(5, 4, 7, 4), sg(7, 4, 7, 8), sg(7, 8, 12, 8) };
    const wires = [_]RoutedWire{ wire(0, 1, &up), wire(0, 2, &down) };
    const r = try check(arena.allocator(), mkGrid(&.{}, &wires));
    try testing.expectEqual(Report{ .bends = 4, .wires = 2 }, r);
}

test "invariants: a disconnected net and a broken chain count as non-tree" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Net 0: second segment does not start where the first ends.
    const broken = [_]Segment{ sg(0, 0, 4, 0), sg(6, 0, 9, 0) };
    // Net 2: two wires, the second starts somewhere else entirely.
    const w1 = [_]Segment{sg(0, 5, 4, 5)};
    const w2 = [_]Segment{sg(10, 5, 14, 5)};
    // Net 4: fine.
    const ok = [_]Segment{ sg(0, 9, 4, 9), sg(4, 9, 4, 12) };
    const wires = [_]RoutedWire{ wire(0, 1, &broken), wire(2, 3, &w1), wire(2, 6, &w2), wire(4, 5, &ok) };
    const r = try check(arena.allocator(), mkGrid(&.{}, &wires));
    try testing.expectEqual(@as(u32, 2), r.tree);
    try testing.expectEqual(@as(u32, 4), r.wires);
    try testing.expectEqual(@as(u32, 2), r.bends);
}

test "invariants: and_of_not's fused cells reproduce as shared" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // The golden picture: `a` (net 0) leaves at (5,1) and runs to (19,3) via a
    // detour on row 3; `b` (net 1) leaves at (5,7), climbs x=6 and enters NOT
    // on row 1. Their cells meet at (6,1)…(6,3) with `b` vertical and `a`'s
    // corner, and `a`'s row-3 rail is shared with NOT.out (net 2) on x=16..18.
    const a = [_]Segment{ sg(5, 1, 6, 1), sg(6, 1, 6, 3), sg(6, 3, 19, 3) };
    const b = [_]Segment{ sg(5, 7, 6, 7), sg(6, 7, 6, 1), sg(6, 1, 9, 1) };
    const n = [_]Segment{ sg(15, 1, 16, 1), sg(16, 1, 16, 3), sg(16, 3, 19, 3) };
    const wires = [_]RoutedWire{ wire(0, 3, &a), wire(1, 2, &b), wire(2, 3, &n) };
    const r = try check(arena.allocator(), mkGrid(&.{}, &wires));
    try testing.expect(r.shared > 0);
    try testing.expect(r.junction > 0);
    try testing.expectEqual(@as(u32, 0), r.tree);
}
