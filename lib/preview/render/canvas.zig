const std = @import("std");
const color_mod = @import("color");

pub const ColorTag = color_mod.ColorTag;

/// In-memory character grid with per-cell color tags. Each cell holds a
/// `[]const u8` slice — typically a static UTF-8 string literal ("─", "╭", "X")
/// — letting box-drawing characters coexist with ASCII at no extra bookkeeping.
/// Default cell content is a single space; default tag is `.none`.
///
/// Coordinates: row-major, (x, y) where x is the column and y is the row.
/// `setCell` and the segment drawers silently no-op on out-of-bounds writes
/// rather than erroring — the renderer's algorithms compute coordinates that
/// should always fit inside the canvas, but defensive bounds-checking is cheap
/// insurance against off-by-one geometry mistakes during slice-4 development.
///
/// `writeOut` interleaves ANSI escape sequences with cell bytes when
/// `use_color = true`. Color resets are emitted at every tag transition (so
/// adjacent cells with different tags get distinct sequences) and at end-of-row
/// (so terminals that trim trailing whitespace don't carry color into the next
/// line). When `use_color = false`, output is pure cell bytes plus newlines —
/// no escape bytes (asserted by tests).
pub const Canvas = struct {
    width: u32,
    height: u32,
    cells: [][]const u8,
    color: []ColorTag,

    pub fn init(arena: std.mem.Allocator, width: u32, height: u32) !Canvas {
        const total = @as(usize, width) * @as(usize, height);
        const cells = try arena.alloc([]const u8, total);
        for (cells) |*c| c.* = " ";
        const color_buf = try arena.alloc(ColorTag, total);
        @memset(color_buf, .none);
        return .{ .width = width, .height = height, .cells = cells, .color = color_buf };
    }

    pub fn setCell(self: *Canvas, x: u32, y: u32, ch_bytes: []const u8, tag: ColorTag) void {
        if (x >= self.width or y >= self.height) return;
        const idx = @as(usize, y) * @as(usize, self.width) + @as(usize, x);
        self.cells[idx] = ch_bytes;
        self.color[idx] = tag;
    }

    pub fn drawHSegment(self: *Canvas, from_x: u32, to_x: u32, y: u32, ch_bytes: []const u8, tag: ColorTag) void {
        const lo = @min(from_x, to_x);
        const hi = @max(from_x, to_x);
        var x = lo;
        while (x <= hi) : (x += 1) self.setCell(x, y, ch_bytes, tag);
    }

    pub fn drawVSegment(self: *Canvas, x: u32, from_y: u32, to_y: u32, ch_bytes: []const u8, tag: ColorTag) void {
        const lo = @min(from_y, to_y);
        const hi = @max(from_y, to_y);
        var y = lo;
        while (y <= hi) : (y += 1) self.setCell(x, y, ch_bytes, tag);
    }

    pub fn writeOut(self: Canvas, writer: anytype, use_color: bool) !void {
        var current_tag: ColorTag = .none;
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                const idx = @as(usize, y) * @as(usize, self.width) + @as(usize, x);
                const tag = self.color[idx];
                if (use_color and tag != current_tag) {
                    if (current_tag != .none) try writer.writeAll(color_mod.ANSI_RESET);
                    if (tag != .none) try writer.writeAll(color_mod.ansiFor(tag));
                    current_tag = tag;
                }
                try writer.writeAll(self.cells[idx]);
            }
            // Always reset at end of row so color never leaks past a newline.
            if (use_color and current_tag != .none) {
                try writer.writeAll(color_mod.ANSI_RESET);
                current_tag = .none;
            }
            try writer.writeByte('\n');
        }
    }
};

// ---------- Tests ----------

test "canvas_set_cell" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var canvas = try Canvas.init(arena.allocator(), 4, 3);

    canvas.setCell(2, 1, "X", .none);

    const idx = 1 * 4 + 2;
    try std.testing.expectEqualStrings("X", canvas.cells[idx]);
    try std.testing.expectEqual(ColorTag.none, canvas.color[idx]);

    // Out-of-bounds writes are silently dropped.
    canvas.setCell(99, 99, "Z", .none);
    // (No assertion needed — surviving without panic is the test.)
}

test "canvas_draw_h_segment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var canvas = try Canvas.init(arena.allocator(), 6, 3);

    canvas.drawHSegment(0, 4, 2, "─", .wire);

    var x: u32 = 0;
    while (x <= 4) : (x += 1) {
        const idx = 2 * 6 + x;
        try std.testing.expectEqualStrings("─", canvas.cells[idx]);
        try std.testing.expectEqual(ColorTag.wire, canvas.color[idx]);
    }
    // Cells outside the segment stay default (" ", .none).
    const beyond_idx = 2 * 6 + 5;
    try std.testing.expectEqualStrings(" ", canvas.cells[beyond_idx]);
    try std.testing.expectEqual(ColorTag.none, canvas.color[beyond_idx]);
}

test "canvas_draw_v_segment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var canvas = try Canvas.init(arena.allocator(), 4, 5);

    canvas.drawVSegment(2, 1, 3, "│", .wire);

    var y: u32 = 1;
    while (y <= 3) : (y += 1) {
        const idx = y * 4 + 2;
        try std.testing.expectEqualStrings("│", canvas.cells[idx]);
        try std.testing.expectEqual(ColorTag.wire, canvas.color[idx]);
    }
    // Row 0 and row 4 at column 2 stay default.
    try std.testing.expectEqualStrings(" ", canvas.cells[0 * 4 + 2]);
    try std.testing.expectEqualStrings(" ", canvas.cells[4 * 4 + 2]);
}

test "canvas_write_out_no_color" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var canvas = try Canvas.init(arena.allocator(), 3, 2);

    // Mixed tags — but use_color = false should produce no escape bytes.
    canvas.setCell(0, 0, "A", .input_pin);
    canvas.setCell(1, 0, "B", .led);
    canvas.setCell(2, 0, "C", .wire);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try canvas.writeOut(buf.writer(allocator), false);

    // No ESC byte (\x1b = 0x1B) anywhere.
    for (buf.items) |b| try std.testing.expect(b != 0x1B);

    // Content is the cells separated by newlines.
    try std.testing.expectEqualStrings("ABC\n   \n", buf.items);
}

test "canvas_write_out_with_color" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var canvas = try Canvas.init(arena.allocator(), 2, 1);

    canvas.setCell(0, 0, "A", .input_pin); // green
    canvas.setCell(1, 0, "B", .led); // yellow

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try canvas.writeOut(buf.writer(allocator), true);

    // Output contains: ESC[32m A ESC[0m ESC[33m B ESC[0m \n
    // Verify ESC bytes are present and the tag-boundary resets fire.
    var saw_esc = false;
    for (buf.items) |b| {
        if (b == 0x1B) {
            saw_esc = true;
            break;
        }
    }
    try std.testing.expect(saw_esc);

    // Specifically check that A and B appear with the right escapes around them.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\x1b[32mA") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\x1b[33mB") != null);
    // Reset before newline.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\x1b[0m\n") != null);
}
