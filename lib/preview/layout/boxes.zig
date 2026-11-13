//! Box geometry per node: size, display label and port coordinates. Moved
//! out of `place.zig` unchanged in behaviour (Phase 2 of the layout rewrite)
//! so the coordinate stage that replaces placement can share them. Port rows
//! come from `ports.zig`; the coordinates are the table's rows plus the box
//! origin, one cell outside the border (`x - 1` for inputs, `x + width` for
//! the output).
const std = @import("std");
const full_format = @import("full_format");
const layout = @import("layout");
const types = @import("layout_types");
const sizing = @import("sizing");
const ports = @import("ports");

const VirtualNode = types.VirtualNode;
const PortSlot = layout.PortSlot;
const PortCoord = layout.PortCoord;

pub const PrimitiveSize = sizing.PrimitiveSize;

pub const Ports = struct {
    in_ports: []const PortSlot,
    /// The first (for a primitive, the only) output port.
    out_port: PortCoord,
    /// Every output port: none for a sink, one for a source or a gate, one
    /// per declared output for a chip.
    out_ports: []const PortSlot,
};

pub fn resolvePortCoords(arena: std.mem.Allocator, node: VirtualNode, x: u32, y: u32, w: u32, h: u32) !Ports {
    const slots = ports.inputSlots(node);
    const in_list = try arena.alloc(PortSlot, slots.len);
    for (slots, 0..) |s, i| in_list[i] = .{ .port_name = s.name, .port = s.port, .coord = .{ .x = x -| 1, .y = y + s.row } };
    const out_byte: u8 = @intFromEnum(full_format.PortName.out);
    const out_list: []PortSlot = switch (node.kind) {
        .subcircuit => blk: {
            const list = try arena.alloc(PortSlot, node.out_slots.len);
            for (node.out_slots, 0..) |s, i| list[i] = .{ .port_name = s.name, .port = s.port, .coord = .{ .x = x + w, .y = y + s.row } };
            break :blk list;
        },
        .primitive => |p| switch (p) {
            .output_pin, .led, .wire, .slice, .concat => &.{},
            else => blk: {
                const list = try arena.alloc(PortSlot, 1);
                list[0] = .{ .port_name = "out", .port = out_byte, .coord = .{ .x = x + w, .y = y + ports.outputRow(node, h, out_byte) } };
                break :blk list;
            },
        },
    };
    const first: PortCoord = if (out_list.len > 0) out_list[0].coord else .{ .x = x + w, .y = y + h / 2 };
    return .{ .in_ports = in_list, .out_port = first, .out_ports = out_list };
}

/// Pre-compose the displayed label for a node so its memory is arena-owned
/// (the canvas stores slice pointers, not copies — see the canvas note in
/// glyphs.zig). Pins gain a `name[N]` suffix at multi-bit widths; LEDs gain
/// a `0x???...` hex or `·` row display per S11.2 decision #12; everything
/// else falls back to its bare name.
pub fn composeDisplayLabel(
    arena: std.mem.Allocator,
    node: VirtualNode,
    opts: layout.LayoutOptions,
) ![]const u8 {
    return switch (node.kind) {
        .primitive => |p| switch (p) {
            .input_pin, .output_pin => if (node.signal_width > 1)
                try std.fmt.allocPrint(arena, "{s}[{d}]", .{ node.name, node.signal_width })
            else
                node.name,
            .led => try composeLedLabel(arena, node.signal_width, opts.expand_display),
            .rom, .ram => try std.fmt.allocPrint(arena, "{s} {s}[{d},{d}]", .{ @tagName(p), node.name, node.signal_width, node.addr_width }),
            else => node.name,
        },
        .subcircuit => node.name,
    };
}

