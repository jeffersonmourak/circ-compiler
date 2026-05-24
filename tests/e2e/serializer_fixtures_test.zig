const std = @import("std");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const validator_run_project = @import("validator_run_project");
const diagnostics = @import("diagnostics");
const serializer = @import("serializer");
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

fn appendLEB128(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var v = value;
    while (true) {
        const byte: u8 = @intCast(v & 0x7F);
        v >>= 7;
        if (v != 0) {
            try buf.append(allocator, byte | 0x80);
        } else {
            try buf.append(allocator, byte);
            return;
        }
    }
}

fn buildCombinedWasm(allocator: std.mem.Allocator, topology_payload: []const u8) ![]u8 {
    const section_name = "circ.topology.v0.min";
    // Section body = LEB128(name_len) + name + payload
    const name_len: u32 = @intCast(section_name.len);
    // name_len < 128, so LEB128 is 1 byte
    const section_body_len: u32 = 1 + name_len + @as(u32, @intCast(topology_payload.len));

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    // Start with the pre-built runtime WASM
    try buf.appendSlice(allocator, runtime_embed.runtime_wasm);

    // Append custom section
    try buf.append(allocator, 0x00); // section id = custom
    try appendLEB128(&buf, allocator, section_body_len);
    try appendLEB128(&buf, allocator, name_len);
    try buf.appendSlice(allocator, section_name);
    try buf.appendSlice(allocator, topology_payload);

    return buf.toOwnedSlice(allocator);
}

fn pinId(mappings: []const serializer.PinMapping, name: []const u8) ?u32 {
    for (mappings) |m| {
        if (std.mem.eql(u8, m.name, name)) return m.global_id;
    }
    return null;
}

fn runFixture(fixture: Fixture) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Check if node is available
    const node_check = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", "--version" },
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("SKIPPED (node not found on PATH)\n", .{});
            return;
        }
        return err;
    };
    if (node_check.term != .Exited or node_check.term.Exited != 0) {
        std.debug.print("SKIPPED (node execution failed)\n", .{});
        return;
    }

    // Resolve the project
    const scan_result = try scan_imports.scanProjectImports(allocator, fixture.root_path);
    if (hasHardErrors(scan_result.diagnostics.items)) return error.ScanFailed;

    const cycle_result = try import_cycle.analyzeImports(
        allocator,
        scan_result.file_paths,
        scan_result.import_table,
    );
    if (hasHardErrors(cycle_result.diagnostics.items)) return error.CycleFailed;

    var resolver_diagnostics = diagnostics.initDiagnosticList();
    const project = try resolve_bodies.resolveBodies(
        allocator,
        scan_result.file_paths,
        scan_result.import_table,
        cycle_result.topo_order,
        &resolver_diagnostics,
    );
    if (hasHardErrors(resolver_diagnostics.items)) return error.UnexpectedResolverDiagnostics;

    var diags = try validator_run_project.run(allocator, &project);
    defer diags.deinit(allocator);
    if (hasHardErrors(diags.items)) return error.ValidationFailed;

    // Serialize to topology
    var topo = try serializer.serializeProjectFull(allocator, &project);
    defer topo.deinit(allocator);

    // Build combined WASM
    const combined_wasm = try buildCombinedWasm(allocator, topo.payload);
    defer allocator.free(combined_wasm);

    // Parse spec
    const spec_text = try std.fs.cwd().readFileAlloc(allocator, fixture.spec_path, 4 * 1024 * 1024);
    const steps = try parseSteps(allocator, spec_text);

    // Generate Node script
    var script: std.ArrayList(u8) = .{};
    const w = script.writer(allocator);
    try w.writeAll(
        \\const fs = require('fs');
        \\const wasmBytes = fs.readFileSync(process.argv[2]);
        \\(async () => {
        \\    const mod = await WebAssembly.compile(wasmBytes);
        \\    const instance = await WebAssembly.instantiate(mod, { env: {
        \\        print: () => {}, printFmt: () => {}, flushBuffer: () => {},
        \\        _log: () => {}, _log_flush: () => {}, _log_set_name: () => {},
        \\        debugEnabled: () => 0, onDebugLog: () => {}
        \\    } });
        \\    const topoSections = WebAssembly.Module.customSections(mod, 'circ.topology.v0.min');
        \\    if (topoSections.length === 0) throw new Error('No circ.topology.v0.min section');
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
            const value: u64 = if (inp.value == 1) 1 else 0;
            const defined: u64 = if (inp.value == 2) 0 else 1;
            try w.print("    instance.exports.setPin({d}, {d}n, {d}n);\n", .{ id, value, defined });
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

    // Write to temp files and run
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "combined.wasm", .data = combined_wasm });
    try tmp_dir.dir.writeFile(.{ .sub_path = "runner.js", .data = script.items });

    const wasm_path = try tmp_dir.dir.realpathAlloc(allocator, "combined.wasm");
    const script_path = try tmp_dir.dir.realpathAlloc(allocator, "runner.js");

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", script_path, wasm_path },
    });

    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("Node failed for {s}\nSTDOUT:\n{s}\nSTDERR:\n{s}\n", .{
            fixture.root_path,
            result.stdout,
            result.stderr,
        });
        return error.NodeFailed;
    }

    try std.testing.expectEqualStrings(expected.items, result.stdout);
}

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

test "serializer: circuits fixtures via Node" {
    for (circuit_fixtures) |fx| {
        try runFixture(fx);
    }
}

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

test "serializer: project fixtures via Node" {
    for (project_fixtures) |fx| {
        try runFixture(fx);
    }
}
