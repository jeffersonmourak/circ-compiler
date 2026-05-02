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

fn hasDriverComponent(module: *const ir.Module, component_id: ir.ComponentId) bool {
    for (module.components) |component| {
        if (component.id.value == component_id.value) return true;
    }
    return false;
}

pub fn run(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    for (module.outputs) |output_pin| {
        if (hasDriverComponent(module, output_pin.driver.component)) continue;
        const message = try std.fmt.allocPrint(allocator, "output '{s}' has no assigned driver", .{output_pin.name});
        var diagnostic = diagnostics.makeDiagnostic(.E007, toDiagnosticSpan(output_pin.span));
        diagnostic.message = message;
        try diagnostic_list.append(allocator, diagnostic);
    }
}
