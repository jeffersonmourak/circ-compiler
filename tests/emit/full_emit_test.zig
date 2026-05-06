const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const validator_run = @import("validator_run");
const diagnostics = @import("diagnostics");
const emit_main = @import("emit_main");
const golden = @import("golden");

const Fixture = struct {
    name: []const u8,
    source_path: []const u8,
    source_name: []const u8,
    expected_path: []const u8,
};

const fixtures = [_]Fixture{
    .{
        .name = "empty-ish",
        .source_path = "tests/fixtures/circuits/empty_ish.circ",
        .source_name = "empty_ish.circ",
        .expected_path = "tests/fixtures/expected-zig/empty_ish.zig",
    },
    .{
        .name = "and-two-inputs",
        .source_path = "tests/fixtures/circuits/and_two_inputs.circ",
        .source_name = "and_two_inputs.circ",
        .expected_path = "tests/fixtures/expected-zig/and_two_inputs.zig",
    },
    .{
        .name = "anonymous-nested",
        .source_path = "tests/fixtures/circuits/anonymous_nested.circ",
        .source_name = "anonymous_nested.circ",
        .expected_path = "tests/fixtures/expected-zig/anonymous_nested.zig",
    },
};

fn hasHardErrors(diagnostic_list: []const diagnostics.Diagnostic) bool {
    for (diagnostic_list) |diagnostic| {
        if (diagnostic.level == .err) return true;
    }
    return false;
}

test "full emitter fixture files" {
    for (fixtures) |fixture| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const source = try std.fs.cwd().readFileAlloc(allocator, fixture.source_path, 1024 * 1024);
        const ast_file = try translate.parseSource(allocator, 0, source);
        const ir_module = try resolver.resolve(allocator, ast_file, 0);
        var diagnostic_list = try validator_run.run(allocator, &ir_module);
        defer diagnostic_list.deinit(allocator);
        if (hasHardErrors(diagnostic_list.items)) return error.InvalidFixtureForEmission;

        const emitted = try emit_main.emitModuleSource(allocator, &ir_module, .{
            .source_name = fixture.source_name,
            .compile_timestamp = "2026-05-01T22:00:00Z",
            .compiler_version = "circ-compiler/dev",
        });

        golden.expectGolden(emitted, fixture.expected_path) catch |err| {
            std.debug.print("Full emission fixture failed: {s}\n", .{fixture.name});
            return err;
        };
    }
}

test "emit topology_blob marker is circ.topology.v0.min" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = try std.fs.cwd().readFileAlloc(allocator, "tests/fixtures/circuits/empty_ish.circ", 1024 * 1024);
    const ast_file = try translate.parseSource(allocator, 0, source);
    const ir_module = try resolver.resolve(allocator, ast_file, 0);
    var diagnostic_list = try validator_run.run(allocator, &ir_module);
    defer diagnostic_list.deinit(allocator);
    if (hasHardErrors(diagnostic_list.items)) return error.InvalidFixtureForEmission;

    const emitted = try emit_main.emitModuleSource(allocator, &ir_module, .{
        .source_name = "empty_ish.circ",
        .compile_timestamp = "2026-05-01T22:00:00Z",
        .compiler_version = "circ-compiler/dev",
    });

    try std.testing.expect(std.mem.indexOf(u8, emitted, "\"circ.topology.v0.min\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, emitted, "\"debug-paths-v1\"") == null);
}
