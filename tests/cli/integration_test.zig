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

// `zig build circ-compile` produces an identical binary for every test in this
// file, so build it at most once. Zig runs a test binary's tests serially on a
// single thread, so a plain flag suffices (no atomics / std.once). A failed
// first build leaves the flag false, so later tests retry rather than skip.
var cli_built = false;

fn buildCli() !void {
    if (cli_built) return;
    var result = try run(&.{ "zig", "build", "circ-compile" });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 0), exitCode(result.term));
    cli_built = true;
}

fn expectFileExists(path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    file.close();
}

fn expectFileMissing(path: []const u8) !void {
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().openFile(path, .{}));
}

fn readFile(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, 16 * 1024 * 1024);
}

fn expectStdoutMatchesFixture(actual: []const u8, fixture_path: []const u8) !void {
    const expected = try readFile(fixture_path);
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
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

test "cli build-dir is rejected as unknown flag" {
    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const build_dir = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/cli-build-dir", .{tmp.sub_path});
    defer std.testing.allocator.free(build_dir);
    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/build_dir_out.wasm", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);

    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/inverter.circ", "-o", output_path, "--build-dir", build_dir });
    defer result.deinit(std.testing.allocator);

    // --build-dir is now an unknown flag — exits 2 with a usage error
    try std.testing.expectEqual(@as(i32, 2), exitCode(result.term));
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "usage error") != null);
}

test "cli emit-zig mode writes expected zig file" {
    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/emit_zig_out.zig", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);

    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/and_two_inputs.circ", "--emit-zig", "-o", output_path });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 0), exitCode(result.term));
    try expectFileExists(output_path);

    const actual = try readFile(output_path);
    defer std.testing.allocator.free(actual);
    const expected = try readFile("tests/fixtures/expected-zig/and_two_inputs.zig");
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
}

test "cli emit-zig hard error exits 1 and no output" {
    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/emit_hard_error.zig", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);

    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/E001_undeclared.circ", "--emit-zig", "-o", output_path });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 1), exitCode(result.term));
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "E001") != null);
    try expectFileMissing(output_path);
}

test "cli build-dir is unknown flag in all modes" {
    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/emit_build_dir_reject.zig", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);
    const build_dir = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/emit-build-dir", .{tmp.sub_path});
    defer std.testing.allocator.free(build_dir);

    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/inverter.circ", "--emit-zig", "-o", output_path, "--build-dir", build_dir });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 2), exitCode(result.term));
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "usage error") != null);
}

test "cli inspect clean fixture exits 0 and matches golden stdout" {
    try buildCli();
    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/inverter.circ", "--inspect" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 0), exitCode(result.term));
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    try expectStdoutMatchesFixture(result.stdout, "tests/fixtures/expected-inspect/clean_inverter.txt");
}

test "cli inspect memory fixture exits 0 and matches golden stdout" {
    try buildCli();
    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/rom_basic.circ", "--inspect" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 0), exitCode(result.term));
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    try expectStdoutMatchesFixture(result.stdout, "tests/fixtures/expected-inspect/rom_basic.txt");
}

test "cli memory sources are rejected in every artifact mode" {
    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const wasm_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/rom_basic.wasm", .{tmp.sub_path});
    defer std.testing.allocator.free(wasm_path);
    const zig_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/rom_basic.zig", .{tmp.sub_path});
    defer std.testing.allocator.free(zig_path);

    const rejection = "rom/ram are not yet supported in this mode";
    const invocations = [_][]const []const u8{
        &.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/rom_basic.circ", "-o", wasm_path },
        &.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/rom_basic.circ", "--emit-zig", "-o", zig_path },
        &.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/rom_basic.circ", "--preview" },
        &.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/rom_basic.circ", "--truth-table" },
        &.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/ram_basic.circ", "--sim" },
    };
    for (invocations) |argv| {
        var result = try run(argv);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(i32, 1), exitCode(result.term));
        try std.testing.expectEqual(@as(usize, 0), result.stdout.len);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, rejection) != null);
    }
    try expectFileMissing(wasm_path);
    try expectFileMissing(zig_path);
}

test "cli inspect error fixture exits 1 and matches golden stdout" {
    try buildCli();
    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/E001_undeclared.circ", "--inspect" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 1), exitCode(result.term));
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    try expectStdoutMatchesFixture(result.stdout, "tests/fixtures/expected-inspect/error_undeclared.txt");
}

test "cli inspect canonical half_adder project root matches golden" {
    try buildCli();
    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/projects/half_adder/root.circ", "--inspect" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 0), exitCode(result.term));
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    try expectStdoutMatchesFixture(result.stdout, "tests/fixtures/expected-inspect/canonical_half_adder_root.txt");
}

test "cli inspect rejects -o flag" {
    try buildCli();
    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/inverter.circ", "--inspect", "-o", "ignored.txt" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 2), exitCode(result.term));
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "-o is not valid in --inspect mode") != null);
}

test "perf smoke: 100-component grid compiles under budget" {
    if (std.process.hasEnvVarConstant("CIRC_SKIP_PERF")) return error.SkipZigTest;

    try buildCli();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/perf.wasm", .{tmp.sub_path});
    defer std.testing.allocator.free(output_path);

    const start_ns = std.time.nanoTimestamp();
    var result = try run(&.{ "zig-out/bin/circ-compile", "tests/fixtures/circuits/stress_grid_10x10.circ", "-o", output_path });
    defer result.deinit(std.testing.allocator);
    const elapsed_ns = std.time.nanoTimestamp() - start_ns;

    try std.testing.expectEqual(@as(i32, 0), exitCode(result.term));
    try expectFileExists(output_path);

    const budget_ns: i128 = 30 * std.time.ns_per_s;
    if (elapsed_ns >= budget_ns) {
        std.debug.print("perf smoke: stress_grid_10x10 compile took {d}ms (budget 30000ms)\n", .{@divTrunc(elapsed_ns, std.time.ns_per_ms)});
        return error.PerfBudgetExceeded;
    }
}
