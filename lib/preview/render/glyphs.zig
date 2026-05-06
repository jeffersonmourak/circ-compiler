const std = @import("std");
const layout = @import("layout");
const canvas_mod = @import("canvas");
const color_mod = @import("color");

const Canvas = canvas_mod.Canvas;
const ColorTag = color_mod.ColorTag;
const PlacedComponent = layout.PlacedComponent;

/// Slice 3 glyph art. Each kind's drawing function fills the bounding box of
/// its `PlacedComponent` with the canonical schematic-style glyphs and tags
/// every cell with the appropriate `ColorTag`. Wire renderings are deferred
/// to slice 4's orchestrator.
pub fn drawComponent(canvas: *Canvas, placed: PlacedComponent) void {
    switch (placed.kind) {
        .primitive => |p| switch (p) {
            .input_pin => drawInputPin(canvas, placed),
            .output_pin => drawOutputPin(canvas, placed),
            .not_gate => drawNotGate(canvas, placed),
            .and_gate => drawAndGate(canvas, placed),
            .led => drawLed(canvas, placed),
            .wire => unreachable, // collapsed before placement
        },
        .subcircuit => |sub| drawMacroBox(canvas, placed, sub),
    }
}

/// Input pin: `name──` left-aligned on a single row. Names longer than
/// `width - 2` get truncated; shorter names pad on the right with `─`.
pub fn drawInputPin(canvas: *Canvas, placed: PlacedComponent) void {
    const tag: ColorTag = .input_pin;
    const w = placed.width;
    const name_max = @min(placed.name.len, @as(usize, w -| 2));
    var i: u32 = 0;
    while (i < @as(u32, @intCast(name_max))) : (i += 1) {
        canvas.setCell(placed.x + i, placed.y, placed.name[i .. i + 1], tag);
    }
    while (i < w) : (i += 1) {
        canvas.setCell(placed.x + i, placed.y, "─", tag);
    }
}

/// Output pin: `──name` right-aligned on a single row. Mirrors input_pin.
pub fn drawOutputPin(canvas: *Canvas, placed: PlacedComponent) void {
    const tag: ColorTag = .input_pin; // share the pin-style color tag
    const w = placed.width;
    const name_max = @min(placed.name.len, @as(usize, w -| 2));
    const pad = w - @as(u32, @intCast(name_max));
    var i: u32 = 0;
    while (i < pad) : (i += 1) {
        canvas.setCell(placed.x + i, placed.y, "─", tag);
    }
    var j: usize = 0;
    while (j < name_max) : (j += 1) {
        canvas.setCell(placed.x + pad + @as(u32, @intCast(j)), placed.y, placed.name[j .. j + 1], tag);
    }
}

/// NOT gate: 5×3. Single-row glyph `─▷○──` on the middle row, blank above and
/// below. Ports: `in` at (x, y+1), `out` at (x+4, y+1).
pub fn drawNotGate(canvas: *Canvas, placed: PlacedComponent) void {
    const tag: ColorTag = .not_gate;
    const x = placed.x;
    const y = placed.y;
    canvas.setCell(x + 0, y + 1, "─", tag);
    canvas.setCell(x + 1, y + 1, "▷", tag);
    canvas.setCell(x + 2, y + 1, "○", tag);
    canvas.setCell(x + 3, y + 1, "─", tag);
    canvas.setCell(x + 4, y + 1, "─", tag);
}

/// AND gate: 5×3. Top corner `─╮`, middle `│───` extending toward the output,
/// bottom corner `─╯`. Ports: `a` at (x, y), `b` at (x, y+2), `out` at (x+4, y+1).
pub fn drawAndGate(canvas: *Canvas, placed: PlacedComponent) void {
    const tag: ColorTag = .and_gate;
    const x = placed.x;
    const y = placed.y;
    canvas.setCell(x + 0, y + 0, "─", tag);
    canvas.setCell(x + 1, y + 0, "╮", tag);
    canvas.setCell(x + 1, y + 1, "│", tag);
    canvas.setCell(x + 2, y + 1, "─", tag);
    canvas.setCell(x + 3, y + 1, "─", tag);
    canvas.setCell(x + 4, y + 1, "─", tag);
    canvas.setCell(x + 0, y + 2, "─", tag);
    canvas.setCell(x + 1, y + 2, "╯", tag);
}

/// LED: 3×3. `─◉ ` on the middle row. Port: `in` at (x, y+1).
pub fn drawLed(canvas: *Canvas, placed: PlacedComponent) void {
    const tag: ColorTag = .led;
    const x = placed.x;
    const y = placed.y;
    canvas.setCell(x + 0, y + 1, "─", tag);
    canvas.setCell(x + 1, y + 1, "◉", tag);
}