/// LED display label for a static preview (no runtime state — all bits
/// undefined). Width 1 keeps the literal "LED" tag. Width 2..7 with
/// expand_display becomes a row of `·` indicators (LSB on the left).
/// Anything else, including width >=8 with expand_display, becomes a hex
/// numeric display `0x?...?` with one `?` per nibble.
pub fn composeLedLabel(arena: std.mem.Allocator, width: u8, expand_display: bool) ![]const u8 {
    if (width <= 1) return "LED";
    if (expand_display and width < 8) {
        const buf = try arena.alloc(u8, @as(usize, width) * "·".len);
        var idx: usize = 0;
        var i: u8 = 0;
        while (i < width) : (i += 1) {
            @memcpy(buf[idx .. idx + "·".len], "·");
            idx += "·".len;
        }
        return buf;
    }
    // Numeric: one '?' per nibble of the value.
    const nibbles = (@as(usize, width) + 3) / 4;
    const buf = try arena.alloc(u8, 2 + nibbles); // "0x" + N '?'
    buf[0] = '0';
    buf[1] = 'x';
    var k: usize = 0;
    while (k < nibbles) : (k += 1) buf[2 + k] = '?';
    return buf;
}

pub fn sizeOf(node: VirtualNode, opts: layout.LayoutOptions) sizing.PrimitiveSize {
    return switch (node.kind) {
        .primitive => |p| switch (p) {
            .input_pin, .output_pin => sizing.pinSize(node.name.len, node.signal_width),
            .led => sizing.ledSize(node.signal_width, opts.expand_display),
            .rom => sizing.memorySize(sizing.memoryLabelLen(3, node.name.len, node.signal_width, node.addr_width), 1),
            .ram => sizing.memorySize(sizing.memoryLabelLen(3, node.name.len, node.signal_width, node.addr_width), 4),
            // Slice and concat are collapsed in stage 1; the layer
            // should never ask for their size. Return the sentinel
            // zero so a stray call doesn't crash.
            .slice, .concat => sizing.primitive_sizing.get(p),
            else => sizing.primitive_sizing.get(p),
        },
        .subcircuit => |sub| chipSize(sub, node),
    };
}

/// A chip box: tall enough for one port on every other row, and wide enough
/// for its `[<chip>:<name>]` title. With port labels it is also wide enough
/// for each row's input and output names side by side, and for the title to
/// clear the names that share its row.
fn chipSize(sub: []const u8, node: VirtualNode) sizing.PrimitiveSize {
    const title: u32 = @intCast(sub.len + node.name.len + 3); // [, :, ]
    const height = types.chipHeight(node.in_slots.len, node.out_slots.len);
    var width = sizing.macroSize(title, 1).width;
    if (!node.port_labels) return .{ .width = width, .height = height };

    const mid = height / 2;
    var row: u32 = 1;
    while (row + 1 < height) : (row += 1) {
        const in_len = labelLenAt(node.in_slots, row);
        const out_len = labelLenAt(node.out_slots, row);
        // Two names on one row keep a cell between them.
        var need = in_len + out_len + @as(u32, if (in_len > 0 and out_len > 0) 1 else 0);
        // The title is centred, so it clears the longer name on both sides.
        if (row == mid) {
            const side = @max(in_len, out_len);
            need = title + if (side > 0) 2 * (side + 1) else 0;
        }
        width = @max(width, need + 2);
    }
    return .{ .width = width, .height = height };
}

fn labelLenAt(slots: []const types.Slot, row: u32) u32 {
    for (slots) |s| {
        if (s.row == row) return @intCast(s.name.len);
    }
    return 0;
}

// ---------- Tests ----------

const P = full_format.PortName;
const InputEdge = types.InputEdge;

fn mk(kind: types.NodeKind, inputs: []const InputEdge) VirtualNode {
    return .{ .id = 0, .kind = kind, .name = "g", .origin = &.{}, .inputs = inputs, .outputs = &.{} };
}

const in_a = InputEdge{ .src_id = 9, .src_port = @intFromEnum(P.out), .dst_port = @intFromEnum(P.a) };
const in_in = InputEdge{ .src_id = 9, .src_port = @intFromEnum(P.out), .dst_port = @intFromEnum(P.in) };
const in_b = InputEdge{ .src_id = 9, .src_port = @intFromEnum(P.out), .dst_port = @intFromEnum(P.b) };

