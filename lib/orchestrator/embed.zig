pub const EmbeddedFile = struct {
    name: []const u8,
    content: []const u8,
};

pub const runtime_files = [_]EmbeddedFile{
    .{ .name = "build.zig", .content = @embedFile("../../templates/build.zig") },
    .{ .name = "src/main.zig", .content = @embedFile("../../templates/main.zig") },
    .{ .name = "src/circuit.zig", .content = @embedFile("../../lib/circuit.zig") },
    .{ .name = "src/memory.zig", .content = @embedFile("../../lib/memory.zig") },
    .{ .name = "src/log.zig", .content = @embedFile("../../lib/log.zig") },
    .{ .name = "src/transport.zig", .content = @embedFile("../../lib/transport.zig") },
};
