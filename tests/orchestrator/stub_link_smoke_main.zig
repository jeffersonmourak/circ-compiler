const std = @import("std");
const workspace_mod = @import("orchestrator_workspace");
const inprocess = @import("orchestrator_inprocess");

const minimal_source =
    \\pub export fn add(a: i32, b: i32) i32 {
    \\    return a + b;
    \\}
    \\
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var workspace = try workspace_mod.createWorkspace(allocator, tmp_path);
    defer workspace.deinit();

    try workspace_mod.writeRuntime(&workspace);
    try workspace_mod.writeEmittedSource(&workspace, minimal_source);

    try inprocess.compile(allocator, workspace.path, std.io.null_writer);

    const out_path = try std.fmt.allocPrint(allocator, "{s}/zig-out/bin/compiled.wasm", .{workspace.path});
    defer allocator.free(out_path);

    const wasm = try std.fs.cwd().readFileAlloc(allocator, out_path, 4 * 1024 * 1024);
    defer allocator.free(wasm);

    if (wasm.len < 4 or !std.mem.eql(u8, wasm[0..4], "\x00asm")) return error.BadWasm;
}
