const std = @import("std");
const full_format = @import("full_format");
const layout_mod = @import("layout");

const LayoutGrid = layout_mod.LayoutGrid;
const PlacedComponent = layout_mod.PlacedComponent;
const PortCoord = layout_mod.PortCoord;
const RoutedWire = layout_mod.RoutedWire;

/// Machine-readable `LayoutGrid` dump — the cross-language layout-parity
/// contract shared with circ-renderer's `test/layout-parity.test.ts`.
///
/// The shape is the common subset of Zig's `LayoutGrid` and the TypeScript
/// port's `LayoutGrid` (`circ-renderer/src/layout/types.ts`), with camelCase
/// keys so the TS side compares `buildLayout()`'s output without renaming:
///
///   { width, height,
///     components[]: { id, kind, name, x, y, width, height,
///                     inPorts[]: { portName, coord{x,y} }, outPort{x,y}, bitWidth },
///     wires[]:      { srcId, srcPort, dstId, dstPort, segments[]: { from{x,y}, to{x,y} } } }
///
/// `kind` is `{"tag":"primitive","kind":<u8>}` (the wire-format numbering from
/// `lib/topology/format.zig`, which the TS `ComponentKind` enum mirrors) or
/// `{"tag":"subcircuit","subcircuit":"<name>"}`.
///
/// Deliberately excluded: `origin` and `display_label` (render-only), `slice`
/// / `memory` aux (TS-only fields), `crossings` (derived from the segments,
/// and the two routers classify endpoint touches differently), and the TS
/// `realSrcId` (a live-signal lookup aid with no Zig counterpart).
///
/// Formatting is fixed — two-space indent, one component or wire per line —
/// so the checked-in goldens diff per component and per wire.
pub fn dumpLayoutJson(writer: anytype, grid: LayoutGrid) !void {
    try writer.print("{{\n  \"width\": {d},\n  \"height\": {d},\n", .{ grid.width, grid.height });

    try writer.writeAll("  \"components\": [");
    for (grid.components, 0..) |comp, i| {
        try writer.writeAll(if (i == 0) "\n    " else ",\n    ");
        try writeComponent(writer, comp);
    }
    try writer.writeAll(if (grid.components.len == 0) "],\n" else "\n  ],\n");

    try writer.writeAll("  \"wires\": [");
    for (grid.wires, 0..) |w, i| {
        try writer.writeAll(if (i == 0) "\n    " else ",\n    ");
        try writeWire(writer, w);
    }
    try writer.writeAll(if (grid.wires.len == 0) "]\n}\n" else "\n  ]\n}\n");
}

fn writeComponent(writer: anytype, comp: PlacedComponent) !void {
    try writer.print("{{ \"id\": {d}, \"kind\": ", .{comp.id});
    switch (comp.kind) {
        .primitive => |p| try writer.print("{{ \"tag\": \"primitive\", \"kind\": {d} }}", .{@intFromEnum(p)}),
        .subcircuit => |sub| {
            try writer.writeAll("{ \"tag\": \"subcircuit\", \"subcircuit\": ");
            try writeJsonString(writer, sub);
            try writer.writeAll(" }");
        },
    }
    try writer.writeAll(", \"name\": ");
    try writeJsonString(writer, comp.name);
    try writer.print(", \"x\": {d}, \"y\": {d}, \"width\": {d}, \"height\": {d}, \"inPorts\": [", .{
        comp.x, comp.y, comp.width, comp.height,
    });
    for (comp.in_ports, 0..) |port, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.writeAll("{ \"portName\": ");
        try writeJsonString(writer, port.port_name);
        try writer.writeAll(", \"coord\": ");
        try writeCoord(writer, port.coord);
        try writer.writeAll(" }");
    }
    try writer.writeAll("], \"outPort\": ");
    try writeCoord(writer, comp.out_port);
    try writer.print(", \"bitWidth\": {d} }}", .{comp.signal_width});
}

fn writeWire(writer: anytype, w: RoutedWire) !void {
    try writer.print("{{ \"srcId\": {d}, \"srcPort\": {d}, \"dstId\": {d}, \"dstPort\": {d}, \"segments\": [", .{
        w.src_id, w.src_port, w.dst_id, w.dst_port,
    });
    for (w.segments, 0..) |seg, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.writeAll("{ \"from\": ");
        try writeCoord(writer, seg.from);
        try writer.writeAll(", \"to\": ");
        try writeCoord(writer, seg.to);
        try writer.writeAll(" }");
    }
    try writer.writeAll("] }");
}

