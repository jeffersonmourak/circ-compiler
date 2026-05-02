const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const validator_run = @import("validator_run");
const diagnostics = @import("diagnostics");
const build_fn = @import("build_fn");
const golden = @import("golden");

const Fixture = struct {
    name: []const u8,
    source_path: []const u8,
    expected_path: []const u8,
};

const fixtures = [_]Fixture{
    .{
        .name = "empty-ish",
        .source_path = "tests/fixtures/circuits/empty_ish.circ",
        .expected_path = "tests/fixtures/expected-zig/empty_ish_build_fn.zig",
    },
    .{
        .name = "and-two-inputs",
        .source_path = "tests/fixtures/circuits/and_two_inputs.circ",
        .expected_path = "tests/fixtures/expected-zig/and_two_inputs_build_fn.zig",
    },
    .{
        .name = "anonymous-nested",
        .source_path = "tests/fixtures/circuits/anonymous_nested.circ",
        .expected_path = "tests/fixtures/expected-zig/anonymous_nested_build_fn.zig",
    },
    .{
        .name = "keyword-instance-name",
        .source_path = "tests/fixtures/circuits/keyword_instance_name.circ",
        .expected_path = "tests/fixtures/expected-zig/keyword_instance_name_build_fn.zig",
    },
};

fn hasHardErrors(diagnostic_list: []const diagnostics.Diagnostic) bool {
    for (diagnostic_list) |diagnostic| {
        if (diagnostic.level == .err) return true;
    }
    return false;
}

test "buildCircuit emitter fixtures" {
    for (fixtures) |fixture| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const source = try std.fs.cwd().readFileAlloc(allocator, fixture.source_path, 1024 * 1024);
        const ast_file = try translate.parseSource(allocator, 0, source);
        const ir_module = try resolver.resolve(allocator, ast_file, 0);
        var diagnostic_list = try validator_run.run(allocator, &ir_module);
        defer diagnostic_list.deinit(allocator);

        if (hasHardErrors(diagnostic_list.items)) {
            std.debug.print("Fixture has hard diagnostics and cannot be emitted: {s}\n", .{fixture.name});
            return error.InvalidFixtureForEmission;
        }

        const emitted = try build_fn.emitBuildFunction(allocator, &ir_module);
        golden.expectGolden(emitted, fixture.expected_path) catch |err| {
            std.debug.print("Build function fixture failed: {s}\n", .{fixture.name});
            return err;
        };
    }
}
