const std = @import("std");
const layout = @import("layout");
const canvas_mod = @import("canvas");
const color_mod = @import("color");

const Canvas = canvas_mod.Canvas;
const ColorTag = color_mod.ColorTag;
const PlacedComponent = layout.PlacedComponent;

/// Monosketch-style labeled rectangles. Every component is a closed box with
/// rounded corners; port locations on the border are stamped with `├` (source)
/// or `┤` (sink) so the box rectangle stays visually intact while the port
/// position is unambiguous. Wires source/sink at the cell immediately outside
/// the corresponding border, so wire glyphs never overwrite box body cells.
pub fn drawComponent(canvas: *Canvas, placed: PlacedComponent) void {
    switch (placed.kind) {
        .primitive => |p| switch (p) {
            .input_pin => drawInputPin(canvas, placed),
            .output_pin => drawOutputPin(canvas, placed),
            .not_gate => drawNotGate(canvas, placed),
            .and_gate => drawAndGate(canvas, placed),
            .led => drawLed(canvas, placed),
            .wire, .slice => unreachable, // collapsed before placement
        },
        .subcircuit => |sub| drawMacroBox(canvas, placed, sub),
    }
    // After drawing the labeled-box body, stamp port T-glyphs onto the box
    // borders at every active port row. This is shared across primitives and
    // subcircuits so the geometry rule lives in one place.
    stampPortBorders(canvas, placed);
}

fn stampPortBorders(canvas: *Canvas, placed: PlacedComponent) void {
    const tag = colorTagFor(placed.kind);
    // Source port: out_port lives one cell EAST of the right border, so the
    // border cell is at (out_port.x - 1, out_port.y).
    if (hasOutPort(placed)) {
        if (placed.out_port.x >= 1) {
            canvas.setCell(placed.out_port.x - 1, placed.out_port.y, "├", tag);
        }
    }
    // Sink ports: in_port lives one cell WEST of the left border, so the
    // border cell is at (in_port.x + 1, in_port.y).
    for (placed.in_ports) |slot| {
        canvas.setCell(slot.coord.x + 1, slot.coord.y, "┤", tag);
    }
}

fn hasOutPort(placed: PlacedComponent) bool {
    // Sinks (output_pin, led) leave out_port at its default; we treat any
    // component with no listed output role as sinkless. Distinguish by kind.
    return switch (placed.kind) {
        .primitive => |p| switch (p) {
            .output_pin, .led, .wire, .slice => false,
            else => true,
        },
        .subcircuit => true,
    };
}

fn colorTagFor(kind: layout.NodeKind) ColorTag {
    return switch (kind) {
        .primitive => |p| switch (p) {
            .input_pin, .output_pin => .input_pin,
            .not_gate => .not_gate,
            .and_gate => .and_gate,
            .led => .led,
            .wire, .slice => .none,
        },
        .subcircuit => .macro,
    };
}

/// Input pin: labeled rectangle showing the variable name. Output port lives
/// at the middle-right border cell (y+1 of a 3-tall box).
pub fn drawInputPin(canvas: *Canvas, placed: PlacedComponent) void {
    drawLabeledBox(canvas, placed.x, placed.y, placed.width, placed.height, placed.name, .input_pin);
}

/// Output pin: labeled rectangle. Input port at middle-left border cell.
pub fn drawOutputPin(canvas: *Canvas, placed: PlacedComponent) void {
    drawLabeledBox(canvas, placed.x, placed.y, placed.width, placed.height, placed.name, .input_pin);
}

/// NOT gate: 5×3 labeled `NOT` box. Single input on left middle row, output on right.
pub fn drawNotGate(canvas: *Canvas, placed: PlacedComponent) void {
    drawLabeledBox(canvas, placed.x, placed.y, placed.width, placed.height, "NOT", .not_gate);
}

/// AND gate: 5×5 labeled `AND` box. Two inputs on rows 1 & 3, output on row 2.
/// The label sits on the same row as the output so the box reads top-to-bottom
/// as `a-port / label-with-output / b-port`.
pub fn drawAndGate(canvas: *Canvas, placed: PlacedComponent) void {
    drawLabeledBox(canvas, placed.x, placed.y, placed.width, placed.height, "AND", .and_gate);
}

/// LED: 5×3 labeled `LED` box. Single input on left middle row.
pub fn drawLed(canvas: *Canvas, placed: PlacedComponent) void {
    drawLabeledBox(canvas, placed.x, placed.y, placed.width, placed.height, "LED", .led);
}

