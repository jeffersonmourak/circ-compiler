const std = @import("std");
const workspace_mod = @import("orchestrator_workspace");

fn joinPath(allocator: std.mem.Allocator, base: []const u8, rel: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, rel });
}

fn makePathAny(path: []const u8) !void {
    if (!std.fs.path.isAbsolute(path)) {
        try std.fs.cwd().makePath(path);
        return;
    }

    var root_dir = try std.fs.openDirAbsolute("/", .{});
    defer root_dir.close();
    try root_dir.makePath(path[1..]);
}

pub fn copyOutput(workspace: *const workspace_mod.Workspace, target_path: []const u8) !void {
    const source_path = try joinPath(workspace.allocator, workspace.path, "zig-out/bin/compiled.wasm");
    defer workspace.allocator.free(source_path);

    var source_file = if (std.fs.path.isAbsolute(source_path))
        std.fs.openFileAbsolute(source_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.MissingCompiledWasm,
            else => return err,
        }
    else
        std.fs.cwd().openFile(source_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.MissingCompiledWasm,
            else => return err,
        };
    defer source_file.close();

    if (std.fs.path.dirname(target_path)) |target_parent| {
        try makePathAny(target_parent);
    }

    var target_file = if (std.fs.path.isAbsolute(target_path))
        try std.fs.createFileAbsolute(target_path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(target_path, .{ .truncate = true });
    defer target_file.close();

    var copy_buffer: [4096]u8 = undefined;
    while (true) {
        const len = try source_file.read(&copy_buffer);
        if (len == 0) break;
        try target_file.writeAll(copy_buffer[0..len]);
    }
}

pub fn cleanup(workspace: *const workspace_mod.Workspace) !void {
    if (!workspace.cleanup_on_success) return;

    if (std.fs.path.isAbsolute(workspace.path)) {
        try std.fs.deleteTreeAbsolute(workspace.path);
        return;
    }
    try std.fs.cwd().deleteTree(workspace.path);
}
