//! libcirc == circ-compile, byte for byte, mode by mode. The CLI is run
//! in-process through its `run` entry point so both sides see the same
//! fixtures; where the CLI already pins a golden, the library output is
//! checked against that golden too.
const std = @import("std");
const libcirc = @import("libcirc");
const circ_compile = @import("circ_compile");
const golden = @import("golden");

const Cli = struct { code: u8, stdout: []const u8, stderr: []const u8 };

fn cli(allocator: std.mem.Allocator, argv: []const []const u8) !Cli {
    var stdout_buf: std.ArrayList(u8) = .{};
    var stderr_buf: std.ArrayList(u8) = .{};
    const code = try circ_compile.run(allocator, argv, stdout_buf.writer(allocator), stderr_buf.writer(allocator));
    return .{ .code = code, .stdout = stdout_buf.items, .stderr = stderr_buf.items };
}

fn expectOk(o: libcirc.Outcome) !void {
    if (o.status != .ok) {
        std.debug.print("unexpected status {s}: {s}\n", .{ @tagName(o.status), o.body });
        return error.UnexpectedStatus;
    }
}

test "driver: version reports the topology versions and the grammar sha" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const v = libcirc.version();
    try std.testing.expectEqual(libcirc.full_format.FULL_VERSION, v.full_version);
    const peg = try std.fs.cwd().readFileAlloc(a, "lib/grammar/proto-circ.peg", 1 << 20);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(peg, &digest, .{});
    const hex = try std.fmt.allocPrint(a, "{x}", .{digest});
    try std.testing.expectEqualStrings(hex, v.grammar_sha256);

    var buf: std.ArrayList(u8) = .{};
    try libcirc.writeVersionJson(buf.writer(a));
    const parsed = try std.json.parseFromSlice(std.json.Value, a, buf.items, .{});
    try std.testing.expectEqual(@as(i64, libcirc.full_format.FULL_VERSION), parsed.value.object.get("full_version").?.integer);
}

const PreviewCase = struct {
    path: []const u8,
    expand_macros: bool = false,
    expand_display: bool = false,
    color: libcirc.Color = .never,
    golden_path: ?[]const u8 = null,
};

const preview_cases = [_]PreviewCase{
    .{ .path = "tests/fixtures/circuits/chain.circ", .golden_path = "tests/fixtures/preview/renders/chain.preview.golden" },
    .{ .path = "tests/fixtures/circuits/builtin_xor.circ", .golden_path = "tests/fixtures/preview/renders/builtin_xor.preview.golden" },
    .{ .path = "tests/fixtures/circuits/builtin_xnor.circ", .golden_path = "tests/fixtures/preview/renders/builtin_xnor.preview.golden" },
    .{ .path = "tests/fixtures/circuits/single_gate.circ", .golden_path = "tests/fixtures/preview/renders/single_gate.render.golden" },
    .{ .path = "tests/fixtures/circuits/single_gate.circ", .color = .always, .golden_path = "tests/fixtures/preview/renders/single_gate.render.color.golden" },
    .{ .path = "tests/fixtures/circuits/multibit_input_preview.circ" },
    .{ .path = "tests/fixtures/circuits/multibit_output_preview.circ" },
    .{ .path = "tests/fixtures/circuits/multibit_and_preview.circ" },
    .{ .path = "tests/fixtures/circuits/mixed_width_preview.circ" },
    .{ .path = "tests/fixtures/circuits/led_4bit_default.circ" },
    .{ .path = "tests/fixtures/circuits/led_4bit_default.circ", .expand_display = true },
    .{ .path = "tests/fixtures/circuits/led_7bit_default.circ", .expand_display = true },
    .{ .path = "tests/fixtures/circuits/led_8bit_default.circ", .expand_display = true },
    .{ .path = "tests/fixtures/circuits/fan_out.circ" },
    .{ .path = "tests/fixtures/circuits/fan_in.circ" },
    .{ .path = "tests/fixtures/circuits/multi_led.circ" },
    .{ .path = "tests/fixtures/circuits/and_of_not.circ" },
    .{ .path = "tests/fixtures/circuits/clean_gated_feedback.circ" },
    .{ .path = "tests/fixtures/circuits/parallel_leftward_detours.circ" },
    .{ .path = "tests/fixtures/circuits/regression_led_out_drives_gate.circ" },
    .{ .path = "tests/fixtures/circuits/edge_single_component.circ" },
    .{ .path = "tests/fixtures/circuits/full_adder_from_builtins.circ", .expand_macros = true },
    .{ .path = "tests/fixtures/circuits/builtin_xor.circ", .expand_macros = true },
    .{ .path = "tests/fixtures/circuits/builtin_xnor.circ", .expand_macros = true },
};

