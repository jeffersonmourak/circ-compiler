const std = @import("std");

pub const MAGIC: [4]u8 = .{ 'C', 'I', 'R', 'C' };
pub const VERSION: u8 = 0x03;

pub const ComponentKind = enum(u8) {
    input_pin = 0,
    not_gate = 1,
    and_gate = 2,
    wire = 3,
    led = 4,
    output_pin = 5,
    // S5.1: bit-range extraction. Min `ComponentRecord` for a slice carries
    // two extra trailing bytes (`lo`, `hi`) after the fixed `(id, kind,
    // width)` prefix, dispatched by kind. Older readers reading a slice
    // record without knowing the suffix layout would mis-frame the next
    // record — but the only reader of this format is the embedded
    // runtime interpreter, which is bumped in lockstep.
    slice = 6,
    // S5.2: N-input bit concatenation. Concat itself adds no trailing
    // bytes to the `ComponentRecord`; its operand connectivity rides on
    // the existing connections table, where the port byte is the operand
    // index (0..N) instead of a `PortName` value. Disambiguation is
    // context-dependent: the interpreter checks `to_comp.kind == concat`
    // before treating the port byte as an operand index.
    concat = 7,
    // v03: native memories. The engine has one `memory` kind with a mode;
    // the wire keeps two kinds. A memory record carries one trailing byte
    // (the address width) after the fixed prefix, dispatched by kind like
    // slice's `(lo, hi)`. Contents never travel in the topology — they are
    // loaded at runtime.
    rom = 8,
    ram = 9,
};

pub const PortName = enum(u8) {
    in = 0,
    a = 1,
    b = 2,
    out = 3,
    // v03: memory input ports.
    addr = 4,
    din = 5,
    we = 6,
    clk = 7,
};

pub const ComponentRecord = extern struct {
    id: u32,
    kind: u8,
    width: u8,
    /// Kind-dispatched aux bytes. Present in the encoded payload only when
    /// `kind` calls for them: `slice` carries trailing `(lo, hi)`, and
    /// `rom`/`ram` carry `aux_lo` alone as the address width. Default zero
    /// keeps existing kinds' records at the historical 6-byte size on the
    /// wire.
    aux_lo: u8 = 0,
    aux_hi: u8 = 0,
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
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(ComponentKind.slice));
    try std.testing.expectEqual(@as(u8, 7), @intFromEnum(ComponentKind.concat));
    try std.testing.expectEqual(@as(u8, 8), @intFromEnum(ComponentKind.rom));
    try std.testing.expectEqual(@as(u8, 9), @intFromEnum(ComponentKind.ram));
    try std.testing.expectEqual(@as(u8, 0x03), VERSION);
}

test "format: PortName values are stable" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(PortName.in));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(PortName.a));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(PortName.b));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(PortName.out));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(PortName.addr));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(PortName.din));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(PortName.we));
    try std.testing.expectEqual(@as(u8, 7), @intFromEnum(PortName.clk));
}