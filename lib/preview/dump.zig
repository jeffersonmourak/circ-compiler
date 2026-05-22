const std = @import("std");
const full_format = @import("full_format");
const layout_mod = @import("layout");

const FullTopology = full_format.FullTopology;
const LayoutGrid = layout_mod.LayoutGrid;
const PlacedComponent = layout_mod.PlacedComponent;
const RoutedWire = layout_mod.RoutedWire;

fn portName(port: u8) []const u8 {
    return switch (port) {
        @intFromEnum(full_format.PortName.in) => "in",
        @intFromEnum(full_format.PortName.a) => "a",
        @intFromEnum(full_format.PortName.b) => "b",
        @intFromEnum(full_format.PortName.out) => "out",
        else => "?",
    };
}

pub fn dump(writer: anytype, topology: FullTopology) !void {
    try writer.writeAll("Topology (v0.full)\n");
    try writer.print("  components: {d}\n", .{topology.components.len});
    try writer.print("  connections: {d}\n\n", .{topology.connections.len});

    try writer.writeAll("Components:\n");
    for (topology.components) |comp| {
        try writer.print("  [{d}] {s} \"{s}\"", .{
            comp.id,
            @tagName(comp.kind),
            comp.name,
        });
        if (comp.origin.len > 0) {
            try writer.writeAll(" origin: ");
            for (comp.origin, 0..) |frame, i| {
                if (i > 0) try writer.writeAll(" > ");
                try writer.print("{s}:{s}", .{ frame.alias, frame.subcircuit });
            }
        }
        try writer.writeByte('\n');
    }

    try writer.writeAll("\nConnections:\n");
    for (topology.connections) |conn| {
        try writer.print("  {d}.out -> {d}.{s}\n", .{
            conn.from_id,
            conn.to_id,
            portName(conn.port),
        });
    }
}

/// Phase 2 slice 6b helper: textual debug dump of a `LayoutGrid` for golden tests
/// and ad-hoc inspection. Three sections: header (grid dimensions), components
/// list with placement, wires list with segment paths, optional crossings list.
pub fn dumpLayout(writer: anytype, grid: LayoutGrid) !void {
    try writer.print("LayoutGrid {d}x{d}\n\n", .{ grid.width, grid.height });

    try writer.writeAll("Components:\n");
    for (grid.components) |comp| {
        try writer.print("  [{d}] ", .{comp.id});
        switch (comp.kind) {
            .primitive => |p| try writer.print("{s}", .{@tagName(p)}),
            .subcircuit => |sub| try writer.print("subcircuit:{s}", .{sub}),
        }
        try writer.print(" \"{s}\" @({d},{d}) {d}x{d}\n", .{ comp.name, comp.x, comp.y, comp.width, comp.height });
    }

    try writer.writeAll("\nWires:\n");
    for (grid.wires) |w| {
        try writer.print("  {d}.{s} -> {d}.{s}:", .{ w.src_id, portName(w.src_port), w.dst_id, portName(w.dst_port) });
        if (w.segments.len == 0) {
            try writer.writeAll(" (empty)\n");
            continue;
        }
        try writer.print(" ({d},{d})", .{ w.segments[0].from.x, w.segments[0].from.y });
        for (w.segments) |seg| {
            try writer.print(" -> ({d},{d})", .{ seg.to.x, seg.to.y });
        }
        try writer.writeByte('\n');
    }

    // Crossings: deduplicated by (wire-pair, point), but for simplicity dump all
    // raw entries grouped by wire.
    var any_crossings = false;
    for (grid.wires) |w| {
        if (w.crossings.len > 0) {
            any_crossings = true;
            break;
        }
    }
    if (any_crossings) {
        try writer.writeAll("\nCrossings:\n");
        for (grid.wires) |w| {
            for (w.crossings) |pt| {
                try writer.print("  wire {d}.{s}->{d}.{s} @({d},{d})\n", .{
                    w.src_id, portName(w.src_port), w.dst_id, portName(w.dst_port), pt.x, pt.y,
                });
            }
        }
    }
}

// ---------- Tests ----------

const FullComponentRecord = full_format.FullComponentRecord;
const FullConnectionRecord = full_format.FullConnectionRecord;
const OriginFrame = full_format.OriginFrame;