test "driver: preview equals the CLI for every render fixture" {
    for (preview_cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var argv: std.ArrayList([]const u8) = .{};
        try argv.appendSlice(a, &.{ "circ-compile", case.path, "--preview" });
        try argv.append(a, if (case.color == .always) "--color=always" else "--color=never");
        if (case.expand_macros) try argv.append(a, "--expand-macros");
        if (case.expand_display) try argv.append(a, "--expand-display");
        const ref = try cli(a, argv.items);
        try std.testing.expectEqual(@as(u8, 0), ref.code);

        const out = try libcirc.preview(a, .{ .root = case.path, .options = .{
            .expand_macros = case.expand_macros,
            .expand_display = case.expand_display,
            .color = case.color,
        } });
        try expectOk(out);
        std.testing.expectEqualStrings(ref.stdout, out.body) catch |err| {
            std.debug.print("preview mismatch for {s}\n", .{case.path});
            return err;
        };
        if (case.golden_path) |g| try golden.expectGolden(out.body, g);
    }
}

const TablePair = struct { path: []const u8, golden_path: []const u8 };
const table_pairs = [_]TablePair{
    .{ .path = "tests/fixtures/circuits/and_two_inputs.circ", .golden_path = "tests/fixtures/truth_table/and_two_inputs.truth.golden" },
    .{ .path = "tests/fixtures/circuits/and_gate.circ", .golden_path = "tests/fixtures/truth_table/primitive_and.truth.golden" },
    .{ .path = "tests/fixtures/circuits/single_gate.circ", .golden_path = "tests/fixtures/truth_table/primitive_not.truth.golden" },
    .{ .path = "tests/fixtures/circuits/wire_passthrough.circ", .golden_path = "tests/fixtures/truth_table/primitive_wire.truth.golden" },
    .{ .path = "tests/fixtures/circuits/edge_single_component.circ", .golden_path = "tests/fixtures/truth_table/primitive_led.truth.golden" },
    .{ .path = "tests/fixtures/circuits/builtin_nand.circ", .golden_path = "tests/fixtures/truth_table/builtin_nand.truth.golden" },
    .{ .path = "tests/fixtures/circuits/builtin_nor.circ", .golden_path = "tests/fixtures/truth_table/builtin_nor.truth.golden" },
    .{ .path = "tests/fixtures/circuits/builtin_or.circ", .golden_path = "tests/fixtures/truth_table/builtin_or.truth.golden" },
    .{ .path = "tests/fixtures/circuits/builtin_xnor.circ", .golden_path = "tests/fixtures/truth_table/builtin_xnor.truth.golden" },
    .{ .path = "tests/fixtures/circuits/half_adder.circ", .golden_path = "tests/fixtures/truth_table/half_adder.truth.golden" },
    .{ .path = "tests/fixtures/circuits/full_adder_from_builtins.circ", .golden_path = "tests/fixtures/truth_table/full_adder.truth.golden" },
    .{ .path = "tests/fixtures/circuits/two_bit_adder.circ", .golden_path = "tests/fixtures/truth_table/two_bit_adder.truth.golden" },
    .{ .path = "tests/fixtures/circuits/mux_2to1.circ", .golden_path = "tests/fixtures/truth_table/mux_2to1.truth.golden" },
    .{ .path = "tests/fixtures/circuits/demux_1to2.circ", .golden_path = "tests/fixtures/truth_table/demux_1to2.truth.golden" },
    .{ .path = "tests/fixtures/circuits/and_2bit.circ", .golden_path = "tests/fixtures/truth_table/and_2bit.truth.golden" },
    .{ .path = "tests/fixtures/circuits/not_4bit.circ", .golden_path = "tests/fixtures/truth_table/not_4bit.truth.golden" },
    .{ .path = "tests/fixtures/circuits/mux_4bit_2to1.circ", .golden_path = "tests/fixtures/truth_table/mux_4bit_2to1.truth.golden" },
    .{ .path = "tests/fixtures/circuits/xor_4bit.circ", .golden_path = "tests/fixtures/truth_table/xor_4bit.truth.golden" },
    .{ .path = "tests/fixtures/circuits/demux_4bit_1to2.circ", .golden_path = "tests/fixtures/truth_table/demux_4bit_1to2.truth.golden" },
    .{ .path = "tests/fixtures/circuits/four_bit_adder.circ", .golden_path = "tests/fixtures/truth_table/four_bit_adder.truth.golden" },
    .{ .path = "tests/fixtures/circuits/alu_4bit.circ", .golden_path = "tests/fixtures/truth_table/alu_4bit.truth.golden" },
};

