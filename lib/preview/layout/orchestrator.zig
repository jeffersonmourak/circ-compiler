const std = @import("std");
const full_format = @import("full_format");
const layout = @import("layout");
const collapse_stage = @import("collapse");
const layering_stage = @import("layering");
const rows_stage = @import("rows");
const place_stage = @import("place");
const route_stage = @import("route");

/// Phase 2 slice 6b orchestrator: composes the five layout stages into a single
/// `LayoutGrid`. Used by the integration tests and (eventually) Phase 3's CLI
/// preview path. Lives in its own module to avoid a cyclic import in `layout.zig`
/// (which only owns types; stages already import `layout` for `LayoutOptions`).
pub fn build(
    arena: std.mem.Allocator,
    topology: full_format.FullTopology,
    opts: layout.LayoutOptions,
) !layout.LayoutGrid {
    const graph = try collapse_stage.collapse(arena, topology, opts);
    // Phase 1 of the layout rewrite: layers (with dummies for long edges)
    // replace columns; the old row, place and route stages still consume
    // the ColumnAssignment view over the real nodes.
    const layered = try layering_stage.layer(arena, graph);
    const cols = try layering_stage.toColumns(arena, layered, graph.nodes.len);
    const rows = try rows_stage.assignRows(arena, graph, cols);
    const placed = try place_stage.place(arena, graph, cols, rows, opts);
    const route_result = try route_stage.route(arena, graph, placed);
    return .{
        .width = route_result.width,
        .height = route_result.height,
        .components = placed,
        .wires = route_result.wires,
    };
}
