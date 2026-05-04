const std = @import("std");
const build_options = @import("build_options");
const zc = @import("zig_compiler");

pub fn main() !void {
    var stdout_buf: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_writer.interface;

    try out.print("spike ok\n", .{});
    try out.print("zig_lib_dir: {s}\n", .{build_options.zig_lib_dir});
    try out.print("zig_src_dir: {s}\n", .{build_options.zig_src_dir});

    // Reference real function bodies to force comptime analysis across the
    // codegen / link surface, then print their addresses so the linker has to
    // keep them. This is what proves the embedding strategy compiles & links
    // without LLVM (Phase 0 hard stop).
    const create_addr: usize = @intFromPtr(&zc.Compilation.create);
    const update_addr: usize = @intFromPtr(&zc.Compilation.update);
    const module_create_addr: usize = @intFromPtr(&zc.Package.Module.create);
    try out.print("Compilation.create  @ 0x{x}\n", .{create_addr});
    try out.print("Compilation.update  @ 0x{x}\n", .{update_addr});
    try out.print("Package.Module.create @ 0x{x}\n", .{module_create_addr});

    try out.flush();
}
