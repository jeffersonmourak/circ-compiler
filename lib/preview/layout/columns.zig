const std = @import("std");
const full_format = @import("full_format");
const types = @import("layout_types");

const VirtualGraph = types.VirtualGraph;
const VirtualNode = types.VirtualNode;
const ColumnAssignment = types.ColumnAssignment;

/// Stage 2: longest-path column assignment over a `VirtualGraph`.
///
/// Rules:
///   - `input_pin` primitives are pinned at column 0.
///   - For every other node: `column_of[n] = 1 + max(column_of[upstream])`
///     across all incoming edges, *excluding back edges that close a cycle*.
///   - `led` and `output_pin` primitives are then forced to `num_columns - 1`
///     so all sinks line up on the right edge of the diagram.
///
/// Cycle handling: combinational feedback (e.g. cross-coupled NOR latches) is
/// legal at the simulation layer, so the column stage must tolerate it. A
/// pre-pass DFS over output edges classifies each edge as tree/forward/cross
/// (DAG) or back (closes a cycle). Back edges are excluded from the longest-
/// path sweep — without that, every iteration through the cycle bumps each
/// member's column and the sweep only stops when the iteration cap fires,
/// stranding inputs at low columns and pushing cycle nodes to the far right.
/// The back edges themselves stay in the graph; the router renders them as
/// right-to-left feedback wires via its 5-leg detour path.
///
/// Iteration: a fixed-point sweep that converges in at most `nodes.len + 1`
/// passes once back edges are removed (the residual is a DAG by construction).
pub fn assignColumns(arena: std.mem.Allocator, graph: VirtualGraph) !ColumnAssignment {
    const n = graph.nodes.len;
    const column_of = try arena.alloc(u32, n);
    @memset(column_of, 0);

    var index_of = std.AutoHashMap(u32, usize).init(arena);
    for (graph.nodes, 0..) |node, i| {
        try index_of.put(node.id, i);
    }

    const back_edges = try detectBackEdges(arena, graph, &index_of);

    // A "back-edge destination" needs at least column 1, even when no forward
    // upstream pushes it there. Reason: route.zig's 5-leg detour for a
    // leftward feedback wire anchors on the cell west of the destination's
    // in-port (the "west gutter"). At column 0 there is no such cell — the
    // router's documented fallback overdraws the gate body. Reserve column 0
    // as gutter for free-floating cycles by bumping orphan back-edge dsts to
    // column 1 during the sweep.
    const is_back_edge_dst = try arena.alloc(bool, n);
    @memset(is_back_edge_dst, false);
    var be_iter = back_edges.keyIterator();
    while (be_iter.next()) |key| {
        const dst_idx = index_of.get(key.dst_id) orelse continue;
        is_back_edge_dst[dst_idx] = true;
    }

    // Fixed-point sweep.
    var iter: usize = 0;
    var changed = true;
    while (changed and iter <= n + 1) : (iter += 1) {
        changed = false;
        for (graph.nodes, 0..) |node, i| {
            if (isInputPin(node)) {
                if (column_of[i] != 0) {
                    column_of[i] = 0;
                    changed = true;
                }
                continue;
            }
            var max_upstream_plus_one: u32 = 0;
            for (node.inputs) |edge| {
                if (back_edges.contains(.{
                    .src_id = edge.src_id,
                    .dst_id = node.id,
                    .src_port = edge.src_port,
                    .dst_port = edge.dst_port,
                })) continue;
                const up_idx = index_of.get(edge.src_id) orelse continue;
                const candidate = column_of[up_idx] + 1;
                if (candidate > max_upstream_plus_one) max_upstream_plus_one = candidate;
            }
            if (max_upstream_plus_one == 0 and is_back_edge_dst[i]) {
                max_upstream_plus_one = 1;
            }
            if (max_upstream_plus_one != column_of[i]) {
                column_of[i] = max_upstream_plus_one;
                changed = true;
            }
        }
    }

    // Determine total column count from the longest path.
    var num_columns: u32 = 1;
    for (column_of) |c| {
        if (c + 1 > num_columns) num_columns = c + 1;
    }

    // Force sinks (led, output_pin) to the rightmost column.
    for (graph.nodes, 0..) |node, i| {
        if (isSink(node)) column_of[i] = num_columns - 1;
    }

    return .{ .column_of = column_of, .num_columns = num_columns };
}

