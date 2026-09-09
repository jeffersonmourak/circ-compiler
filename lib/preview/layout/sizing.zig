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
    // Slice and concat are collapsed alongside wires in `collapse.zig`
    // so they never reach placement. The zero entries are sentinels;
    // placement code that looked at them would draw empty boxes.
    .slice = .{ .width = 0, .height = 0 },
    .concat = .{ .width = 0, .height = 0 },
    // Memories size dynamically via `memorySize` (the label carries the
    // instance name and widths); zero sentinels here.
    .rom = .{ .width = 0, .height = 0 },
    .ram = .{ .width = 0, .height = 0 },
});

/// Decimal-digit count of `n` for label-length math (e.g. 1 -> 1, 64 -> 2).
fn digitsOf(n: u8) usize {
    var v: u32 = n;
    var d: usize = 1;
    while (v >= 10) : (v /= 10) d += 1;
    return d;
}

/// Width-annotation suffix length for the given signal width: `[N]` for
/// widths > 1, empty for scalar pins.
pub fn widthAnnotationLen(signal_width: u8) usize {
    if (signal_width <= 1) return 0;
    return 2 + digitsOf(signal_width); // '[' + N + ']'
}

/// LED box size. Width-1 keeps the legacy 5×3 dimensions so existing scalar
/// goldens are byte-identical. Wider LEDs need room for their display label:
/// numeric mode is "0x" + ceil(width/4) `?` chars; indicator mode (widths
/// 2..7 with --expand-display) is one `·` per bit.
pub fn ledSize(signal_width: u8, expand_display: bool) PrimitiveSize {
    if (signal_width <= 1) return primitive_sizing.get(.led);
    const label_len: usize = if (expand_display and signal_width < 8)
        signal_width // one '·' per bit
    else
        2 + (@as(usize, signal_width) + 3) / 4; // "0x" + nibbles
    const min_width: u32 = 5;
    const padded = @max(min_width, @as(u32, @intCast(label_len)) + 4);
    return .{ .width = padded, .height = 3 };
}

/// Pin (input or output) box size. Width grows with the pin name to keep the
/// label centered with at least one cell of padding on each side; floor at 5
/// so isolated short-name pins still look box-shaped (`╭───╮ │ a │ ╰───╯`).
/// Multi-bit pins get extra room for the trailing `[N]` annotation.
pub fn pinSize(name_len: usize, signal_width: u8) PrimitiveSize {
    const min_width: u32 = 5;
    const annot = widthAnnotationLen(signal_width);
    const padded = @max(min_width, @as(u32, @intCast(name_len + annot)) + 4);
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

/// Length of a memory box label `<kind> <name>[W,A]`.
pub fn memoryLabelLen(kind_name_len: usize, name_len: usize, data_width: u8, addr_width: u8) usize {
    return kind_name_len + 1 + name_len + 1 + digitsOf(data_width) + 1 + digitsOf(addr_width) + 1;
}

/// Memory box size: wide enough for its label like a pin, and tall enough
/// for one input port per odd border row like a macro box (rom: 3 rows,
/// ram: 9 rows).
pub fn memorySize(label_len: usize, input_count: u32) PrimitiveSize {
    const min_width: u32 = 5;
    const padded_w = @max(min_width, @as(u32, @intCast(label_len)) + 4);
    const needed_h: u32 = if (input_count <= 1) 3 else 2 * input_count + 1;
    return .{ .width = padded_w, .height = needed_h };
}

test "sizing: memorySize follows the pin width rule and the macro height rule" {
    try std.testing.expectEqual(@as(u32, 17), memorySize(13, 1).width);
    try std.testing.expectEqual(@as(u32, 3), memorySize(13, 1).height);
    try std.testing.expectEqual(@as(u32, 17), memorySize(13, 4).width);
    try std.testing.expectEqual(@as(u32, 9), memorySize(13, 4).height);
    try std.testing.expectEqual(@as(u32, 5), memorySize(0, 1).width);
    // "rom code[8,4]" is 13 chars.
    try std.testing.expectEqual(@as(usize, 13), memoryLabelLen(3, 4, 8, 4));
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
    try std.testing.expectEqual(@as(u32, 5), pinSize(0, 1).width);
    try std.testing.expectEqual(@as(u32, 5), pinSize(1, 1).width);
    try std.testing.expectEqual(@as(u32, 7), pinSize(3, 1).width);
    try std.testing.expectEqual(@as(u32, 14), pinSize(10, 1).width);
    try std.testing.expectEqual(@as(u32, 3), pinSize(0, 1).height);
}

test "sizing: pinSize accounts for [N] annotation at width > 1" {
    // Single-digit widths add "[N]" = 3 chars; double-digit "[NN]" = 4.
    try std.testing.expectEqual(@as(u32, 8), pinSize(1, 4).width); // "a[4]" → 1 + 3 = 4 chars + 4 padding
    try std.testing.expectEqual(@as(u32, 9), pinSize(2, 4).width); // "ab[4]"
    try std.testing.expectEqual(@as(u32, 9), pinSize(1, 64).width); // "a[64]" → 5 chars + 4 padding
    // Width 1 stays as-is — no annotation.
    try std.testing.expectEqual(@as(u32, 5), pinSize(1, 1).width);
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
