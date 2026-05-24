const std = @import("std");
const engine = @import("circuit");
const builder = @import("builder");

const Table = builder.Table;
const PinRef = builder.PinRef;

/// Per-cell value format. JSON emits values as numbers for `binary`
/// and `decimal` (since both reduce to a positional integer), and as
/// strings for `hex` so the literal `A..F` characters survive a
/// `JSON.parse`. Per S10's locked design.
pub const ValueFormat = enum { binary, hex, decimal };

fn widthMaskU64(width: u8) u64 {
    if (width == 0) return 0;
    if (width >= 64) return std.math.maxInt(u64);
    return (@as(u64, 1) << @intCast(width)) - 1;
}

fn writePinName(writer: anytype, pin: PinRef) !void {
    try writer.writeByte('"');
    // Pin names from the IR are identifiers (no escaping required), but be
    // explicit anyway so the format isn't fragile if that ever changes.
    for (pin.name) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            else => try writer.writeByte(c),
        }
    }
    if (pin.width > 1) try writer.print("[{d}]", .{pin.width});
    try writer.writeByte('"');
}

fn writeNameList(writer: anytype, pins: []const PinRef) !void {
    try writer.writeByte('[');
    for (pins, 0..) |pin, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writePinName(writer, pin);
    }
    try writer.writeByte(']');
}

fn writeHexUpper(writer: anytype, value: u64, width: u8) !void {
    try writer.writeByte('"');
    const digits = (@as(usize, width) + 3) / 4;
    var digit_idx: i32 = @intCast(digits);
    digit_idx -= 1;
    while (digit_idx >= 0) : (digit_idx -= 1) {
        const shift: u6 = @intCast(@as(u32, @intCast(digit_idx)) * 4);
        const nibble: u8 = @intCast((value >> shift) & 0xF);
        const ch: u8 = if (nibble < 10) '0' + nibble else 'A' + (nibble - 10);
        try writer.writeByte(ch);
    }
    try writer.writeByte('"');
}

fn writeValueCell(writer: anytype, state: engine.BitVecState, format: ValueFormat) !void {
    if (state.isUndefined()) {
        // `null` carries undefined-ness across all three formats — a typed
        // signal the JSON consumer can branch on without parsing a magic
        // string.
        try writer.writeAll("null");
        return;
    }
    const expected_defined = widthMaskU64(state.width);
    const fully_defined = state.defined == expected_defined;
    if (!fully_defined) {
        try writer.writeAll("null");
        return;
    }
    const value = state.value & expected_defined;
    switch (format) {
        .binary, .decimal => try writer.print("{d}", .{value}),
        .hex => try writeHexUpper(writer, value, state.width),
    }
}

fn extractInputValue(row: builder.Row, inputs: []const PinRef, idx: usize) engine.BitVecState {
    var offset: u8 = 0;
    for (inputs[0..idx]) |prev| offset += prev.width;
    const pin = inputs[idx];
    const pin_mask = widthMaskU64(pin.width);
    const shift: u6 = @intCast(offset);
    return .{
        .value = (row.input_bits >> shift) & pin_mask,
        .defined = pin_mask,
        .width = pin.width,
    };
}

pub fn render(writer: anytype, table: Table, format: ValueFormat) !void {
    const inputs = table.header.inputs;
    const outputs = table.header.outputs;

    try writer.writeAll("{\"inputs\":");
    try writeNameList(writer, inputs);
    try writer.writeAll(",\"outputs\":");
    try writeNameList(writer, outputs);
    try writer.writeAll(",\"rows\":[");

    for (table.rows, 0..) |row, row_idx| {
        if (row_idx != 0) try writer.writeByte(',');
        try writer.writeAll("{\"in\":[");
        for (inputs, 0..) |_, idx| {
            if (idx != 0) try writer.writeByte(',');
            const state = extractInputValue(row, inputs, idx);
            try writeValueCell(writer, state, format);
        }
        try writer.writeAll("],\"out\":[");
        for (outputs, 0..) |_, idx| {
            if (idx != 0) try writer.writeByte(',');
            try writeValueCell(writer, row.outputs[idx], format);
        }
        try writer.writeAll("]}");
    }

    try writer.writeAll("]}\n");
}

// ---------- Tests ----------

const test_alloc = std.testing.allocator;

fn makeTable(
    arena: *std.heap.ArenaAllocator,
    inputs: []const PinRef,
    outputs: []const PinRef,
    rows: []const builder.Row,
) !Table {
    const a = arena.allocator();
    const inputs_copy = try a.dupe(PinRef, inputs);
    const outputs_copy = try a.dupe(PinRef, outputs);
    const rows_copy = try a.alloc(builder.Row, rows.len);
    for (rows, rows_copy) |src, *dst| {
        const out_copy = try a.dupe(engine.BitVecState, src.outputs);
        dst.* = .{ .input_bits = src.input_bits, .outputs = out_copy };
    }
    var total_bits: u8 = 0;
    for (inputs) |pin| total_bits += pin.width;
    return .{
        .arena = arena.*,
        .header = .{ .inputs = inputs_copy, .outputs = outputs_copy },
        .rows = rows_copy,
        .total_input_bits = total_bits,
    };
}