test "preview_dump_primitives" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "a", .origin = &.{} },
        .{ .id = 1, .kind = .input_pin, .width = 1, .name = "b", .origin = &.{} },
        .{ .id = 2, .kind = .and_gate, .width = 1, .name = "g", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 2, .port = @intFromEnum(full_format.PortName.a) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.b) },
    };
    const topo = FullTopology{ .components = &components, .connections = &connections };

    try dump(buf.writer(allocator), topo);

    const expected =
        \\Topology (v0.full)
        \\  components: 3
        \\  connections: 2
        \\
        \\Components:
        \\  [0] input_pin "a"
        \\  [1] input_pin "b"
        \\  [2] and_gate "g"
        \\
        \\Connections:
        \\  0.out -> 2.a
        \\  1.out -> 2.b
        \\
    ;
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "preview_dump_with_origin" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    const single_frame = [_]OriginFrame{
        .{ .alias = "g", .subcircuit = "xor", .target_file = 1 },
    };
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "a", .origin = &.{} },
        .{ .id = 1, .kind = .not_gate, .width = 1, .name = "n1", .origin = &single_frame },
        .{ .id = 2, .kind = .and_gate, .width = 1, .name = "a1", .origin = &single_frame },
    };
    const topo = FullTopology{ .components = &components, .connections = &.{} };

    try dump(buf.writer(allocator), topo);

    const expected =
        \\Topology (v0.full)
        \\  components: 3
        \\  connections: 0
        \\
        \\Components:
        \\  [0] input_pin "a"
        \\  [1] not_gate "n1" origin: g:xor
        \\  [2] and_gate "a1" origin: g:xor
        \\
        \\Connections:
        \\
    ;
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "preview_dump_nested_origin" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    const nested = [_]OriginFrame{
        .{ .alias = "g", .subcircuit = "xnor", .target_file = 2 },
        .{ .alias = "", .subcircuit = "xor", .target_file = 1 },
    };
    const components = [_]FullComponentRecord{
        .{ .id = 5, .kind = .not_gate, .width = 1, .name = "deep", .origin = &nested },
    };
    const topo = FullTopology{ .components = &components, .connections = &.{} };

    try dump(buf.writer(allocator), topo);

    const expected =
        \\Topology (v0.full)
        \\  components: 1
        \\  connections: 0
        \\
        \\Components:
        \\  [5] not_gate "deep" origin: g:xnor > :xor
        \\
        \\Connections:
        \\
    ;
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "preview_dump_anonymous_component_name" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .not_gate, .width = 1, .name = "", .origin = &.{} },
    };
    const topo = FullTopology{ .components = &components, .connections = &.{} };

    try dump(buf.writer(allocator), topo);

    // Anonymous name renders as the literal `""`, not <anon> or omitted.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[0] not_gate \"\"") != null);
}

test "preview_dump_port_decoding" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "x", .origin = &.{} },
        .{ .id = 1, .kind = .not_gate, .width = 1, .name = "n", .origin = &.{} },
        .{ .id = 2, .kind = .and_gate, .width = 1, .name = "a", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.in) },
        .{ .from_id = 0, .to_id = 2, .port = @intFromEnum(full_format.PortName.a) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.b) },
    };
    const topo = FullTopology{ .components = &components, .connections = &connections };

    try dump(buf.writer(allocator), topo);

    try std.testing.expect(std.mem.indexOf(u8, buf.items, "0.out -> 1.in") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "0.out -> 2.a") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "1.out -> 2.b") != null);
}

test "preview_dump_deterministic_ordering" {
    const allocator = std.testing.allocator;

    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "a", .origin = &.{} },
        .{ .id = 1, .kind = .and_gate, .width = 1, .name = "g", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.a) },
    };
    const topo = FullTopology{ .components = &components, .connections = &connections };

    var buf1: std.ArrayList(u8) = .{};
    defer buf1.deinit(allocator);
    var buf2: std.ArrayList(u8) = .{};
    defer buf2.deinit(allocator);

    try dump(buf1.writer(allocator), topo);
    try dump(buf2.writer(allocator), topo);

    try std.testing.expectEqualStrings(buf1.items, buf2.items);
}
