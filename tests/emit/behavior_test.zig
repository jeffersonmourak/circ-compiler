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
            try script_writer.print("wasm.setPin({d}, {d});\n", .{ id, input.value });
        }
        try script_writer.writeAll("wasm.run();\n");
        try script_writer.print("const outParts{d} = [];\n", .{idx});
        var first = true;
        for (step.outputs) |output| {
            const id = outputId(module, output.name) orelse return error.UnknownOutputName;
            try script_writer.print("outParts{d}.push(\"{s}=\" + wasm.getOutputState({d}));\n", .{ idx, output.name, id });
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
        .compiler_version = "circ-renderer-z/dev",
    });

    const stdout = try wasm_run.compileAndRun(allocator, emitted_source, script_and_expected.script);
    try std.testing.expectEqualStrings(script_and_expected.expected_stdout, stdout);
}

test "behavior fixture: inverter" {
    try runBehaviorFixture(.{
        .source_path = "tests/fixtures/circuits/inverter.circ",
        .source_name = "inverter.circ",
        .expected_path = "tests/fixtures/expected-wasm/inverter.txt",
    });
}

test "behavior fixture: and gate" {
    try runBehaviorFixture(.{
        .source_path = "tests/fixtures/circuits/and_gate.circ",
        .source_name = "and_gate.circ",
        .expected_path = "tests/fixtures/expected-wasm/and_gate.txt",
    });
}

test "behavior fixture: and of not" {
    try runBehaviorFixture(.{
        .source_path = "tests/fixtures/circuits/and_of_not.circ",
        .source_name = "and_of_not.circ",
        .expected_path = "tests/fixtures/expected-wasm/and_of_not.txt",
    });
}

test "behavior fixture: chain" {
    try runBehaviorFixture(.{
        .source_path = "tests/fixtures/circuits/chain.circ",
        .source_name = "chain.circ",
        .expected_path = "tests/fixtures/expected-wasm/chain.txt",
    });
}

test "behavior fixture: unused input" {
    try runBehaviorFixture(.{
        .source_path = "tests/fixtures/circuits/unused_input.circ",
        .source_name = "unused_input.circ",
        .expected_path = "tests/fixtures/expected-wasm/unused_input.txt",
    });
}

const edge_behavior_fixtures = [_]BehaviorFixture{
    .{
        .source_path = "tests/fixtures/circuits/edge_empty_circuit.circ",
        .source_name = "edge_empty_circuit.circ",
        .expected_path = "tests/fixtures/expected-wasm/edge_empty_circuit.txt",
    },
    .{
        .source_path = "tests/fixtures/circuits/edge_single_component.circ",
        .source_name = "edge_single_component.circ",
        .expected_path = "tests/fixtures/expected-wasm/edge_single_component.txt",
    },
    .{
        .source_path = "tests/fixtures/circuits/edge_deep_anonymous.circ",
        .source_name = "edge_deep_anonymous.circ",
        .expected_path = "tests/fixtures/expected-wasm/edge_deep_anonymous.txt",
    },
    .{
        .source_path = "tests/fixtures/circuits/edge_wide_fanin.circ",
        .source_name = "edge_wide_fanin.circ",
        .expected_path = "tests/fixtures/expected-wasm/edge_wide_fanin.txt",
    },
    .{
        .source_path = "tests/fixtures/circuits/edge_wide_fanout.circ",
        .source_name = "edge_wide_fanout.circ",
        .expected_path = "tests/fixtures/expected-wasm/edge_wide_fanout.txt",
    },
};

test "Phase 9 edge: single-file wasm fixtures" {
    for (edge_behavior_fixtures) |fx| {
        try runBehaviorFixture(fx);
    }
}

const stress_behavior_fixtures = [_]BehaviorFixture{
    .{
        .source_path = "tests/fixtures/circuits/stress_chain_100.circ",
        .source_name = "stress_chain_100.circ",
        .expected_path = "tests/fixtures/expected-wasm/stress_chain_100.txt",
    },
    .{
        .source_path = "tests/fixtures/circuits/stress_grid_10x10.circ",
        .source_name = "stress_grid_10x10.circ",
        .expected_path = "tests/fixtures/expected-wasm/stress_grid_10x10.txt",
    },
};

const regression_behavior_fixtures = [_]BehaviorFixture{
    .{
        .source_path = "tests/fixtures/circuits/regression_led_out_drives_gate.circ",
        .source_name = "regression_led_out_drives_gate.circ",
        .expected_path = "tests/fixtures/expected-wasm/regression_led_out_drives_gate.txt",
    },
};

test "Phase 9 regression: single-file wasm fixtures" {
    for (regression_behavior_fixtures) |fx| {
        try runBehaviorFixture(fx);
    }
}

test "Phase 9 stress: large single-file wasm fixtures" {
    for (stress_behavior_fixtures) |fx| {
        try runBehaviorFixture(fx);
    }
}
