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
    for (module.connections, 0..) |base_connection, idx| {
        var matches: std.ArrayList(usize) = .{};
        try matches.append(allocator, idx);

        var j = idx + 1;
        while (j < module.connections.len) : (j += 1) {
            const other = module.connections[j];
            if (other.to.component.value == base_connection.to.component.value and
                std.mem.eql(u8, other.to.port, base_connection.to.port))
            {
                try matches.append(allocator, j);
            }
        }

        if (matches.items.len <= 1) continue;

        var is_first = true;
        for (matches.items) |match_idx| {
            if (match_idx < idx) {
                is_first = false;
                break;
            }
        }
        if (!is_first) continue;

        const message = try std.fmt.allocPrint(
            allocator,
            "multiple drivers for input port '{s}'",
            .{base_connection.to.port},
        );
        var diagnostic = diagnostics.makeDiagnostic(.E003, toDiagnosticSpan(base_connection.span));
        diagnostic.message = message;

        var notes: std.ArrayList(diagnostics.DiagnosticNote) = .{};
        for (matches.items) |match_idx| {
            const driver = module.connections[match_idx];
            const note_message = try std.fmt.allocPrint(
                allocator,
                "driver from component {d}.{s}",
                .{ driver.from.component.value, driver.from.port },
            );
            try notes.append(allocator, .{
                .span = toDiagnosticSpan(driver.span),
                .message = note_message,
            });
        }

        diagnostic.notes = try notes.toOwnedSlice(allocator);
        try diagnostic_list.append(allocator, diagnostic);
    }
}
