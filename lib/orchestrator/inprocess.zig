const std = @import("std");
const zc = @import("zig_compiler");

pub fn compile(
    allocator: std.mem.Allocator,
    workspace_path: []const u8,
    stderr_writer: anytype,
) !void {
    _ = allocator;
    _ = workspace_path;
    _ = stderr_writer;
    _ = zc.Compilation;
    return error.NotImplemented;
}
