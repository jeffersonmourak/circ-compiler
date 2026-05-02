const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const validator_run = @import("validator_run");
const diagnostics = @import("diagnostics");
const emit_main = @import("emit_main");
const orchestrator = @import("orchestrator_main");

fn hasHardErrors(diagnostic_list: []const diagnostics.Diagnostic) bool {
    for (diagnostic_list) |diagnostic| {
        if (diagnostic.level == .err) return true;
    }
    return false;
}

fn buildEmittedSource(allocator: std.mem.Allocator, source_path: []const u8, source_name: []const u8) ![]u8 {
    const source = try std.fs.cwd().readFileAlloc(allocator, source_path, 1024 * 1024);
    const ast_file = try translate.parseSource(allocator, 0, source);
    const ir_module = try resolver.resolve(allocator, ast_file, 0);
    var diagnostic_list = try validator_run.run(allocator, &ir_module);
    defer diagnostic_list.deinit(allocator);
    if (hasHardErrors(diagnostic_list.items)) return error.InvalidFixtureForEmission;

    return emit_main.emitModuleSource(allocator, &ir_module, .{
        .source_name = source_name,
        .compile_timestamp = "2026-05-01T22:00:00Z",
        .compiler_version = "circ-compiler/dev",
    });
}

test "orchestrator compile produces wasm and cleans temp workspace" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const emitted = try buildEmittedSource(allocator, "tests/fixtures/circuits/inverter.circ", "inverter.circ");
    defer allocator.free(emitted);

    const output_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/output/inverter.wasm", .{tmp.sub_path});
    defer allocator.free(output_path);

    var result = try orchestrator.compile(allocator, emitted, .{
        .output_wasm_path = output_path,
        .build_dir = null,
    });
    defer result.deinit(allocator);

    try std.testing.expect(result.cleaned_up);
    const output_bytes = try std.fs.cwd().readFileAlloc(allocator, output_path, 1024 * 1024);
    try std.testing.expect(output_bytes.len >= 4);
    try std.testing.expectEqualStrings("\x00asm", output_bytes[0..4]);
    try std.testing.expectError(error.FileNotFound, std.fs.openDirAbsolute(result.build_dir, .{}));
}

test "orchestrator compile preserves supplied build_dir" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const emitted = try buildEmittedSource(allocator, "tests/fixtures/circuits/inverter.circ", "inverter.circ");
    defer allocator.free(emitted);

    const build_dir = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/manual-build-dir", .{tmp.sub_path});
    defer allocator.free(build_dir);
    const output_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/output/manual.wasm", .{tmp.sub_path});
    defer allocator.free(output_path);

    var result = try orchestrator.compile(allocator, emitted, .{
        .output_wasm_path = output_path,
        .build_dir = build_dir,
    });
    defer result.deinit(allocator);

    try std.testing.expect(!result.cleaned_up);
    try std.testing.expectEqualStrings(build_dir, result.build_dir);

    var dir = try std.fs.cwd().openDir(build_dir, .{});
    dir.close();
    const compiled_source = try std.fmt.allocPrint(allocator, "{s}/src/compiled.zig", .{build_dir});
    defer allocator.free(compiled_source);
    const compiled_bytes = try std.fs.cwd().readFileAlloc(allocator, compiled_source, 1024 * 1024);
    try std.testing.expect(compiled_bytes.len > 0);
}

test "orchestrator compile failure preserves build_dir" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const build_dir = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/broken-build-dir", .{tmp.sub_path});
    defer allocator.free(build_dir);
    const output_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/output/broken.wasm", .{tmp.sub_path});
    defer allocator.free(output_path);

    const invalid_source = "this is not valid zig source";
    var err_capture: std.ArrayList(u8) = .{};
    defer err_capture.deinit(allocator);

    try std.testing.expectError(
        error.ZigBuildFailed,
        orchestrator.compileWithStderrWriter(
            allocator,
            invalid_source,
            .{
                .output_wasm_path = output_path,
                .build_dir = build_dir,
            },
            err_capture.writer(allocator),
        ),
    );

    var dir = try std.fs.cwd().openDir(build_dir, .{});
    dir.close();
}
