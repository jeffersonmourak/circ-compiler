const std = @import("std");

const RunResult = struct {
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,

    fn deinit(self: *RunResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

fn run(args: []const []const u8) !RunResult {
    const allocator = std.testing.allocator;
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
        .cwd = ".",
        .max_output_bytes = 4 * 1024 * 1024,
    });
    return .{
        .term = result.term,
        .stdout = result.stdout,
        .stderr = result.stderr,
    };
}

fn exitCode(term: std.process.Child.Term) i32 {
    return switch (term) {
        .Exited => |code| @as(i32, @intCast(code)),
        .Signal => |signal| -@as(i32, @intCast(signal)),
        .Stopped => |signal| -@as(i32, @intCast(signal)),
        .Unknown => -1,
    };
}

fn buildCli() !void {
    var result = try run(&.{ "zig", "build", "circ-compile" });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 0), exitCode(result.term));
}

fn expectFileExists(path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    file.close();
}

fn expectFileMissing(path: []const u8) !void {
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().openFile(path, .{}));
}

test "cli default mode happy path writes wasm" {
    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/happy.wasm", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);

    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/inverter.circ", "-o", output_path });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 0), exitCode(result.term));
    try expectFileExists(output_path);
}

test "cli default mode hard error exits 1 and no output" {
    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/hard_error.wasm", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);

    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/E001_undeclared.circ", "-o", output_path });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 1), exitCode(result.term));
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "E001") != null);
    try expectFileMissing(output_path);
}

test "cli default mode warning exits 0 and writes output" {
    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/warning_ok.wasm", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);

    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/W001_unused_input.circ", "-o", output_path });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 0), exitCode(result.term));
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "W001") != null);
    try expectFileExists(output_path);
}

test "cli warnings-as-errors exits 1 on warning and no output" {
    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/warning_error.wasm", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);

    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/W001_unused_input.circ", "-o", output_path, "--warnings-as-errors" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 1), exitCode(result.term));
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "W001") != null);
    try expectFileMissing(output_path);
}

test "cli missing input file exits 2" {
    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/missing_input.wasm", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);

    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/does_not_exist.circ", "-o", output_path });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 2), exitCode(result.term));
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "input file not found") != null);
}

test "cli unknown flag exits 2" {
    try buildCli();
    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/inverter.circ", "--bogus", "-o", "out.wasm" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 2), exitCode(result.term));
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "usage error") != null);
}

test "cli build-dir preserves workspace" {
    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const build_dir = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/cli-build-dir", .{tmp.sub_path});
    defer std.testing.allocator.free(build_dir);
    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/build_dir_out.wasm", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);

    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/inverter.circ", "-o", output_path, "--build-dir", build_dir });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 0), exitCode(result.term));
    try expectFileExists(output_path);
    const compiled_source = try std.fmt.allocPrint(std.testing.allocator, "{s}/src/compiled.zig", .{build_dir});
    defer std.testing.allocator.free(compiled_source);
    try expectFileExists(compiled_source);
}
