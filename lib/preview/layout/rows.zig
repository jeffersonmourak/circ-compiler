const std = @import("std");
const full_format = @import("full_format");
const types = @import("layout_types");

const VirtualGraph = types.VirtualGraph;
const VirtualNode = types.VirtualNode;
const ColumnAssignment = types.ColumnAssignment;
const RowAssignment = types.RowAssignment;

const Pair = struct {
    idx: usize,
    barycenter: f64,
};

/// Stage 3: barycenter-method row assignment over a column-laid-out `VirtualGraph`.
///
/// Algorithm:
///   1. Group nodes by column. Initial row order within each column = id-ascending
///      (inherited from `VirtualGraph.nodes`, which collapse stage sorts by id).
///   2. Sweep left-to-right: for each column from 1 to N-1, compute each node's
///      barycenter as the mean row index of its upstream neighbours in earlier
///      columns. Reorder the column by ascending barycenter; ties broken by
///      ascending node id.
///   3. Sweep right-to-left: same, but using downstream neighbours in later columns.
///
/// Output rows are 0-indexed positions within each column.
///
/// Determinism is anchored by:
///   - Stable input order (`graph.nodes` sorted by id at collapse time).
///   - Float comparison without epsilon (we want byte-identical results across runs).
///   - Tie-break on raw integer id when barycenters are equal.
pub fn assignRows(
    arena: std.mem.Allocator,
    graph: VirtualGraph,
    columns: ColumnAssignment,
) !RowAssignment {
    const n = graph.nodes.len;

    // Build node-id → graph-index lookup.
    var index_of = std.AutoHashMap(u32, usize).init(arena);
    for (graph.nodes, 0..) |node, i| try index_of.put(node.id, i);

    // Group nodes by column. Buckets hold graph-indices in their current row order.
    const buckets = try arena.alloc(std.ArrayList(usize), columns.num_columns);
    for (buckets) |*b| b.* = .{};
    for (columns.column_of, 0..) |col, idx| {
        try buckets[col].append(arena, idx);
    }

    // Two sweeps.
    try sweepBarycenter(arena, graph, columns, buckets, &index_of, .left_to_right);
    try sweepBarycenter(arena, graph, columns, buckets, &index_of, .right_to_left);

    // Materialize row_of from final bucket positions.
    const row_of = try arena.alloc(u32, n);
    var max_rows: u32 = 0;
    for (buckets) |bucket| {
        for (bucket.items, 0..) |node_idx, pos| {
            row_of[node_idx] = @intCast(pos);
        }
        if (bucket.items.len > max_rows) max_rows = @intCast(bucket.items.len);
    }

    return .{ .row_of = row_of, .num_rows = max_rows };
}

const Direction = enum { left_to_right, right_to_left };

fn sweepBarycenter(
    arena: std.mem.Allocator,
    graph: VirtualGraph,
    columns: ColumnAssignment,
    buckets: []std.ArrayList(usize),
    index_of: *std.AutoHashMap(u32, usize),
    dir: Direction,
) !void {
    var col_iter: i64 = switch (dir) {
        .left_to_right => 1,
        .right_to_left => @as(i64, @intCast(columns.num_columns)) - 2,
    };
    const end_inclusive: i64 = switch (dir) {
        .left_to_right => @as(i64, @intCast(columns.num_columns)) - 1,
        .right_to_left => 0,
    };
    const step: i64 = switch (dir) {
        .left_to_right => 1,
        .right_to_left => -1,
    };

    while (true) : (col_iter += step) {
        // Stop condition.
        if (step > 0 and col_iter > end_inclusive) break;
        if (step < 0 and col_iter < end_inclusive) break;

        const col: u32 = @intCast(col_iter);
        const bucket = &buckets[col];
        if (bucket.items.len <= 1) continue;

        const pairs = try arena.alloc(Pair, bucket.items.len);
        for (bucket.items, 0..) |node_idx, i| {
            pairs[i] = .{
                .idx = node_idx,
                .barycenter = computeBarycenter(graph, columns, buckets, index_of, node_idx, dir, i),
            };
        }

        std.mem.sort(Pair, pairs, graph.nodes, lessByBarycenterThenId);

        bucket.clearRetainingCapacity();
        for (pairs) |p| try bucket.append(arena, p.idx);
    }
}

fn computeBarycenter(
    graph: VirtualGraph,
    columns: ColumnAssignment,
    buckets: []std.ArrayList(usize),
    index_of: *std.AutoHashMap(u32, usize),
    node_idx: usize,
    dir: Direction,
    fallback_position: usize,
) f64 {
    const node = graph.nodes[node_idx];
    var sum: f64 = 0;
    var count: f64 = 0;

    switch (dir) {
        .left_to_right => for (node.inputs) |edge| {
            accumulateRow(columns, buckets, index_of, edge.src_id, &sum, &count);
        },
        .right_to_left => for (node.outputs) |edge| {
            accumulateRow(columns, buckets, index_of, edge.dst_id, &sum, &count);
        },
    }

    return if (count > 0) sum / count else @as(f64, @floatFromInt(fallback_position));
}

