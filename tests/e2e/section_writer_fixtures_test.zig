const std = @import("std");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const validator_run_project = @import("validator_run_project");
const diagnostics = @import("diagnostics");
const serializer = @import("serializer");
const section_writer = @import("section_writer");
const runtime_embed = @import("runtime_embed");

const Fixture = struct {
    root_path: []const u8,
    spec_path: []const u8,
};

const Assignment = struct {
    name: []const u8,
    value: i32,
};

const Step = struct {
    inputs: []Assignment,
    outputs: []Assignment,
};

fn hasHardErrors(diags: []const diagnostics.Diagnostic) bool {
    for (diags) |d| {
        if (d.level == .err) return true;
    }
    return false;
}

fn parseAssignment(token: []const u8) !Assignment {
    const eq = std.mem.indexOfScalar(u8, token, '=') orelse return error.InvalidAssignment;
    return .{
        .name = token[0..eq],
        .value = try std.fmt.parseInt(i32, token[eq + 1 ..], 10),
    };
}

fn parseSide(allocator: std.mem.Allocator, text: []const u8) ![]Assignment {
    var list: std.ArrayList(Assignment) = .{};
    var it = std.mem.tokenizeScalar(u8, text, ' ');
    while (it.next()) |tok| {
        if (tok.len == 0) continue;
        try list.append(allocator, try parseAssignment(tok));
    }
    return list.toOwnedSlice(allocator);
}

fn parseSteps(allocator: std.mem.Allocator, text: []const u8) ![]Step {
    var steps: std.ArrayList(Step) = .{};
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

fn pinId(mappings: []const serializer.PinMapping, name: []const u8) ?u32 {
    for (mappings) |m| {
        if (std.mem.eql(u8, m.name, name)) return m.global_id;
    }
    return null;
}

fn checkNodeAvailable(allocator: std.mem.Allocator) !bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", "--version" },
    }) catch |err| {
        if (err == error.FileNotFound) return false;
        return err;
    };
    return result.term == .Exited and result.term.Exited == 0;
}

/// Builds the combined WASM using section_writer.combine and returns the bytes.
fn buildCombined(allocator: std.mem.Allocator, topology_payload: []const u8) ![]u8 {
    return section_writer.combine(allocator, runtime_embed.runtime_wasm, topology_payload);
}

/// Runs only WebAssembly.validate() on the combined WASM for the fixture.
fn runValidateOnly(fixture: Fixture, allocator: std.mem.Allocator) !void {
    const scan_result = try scan_imports.scanProjectImports(allocator, fixture.root_path);
    if (hasHardErrors(scan_result.diagnostics.items)) return error.ScanFailed;

    const cycle_result = try import_cycle.analyzeImports(
        allocator,
        scan_result.file_paths,
        scan_result.import_table,
    );
    if (hasHardErrors(cycle_result.diagnostics.items)) return error.CycleFailed;

    const project = try resolve_bodies.resolveBodies(
        allocator,
        scan_result.file_paths,
        scan_result.import_table,
        cycle_result.topo_order,
    );

    var diags = try validator_run_project.run(allocator, &project);
    defer diags.deinit(allocator);
    if (hasHardErrors(diags.items)) return error.ValidationFailed;

    var topo = try serializer.serializeProjectFull(allocator, &project);
    defer topo.deinit(allocator);

    const combined = try buildCombined(allocator, topo.payload);
    defer allocator.free(combined);

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    try tmp_dir.dir.writeFile(.{ .sub_path = "combined.wasm", .data = combined });
    const wasm_path = try tmp_dir.dir.realpathAlloc(allocator, "combined.wasm");

    const script =
        \\const fs = require('fs');
        \\const wasmBytes = fs.readFileSync(process.argv[2]);
        \\const valid = WebAssembly.validate(wasmBytes);
        \\if (!valid) { console.error('WebAssembly.validate() failed'); process.exit(1); }
        \\console.log("VALID");
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "runner.js", .data = script });
    const script_path = try tmp_dir.dir.realpathAlloc(allocator, "runner.js");

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", script_path, wasm_path },
    });

    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("validate failed for {s}\nSTDOUT:\n{s}\nSTDERR:\n{s}\n", .{
            fixture.root_path, result.stdout, result.stderr,
        });
        return error.ValidateFailed;
    }
    try std.testing.expectEqualStrings("VALID\n", result.stdout);
}

