//! JSON codec for the library boundary: the request the C ABI accepts, and
//! the error / diagnostics bodies every non-zero status carries. Diagnostics
//! use the analyze-api shape so one client-side decoder serves both.
const std = @import("std");
const frontend = @import("frontend.zig");
const analyzer = @import("analyze");

const Request = @import("../libcirc.zig").Request;
const Options = @import("../libcirc.zig").Options;
const File = frontend.File;

pub const ParseError = error{
    InvalidJson,
    NotAnObject,
    MissingRoot,
    RootNotString,
    FilesNotObject,
    FileTextNotString,
    FileKeyNotAbsolute,
    OptionsNotObject,
    BadOption,
    CapOutOfRange,
    OutOfMemory,
};

pub fn describe(err: ParseError) []const u8 {
    return switch (err) {
        error.InvalidJson => "invalid request JSON",
        error.NotAnObject => "request must be a JSON object",
        error.MissingRoot => "request missing 'root'",
        error.RootNotString => "'root' must be a string",
        error.FilesNotObject => "'files' must be an object of path -> text",
        error.FileTextNotString => "every 'files' value must be a string",
        error.FileKeyNotAbsolute => "files keys must be absolute paths",
        error.OptionsNotObject => "'options' must be an object",
        error.BadOption => "unknown or mistyped option",
        error.CapOutOfRange => "options.truth_table_cap must be 1..24",
        error.OutOfMemory => "out of memory",
    };
}

fn enumOption(comptime E: type, value: std.json.Value) ParseError!E {
    return switch (value) {
        .string => |s| std.meta.stringToEnum(E, s) orelse error.BadOption,
        else => error.BadOption,
    };
}

fn boolOption(value: std.json.Value) ParseError!bool {
    return switch (value) {
        .bool => |b| b,
        else => error.BadOption,
    };
}

/// Parse `{"root": "...", "files": {path: text}, "options": {...}}`.
/// Everything but `root` is optional; an unknown option key is an error so
/// a misspelt flag never silently means "default".
pub fn parseRequest(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Request {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidJson,
    };
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.NotAnObject,
    };

    const root_val = obj.get("root") orelse return error.MissingRoot;
    const root = switch (root_val) {
        .string => |s| s,
        else => return error.RootNotString,
    };

    var files: std.ArrayList(File) = .{};
    if (obj.get("files")) |files_val| {
        const files_obj = switch (files_val) {
            .object => |o| o,
            else => return error.FilesNotObject,
        };
        var it = files_obj.iterator();
        while (it.next()) |entry| {
            if (!std.fs.path.isAbsolutePosix(entry.key_ptr.*)) return error.FileKeyNotAbsolute;
            const text = switch (entry.value_ptr.*) {
                .string => |s| s,
                else => return error.FileTextNotString,
            };
            try files.append(allocator, .{ .path = entry.key_ptr.*, .text = text });
        }
    }

    var options: Options = .{};
    if (obj.get("options")) |opts_val| {
        const opts_obj = switch (opts_val) {
            .object => |o| o,
            else => return error.OptionsNotObject,
        };
        var it = opts_obj.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            if (std.mem.eql(u8, key, "expand_macros")) {
                options.expand_macros = try boolOption(value);
            } else if (std.mem.eql(u8, key, "expand_display")) {
                options.expand_display = try boolOption(value);
            } else if (std.mem.eql(u8, key, "warnings_as_errors")) {
                options.warnings_as_errors = try boolOption(value);
            } else if (std.mem.eql(u8, key, "color")) {
                options.color = try enumOption(@TypeOf(options.color), value);
            } else if (std.mem.eql(u8, key, "format")) {
                options.format = try enumOption(@TypeOf(options.format), value);
            } else if (std.mem.eql(u8, key, "value_format")) {
                options.value_format = try enumOption(@TypeOf(options.value_format), value);
            } else if (std.mem.eql(u8, key, "truth_table_cap")) {
                const cap = switch (value) {
                    .integer => |i| i,
                    else => return error.BadOption,
                };
                if (cap < 1 or cap > 24) return error.CapOutOfRange;
                options.truth_table_cap = @intCast(cap);
            } else {
                return error.BadOption;
            }
        }
    }

    return .{ .root = root, .files = try files.toOwnedSlice(allocator), .options = options };
}

/// `{"error":"<message>"}`
pub fn writeError(writer: anytype, message: []const u8) !void {
    try writer.writeAll("{\"error\":");
    try analyzer.writeJsonString(writer, message);
    try writer.writeAll("}");
}

