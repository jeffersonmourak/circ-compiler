const std = @import("std");
const ir = @import("ir_types");
const format = @import("format");

pub fn serializeModule(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
) ![]u8 {
    var components: std.ArrayList(format.ComponentRecord) = .{};
    defer components.deinit(allocator);
    var connections: std.ArrayList(format.ConnectionRecord) = .{};
    defer connections.deinit(allocator);

    for (module.components) |comp| {
        const kind: format.ComponentKind = switch (comp.kind) {
            .primitive => |p| switch (p) {
                .and_gate => .and_gate,
                .not_gate => .not_gate,
                .wire => .wire,
                .led => .led,
                .input_pin => .input_pin,
                .output_pin => .output_pin,
            },
            else => return error.SubCircuitInFlatModule,
        };
        try components.append(allocator, .{
            .id = comp.id.value,
            .kind = @intFromEnum(kind),
        });
    }

    for (module.connections) |conn| {
        try connections.append(allocator, .{
            .from_id = conn.from.component.value,
            .to_id = conn.to.component.value,
            .port = @intFromEnum(try parsePortName(conn.to.port)),
        });
    }

    return try encodePayload(allocator, components.items, connections.items);
}

pub fn serializeProject(
    allocator: std.mem.Allocator,
    project: *const ir.Project,
) ![]u8 {
    _ = allocator;
    _ = project;
    return error.NotImplemented;
}

fn parsePortName(name: []const u8) !format.PortName {
    if (std.mem.eql(u8, name, "in")) return .in;
    if (std.mem.eql(u8, name, "a")) return .a;
    if (std.mem.eql(u8, name, "b")) return .b;
    if (std.mem.eql(u8, name, "out")) return .out;
    return error.UnknownPortName;
}

fn encodePayload(
    allocator: std.mem.Allocator,
    components: []const format.ComponentRecord,
    connections: []const format.ConnectionRecord,
) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, &format.MAGIC);
    try out.append(allocator, format.VERSION);

    var buf: [4]u8 = undefined;
    
    std.mem.writeInt(u32, &buf, @intCast(components.len), .little);
    try out.appendSlice(allocator, &buf);
    
    std.mem.writeInt(u32, &buf, @intCast(connections.len), .little);
    try out.appendSlice(allocator, &buf);

    for (components) |comp| {
        std.mem.writeInt(u32, &buf, comp.id, .little);
        try out.appendSlice(allocator, &buf);
        try out.append(allocator, comp.kind);
    }

    for (connections) |connection| {
        std.mem.writeInt(u32, &buf, connection.from_id, .little);
        try out.appendSlice(allocator, &buf);
        std.mem.writeInt(u32, &buf, connection.to_id, .little);
        try out.appendSlice(allocator, &buf);
        try out.append(allocator, connection.port);
    }

    return out.toOwnedSlice(allocator);
}

test "serialize: inverter module bytes" {
    const allocator = std.testing.allocator;
    const span = ir.Span{ .file_id = 0, .start_line = 0, .start_col = 0, .end_line = 0, .end_col = 0 };
    
    const components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .primitive = .input_pin }, .instance_name = "in", .span = span },
        .{ .id = .{ .value = 1 }, .kind = .{ .primitive = .not_gate }, .instance_name = "n1", .span = span },
        .{ .id = .{ .value = 2 }, .kind = .{ .primitive = .output_pin }, .instance_name = "out", .span = span },
    };
    
    const connections = [_]ir.Connection{
        .{
            .from = .{ .component = .{ .value = 0 }, .port = "out" },
            .to = .{ .component = .{ .value = 1 }, .port = "in" },
            .span = span,
        },
        .{
            .from = .{ .component = .{ .value = 1 }, .port = "out" },
            .to = .{ .component = .{ .value = 2 }, .port = "in" },
            .span = span,
        },
    };
    
    const module = ir.Module{
        .file_id = .{ .value = 0 },
        .inputs = &.{},
        .outputs = &.{},
        .components = &components,
        .connections = &connections,
        .imports = &.{},
    };
    
    const payload = try serializeModule(allocator, &module);
    defer allocator.free(payload);
    
    try std.testing.expectEqualStrings(&format.MAGIC, payload[0..4]);
    try std.testing.expectEqual(format.VERSION, payload[4]);
    
    // comp_count = 3
    try std.testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, payload[5..9][0..4], .little));
    // conn_count = 2
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, payload[9..13][0..4], .little));
    
    // Verify records
    var offset: usize = 13;
    // Comp 0
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, payload[offset..offset+4][0..4], .little));
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.input_pin), payload[offset+4]);
    offset += 5;
    // Comp 1
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, payload[offset..offset+4][0..4], .little));
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.not_gate), payload[offset+4]);
    offset += 5;
    // Comp 2
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, payload[offset..offset+4][0..4], .little));
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.output_pin), payload[offset+4]);
    offset += 5;
    
    // Conn 0
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, payload[offset..offset+4][0..4], .little));
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, payload[offset+4..offset+8][0..4], .little));
    try std.testing.expectEqual(@intFromEnum(format.PortName.in), payload[offset+8]);
    offset += 9;
}

test "serialize: unknown port name returns error" {
    const allocator = std.testing.allocator;
    const span = ir.Span{ .file_id = 0, .start_line = 0, .start_col = 0, .end_line = 0, .end_col = 0 };
    
    const components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .primitive = .input_pin }, .instance_name = "in", .span = span },
        .{ .id = .{ .value = 1 }, .kind = .{ .primitive = .not_gate }, .instance_name = "n1", .span = span },
    };
    
    const connections = [_]ir.Connection{
        .{
            .from = .{ .component = .{ .value = 0 }, .port = "out" },
            .to = .{ .component = .{ .value = 1 }, .port = "invalid" },
            .span = span,
        },
    };
    
    const module = ir.Module{
        .file_id = .{ .value = 0 },
        .inputs = &.{},
        .outputs = &.{},
        .components = &components,
        .connections = &connections,
        .imports = &.{},
    };
    
    try std.testing.expectError(error.UnknownPortName, serializeModule(allocator, &module));
}
