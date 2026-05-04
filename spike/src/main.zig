const std = @import("std");
const build_options = @import("build_options");

pub fn main() !void {
    var stdout_buf: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_writer.interface;

    try out.print("spike ok\n", .{});
    try out.print("zig_lib_dir: {s}\n", .{build_options.zig_lib_dir});
    try out.flush();
}
