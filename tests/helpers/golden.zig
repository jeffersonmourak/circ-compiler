const std = @import("std");

fn updateModeEnabled() bool {
    const env_value = std.posix.getenv("UPDATE_GOLDENS") orelse return false;
    return std.mem.eql(u8, env_value, "1");
}

pub fn expectGolden(actual: []const u8, fixture_path: []const u8) !void {
    if (updateModeEnabled()) {
        try std.fs.cwd().writeFile(.{
            .sub_path = fixture_path,
            .data = actual,
        });
        return;
    }

    const expected = std.fs.cwd().readFileAlloc(
        std.heap.page_allocator,
        fixture_path,
        1024 * 1024 * 10,
    ) catch |err| switch (err) {
        error.FileNotFound => {
            return error.GoldenFixtureMissing;
        },
        else => return err,
    };
    defer std.heap.page_allocator.free(expected);

    if (std.mem.eql(u8, expected, actual)) {
        return;
    }

    return error.GoldenMismatch;
}