test "driver: truth table equals the CLI and the golden for each table fixture" {
    for (table_pairs) |pair| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const ref = try cli(a, &.{ "circ-compile", pair.path, "--truth-table" });
        try std.testing.expectEqual(@as(u8, 0), ref.code);
        const out = try libcirc.truthTable(a, .{ .root = pair.path });
        try expectOk(out);
        std.testing.expectEqualStrings(ref.stdout, out.body) catch |err| {
            std.debug.print("truth table mismatch for {s}\n", .{pair.path});
            return err;
        };
        try golden.expectGolden(out.body, pair.golden_path);
    }
}

test "driver: truth table formats equal their goldens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const csv = try libcirc.truthTable(a, .{ .root = "tests/fixtures/circuits/builtin_xor.circ", .options = .{ .format = .csv } });
    try expectOk(csv);
    try golden.expectGolden(csv.body, "tests/fixtures/truth_table/builtin_xor.csv.golden");
    const js = try libcirc.truthTable(a, .{ .root = "tests/fixtures/circuits/builtin_xor.circ", .options = .{ .format = .json } });
    try expectOk(js);
    try golden.expectGolden(js.body, "tests/fixtures/truth_table/builtin_xor.json.golden");

    const hex_md = try libcirc.truthTable(a, .{ .root = "tests/fixtures/circuits/and_4bit_truth.circ", .options = .{ .value_format = .hex } });
    try expectOk(hex_md);
    try golden.expectGolden(hex_md.body, "tests/fixtures/truth_table/and_4bit_truth.hex.md.golden");
    const dec_md = try libcirc.truthTable(a, .{ .root = "tests/fixtures/circuits/and_4bit_truth.circ", .options = .{ .value_format = .decimal } });
    try expectOk(dec_md);
    try golden.expectGolden(dec_md.body, "tests/fixtures/truth_table/and_4bit_truth.decimal.md.golden");
    const hex_csv = try libcirc.truthTable(a, .{ .root = "tests/fixtures/circuits/and_4bit_truth.circ", .options = .{ .format = .csv, .value_format = .hex } });
    try expectOk(hex_csv);
    try golden.expectGolden(hex_csv.body, "tests/fixtures/truth_table/and_4bit_truth.hex.csv.golden");
}

test "driver: truth table refusals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const capped = try libcirc.truthTable(a, .{ .root = "tests/fixtures/circuits/and_4bit_truth.circ", .options = .{ .truth_table_cap = 4 } });
    try std.testing.expectEqual(libcirc.Status.refused, capped.status);
    try std.testing.expectEqualStrings(
        "{\"error\":\"truth table requires 8 input bits, exceeds cap of 4 (raise with options.truth_table_cap, max 24)\"}",
        capped.body,
    );

    const ref = try cli(a, &.{ "circ-compile", "tests/fixtures/circuits/and_4bit_truth.circ", "--truth-table", "--truth-table-cap=4" });
    try std.testing.expectEqual(@as(u8, 1), ref.code);
    try std.testing.expectEqualStrings("truth table requires 8 input bits, exceeds cap of 4 (raise with --truth-table-cap, max 24)\n", ref.stderr);

    const zero = try libcirc.truthTable(a, .{ .root = "tests/fixtures/circuits/and_gate.circ", .options = .{ .truth_table_cap = 0 } });
    try std.testing.expectEqual(libcirc.Status.bad_request, zero.status);
    const over = try libcirc.truthTable(a, .{ .root = "tests/fixtures/circuits/and_gate.circ", .options = .{ .truth_table_cap = 25 } });
    try std.testing.expectEqual(libcirc.Status.bad_request, over.status);
}

