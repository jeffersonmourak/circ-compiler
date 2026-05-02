const std = @import("std");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const validator_run_project = @import("validator_run_project");
const diagnostics = @import("diagnostics");
const emit_main = @import("emit_main");
const emit_project = @import("emit_project");
const ir = @import("ir_types");
const wasm_run = @import("wasm_run");

const Assignment = struct {
    name: []const u8,
    value: i32,
};

const Step = struct {
    inputs: []Assignment,
    outputs: []Assignment,
};

const Fixture = struct {
    name: []const u8,
    root_path: []const u8,
    source_name: []const u8,
    spec_path: []const u8,
};

fn hasHardErrors(diagnostic_list: []const diagnostics.Diagnostic) bool {
    for (diagnostic_list) |diagnostic| {
        if (diagnostic.level == .err) return true;
    }
    return false;
}

fn parseAssignment(token: []const u8) !Assignment {
    const eq_idx = std.mem.indexOfScalar(u8, token, '=') orelse return error.InvalidAssignment;
    return .{
        .name = token[0..eq_idx],
        .value = try std.fmt.parseInt(i32, token[eq_idx + 1 ..], 10),
    };
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

fn parseSteps(allocator: std.mem.Allocator, text: []const u8) ![]Step {
    var steps: std.ArrayList(Step) = .{};
    defer steps.deinit(allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const arrow = std.mem.indexOf(u8, line, "=>") orelse return error.InvalidBehaviorLine;
        try steps.append(allocator, .{
            .inputs = try parseSide(allocator, std.mem.trim(u8, line[0..arrow], " \t")),
            .outputs = try parseSide(allocator, std.mem.trim(u8, line[arrow + 2 ..], " \t")),
        });
    }
    return steps.toOwnedSlice(allocator);
}

fn rootInputGlobalId(root_module: *const ir.Module, layout: *const emit_project.ProjectLayout, name: []const u8) ?u32 {
    for (root_module.inputs, 0..) |pin, idx| {
        if (std.mem.eql(u8, pin.name, name)) return layout.root_input_global_ids[idx];
    }
    return null;
}

fn rootOutputGlobalId(root_module: *const ir.Module, layout: *const emit_project.ProjectLayout, name: []const u8) ?u32 {
    var idx: usize = 0;
    for (root_module.outputs) |pin| {
        if (idx >= layout.root_output_global_ids.len) break;
        if (std.mem.eql(u8, pin.name, name)) return layout.root_output_global_ids[idx];
        idx += 1;
    }
    return null;
}

fn buildScript(
    allocator: std.mem.Allocator,
    root_module: *const ir.Module,
    layout: *const emit_project.ProjectLayout,
    steps: []const Step,
) !struct { script: []u8, expected_stdout: []u8 } {
    var script: std.ArrayList(u8) = .{};
    errdefer script.deinit(allocator);
    var expected: std.ArrayList(u8) = .{};
    errdefer expected.deinit(allocator);

    const sw = script.writer(allocator);
    const ew = expected.writer(allocator);

    for (steps, 0..) |step, idx| {
        for (step.inputs) |input| {
            const id = rootInputGlobalId(root_module, layout, input.name) orelse return error.UnknownInputName;
            try sw.print("wasm.setPin({d}, {d});\n", .{ id, input.value });
        }
        try sw.writeAll("wasm.run();\n");
        try sw.print("const outParts{d} = [];\n", .{idx});
        var first = true;
        for (step.outputs) |output| {
            const id = rootOutputGlobalId(root_module, layout, output.name) orelse return error.UnknownOutputName;
            try sw.print("outParts{d}.push(\"{s}=\" + wasm.getOutputState({d}));\n", .{ idx, output.name, id });
            if (!first) try ew.writeAll(" ");
            first = false;
            try ew.print("{s}={d}", .{ output.name, output.value });
        }
        try sw.print("console.log(outParts{d}.join(\" \"));\n", .{idx});
        try ew.writeAll("\n");
    }

    return .{
        .script = try script.toOwnedSlice(allocator),
        .expected_stdout = try expected.toOwnedSlice(allocator),
    };
}

fn runFixture(fixture: Fixture) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const scan_result = try scan_imports.scanProjectImports(allocator, fixture.root_path);
    if (hasHardErrors(scan_result.diagnostics.items)) return error.InvalidFixtureScan;

    const cycle_result = try import_cycle.analyzeImports(allocator, scan_result.file_paths, scan_result.import_table);
    if (hasHardErrors(cycle_result.diagnostics.items)) return error.InvalidFixtureCycle;

    const project = try resolve_bodies.resolveBodies(
        allocator,
        scan_result.file_paths,
        scan_result.import_table,
        cycle_result.topo_order,
    );

    var diags = try validator_run_project.run(allocator, &project);
    defer diags.deinit(allocator);
    if (hasHardErrors(diags.items)) {
        std.debug.print("project validation failed for {s}:\n", .{fixture.name});
        for (diags.items) |d| std.debug.print("  {s}\n", .{d.message});
        return error.InvalidFixtureValidation;
    }

    var layout = try emit_project.computeLayout(allocator, &project);
    defer layout.deinit();

    const root_module = &project.files[project.root_file_id.value];
    const expected_text = try std.fs.cwd().readFileAlloc(allocator, fixture.spec_path, 1024 * 1024);
    const steps = try parseSteps(allocator, expected_text);
    const script_and_expected = try buildScript(allocator, root_module, &layout, steps);

    const emitted = try emit_main.emitProjectSource(allocator, &project, .{
        .source_name = fixture.source_name,
        .compile_timestamp = "2026-05-01T22:00:00Z",
        .compiler_version = "circ-renderer-z/dev",
    });

    const stdout = try wasm_run.compileAndRun(allocator, emitted, script_and_expected.script);
    try std.testing.expectEqualStrings(script_and_expected.expected_stdout, stdout);
}

