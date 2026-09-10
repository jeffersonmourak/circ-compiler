const std = @import("std");
const full_format = @import("full_format");
const layout = @import("layout");

pub const NodeKind = layout.NodeKind;

pub const InputEdge = struct {
    src_id: u32,
    src_port: u8,
    dst_port: u8,
};

pub const OutputEdge = struct {
    dst_id: u32,
    src_port: u8,
    dst_port: u8,
};

pub const VirtualNode = struct {
    id: u32,
    kind: NodeKind,
    name: []const u8,
    origin: []const full_format.OriginFrame,
    inputs: []const InputEdge,
    outputs: []const OutputEdge,
    /// The signal width of this component, copied from the topology's
    /// per-component width byte. Default 1 so test fixtures that build
    /// `VirtualNode` literals without setting this stay scalar.
    signal_width: u8 = 1,
    /// Address width of a memory node (from the topology's `Aux.memory`);
    /// 0 for every other kind.
    addr_width: u8 = 0,
};

pub const VirtualGraph = struct {
    nodes: []const VirtualNode,
    next_id: u32,
};

pub const ColumnAssignment = struct {
    column_of: []const u32,
    num_columns: u32,
};

pub const RowAssignment = struct {
    row_of: []const u32,
    num_rows: u32,
};

// ---------- Layered graph (Phase 1 of the layout rewrite) ----------

/// A node of the layered graph: a real `VirtualGraph` node or a dummy that
/// carries a long edge through an intermediate layer.
pub const LayerNode = struct {
    /// Index into `VirtualGraph.nodes` for a real node; null for a dummy.
    real: ?usize,
    layer: u32,
    /// For a dummy: index into `LayeredGraph.originals` of the edge it carries.
    carries: ?u32,
};

/// One wire as collapse produced it, in `VirtualGraph` node order and each
/// node's `outputs` order.
pub const OriginalEdge = struct {
    src: usize, // VirtualGraph node index
    src_port: u8,
    dst: usize,
    dst_port: u8,
    /// Closes a cycle: excluded from layering and ordering, routed as a
    /// return lane.
    back: bool,
};

/// A layer-adjacent segment: `src` sits in layer `L`, `dst` in `L + 1`.
/// Back edges are not segmented and never appear here.
pub const LayerEdge = struct {
    src: u32, // LayerNode index
    dst: u32,
    src_port: u8, // 0 on a dummy source
    dst_port: u8, // 0 on a dummy sink
    original: u32, // index into `LayeredGraph.originals`
};

pub const LayeredGraph = struct {
    /// Real nodes first, in `VirtualGraph` order, then dummies in
    /// `originals` order and, within one edge, by layer.
    nodes: []const LayerNode,
    /// In `originals` order, then by segment.
    edges: []const LayerEdge,
    originals: []const OriginalEdge,
    num_layers: u32,
};

pub const Ordering = struct {
    /// Per layer, `LayerNode` indices top to bottom.
    order: []const []const u32,
    /// Position of every `LayerNode` inside its layer (the inverse of `order`).
    pos: []const u32,
    /// Sweep rounds the ordering ran (observable for tests).
    rounds: u8 = 0,
};

// ---------- Coordinates (Phase 2 of the layout rewrite) ----------

pub const ChannelWidths = struct {
    /// Width in cells of the gap after layer `k` (source marker, sink marker
    /// and every track). Indexed `0 .. num_layers`; the last entry is unused.
    after: []const u32,
};

pub const Coords = struct {
    /// Per LayerNode: the top-left cell of a real node's box; a dummy's cell.
    x: []u32,
    y: []u32,
    /// Per LayerNode: box size (a dummy is 0 wide, 1 tall).
    w: []u32,
    h: []u32,
    /// Per layer: left edge and width of its widest box.
    layer_x: []u32,
    layer_w: []u32,
    /// Per layer: the first cell of the channel after it.
    channel_x: []u32,
    width: u32,
    height: u32,
};

test "types: pipeline structs compile" {
    comptime {
        std.debug.assert(@typeInfo(VirtualNode).@"struct".fields.len == 8);
        std.debug.assert(@typeInfo(VirtualGraph).@"struct".fields.len == 2);
        std.debug.assert(@typeInfo(ColumnAssignment).@"struct".fields.len == 2);
        std.debug.assert(@typeInfo(RowAssignment).@"struct".fields.len == 2);
        std.debug.assert(@typeInfo(LayerNode).@"struct".fields.len == 3);
        std.debug.assert(@typeInfo(OriginalEdge).@"struct".fields.len == 5);
        std.debug.assert(@typeInfo(LayerEdge).@"struct".fields.len == 5);
        std.debug.assert(@typeInfo(LayeredGraph).@"struct".fields.len == 4);
        std.debug.assert(@typeInfo(Ordering).@"struct".fields.len == 3);
        std.debug.assert(@typeInfo(ChannelWidths).@"struct".fields.len == 1);
        std.debug.assert(@typeInfo(Coords).@"struct".fields.len == 9);
    }
}