const compile_fixtures = [_][]const u8{
    "tests/fixtures/circuits/inverter.circ",
    "tests/fixtures/circuits/and_gate.circ",
    // full_adder_from_builtins is deliberately absent: `compile` takes the
    // import-free fast path, which does not resolve implicit builtins, so
    // the CLI itself exits 1 on it (preview/truth-table take the project route).
    "tests/fixtures/circuits/chain.circ",
    "tests/fixtures/circuits/slice_basic.circ",
    "tests/fixtures/circuits/stress_grid_10x10.circ",
    "tests/fixtures/projects/full_adder/root.circ",
};

test "driver: compile equals the CLI artifact byte for byte" {
    for (compile_fixtures) |path| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const out_path = try tmp.dir.realpathAlloc(a, ".");
        const wasm_path = try std.fs.path.join(a, &.{ out_path, "out.wasm" });

        const ref = try cli(a, &.{ "circ-compile", path, "-o", wasm_path });
        if (ref.code != 0) std.debug.print("cli compile of {s} exited {d}: {s}\n", .{ path, ref.code, ref.stderr });
        try std.testing.expectEqual(@as(u8, 0), ref.code);
        const expected = try std.fs.cwd().readFileAlloc(a, wasm_path, 64 * 1024 * 1024);

        const out = try libcirc.compile(a, .{ .root = path });
        try expectOk(out);
        try std.testing.expect(std.mem.eql(u8, expected, out.body));
        try std.testing.expectEqualStrings("\x00asm", out.body[0..4]);
    }
}

fn nodeAvailable(allocator: std.mem.Allocator) bool {
    const result = std.process.Child.run(.{ .allocator = allocator, .argv = &.{ "node", "--version" } }) catch return false;
    return result.term == .Exited and result.term.Exited == 0;
}

test "driver: compiled inverter runs in Node" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (!nodeAvailable(a)) {
        std.debug.print("SKIPPED (node not found on PATH)\n", .{});
        return;
    }

    const root = "tests/fixtures/circuits/inverter.circ";
    const out = try libcirc.compile(a, .{ .root = root });
    try expectOk(out);

    // Root pin ids from the same topology the artifact carries.
    var failure: libcirc.frontend.Failure = undefined;
    var front = try libcirc.frontend.run(a, root, &.{}, .project_if_imports, &failure);
    defer front.deinit(a);
    const topology = try libcirc.modes.buildTopology(a, &front, &failure);
    var in_id: ?u32 = null;
    var out_id: ?u32 = null;
    for (topology.components) |comp| {
        if (comp.origin.len != 0) continue;
        switch (comp.kind) {
            .input_pin => in_id = comp.id,
            .output_pin => out_id = comp.id,
            else => {},
        }
    }

    const script = try std.fmt.allocPrint(a,
        \\const fs = require('fs');
        \\const bytes = fs.readFileSync(process.argv[2]);
        \\if (!WebAssembly.validate(bytes)) throw new Error('invalid wasm');
        \\(async () => {{
        \\  const mod = await WebAssembly.compile(bytes);
        \\  const inst = await WebAssembly.instantiate(mod, {{ env: {{
        \\    print: () => {{}}, printFmt: () => {{}}, flushBuffer: () => {{}},
        \\    _log: () => {{}}, _log_flush: () => {{}}, _log_set_name: () => {{}},
        \\    debugEnabled: () => 0, onDebugLog: () => {{}}
        \\  }} }});
        \\  const topo = new Uint8Array(WebAssembly.Module.customSections(mod, 'circ.topology.v0.min')[0]);
        \\  const ptr = inst.exports.topology_alloc(topo.length);
        \\  new Uint8Array(inst.exports.memory.buffer).set(topo, ptr);
        \\  inst.exports.init();
        \\  inst.exports.setPin({d}, 1n, 1n); inst.exports.run();
        \\  const a = inst.exports.getOutputValue({d}) & 1n;
        \\  inst.exports.setPin({d}, 0n, 1n); inst.exports.run();
        \\  const b = inst.exports.getOutputValue({d}) & 1n;
        \\  console.log(String(a) + ' ' + String(b));
        \\}})().catch(e => {{ console.error(e); process.exit(1); }});
        \\
    , .{ in_id.?, out_id.?, in_id.?, out_id.? });

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "out.wasm", .data = out.body });
    try tmp.dir.writeFile(.{ .sub_path = "run.js", .data = script });
    const wasm_path = try tmp.dir.realpathAlloc(a, "out.wasm");
    const js_path = try tmp.dir.realpathAlloc(a, "run.js");
    const result = try std.process.Child.run(.{ .allocator = a, .argv = &.{ "node", js_path, wasm_path } });
    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("node failed:\n{s}\n{s}\n", .{ result.stdout, result.stderr });
        return error.NodeFailed;
    }
    try std.testing.expectEqualStrings("0 1\n", result.stdout);
}

