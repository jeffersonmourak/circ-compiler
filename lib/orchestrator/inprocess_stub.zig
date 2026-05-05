const std = @import("std");
const build_options = @import("build_options");

extern fn circ_inprocess_compile(
    workspace_path_z: [*:0]const u8,
    zig_lib_dir_z: [*:0]const u8,
    compiler_rt_z: [*:0]const u8,
) callconv(.c) c_int;

fn toNullTerminated(arena: std.mem.Allocator, s: []const u8) ![*:0]const u8 {
    const buf = try arena.allocSentinel(u8, s.len, 0);
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return buf.ptr;
}

/// Same contract as `inprocess.zig`; implementation calls `circ_inprocess_compile` in `libinprocess.a`.
pub fn compile(
    allocator: std.mem.Allocator,
    workspace_path: []const u8,
    stderr_writer: anytype,
) !void {
    _ = stderr_writer;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const abs_workspace = if (std.fs.path.isAbsolute(workspace_path))
        try arena.dupe(u8, workspace_path)
    else
        try std.fs.cwd().realpathAlloc(arena, workspace_path);

    const ws_z = try toNullTerminated(arena, abs_workspace);
    const zig_z = try toNullTerminated(arena, build_options.zig_lib_dir);
    const crt_z = try toNullTerminated(arena, build_options.wasm_compiler_rt);

    switch (circ_inprocess_compile(ws_z, zig_z, crt_z)) {
        0 => return,
        else => return error.ZigBuildFailed,
    }
}
