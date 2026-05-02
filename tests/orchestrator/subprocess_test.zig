const std = @import("std");
const subprocess = @import("orchestrator_subprocess");

test "subprocess wrapper succeeds for zig version" {
    var err_capture: std.ArrayList(u8) = .{};
    defer err_capture.deinit(std.testing.allocator);

    var result = try subprocess.runCommand(
        std.testing.allocator,
        &.{ "zig", "version" },
        ".",
        "/tmp/unused",
        err_capture.writer(std.testing.allocator),
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 0), result.exit_code);
    try std.testing.expect(result.stdout.len > 0);
    try std.testing.expectEqual(@as(usize, 0), err_capture.items.len);
}

test "subprocess wrapper captures failure and prints header" {
    var err_capture: std.ArrayList(u8) = .{};
    defer err_capture.deinit(std.testing.allocator);

    const failing_build_dir = "/tmp/circ-build-dir-for-test";
    var result = try subprocess.runCommand(
        std.testing.allocator,
        &.{ "zig", "--invalid-flag" },
        ".",
        failing_build_dir,
        err_capture.writer(std.testing.allocator),
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(result.stderr.len > 0 or result.stdout.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, err_capture.items, "zig build failed in ") != null);
    try std.testing.expect(std.mem.indexOf(u8, err_capture.items, failing_build_dir) != null);
}
