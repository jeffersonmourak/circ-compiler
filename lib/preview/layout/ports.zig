//! Port tables: which input ports a node exposes, in border order, at which
//! row offset from its box top, and where its output port sits. This is the
//! one source both `ordering.zig` (port order for crossing counts) and
//! `coords.zig` (port rows for alignment) read, through `boxes.zig`'s
//! `resolvePortCoords` (which `boxes.zig` tests against these tables).
//!
//! Port coordinates live one cell outside the box border (`x - 1` for inputs,
//! `x + width` for the output); only the row offsets are tabled here.
const std = @import("std");
const full_format = @import("full_format");
const types = @import("layout_types");

const VirtualNode = types.VirtualNode;

pub const Slot = struct {
    name: []const u8,
    /// The `dst_port` byte as `full_format.PortName`.
    port: u8,
    /// Row offset from the box's top edge.
    row: u32,
};

/// No node exposes more input ports than this (`ram` has four).
pub const MAX_INPUTS: u32 = 4;
/// Multiplier that keeps a neighbour's position and its port slot in one
/// integer key (`pos * SLOT_KEY_BASE + slot`); must exceed `MAX_INPUTS`.
pub const SLOT_KEY_BASE: u32 = 16;

comptime {
    std.debug.assert(SLOT_KEY_BASE > MAX_INPUTS);
}

const P = full_format.PortName;

fn slot(name: []const u8, port: P, row: u32) Slot {
    return .{ .name = name, .port = @intFromEnum(port), .row = row };
}

const IN_1 = [_]Slot{slot("in", .in, 1)};
const AND_AB = [_]Slot{ slot("a", .a, 1), slot("b", .b, 3) };
const ROM_ADDR = [_]Slot{slot("addr", .addr, 1)};
const RAM_4 = [_]Slot{ slot("addr", .addr, 1), slot("din", .din, 3), slot("we", .we, 5), slot("clk", .clk, 7) };
const SUB_A = [_]Slot{slot("a", .a, 1)};
const SUB_IN = [_]Slot{slot("in", .in, 1)};
const SUB_B = [_]Slot{slot("b", .b, 1)};
const SUB_A_IN = [_]Slot{ slot("a", .a, 1), slot("in", .in, 3) };
const SUB_A_B = [_]Slot{ slot("a", .a, 1), slot("b", .b, 3) };
const SUB_IN_B = [_]Slot{ slot("in", .in, 1), slot("b", .b, 3) };
const SUB_A_IN_B = [_]Slot{ slot("a", .a, 1), slot("in", .in, 3), slot("b", .b, 5) };

/// The node's input ports in border order (top to bottom). Static slices —
/// nothing is allocated.
pub fn inputSlots(node: VirtualNode) []const Slot {
    return switch (node.kind) {
        .primitive => |p| switch (p) {
            .input_pin => &.{},
            .output_pin, .not_gate, .led => &IN_1,
            .and_gate => &AND_AB,
            .rom => &ROM_ADDR,
            .ram => &RAM_4,
            // Collapsed in stage 1; never placed.
            .wire, .slice, .concat => &.{},
        },
        .subcircuit => blk: {
            // Active inputs land on consecutive non-corner border rows in
            // canonical order a, in, b (place.zig's rule).
            var has_in = false;
            var has_a = false;
            var has_b = false;
            for (node.inputs) |edge| {
                if (edge.dst_port == @intFromEnum(P.in)) has_in = true;
                if (edge.dst_port == @intFromEnum(P.a)) has_a = true;
                if (edge.dst_port == @intFromEnum(P.b)) has_b = true;
            }
            if (has_a and has_in and has_b) break :blk &SUB_A_IN_B;
            if (has_a and has_in) break :blk &SUB_A_IN;
            if (has_a and has_b) break :blk &SUB_A_B;
            if (has_in and has_b) break :blk &SUB_IN_B;
            if (has_a) break :blk &SUB_A;
            if (has_in) break :blk &SUB_IN;
            if (has_b) break :blk &SUB_B;
            break :blk &.{};
        },
    };
}

/// Index of the slot that receives `dst_port`, or null when the node has no
/// such port (a wire into a collapsed kind, or a subcircuit port the
/// topology never connects).
pub fn slotIndex(node: VirtualNode, dst_port: u8) ?u8 {
    for (inputSlots(node), 0..) |s, i| {
        if (s.port == dst_port) return @intCast(i);
    }
    return null;
}

/// Row offset of the output port from the box's top edge, given the box
/// height (`ram` and subcircuits centre it; everything else is row 1 or, for
/// `and`, row 2).
pub fn outputRow(node: VirtualNode, height: u32) u32 {
    return switch (node.kind) {
        .primitive => |p| switch (p) {
            .and_gate => 2,
            .ram => height / 2,
            .input_pin, .not_gate, .rom => 1,
            // Sinks have no output port; place.zig leaves the default centre.
            .output_pin, .led => height / 2,
            .wire, .slice, .concat => height / 2,
        },
        .subcircuit => height / 2,
    };
}

// ---------- Tests ----------

const layout = @import("layout");
const InputEdge = types.InputEdge;

fn mk(kind: types.NodeKind, inputs: []const InputEdge) VirtualNode {
    return .{ .id = 0, .kind = kind, .name = "g", .origin = &.{}, .inputs = inputs, .outputs = &.{} };
}

const in_a = InputEdge{ .src_id = 9, .src_port = @intFromEnum(P.out), .dst_port = @intFromEnum(P.a) };
const in_in = InputEdge{ .src_id = 9, .src_port = @intFromEnum(P.out), .dst_port = @intFromEnum(P.in) };
const in_b = InputEdge{ .src_id = 9, .src_port = @intFromEnum(P.out), .dst_port = @intFromEnum(P.b) };

test "ports: input slots are in border order and slotIndex finds them" {
    const ram = mk(.{ .primitive = .ram }, &.{});
    const slots = inputSlots(ram);
    try std.testing.expectEqual(@as(usize, 4), slots.len);
    for (slots[1..], 0..) |s, i| try std.testing.expect(s.row > slots[i].row);
    try std.testing.expectEqual(@as(?u8, 2), slotIndex(ram, @intFromEnum(P.we)));
    try std.testing.expectEqual(@as(?u8, null), slotIndex(ram, @intFromEnum(P.a)));

    const and_g = mk(.{ .primitive = .and_gate }, &.{});
    try std.testing.expectEqual(@as(?u8, 0), slotIndex(and_g, @intFromEnum(P.a)));
    try std.testing.expectEqual(@as(?u8, 1), slotIndex(and_g, @intFromEnum(P.b)));
    try std.testing.expect(inputSlots(and_g).len <= MAX_INPUTS);
}
