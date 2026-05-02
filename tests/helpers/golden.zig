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
            std.debug.print(
                "Golden fixture not found at '{s}'. Run tests with UPDATE_GOLDENS=1 to create it.\n",
                .{fixture_path},
            );
            return error.GoldenFixtureMissing;
        },
        else => return err,
    };
    defer std.heap.page_allocator.free(expected);

    if (std.mem.eql(u8, expected, actual)) {
        return;
    }

    if (std.mem.indexOfDiff(u8, expected, actual)) |idx| {
        std.debug.print(
            "Golden mismatch at '{s}' (first difference at byte {d}).\n",
            .{ fixture_path, idx },
        );
    } else {
        std.debug.print(
            "Golden mismatch at '{s}' (different lengths: expected {d}, actual {d}).\n",
            .{ fixture_path, expected.len, actual.len },
        );
    }

    return error.GoldenMismatch;
}
