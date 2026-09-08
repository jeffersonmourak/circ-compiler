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
        .addr => "addr",
        .din => "din",
        .we => "we",
        .clk => "clk",
    };
}

/// Wire kind byte for an engine memory mode. The runtime module has no
/// `format` import of its own, so the exports reach the byte through here.
pub fn memKindByte(mode: engine.MemoryMode) u8 {
    return switch (mode) {
        .rom => @intFromEnum(format.ComponentKind.rom),
        .ram => @intFromEnum(format.ComponentKind.ram),
    };
}

pub fn initFromTopology(circuit: *engine.Circuit, payload: []const u8) !void {
    if (payload.len < 13) return error.TruncatedPayload;
    if (!std.mem.eql(u8, payload[0..4], &format.MAGIC)) return error.InvalidMagic;
    if (payload[4] != format.VERSION) return error.UnsupportedVersion;

    const comp_count = readU32(payload[5..9][0..4]);
    const conn_count = readU32(payload[9..13][0..4]);

    var comp_map = std.AutoHashMap(u32, *engine.Component).init(allocator);
    defer comp_map.deinit();
    try comp_map.ensureTotalCapacity(@intCast(comp_count));

    var offset: usize = 13;
    for (0..comp_count) |_| {
        if (offset + 6 > payload.len) return error.TruncatedPayload;
        const id = readU32(payload[offset .. offset + 4][0..4]);
        const kind_val = payload[offset + 4];
        const width = payload[offset + 5];
        offset += 6;

        const component_kind = std.meta.intToEnum(format.ComponentKind, kind_val) catch return error.InvalidComponentKind;
        const comp = switch (component_kind) {
            .input_pin => try circuit.createComponent(.{ .input_pin_gate = .{} }, width),
            .not_gate => try circuit.createComponent(.{ .not_gate = .{} }, width),
            .and_gate => try circuit.createComponent(.{ .and_gate = .{} }, width),
            .wire => try circuit.createComponent(.{ .wire = .{} }, width),
            .led => try circuit.createComponent(.{ .led = .{} }, width),
            .output_pin => try circuit.createComponent(.{ .output_pin = .{} }, width),
            .slice => blk: {
                // Slice records carry two trailing aux bytes `(lo, hi)`.
                // The `from` pointer is wired up later when the
                // source→slice connection is processed.
                if (offset + 2 > payload.len) return error.TruncatedPayload;
                const lo = payload[offset];
                const hi = payload[offset + 1];
                offset += 2;
                break :blk try circuit.createComponent(
                    .{ .slice = .{ .lo = lo, .hi = hi } },
                    width,
                );
            },
            .concat => try circuit.createComponent(.{ .concat = .{} }, width),
            .rom, .ram => blk: {
                // Memory records carry one trailing aux byte: the address
                // width. Exactly one engine node per record keeps the
                // host's positional id addressing intact.
                if (offset + 1 > payload.len) return error.TruncatedPayload;
                const addr_width = payload[offset];
                offset += 1;
                if (addr_width == 0 or addr_width > engine.MAX_ADDR_WIDTH) return error.InvalidMemoryRecord;
                const mode: engine.MemoryMode = if (component_kind == .rom) .rom else .ram;
                break :blk try circuit.createComponent(
                    .{ .memory = .{ .mode = mode, .cells = .{ .addr_width = addr_width } } },
                    width,
                );
            },
        };
        comp.id = id;
        comp_map.putAssumeCapacity(id, comp);
    }

    if (offset + 9 * conn_count > payload.len) return error.TruncatedPayload;

    for (0..conn_count) |_| {
        const from_id = readU32(payload[offset .. offset + 4][0..4]);
        const to_id = readU32(payload[offset + 4 .. offset + 8][0..4]);
        const port_val = payload[offset + 8];
        offset += 9;

        const from_comp = comp_map.get(from_id) orelse return error.UnknownComponentId;
        const to_comp = comp_map.get(to_id) orelse return error.UnknownComponentId;

        // Concat ports are operand indices, not PortName values. Format
        // the byte as `operand_<idx>` so the engine's `connect()` knows
        // to slot the operand into the right position.
        if (to_comp.kind == .concat) {
            var port_buf: [16]u8 = undefined;
            const port_str = try std.fmt.bufPrint(&port_buf, "operand_{d}", .{port_val});
            try circuit.connect(.{ from_comp, "out" }, .{ to_comp, port_str });
        } else {
            const port_str = try portNameStr(port_val);
            try circuit.connect(.{ from_comp, "out" }, .{ to_comp, port_str });
        }
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
    payload[4] = 0x99;
    try std.testing.expectError(error.UnsupportedVersion, initFromTopology(&circuit, &payload));
}

test "interpreter: rejects v01 payload" {
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    var payload = [_]u8{0} ** 13;
    std.mem.copyForwards(u8, payload[0..4], &format.MAGIC);
    payload[4] = 0x01;
    try std.testing.expectError(error.UnsupportedVersion, initFromTopology(&circuit, &payload));
}

test "interpreter: rejects v02 payload" {
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    var payload = [_]u8{0} ** 13;
    std.mem.copyForwards(u8, payload[0..4], &format.MAGIC);
    payload[4] = 0x02;
    try std.testing.expectError(error.UnsupportedVersion, initFromTopology(&circuit, &payload));
}

fn memoryPayload(list: *std.ArrayList(u8), comp_count: u32, conn_count: u32) !void {
    try list.appendSlice(allocator, &format.MAGIC);
    try list.append(allocator, format.VERSION);
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, comp_count, .little);
    try list.appendSlice(allocator, &buf);
    std.mem.writeInt(u32, &buf, conn_count, .little);
    try list.appendSlice(allocator, &buf);
}

