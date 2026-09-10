const std = @import("std");
const full_format = @import("full_format");
const layout = @import("layout");
const collapse_stage = @import("collapse");
const layering_stage = @import("layering");
const ordering_stage = @import("ordering");
const types = @import("layout_types");
const coords_stage = @import("coords");
const channels_stage = @import("channels");

/// Phase 2 slice 6b orchestrator: composes the five layout stages into a single
/// `LayoutGrid`. Used by the integration tests and (eventually) Phase 3's CLI
/// preview path. Lives in its own module to avoid a cyclic import in `layout.zig`
/// (which only owns types; stages already import `layout` for `LayoutOptions`).
/// Every intermediate result, for the tests that measure the stages.
pub const Stages = struct {
    graph: types.VirtualGraph,
    layered: types.LayeredGraph,
    ordering: types.Ordering,
    coords: types.Coords,
    plan: types.RoutePlan,
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
    // The layout rewrite: layers (with dummies for long edges), a port-aware
    // ordering, per-node rows, then channel routing in two passes — the plan
    // on stub-width columns decides tracks, doglegs, spacer rows and return
    // lanes (rows only), the columns are laid out again from the measured
    // gap widths, and the wires are emitted on those.
    const layered = try layering_stage.layer(arena, graph);
    const ordering = try ordering_stage.order(arena, graph, layered);
    var coords = try coords_stage.assign(arena, graph, layered, ordering, opts, try coords_stage.stubWidths(arena, layered.num_layers));
    const plan = try channels_stage.plan(arena, graph, layered, &coords);
    coords_stage.relayoutColumns(&coords, layered, try channels_stage.widths(arena, plan, layered.num_layers));
    const placed = try coords_stage.toPlaced(arena, graph, layered, coords, opts);
    const route_result = try channels_stage.emit(arena, graph, layered, coords, plan);
    return .{
        .graph = graph,
        .layered = layered,
        .ordering = ordering,
        .coords = coords,
        .plan = plan,
        .grid = .{
            .width = route_result.width,
            .height = route_result.height,
            .components = placed,
            .wires = route_result.wires,
        },
    };
}