/// Macro box: variable W × 3. Border uses `╭╮╰╯─│`, label `[<sub>:<name>]`
/// centered on the middle row. Ports replace border cells per slice 4's
/// renderer pass; this function only draws the box and label.
pub fn drawMacroBox(canvas: *Canvas, placed: PlacedComponent, sub: []const u8) void {
    const tag: ColorTag = .macro;
    const x = placed.x;
    const y = placed.y;
    const w = placed.width;

    // Top border.
    canvas.setCell(x, y, "╭", tag);
    var i: u32 = 1;
    while (i + 1 < w) : (i += 1) {
        canvas.setCell(x + i, y, "─", tag);
    }
    canvas.setCell(x + w - 1, y, "╮", tag);

    // Middle row: side borders + centered label.
    canvas.setCell(x, y + 1, "│", tag);
    canvas.setCell(x + w - 1, y + 1, "│", tag);
    // Fill interior with spaces first.
    var k: u32 = 1;
    while (k + 1 < w) : (k += 1) {
        canvas.setCell(x + k, y + 1, " ", tag);
    }
    // Compose label "[<sub>:<name>]".
    const label_len: u32 = @intCast(sub.len + placed.name.len + 3); // [, :, ]
    if (label_len + 2 <= w) {
        const inner = w - 2;
        const pad: u32 = @intCast((inner - label_len) / 2);
        var col = x + 1 + pad;
        canvas.setCell(col, y + 1, "[", tag);
        col += 1;
        var si: usize = 0;
        while (si < sub.len) : (si += 1) {
            canvas.setCell(col, y + 1, sub[si .. si + 1], tag);
            col += 1;
        }
        canvas.setCell(col, y + 1, ":", tag);
        col += 1;
        var ni: usize = 0;
        while (ni < placed.name.len) : (ni += 1) {
            canvas.setCell(col, y + 1, placed.name[ni .. ni + 1], tag);
            col += 1;
        }
        canvas.setCell(col, y + 1, "]", tag);
    }

    // Bottom border.
    canvas.setCell(x, y + 2, "╰", tag);
    var j: u32 = 1;
    while (j + 1 < w) : (j += 1) {
        canvas.setCell(x + j, y + 2, "─", tag);
    }
    canvas.setCell(x + w - 1, y + 2, "╯", tag);
}

// ---------- Tests ----------

const NodeKind = layout.NodeKind;
const PortSlot = layout.PortSlot;

fn captureCanvas(allocator: std.mem.Allocator, arena: std.mem.Allocator, w: u32, h: u32, draw: anytype, placed: PlacedComponent) ![]u8 {
    var canvas = try Canvas.init(arena, w, h);
    draw(&canvas, placed);
    var buf: std.ArrayList(u8) = .{};
    try canvas.writeOut(buf.writer(allocator), false);
    return buf.toOwnedSlice(allocator);
}

test "glyphs_draws_input_pin" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const placed = PlacedComponent{
        .id = 0,
        .kind = .{ .primitive = .input_pin },
        .name = "pin1",
        .origin = &.{},
        .x = 0,
        .y = 0,
        .width = 6,
        .height = 1,
        .in_ports = &.{},
        .out_port = .{ .x = 5, .y = 0 },
    };

    const out = try captureCanvas(std.testing.allocator, a, 6, 1, drawInputPin, placed);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("pin1──\n", out);
}

test "glyphs_draws_not_gate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const placed = PlacedComponent{
        .id = 0,
        .kind = .{ .primitive = .not_gate },
        .name = "n",
        .origin = &.{},
        .x = 0,
        .y = 0,
        .width = 5,
        .height = 3,
        .in_ports = &.{},
        .out_port = .{ .x = 4, .y = 1 },
    };

    const out = try captureCanvas(std.testing.allocator, a, 5, 3, drawNotGate, placed);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("     \n─▷○──\n     \n", out);
}

test "glyphs_draws_and_gate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const placed = PlacedComponent{
        .id = 0,
        .kind = .{ .primitive = .and_gate },
        .name = "g",
        .origin = &.{},
        .x = 0,
        .y = 0,
        .width = 5,
        .height = 3,
        .in_ports = &.{},
        .out_port = .{ .x = 4, .y = 1 },
    };

    const out = try captureCanvas(std.testing.allocator, a, 5, 3, drawAndGate, placed);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("─╮   \n │───\n─╯   \n", out);
}

test "glyphs_draws_led" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const placed = PlacedComponent{
        .id = 0,
        .kind = .{ .primitive = .led },
        .name = "l",
        .origin = &.{},
        .x = 0,
        .y = 0,
        .width = 3,
        .height = 3,
        .in_ports = &.{},
        .out_port = .{ .x = 2, .y = 1 },
    };

    const out = try captureCanvas(std.testing.allocator, a, 3, 3, drawLed, placed);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("   \n─◉ \n   \n", out);
}

test "glyphs_draws_macro_box" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // sub="xor" name="combine" → label "[xor:combine]" (13 chars), width = max(8, 13+2) = 15.
    const placed = PlacedComponent{
        .id = 0,
        .kind = .{ .subcircuit = "xor" },
        .name = "combine",
        .origin = &.{},
        .x = 0,
        .y = 0,
        .width = 15,
        .height = 3,
        .in_ports = &.{},
        .out_port = .{ .x = 14, .y = 1 },
    };

    var canvas = try Canvas.init(a, 15, 3);
    drawMacroBox(&canvas, placed, "xor");
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    try canvas.writeOut(buf.writer(std.testing.allocator), false);

    try std.testing.expectEqualStrings(
        \\╭─────────────╮
        \\│[xor:combine]│
        \\╰─────────────╯
        \\
    , buf.items);
}