/// A back edge identified by its full (src_id, src_port, dst_id, dst_port) key.
/// We need all four because a node can fan in from the same source on
/// multiple ports (or, for fanout, drive multiple ports on the same dst);
/// using only (src_id, dst_id) would over-classify.
const EdgeKey = struct {
    src_id: u32,
    dst_id: u32,
    src_port: u8,
    dst_port: u8,
};

const Color = enum(u8) { white = 0, gray = 1, black = 2 };

/// Iterative DFS over output edges. An edge `u → v` is a *back edge* iff `v`
/// is currently on the recursion stack (gray). Back edges are exactly the
/// edges that close cycles in any DFS spanning forest, and removing them
/// leaves a DAG.
///
/// DFS roots are picked in `graph.nodes` index order, which is stable
/// (collapse stage sorts by id). This makes the back-edge set deterministic
/// across runs even when multiple choices would be valid (e.g. for a
/// 2-cycle A↔B, the edge visited second is the one classified back).
fn detectBackEdges(
    arena: std.mem.Allocator,
    graph: VirtualGraph,
    index_of: *std.AutoHashMap(u32, usize),
) !std.AutoHashMap(EdgeKey, void) {
    const n = graph.nodes.len;
    const color = try arena.alloc(Color, n);
    @memset(color, .white);

    var back_edges = std.AutoHashMap(EdgeKey, void).init(arena);

    const Frame = struct { node_idx: usize, next_edge: usize };
    var stack: std.ArrayList(Frame) = .{};

    for (0..n) |start| {
        if (color[start] != .white) continue;
        color[start] = .gray;
        try stack.append(arena, .{ .node_idx = start, .next_edge = 0 });

        while (stack.items.len > 0) {
            const top = &stack.items[stack.items.len - 1];
            const node = graph.nodes[top.node_idx];
            if (top.next_edge >= node.outputs.len) {
                color[top.node_idx] = .black;
                _ = stack.pop();
                continue;
            }
            const edge = node.outputs[top.next_edge];
            top.next_edge += 1;

            const dst_idx = index_of.get(edge.dst_id) orelse continue;
            switch (color[dst_idx]) {
                .gray => {
                    // Back edge: closes a cycle. Skip in column propagation.
                    try back_edges.put(.{
                        .src_id = node.id,
                        .dst_id = edge.dst_id,
                        .src_port = edge.src_port,
                        .dst_port = edge.dst_port,
                    }, {});
                },
                .white => {
                    color[dst_idx] = .gray;
                    try stack.append(arena, .{ .node_idx = dst_idx, .next_edge = 0 });
                },
                .black => {}, // forward or cross edge — DAG, no action.
            }
        }
    }

    return back_edges;
}

fn isInputPin(node: VirtualNode) bool {
    return switch (node.kind) {
        .primitive => |p| p == .input_pin,
        .subcircuit => false,
    };
}

fn isSink(node: VirtualNode) bool {
    return switch (node.kind) {
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

test "columns_longest_path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // pin → not → and → led
    // Build inputs/outputs lists to wire the chain.
    const pin = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_node = makeNode(1, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_A },
    });
    const and_node = makeNode(2, .{ .primitive = .and_gate }, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_A },
    }, &.{
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const led = makeNode(3, .{ .primitive = .led }, &.{
        .{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});

    const nodes = [_]VirtualNode{ pin, not_node, and_node, led };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 4 };

    const cols = try assignColumns(a, graph);
    try std.testing.expectEqual(@as(u32, 4), cols.num_columns);
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[0]);
    try std.testing.expectEqual(@as(u32, 1), cols.column_of[1]);
    try std.testing.expectEqual(@as(u32, 2), cols.column_of[2]);
    try std.testing.expectEqual(@as(u32, 3), cols.column_of[3]);
}

