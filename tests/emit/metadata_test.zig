const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const validator_run = @import("validator_run");
const diagnostics = @import("diagnostics");
const file_info = @import("emit_file_info");
const file_info_format = @import("emit_file_info_format");
const debug_paths = @import("emit_debug_paths");
const golden = @import("golden");

const Fixture = struct {
    source_path: []const u8,
    source_name: []const u8,
    expected_file_info_path: []const u8,
    expected_debug_paths_path: []const u8,
};

const fixtures = [_]Fixture{
    .{
        .source_path = "tests/fixtures/circuits/empty_ish.circ",
        .source_name = "empty_ish.circ",
        .expected_file_info_path = "tests/fixtures/expected-zig/empty_ish_file_info.zig",
        .expected_debug_paths_path = "tests/fixtures/expected-zig/empty_ish_debug_paths.zig",
    },
    .{
        .source_path = "tests/fixtures/circuits/and_two_inputs.circ",
        .source_name = "and_two_inputs.circ",
        .expected_file_info_path = "tests/fixtures/expected-zig/and_two_inputs_file_info.zig",
        .expected_debug_paths_path = "tests/fixtures/expected-zig/and_two_inputs_debug_paths.zig",
    },
    .{
        .source_path = "tests/fixtures/circuits/anonymous_nested.circ",
        .source_name = "anonymous_nested.circ",
        .expected_file_info_path = "tests/fixtures/expected-zig/anonymous_nested_file_info.zig",
        .expected_debug_paths_path = "tests/fixtures/expected-zig/anonymous_nested_debug_paths.zig",
    },
};

fn hasHardErrors(diagnostic_list: []const diagnostics.Diagnostic) bool {
    for (diagnostic_list) |diagnostic| {
        if (diagnostic.level == .err) return true;
    }
    return false;
}

fn parseResolveValidate(allocator: std.mem.Allocator, source_path: []const u8) !@import("ir_types").Module {
    const source = try std.fs.cwd().readFileAlloc(allocator, source_path, 1024 * 1024);
    const ast_file = try translate.parseSource(allocator, 0, source);
    const ir_module = try resolver.resolve(allocator, ast_file, 0);

    var diagnostic_list = try validator_run.run(allocator, &ir_module);
    defer diagnostic_list.deinit(allocator);
    if (hasHardErrors(diagnostic_list.items)) return error.InvalidFixtureForEmission;

    return ir_module;
}

test "file info and debug path emitters fixtures" {
    for (fixtures) |fixture| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const ir_module = try parseResolveValidate(allocator, fixture.source_path);

        const emitted_file_info = try file_info.emitFileInfoConstants(allocator, &ir_module, .{
            .source_name = fixture.source_name,
            .compile_timestamp = "2026-05-01T22:00:00Z",
            .compiler_version = "circ-compiler/dev",
        });
        try golden.expectGolden(emitted_file_info, fixture.expected_file_info_path);

        const emitted_debug_paths = try debug_paths.emitDebugPathsConstants(allocator, &ir_module, .{
            .root_name = fixture.source_name,
        });
        try golden.expectGolden(emitted_debug_paths, fixture.expected_debug_paths_path);
    }
}

test "file info blob round trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ir_module = try parseResolveValidate(allocator, "tests/fixtures/circuits/and_two_inputs.circ");
    const encoded = try file_info.encodeFileInfoBlob(allocator, &ir_module, .{
        .source_name = "and_two_inputs.circ",
        .compile_timestamp = "2026-05-01T22:00:00Z",
        .compiler_version = "circ-compiler/dev",
    });
    const decoded = try file_info_format.decodeFileInfo(allocator, encoded);
    defer {
        var mutable = decoded;
        mutable.deinit(allocator);
    }

    try std.testing.expectEqual(@as(u32, 1), decoded.schema_version);
    try std.testing.expectEqual(@as(u32, 0), decoded.file_id);
    try std.testing.expectEqualStrings("and_two_inputs.circ", decoded.source_name);
    try std.testing.expectEqualStrings("2026-05-01T22:00:00Z", decoded.compile_timestamp);
    try std.testing.expectEqualStrings("circ-compiler/dev", decoded.compiler_version);
    try std.testing.expectEqual(@as(u32, 4), decoded.component_count);
    try std.testing.expectEqual(@as(u32, 3), decoded.connection_count);
    try std.testing.expectEqual(@as(usize, 2), decoded.inputs.len);
    try std.testing.expectEqualStrings("a", decoded.inputs[0].name);
    try std.testing.expectEqual(@as(u32, 0), decoded.inputs[0].component_id);
    try std.testing.expectEqualStrings("b", decoded.inputs[1].name);
    try std.testing.expectEqual(@as(u32, 1), decoded.inputs[1].component_id);
    try std.testing.expectEqual(@as(usize, 1), decoded.outputs.len);
    try std.testing.expectEqualStrings("result", decoded.outputs[0].name);
    try std.testing.expectEqual(@as(u32, 2), decoded.outputs[0].component_id);
}