fn lowState() engine.BitVecState {
    return engine.BitVecState.low(1);
}
fn highState() engine.BitVecState {
    return engine.BitVecState.high(1);
}
fn undefState() engine.BitVecState {
    return engine.BitVecState.undefined_(1);
}

test "json_render_and_two_inputs" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    const inputs = [_]PinRef{
        .{ .name = "a", .component_id = 0, .width = 1 },
        .{ .name = "b", .component_id = 1, .width = 1 },
    };
    const outputs = [_]PinRef{
        .{ .name = "result", .component_id = 3, .width = 1 },
    };
    const rows = [_]builder.Row{
        .{ .input_bits = 0, .outputs = &.{lowState()} },
        .{ .input_bits = 1, .outputs = &.{lowState()} },
        .{ .input_bits = 2, .outputs = &.{lowState()} },
        .{ .input_bits = 3, .outputs = &.{highState()} },
    };

    var table = try makeTable(&arena, &inputs, &outputs, &rows);
    defer table.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(test_alloc);
    try render(buf.writer(test_alloc), table, .binary);

    const expected =
        "{\"inputs\":[\"a\",\"b\"]," ++
        "\"outputs\":[\"result\"]," ++
        "\"rows\":[" ++
        "{\"in\":[0,0],\"out\":[0]}," ++
        "{\"in\":[1,0],\"out\":[0]}," ++
        "{\"in\":[0,1],\"out\":[0]}," ++
        "{\"in\":[1,1],\"out\":[1]}" ++
        "]}\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "json_render_undefined_emits_null" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    const inputs = [_]PinRef{
        .{ .name = "a", .component_id = 0, .width = 1 },
    };
    const outputs = [_]PinRef{
        .{ .name = "out", .component_id = 1, .width = 1 },
    };
    const rows = [_]builder.Row{
        .{ .input_bits = 0, .outputs = &.{undefState()} },
        .{ .input_bits = 1, .outputs = &.{highState()} },
    };

    var table = try makeTable(&arena, &inputs, &outputs, &rows);
    defer table.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(test_alloc);
    try render(buf.writer(test_alloc), table, .binary);

    const expected =
        "{\"inputs\":[\"a\"]," ++
        "\"outputs\":[\"out\"]," ++
        "\"rows\":[" ++
        "{\"in\":[0],\"out\":[null]}," ++
        "{\"in\":[1],\"out\":[1]}" ++
        "]}\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "json_render_parses_as_valid_json" {
    // Use the std.json parser as an oracle to guarantee output validity.
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    const inputs = [_]PinRef{
        .{ .name = "a", .component_id = 0, .width = 1 },
        .{ .name = "b", .component_id = 1, .width = 1 },
    };
    const outputs = [_]PinRef{
        .{ .name = "out", .component_id = 2, .width = 1 },
    };
    const rows = [_]builder.Row{
        .{ .input_bits = 0, .outputs = &.{highState()} },
        .{ .input_bits = 3, .outputs = &.{undefState()} },
    };
    var table = try makeTable(&arena, &inputs, &outputs, &rows);
    defer table.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(test_alloc);
    try render(buf.writer(test_alloc), table, .binary);

    var parsed = try std.json.parseFromSlice(std.json.Value, test_alloc, buf.items, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expect(parsed.value.object.get("inputs").? == .array);
    try std.testing.expect(parsed.value.object.get("rows").? == .array);
}

test "json_render_multi_bit_binary_format_emits_decimal_number" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    const inputs = [_]PinRef{
        .{ .name = "a", .component_id = 0, .width = 4 },
    };
    const outputs = [_]PinRef{
        .{ .name = "r", .component_id = 1, .width = 4 },
    };
    const rows = [_]builder.Row{
        .{ .input_bits = 13, .outputs = &.{
            engine.BitVecState{ .value = 13, .defined = 0xF, .width = 4 },
        } },
    };

    var table = try makeTable(&arena, &inputs, &outputs, &rows);
    defer table.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(test_alloc);
    try render(buf.writer(test_alloc), table, .binary);

    const expected =
        "{\"inputs\":[\"a[4]\"],\"outputs\":[\"r[4]\"]," ++
        "\"rows\":[{\"in\":[13],\"out\":[13]}]}\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "json_render_multi_bit_hex_format_emits_uppercase_string" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    const inputs = [_]PinRef{
        .{ .name = "a", .component_id = 0, .width = 4 },
    };
    const outputs = [_]PinRef{
        .{ .name = "r", .component_id = 1, .width = 4 },
    };
    const rows = [_]builder.Row{
        .{ .input_bits = 13, .outputs = &.{
            engine.BitVecState{ .value = 13, .defined = 0xF, .width = 4 },
        } },
    };

    var table = try makeTable(&arena, &inputs, &outputs, &rows);
    defer table.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(test_alloc);
    try render(buf.writer(test_alloc), table, .hex);

    const expected =
        "{\"inputs\":[\"a[4]\"],\"outputs\":[\"r[4]\"]," ++
        "\"rows\":[{\"in\":[\"D\"],\"out\":[\"D\"]}]}\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}
