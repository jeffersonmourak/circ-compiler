const std = @import("std");

pub const RunResult = struct {
    term: std.process.Child.Term,
    exit_code: i32,
    stdout: []u8,
    stderr: []u8,

    pub fn deinit(self: *RunResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

fn termToExitCode(term: std.process.Child.Term) i32 {
    return switch (term) {
        .Exited => |code| @as(i32, @intCast(code)),
        .Signal => |signal| -@as(i32, @intCast(signal)),
        .Stopped => |signal| -@as(i32, @intCast(signal)),
        .Unknown => -1,
    };
}

pub fn runCommand(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    cwd: []const u8,
    build_dir_for_errors: []const u8,
    stderr_writer: anytype,
) !RunResult {
    const child_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd,
        .max_output_bytes = 1024 * 1024,
    }) catch |err| {
        if (err == error.FileNotFound and argv.len > 0 and std.mem.eql(u8, argv[0], "zig")) {
            return error.ZigBinaryNotFound;
        }
        return err;
    };

    const result = RunResult{
        .term = child_result.term,
        .exit_code = termToExitCode(child_result.term),
        .stdout = child_result.stdout,
        .stderr = child_result.stderr,
    };

    if (result.exit_code != 0) {
        try stderr_writer.print("zig build failed in {s}:\n", .{build_dir_for_errors});
        if (result.stderr.len > 0) try stderr_writer.writeAll(result.stderr);
        if (result.stdout.len > 0) try stderr_writer.writeAll(result.stdout);
    }

    return result;
}
