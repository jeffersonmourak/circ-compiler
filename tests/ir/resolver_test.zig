const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const ir_dump = @import("ir_dump");
const golden = @import("golden");

const Fixture = struct {
    name: []const u8,
    source_path: []const u8,
    expected_ir_path: []const u8,
};

const fixtures = [_]Fixture{
    .{
        .name = "single-primitive-resolution",
        .source_path = "tests/fixtures/circuits/and_two_inputs.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/and_two_inputs.txt",
    },
    .{
        .name = "anonymous-component-flattening",
        .source_path = "tests/fixtures/circuits/anonymous_nested.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/anonymous_nested.txt",
    },
    .{
        .name = "unknown-name-marker",
        .source_path = "tests/fixtures/circuits/unknown_component.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/unknown_component.txt",
    },
    .{
        .name = "import-alias-marker",
        .source_path = "tests/fixtures/circuits/with_import.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/with_import.txt",
    },
    .{
        .name = "output-component-connection",
        .source_path = "tests/fixtures/circuits/multi_output.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/multi_output.txt",
    },
};

test "resolve ast to ir fixtures" {
    for (fixtures) |fixture| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const source = try std.fs.cwd().readFileAlloc(allocator, fixture.source_path, 1024 * 1024);
        const ast_file = try translate.parseSource(allocator, 0, source);
        const module = try resolver.resolve(allocator, ast_file, 0);
        const dump = try ir_dump.dumpModule(allocator, module);

        golden.expectGolden(dump, fixture.expected_ir_path) catch |err| {
            std.debug.print("IR fixture failed: {s}\n", .{fixture.name});
            return err;
        };
    }
}