fn writeCoord(writer: anytype, c: PortCoord) !void {
    try writer.print("{{ \"x\": {d}, \"y\": {d} }}", .{ c.x, c.y });
}

/// Component and port names are identifiers, but escape like a JSON string
/// anyway so a future subcircuit label with a quote cannot corrupt a golden.
fn writeJsonString(writer: anytype, s: []const u8) !void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => if (c < 0x20) {
                try writer.print("\\u{x:0>4}", .{c});
            } else {
                try writer.writeByte(c);
            },
        }
    }
    try writer.writeByte('"');
}

// ---------- Tests ----------

test "dump_json: emits the contract shape and parses back as JSON" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    const in_ports = [_]layout_mod.PortSlot{
        .{ .port_name = "a", .coord = .{ .x = 9, .y = 1 } },
        .{ .port_name = "b", .coord = .{ .x = 9, .y = 3 } },
    };
    const components = [_]PlacedComponent{
        .{ .id = 0, .kind = .{ .primitive = .input_pin }, .name = "a", .origin = &.{}, .x = 0, .y = 0, .width = 5, .height = 3, .in_ports = &.{}, .out_port = .{ .x = 5, .y = 1 } },
        .{ .id = 1, .kind = .{ .subcircuit = "xor" }, .name = "g", .origin = &.{}, .x = 10, .y = 0, .width = 7, .height = 5, .in_ports = &in_ports, .out_port = .{ .x = 17, .y = 2 }, .signal_width = 4 },
    };
    const segments = [_]layout_mod.Segment{
        .{ .from = .{ .x = 5, .y = 1 }, .to = .{ .x = 9, .y = 1 } },
    };
    const wires = [_]RoutedWire{
        .{ .src_id = 0, .src_port = 3, .dst_id = 1, .dst_port = 1, .segments = &segments, .crossings = &.{} },
    };
    const grid = LayoutGrid{ .width = 18, .height = 5, .components = &components, .wires = &wires };

    try dumpLayoutJson(buf.writer(allocator), grid);

    const expected =
        \\{
        \\  "width": 18,
        \\  "height": 5,
        \\  "components": [
        \\    { "id": 0, "kind": { "tag": "primitive", "kind": 0 }, "name": "a", "x": 0, "y": 0, "width": 5, "height": 3, "inPorts": [], "outPort": { "x": 5, "y": 1 }, "bitWidth": 1 },
        \\    { "id": 1, "kind": { "tag": "subcircuit", "subcircuit": "xor" }, "name": "g", "x": 10, "y": 0, "width": 7, "height": 5, "inPorts": [{ "portName": "a", "coord": { "x": 9, "y": 1 } }, { "portName": "b", "coord": { "x": 9, "y": 3 } }], "outPort": { "x": 17, "y": 2 }, "bitWidth": 4 }
        \\  ],
        \\  "wires": [
        \\    { "srcId": 0, "srcPort": 3, "dstId": 1, "dstPort": 1, "segments": [{ "from": { "x": 5, "y": 1 }, "to": { "x": 9, "y": 1 } }] }
        \\  ]
        \\}
        \\
    ;
    try std.testing.expectEqualStrings(expected, buf.items);

    // Round-trip through std.json so the hand emission is proven well-formed.
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, buf.items, .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    try std.testing.expectEqual(@as(i64, 18), root.get("width").?.integer);
    try std.testing.expectEqual(@as(usize, 2), root.get("components").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 1), root.get("wires").?.array.items.len);
}

test "dump_json: empty grid and escaped names" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try dumpLayoutJson(buf.writer(allocator), .{ .width = 0, .height = 0, .components = &.{}, .wires = &.{} });
    try std.testing.expectEqualStrings("{\n  \"width\": 0,\n  \"height\": 0,\n  \"components\": [],\n  \"wires\": []\n}\n", buf.items);

    buf.clearRetainingCapacity();
    try writeJsonString(buf.writer(allocator), "q\"b\\s\tn");
    try std.testing.expectEqualStrings("\"q\\\"b\\\\s\\tn\"", buf.items);
}