/// Macro box: variable W × H (height grows with input count). Border uses
/// `╭╮╰╯─│`, label `[<sub>:<name>]` centered on the middle row. Ports replace
/// border cells per the renderer's wire-draw pass; this function only draws
/// the box and label.
pub fn drawMacroBox(canvas: *Canvas, placed: PlacedComponent, sub: []const u8) void {
    const tag: ColorTag = .macro;
    const x = placed.x;
    const y = placed.y;
    const w = placed.width;
    const h = placed.height;
    const mid_y = y + h / 2;

    drawBoxBorder(canvas, x, y, w, h, tag);

    // Compose label "[<sub>:<name>]".
    const label_len: u32 = @intCast(sub.len + placed.name.len + 3); // [, :, ]
    if (label_len + 2 <= w) {
        const inner = w - 2;
        const pad: u32 = @intCast((inner - label_len) / 2);
        var col = x + 1 + pad;
        canvas.setCell(col, mid_y, "[", tag);
        col += 1;
        var si: usize = 0;
        while (si < sub.len) : (si += 1) {
            canvas.setCell(col, mid_y, sub[si .. si + 1], tag);
            col += 1;
        }
        canvas.setCell(col, mid_y, ":", tag);
        col += 1;
        var ni: usize = 0;
        while (ni < placed.name.len) : (ni += 1) {
            canvas.setCell(col, mid_y, placed.name[ni .. ni + 1], tag);
            col += 1;
        }
        canvas.setCell(col, mid_y, "]", tag);
    }
}

// ---------- internal helpers ----------

/// Draw a rounded-corner rectangle border at (x, y, w, h) and a single-line
/// label centered on the middle row. Interior cells are filled with spaces so
/// later passes don't see leftover canvas junk.
fn drawLabeledBox(
    canvas: *Canvas,
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    label: []const u8,
    tag: ColorTag,
) void {
    drawBoxBorder(canvas, x, y, w, h, tag);

    // Fill interior with spaces (skip border cells).
    var row: u32 = 1;
    while (row + 1 < h) : (row += 1) {
        var col: u32 = 1;
        while (col + 1 < w) : (col += 1) {
            canvas.setCell(x + col, y + row, " ", tag);
        }
    }

    // Center the label on the middle row, truncating if it wouldn't fit
    // between the side borders.
    const mid_y = y + h / 2;
    const inner: i64 = @as(i64, w) - 2;
    if (inner <= 0) return;
    const max_label: usize = @intCast(inner);
    const label_len: usize = @min(label.len, max_label);
    const inner_u: u32 = @intCast(inner);
    const label_u: u32 = @intCast(label_len);
    const pad: u32 = (inner_u - label_u) / 2;
    var i: usize = 0;
    while (i < label_len) : (i += 1) {
        canvas.setCell(x + 1 + pad + @as(u32, @intCast(i)), mid_y, label[i .. i + 1], tag);
    }
}

fn drawBoxBorder(canvas: *Canvas, x: u32, y: u32, w: u32, h: u32, tag: ColorTag) void {
    if (w == 0 or h == 0) return;

    // Top row.
    canvas.setCell(x, y, "╭", tag);
    var i: u32 = 1;
    while (i + 1 < w) : (i += 1) canvas.setCell(x + i, y, "─", tag);
    if (w >= 2) canvas.setCell(x + w - 1, y, "╮", tag);

    // Bottom row.
    if (h >= 2) {
        canvas.setCell(x, y + h - 1, "╰", tag);
        var j: u32 = 1;
        while (j + 1 < w) : (j += 1) canvas.setCell(x + j, y + h - 1, "─", tag);
        if (w >= 2) canvas.setCell(x + w - 1, y + h - 1, "╯", tag);
    }

    // Left and right side cells (excluding corners).
    var r: u32 = 1;
    while (r + 1 < h) : (r += 1) {
        canvas.setCell(x, y + r, "│", tag);
        if (w >= 2) canvas.setCell(x + w - 1, y + r, "│", tag);
    }
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

test "glyphs_draws_input_pin_box" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const placed = PlacedComponent{
        .id = 0,
        .kind = .{ .primitive = .input_pin },
        .name = "a",
        .origin = &.{},
        .x = 0,
        .y = 0,
        .width = 5,
        .height = 3,
        .in_ports = &.{},
        .out_port = .{ .x = 4, .y = 1 },
    };

    const out = try captureCanvas(std.testing.allocator, a, 5, 3, drawInputPin, placed);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\╭───╮
        \\│ a │
        \\╰───╯
        \\
    , out);
}

test "glyphs_draws_not_gate_box" {
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
    try std.testing.expectEqualStrings(
        \\╭───╮
        \\│NOT│
        \\╰───╯
        \\
    , out);
}

test "glyphs_draws_and_gate_box" {
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
        .height = 5,
        .in_ports = &.{},
        .out_port = .{ .x = 4, .y = 2 },
    };

    const out = try captureCanvas(std.testing.allocator, a, 5, 5, drawAndGate, placed);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\╭───╮
        \\│   │
        \\│AND│
        \\│   │
        \\╰───╯
        \\
    , out);
}

test "glyphs_draws_led_box" {
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
        .width = 5,
        .height = 3,
        .in_ports = &.{},
        .out_port = .{ .x = 4, .y = 1 },
    };

    const out = try captureCanvas(std.testing.allocator, a, 5, 3, drawLed, placed);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\╭───╮
        \\│LED│
        \\╰───╯
        \\
    , out);
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