test "columns_diamond" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // pin1 fans out to not_a and not_b; both feed an and_gate.
    // Layout: pin=0, not_a=1, not_b=1, and=2.
    const pin = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_a = makeNode(1, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_A },
    });
    const not_b = makeNode(2, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_B },
    });
    const and_node = makeNode(3, .{ .primitive = .and_gate }, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_A },
        .{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_B },
    }, &.{});

    const nodes = [_]VirtualNode{ pin, not_a, not_b, and_node };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 4 };

    const cols = try assignColumns(a, graph);
    try std.testing.expectEqual(@as(u32, 3), cols.num_columns);
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[0]);
    try std.testing.expectEqual(@as(u32, 1), cols.column_of[1]);
    try std.testing.expectEqual(@as(u32, 1), cols.column_of[2]);
    try std.testing.expectEqual(@as(u32, 2), cols.column_of[3]);
}

test "columns_input_pins_at_zero" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two unrelated input pins, no downstream — both must be column 0.
    const pin1 = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{});
    const pin2 = makeNode(1, .{ .primitive = .input_pin }, &.{}, &.{});

    const nodes = [_]VirtualNode{ pin1, pin2 };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 2 };

    const cols = try assignColumns(a, graph);
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[0]);
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[1]);
}

test "columns_leds_rightmost" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // pin → not → and → led_late, plus pin → led_early (would naturally be col 1).
    // The "early" LED should still be forced to the rightmost column.
    const pin = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 4, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_node = makeNode(1, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_A },
    });
    const and_node = makeNode(2, .{ .primitive = .and_gate }, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_A },
    }, &.{
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const led_late = makeNode(3, .{ .primitive = .led }, &.{
        .{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});
    const led_early = makeNode(4, .{ .primitive = .led }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});

    const nodes = [_]VirtualNode{ pin, not_node, and_node, led_late, led_early };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 5 };

    const cols = try assignColumns(a, graph);
    try std.testing.expectEqual(@as(u32, 4), cols.num_columns);
    // Both LEDs land in the rightmost column (3), even though led_early's
    // natural longest-path column would have been 1.
    try std.testing.expectEqual(@as(u32, 3), cols.column_of[3]);
    try std.testing.expectEqual(@as(u32, 3), cols.column_of[4]);
    // Non-sinks keep their longest-path columns.
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[0]);
    try std.testing.expectEqual(@as(u32, 1), cols.column_of[1]);
    try std.testing.expectEqual(@as(u32, 2), cols.column_of[2]);
}

test "columns_two_node_cycle: back edge contained" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two NOT gates wired into a 2-cycle: not_a.out → not_b.in, not_b.out → not_a.in.
    // Without back-edge detection, the longest-path sweep would inflate both
    // columns to (n+1) ≈ 3 before the cap fires. With detection: DFS visits
    // not_a → not_b first, classifies not_b → not_a as the back edge.
    // Gutter rule then bumps not_a (a back-edge dst with no forward upstream)
    // from col 0 to col 1, giving the leftward feedback wire room. Layout:
    // col 0 empty (gutter), not_a at col 1, not_b at col 2.
    const not_a = makeNode(0, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const not_b = makeNode(1, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    });

    const nodes = [_]VirtualNode{ not_a, not_b };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 2 };

    const cols = try assignColumns(a, graph);
    try std.testing.expectEqual(@as(u32, 3), cols.num_columns);
    try std.testing.expectEqual(@as(u32, 1), cols.column_of[0]);
    try std.testing.expectEqual(@as(u32, 2), cols.column_of[1]);
}