fn accumulateRow(
    columns: ColumnAssignment,
    buckets: []std.ArrayList(usize),
    index_of: *std.AutoHashMap(u32, usize),
    neighbour_id: u32,
    sum: *f64,
    count: *f64,
) void {
    const neighbour_idx = index_of.get(neighbour_id) orelse return;
    const neighbour_col = columns.column_of[neighbour_idx];
    for (buckets[neighbour_col].items, 0..) |bi, pos| {
        if (bi == neighbour_idx) {
            sum.* += @floatFromInt(pos);
            count.* += 1;
            return;
        }
    }
}

fn lessByBarycenterThenId(nodes: []const VirtualNode, a: Pair, b: Pair) bool {
    if (a.barycenter != b.barycenter) return a.barycenter < b.barycenter;
    return nodes[a.idx].id < nodes[b.idx].id;
}

// ---------- Tests ----------

const InputEdge = types.InputEdge;
const OutputEdge = types.OutputEdge;
const NodeKind = types.NodeKind;
const SRC_OUT: u8 = @intFromEnum(full_format.PortName.out);
const DST_IN: u8 = @intFromEnum(full_format.PortName.in);
const DST_A: u8 = @intFromEnum(full_format.PortName.a);
const DST_B: u8 = @intFromEnum(full_format.PortName.b);

fn makeNode(id: u32, kind: NodeKind, inputs: []const InputEdge, outputs: []const OutputEdge) VirtualNode {
    return .{
        .id = id,
        .kind = kind,
        .name = "",
        .origin = &.{},
        .inputs = inputs,
        .outputs = outputs,
    };
}

test "rows_barycenter_simple: crossing edges resolved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Column 0: pin0 (id=0), pin1 (id=1).
    // Column 1: not_a (id=2) driven by pin1, not_b (id=3) driven by pin0.
    // Naive id-ascending order: pin0 row 0, pin1 row 1; not_a row 0, not_b row 1.
    // Edges then cross: pin1(row 1) → not_a(row 0); pin0(row 0) → not_b(row 1).
    // Barycenter for col 1: not_a's upstream = pin1 (row 1), not_b's upstream = pin0 (row 0).
    // Reorder col 1 ascending barycenter: not_b first (bary 0), not_a second (bary 1).
    // Result rows: pin0=0, pin1=1, not_b=0, not_a=1. No crossings.
    const pin0 = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const pin1 = makeNode(1, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_a = makeNode(2, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});
    const not_b = makeNode(3, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});

    const nodes = [_]VirtualNode{ pin0, pin1, not_a, not_b };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 4 };
    const cols = ColumnAssignment{
        .column_of = &[_]u32{ 0, 0, 1, 1 },
        .num_columns = 2,
    };

    const rows = try assignRows(a, graph, cols);
    try std.testing.expectEqual(@as(u32, 2), rows.num_rows);

    // pin0 stays row 0, pin1 stays row 1 (col 0 is not swept).
    try std.testing.expectEqual(@as(u32, 0), rows.row_of[0]);
    try std.testing.expectEqual(@as(u32, 1), rows.row_of[1]);

    // not_a (id=2) is driven by pin1 (row 1) → barycenter 1 → ends up at row 1.
    // not_b (id=3) is driven by pin0 (row 0) → barycenter 0 → ends up at row 0.
    try std.testing.expectEqual(@as(u32, 1), rows.row_of[2]);
    try std.testing.expectEqual(@as(u32, 0), rows.row_of[3]);
}

test "rows_deterministic_tie_break: equal barycenters resolve by ascending id" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Single pin at col 0. Two nots at col 1, both driven by the same pin.
    // Both nots have barycenter 0 (their only upstream is at row 0). Ties → ascending id.
    const pin = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_lo = makeNode(1, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});
    const not_hi = makeNode(2, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});

    const nodes = [_]VirtualNode{ pin, not_lo, not_hi };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 3 };
    const cols = ColumnAssignment{
        .column_of = &[_]u32{ 0, 1, 1 },
        .num_columns = 2,
    };

    const rows1 = try assignRows(a, graph, cols);

    // Equal barycenters → id-ascending order: not_lo (id=1) first, not_hi (id=2) second.
    try std.testing.expectEqual(@as(u32, 0), rows1.row_of[1]);
    try std.testing.expectEqual(@as(u32, 1), rows1.row_of[2]);

    // Determinism: run twice on the same input → byte-identical row_of.
    const rows2 = try assignRows(a, graph, cols);
    try std.testing.expectEqualSlices(u32, rows1.row_of, rows2.row_of);
    try std.testing.expectEqual(rows1.num_rows, rows2.num_rows);
}
