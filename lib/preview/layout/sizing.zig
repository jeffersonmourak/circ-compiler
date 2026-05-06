const std = @import("std");
const full_format = @import("full_format");

pub const PrimitiveSize = struct {
    width: u32,
    height: u32,
};

/// Per-kind cell sizes. Values locked at Phase 2 for stable golden coordinates;
/// Phase 3 may rev the table and re-capture goldens. `wire` is sentinel-zero
/// because wires are collapsed before placement.
pub const primitive_sizing = std.EnumArray(full_format.ComponentKind, PrimitiveSize).init(.{
    .input_pin = .{ .width = 6, .height = 1 },
    .not_gate = .{ .width = 5, .height = 3 },
    .led = .{ .width = 3, .height = 3 },
    .and_gate = .{ .width = 5, .height = 3 },
    .wire = .{ .width = 0, .height = 0 },
    .output_pin = .{ .width = 6, .height = 1 },
});

/// Opaque-mode subcircuit boxes size to fit `[<subcircuit>:<alias>]` plus padding.
pub fn macroSize(label_width: usize) PrimitiveSize {
    const padded = @max(@as(u32, 8), @as(u32, @intCast(label_width)) + 2);
    return .{ .width = padded, .height = 3 };
}

test "sizing: primitive table values match locked spec" {
    try std.testing.expectEqual(@as(u32, 6), primitive_sizing.get(.input_pin).width);
    try std.testing.expectEqual(@as(u32, 1), primitive_sizing.get(.input_pin).height);
    try std.testing.expectEqual(@as(u32, 5), primitive_sizing.get(.not_gate).width);
    try std.testing.expectEqual(@as(u32, 3), primitive_sizing.get(.not_gate).height);
    try std.testing.expectEqual(@as(u32, 5), primitive_sizing.get(.and_gate).width);
    try std.testing.expectEqual(@as(u32, 3), primitive_sizing.get(.led).width);
    try std.testing.expectEqual(@as(u32, 0), primitive_sizing.get(.wire).width);
}

test "sizing: macroSize floors at 8 wide" {
    try std.testing.expectEqual(@as(u32, 8), macroSize(2).width);
    try std.testing.expectEqual(@as(u32, 8), macroSize(5).width);
    try std.testing.expectEqual(@as(u32, 12), macroSize(10).width);
    try std.testing.expectEqual(@as(u32, 3), macroSize(50).height);
}
