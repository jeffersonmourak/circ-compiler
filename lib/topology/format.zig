const std = @import("std");

pub const MAGIC: [4]u8 = .{ 'C', 'I', 'R', 'C' };
pub const VERSION: u8 = 0x01;

pub const ComponentKind = enum(u8) {
    input_pin = 0,
    not_gate = 1,
    and_gate = 2,
    wire = 3,
    led = 4,
    output_pin = 5,
};

pub const PortName = enum(u8) {
    in = 0,
    a = 1,
    b = 2,
    out = 3,
};

pub const ComponentRecord = extern struct {
    id: u32,
    kind: u8,
};

pub const ConnectionRecord = extern struct {
    from_id: u32,
    to_id: u32,
    port: u8,
};

test "format: ComponentKind values are stable" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ComponentKind.input_pin));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ComponentKind.not_gate));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ComponentKind.and_gate));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ComponentKind.wire));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(ComponentKind.led));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(ComponentKind.output_pin));
}

test "format: PortName values are stable" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(PortName.in));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(PortName.a));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(PortName.b));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(PortName.out));
}