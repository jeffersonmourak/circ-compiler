const std = @import("std");
const engine = @import("circuit");
const builder = @import("builder");

const Table = builder.Table;
const PinRef = builder.PinRef;

/// Per-cell value format. Selects the textual representation of an
/// input or output bit-vector; the row-shape of CSV is unchanged.
pub const ValueFormat = enum { binary, hex, decimal };

fn widthMaskU64(width: u8) u64 {
    if (width == 0) return 0;
    if (width >= 64) return std.math.maxInt(u64);
    return (@as(u64, 1) << @intCast(width)) - 1;
}

fn writeHeaderName(writer: anytype, pin: PinRef) !void {
    // Scalar columns keep the bare name (e.g. `a`) so existing scalar
    // golden files stay byte-identical; multi-bit columns carry the
    // width annotation `a[N]` to make per-column widths visible.
    if (pin.width <= 1) {
        try writer.writeAll(pin.name);
    } else {
        try writer.print("{s}[{d}]", .{ pin.name, pin.width });
    }
}

/// Emits the per-bit "0/1/?" string for a `BitVecState`. Used when the
/// format is `binary` so individual undefined bits are visible; the
/// non-binary formats collapse any undefined-ness to a single `?`.
fn writeBinaryBits(writer: anytype, state: engine.BitVecState) !void {
    if (state.width == 0) {
        try writer.writeByte('?');
        return;
    }
    var bit: i32 = @as(i32, @intCast(state.width)) - 1;
    while (bit >= 0) : (bit -= 1) {
        const mask: u64 = @as(u64, 1) << @intCast(bit);
        const defined_bit = (state.defined & mask) != 0;
        const value_bit = (state.value & mask) != 0;
        if (!defined_bit) {
            try writer.writeByte('?');
        } else {
            try writer.writeByte(if (value_bit) '1' else '0');
        }
    }
}

fn writeValueCell(writer: anytype, state: engine.BitVecState, format: ValueFormat) !void {
    if (state.isUndefined()) {
        try writer.writeByte('?');
        return;
    }
    const expected_defined = widthMaskU64(state.width);
    const fully_defined = state.defined == expected_defined;

    switch (format) {
        .binary => try writeBinaryBits(writer, state),
        .hex => {
            if (!fully_defined) {
                try writer.writeByte('?');
                return;
            }
            // ceil(width/4) hex digits; uppercase, no `0x` prefix.
            const digits = (@as(usize, state.width) + 3) / 4;
            var digit_idx: i32 = @intCast(digits);
            digit_idx -= 1;
            while (digit_idx >= 0) : (digit_idx -= 1) {
                const shift: u6 = @intCast(@as(u32, @intCast(digit_idx)) * 4);
                const nibble: u8 = @intCast((state.value >> shift) & 0xF);
                const ch: u8 = if (nibble < 10) '0' + nibble else 'A' + (nibble - 10);
                try writer.writeByte(ch);
            }
        },
        .decimal => {
            if (!fully_defined) {
                try writer.writeByte('?');
                return;
            }
            try writer.print("{d}", .{state.value & expected_defined});
        },
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

    // Header row. CSV cells are unquoted because pin names from the IR can't
    // contain commas, quotes, or newlines (the parser's identifier rules).
    var first = true;
    for (inputs) |pin| {
        if (!first) try writer.writeByte(',');
        try writeHeaderName(writer, pin);
        first = false;
    }
    for (outputs) |pin| {
        if (!first) try writer.writeByte(',');
        try writeHeaderName(writer, pin);
        first = false;
    }
    try writer.writeByte('\n');

    // Data rows.
    for (table.rows) |row| {
        first = true;
        for (inputs, 0..) |_, idx| {
            if (!first) try writer.writeByte(',');
            const state = extractInputValue(row, inputs, idx);
            try writeValueCell(writer, state, format);
            first = false;
        }
        for (outputs, 0..) |_, idx| {
            if (!first) try writer.writeByte(',');
            try writeValueCell(writer, row.outputs[idx], format);
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

test "csv_render_and_two_inputs" {
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
        .{ .name = "a", .component_id = 0, .width = 1 },
    };
    const outputs = [_]PinRef{
        .{ .name = "out", .component_id = 1, .width = 1 },
    };
    const rows = [_]builder.Row{
        .{ .input_bits = 0, .outputs = &.{undefState()} },
        .{ .input_bits = 1, .outputs = &.{undefState()} },
    };

    var table = try makeTable(&arena, &inputs, &outputs, &rows);
    defer table.deinit();

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(test_alloc);
    try render(buf.writer(test_alloc), table, .binary);

    const expected =
        "a,out\n" ++
        "0,?\n" ++
        "1,?\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "csv_render_multi_bit_binary_format" {
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

    // Header has `[4]` decoration for multi-bit columns; cells render 4-bit
    // binary big-endian (MSB first) so reading top-to-bottom matches the
    // hex/decimal interpretations.
    const expected =
        "a[4],r[4]\n" ++
        "1101,1101\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "csv_render_multi_bit_hex_format" {
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
        "a[4],r[4]\n" ++
        "D,D\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "csv_render_multi_bit_decimal_format" {
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
    try render(buf.writer(test_alloc), table, .decimal);

    const expected =
        "a[4],r[4]\n" ++
        "13,13\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}
