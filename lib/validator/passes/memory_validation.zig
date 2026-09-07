const std = @import("std");
const diagnostics = @import("diagnostics");
const ir = @import("ir_types");

/// `BitVecState` carries at most 64 bits.
pub const MAX_DATA_WIDTH: u8 = 64;
/// 65,536 words; keeps a memory's cell planes at ~1 MiB.
pub const MAX_ADDR_WIDTH: u8 = 16;

pub const Side = enum { from, to };

/// Single source of truth for memory port widths. `side == .to` answers
/// "what width does this input port expect"; `side == .from` answers "what
/// width does this output port drive". Unknown ports yield null (the port
/// validity pass reports them separately).
pub fn memoryPortWidth(mem: ir.Memory, port: []const u8, side: Side) ?u8 {
    return switch (side) {
        .from => if (std.mem.eql(u8, port, "out")) mem.data_width else null,
        .to => if (std.mem.eql(u8, port, "addr"))
            mem.addr_width
        else if (mem.mode == .ram and std.mem.eql(u8, port, "din"))
            mem.data_width
        else if (mem.mode == .ram and (std.mem.eql(u8, port, "we") or std.mem.eql(u8, port, "clk")))
            1
        else
            null,
    };
}

fn toDiagnosticSpan(span: ir.Span) diagnostics.Span {
    return .{
        .file_id = span.file_id,
        .start_line = span.start_line,
        .start_col = span.start_col,
        .end_line = span.end_line,
        .end_col = span.end_col,
    };
}

fn append(
    allocator: std.mem.Allocator,
    diagnostic_list: *diagnostics.DiagnosticList,
    code: diagnostics.DiagnosticCode,
    span: ir.Span,
    message: []const u8,
) !void {
    var diagnostic = diagnostics.makeDiagnostic(code, toDiagnosticSpan(span));
    diagnostic.message = message;
    try diagnostic_list.append(allocator, diagnostic);
}

/// E017 for a malformed `[W, A]` list (wrong count, or a width in the type
/// position), then E018 for out-of-range widths. E018 is skipped when E017
/// fired because the resolver's placeholder widths are not the user's.
pub fn run(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    for (module.components) |component| {
        const mem = switch (component.kind) {
            .memory => |m| m,
            else => continue,
        };
        const name = component.instance_name orelse "<anonymous>";
        const example_name = component.instance_name orelse "m";
        const keyword = @tagName(mem.mode);

        if (mem.arg_count != 2) {
            const message = if (mem.arg_count == 0)
                try std.fmt.allocPrint(
                    allocator,
                    "memory '{s}' requires exactly two width arguments [W, A]; got 0 (write '{s} {s}[W, A](...)' on its own line)",
                    .{ name, keyword, example_name },
                )
            else
                try std.fmt.allocPrint(
                    allocator,
                    "memory '{s}' requires exactly two width arguments [W, A]; got {d}",
                    .{ name, mem.arg_count },
                );
            try append(allocator, diagnostic_list, .E017, component.span, message);
            continue;
        }

        if (mem.type_width_given) {
            const message = try std.fmt.allocPrint(
                allocator,
                "memory '{s}': the width annotation goes in the instance position; write '{s} {s}[{d}, {d}](...)' with no width after '{s}'",
                .{ name, keyword, example_name, mem.data_width, mem.addr_width, keyword },
            );
            try append(allocator, diagnostic_list, .E017, component.span, message);
            continue;
        }

        if (mem.data_width == 0) {
            const message = try std.fmt.allocPrint(allocator, "memory '{s}': data width 0 must be 1..{d}", .{ name, MAX_DATA_WIDTH });
            try append(allocator, diagnostic_list, .E018, component.span, message);
        } else if (mem.data_width > MAX_DATA_WIDTH) {
            const message = try std.fmt.allocPrint(allocator, "memory '{s}': data width {d} exceeds {d}", .{ name, mem.data_width, MAX_DATA_WIDTH });
            try append(allocator, diagnostic_list, .E018, component.span, message);
        }

        if (mem.addr_width == 0) {
            const message = try std.fmt.allocPrint(allocator, "memory '{s}': address width 0 must be 1..{d}", .{ name, MAX_ADDR_WIDTH });
            try append(allocator, diagnostic_list, .E018, component.span, message);
        } else if (mem.addr_width > MAX_ADDR_WIDTH) {
            const message = try std.fmt.allocPrint(
                allocator,
                "memory '{s}': address width {d} exceeds {d} ({d} words)",
                .{ name, mem.addr_width, MAX_ADDR_WIDTH, @as(u32, 1) << MAX_ADDR_WIDTH },
            );
            try append(allocator, diagnostic_list, .E018, component.span, message);
        }
    }
}

// ---------- Tests ----------

const test_span = ir.Span{ .file_id = 0, .start_line = 2, .start_col = 1, .end_line = 2, .end_col = 20 };

fn memoryComponent(mem: ir.Memory) ir.Component {
    return .{
        .id = .{ .value = 0 },
        .kind = .{ .memory = mem },
        .instance_name = "m",
        .span = test_span,
        .width = mem.data_width,
    };
}

