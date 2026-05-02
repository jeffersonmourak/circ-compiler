const std = @import("std");
const workspace_mod = @import("orchestrator_workspace");
const embed = @import("orchestrator_embed");

fn openDirAny(path: []const u8) !std.fs.Dir {
    if (std.fs.path.isAbsolute(path)) return std.fs.openDirAbsolute(path, .{});
    return std.fs.cwd().openDir(path, .{});
}

fn readFileAny(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        var file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, 1024 * 1024);
    }
    return std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
}

test "createWorkspace(null) creates temp path and src with cleanup flag" {
    var workspace = try workspace_mod.createWorkspace(std.testing.allocator, null);
    defer workspace.deinit();
    defer std.fs.deleteTreeAbsolute(workspace.path) catch {};

    try std.testing.expect(workspace.cleanup_on_success);
    try std.testing.expect(std.mem.startsWith(u8, workspace.path, "/tmp/circ-compile-"));

    var dir = try openDirAny(workspace.path);
    dir.close();

    const src_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/src", .{workspace.path});
    defer std.testing.allocator.free(src_path);
    var src_dir = try openDirAny(src_path);
    src_dir.close();
}

test "createWorkspace(override) uses provided path and disables cleanup" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const override = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/workspace_override", .{tmp.sub_path});
    defer std.testing.allocator.free(override);

    var workspace = try workspace_mod.createWorkspace(std.testing.allocator, override);
    defer workspace.deinit();

    try std.testing.expect(!workspace.cleanup_on_success);
    try std.testing.expectEqualStrings(override, workspace.path);

    var dir = try openDirAny(workspace.path);
    dir.close();
}

test "writeRuntime writes all embedded runtime files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const override = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/runtime_workspace", .{tmp.sub_path});
    defer std.testing.allocator.free(override);

    var workspace = try workspace_mod.createWorkspace(std.testing.allocator, override);
    defer workspace.deinit();

    try workspace_mod.writeRuntime(&workspace);

    for (embed.runtime_files) |embedded_file| {
        const path = try std.fmt.allocPrint(std.testing.allocator, "{s}/{s}", .{ workspace.path, embedded_file.name });
        defer std.testing.allocator.free(path);
        const contents = try readFileAny(std.testing.allocator, path);
        defer std.testing.allocator.free(contents);
        try std.testing.expectEqualStrings(embedded_file.content, contents);
    }
}

test "writeEmittedSource writes src/compiled.zig" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const override = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/emit_workspace", .{tmp.sub_path});
    defer std.testing.allocator.free(override);

    var workspace = try workspace_mod.createWorkspace(std.testing.allocator, override);
    defer workspace.deinit();

    const emitted = "const hello = 42;\n";
    try workspace_mod.writeEmittedSource(&workspace, emitted);

    const compiled_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/src/compiled.zig", .{workspace.path});
    defer std.testing.allocator.free(compiled_path);
    const contents = try readFileAny(std.testing.allocator, compiled_path);
    defer std.testing.allocator.free(contents);

    try std.testing.expectEqualStrings(emitted, contents);
}
