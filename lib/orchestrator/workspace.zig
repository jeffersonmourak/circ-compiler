const std = @import("std");
const embed = @import("orchestrator_embed");

pub const Workspace = struct {
    allocator: std.mem.Allocator,
    path: []u8,
    cleanup_on_success: bool,

    pub fn deinit(self: *Workspace) void {
        self.allocator.free(self.path);
    }
};

fn makePathAny(path: []const u8) !void {
    if (!std.fs.path.isAbsolute(path)) {
        try std.fs.cwd().makePath(path);
        return;
    }

    var root_dir = try std.fs.openDirAbsolute("/", .{});
    defer root_dir.close();
    try root_dir.makePath(path[1..]);
}

fn joinPath(allocator: std.mem.Allocator, base: []const u8, rel: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, rel });
}

fn writeFileAny(path: []const u8, data: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        var file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(data);
        return;
    }

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

pub fn createWorkspace(allocator: std.mem.Allocator, build_dir_override: ?[]const u8) !Workspace {
    if (build_dir_override) |path_override| {
        const path = try allocator.dupe(u8, path_override);
        errdefer allocator.free(path);
        try makePathAny(path);
        const src_path = try joinPath(allocator, path, "src");
        defer allocator.free(src_path);
        try makePathAny(src_path);
        return .{
            .allocator = allocator,
            .path = path,
            .cleanup_on_success = false,
        };
    }

    const rand = std.crypto.random.int(u64);
    const path = try std.fmt.allocPrint(allocator, "/tmp/circ-compile-{x}", .{rand});
    errdefer allocator.free(path);

    try makePathAny(path);
    const src_path = try joinPath(allocator, path, "src");
    defer allocator.free(src_path);
    try makePathAny(src_path);

    return .{
        .allocator = allocator,
        .path = path,
        .cleanup_on_success = true,
    };
}

pub fn writeRuntime(workspace: *const Workspace) !void {
    for (embed.runtime_files) |file| {
        const target_path = try joinPath(workspace.allocator, workspace.path, file.name);
        defer workspace.allocator.free(target_path);

        if (std.fs.path.dirname(file.name)) |parent_rel| {
            const parent_path = try joinPath(workspace.allocator, workspace.path, parent_rel);
            defer workspace.allocator.free(parent_path);
            try makePathAny(parent_path);
        }

        try writeFileAny(target_path, file.content);
    }
}

pub fn writeEmittedSource(workspace: *const Workspace, source: []const u8) !void {
    const target_path = try joinPath(workspace.allocator, workspace.path, "src/compiled.zig");
    defer workspace.allocator.free(target_path);
    try writeFileAny(target_path, source);
}
