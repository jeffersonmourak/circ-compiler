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

fn hasOutgoingConnection(module: *const ir.Module, component_id: ir.ComponentId) bool {
    for (module.connections) |connection| {
        if (connection.from.component.value == component_id.value) return true;
    }
    return false;
}

pub fn run(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    for (module.inputs) |input_pin| {
        if (hasOutgoingConnection(module, input_pin.component)) continue;
        const message = try std.fmt.allocPrint(
            allocator,
            "input '{s}' is declared but never used",
            .{input_pin.name},
        );
        var diagnostic = diagnostics.makeDiagnostic(.W001, toDiagnosticSpan(input_pin.span));
        diagnostic.message = message;
        try diagnostic_list.append(allocator, diagnostic);
    }

    // W002 is reserved in single-file mode. In top-level single-file compilation,
    // output reads are a runtime host concern, so this pass intentionally does not
    // emit W002 until multi-file context (Phase 7) is available.
}
