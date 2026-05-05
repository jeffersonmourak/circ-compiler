const std = @import("std");
const inprocess = @import("orchestrator_inprocess");
const workspace_mod = @import("orchestrator_workspace");

// Minimal Zig source that produces a valid WASM export without importing
// any of the bundled runtime modules (circuit.zig, memory.zig, etc.).
const minimal_source =
    \\pub export fn add(a: i32, b: i32) i32 {
    \\    return a + b;
    \\}
    \\
;

test "inprocess compile produces valid wasm" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var workspace = try workspace_mod.createWorkspace(allocator, tmp_path);
    defer workspace.deinit();

    try workspace_mod.writeRuntime(&workspace);
    try workspace_mod.writeEmittedSource(&workspace, minimal_source);

    var stderr_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer stderr_buf.deinit(allocator);

    try inprocess.compile(allocator, workspace.path, stderr_buf.writer(allocator));

    const out_path = try std.fmt.allocPrint(allocator, "{s}/zig-out/bin/compiled.wasm", .{workspace.path});
    defer allocator.free(out_path);

    const wasm = try std.fs.cwd().readFileAlloc(allocator, out_path, 4 * 1024 * 1024);
    defer allocator.free(wasm);

    try std.testing.expect(wasm.len >= 4);
    try std.testing.expectEqualStrings("\x00asm", wasm[0..4]);
}
