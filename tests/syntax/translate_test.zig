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
    .{
        .name = "multibit-input",
        .source_path = "tests/fixtures/circuits/multibit_input.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/multibit_input.txt",
    },
    .{
        .name = "multibit-and",
        .source_path = "tests/fixtures/circuits/multibit_and.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/multibit_and.txt",
    },
    .{
        .name = "multibit-output",
        .source_path = "tests/fixtures/circuits/multibit_output.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/multibit_output.txt",
    },
    .{
        .name = "multibit-not",
        .source_path = "tests/fixtures/circuits/multibit_not.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/multibit_not.txt",
    },
    .{
        .name = "multibit-led",
        .source_path = "tests/fixtures/circuits/multibit_led.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/multibit_led.txt",
    },
    .{
        .name = "multibit-wire",
        .source_path = "tests/fixtures/circuits/multibit_wire.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/multibit_wire.txt",
    },
    .{
        .name = "width-edges",
        .source_path = "tests/fixtures/circuits/width_edges.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/width_edges.txt",
    },
    .{
        .name = "width-whitespace",
        .source_path = "tests/fixtures/circuits/width_whitespace.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/width_whitespace.txt",
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

// The parser may either raise an error or silently produce zero declarations
// for malformed width syntax — both outcomes are acceptable. The invariant
// these tests protect is "invalid width syntax does NOT produce an input
// declaration whose name carries that bogus width as a literal".
fn expectNoInputDecl(source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = translate.parseSource(allocator, 0, source) catch return;
    try std.testing.expectEqual(@as(usize, 0), parsed.inputs.len);
}

test "width: large literal beyond engine max still parses (validation is later)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try translate.parseSource(allocator, 0, "input[100] a\n");
    try std.testing.expectEqual(@as(usize, 1), parsed.inputs.len);
    const width = parsed.inputs[0].names[0].width orelse return error.MissingWidth;
    try std.testing.expectEqual(@as(u8, 100), width.literal);
}

test "width: empty brackets are not interpreted as a width annotation" {
    try expectNoInputDecl("input[] a\n");
}

test "width: identifier inside brackets is not interpreted as a width (deferred to S3.2)" {
    try expectNoInputDecl("input[abc] a\n");
}

test "width: negative integer is not interpreted as a width" {
    try expectNoInputDecl("input[-1] a\n");
}

test "width: floating-point literal is not interpreted as a width" {
    try expectNoInputDecl("input[1.5] a\n");
}

test "width: unclosed bracket is not interpreted as a width" {
    try expectNoInputDecl("input[4 a\n");
}
