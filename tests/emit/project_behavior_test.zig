//! Emit-zig backend smoke (multi-file project path).
//!
//! Circuit *behavior* for the whole fixture corpus is covered cheaply by the
//! production path in tests/e2e/serializer_fixtures_test.zig (prebuilt runtime
//! + topology sections, no per-fixture compile). This file's only remaining job
//! is to guard that the experimental `--emit-zig` project backend
//! (emit_project.emitProjectSource) still emits runnable wasm, so it keeps a
//! minimal set of fixtures and is wired into the opt-in `test-emit` build step
//! rather than the default `test` step. Each kept fixture triggers one nested
//! `zig build wasm` via wasm_run, so add new cases sparingly.
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
            const value: u64 = if (input.value == 1) 1 else 0;
            const defined: u64 = if (input.value == 2) 0 else 1;
            try sw.print("wasm.setPin({d}, {d}n, {d}n);\n", .{ id, value, defined });
        }
        try sw.writeAll("wasm.run();\n");
        try sw.print("const outParts{d} = [];\n", .{idx});
        var first = true;
        for (step.outputs) |output| {
            const id = rootOutputGlobalId(root_module, layout, output.name) orelse return error.UnknownOutputName;
            try sw.print(
                "outParts{d}.push(\"{s}=\" + ((wasm.getOutputDefined({d}) === 0n) ? 2 : (wasm.getOutputValue({d}) === 0n ? 0 : 1)));\n",
                .{ idx, output.name, id, id },
            );
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

    var resolver_diagnostics = diagnostics.initDiagnosticList();
    const project = try resolve_bodies.resolveBodies(
        allocator,
        scan_result.file_paths,
        scan_result.import_table,
        cycle_result.topo_order,
        &resolver_diagnostics,
    );
    if (hasHardErrors(resolver_diagnostics.items)) return error.InvalidFixtureResolve;

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
        .compiler_version = "circ-compiler/dev",
    });

    const stdout = try wasm_run.compileAndRun(allocator, emitted, script_and_expected.script);
    try std.testing.expectEqualStrings(script_and_expected.expected_stdout, stdout);
}

// Minimal emit-zig project smoke set. The full behavioral corpus runs on the
// production path in serializer_fixtures_test.zig; these two only prove the
// --emit-zig project backend still emits runnable wasm. `full_adder_from_builtins`
// exercises auto-imported builtins + sub-circuit flattening; `half_adder` is a
// canonical two-file project.
test "emit-zig smoke: full adder from built-in xor, and, or" {
    try runFixture(.{
        .name = "full_adder_from_builtins",
        .root_path = "tests/fixtures/circuits/full_adder_from_builtins.circ",
        .source_name = "full_adder_from_builtins.circ",
        .spec_path = "tests/fixtures/expected-wasm/full_adder_from_builtins.txt",
    });
}

test "emit-zig smoke: half adder project (sum, carry truth table)" {
    try runFixture(.{
        .name = "half_adder",
        .root_path = "tests/fixtures/projects/half_adder/root.circ",
        .source_name = "root.circ",
        .spec_path = "tests/fixtures/expected-wasm/projects/half_adder.txt",
    });
}
