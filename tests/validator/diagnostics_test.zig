const std = @import("std");
const diagnostics = @import("diagnostics");
const codes = @import("codes");
const Span = diagnostics.Span;

test "formats one diagnostic line" {
    const span = Span{
        .file_id = 0,
        .start_line = 4,
        .start_col = 7,
        .end_line = 4,
        .end_col = 12,
    };
    const diagnostic = diagnostics.Diagnostic{
        .level = diagnostics.DiagnosticLevel.err,
        .code = diagnostics.DiagnosticCode.E001,
        .span = span,
        .message = "undeclared name 'mystery'",
        .notes = &.{},
    };

    const line = try diagnostics.formatDiagnosticLine(std.testing.allocator, "tests/fixtures/circuits/unknown_component.circ", diagnostic);
    defer std.testing.allocator.free(line);

    try std.testing.expectEqualStrings(
        "tests/fixtures/circuits/unknown_component.circ:4:7: error: E001: undeclared name 'mystery'",
        line,
    );
}

test "every diagnostic code has default message and formatting" {
    const span = Span{
        .file_id = 0,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 1,
    };

    for (codes.templates) |entry| {
        try std.testing.expect(entry.default_message.len > 0);

        const diagnostic = diagnostics.makeDiagnostic(entry.code, span);
        try std.testing.expectEqualStrings(entry.default_message, diagnostic.message);

        const line = try diagnostics.formatDiagnosticLine(std.testing.allocator, "file.circ", diagnostic);
        defer std.testing.allocator.free(line);

        try std.testing.expect(std.mem.indexOf(u8, line, @tagName(entry.code)) != null);
    }
}
