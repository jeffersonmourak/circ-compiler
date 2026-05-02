const std = @import("std");
const testing = std.testing;
const golden = @import("golden.zig");

const c = @cImport({
    @cInclude("stdlib.h");
});

fn setUpdateGoldensEnabled(enabled: bool) !void {
    if (enabled) {
        if (c.setenv("UPDATE_GOLDENS", "1", 1) != 0) {
            return error.FailedToSetEnvVar;
        }
        return;
    }

    if (c.unsetenv("UPDATE_GOLDENS") != 0) {
        return error.FailedToUnsetEnvVar;
    }
}

fn tmpFixturePath(allocator: std.mem.Allocator, tmp: *testing.TmpDir, filename: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path, filename });
}

test "expectGolden passes on matching content" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const fixture_path = try tmpFixturePath(testing.allocator, &tmp, "matching.txt");
    defer testing.allocator.free(fixture_path);

    try std.fs.cwd().writeFile(.{
        .sub_path = fixture_path,
        .data = "expected-content",
    });

    try setUpdateGoldensEnabled(false);
    try golden.expectGolden("expected-content", fixture_path);
}

test "expectGolden fails on mismatching content" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const fixture_path = try tmpFixturePath(testing.allocator, &tmp, "mismatch.txt");
    defer testing.allocator.free(fixture_path);

    try std.fs.cwd().writeFile(.{
        .sub_path = fixture_path,
        .data = "expected-content",
    });

    try setUpdateGoldensEnabled(false);
    try testing.expectError(error.GoldenMismatch, golden.expectGolden("actual-content", fixture_path));
}

test "expectGolden fails when fixture is missing and update mode is off" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const fixture_path = try tmpFixturePath(testing.allocator, &tmp, "missing.txt");
    defer testing.allocator.free(fixture_path);

    try setUpdateGoldensEnabled(false);
    try testing.expectError(error.GoldenFixtureMissing, golden.expectGolden("any-content", fixture_path));
}

test "expectGolden update mode writes a missing fixture" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const fixture_path = try tmpFixturePath(testing.allocator, &tmp, "create.txt");
    defer testing.allocator.free(fixture_path);

    try setUpdateGoldensEnabled(true);
    defer setUpdateGoldensEnabled(false) catch {};

    try golden.expectGolden("created-content", fixture_path);

    const file_data = try std.fs.cwd().readFileAlloc(testing.allocator, fixture_path, 1024 * 1024);
    defer testing.allocator.free(file_data);

    try testing.expectEqualStrings("created-content", file_data);
}

test "expectGolden update mode overwrites an existing fixture" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const fixture_path = try tmpFixturePath(testing.allocator, &tmp, "overwrite.txt");
    defer testing.allocator.free(fixture_path);

    try std.fs.cwd().writeFile(.{
        .sub_path = fixture_path,
        .data = "old-content",
    });

    try setUpdateGoldensEnabled(true);
    defer setUpdateGoldensEnabled(false) catch {};

    try golden.expectGolden("new-content", fixture_path);

    const file_data = try std.fs.cwd().readFileAlloc(testing.allocator, fixture_path, 1024 * 1024);
    defer testing.allocator.free(file_data);

    try testing.expectEqualStrings("new-content", file_data);
}