test "interpreter: decodes rom and ram records and wires their ports" {
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();

    var payload: std.ArrayList(u8) = .{};
    defer payload.deinit(allocator);
    try memoryPayload(&payload, 3, 5);
    // id 0: input_pin[4]
    try payload.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0, @intFromEnum(format.ComponentKind.input_pin), 4 });
    // id 1: rom[8, 4]
    try payload.appendSlice(allocator, &[_]u8{ 1, 0, 0, 0, @intFromEnum(format.ComponentKind.rom), 8, 4 });
    // id 2: ram[8, 2]
    try payload.appendSlice(allocator, &[_]u8{ 2, 0, 0, 0, @intFromEnum(format.ComponentKind.ram), 8, 2 });
    // 0 -> 1.addr, 0 -> 2.addr, 1 -> 2.din, 0 -> 2.we, 0 -> 2.clk
    try payload.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0, 1, 0, 0, 0, @intFromEnum(format.PortName.addr) });
    try payload.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0, 2, 0, 0, 0, @intFromEnum(format.PortName.addr) });
    try payload.appendSlice(allocator, &[_]u8{ 1, 0, 0, 0, 2, 0, 0, 0, @intFromEnum(format.PortName.din) });
    try payload.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0, 2, 0, 0, 0, @intFromEnum(format.PortName.we) });
    try payload.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0, 2, 0, 0, 0, @intFromEnum(format.PortName.clk) });

    try initFromTopology(&circuit, payload.items);

    try std.testing.expectEqual(@as(usize, 3), circuit.nodes.items.len);
    const rom = circuit.nodes.items[1];
    const ram = circuit.nodes.items[2];
    try std.testing.expect(rom.kind == .memory and rom.kind.memory.mode == .rom);
    try std.testing.expectEqual(@as(u8, 4), rom.kind.memory.cells.addr_width);
    try std.testing.expectEqual(@as(u8, 8), rom.state_handle.tier);
    try std.testing.expect(ram.kind.memory.mode == .ram);
    try std.testing.expectEqual(@as(usize, 4), ram.kind.memory.cells.values.len);
    try std.testing.expect(ram.kind.memory.addr == circuit.nodes.items[0]);
    try std.testing.expect(ram.kind.memory.din == rom);
    try std.testing.expect(ram.kind.memory.we != null and ram.kind.memory.clk != null);
    try std.testing.expectEqual(@as(u8, 8), memKindByte(.rom));
    try std.testing.expectEqual(@as(u8, 9), memKindByte(.ram));
}

test "interpreter: rejects truncated or out-of-range memory record" {
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();

    var truncated: std.ArrayList(u8) = .{};
    defer truncated.deinit(allocator);
    try memoryPayload(&truncated, 1, 0);
    try truncated.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0, @intFromEnum(format.ComponentKind.rom), 8 });
    try std.testing.expectError(error.TruncatedPayload, initFromTopology(&circuit, truncated.items));

    for ([_]u8{ 0, 17 }) |bad_width| {
        var circuit2 = try engine.Circuit.init();
        defer circuit2.deinit();
        var payload: std.ArrayList(u8) = .{};
        defer payload.deinit(allocator);
        try memoryPayload(&payload, 1, 0);
        try payload.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0, @intFromEnum(format.ComponentKind.ram), 8, bad_width });
        try std.testing.expectError(error.InvalidMemoryRecord, initFromTopology(&circuit2, payload.items));
    }
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
    try payload.append(allocator, 1);

    try payload.appendSlice(allocator, &[_]u8{1, 0, 0, 0});
    try payload.append(allocator, @intFromEnum(format.ComponentKind.not_gate));
    try payload.append(allocator, 1);
    
    try payload.appendSlice(allocator, &[_]u8{0, 0, 0, 0}); 
    try payload.appendSlice(allocator, &[_]u8{1, 0, 0, 0}); 
    try payload.append(allocator, @intFromEnum(format.PortName.in)); 
    
    try initFromTopology(&circuit, payload.items);
    
    try std.testing.expectEqual(@as(usize, 2), circuit.nodes.items.len);
    try std.testing.expectEqualStrings("wire", @tagName(circuit.nodes.items[0].kind));
    try std.testing.expectEqualStrings("not_gate", @tagName(circuit.nodes.items[1].kind));
}
