pub const DiagnosticCode = enum {
    E001,
    E002,
    E003,
    E004,
    E005,
    E006,
    E007,
    E008,
    W001,
    W002,
};

pub const CodeTemplate = struct {
    code: DiagnosticCode,
    default_message: []const u8,
};

pub const templates = [_]CodeTemplate{
    .{ .code = .E001, .default_message = "undeclared name" },
    .{ .code = .E002, .default_message = "unknown port" },
    .{ .code = .E003, .default_message = "multiple drivers for input port" },
    .{ .code = .E004, .default_message = "required input is unconnected" },
    .{ .code = .E005, .default_message = "duplicate instance name" },
    .{ .code = .E006, .default_message = "name shadows built-in" },
    .{ .code = .E007, .default_message = "output has no assigned driver" },
    .{ .code = .E008, .default_message = "combinational loop detected" },
    .{ .code = .W001, .default_message = "unused input declaration" },
    .{ .code = .W002, .default_message = "dangling output declaration" },
};

pub fn defaultMessage(code: DiagnosticCode) []const u8 {
    inline for (templates) |entry| {
        if (entry.code == code) return entry.default_message;
    }
    unreachable;
}
