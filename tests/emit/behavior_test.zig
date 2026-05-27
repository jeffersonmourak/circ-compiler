//! Emit-zig backend smoke (single-module path).
//!
//! Circuit *behavior* for the whole fixture corpus is covered cheaply by the
//! production path in tests/e2e/serializer_fixtures_test.zig (prebuilt runtime
//! + topology sections, no per-fixture compile). This file's only remaining job
//! is to guard that the experimental `--emit-zig` standalone-source backend
//! still emits runnable wasm, so it keeps a minimal set of fixtures and is wired
//! into the opt-in `test-emit` build step rather than the default `test` step.
//! Each kept fixture triggers one nested `zig build wasm` via wasm_run, so add
//! new cases sparingly.
const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const validator_run = @import("validator_run");
const diagnostics = @import("diagnostics");
const emit_main = @import("emit_main");
const wasm_run = @import("wasm_run");

const Assignment = struct {
    name: []const u8,
    value: i32,
};

const Step = struct {
    inputs: []Assignment,
    outputs: []Assignment,
};

const BehaviorFixture = struct {
    source_path: []const u8,
    source_name: []const u8,
    expected_path: []const u8,
};

fn hasHardErrors(diagnostic_list: []const diagnostics.Diagnostic) bool {
    for (diagnostic_list) |diagnostic| {
        if (diagnostic.level == .err) return true;
    }
    return false;
}

fn parseAssignment(token: []const u8) !Assignment {
    const eq_idx = std.mem.indexOfScalar(u8, token, '=') orelse return error.InvalidAssignment;
    const name = token[0..eq_idx];
    const value_text = token[eq_idx + 1 ..];
    const value = try std.fmt.parseInt(i32, value_text, 10);
    return .{ .name = name, .value = value };
}

fn parseSide(allocator: std.mem.Allocator, text: []const u8) ![]Assignment {
    var assignments: std.ArrayList(Assignment) = .{};
    defer assignments.deinit(allocator);
    var iter = std.mem.tokenizeScalar(u8, text, ' ');
    while (iter.next()) |token| {
        if (token.len == 0) continue;
        try assignments.append(allocator, try parseAssignment(token));
    }
    return assignments.toOwnedSlice(allocator);
}

fn parseBehaviorSteps(allocator: std.mem.Allocator, text: []const u8) ![]Step {
    var steps: std.ArrayList(Step) = .{};
    defer steps.deinit(allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const arrow_idx = std.mem.indexOf(u8, line, "=>") orelse return error.InvalidBehaviorLine;
        const left = std.mem.trim(u8, line[0..arrow_idx], " \t");
        const right = std.mem.trim(u8, line[arrow_idx + 2 ..], " \t");
        try steps.append(allocator, .{
            .inputs = try parseSide(allocator, left),
            .outputs = try parseSide(allocator, right),
        });
    }
    return steps.toOwnedSlice(allocator);
}

fn inputId(module: anytype, name: []const u8) ?u32 {
    for (module.inputs) |input_pin| {
        if (std.mem.eql(u8, input_pin.name, name)) return input_pin.component.value;
    }
    return null;
}

fn outputId(module: anytype, name: []const u8) ?u32 {
    for (module.outputs) |output_pin| {
        if (std.mem.eql(u8, output_pin.name, name)) return output_pin.driver.component.value;
    }
    return null;
}

fn buildScriptAndExpected(
    allocator: std.mem.Allocator,
    module: anytype,
    steps: []const Step,
) !struct { script: []u8, expected_stdout: []u8 } {
    var script: std.ArrayList(u8) = .{};
    errdefer script.deinit(allocator);
    var expected: std.ArrayList(u8) = .{};
    errdefer expected.deinit(allocator);

    const script_writer = script.writer(allocator);
    const expected_writer = expected.writer(allocator);

    for (steps, 0..) |step, idx| {
        for (step.inputs) |input| {
            const id = inputId(module, input.name) orelse return error.UnknownInputName;
            // Translate the legacy scalar int encoding (0=low, 1=high, 2=undef)
            // into the post-S9.1 (value, defined) BigInt pair: low → (0, 1),
            // high → (1, 1), undefined → (0, 0). Widths >1 will need a wider
            // input-value shape; not in this slice's scope.
            const value: u64 = if (input.value == 1) 1 else 0;
            const defined: u64 = if (input.value == 2) 0 else 1;
            try script_writer.print("wasm.setPin({d}, {d}n, {d}n);\n", .{ id, value, defined });
        }
        try script_writer.writeAll("wasm.run();\n");
        try script_writer.print("const outParts{d} = [];\n", .{idx});
        var first = true;
        for (step.outputs) |output| {
            const id = outputId(module, output.name) orelse return error.UnknownOutputName;
            // Read back via the paired getters and project to the legacy
            // int encoding (0=low, 1=high, 2=undefined) so existing scalar
            // .txt fixtures don't need to change.
            try script_writer.print(
                "outParts{d}.push(\"{s}=\" + ((wasm.getOutputDefined({d}) === 0n) ? 2 : (wasm.getOutputValue({d}) === 0n ? 0 : 1)));\n",
                .{ idx, output.name, id, id },
            );
            if (!first) try expected_writer.writeAll(" ");
            first = false;
            try expected_writer.print("{s}={d}", .{ output.name, output.value });
        }
        try script_writer.print("console.log(outParts{d}.join(\" \"));\n", .{idx});
        try expected_writer.writeAll("\n");
    }

    return .{
        .script = try script.toOwnedSlice(allocator),
        .expected_stdout = try expected.toOwnedSlice(allocator),
    };
}

fn runBehaviorFixture(fixture: BehaviorFixture) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = try std.fs.cwd().readFileAlloc(allocator, fixture.source_path, 1024 * 1024);
    const ast_file = try translate.parseSource(allocator, 0, source);
    const ir_module = try resolver.resolve(allocator, ast_file, 0);
    var diagnostic_list = try validator_run.run(allocator, &ir_module);
    defer diagnostic_list.deinit(allocator);
    if (hasHardErrors(diagnostic_list.items)) return error.InvalidFixtureForEmission;

    const expected_text = try std.fs.cwd().readFileAlloc(allocator, fixture.expected_path, 1024 * 1024);
    const steps = try parseBehaviorSteps(allocator, expected_text);
    const script_and_expected = try buildScriptAndExpected(allocator, &ir_module, steps);

    const emitted_source = try emit_main.emitModuleSource(allocator, &ir_module, .{
        .source_name = fixture.source_name,
        .compile_timestamp = "2026-05-01T22:00:00Z",
        .compiler_version = "circ-compiler/dev",
    });

    const stdout = try wasm_run.compileAndRun(allocator, emitted_source, script_and_expected.script);
    try std.testing.expectEqualStrings(script_and_expected.expected_stdout, stdout);
}

// Minimal emit-zig single-module smoke set. The full behavioral corpus runs on
// the production path in serializer_fixtures_test.zig; these two only prove the
// --emit-zig backend still emits runnable wasm. `inverter` is the smallest
// circuit (one NOT gate); `chain` exercises multi-stage wire propagation.
test "emit-zig smoke: inverter" {
    try runBehaviorFixture(.{
        .source_path = "tests/fixtures/circuits/inverter.circ",
        .source_name = "inverter.circ",
        .expected_path = "tests/fixtures/expected-wasm/inverter.txt",
    });
}

test "emit-zig smoke: chain" {
    try runBehaviorFixture(.{
        .source_path = "tests/fixtures/circuits/chain.circ",
        .source_name = "chain.circ",
        .expected_path = "tests/fixtures/expected-wasm/chain.txt",
    });
}
