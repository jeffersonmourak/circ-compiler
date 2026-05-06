const std = @import("std");
const full_format = @import("full_format");

const FullTopology = full_format.FullTopology;
const FullComponentRecord = full_format.FullComponentRecord;
const FullConnectionRecord = full_format.FullConnectionRecord;
const OriginFrame = full_format.OriginFrame;

fn appendU32LE(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try out.appendSlice(allocator, &buf);
}

fn appendString(out: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    try appendU32LE(out, allocator, @intCast(str.len));
    try out.appendSlice(allocator, str);
}

pub fn encode(allocator: std.mem.Allocator, topology: FullTopology) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, &full_format.FULL_MAGIC);
    try out.append(allocator, full_format.FULL_VERSION);

    try appendU32LE(&out, allocator, @intCast(topology.components.len));
    for (topology.components) |comp| {
        try appendU32LE(&out, allocator, comp.id);
        try out.append(allocator, @intFromEnum(comp.kind));
        try appendString(&out, allocator, comp.name);
        try appendU32LE(&out, allocator, @intCast(comp.origin.len));
        for (comp.origin) |frame| {
            try appendString(&out, allocator, frame.alias);
            try appendString(&out, allocator, frame.subcircuit);
            try appendU32LE(&out, allocator, frame.target_file);
        }
    }

    try appendU32LE(&out, allocator, @intCast(topology.connections.len));
    for (topology.connections) |conn| {
        try appendU32LE(&out, allocator, conn.from_id);
        try appendU32LE(&out, allocator, conn.to_id);
        try out.append(allocator, conn.port);
    }

    return out.toOwnedSlice(allocator);
}

test "full_encode_empty: locks the wire format" {
    const allocator = std.testing.allocator;
    const topo = FullTopology{ .components = &.{}, .connections = &.{} };

    const bytes = try encode(allocator, topo);
    defer allocator.free(bytes);

    // magic(4) + version(1) + num_components(4) + num_connections(4) = 13 bytes
    const expected = [_]u8{
        'C', 'I', 'R', 'F',
        0x01,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    };
    try std.testing.expectEqualSlices(u8, &expected, bytes);
}

test "full_encode: single component with no origin emits expected layout" {
    const allocator = std.testing.allocator;
    const components = [_]FullComponentRecord{
        .{ .id = 7, .kind = .not_gate, .name = "n1", .origin = &.{} },
    };
    const topo = FullTopology{ .components = &components, .connections = &.{} };

    const bytes = try encode(allocator, topo);
    defer allocator.free(bytes);

    // magic(4)+ver(1)+num_components(4) + id(4)+kind(1)+name_len(4)+name(2)+origin_len(4) + num_connections(4) = 28
    try std.testing.expectEqual(@as(usize, 28), bytes.len);
    try std.testing.expectEqualSlices(u8, "CIRF", bytes[0..4]);
    try std.testing.expectEqual(@as(u8, 0x01), bytes[4]);
    // num_components = 1
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, bytes[5..9], .little));
    // id = 7
    try std.testing.expectEqual(@as(u32, 7), std.mem.readInt(u32, bytes[9..13], .little));
    // kind = not_gate
    try std.testing.expectEqual(@intFromEnum(full_format.ComponentKind.not_gate), bytes[13]);
    // name_len = 2
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, bytes[14..18], .little));
    // name = "n1"
    try std.testing.expectEqualSlices(u8, "n1", bytes[18..20]);
    // origin_len = 0
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, bytes[20..24], .little));
    // num_connections = 0
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, bytes[24..28], .little));
}
