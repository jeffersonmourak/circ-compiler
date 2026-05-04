const std = @import("std");
const builtin = @import("builtin");

/// Base directory under `.zig-cache/`. Each OS process gets its own subdirectory
/// (`test-wasm-workspace-<pid>`) so parallel `zig build test` runners (e.g. behavior vs
/// project_behavior test binaries) never clobber the same `compiled.zig` / WASM output.
const workspace_dir_prefix = ".zig-cache/test-wasm-workspace";

fn processWorkspacePath(buffer: []u8) []const u8 {
    const pid: u32 = switch (builtin.os.tag) {
        .windows => @truncate(std.os.windows.kernel32.GetCurrentProcessId()),
        else => @bitCast(std.c.getpid()),
    };
    return std.fmt.bufPrint(buffer, "{s}-{d}", .{ workspace_dir_prefix, pid }) catch unreachable;
}

const engine_files = [_][]const u8{
    "circuit.zig",
    "memory.zig",
    "transport.zig",
    "log.zig",
};

fn copyTextFile(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    dest_dir: std.fs.Dir,
    destination_name: []const u8,
) !void {
    const data = try std.fs.cwd().readFileAlloc(allocator, source_path, 1024 * 1024);
    defer allocator.free(data);
    try dest_dir.writeFile(.{
        .sub_path = destination_name,
        .data = data,
    });
}

fn ensureSuccess(term: std.process.Child.Term) !void {
    switch (term) {
        .Exited => |code| {
            if (code != 0) return error.SubprocessFailed;
        },
        else => return error.SubprocessFailed,
    }
}

fn exitedCode(term: std.process.Child.Term) ?u8 {
    return switch (term) {
        .Exited => |code| code,
        else => null,
    };
}

pub fn compileAndRun(
    allocator: std.mem.Allocator,
    emitted_source: []const u8,
    script: []const u8,
) ![]u8 {
    var workspace_path_buf: [128]u8 = undefined;
    const workspace_path = processWorkspacePath(workspace_path_buf[0..]);

    try std.fs.cwd().makePath(workspace_path);
    var workspace = try std.fs.cwd().openDir(workspace_path, .{});
    defer workspace.close();

    try workspace.writeFile(.{
        .sub_path = "compiled.zig",
        .data = emitted_source,
    });
    try copyTextFile(allocator, "tests/harness/build.zig", workspace, "build.zig");

    for (engine_files) |engine_file| {
        const source_path = try std.fmt.allocPrint(allocator, "lib/{s}", .{engine_file});
        defer allocator.free(source_path);
        try copyTextFile(allocator, source_path, workspace, engine_file);
    }

    const build_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig", "build", "wasm", "-Doptimize=Debug" },
        .cwd = workspace_path,
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(build_result.stdout);
    defer allocator.free(build_result.stderr);
    if (exitedCode(build_result.term) != 0) {
        std.debug.print("zig build wasm failed\nstdout:\n{s}\nstderr:\n{s}\n", .{ build_result.stdout, build_result.stderr });
        return error.SubprocessFailed;
    }
    try ensureSuccess(build_result.term);

    const wasm_path = try std.fmt.allocPrint(allocator, "{s}/zig-out/bin/compiled.wasm", .{workspace_path});
    defer allocator.free(wasm_path);
    const encoded_len = std.base64.standard.Encoder.calcSize(script.len);
    const encoded_script = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded_script, script);
    defer allocator.free(encoded_script);

    const node_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", "tests/harness/loader.js", wasm_path, encoded_script },
        .cwd = ".",
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(node_result.stderr);
    if (exitedCode(node_result.term) != 0) {
        std.debug.print("node harness failed\nstdout:\n{s}\nstderr:\n{s}\n", .{ node_result.stdout, node_result.stderr });
        return error.SubprocessFailed;
    }
    try ensureSuccess(node_result.term);
    return node_result.stdout;
}
