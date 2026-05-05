const std = @import("std");
const workspace_mod = @import("orchestrator_workspace");
const subprocess_mod = @import("orchestrator_subprocess");
const finalize_mod = @import("orchestrator_finalize");
const build_options = @import("orchestrator_build_options");

pub const OrchestratorOptions = struct {
    output_wasm_path: []const u8,
    build_dir: ?[]const u8 = null,
};

pub const OrchestratorResult = struct {
    output_wasm_path: []u8,
    build_dir: []u8,
    cleaned_up: bool,

    pub fn deinit(self: *OrchestratorResult, allocator: std.mem.Allocator) void {
        allocator.free(self.output_wasm_path);
        allocator.free(self.build_dir);
    }
};

pub fn compile(
    allocator: std.mem.Allocator,
    emitted_zig_source: []const u8,
    options: OrchestratorOptions,
) !OrchestratorResult {
    return compileWithStderrWriter(allocator, emitted_zig_source, options, std.fs.File.stderr().deprecatedWriter());
}

pub fn compileWithStderrWriter(
    allocator: std.mem.Allocator,
    emitted_zig_source: []const u8,
    options: OrchestratorOptions,
    stderr_writer: anytype,
) !OrchestratorResult {
    var workspace = try workspace_mod.createWorkspace(allocator, options.build_dir);
    defer workspace.deinit();

    try workspace_mod.writeRuntime(&workspace);
    try workspace_mod.writeEmittedSource(&workspace, emitted_zig_source);

    if (build_options.use_subprocess_for_wasm) {
        const zig_argv = [_][]const u8{ "zig", "build", "wasm" };
        var zig_result = try subprocess_mod.runCommand(
            allocator,
            &zig_argv,
            workspace.path,
            workspace.path,
            stderr_writer,
        );
        defer zig_result.deinit(allocator);
        if (zig_result.exit_code != 0) return error.ZigBuildFailed;
    } else {
        const inprocess_mod = @import("orchestrator_inprocess");
        try inprocess_mod.compile(allocator, workspace.path, stderr_writer);
    }

    try finalize_mod.copyOutput(&workspace, options.output_wasm_path);

    var cleaned_up = false;
    if (workspace.cleanup_on_success) {
        try finalize_mod.cleanup(&workspace);
        cleaned_up = true;
    }

    return .{
        .output_wasm_path = try allocator.dupe(u8, options.output_wasm_path),
        .build_dir = try allocator.dupe(u8, workspace.path),
        .cleaned_up = cleaned_up,
    };
}