/// Runs the full pipeline: serialize → combine → Node behavioral test.
/// Also includes WebAssembly.validate() at the start of the Node script.
fn runFixture(fixture: Fixture, allocator: std.mem.Allocator) !void {
    const scan_result = try scan_imports.scanProjectImports(allocator, fixture.root_path);
    if (hasHardErrors(scan_result.diagnostics.items)) return error.ScanFailed;

    const cycle_result = try import_cycle.analyzeImports(
        allocator,
        scan_result.file_paths,
        scan_result.import_table,
    );
    if (hasHardErrors(cycle_result.diagnostics.items)) return error.CycleFailed;

    const project = try resolve_bodies.resolveBodies(
        allocator,
        scan_result.file_paths,
        scan_result.import_table,
        cycle_result.topo_order,
    );

    var diags = try validator_run_project.run(allocator, &project);
    defer diags.deinit(allocator);
    if (hasHardErrors(diags.items)) return error.ValidationFailed;

    var topo = try serializer.serializeProjectFull(allocator, &project);
    defer topo.deinit(allocator);

    const combined = try buildCombined(allocator, topo.payload);
    defer allocator.free(combined);

    const spec_text = try std.fs.cwd().readFileAlloc(allocator, fixture.spec_path, 4 * 1024 * 1024);
    const steps = try parseSteps(allocator, spec_text);

    var script: std.ArrayList(u8) = .{};
    const w = script.writer(allocator);
    try w.writeAll(
        \\const fs = require('fs');
        \\const wasmBytes = fs.readFileSync(process.argv[2]);
        \\if (!WebAssembly.validate(wasmBytes)) throw new Error('WebAssembly.validate() failed');
        \\(async () => {
        \\    const mod = await WebAssembly.compile(wasmBytes);
        \\    const instance = await WebAssembly.instantiate(mod, { env: {
        \\        print: () => {}, printFmt: () => {}, flushBuffer: () => {},
        \\        _log: () => {}, _log_flush: () => {}, _log_set_name: () => {},
        \\        debugEnabled: () => 0, onDebugLog: () => {}
        \\    } });
        \\    const topoSections = WebAssembly.Module.customSections(mod, 'circ.topology');
        \\    if (topoSections.length === 0) throw new Error('No circ.topology section');
        \\    const topoBytes = new Uint8Array(topoSections[0]);
        \\    const ptr = instance.exports.topology_alloc(topoBytes.length);
        \\    new Uint8Array(instance.exports.memory.buffer).set(topoBytes, ptr);
        \\    instance.exports.init();
        \\
    );

    var expected: std.ArrayList(u8) = .{};
    const ew = expected.writer(allocator);

    for (steps, 0..) |step, idx| {
        for (step.inputs) |inp| {
            const id = pinId(topo.input_ids, inp.name) orelse {
                std.debug.print("Unknown input pin '{s}' in fixture {s}\n", .{ inp.name, fixture.root_path });
                return error.UnknownInputPin;
            };
            try w.print("    instance.exports.setPin({d}, {d});\n", .{ id, inp.value });
        }
        try w.writeAll("    instance.exports.run();\n");
        try w.print("    const p{d} = [];\n", .{idx});
        var first = true;
        for (step.outputs) |out| {
            const id = pinId(topo.output_ids, out.name) orelse {
                std.debug.print("Unknown output pin '{s}' in fixture {s}\n", .{ out.name, fixture.root_path });
                return error.UnknownOutputPin;
            };
            try w.print("    p{d}.push('{s}=' + instance.exports.getOutputState({d}));\n", .{ idx, out.name, id });
            if (!first) try ew.writeAll(" ");
            first = false;
            try ew.print("{s}={d}", .{ out.name, out.value });
        }
        try w.print("    console.log(p{d}.join(' '));\n", .{idx});
        try ew.writeAll("\n");
    }
    try w.writeAll("})().catch(e => { console.error(e); process.exit(1); });\n");

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    try tmp_dir.dir.writeFile(.{ .sub_path = "combined.wasm", .data = combined });
    try tmp_dir.dir.writeFile(.{ .sub_path = "runner.js", .data = script.items });

    const wasm_path = try tmp_dir.dir.realpathAlloc(allocator, "combined.wasm");
    const script_path = try tmp_dir.dir.realpathAlloc(allocator, "runner.js");

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", script_path, wasm_path },
    });

    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("Node failed for {s}\nSTDOUT:\n{s}\nSTDERR:\n{s}\n", .{
            fixture.root_path, result.stdout, result.stderr,
        });
        return error.NodeFailed;
    }
    try std.testing.expectEqualStrings(expected.items, result.stdout);
}

const all_fixtures = circuit_fixtures ++ project_fixtures;