test "project behavior: passthrough_chain" {
    try runFixture(.{
        .name = "passthrough_chain",
        .root_path = "tests/fixtures/projects/passthrough_chain/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/passthrough_chain.txt",
    });
}

test "project behavior: and_pair" {
    try runFixture(.{
        .name = "and_pair",
        .root_path = "tests/fixtures/projects/and_pair/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/and_pair.txt",
    });
}

test "project behavior: nested_invert" {
    try runFixture(.{
        .name = "nested_invert",
        .root_path = "tests/fixtures/projects/nested_invert/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/nested_invert.txt",
    });
}

test "project behavior: diamond shared base" {
    try runFixture(.{
        .name = "diamond",
        .root_path = "tests/fixtures/projects/diamond/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/diamond.txt",
    });
}

test "project behavior: deep_chain" {
    try runFixture(.{
        .name = "deep_chain",
        .root_path = "tests/fixtures/projects/deep_chain/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/deep_chain.txt",
    });
}

test "project behavior: same_name_half_adder" {
    try runFixture(.{
        .name = "same_name_half_adder",
        .root_path = "tests/fixtures/projects/same_name_half_adder/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/same_name_half_adder.txt",
    });
}

const builtin_truth_fixtures = [_]Fixture{
    .{
        .name = "builtin_or",
        .root_path = "tests/fixtures/circuits/builtin_or.circ",
        .source_name = "builtin_or.circ",
        .spec_path = "tests/fixtures/expected-wasm/builtin_or.txt",
    },
    .{
        .name = "builtin_nand",
        .root_path = "tests/fixtures/circuits/builtin_nand.circ",
        .source_name = "builtin_nand.circ",
        .spec_path = "tests/fixtures/expected-wasm/builtin_nand.txt",
    },
    .{
        .name = "builtin_nor",
        .root_path = "tests/fixtures/circuits/builtin_nor.circ",
        .source_name = "builtin_nor.circ",
        .spec_path = "tests/fixtures/expected-wasm/builtin_nor.txt",
    },
    .{
        .name = "builtin_xor",
        .root_path = "tests/fixtures/circuits/builtin_xor.circ",
        .source_name = "builtin_xor.circ",
        .spec_path = "tests/fixtures/expected-wasm/builtin_xor.txt",
    },
    .{
        .name = "builtin_xnor",
        .root_path = "tests/fixtures/circuits/builtin_xnor.circ",
        .source_name = "builtin_xnor.circ",
        .spec_path = "tests/fixtures/expected-wasm/builtin_xnor.txt",
    },
};

test "built-in macros: truth tables (or nand nor xor xnor)" {
    for (builtin_truth_fixtures) |fx| {
        try runFixture(fx);
    }
}

test "composition: full adder from built-in xor, and, or" {
    try runFixture(.{
        .name = "full_adder_from_builtins",
        .root_path = "tests/fixtures/circuits/full_adder_from_builtins.circ",
        .source_name = "full_adder_from_builtins.circ",
        .spec_path = "tests/fixtures/expected-wasm/full_adder_from_builtins.txt",
    });
}

test "composition: full adder from user half_adder plus xor, and, or macros" {
    try runFixture(.{
        .name = "full_adder_ha_or",
        .root_path = "tests/fixtures/projects/full_adder_ha_or/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/full_adder_ha_or.txt",
    });
}

test "Phase 9 edge: single built-in gate only (xor)" {
    try runFixture(.{
        .name = "edge_single_builtin",
        .root_path = "tests/fixtures/circuits/edge_single_builtin.circ",
        .source_name = "edge_single_builtin.circ",
        .spec_path = "tests/fixtures/expected-wasm/edge_single_builtin.txt",
    });
}

test "Phase 9 edge: deep sub-circuit import chain" {
    try runFixture(.{
        .name = "deep_subcircuit_chain",
        .root_path = "tests/fixtures/projects/deep_subcircuit_chain/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/deep_subcircuit_chain.txt",
    });
}

test "Phase 9 stress: deep hierarchy 256 leaf NOTs" {
    try runFixture(.{
        .name = "stress_deep_subcircuit",
        .root_path = "tests/fixtures/projects/stress_deep_subcircuit/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/stress_deep_subcircuit.txt",
    });
}

test "canonical: half adder project (sum, carry truth table)" {
    try runFixture(.{
        .name = "half_adder",
        .root_path = "tests/fixtures/projects/half_adder/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/half_adder.txt",
    });
}

test "canonical: full adder project (two half-adders + or)" {
    try runFixture(.{
        .name = "full_adder",
        .root_path = "tests/fixtures/projects/full_adder/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/full_adder.txt",
    });
}

test "canonical: 4-bit AND/OR network project" {
    try runFixture(.{
        .name = "and_or_network",
        .root_path = "tests/fixtures/projects/and_or_network/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/and_or_network.txt",
    });
}

