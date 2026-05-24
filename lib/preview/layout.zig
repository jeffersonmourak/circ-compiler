const std = @import("std");
const full_format = @import("full_format");

pub const PortCoord = struct {
    x: u32,
    y: u32,
};

pub const PortSlot = struct {
    port_name: []const u8,
    coord: PortCoord,
};

pub const NodeKind = union(enum) {
    primitive: full_format.ComponentKind,
    subcircuit: []const u8,
};

pub const PlacedComponent = struct {
    id: u32,
    kind: NodeKind,
    name: []const u8,
    origin: []const full_format.OriginFrame,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    in_ports: []const PortSlot,
    out_port: PortCoord,
    /// Signal bit-width carried by this component, threaded from the
    /// topology's per-component width byte. Renderers append a `[N]`
    /// annotation to the pin label when this is > 1. Default 1 so
    /// scalar test fixtures don't need to set the field explicitly.
    signal_width: u8 = 1,
    /// Pre-composed display label, arena-owned, used by pin renderers.
    /// Equals `name` for scalar pins and `name[N]` for multi-bit pins.
    /// The canvas stores slice pointers (not copies), so the label
    /// memory must live at least as long as the canvas. Setting this
    /// at placement time guarantees that lifetime.
    display_label: []const u8 = "",
};

pub const Segment = struct {
    from: PortCoord,
    to: PortCoord,
};

pub const RoutedWire = struct {
    src_id: u32,
    src_port: u8,
    dst_id: u32,
    dst_port: u8,
    segments: []const Segment,
    crossings: []const PortCoord,
};

pub const LayoutGrid = struct {
    width: u32,
    height: u32,
    components: []const PlacedComponent,
    wires: []const RoutedWire,
};

pub const LayoutOptions = struct {
    expand_macros: bool = false,
    /// Honor `--expand-display`: render multi-bit LEDs (widths 2..7) as a
    /// row of indicator glyphs instead of a single hex display. Widths >=8
    /// silently fall back to numeric — the render pass emits a warning to
    /// stderr the first time it draws such an LED.
    expand_display: bool = false,
};

/// Slice 1 stub. The five-stage pipeline (collapse → columns → rows → place → route)
/// lands across slices 2–6. Until then any caller hitting this gets a clear error.
pub fn layout(
    allocator: std.mem.Allocator,
    topology: full_format.FullTopology,
    opts: LayoutOptions,
) !LayoutGrid {
    _ = allocator;
    _ = topology;
    _ = opts;
    return error.NotImplemented;
}

test "layout: public types compile and have expected fields" {
    // Comptime sanity check: each type's @typeInfo reflects the documented shape.
    comptime {
        const port_coord_info = @typeInfo(PortCoord).@"struct";
        std.debug.assert(port_coord_info.fields.len == 2);

        const placed_info = @typeInfo(PlacedComponent).@"struct";
        std.debug.assert(placed_info.fields.len == 12);

        const layout_grid_info = @typeInfo(LayoutGrid).@"struct";
        std.debug.assert(layout_grid_info.fields.len == 4);

        const node_kind_info = @typeInfo(NodeKind);
        std.debug.assert(node_kind_info == .@"union");
        std.debug.assert(node_kind_info.@"union".fields.len == 2);
    }
}

test "layout: stub returns NotImplemented" {
    const empty = full_format.FullTopology{ .components = &.{}, .connections = &.{} };
    try std.testing.expectError(error.NotImplemented, layout(std.testing.allocator, empty, .{}));
}
