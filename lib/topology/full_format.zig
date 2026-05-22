const std = @import("std");
const format = @import("format");

pub const FULL_MAGIC: [4]u8 = .{ 'C', 'I', 'R', 'F' };
pub const FULL_VERSION: u8 = 0x02;

pub const ComponentKind = format.ComponentKind;
pub const PortName = format.PortName;
pub const FullConnectionRecord = format.ConnectionRecord;

pub const OriginFrame = struct {
    alias: []const u8,
    subcircuit: []const u8,
    target_file: u32,
};

pub const FullComponentRecord = struct {
    id: u32,
    kind: ComponentKind,
    width: u8,
    name: []const u8,
    origin: []const OriginFrame,
};

pub const FullTopology = struct {
    components: []const FullComponentRecord,
    connections: []const FullConnectionRecord,

    pub fn deinit(self: *FullTopology, allocator: std.mem.Allocator) void {
        for (self.components) |comp| {
            allocator.free(comp.name);
            for (comp.origin) |frame| {
                allocator.free(frame.alias);
                allocator.free(frame.subcircuit);
            }
            allocator.free(comp.origin);
        }
        allocator.free(self.components);
        allocator.free(self.connections);
    }
};

test "full_format: magic and version are stable" {
    try std.testing.expectEqualSlices(u8, "CIRF", &FULL_MAGIC);
    try std.testing.expectEqual(@as(u8, 0x02), FULL_VERSION);
}

test "full_format: kind values mirror min payload" {
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.input_pin), @intFromEnum(ComponentKind.input_pin));
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.not_gate), @intFromEnum(ComponentKind.not_gate));
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.and_gate), @intFromEnum(ComponentKind.and_gate));
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.wire), @intFromEnum(ComponentKind.wire));
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.led), @intFromEnum(ComponentKind.led));
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.output_pin), @intFromEnum(ComponentKind.output_pin));
}
