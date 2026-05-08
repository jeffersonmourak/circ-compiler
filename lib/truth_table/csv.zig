const std = @import("std");
const builder = @import("builder");

const Table = builder.Table;
const State = builder.State;
const PinRef = builder.PinRef;

fn stateChar(s: State) u8 {
    return switch (s) {
        .low => '0',
        .high => '1',
        .undef => '?',
    };
}

pub fn render(writer: anytype, table: Table) !void {
    const inputs = table.header.inputs;
    const outputs = table.header.outputs;

    // Header row. CSV cells are unquoted because pin names from the IR can't
    // contain commas, quotes, or newlines (the parser's identifier rules).
    var first = true;
    for (inputs) |pin| {
        if (!first) try writer.writeByte(',');
        try writer.writeAll(pin.name);
        first = false;
    }
    for (outputs) |pin| {
        if (!first) try writer.writeByte(',');
        try writer.writeAll(pin.name);
        first = false;
    }
    try writer.writeByte('\n');

    // Data rows.
    for (table.rows) |row| {
        first = true;
        for (inputs, 0..) |_, idx| {
            if (!first) try writer.writeByte(',');
            const bit: u8 = @intCast((row.input_bits >> @intCast(idx)) & 1);
            try writer.writeByte(if (bit == 1) '1' else '0');
            first = false;
        }
        for (outputs, 0..) |_, idx| {
            if (!first) try writer.writeByte(',');
            try writer.writeByte(stateChar(row.outputs[idx]));
            first = false;
        }
        try writer.writeByte('\n');
    }
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

test "csv_render_and_two_inputs" {
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
        "a,b,result\n" ++
        "0,0,0\n" ++
        "1,0,0\n" ++
        "0,1,0\n" ++
        "1,1,1\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "csv_render_undefined_emits_question_mark" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    const inputs = [_]PinRef{
        .{ .name = "a", .component_id = 0 },
    };
    const outputs = [_]PinRef{
        .{ .name = "out", .component_id = 1 },
    };
    const rows = [_]builder.Row{
        .{ .input_bits = 0, .outputs = &.{.undef} },
        .{ .input_bits = 1, .outputs = &.{.undef} },
    };

    var table = try makeTable(&arena, &inputs, &outputs, &rows);
    defer table.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(test_alloc);
    try render(buf.writer(test_alloc), table);

    const expected =
        "a,out\n" ++
        "0,?\n" ++
        "1,?\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}
