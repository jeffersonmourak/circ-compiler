const std = @import("std");
const builtins = @import("builtins");

fn readAbsoluteFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

pub const builtin_path_prefix = builtins.builtin_vpath_prefix;

pub const LoadedFile = struct {
    absolute_path: []u8,
    source: []u8,
};

/// In-memory source overlay for editor integration. Maps an absolute file
/// path to the unsaved buffer the editor currently holds. The analyzer
/// consults it before reading disk so it sees the document being edited,
/// not the last-saved bytes. Keyed by absolute path because that is the
/// stable identity the resolver threads through `file_paths`.
pub const Overlay = std.StringHashMapUnmanaged([]const u8);

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !LoadedFile {
    return loadFileWithOverlay(allocator, path, null);
}

pub fn loadFileWithOverlay(allocator: std.mem.Allocator, path: []const u8, overlay: ?Overlay) !LoadedFile {
    if (std.mem.startsWith(u8, path, builtin_path_prefix)) {
        const suffix = path[builtin_path_prefix.len..];
        const embedded = builtins.sourceForPathSuffix(suffix) orelse return error.BuiltinNotFound;
        const absolute_path = try allocator.dupe(u8, path);
        errdefer allocator.free(absolute_path);
        const source = try allocator.dupe(u8, embedded);
        return .{
            .absolute_path = absolute_path,
            .source = source,
        };
    }

    // Resolve to an absolute path so the overlay (keyed by absolute path)
    // matches. A never-saved buffer fails realpath; fall back to the given
    // path so an absolute overlay key still resolves for new documents.
    const absolute_path = std.fs.realpathAlloc(allocator, path) catch |err| blk: {
        if (err == error.FileNotFound) break :blk try allocator.dupe(u8, path);
        return err;
    };
    errdefer allocator.free(absolute_path);

    if (overlay) |ov| {
        if (ov.get(absolute_path)) |buffer| {
            const source = try allocator.dupe(u8, buffer);
            return .{ .absolute_path = absolute_path, .source = source };
        }
    }

    const source = try readAbsoluteFileAlloc(allocator, absolute_path);
    errdefer allocator.free(source);
    return .{
        .absolute_path = absolute_path,
        .source = source,
    };
}

pub fn resolveImportPath(allocator: std.mem.Allocator, importing_file_path: []const u8, import_path: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, import_path, builtin_path_prefix)) {
        return allocator.dupe(u8, import_path);
    }
    const base_dir = std.fs.path.dirname(importing_file_path) orelse ".";
    const joined = try std.fs.path.resolve(allocator, &.{ base_dir, import_path });
    defer allocator.free(joined);
    return std.fs.realpathAlloc(allocator, joined);
}
