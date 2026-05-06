const std = @import("std");
const full_format = @import("full_format");
const layout = @import("layout");
const collapse_stage = @import("collapse");
const columns_stage = @import("columns");
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
    const cols = try columns_stage.assignColumns(arena, graph);
    const rows = try rows_stage.assignRows(arena, graph, cols);
    const placed = try place_stage.place(arena, graph, cols, rows);
    const route_result = try route_stage.route(arena, graph, placed);
    return .{
        .width = route_result.width,
        .height = route_result.height,
        .components = placed,
        .wires = route_result.wires,
    };
}
