const std = @import("std");

const engine_files = [_][]const u8{
    "circuit.zig",
    "memory.zig",
    "transport.zig",
    "log.zig",
};

fn tmpDirPath(allocator: std.mem.Allocator, tmp: *std.testing.TmpDir) ![]u8 {
    return std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
}

fn copyTextFile(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    tmp: *std.testing.TmpDir,
    destination_name: []const u8,
) !void {
    const data = try std.fs.cwd().readFileAlloc(allocator, source_path, 1024 * 1024);
    defer allocator.free(data);
    try tmp.dir.writeFile(.{
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
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "compiled.zig",
        .data = emitted_source,
    });
    try copyTextFile(allocator, "tests/harness/build.zig", &tmp, "build.zig");

    for (engine_files) |engine_file| {
        const source_path = try std.fmt.allocPrint(allocator, "lib/{s}", .{engine_file});
        defer allocator.free(source_path);
        try copyTextFile(allocator, source_path, &tmp, engine_file);
    }

    const tmp_path = try tmpDirPath(allocator, &tmp);
    defer allocator.free(tmp_path);

    const build_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig", "build", "wasm", "-Doptimize=Debug" },
        .cwd = tmp_path,
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(build_result.stdout);
    defer allocator.free(build_result.stderr);
    if (exitedCode(build_result.term) != 0) {
        std.debug.print("zig build wasm failed\nstdout:\n{s}\nstderr:\n{s}\n", .{ build_result.stdout, build_result.stderr });
        return error.SubprocessFailed;
    }
    try ensureSuccess(build_result.term);

    const wasm_path = try std.fmt.allocPrint(allocator, "{s}/zig-out/bin/compiled.wasm", .{tmp_path});
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
