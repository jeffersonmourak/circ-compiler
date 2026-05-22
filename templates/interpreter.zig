const std = @import("std");
const builtin = @import("builtin");
const format = @import("format");
const engine = @import("circuit.zig");

const is_wasm = builtin.target.cpu.arch == .wasm32;
const allocator = if (is_wasm) std.heap.wasm_allocator else std.testing.allocator;

fn readU32(bytes: *const [4]u8) u32 {
    return std.mem.readInt(u32, bytes, .little);
}

fn portNameStr(port: u8) ![]const u8 {
    const port_name = std.meta.intToEnum(format.PortName, port) catch return error.InvalidPort;
    return switch (port_name) {
        .in => "in",
        .a => "a",
        .b => "b",
        .out => "out",
    };
}

pub fn initFromTopology(circuit: *engine.Circuit, payload: []const u8) !void {
    if (payload.len < 13) return error.TruncatedPayload;
    if (!std.mem.eql(u8, payload[0..4], &format.MAGIC)) return error.InvalidMagic;
    if (payload[4] != format.VERSION) return error.UnsupportedVersion;

    const comp_count = readU32(payload[5..9][0..4]);
    const conn_count = readU32(payload[9..13][0..4]);

    const comp_bytes = 5 * comp_count;
    const conn_bytes = 9 * conn_count;

    if (payload.len < 13 + comp_bytes + conn_bytes) return error.TruncatedPayload;

    var comp_map = std.AutoHashMap(u32, *engine.Component).init(allocator);
    defer comp_map.deinit();
    try comp_map.ensureTotalCapacity(@intCast(comp_count));

    var offset: usize = 13;
    for (0..comp_count) |_| {
        const id = readU32(payload[offset .. offset + 4][0..4]);
        const kind_val = payload[offset + 4];
        offset += 5;

        const component_kind = std.meta.intToEnum(format.ComponentKind, kind_val) catch return error.InvalidComponentKind;
        const comp = switch (component_kind) {
            .input_pin => try circuit.createComponent(.{ .input_pin_gate = .{} }, 1),
            .not_gate => try circuit.createComponent(.{ .not_gate = .{} }, 1),
            .and_gate => try circuit.createComponent(.{ .and_gate = .{} }, 1),
            .wire => try circuit.createComponent(.{ .wire = .{} }, 1),
            .led => try circuit.createComponent(.{ .led = .{} }, 1),
            .output_pin => try circuit.createComponent(.{ .output_pin = .{} }, 1),
        };
        comp.id = id; 
        comp_map.putAssumeCapacity(id, comp);
    }

    for (0..conn_count) |_| {
        const from_id = readU32(payload[offset .. offset + 4][0..4]);
        const to_id = readU32(payload[offset + 4 .. offset + 8][0..4]);
        const port_val = payload[offset + 8];
        offset += 9;

        const from_comp = comp_map.get(from_id) orelse return error.UnknownComponentId;
        const to_comp = comp_map.get(to_id) orelse return error.UnknownComponentId;

        const port_str = try portNameStr(port_val);
        try circuit.connect(.{ from_comp, "out" }, .{ to_comp, port_str });
    }
}

test "interpreter: rejects truncated payload" {
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    try std.testing.expectError(error.TruncatedPayload, initFromTopology(&circuit, &.{ 0, 0, 0, 0 }));
}

test "interpreter: rejects wrong magic" {
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    var payload = [_]u8{0} ** 13;
    payload[0] = 'X';
    try std.testing.expectError(error.InvalidMagic, initFromTopology(&circuit, &payload));
}

test "interpreter: rejects unknown version" {
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    var payload = [_]u8{0} ** 13;
    std.mem.copyForwards(u8, payload[0..4], &format.MAGIC);
    payload[4] = 0x02; 
    try std.testing.expectError(error.UnsupportedVersion, initFromTopology(&circuit, &payload));
}

test "interpreter: single not-gate topology" {
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    
    var payload: std.ArrayList(u8) = .{};
    defer payload.deinit(allocator);
    
    try payload.appendSlice(allocator, &format.MAGIC);
    try payload.append(allocator, format.VERSION);
    
    try payload.appendSlice(allocator, &[_]u8{2, 0, 0, 0}); 
    try payload.appendSlice(allocator, &[_]u8{1, 0, 0, 0}); 
    
    try payload.appendSlice(allocator, &[_]u8{0, 0, 0, 0});
    try payload.append(allocator, @intFromEnum(format.ComponentKind.wire));
    
    try payload.appendSlice(allocator, &[_]u8{1, 0, 0, 0});
    try payload.append(allocator, @intFromEnum(format.ComponentKind.not_gate));
    
    try payload.appendSlice(allocator, &[_]u8{0, 0, 0, 0}); 
    try payload.appendSlice(allocator, &[_]u8{1, 0, 0, 0}); 
    try payload.append(allocator, @intFromEnum(format.PortName.in)); 
    
    try initFromTopology(&circuit, payload.items);
    
    try std.testing.expectEqual(@as(usize, 2), circuit.nodes.items.len);
    try std.testing.expectEqualStrings("wire", @tagName(circuit.nodes.items[0].kind));
    try std.testing.expectEqualStrings("not_gate", @tagName(circuit.nodes.items[1].kind));
}
