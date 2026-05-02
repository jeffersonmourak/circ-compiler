const std = @import("std");
const workspace_mod = @import("orchestrator_workspace");
const finalize = @import("orchestrator_finalize");

fn readFileAny(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        var file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, 1024 * 1024);
    }
    return std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
}

test "copyOutput copies compiled wasm bytes to target path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_override = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/finalize_workspace", .{tmp.sub_path});
    defer std.testing.allocator.free(workspace_override);
    var workspace = try workspace_mod.createWorkspace(std.testing.allocator, workspace_override);
    defer workspace.deinit();

    const wasm_source_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/zig-out/bin", .{workspace.path});
    defer std.testing.allocator.free(wasm_source_path);
    try std.fs.cwd().makePath(wasm_source_path);
    const wasm_file_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/compiled.wasm", .{wasm_source_path});
    defer std.testing.allocator.free(wasm_file_path);
    try std.fs.cwd().writeFile(.{
        .sub_path = wasm_file_path,
        .data = "\x00asm",
    });

    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/out/result.wasm", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);
    try finalize.copyOutput(&workspace, output_path);

    const output_bytes = try readFileAny(std.testing.allocator, output_path);
    defer std.testing.allocator.free(output_bytes);
    try std.testing.expectEqualStrings("\x00asm", output_bytes);
}

test "copyOutput errors when compiled wasm is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_override = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/missing_workspace", .{tmp.sub_path});
    defer std.testing.allocator.free(workspace_override);
    var workspace = try workspace_mod.createWorkspace(std.testing.allocator, workspace_override);
    defer workspace.deinit();

    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/out/missing.wasm", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);

    try std.testing.expectError(error.MissingCompiledWasm, finalize.copyOutput(&workspace, output_path));
}

test "cleanup deletes workspace when cleanup_on_success is true" {
    var workspace = try workspace_mod.createWorkspace(std.testing.allocator, null);
    defer workspace.deinit();

    const workspace_path = try std.testing.allocator.dupe(u8, workspace.path);
    defer std.testing.allocator.free(workspace_path);

    try finalize.cleanup(&workspace);
    try std.testing.expectError(error.FileNotFound, std.fs.openDirAbsolute(workspace_path, .{}));
}

test "cleanup is no-op when cleanup_on_success is false" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workspace_override = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/no_cleanup_workspace", .{tmp.sub_path});
    defer std.testing.allocator.free(workspace_override);
    var workspace = try workspace_mod.createWorkspace(std.testing.allocator, workspace_override);
    defer workspace.deinit();

    try finalize.cleanup(&workspace);
    var dir = try std.fs.cwd().openDir(workspace.path, .{});
    dir.close();
}
