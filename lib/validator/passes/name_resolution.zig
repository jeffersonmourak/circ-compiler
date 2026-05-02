const std = @import("std");
const diagnostics = @import("diagnostics");
const ir = @import("ir_types");

fn toDiagnosticSpan(span: ir.Span) diagnostics.Span {
    return .{
        .file_id = span.file_id,
        .start_line = span.start_line,
        .start_col = span.start_col,
        .end_line = span.end_line,
        .end_col = span.end_col,
    };
}

pub fn run(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    for (module.components) |component| {
        switch (component.kind) {
            .unresolved_name => |name| {
                const message = try std.fmt.allocPrint(allocator, "undeclared name '{s}'", .{name});
                var diagnostic = diagnostics.makeDiagnostic(.E001, toDiagnosticSpan(component.span));
                diagnostic.message = message;
                try diagnostic_list.append(allocator, diagnostic);
            },
            else => {},
        }
    }
}