test "driver: analyze equals renderJson" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const out = try libcirc.analyze(a, .{ .root = "tests/fixtures/projects/two_file/root.circ" });
    try expectOk(out);
    const analysis = try libcirc.analyzer.analyze(a, "tests/fixtures/projects/two_file/root.circ", null);
    var buf: std.ArrayList(u8) = .{};
    try libcirc.analyzer.renderJson(buf.writer(a), analysis);
    try std.testing.expectEqualStrings(buf.items, out.body);

    const files = [_]libcirc.File{
        .{ .path = "/virtual/dep.circ", .text = "input x\noutput y(in=x)\n" },
        .{ .path = "/virtual/root.circ", .text = "import dep \"dep.circ\"\ninput a\ndep d(x=a)\noutput o(in=d.y)\n" },
    };
    const mem = try libcirc.analyze(a, .{ .root = "/virtual/root.circ", .files = &files });
    try expectOk(mem);
    try std.testing.expect(std.mem.indexOf(u8, mem.body, "\"E009\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, mem.body, "/virtual/dep.circ") != null);
}

test "driver: status 1 result is analyze-api shaped" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const out = try libcirc.compile(a, .{ .root = "tests/fixtures/circuits/E001_undeclared.circ" });
    try std.testing.expectEqual(libcirc.Status.diagnostics, out.status);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, out.body, .{});
    const diags = parsed.value.object.get("diagnostics").?.array;
    try std.testing.expect(diags.items.len > 0);
    try std.testing.expectEqualStrings("E001", diags.items[0].object.get("code").?.string);
    const files = parsed.value.object.get("files").?.array;
    try std.testing.expect(std.mem.endsWith(u8, files.items[0].object.get("path").?.string, "tests/fixtures/circuits/E001_undeclared.circ"));
    try std.testing.expectEqual(@as(usize, 0), parsed.value.object.get("symbols").?.array.items.len);

    const warn = try libcirc.compile(a, .{ .root = "tests/fixtures/circuits/W001_unused_input.circ" });
    try expectOk(warn);
    const strict = try libcirc.compile(a, .{ .root = "tests/fixtures/circuits/W001_unused_input.circ", .options = .{ .warnings_as_errors = true } });
    try std.testing.expectEqual(libcirc.Status.diagnostics, strict.status);
    try std.testing.expect(std.mem.indexOf(u8, strict.body, "\"W001\"") != null);
}

