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
    out_port: PortCoord,
};

pub fn resolvePortCoords(arena: std.mem.Allocator, node: VirtualNode, x: u32, y: u32, w: u32, h: u32) !Ports {
    const slots = ports.inputSlots(node);
    const in_list = try arena.alloc(PortSlot, slots.len);
    for (slots, 0..) |s, i| in_list[i] = .{ .port_name = s.name, .coord = .{ .x = x -| 1, .y = y + s.row } };
    return .{ .in_ports = in_list, .out_port = .{ .x = x + w, .y = y + ports.outputRow(node, h) } };
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
        .subcircuit => |sub| sizing.macroSize(
            sub.len + node.name.len + 3, // [, :, ]
            countActiveSubcircuitInputs(node),
        ),
    };
}

fn countActiveSubcircuitInputs(node: VirtualNode) u32 {
    var has_in = false;
    var has_a = false;
    var has_b = false;
    for (node.inputs) |edge| {
        switch (edge.dst_port) {
            @intFromEnum(full_format.PortName.in) => has_in = true,
            @intFromEnum(full_format.PortName.a) => has_a = true,
            @intFromEnum(full_format.PortName.b) => has_b = true,
            else => {},
        }
    }
    var n: u32 = 0;
    if (has_a) n += 1;
    if (has_in) n += 1;
    if (has_b) n += 1;
    return n;
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
    const cases = [_]struct { n: VirtualNode, w: u32, h: u32 }{
        .{ .n = mk(.{ .primitive = .input_pin }, &.{}), .w = 5, .h = 3 },
        .{ .n = mk(.{ .primitive = .and_gate }, &.{ in_a, in_b }), .w = 5, .h = 5 },
        .{ .n = mk(.{ .primitive = .ram }, &.{}), .w = 12, .h = 9 },
        .{ .n = mk(.{ .subcircuit = "m" }, &.{ in_a, in_in, in_b }), .w = 7, .h = 7 },
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
        try std.testing.expectEqual(20 + ports.outputRow(c.n, c.h), got.out_port.y);
    }
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
