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
    .{
        .name = "param-input-single",
        .source_path = "tests/fixtures/circuits/param_input_single.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/param_input_single.txt",
    },
    .{
        .name = "param-input-multi",
        .source_path = "tests/fixtures/circuits/param_input_multi.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/param_input_multi.txt",
    },
    .{
        .name = "param-callsite-single",
        .source_path = "tests/fixtures/circuits/param_callsite_single.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/param_callsite_single.txt",
    },
    .{
        .name = "param-callsite-multi",
        .source_path = "tests/fixtures/circuits/param_callsite_multi.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/param_callsite_multi.txt",
    },
    .{
        .name = "param-callsite-ident",
        .source_path = "tests/fixtures/circuits/param_callsite_ident.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/param_callsite_ident.txt",
    },
    .{
        .name = "param-used-as-width",
        .source_path = "tests/fixtures/circuits/param_used_as_width.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/param_used_as_width.txt",
    },
    .{
        .name = "param-whitespace",
        .source_path = "tests/fixtures/circuits/param_whitespace.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/param_whitespace.txt",
    },
    .{
        .name = "portref-index",
        .source_path = "tests/fixtures/circuits/portref_index.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/portref_index.txt",
    },
    .{
        .name = "portref-slice",
        .source_path = "tests/fixtures/circuits/portref_slice.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/portref_slice.txt",
    },
    .{
        .name = "portref-concat-simple",
        .source_path = "tests/fixtures/circuits/portref_concat_simple.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/portref_concat_simple.txt",
    },
    .{
        .name = "portref-concat-mixed",
        .source_path = "tests/fixtures/circuits/portref_concat_mixed.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/portref_concat_mixed.txt",
    },
    .{
        .name = "portref-concat-nested",
        .source_path = "tests/fixtures/circuits/portref_concat_nested.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/portref_concat_nested.txt",
    },
    .{
        .name = "portref-compose",
        .source_path = "tests/fixtures/circuits/portref_compose.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/portref_compose.txt",
    },
    .{
        .name = "portref-concat-whitespace",
        .source_path = "tests/fixtures/circuits/portref_concat_whitespace.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/portref_concat_whitespace.txt",
    },
    .{
        .name = "recovery-busvalue-eof",
        .source_path = "tests/fixtures/circuits/recovery_busvalue_eof.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/recovery_busvalue_eof.txt",
    },
    .{
        .name = "recovery-busvalue-newline",
        .source_path = "tests/fixtures/circuits/recovery_busvalue_newline.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/recovery_busvalue_newline.txt",
    },
    .{
        .name = "recovery-busclose-midline",
        .source_path = "tests/fixtures/circuits/recovery_busclose_midline.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/recovery_busclose_midline.txt",
    },
    .{
        .name = "recovery-busclose-newline",
        .source_path = "tests/fixtures/circuits/recovery_busclose_newline.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/recovery_busclose_newline.txt",
    },
    .{
        .name = "recovery-empty-ports",
        .source_path = "tests/fixtures/circuits/recovery_empty_ports.circ",
        .expected_ast_path = "tests/fixtures/expected-ast/recovery_empty_ports.txt",
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

test "errors: clean source has no marks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try translate.parseSource(allocator, 0, "input a\noutput o(in=a)\n");
    try std.testing.expectEqual(@as(usize, 0), parsed.errors.len);
}

test "errors: truncated bus carries busvalue then busclose marks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // No trailing newline: the marks sit at the stall point on line 2. With a
    // newline the Spacing before PortRef eats it and both marks move to 3:1.
    const parsed = try translate.parseSource(allocator, 0, "input a\nand g(a=");
    try std.testing.expectEqual(@as(usize, 0), parsed.components.len);
    try std.testing.expectEqual(@as(usize, 2), parsed.errors.len);
    try std.testing.expectEqualStrings("expected a signal reference after '='", parsed.errors[0].message);
    try std.testing.expectEqualStrings("expected ')' to close the connection list", parsed.errors[1].message);
    for (parsed.errors) |mark| {
        try std.testing.expectEqual(@as(u32, 2), mark.span.start_line);
        try std.testing.expectEqual(@as(u32, 9), mark.span.start_col);
        try std.testing.expectEqual(@as(u32, 2), mark.span.end_line);
        try std.testing.expectEqual(@as(u32, 9), mark.span.end_col);
    }
}

test "edge: whitespace-only .circ is InvalidProgram" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // The root payload is a bare String when nothing but Spacing matched.
    const parsed = translate.parseSource(allocator, 0, "\n  \n");
    try std.testing.expectError(error.InvalidProgram, parsed);
}

test "recovery: busvalue_eof fixture has no trailing newline" {
    // Editors add a final newline silently; with one, both marks in the
    // golden move from 2:9 to 3:1 (see recovery_busvalue_newline).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = try std.fs.cwd().readFileAlloc(allocator, "tests/fixtures/circuits/recovery_busvalue_eof.circ", 1024);
    try std.testing.expectEqual(@as(u8, '='), source[source.len - 1]);
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

test "width: identifier inside brackets binds to a parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try translate.parseSource(allocator, 0, "input<W> a\nand[W] g(a=a)\n");
    try std.testing.expectEqual(@as(usize, 1), parsed.components.len);
    const width = parsed.components[0].type_name.width orelse return error.MissingWidth;
    try std.testing.expectEqualStrings("W", width.parameter);
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

test "param: empty parameter introduction is not interpreted" {
    try expectNoInputDecl("input<> a\n");
}

test "param: literal in parameter introduction is not interpreted" {
    try expectNoInputDecl("input<4> a\n");
}

test "callwidths: empty brackets do not produce a component" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = translate.parseSource(allocator, 0, "input a\nsomething p[](in=a)\n") catch return;
    // Either the call-site bracket was rejected (no component) or the bracket
    // was simply skipped (component exists but width_args is empty). Neither
    // case admits the bogus empty bracket as a meaningful width_args list.
    for (parsed.components) |comp| {
        try std.testing.expectEqual(@as(usize, 0), comp.width_args.len);
    }
}

