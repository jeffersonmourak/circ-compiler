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

fn aliasIsUsed(module: *const ir.Module, alias: []const u8) bool {
    for (module.components) |component| {
        switch (component.kind) {
            .sub_circuit_ref => |ref| {
                if (std.mem.eql(u8, ref.name, alias)) return true;
            },
            else => {},
        }
    }
    return false;
}

pub fn run(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    for (module.imports) |import_decl| {
        if (import_decl.implicit_builtin) continue;
        if (aliasIsUsed(module, import_decl.alias)) continue;
        const message = try std.fmt.allocPrint(
            allocator,
            "import '{s}' is declared but never instantiated",
            .{import_decl.alias},
        );
        var diagnostic = diagnostics.makeDiagnostic(.W003, toDiagnosticSpan(import_decl.span));
        diagnostic.message = message;
        try diagnostic_list.append(allocator, diagnostic);
    }
}
