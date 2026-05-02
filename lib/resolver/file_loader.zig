const std = @import("std");

fn readAbsoluteFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

pub const LoadedFile = struct {
    absolute_path: []u8,
    source: []u8,
};

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !LoadedFile {
    const absolute_path = try std.fs.realpathAlloc(allocator, path);
    errdefer allocator.free(absolute_path);
    const source = try readAbsoluteFileAlloc(allocator, absolute_path);
    errdefer allocator.free(source);
    return .{
        .absolute_path = absolute_path,
        .source = source,
    };
}

pub fn resolveImportPath(allocator: std.mem.Allocator, importing_file_path: []const u8, import_path: []const u8) ![]u8 {
    const base_dir = std.fs.path.dirname(importing_file_path) orelse ".";
    const joined = try std.fs.path.resolve(allocator, &.{ base_dir, import_path });
    defer allocator.free(joined);
    return std.fs.realpathAlloc(allocator, joined);
}