test "param: parameters appear in source order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try translate.parseSource(allocator, 0, "input<W, X, Y> a\n");
    try std.testing.expectEqual(@as(usize, 1), parsed.inputs.len);
    const params = parsed.inputs[0].parameters;
    try std.testing.expectEqual(@as(usize, 3), params.len);
    try std.testing.expectEqualStrings("W", params[0].text);
    try std.testing.expectEqualStrings("X", params[1].text);
    try std.testing.expectEqualStrings("Y", params[2].text);
}

test "callwidths: mixed literal and identifier args populate WidthSpec variants" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try translate.parseSource(allocator, 0, "input<W> a\nsomething inst[4, W](in=a)\n");
    try std.testing.expectEqual(@as(usize, 1), parsed.components.len);
    const args = parsed.components[0].width_args;
    try std.testing.expectEqual(@as(usize, 2), args.len);
    try std.testing.expectEqual(@as(u8, 4), args[0].literal);
    try std.testing.expectEqualStrings("W", args[1].parameter);
}

// PEG with `IndexedRef <- BaseRef #Subscript?` makes the `[...]` after a port
// name lexified — `a[2]` parses, `a [2]` does not.
fn outputSourceTag(source: anytype) []const u8 {
    return @tagName(source);
}

test "subscript: name[i] parses as indexed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try translate.parseSource(allocator, 0, "input a\noutput o(in=a[2])\n");
    try std.testing.expectEqual(@as(usize, 1), parsed.outputs.len);
    try std.testing.expectEqualStrings("indexed", @tagName(parsed.outputs[0].value));
    try std.testing.expectEqual(@as(u8, 2), parsed.outputs[0].value.indexed.bit);
}

test "subscript: name [i] with space parses as indexed (langlang lexification limitation)" {
    // The S3.3 issue pinned `IndexedRef <- BaseRef #Subscript?` with the
    // intent that whitespace would defeat the subscript binding. langlang
    // v0.0.12's grammar compiler silently ignores the `#` lexification
    // operator and injects automatic Spacing between every sequence element,
    // so `a [2]` parses identically to `a[2]`. The expectation is captured
    // here so the gap is explicit if/when langlang gains real lexification.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try translate.parseSource(allocator, 0, "input a\noutput o(in=a [2])\n");
    try std.testing.expectEqualStrings("indexed", @tagName(parsed.outputs[0].value));
}

test "subscript: slice vs index disambiguation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try translate.parseSource(allocator, 0,
        "input a\noutput o1(in=a[2])\noutput o2(in=a[2..5])\n");
    try std.testing.expectEqual(@as(usize, 2), parsed.outputs.len);
    try std.testing.expectEqualStrings("indexed", @tagName(parsed.outputs[0].value));
    try std.testing.expectEqualStrings("sliced", @tagName(parsed.outputs[1].value));
    try std.testing.expectEqual(@as(u8, 2), parsed.outputs[1].value.sliced.lo);
    try std.testing.expectEqual(@as(u8, 5), parsed.outputs[1].value.sliced.hi);
}

test "concat: empty braces fail to parse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = translate.parseSource(allocator, 0, "input a\noutput o(in={})\n") catch return;
    for (parsed.outputs) |out| {
        try std.testing.expect(out.value != .concat);
    }
}

test "slice: open-ended bounds fail to parse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const a = translate.parseSource(allocator, 0, "input x\noutput o(in=x[1..])\n") catch return;
    for (a.outputs) |out| try std.testing.expect(out.value != .sliced);
    const b = translate.parseSource(allocator, 0, "input x\noutput o(in=x[..2])\n") catch return;
    for (b.outputs) |out| try std.testing.expect(out.value != .sliced);
}

test "concat: parts preserve source order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try translate.parseSource(allocator, 0,
        "input a, b, c\noutput o(in={a, b, c})\n");
    try std.testing.expectEqual(@as(usize, 1), parsed.outputs.len);
    try std.testing.expectEqualStrings("concat", @tagName(parsed.outputs[0].value));
    const parts = parsed.outputs[0].value.concat.parts;
    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("a", parts[0].named.target.text);
    try std.testing.expectEqualStrings("b", parts[1].named.target.text);
    try std.testing.expectEqualStrings("c", parts[2].named.target.text);
}

test "concat: nested produces nested AST (not flattened)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try translate.parseSource(allocator, 0,
        "input a, b, c, d\noutput o(in={a, {b, c}, d})\n");
    const outer = parsed.outputs[0].value.concat;
    try std.testing.expectEqual(@as(usize, 3), outer.parts.len);
    try std.testing.expectEqualStrings("concat", @tagName(outer.parts[1]));
    try std.testing.expectEqual(@as(usize, 2), outer.parts[1].concat.parts.len);
}

test "slice: half-open bounds for a[0..4] are lo=0, hi=4" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try translate.parseSource(allocator, 0, "input a\noutput o(in=a[0..4])\n");
    const s = parsed.outputs[0].value.sliced;
    try std.testing.expectEqual(@as(u8, 0), s.lo);
    try std.testing.expectEqual(@as(u8, 4), s.hi);
}
