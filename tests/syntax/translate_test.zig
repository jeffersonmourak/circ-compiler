const std = @import("std");
const translate = @import("translate");
const golden = @import("golden");
const ast_dump = @import("ast_dump");

const Fixture = struct {
    name: []const u8,
    source_path: []const u8,
    expected_ast_path: []const u8,
};

const fixtures = [_]Fixture{
    .{
        .name = "empty-ish",
        .source_path = "tests/fixtures/circuits/empty_ish.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/empty_ish.txt",
    },
    .{
        .name = "and-two-inputs",
        .source_path = "tests/fixtures/circuits/and_two_inputs.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/and_two_inputs.txt",
    },
    .{
        .name = "anonymous-nested",
        .source_path = "tests/fixtures/circuits/anonymous_nested.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/anonymous_nested.txt",
    },
    .{
        .name = "import-file",
        .source_path = "tests/fixtures/circuits/with_import.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/with_import.txt",
    },
    .{
        .name = "multiple-outputs",
        .source_path = "tests/fixtures/circuits/multi_output.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/multi_output.txt",
    },
};

test "translate parse tree to typed ast fixtures" {
    for (fixtures) |fixture| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const source = try std.fs.cwd().readFileAlloc(allocator, fixture.source_path, 1024 * 1024);
        const ast_file = try translate.parseSource(allocator, 0, source);
        const dump = try ast_dump.dumpFile(allocator, ast_file);

        golden.expectGolden(dump, fixture.expected_ast_path) catch |err| {
            std.debug.print("Fixture failed: {s}\n", .{fixture.name});
            return err;
        };
    }
}

test "edge: completely empty .circ fails parse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = try std.fs.cwd().readFileAlloc(allocator, "tests/fixtures/circuits/edge_parse_empty.circ", 1024);
    const parsed = translate.parseSource(allocator, 0, source);
    try std.testing.expectError(error.ParsingFailed, parsed);
}