test "boxes: port coordinates equal the ports table plus the box origin" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A chip with three inputs and two outputs: seven rows, the outputs
    // centred on rows 2 and 4.
    var chip_in = [_]types.Slot{ .{ .name = "d", .port = 16, .row = 0 }, .{ .name = "clk", .port = 17, .row = 0 }, .{ .name = "en", .port = 18, .row = 0 } };
    var chip_out = [_]types.Slot{ .{ .name = "q", .port = 16, .row = 0 }, .{ .name = "nq", .port = 17, .row = 0 } };
    types.assignChipRows(&chip_in, &chip_out);
    var chip = mk(.{ .subcircuit = "m" }, &.{});
    chip.in_slots = &chip_in;
    chip.out_slots = &chip_out;
    chip.port_labels = true;
    const cases = [_]struct { n: VirtualNode, w: u32, h: u32 }{
        .{ .n = mk(.{ .primitive = .input_pin }, &.{}), .w = 5, .h = 3 },
        .{ .n = mk(.{ .primitive = .and_gate }, &.{ in_a, in_b }), .w = 5, .h = 5 },
        .{ .n = mk(.{ .primitive = .ram }, &.{}), .w = 12, .h = 9 },
        .{ .n = chip, .w = 7, .h = 7 },
    };
    for (cases) |c| {
        const got = try resolvePortCoords(a, c.n, 10, 20, c.w, c.h);
        const slots = ports.inputSlots(c.n);
        try std.testing.expectEqual(slots.len, got.in_ports.len);
        for (got.in_ports, slots) |pp, s| {
            try std.testing.expectEqualStrings(s.name, pp.port_name);
            try std.testing.expectEqual(@as(u32, 9), pp.coord.x);
            try std.testing.expectEqual(20 + s.row, pp.coord.y);
        }
        try std.testing.expectEqual(10 + c.w, got.out_port.x);
        try std.testing.expect(got.out_ports.len > 0);
        try std.testing.expectEqual(got.out_ports[0].coord, got.out_port);
        try std.testing.expectEqual(20 + ports.outputRow(c.n, c.h, got.out_ports[0].port), got.out_port.y);
    }
    const chip_p = try resolvePortCoords(a, chip, 10, 20, 7, 7);
    try std.testing.expectEqual(@as(usize, 3), chip_p.in_ports.len);
    try std.testing.expectEqual(@as(u32, 25), chip_p.in_ports[2].coord.y);
    try std.testing.expectEqual(@as(usize, 2), chip_p.out_ports.len);
    try std.testing.expectEqual(@as(u32, 22), chip_p.out_ports[0].coord.y);
    try std.testing.expectEqual(@as(u32, 24), chip_p.out_ports[1].coord.y);
    // Tall enough for three inputs; wide enough for `clk` beside `[m:g]`
    // on the middle row: 5 + 2 * (3 + 1) + 2.
    try std.testing.expectEqual(@as(u32, 7), sizeOf(chip, .{}).height);
    try std.testing.expectEqual(@as(u32, 15), sizeOf(chip, .{}).width);
    // A sink has no output port.
    try std.testing.expectEqual(@as(usize, 0), (try resolvePortCoords(a, mk(.{ .primitive = .led }, &.{}), 0, 0, 5, 3)).out_ports.len);
    // The and gate's well-known offsets, spelled out.
    const and_p = try resolvePortCoords(a, mk(.{ .primitive = .and_gate }, &.{ in_a, in_b }), 10, 0, 5, 5);
    try std.testing.expectEqual(@as(u32, 1), and_p.in_ports[0].coord.y);
    try std.testing.expectEqual(@as(u32, 3), and_p.in_ports[1].coord.y);
    try std.testing.expectEqual(@as(u32, 15), and_p.out_port.x);
    try std.testing.expectEqual(@as(u32, 2), and_p.out_port.y);
}

test "boxes: labels and sizes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var pin = mk(.{ .primitive = .input_pin }, &.{});
    pin.name = "bus";
    pin.signal_width = 8;
    try std.testing.expectEqualStrings("bus[8]", try composeDisplayLabel(a, pin, .{}));
    var led = mk(.{ .primitive = .led }, &.{});
    led.signal_width = 4;
    try std.testing.expectEqualStrings("0x?", try composeDisplayLabel(a, led, .{}));
    try std.testing.expectEqualStrings("····", try composeDisplayLabel(a, led, .{ .expand_display = true }));
    var sub = mk(.{ .subcircuit = "xor" }, &.{});
    sub.name = "longish_combine";
    try std.testing.expectEqual(@as(u32, 23), sizeOf(sub, .{}).width);
}
