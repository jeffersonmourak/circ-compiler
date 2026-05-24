const std = @import("std");
const engine = @import("circuit");
const builder = @import("builder");

const Table = builder.Table;
const PinRef = builder.PinRef;

/// Per-cell value format. Markdown shares the same enum as CSV/JSON;
/// `binary` shows per-bit `0`/`1`/`?` (so partial undefined values are
/// readable), `hex` and `decimal` collapse any undefined-ness to `?`.
pub const ValueFormat = enum { binary, hex, decimal };

fn widthMaskU64(width: u8) u64 {
    if (width == 0) return 0;
    if (width >= 64) return std.math.maxInt(u64);
    return (@as(u64, 1) << @intCast(width)) - 1;
}

/// Returns the rendered length of a multi-bit value in the given format.
/// Used to size table columns so cell rendering and the separator row
/// agree on column widths.
fn cellWidthForFormat(state_width: u8, format: ValueFormat) usize {
    if (state_width == 0) return 1;
    return switch (format) {
        .binary => @as(usize, state_width),
        .hex => (@as(usize, state_width) + 3) / 4,
        .decimal => decimalWidthForBits(state_width),
    };
}

fn decimalWidthForBits(width: u8) usize {
    if (width == 0) return 1;
    const max_value: u64 = widthMaskU64(width);
    var digits: usize = 0;
    var v: u64 = max_value;
    while (true) {
        digits += 1;
        v /= 10;
        if (v == 0) break;
    }
    return digits;
}

fn headerNameWidth(pin: PinRef) usize {
    if (pin.width <= 1) return @max(pin.name.len, 1);
    // `name[N]` rendering: name + `[` + decimal-of-N + `]`.
    var n_digits: usize = 0;
    var n: u32 = pin.width;
    while (true) {
        n_digits += 1;
        n /= 10;
        if (n == 0) break;
    }
    return pin.name.len + 2 + n_digits;
}

fn columnWidth(pin: PinRef, format: ValueFormat) usize {
    return @max(headerNameWidth(pin), cellWidthForFormat(pin.width, format));
}

fn writeHeaderName(writer: anytype, pin: PinRef) !void {
    if (pin.width <= 1) {
        try writer.writeAll(pin.name);
    } else {
        try writer.print("{s}[{d}]", .{ pin.name, pin.width });
    }
}

fn writePaddedHeader(writer: anytype, pin: PinRef, total_width: usize) !void {
    try writer.writeByte(' ');
    try writeHeaderName(writer, pin);
    const used = headerNameWidth(pin);
    var pad: usize = if (total_width >= used) total_width - used else 0;
    while (pad > 0) : (pad -= 1) try writer.writeByte(' ');
    try writer.writeByte(' ');
}

fn writePaddedCell(writer: anytype, state: engine.BitVecState, total_width: usize, format: ValueFormat) !void {
    try writer.writeByte(' ');
    var written: usize = 0;

    if (state.isUndefined()) {
        try writer.writeByte('?');
        written = 1;
    } else {
        const expected = widthMaskU64(state.width);
        const fully_defined = state.defined == expected;
        switch (format) {
            .binary => {
                // Per-bit, MSB first. Undefined bits render as `?`.
                if (state.width == 0) {
                    try writer.writeByte('?');
                    written = 1;
                } else {
                    var bit: i32 = @as(i32, @intCast(state.width)) - 1;
                    while (bit >= 0) : (bit -= 1) {
                        const mask: u64 = @as(u64, 1) << @intCast(bit);
                        const defined_bit = (state.defined & mask) != 0;
                        const value_bit = (state.value & mask) != 0;
                        if (!defined_bit) try writer.writeByte('?') else try writer.writeByte(if (value_bit) '1' else '0');
                        written += 1;
                    }
                }
            },
            .hex => {
                if (!fully_defined) {
                    try writer.writeByte('?');
                    written = 1;
                } else {
                    const digits = (@as(usize, state.width) + 3) / 4;
                    var digit_idx: i32 = @intCast(digits);
                    digit_idx -= 1;
                    while (digit_idx >= 0) : (digit_idx -= 1) {
                        const shift: u6 = @intCast(@as(u32, @intCast(digit_idx)) * 4);
                        const nibble: u8 = @intCast((state.value >> shift) & 0xF);
                        const ch: u8 = if (nibble < 10) '0' + nibble else 'A' + (nibble - 10);
                        try writer.writeByte(ch);
                        written += 1;
                    }
                }
            },
            .decimal => {
                if (!fully_defined) {
                    try writer.writeByte('?');
                    written = 1;
                } else {
                    // Format into a small stack buffer so we know how
                    // many characters we wrote before padding the cell.
                    var dec_buf: [24]u8 = undefined;
                    const slice = try std.fmt.bufPrint(&dec_buf, "{d}", .{state.value & expected});
                    try writer.writeAll(slice);
                    written = slice.len;
                }
            },
        }
    }

    var pad: usize = if (total_width >= written) total_width - written else 0;
    while (pad > 0) : (pad -= 1) try writer.writeByte(' ');
    try writer.writeByte(' ');
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

    // Header row.
    try writer.writeByte('|');
    for (inputs) |pin| {
        try writePaddedHeader(writer, pin, columnWidth(pin, format));
        try writer.writeByte('|');
    }
    for (outputs) |pin| {
        try writePaddedHeader(writer, pin, columnWidth(pin, format));
        try writer.writeByte('|');
    }
    try writer.writeByte('\n');

    // Separator row: each column has (width + 2) dashes between pipes.
    try writer.writeByte('|');
    for (inputs) |pin| {
        var n = columnWidth(pin, format) + 2;
        while (n > 0) : (n -= 1) try writer.writeByte('-');
        try writer.writeByte('|');
    }
    for (outputs) |pin| {
        var n = columnWidth(pin, format) + 2;
        while (n > 0) : (n -= 1) try writer.writeByte('-');
        try writer.writeByte('|');
    }
    try writer.writeByte('\n');

    // Data rows.
    for (table.rows) |row| {
        try writer.writeByte('|');
        for (inputs, 0..) |pin, idx| {
            const state = extractInputValue(row, inputs, idx);
            try writePaddedCell(writer, state, columnWidth(pin, format), format);
            try writer.writeByte('|');
        }
        for (outputs, 0..) |pin, idx| {
            try writePaddedCell(writer, row.outputs[idx], columnWidth(pin, format), format);
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

test "markdown_render_and_two_inputs" {
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
        "| a | out |\n" ++
        "|---|-----|\n" ++
        "| 0 | ?   |\n" ++
        "| 1 | ?   |\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "markdown_render_multi_bit_binary_header_carries_width" {
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

    // Both columns are 4 chars wide (the cell content `1101`, equal to
    // the header `a[4]`).
    const expected =
        "| a[4] | r[4] |\n" ++
        "|------|------|\n" ++
        "| 1101 | 1101 |\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "markdown_render_multi_bit_hex_uses_one_digit_per_nibble" {
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

    // Header `a[4]` is 4 chars; cell `D` is 1 char. Column width is
    // max(4, 1) = 4, so the cell needs padding.
    const expected =
        "| a[4] | r[4] |\n" ++
        "|------|------|\n" ++
        "| D    | D    |\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}