const circuit_fixtures = [_]Fixture{
    .{ .root_path = "tests/fixtures/circuits/inverter.circ", .spec_path = "tests/fixtures/expected-wasm/inverter.txt" },
    .{ .root_path = "tests/fixtures/circuits/and_gate.circ", .spec_path = "tests/fixtures/expected-wasm/and_gate.txt" },
    .{ .root_path = "tests/fixtures/circuits/and_of_not.circ", .spec_path = "tests/fixtures/expected-wasm/and_of_not.txt" },
    .{ .root_path = "tests/fixtures/circuits/chain.circ", .spec_path = "tests/fixtures/expected-wasm/chain.txt" },
    .{ .root_path = "tests/fixtures/circuits/unused_input.circ", .spec_path = "tests/fixtures/expected-wasm/unused_input.txt" },
    .{ .root_path = "tests/fixtures/circuits/edge_empty_circuit.circ", .spec_path = "tests/fixtures/expected-wasm/edge_empty_circuit.txt" },
    .{ .root_path = "tests/fixtures/circuits/edge_single_component.circ", .spec_path = "tests/fixtures/expected-wasm/edge_single_component.txt" },
    .{ .root_path = "tests/fixtures/circuits/edge_deep_anonymous.circ", .spec_path = "tests/fixtures/expected-wasm/edge_deep_anonymous.txt" },
    .{ .root_path = "tests/fixtures/circuits/edge_wide_fanin.circ", .spec_path = "tests/fixtures/expected-wasm/edge_wide_fanin.txt" },
    .{ .root_path = "tests/fixtures/circuits/edge_wide_fanout.circ", .spec_path = "tests/fixtures/expected-wasm/edge_wide_fanout.txt" },
    .{ .root_path = "tests/fixtures/circuits/edge_single_builtin.circ", .spec_path = "tests/fixtures/expected-wasm/edge_single_builtin.txt" },
    .{ .root_path = "tests/fixtures/circuits/full_adder_from_builtins.circ", .spec_path = "tests/fixtures/expected-wasm/full_adder_from_builtins.txt" },
    .{ .root_path = "tests/fixtures/circuits/builtin_or.circ", .spec_path = "tests/fixtures/expected-wasm/builtin_or.txt" },
    .{ .root_path = "tests/fixtures/circuits/builtin_nand.circ", .spec_path = "tests/fixtures/expected-wasm/builtin_nand.txt" },
    .{ .root_path = "tests/fixtures/circuits/builtin_nor.circ", .spec_path = "tests/fixtures/expected-wasm/builtin_nor.txt" },
    .{ .root_path = "tests/fixtures/circuits/builtin_xor.circ", .spec_path = "tests/fixtures/expected-wasm/builtin_xor.txt" },
    .{ .root_path = "tests/fixtures/circuits/builtin_xnor.circ", .spec_path = "tests/fixtures/expected-wasm/builtin_xnor.txt" },
    .{ .root_path = "tests/fixtures/circuits/regression_led_out_drives_gate.circ", .spec_path = "tests/fixtures/expected-wasm/regression_led_out_drives_gate.txt" },
    .{ .root_path = "tests/fixtures/circuits/stress_chain_100.circ", .spec_path = "tests/fixtures/expected-wasm/stress_chain_100.txt" },
    .{ .root_path = "tests/fixtures/circuits/stress_grid_10x10.circ", .spec_path = "tests/fixtures/expected-wasm/stress_grid_10x10.txt" },
};

const project_fixtures = [_]Fixture{
    .{ .root_path = "tests/fixtures/projects/half_adder/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/half_adder.txt" },
    .{ .root_path = "tests/fixtures/projects/full_adder/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/full_adder.txt" },
    .{ .root_path = "tests/fixtures/projects/and_pair/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/and_pair.txt" },
    .{ .root_path = "tests/fixtures/projects/nested_invert/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/nested_invert.txt" },
    .{ .root_path = "tests/fixtures/projects/passthrough_chain/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/passthrough_chain.txt" },
    .{ .root_path = "tests/fixtures/projects/diamond/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/diamond.txt" },
    .{ .root_path = "tests/fixtures/projects/deep_chain/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/deep_chain.txt" },
    .{ .root_path = "tests/fixtures/projects/deep_subcircuit_chain/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/deep_subcircuit_chain.txt" },
    .{ .root_path = "tests/fixtures/projects/same_name_half_adder/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/same_name_half_adder.txt" },
    .{ .root_path = "tests/fixtures/projects/and_or_network/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/and_or_network.txt" },
    .{ .root_path = "tests/fixtures/projects/full_adder_ha_or/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/full_adder_ha_or.txt" },
    .{ .root_path = "tests/fixtures/projects/stress_deep_subcircuit/root.circ", .spec_path = "tests/fixtures/expected-wasm/projects/stress_deep_subcircuit.txt" },
};

test "section_writer: combined wasm is structurally valid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (!try checkNodeAvailable(allocator)) {
        std.debug.print("SKIPPED (node not found on PATH)\n", .{});
        return;
    }
    for (all_fixtures) |fx| {
        try runValidateOnly(fx, allocator);
    }
}

test "section_writer: circuits fixtures behavioral correctness" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (!try checkNodeAvailable(allocator)) {
        std.debug.print("SKIPPED (node not found on PATH)\n", .{});
        return;
    }
    for (circuit_fixtures) |fx| {
        try runFixture(fx, allocator);
    }
}

test "section_writer: project fixtures behavioral correctness" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (!try checkNodeAvailable(allocator)) {
        std.debug.print("SKIPPED (node not found on PATH)\n", .{});
        return;
    }
    for (project_fixtures) |fx| {
        try runFixture(fx, allocator);
    }
}
