const std = @import("std");

pub const Writer = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    indent_level: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Writer {
        return .{
            .allocator = allocator,
            .buffer = .{},
            .indent_level = 0,
        };
    }

    pub fn deinit(self: *Writer) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn indent(self: *Writer) void {
        self.indent_level += 1;
    }

    pub fn dedent(self: *Writer) void {
        if (self.indent_level > 0) self.indent_level -= 1;
    }

    pub fn writeRaw(self: *Writer, text: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, text);
    }

    pub fn writeLine(self: *Writer, text: []const u8) !void {
        var i: usize = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.writeRaw("    ");
        }
        try self.writeRaw(text);
        try self.writeRaw("\n");
    }

    pub fn writeLineFmt(self: *Writer, comptime format: []const u8, args: anytype) !void {
        var line_buffer: std.ArrayList(u8) = .{};
        defer line_buffer.deinit(self.allocator);
        try line_buffer.writer(self.allocator).print(format, args);
        try self.writeLine(line_buffer.items);
    }

    pub fn escapeIdentifier(self: *Writer, raw: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .{};
        errdefer out.deinit(self.allocator);

        const starts_with_digit = raw.len > 0 and std.ascii.isDigit(raw[0]);
        if (starts_with_digit) {
            try out.append(self.allocator, '_');
        }

        for (raw) |ch| {
            const valid = std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch) or ch == '_';
            try out.append(self.allocator, if (valid) ch else '_');
        }

        const candidate = out.items;
        if (isZigKeyword(candidate)) {
            try out.append(self.allocator, '_');
        }
        return out.toOwnedSlice(self.allocator);
    }

    pub fn zigStringLiteral(self: *Writer, raw: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .{};
        errdefer out.deinit(self.allocator);
        try out.append(self.allocator, '"');
        for (raw) |ch| {
            switch (ch) {
                '\\' => try out.appendSlice(self.allocator, "\\\\"),
                '"' => try out.appendSlice(self.allocator, "\\\""),
                '\n' => try out.appendSlice(self.allocator, "\\n"),
                '\r' => try out.appendSlice(self.allocator, "\\r"),
                '\t' => try out.appendSlice(self.allocator, "\\t"),
                else => try out.append(self.allocator, ch),
            }
        }
        try out.append(self.allocator, '"');
        return out.toOwnedSlice(self.allocator);
    }

    pub fn toOwnedSlice(self: *Writer) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }
};

fn isZigKeyword(text: []const u8) bool {
    const keywords = [_][]const u8{
        "addrspace", "align", "allowzero", "and", "anyframe", "anytype", "asm", "async",
        "await", "break", "callconv", "catch", "comptime", "const", "continue", "defer",
        "else", "enum", "errdefer", "error", "export", "extern", "fn", "for", "if",
        "inline", "linksection", "noalias", "nosuspend", "opaque", "or", "orelse", "packed",
        "pub", "resume", "return", "struct", "suspend", "switch", "test", "threadlocal",
        "try", "union", "unreachable", "usingnamespace", "var", "volatile", "while",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, text, keyword)) return true;
    }
    return false;
}
