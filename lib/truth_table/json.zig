const std = @import("std");
const builder = @import("builder");

const Table = builder.Table;
const State = builder.State;
const PinRef = builder.PinRef;

fn writeStateCell(writer: anytype, s: State) !void {
    // 0 / 1 are the canonical boolean encodings; null marks an undriven cell.
    // Picking null over "?" or 2 gives consumers a typed signal — they can
    // branch on `cell === null` without parsing magic strings.
    switch (s) {
        .low => try writer.writeByte('0'),
        .high => try writer.writeByte('1'),
        .undef => try writer.writeAll("null"),
    }
}

fn writeNameList(writer: anytype, pins: []const PinRef) !void {
    try writer.writeByte('[');
    for (pins, 0..) |pin, idx| {
        if (idx != 0) try writer.writeByte(',');
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
        try writer.writeByte('"');
    }
    try writer.writeByte(']');
}

pub fn render(writer: anytype, table: Table) !void {
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
            const bit: u8 = @intCast((row.input_bits >> @intCast(idx)) & 1);
            try writer.writeByte(if (bit == 1) '1' else '0');
        }
        try writer.writeAll("],\"out\":[");
        for (outputs, 0..) |_, idx| {
            if (idx != 0) try writer.writeByte(',');
            try writeStateCell(writer, row.outputs[idx]);
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
        const out_copy = try a.dupe(State, src.outputs);
        dst.* = .{ .input_bits = src.input_bits, .outputs = out_copy };
    }
    return .{
        .arena = arena.*,
        .header = .{ .inputs = inputs_copy, .outputs = outputs_copy },
        .rows = rows_copy,
    };
}

test "json_render_and_two_inputs" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    const inputs = [_]PinRef{
        .{ .name = "a", .component_id = 0 },
        .{ .name = "b", .component_id = 1 },
    };
    const outputs = [_]PinRef{
        .{ .name = "result", .component_id = 3 },
    };
    const rows = [_]builder.Row{
        .{ .input_bits = 0, .outputs = &.{.low} },
        .{ .input_bits = 1, .outputs = &.{.low} },
        .{ .input_bits = 2, .outputs = &.{.low} },
        .{ .input_bits = 3, .outputs = &.{.high} },
    };

    var table = try makeTable(&arena, &inputs, &outputs, &rows);
    defer table.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(test_alloc);
    try render(buf.writer(test_alloc), table);

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
        .{ .name = "a", .component_id = 0 },
    };
    const outputs = [_]PinRef{
        .{ .name = "out", .component_id = 1 },
    };
    const rows = [_]builder.Row{
        .{ .input_bits = 0, .outputs = &.{.undef} },
        .{ .input_bits = 1, .outputs = &.{.high} },
    };

    var table = try makeTable(&arena, &inputs, &outputs, &rows);
    defer table.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(test_alloc);
    try render(buf.writer(test_alloc), table);

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
        .{ .name = "a", .component_id = 0 },
        .{ .name = "b", .component_id = 1 },
    };
    const outputs = [_]PinRef{
        .{ .name = "out", .component_id = 2 },
    };
    const rows = [_]builder.Row{
        .{ .input_bits = 0, .outputs = &.{.high} },
        .{ .input_bits = 3, .outputs = &.{.undef} },
    };
    var table = try makeTable(&arena, &inputs, &outputs, &rows);
    defer table.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(test_alloc);
    try render(buf.writer(test_alloc), table);

    var parsed = try std.json.parseFromSlice(std.json.Value, test_alloc, buf.items, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expect(parsed.value.object.get("inputs").? == .array);
    try std.testing.expect(parsed.value.object.get("rows").? == .array);
}
