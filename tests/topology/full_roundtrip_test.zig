const std = @import("std");
const full_format = @import("full_format");
const full_serializer = @import("full_serializer");
const full_decoder = @import("full_decoder");

const FullTopology = full_format.FullTopology;
const FullComponentRecord = full_format.FullComponentRecord;
const FullConnectionRecord = full_format.FullConnectionRecord;
const OriginFrame = full_format.OriginFrame;

fn expectComponentEqual(expected: FullComponentRecord, actual: FullComponentRecord) !void {
    try std.testing.expectEqual(expected.id, actual.id);
    try std.testing.expectEqual(expected.kind, actual.kind);
    try std.testing.expectEqualStrings(expected.name, actual.name);
    try std.testing.expectEqual(expected.origin.len, actual.origin.len);
    for (expected.origin, actual.origin) |exp_frame, act_frame| {
        try std.testing.expectEqualStrings(exp_frame.alias, act_frame.alias);
        try std.testing.expectEqualStrings(exp_frame.subcircuit, act_frame.subcircuit);
        try std.testing.expectEqual(exp_frame.target_file, act_frame.target_file);
    }
}

test "full_encode_decode_roundtrip_simple" {
    const allocator = std.testing.allocator;

    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .name = "a", .origin = &.{} },
        .{ .id = 1, .kind = .input_pin, .name = "b", .origin = &.{} },
        .{ .id = 2, .kind = .and_gate, .name = "g1", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 2, .port = @intFromEnum(full_format.PortName.a) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.b) },
    };
    const original = FullTopology{ .components = &components, .connections = &connections };

    const bytes = try full_serializer.encode(allocator, original);
    defer allocator.free(bytes);

    var decoded = try full_decoder.decode(allocator, bytes);
    defer decoded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), decoded.components.len);
    try std.testing.expectEqual(@as(usize, 2), decoded.connections.len);
    for (components, decoded.components) |exp, act| try expectComponentEqual(exp, act);
    for (connections, decoded.connections) |exp, act| {
        try std.testing.expectEqual(exp.from_id, act.from_id);
        try std.testing.expectEqual(exp.to_id, act.to_id);
        try std.testing.expectEqual(exp.port, act.port);
    }
}

test "full_encode_decode_roundtrip_with_origin" {
    const allocator = std.testing.allocator;

    const single_frame = [_]OriginFrame{
        .{ .alias = "combine", .subcircuit = "xor", .target_file = 7 },
    };
    const nested_frames = [_]OriginFrame{
        .{ .alias = "outer", .subcircuit = "xnor", .target_file = 5 },
        .{ .alias = "", .subcircuit = "xor", .target_file = 7 },
    };

    const components = [_]FullComponentRecord{
        .{ .id = 10, .kind = .not_gate, .name = "n_in_combine", .origin = &single_frame },
        .{ .id = 11, .kind = .and_gate, .name = "a_in_combine", .origin = &single_frame },
        .{ .id = 12, .kind = .not_gate, .name = "n_in_nested", .origin = &nested_frames },
    };
    const original = FullTopology{ .components = &components, .connections = &.{} };

    const bytes = try full_serializer.encode(allocator, original);
    defer allocator.free(bytes);

    var decoded = try full_decoder.decode(allocator, bytes);
    defer decoded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), decoded.components.len);
    for (components, decoded.components) |exp, act| try expectComponentEqual(exp, act);

    // The nested-frame component carries an empty alias on its inner frame; verify it survives byte-identically.
    try std.testing.expectEqual(@as(usize, 2), decoded.components[2].origin.len);
    try std.testing.expectEqualStrings("", decoded.components[2].origin[1].alias);
    try std.testing.expectEqualStrings("xor", decoded.components[2].origin[1].subcircuit);
    try std.testing.expectEqual(@as(u32, 7), decoded.components[2].origin[1].target_file);
}
