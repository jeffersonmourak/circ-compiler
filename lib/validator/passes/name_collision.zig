const std = @import("std");
const diagnostics = @import("diagnostics");
const ir = @import("ir_types");

const first_seen_span = struct {
    span: ir.Span,
};

fn toDiagnosticSpan(span: ir.Span) diagnostics.Span {
    return .{
        .file_id = span.file_id,
        .start_line = span.start_line,
        .start_col = span.start_col,
        .end_line = span.end_line,
        .end_col = span.end_col,
    };
}

fn isBuiltinName(name: []const u8) bool {
    return std.mem.eql(u8, name, "and") or
        std.mem.eql(u8, name, "not") or
        std.mem.eql(u8, name, "wire") or
        std.mem.eql(u8, name, "led") or
        std.mem.eql(u8, name, "input_pin") or
        std.mem.eql(u8, name, "output_pin");
}

pub fn run(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    var seen = std.StringHashMap(first_seen_span).init(allocator);
    defer seen.deinit();

    for (module.components) |component| {
        const name = component.instance_name orelse continue;

        if (isBuiltinName(name)) {
            const message = try std.fmt.allocPrint(allocator, "instance name '{s}' shadows built-in", .{name});
            var diagnostic = diagnostics.makeDiagnostic(.E006, toDiagnosticSpan(component.span));
            diagnostic.message = message;
            try diagnostic_list.append(allocator, diagnostic);
        }

        const result = try seen.getOrPut(name);
        if (!result.found_existing) {
            result.value_ptr.* = .{ .span = component.span };
            continue;
        }

        const message = try std.fmt.allocPrint(allocator, "duplicate instance name '{s}'", .{name});
        const note_message = try std.fmt.allocPrint(allocator, "first declared as '{s}' here", .{name});
        const note = try allocator.create(diagnostics.DiagnosticNote);
        note.* = .{
            .span = toDiagnosticSpan(result.value_ptr.span),
            .message = note_message,
        };
        var diagnostic = diagnostics.makeDiagnostic(.E005, toDiagnosticSpan(component.span));
        diagnostic.message = message;
        diagnostic.notes = note[0..1];
        try diagnostic_list.append(allocator, diagnostic);
    }
}
