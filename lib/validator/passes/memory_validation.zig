const std = @import("std");
const ir = @import("ir_types");

/// `BitVecState` carries at most 64 bits.
pub const MAX_DATA_WIDTH: u8 = 64;
/// 65,536 words; keeps a memory's cell planes at ~1 MiB.
pub const MAX_ADDR_WIDTH: u8 = 16;

pub const Side = enum { from, to };

/// Single source of truth for memory port widths. `side == .to` answers
/// "what width does this input port expect"; `side == .from` answers "what
/// width does this output port drive". Unknown ports yield null (the port
/// validity pass reports them separately).
pub fn memoryPortWidth(mem: ir.Memory, port: []const u8, side: Side) ?u8 {
    return switch (side) {
        .from => if (std.mem.eql(u8, port, "out")) mem.data_width else null,
        .to => if (std.mem.eql(u8, port, "addr"))
            mem.addr_width
        else if (mem.mode == .ram and std.mem.eql(u8, port, "din"))
            mem.data_width
        else if (mem.mode == .ram and (std.mem.eql(u8, port, "we") or std.mem.eql(u8, port, "clk")))
            1
        else
            null,
    };
}

test "memoryPortWidth contract" {
    const rom = ir.Memory{ .mode = .rom, .data_width = 8, .addr_width = 4, .arg_count = 2, .type_width_given = false };
    try std.testing.expectEqual(@as(?u8, 4), memoryPortWidth(rom, "addr", .to));
    try std.testing.expectEqual(@as(?u8, 8), memoryPortWidth(rom, "out", .from));
    try std.testing.expectEqual(@as(?u8, null), memoryPortWidth(rom, "din", .to));
    try std.testing.expectEqual(@as(?u8, null), memoryPortWidth(rom, "we", .to));
    try std.testing.expectEqual(@as(?u8, null), memoryPortWidth(rom, "clk", .to));
    try std.testing.expectEqual(@as(?u8, null), memoryPortWidth(rom, "addr", .from));

    const ram = ir.Memory{ .mode = .ram, .data_width = 12, .addr_width = 2, .arg_count = 2, .type_width_given = false };
    try std.testing.expectEqual(@as(?u8, 2), memoryPortWidth(ram, "addr", .to));
    try std.testing.expectEqual(@as(?u8, 12), memoryPortWidth(ram, "din", .to));
    try std.testing.expectEqual(@as(?u8, 1), memoryPortWidth(ram, "we", .to));
    try std.testing.expectEqual(@as(?u8, 1), memoryPortWidth(ram, "clk", .to));
    try std.testing.expectEqual(@as(?u8, 12), memoryPortWidth(ram, "out", .from));
    try std.testing.expectEqual(@as(?u8, null), memoryPortWidth(ram, "in", .to));
}
