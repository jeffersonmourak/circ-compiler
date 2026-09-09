//! JSON codec for the library boundary: the request the C ABI accepts, and
//! the error / diagnostics bodies every non-zero status carries. Diagnostics
//! use the analyze-api shape so one client-side decoder serves both.
const std = @import("std");
const frontend = @import("frontend.zig");
const analyzer = @import("analyze");

/// `{"error":"<message>"}`
pub fn writeError(writer: anytype, message: []const u8) !void {
    try writer.writeAll("{\"error\":");
    try analyzer.writeJsonString(writer, message);
    try writer.writeAll("}");
}

/// The front end's diagnostics in the analyze-api shape:
/// `{"files":[…],"diagnostics":[…],"symbols":[],"references":[]}`.
pub fn writeDiagnostics(allocator: std.mem.Allocator, writer: anytype, front: *const frontend.Front) !void {
    const files = try allocator.alloc(analyzer.FileEntry, front.file_paths.len);
    for (front.file_paths, 0..) |p, i| files[i] = .{ .file_id = @intCast(i), .path = p };
    const diags = try analyzer.convertDiagnostics(allocator, front.diagnostics.items);
    try analyzer.renderJson(writer, .{
        .files = files,
        .diagnostics = diags,
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
