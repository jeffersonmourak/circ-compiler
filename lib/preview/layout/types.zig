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

test "types: pipeline structs compile" {
    comptime {
        std.debug.assert(@typeInfo(VirtualNode).@"struct".fields.len == 8);
        std.debug.assert(@typeInfo(VirtualGraph).@"struct".fields.len == 2);
        std.debug.assert(@typeInfo(ColumnAssignment).@"struct".fields.len == 2);
        std.debug.assert(@typeInfo(RowAssignment).@"struct".fields.len == 2);
    }
}