/// The front end's diagnostics in the analyze-api shape:
/// `{"files":[…],"diagnostics":[…],"symbols":[],"references":[]}`.
/// Validator diagnostics first, then one `syntax` entry per recovered
/// error mark on the root — the same order and widening `--analyze` uses.
pub fn writeDiagnostics(allocator: std.mem.Allocator, writer: anytype, front: *const frontend.Front) !void {
    const files = try allocator.alloc(analyzer.FileEntry, front.file_paths.len);
    for (front.file_paths, 0..) |p, i| files[i] = .{ .file_id = @intCast(i), .path = p };
    const converted = try analyzer.convertDiagnostics(allocator, front.diagnostics.items);
    var diags: std.ArrayList(analyzer.Diagnostic) = .{};
    try diags.appendSlice(allocator, converted);
    for (front.ast_file.errors) |mark| {
        // Guarantee a non-empty range so an editor highlights a span.
        var end_col = mark.span.end_col;
        if (mark.span.end_line == mark.span.start_line and end_col <= mark.span.start_col) end_col = mark.span.start_col + 1;
        try diags.append(allocator, .{
            .file_id = 0,
            .severity = "error",
            .code = "syntax",
            .range = .{ .start_line = mark.span.start_line, .start_col = mark.span.start_col, .end_line = mark.span.end_line, .end_col = end_col },
            .message = mark.message,
            .related = &.{},
        });
    }
    try analyzer.renderJson(writer, .{
        .files = files,
        .diagnostics = diags.items,
        .symbols = &.{},
        .references = &.{},
    });
}

/// A hard parse failure of the root, as one located `syntax` diagnostic.
pub fn writeSyntaxFailure(allocator: std.mem.Allocator, writer: anytype, root: []const u8, cause: anyerror) !void {
    const message = try std.fmt.allocPrint(allocator, "parse failed: {s}", .{@errorName(cause)});
    const files = [_]analyzer.FileEntry{.{ .file_id = 0, .path = root }};
    const diags = [_]analyzer.Diagnostic{.{
        .file_id = 0,
        .severity = "error",
        .code = "syntax",
        .range = .{ .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 2 },
        .message = message,
        .related = &.{},
    }};
    try analyzer.renderJson(writer, .{
        .files = &files,
        .diagnostics = &diags,
        .symbols = &.{},
        .references = &.{},
    });
}

test "json: writeError escapes" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    try writeError(buf.writer(std.testing.allocator), "a\"b\n");
    try std.testing.expectEqualStrings("{\"error\":\"a\\\"b\\n\"}", buf.items);
}

test "json: parses the full request" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const req = try parseRequest(a,
        \\{"root": "/playground/main.circ",
        \\ "files": {"/playground/main.circ": "import ha \"half_adder.circ\"\n", "/playground/./half_adder.circ": "input a\n"},
        \\ "options": {"expand_macros": true, "expand_display": true, "color": "always",
        \\             "format": "csv", "value_format": "hex", "truth_table_cap": 20, "warnings_as_errors": true}}
    );
    try std.testing.expectEqualStrings("/playground/main.circ", req.root);
    try std.testing.expectEqual(@as(usize, 2), req.files.len);
    try std.testing.expect(req.options.expand_macros);
    try std.testing.expect(req.options.expand_display);
    try std.testing.expect(req.options.warnings_as_errors);
    try std.testing.expectEqual(@TypeOf(req.options.color).always, req.options.color);
    try std.testing.expectEqual(@TypeOf(req.options.format).csv, req.options.format);
    try std.testing.expectEqual(@TypeOf(req.options.value_format).hex, req.options.value_format);
    try std.testing.expectEqual(@as(u8, 20), req.options.truth_table_cap);

    const bare = try parseRequest(a, "{\"root\": \"/x.circ\"}");
    try std.testing.expectEqual(@as(usize, 0), bare.files.len);
    try std.testing.expectEqual(@as(u8, 16), bare.options.truth_table_cap);
}

test "json: each error has a message" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_]struct { bytes: []const u8, err: ParseError }{
        .{ .bytes = "[", .err = error.InvalidJson },
        .{ .bytes = "[]", .err = error.NotAnObject },
        .{ .bytes = "{}", .err = error.MissingRoot },
        .{ .bytes = "{\"root\":1}", .err = error.RootNotString },
        .{ .bytes = "{\"root\":\"/r\",\"files\":[]}", .err = error.FilesNotObject },
        .{ .bytes = "{\"root\":\"/r\",\"files\":{\"/r\":1}}", .err = error.FileTextNotString },
        .{ .bytes = "{\"root\":\"/r\",\"files\":{\"r.circ\":\"\"}}", .err = error.FileKeyNotAbsolute },
        .{ .bytes = "{\"root\":\"/r\",\"options\":1}", .err = error.OptionsNotObject },
        .{ .bytes = "{\"root\":\"/r\",\"options\":{\"color\":\"auto\"}}", .err = error.BadOption },
        .{ .bytes = "{\"root\":\"/r\",\"options\":{\"colour\":\"never\"}}", .err = error.BadOption },
        .{ .bytes = "{\"root\":\"/r\",\"options\":{\"expand_macros\":\"yes\"}}", .err = error.BadOption },
        .{ .bytes = "{\"root\":\"/r\",\"options\":{\"truth_table_cap\":25}}", .err = error.CapOutOfRange },
        .{ .bytes = "{\"root\":\"/r\",\"options\":{\"truth_table_cap\":0}}", .err = error.CapOutOfRange },
    };
    for (cases) |c| {
        try std.testing.expectError(c.err, parseRequest(a, c.bytes));
        try std.testing.expect(describe(c.err).len > 0);
    }
}
