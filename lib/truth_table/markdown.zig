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

fn writePaddedCell(writer: anytype, content: []const u8, width: usize) !void {
    try writer.writeByte(' ');
    try writer.writeAll(content);
    var pad = width - content.len;
    while (pad > 0) : (pad -= 1) try writer.writeByte(' ');
    try writer.writeByte(' ');
}

fn writePaddedChar(writer: anytype, c: u8, width: usize) !void {
    try writer.writeByte(' ');
    try writer.writeByte(c);
    var pad = width - 1;
    while (pad > 0) : (pad -= 1) try writer.writeByte(' ');
    try writer.writeByte(' ');
}

fn columnWidth(pin: PinRef) usize {
    return @max(pin.name.len, 1);
}

pub fn render(writer: anytype, table: Table) !void {
    const inputs = table.header.inputs;
    const outputs = table.header.outputs;

    // Header row.
    try writer.writeByte('|');
    for (inputs) |pin| {
        try writePaddedCell(writer, pin.name, columnWidth(pin));
        try writer.writeByte('|');
    }
    for (outputs) |pin| {
        try writePaddedCell(writer, pin.name, columnWidth(pin));
        try writer.writeByte('|');
    }
    try writer.writeByte('\n');

    // Separator row: each column has (width + 2) dashes between pipes.
    try writer.writeByte('|');
    for (inputs) |pin| {
        var n = columnWidth(pin) + 2;
        while (n > 0) : (n -= 1) try writer.writeByte('-');
        try writer.writeByte('|');
    }
    for (outputs) |pin| {
        var n = columnWidth(pin) + 2;
        while (n > 0) : (n -= 1) try writer.writeByte('-');
        try writer.writeByte('|');
    }
    try writer.writeByte('\n');

    // Data rows.
    for (table.rows) |row| {
        try writer.writeByte('|');
        for (inputs, 0..) |pin, idx| {
            const bit: u8 = @intCast((row.input_bits >> @intCast(idx)) & 1);
            const ch: u8 = if (bit == 1) '1' else '0';
            try writePaddedChar(writer, ch, columnWidth(pin));
            try writer.writeByte('|');
        }
        for (outputs, 0..) |pin, idx| {
            try writePaddedChar(writer, stateChar(row.outputs[idx]), columnWidth(pin));
            try writer.writeByte('|');
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

test "markdown_render_and_two_inputs" {
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
        "| a | b | result |\n" ++
        "|---|---|--------|\n" ++
        "| 0 | 0 | 0      |\n" ++
        "| 1 | 0 | 0      |\n" ++
        "| 0 | 1 | 0      |\n" ++
        "| 1 | 1 | 1      |\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "markdown_render_undefined_emits_question" {
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
        "| a | out |\n" ++
        "|---|-----|\n" ++
        "| 0 | ?   |\n" ++
        "| 1 | ?   |\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}
