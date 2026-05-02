const std = @import("std");
const embed = @import("orchestrator_embed");

fn containsName(name: []const u8) bool {
    for (embed.runtime_files) |file| {
        if (std.mem.eql(u8, file.name, name)) return true;
    }
    return false;
}

test "runtime embed manifest has non-empty content" {
    for (embed.runtime_files) |file| {
        try std.testing.expect(file.content.len > 0);
    }
}

test "runtime embed manifest contains expected names" {
    const expected_names = [_][]const u8{
        "build.zig",
        "src/main.zig",
        "src/circuit.zig",
        "src/memory.zig",
        "src/log.zig",
        "src/transport.zig",
    };

    for (expected_names) |name| {
        try std.testing.expect(containsName(name));
    }
}