test "driver: an empty root is a syntax failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const files = [_]libcirc.File{.{ .path = "/v/e.circ", .text = "" }};
    const out = try libcirc.compile(a, .{ .root = "/v/e.circ", .files = &files });
    try std.testing.expectEqual(libcirc.Status.diagnostics, out.status);
    try std.testing.expectEqualStrings(
        "{\"files\":[{\"file_id\":0,\"path\":\"/v/e.circ\"}],\"diagnostics\":[{\"file_id\":0,\"severity\":\"error\",\"code\":\"syntax\",\"range\":{\"start_line\":1,\"start_col\":1,\"end_line\":1,\"end_col\":2},\"message\":\"parse failed: ParsingFailed\",\"related\":[]}],\"symbols\":[],\"references\":[]}\n",
        out.body,
    );

    const missing = try libcirc.compile(a, .{ .root = "/v/nowhere.circ", .files = &files });
    try std.testing.expectEqual(libcirc.Status.bad_request, missing.status);
    try std.testing.expectEqualStrings("{\"error\":\"failed reading input file: FileNotFound\"}", missing.body);
}

test "driver: consecutive truth tables survive memory.reset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const first = try libcirc.truthTable(a, .{ .root = "tests/fixtures/circuits/alu_4bit.circ" });
    try expectOk(first);
    try std.testing.expectEqual(@as(usize, 0), libcirc.circuit.memory.arenaCapacityForTest());
    const second = try libcirc.truthTable(a, .{ .root = "tests/fixtures/circuits/alu_4bit.circ" });
    try expectOk(second);
    try std.testing.expectEqualStrings(first.body, second.body);
    try golden.expectGolden(second.body, "tests/fixtures/truth_table/alu_4bit.truth.golden");
}

test "driver: root plus overlay-only sibling compiles like the disk project" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const root_text = try std.fs.cwd().readFileAlloc(a, "tests/fixtures/projects/full_adder/root.circ", 1 << 20);
    const dir = try std.fs.cwd().openDir("tests/fixtures/projects/full_adder", .{ .iterate = true });
    var files: std.ArrayList(libcirc.File) = .{};
    try files.append(a, .{ .path = "/p/root.circ", .text = root_text });
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or std.mem.eql(u8, entry.name, "root.circ")) continue;
        const text = try dir.readFileAlloc(a, entry.name, 1 << 20);
        try files.append(a, .{ .path = try std.fmt.allocPrint(a, "/p/{s}", .{entry.name}), .text = text });
    }
    try std.testing.expect(files.items.len >= 2);

    const mem = try libcirc.compile(a, .{ .root = "/p/root.circ", .files = files.items });
    try expectOk(mem);
    const disk = try libcirc.compile(a, .{ .root = "tests/fixtures/projects/full_adder/root.circ" });
    try expectOk(disk);
    try std.testing.expect(std.mem.eql(u8, disk.body, mem.body));
}

test "driver: a recovered syntax error is status 1 with a syntax diagnostic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The parser recovers (drops `n`) and the CLI would compile the rest;
    // the library reports the mark so a host never ships a silently
    // truncated circuit.
    const files = [_]libcirc.File{.{ .path = "/v/broken.circ", .text = "input a\nnot n(in=a\n" }};
    const out = try libcirc.compile(a, .{ .root = "/v/broken.circ", .files = &files });
    try std.testing.expectEqual(libcirc.Status.diagnostics, out.status);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, out.body, .{});
    const diags = parsed.value.object.get("diagnostics").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), diags.len);
    try std.testing.expectEqualStrings("syntax", diags[0].object.get("code").?.string);
    try std.testing.expectEqualStrings("expected ')' to close the connection list", diags[0].object.get("message").?.string);
    try std.testing.expectEqual(@as(i64, 3), diags[0].object.get("range").?.object.get("start_line").?.integer);
    try std.testing.expectEqual(@as(i64, 2), diags[0].object.get("range").?.object.get("end_col").?.integer);

    // The same marks, in the same shape, from analyze.
    const an = try libcirc.analyze(a, .{ .root = "/v/broken.circ", .files = &files });
    try std.testing.expectEqual(libcirc.Status.ok, an.status);
    try std.testing.expect(std.mem.indexOf(u8, an.body, "\"code\":\"syntax\"") != null);
}
