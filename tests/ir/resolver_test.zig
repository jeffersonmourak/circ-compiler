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
    .{
        .name = "multibit-and-end-to-end",
        .source_path = "tests/fixtures/circuits/multibit_and_full.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/multibit_and_full.txt",
    },
    .{
        .name = "multibit-not-end-to-end",
        .source_path = "tests/fixtures/circuits/multibit_not_full.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/multibit_not_full.txt",
    },
    .{
        .name = "multibit-wire-end-to-end",
        .source_path = "tests/fixtures/circuits/multibit_wire_full.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/multibit_wire_full.txt",
    },
    .{
        .name = "multibit-led-end-to-end",
        .source_path = "tests/fixtures/circuits/multibit_led_full.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/multibit_led_full.txt",
    },
    .{
        .name = "scalar-default-width-one",
        .source_path = "tests/fixtures/circuits/width_default.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/width_default.txt",
    },
    .{
        .name = "slice-basic-low-bits",
        .source_path = "tests/fixtures/circuits/slice_basic.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/slice_basic.txt",
    },
    .{
        .name = "slice-high-bits-nonzero-lo",
        .source_path = "tests/fixtures/circuits/slice_high_bits.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/slice_high_bits.txt",
    },
    .{
        .name = "bit-index-lowers-to-width-1-slice",
        .source_path = "tests/fixtures/circuits/bit_index_a2.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/bit_index_a2.txt",
    },
    .{
        .name = "concat-four-bits-into-4-bit-bus",
        .source_path = "tests/fixtures/circuits/concat_four_bits.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/concat_four_bits.txt",
    },
    .{
        .name = "concat-nested-preserves-tree-shape",
        .source_path = "tests/fixtures/circuits/concat_nested.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/concat_nested.txt",
    },
    .{
        .name = "slice-then-concat-round-trip",
        .source_path = "tests/fixtures/circuits/slice_then_concat.circ",
        .expected_ir_path = "tests/fixtures/expected-ir/slice_then_concat.txt",
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

test "parameter width without introduction is a placeholder error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = try std.fs.cwd().readFileAlloc(
        allocator,
        "tests/fixtures/circuits/unparametric_uses_param.circ",
        1024 * 1024,
    );
    const ast_file = try translate.parseSource(allocator, 0, source);
    try std.testing.expectError(
        error.ParametricWidthNotImplemented,
        resolver.resolve(allocator, ast_file, 0),
    );
}
