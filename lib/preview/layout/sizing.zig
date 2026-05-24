const std = @import("std");
const full_format = @import("full_format");

pub const PrimitiveSize = struct {
    width: u32,
    height: u32,
};

/// Per-kind cell sizes for fixed-size primitives. Pin sizes are computed
/// dynamically via `pinSize` since they depend on the variable-length pin
/// name. `wire` is sentinel-zero because wires are collapsed before
/// placement; `input_pin` / `output_pin` entries are zero sentinels too —
/// callers must route pins through `pinSize`.
pub const primitive_sizing = std.EnumArray(full_format.ComponentKind, PrimitiveSize).init(.{
    .input_pin = .{ .width = 0, .height = 0 },
    .not_gate = .{ .width = 5, .height = 3 },
    .led = .{ .width = 5, .height = 3 },
    .and_gate = .{ .width = 5, .height = 5 },
    .wire = .{ .width = 0, .height = 0 },
    .output_pin = .{ .width = 0, .height = 0 },
    // Slice components are collapsed alongside wires in `collapse.zig` so
    // they never reach placement. The zero entry is a sentinel; placement
    // code that looks at a slice would draw an empty box.
    .slice = .{ .width = 0, .height = 0 },
});

/// Pin (input or output) box size. Width grows with the pin name to keep the
/// label centered with at least one cell of padding on each side; floor at 5
/// so isolated short-name pins still look box-shaped (`╭───╮ │ a │ ╰───╯`).
pub fn pinSize(name_len: usize) PrimitiveSize {
    const min_width: u32 = 5;
    const padded = @max(min_width, @as(u32, @intCast(name_len)) + 4);
    return .{ .width = padded, .height = 3 };
}

/// Opaque-mode subcircuit boxes size to fit `[<subcircuit>:<alias>]` plus
/// padding. Height grows with the active input-port count so each port lands
/// on a non-corner border row (every other row, starting at y+1).
pub fn macroSize(label_width: usize, input_count: u32) PrimitiveSize {
    const padded_w = @max(@as(u32, 8), @as(u32, @intCast(label_width)) + 2);
    const min_h: u32 = 3;
    const needed_h: u32 = if (input_count <= 1) min_h else 2 * input_count + 1;
    return .{ .width = padded_w, .height = needed_h };
}

test "sizing: primitive table values match locked spec" {
    try std.testing.expectEqual(@as(u32, 5), primitive_sizing.get(.not_gate).width);
    try std.testing.expectEqual(@as(u32, 3), primitive_sizing.get(.not_gate).height);
    try std.testing.expectEqual(@as(u32, 5), primitive_sizing.get(.and_gate).width);
    try std.testing.expectEqual(@as(u32, 5), primitive_sizing.get(.and_gate).height);
    try std.testing.expectEqual(@as(u32, 5), primitive_sizing.get(.led).width);
    try std.testing.expectEqual(@as(u32, 3), primitive_sizing.get(.led).height);
    try std.testing.expectEqual(@as(u32, 0), primitive_sizing.get(.wire).width);
    // Pins are sentinels; real size comes from pinSize.
    try std.testing.expectEqual(@as(u32, 0), primitive_sizing.get(.input_pin).width);
    try std.testing.expectEqual(@as(u32, 0), primitive_sizing.get(.output_pin).width);
}

test "sizing: pinSize floors at 5 wide and grows with name length" {
    try std.testing.expectEqual(@as(u32, 5), pinSize(0).width);
    try std.testing.expectEqual(@as(u32, 5), pinSize(1).width);
    try std.testing.expectEqual(@as(u32, 7), pinSize(3).width);
    try std.testing.expectEqual(@as(u32, 14), pinSize(10).width);
    try std.testing.expectEqual(@as(u32, 3), pinSize(0).height);
}

test "sizing: macroSize floors width at 8 and scales height with input count" {
    try std.testing.expectEqual(@as(u32, 8), macroSize(2, 1).width);
    try std.testing.expectEqual(@as(u32, 8), macroSize(5, 1).width);
    try std.testing.expectEqual(@as(u32, 12), macroSize(10, 1).width);
    try std.testing.expectEqual(@as(u32, 3), macroSize(50, 0).height);
    try std.testing.expectEqual(@as(u32, 3), macroSize(50, 1).height);
    try std.testing.expectEqual(@as(u32, 5), macroSize(50, 2).height);
    try std.testing.expectEqual(@as(u32, 7), macroSize(50, 3).height);
}
