const std = @import("std");
const full_format = @import("full_format");
const layout = @import("layout");
const collapse_stage = @import("collapse");
const layering_stage = @import("layering");
const ordering_stage = @import("ordering");
const types = @import("layout_types");
const place_stage = @import("place");
const route_stage = @import("route");

/// Phase 2 slice 6b orchestrator: composes the five layout stages into a single
/// `LayoutGrid`. Used by the integration tests and (eventually) Phase 3's CLI
/// preview path. Lives in its own module to avoid a cyclic import in `layout.zig`
/// (which only owns types; stages already import `layout` for `LayoutOptions`).
/// Every intermediate result, for the tests that measure the stages.
pub const Stages = struct {
    graph: types.VirtualGraph,
    layered: types.LayeredGraph,
    cols: types.ColumnAssignment,
    rows: types.RowAssignment,
    ordering: types.Ordering,
    grid: layout.LayoutGrid,
};

pub fn build(
    arena: std.mem.Allocator,
    topology: full_format.FullTopology,
    opts: layout.LayoutOptions,
) !layout.LayoutGrid {
    return (try buildStages(arena, topology, opts)).grid;
}

pub fn buildStages(
    arena: std.mem.Allocator,
    topology: full_format.FullTopology,
    opts: layout.LayoutOptions,
) !Stages {
    const graph = try collapse_stage.collapse(arena, topology, opts);
    // Phase 1 of the layout rewrite: layers (with dummies for long edges)
    // and a port-aware ordering replace columns and rows; the old place and
    // route stages still consume the column/row views over the real nodes.
    const layered = try layering_stage.layer(arena, graph);
    const cols = try layering_stage.toColumns(arena, layered, graph.nodes.len);
    const ordering = try ordering_stage.order(arena, graph, layered);
    const rows = try ordering_stage.toRows(arena, layered, ordering, graph.nodes.len);
    const placed = try place_stage.place(arena, graph, cols, rows, opts);
    const route_result = try route_stage.route(arena, graph, placed);
    return .{
        .graph = graph,
        .layered = layered,
        .cols = cols,
        .rows = rows,
        .ordering = ordering,
        .grid = .{
            .width = route_result.width,
            .height = route_result.height,
            .components = placed,
            .wires = route_result.wires,
        },
    };
}