fn runOn(allocator: std.mem.Allocator, components: []const ir.Component) !diagnostics.DiagnosticList {
    const module = ir.Module{
        .file_id = .{ .value = 0 },
        .inputs = &.{},
        .outputs = &.{},
        .components = components,
        .connections = &.{},
        .imports = &.{},
    };
    var list = diagnostics.initDiagnosticList();
    try run(allocator, &module, &list);
    return list;
}

test "memoryPortWidth contract" {
    const rom = ir.Memory{ .mode = .rom, .data_width = 8, .addr_width = 4, .arg_count = 2, .type_width_given = false };
    try std.testing.expectEqual(@as(?u8, 4), memoryPortWidth(rom, "addr", .to));
    try std.testing.expectEqual(@as(?u8, 8), memoryPortWidth(rom, "out", .from));
    try std.testing.expectEqual(@as(?u8, null), memoryPortWidth(rom, "din", .to));
    try std.testing.expectEqual(@as(?u8, null), memoryPortWidth(rom, "we", .to));
    try std.testing.expectEqual(@as(?u8, null), memoryPortWidth(rom, "clk", .to));
    try std.testing.expectEqual(@as(?u8, null), memoryPortWidth(rom, "addr", .from));

    const ram = ir.Memory{ .mode = .ram, .data_width = 12, .addr_width = 2, .arg_count = 2, .type_width_given = false };
    try std.testing.expectEqual(@as(?u8, 2), memoryPortWidth(ram, "addr", .to));
    try std.testing.expectEqual(@as(?u8, 12), memoryPortWidth(ram, "din", .to));
    try std.testing.expectEqual(@as(?u8, 1), memoryPortWidth(ram, "we", .to));
    try std.testing.expectEqual(@as(?u8, 1), memoryPortWidth(ram, "clk", .to));
    try std.testing.expectEqual(@as(?u8, 12), memoryPortWidth(ram, "out", .from));
    try std.testing.expectEqual(@as(?u8, null), memoryPortWidth(ram, "in", .to));
}

test "memory_validation: rejects wrong arity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    for ([_]u8{ 0, 1, 3 }) |count| {
        const list = try runOn(allocator, &.{memoryComponent(.{
            .mode = .rom,
            .data_width = 8,
            .addr_width = 4,
            .arg_count = count,
            .type_width_given = false,
        })});
        try std.testing.expectEqual(@as(usize, 1), list.items.len);
        try std.testing.expectEqual(diagnostics.DiagnosticCode.E017, list.items[0].code);
        const expected_tail = try std.fmt.allocPrint(allocator, "got {d}", .{count});
        try std.testing.expect(std.mem.indexOf(u8, list.items[0].message, expected_tail) != null);
        if (count == 0) try std.testing.expect(std.mem.indexOf(u8, list.items[0].message, "rom m[W, A](...)") != null);
    }

    const ok = try runOn(allocator, &.{memoryComponent(.{
        .mode = .ram,
        .data_width = 8,
        .addr_width = 4,
        .arg_count = 2,
        .type_width_given = false,
    })});
    try std.testing.expectEqual(@as(usize, 0), ok.items.len);
}

test "memory_validation: rejects type-position width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const list = try runOn(allocator, &.{memoryComponent(.{
        .mode = .rom,
        .data_width = 8,
        .addr_width = 4,
        .arg_count = 2,
        .type_width_given = true,
    })});
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqual(diagnostics.DiagnosticCode.E017, list.items[0].code);
    try std.testing.expect(std.mem.indexOf(u8, list.items[0].message, "instance position") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items[0].message, "rom m[8, 4](...)") != null);
}

test "memory_validation: width bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const bad = [_][2]u8{ .{ 65, 4 }, .{ 0, 4 }, .{ 8, 17 }, .{ 8, 0 } };
    for (bad) |widths| {
        const list = try runOn(allocator, &.{memoryComponent(.{
            .mode = .rom,
            .data_width = widths[0],
            .addr_width = widths[1],
            .arg_count = 2,
            .type_width_given = false,
        })});
        try std.testing.expectEqual(@as(usize, 1), list.items.len);
        try std.testing.expectEqual(diagnostics.DiagnosticCode.E018, list.items[0].code);
    }

    const both_bad = try runOn(allocator, &.{memoryComponent(.{
        .mode = .rom,
        .data_width = 0,
        .addr_width = 20,
        .arg_count = 2,
        .type_width_given = false,
    })});
    try std.testing.expectEqual(@as(usize, 2), both_bad.items.len);
    try std.testing.expect(std.mem.indexOf(u8, both_bad.items[1].message, "65536 words") != null);

    const good = [_][2]u8{ .{ 1, 1 }, .{ 64, 16 } };
    for (good) |widths| {
        const list = try runOn(allocator, &.{memoryComponent(.{
            .mode = .ram,
            .data_width = widths[0],
            .addr_width = widths[1],
            .arg_count = 2,
            .type_width_given = false,
        })});
        try std.testing.expectEqual(@as(usize, 0), list.items.len);
    }

    // A malformed argument list suppresses the range check: the widths are
    // the resolver's placeholders, not the user's.
    const suppressed = try runOn(allocator, &.{memoryComponent(.{
        .mode = .rom,
        .data_width = 0,
        .addr_width = 1,
        .arg_count = 1,
        .type_width_given = false,
    })});
    try std.testing.expectEqual(@as(usize, 1), suppressed.items.len);
    try std.testing.expectEqual(diagnostics.DiagnosticCode.E017, suppressed.items[0].code);
}
