const std = @import("std");
const SyntaxSpan = @import("span").Span;
const codes = @import("codes");

pub const DiagnosticCode = codes.DiagnosticCode;
pub const Span = SyntaxSpan;

pub const DiagnosticLevel = enum {
    err,
    warning,
};

pub const DiagnosticNote = struct {
    span: Span,
    message: []const u8,
};

pub const Diagnostic = struct {
    level: DiagnosticLevel,
    code: DiagnosticCode,
    span: Span,
    message: []const u8,
    notes: []const DiagnosticNote = &.{},
};

pub const DiagnosticList = std.ArrayList(Diagnostic);

pub fn initDiagnosticList() DiagnosticList {
    return .{};
}

pub fn levelForCode(code: DiagnosticCode) DiagnosticLevel {
    return switch (code) {
        .W001, .W002 => .warning,
        else => .err,
    };
}

pub fn makeDiagnostic(code: DiagnosticCode, span: Span) Diagnostic {
    return .{
        .level = levelForCode(code),
        .code = code,
        .span = span,
        .message = codes.defaultMessage(code),
        .notes = &.{},
    };
}

pub fn formatDiagnosticLine(allocator: std.mem.Allocator, file_path: []const u8, diagnostic: Diagnostic) ![]u8 {
    const level_text = switch (diagnostic.level) {
        .err => "error",
        .warning => "warning",
    };
    return std.fmt.allocPrint(
        allocator,
        "{s}:{d}:{d}: {s}: {s}: {s}",
        .{
            file_path,
            diagnostic.span.start_line,
            diagnostic.span.start_col,
            level_text,
            @tagName(diagnostic.code),
            diagnostic.message,
        },
    );
}