test "columns_self_loop: edge to self treated as back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A NOT gate whose output feeds its own input — degenerate cycle of length
    // one. The self-edge is the only edge; the DFS classifies it as a back
    // edge and the node is its own back-edge destination, so the gutter rule
    // bumps it from col 0 to col 1. Result: col 0 empty (reserved for the
    // self-loop's wire arc), node at col 1.
    const self = makeNode(0, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    });

    const nodes = [_]VirtualNode{self};
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 1 };

    const cols = try assignColumns(a, graph);
    try std.testing.expectEqual(@as(u32, 2), cols.num_columns);
    try std.testing.expectEqual(@as(u32, 1), cols.column_of[0]);
}

test "columns_sr_latch: cross-coupled cells stay finite" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Cross-coupled NOR-style latch (SR-latch shape):
    //   qcell = AND(nr.out, nqbar.out)
    //   qbcell = AND(ns.out, nq.out)
    //   nq = NOT(qcell.out)
    //   nqbar = NOT(qbcell.out)
    // Cycle: qcell → nq → qbcell → nqbar → qcell.
    //
    // Pre-fix: every fixed-point iteration bumped each cycle node's column
    // until the (n + 1) cap fired, leaving qcell/qbcell/nq/nqbar at columns
    // ≥ 10 and outputs forced even further right. After the back-edge
    // pre-pass, the DAG residual has bounded longest path and num_columns
    // stays small (≤ 7 for this 10-node graph).
    const s_pin = makeNode(0, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 3, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const r_pin = makeNode(1, .{ .primitive = .input_pin }, &.{}, &.{
        .{ .dst_id = 2, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const nr = makeNode(2, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 1, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 4, .src_port = SRC_OUT, .dst_port = DST_A },
    });
    const ns = makeNode(3, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 0, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 5, .src_port = SRC_OUT, .dst_port = DST_A },
    });
    const qcell = makeNode(4, .{ .primitive = .and_gate }, &.{
        .{ .src_id = 2, .src_port = SRC_OUT, .dst_port = DST_A },
        .{ .src_id = 7, .src_port = SRC_OUT, .dst_port = DST_B },
    }, &.{
        .{ .dst_id = 6, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 8, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const qbcell = makeNode(5, .{ .primitive = .and_gate }, &.{
        .{ .src_id = 3, .src_port = SRC_OUT, .dst_port = DST_A },
        .{ .src_id = 6, .src_port = SRC_OUT, .dst_port = DST_B },
    }, &.{
        .{ .dst_id = 7, .src_port = SRC_OUT, .dst_port = DST_IN },
        .{ .dst_id = 9, .src_port = SRC_OUT, .dst_port = DST_IN },
    });
    const nq = makeNode(6, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 4, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 5, .src_port = SRC_OUT, .dst_port = DST_B },
    });
    const nqbar = makeNode(7, .{ .primitive = .not_gate }, &.{
        .{ .src_id = 5, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{
        .{ .dst_id = 4, .src_port = SRC_OUT, .dst_port = DST_B },
    });
    const q_out = makeNode(8, .{ .primitive = .output_pin }, &.{
        .{ .src_id = 4, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});
    const qbar_out = makeNode(9, .{ .primitive = .output_pin }, &.{
        .{ .src_id = 5, .src_port = SRC_OUT, .dst_port = DST_IN },
    }, &.{});

    const nodes = [_]VirtualNode{ s_pin, r_pin, nr, ns, qcell, qbcell, nq, nqbar, q_out, qbar_out };
    const graph = VirtualGraph{ .nodes = &nodes, .next_id = 10 };

    const cols = try assignColumns(a, graph);

    // Sanity: input pins anchored at 0; sinks anchored at the right edge.
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[0]); // s
    try std.testing.expectEqual(@as(u32, 0), cols.column_of[1]); // r
    try std.testing.expectEqual(cols.num_columns - 1, cols.column_of[8]); // q
    try std.testing.expectEqual(cols.num_columns - 1, cols.column_of[9]); // qbar

    // Total columns must be bounded by the actual DAG depth, not by the
    // iteration cap. With one back edge removed the longest path is at most
    // 6 hops (s → ns → qbcell → nqbar → qcell → nq → ... or the reverse),
    // so num_columns ≤ 7.
    try std.testing.expect(cols.num_columns <= 7);
}
