const std = @import("std");
const builtin = @import("builtin");
const builtins = @import("builtins");

/// Disk access exists only on hosted targets. A freestanding build (the
/// wasm library) sees the overlay and the embedded builtins, nothing else.
const has_disk = builtin.os.tag != .freestanding;

fn readAbsoluteFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (comptime !has_disk) return error.FileNotFound;
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

pub const builtin_path_prefix = builtins.builtin_vpath_prefix;

pub const LoadedFile = struct {
    absolute_path: []u8,
    source: []u8,
};

/// In-memory source overlay: maps a file path to the buffer a host holds
/// for it (an editor's unsaved document, or a playground file that never
/// touches disk). Keys are normalised with `normalizeKey` — absolute,
/// POSIX-style, `.`/`..` segments folded — because that is the identity the
/// resolver threads through `file_paths`. The overlay is consulted before
/// disk, so an overlay-only sibling import resolves without ever stat-ing.
pub const Overlay = std.StringHashMapUnmanaged([]const u8);

/// Canonical overlay key for `path`: `std.fs.path.resolvePosix` over the
/// single component, which is pure (no syscalls) and folds dot segments.
pub fn normalizeKey(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.path.resolvePosix(allocator, &.{path});
}

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

    // Overlay first, by the normalised key: a never-saved buffer has no
    // realpath, and an edited file under a symlinked directory must not be
    // realpathed away from the key the host registered it under.
    const key = try normalizeKey(allocator, path);
    if (overlay) |ov| {
        if (ov.get(key)) |buffer| {
            const source = try allocator.dupe(u8, buffer);
            return .{ .absolute_path = key, .source = source };
        }
    }
    if (comptime !has_disk) {
        allocator.free(key);
        return error.FileNotFound;
    }
    allocator.free(key);

    // Resolve to an absolute path so an overlay keyed by the realpath still
    // matches; a never-saved buffer fails realpath, so fall back to the
    // given path.
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

/// Resolve `import_path` relative to the importing file. The joined path is
/// POSIX-normalised; when the overlay holds it, that key is the answer and
/// nothing on disk is consulted. Otherwise (hosted targets only) the path
/// is realpathed, and a missing file is `error.FileNotFound`, which the
/// import scan reports as E009.
pub fn resolveImportPath(allocator: std.mem.Allocator, importing_file_path: []const u8, import_path: []const u8, overlay: ?Overlay) ![]u8 {
    if (std.mem.startsWith(u8, import_path, builtin_path_prefix)) {
        return allocator.dupe(u8, import_path);
    }
    const base_dir = std.fs.path.dirname(importing_file_path) orelse ".";
    const joined = try std.fs.path.resolvePosix(allocator, &.{ base_dir, import_path });
    if (overlay) |ov| {
        if (ov.contains(joined)) return joined;
    }
    defer allocator.free(joined);
    if (comptime !has_disk) return error.FileNotFound;
    return std.fs.realpathAlloc(allocator, joined);
}
