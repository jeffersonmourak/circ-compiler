//! The Node-driven proof for libcirc.wasm: every export answers the way the
//! native C ABI does, byte for byte, and the artifacts it compiles run under
//! the topology host protocol against the expected-wasm vectors.
//!
//! Skips under SKIP_WASM_E2E=1 or without `node` on PATH, like the other
//! Node-driven suites.
const std = @import("std");
const embed = @import("libcirc_wasm_embed");
const c_api = @import("libcirc_c_api");
const libcirc = @import("libcirc");
const golden = @import("golden");

const Result = struct { name: []const u8, status: u32, bytes: []const u8 };

const Run = struct {
    stdout: []const u8,
    results: []const Result,

    fn get(self: Run, name: []const u8) ?Result {
        for (self.results) |r| if (std.mem.eql(u8, r.name, name)) return r;
        return null;
    }
};

fn shouldSkip(allocator: std.mem.Allocator) !bool {
    if (std.process.getEnvVarOwned(allocator, "SKIP_WASM_E2E") catch null) |val| {
        defer allocator.free(val);
        if (std.mem.eql(u8, val, "1")) {
            std.debug.print("SKIPPED (SKIP_WASM_E2E=1 set in environment)\n", .{});
            return true;
        }
    }
    const probe = std.process.Child.run(.{ .allocator = allocator, .argv = &.{ "node", "--version" } }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("SKIPPED (node not found on PATH)\n", .{});
            return true;
        }
        return err;
    };
    allocator.free(probe.stdout);
    allocator.free(probe.stderr);
    if (probe.term != .Exited or probe.term.Exited != 0) {
        std.debug.print("SKIPPED (node execution failed)\n", .{});
        return true;
    }
    return false;
}

/// Write the embedded module to a temp dir and run `script` through the
/// loader; returns stdout with the `RESULT` lines decoded.
fn runNode(allocator: std.mem.Allocator, script: []const u8) !Run {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "libcirc.wasm", .data = embed.wasm });
    const wasm_path = try tmp.dir.realpathAlloc(allocator, "libcirc.wasm");

    const encoder = std.base64.standard.Encoder;
    const b64 = try allocator.alloc(u8, encoder.calcSize(script.len));
    _ = encoder.encode(b64, script);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", "tests/harness/libcirc_loader.js", wasm_path, b64 },
        .max_output_bytes = 64 * 1024 * 1024,
    });
    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("node failed\nSTDOUT:\n{s}\nSTDERR:\n{s}\n", .{ result.stdout, result.stderr });
        return error.NodeFailed;
    }

    var results: std.ArrayList(Result) = .{};
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "RESULT ")) continue;
        var it = std.mem.tokenizeScalar(u8, line["RESULT ".len..], ' ');
        const name = it.next() orelse return error.BadResultLine;
        const status = try std.fmt.parseInt(u32, it.next() orelse return error.BadResultLine, 10);
        const payload = it.next() orelse "";
        const decoder = std.base64.standard.Decoder;
        const bytes = try allocator.alloc(u8, try decoder.calcSizeForSlice(payload));
        try decoder.decode(bytes, payload);
        try results.append(allocator, .{ .name = name, .status = status, .bytes = bytes });
    }
    return .{ .stdout = result.stdout, .results = try results.toOwnedSlice(allocator) };
}

/// The native side of every comparison: the same request through the
/// in-process C ABI.
fn native(op: enum { analyze, compile, preview, truth_table }, req: []const u8) struct { status: u32, bytes: []const u8 } {
    const status = switch (op) {
        .analyze => c_api.circ_analyze(req.ptr, req.len),
        .compile => c_api.circ_compile(req.ptr, req.len),
        .preview => c_api.circ_preview(req.ptr, req.len),
        .truth_table => c_api.circ_truth_table(req.ptr, req.len),
    };
    return .{ .status = status, .bytes = c_api.circ_result_ptr()[0..c_api.circ_result_len()] };
}

fn jsonString(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    try libcirc.analyzer.writeJsonString(buf.writer(allocator), s);
    return buf.toOwnedSlice(allocator);
}

const File = struct { path: []const u8, text: []const u8 };

/// `{"root":..,"files":{..},"options":<options or omitted>}`
fn request(allocator: std.mem.Allocator, root: []const u8, files: []const File, options: ?[]const u8) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    const w = buf.writer(allocator);
    try w.print("{{\"root\":{s},\"files\":{{", .{try jsonString(allocator, root)});
    for (files, 0..) |f, i| {
        if (i > 0) try w.writeByte(',');
        try w.print("{s}:{s}", .{ try jsonString(allocator, f.path), try jsonString(allocator, f.text) });
    }
    try w.writeAll("}");
    if (options) |o| try w.print(",\"options\":{s}", .{o});
    try w.writeAll("}");
    return buf.toOwnedSlice(allocator);
}

fn fixtureFiles(allocator: std.mem.Allocator, fixture: []const u8) ![]File {
    const text = try std.fs.cwd().readFileAlloc(allocator, fixture, 1 << 20);
    const files = try allocator.alloc(File, 1);
    files[0] = .{ .path = "/playground/main.circ", .text = text };
    return files;
}

test "libcirc.wasm: export surface is exactly memory plus the ten circ_ names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (try shouldSkip(a)) return;

    const run = try runNode(a,
        \\if (!WebAssembly.validate(circ.bytes)) throw new Error("invalid module");
        \\circ.emit("exports", 0, circ.exports().join(" "));
        \\circ.emit("imports", 0, circ.imports().join(" "));
    );
    try std.testing.expectEqualStrings(
        "circ_alloc circ_analyze circ_compile circ_free circ_preview circ_reset circ_result_len circ_result_ptr circ_truth_table circ_version memory",
        run.get("exports").?.bytes,
    );
    try std.testing.expectEqualStrings("env.debugEnabled env.onDebugLog", run.get("imports").?.bytes);
}

test "libcirc.wasm: circ_version JSON matches native" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (try shouldSkip(a)) return;

    const run = try runNode(a,
        \\const v = circ.version();
        \\circ.emit("version", v.status, v.bytes);
    );
    const v = run.get("version").?;
    try std.testing.expectEqual(@as(u32, 0), v.status);
    try std.testing.expectEqual(@as(u32, 0), c_api.circ_version());
    try std.testing.expectEqualStrings(c_api.circ_result_ptr()[0..c_api.circ_result_len()], v.bytes);

    const parsed = try std.json.parseFromSlice(std.json.Value, a, v.bytes, .{});
    const obj = parsed.value.object;
    try std.testing.expectEqual(@as(usize, 7), obj.count());
    try std.testing.expectEqual(@as(i64, libcirc.format.VERSION), obj.get("topology_version").?.integer);
    try std.testing.expectEqual(@as(i64, libcirc.full_format.FULL_VERSION), obj.get("full_version").?.integer);
    const version_file = std.mem.trim(u8, try std.fs.cwd().readFileAlloc(a, "VERSION", 64), " \t\r\n");
    try std.testing.expectEqualStrings(version_file, obj.get("version").?.string);
}

// ---- compile + drive ----

const Assignment = struct { name: []const u8, text: []const u8, value: u64, defined: u64 };
const Step = struct { inputs: []Assignment, outputs: []Assignment };

fn parseAssignment(token: []const u8) !Assignment {
    const eq = std.mem.indexOfScalar(u8, token, '=') orelse return error.InvalidAssignment;
    const name = token[0..eq];
    const text = token[eq + 1 ..];
    if (text.len == 0 or text.len > 64) return error.InvalidStateToken;
    var value: u64 = 0;
    var defined: u64 = 0;
    for (text, 0..) |c, i| {
        const bit: u6 = @intCast(text.len - 1 - i);
        const mask = @as(u64, 1) << bit;
        switch (c) {
            '0' => defined |= mask,
            '1' => {
                defined |= mask;
                value |= mask;
            },
            '?' => {},
            else => return error.InvalidStateToken,
        }
    }
    return .{ .name = name, .text = text, .value = value, .defined = defined };
}

fn parseSide(allocator: std.mem.Allocator, text: []const u8) ![]Assignment {
    var list: std.ArrayList(Assignment) = .{};
    var it = std.mem.tokenizeScalar(u8, text, ' ');
    while (it.next()) |tok| try list.append(allocator, try parseAssignment(tok));
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

const Pin = struct { name: []const u8, id: u32, width: u8 };

/// Root pins of the artifact the request compiles to, from the same
/// front end the library runs (ids are the runtime's component ids).
fn rootPins(allocator: std.mem.Allocator, root: []const u8, files: []const File) !struct { inputs: []Pin, outputs: []Pin } {
    const fe_files = try allocator.alloc(libcirc.File, files.len);
    for (files, 0..) |f, i| fe_files[i] = .{ .path = f.path, .text = f.text };
    var failure: libcirc.frontend.Failure = undefined;
    var front = try libcirc.frontend.run(allocator, root, fe_files, .project_if_imports, &failure);
    const topology = try libcirc.modes.buildTopology(allocator, &front, &failure);
    var inputs: std.ArrayList(Pin) = .{};
    var outputs: std.ArrayList(Pin) = .{};
    for (topology.components) |comp| {
        if (comp.origin.len != 0) continue;
        switch (comp.kind) {
            .input_pin => try inputs.append(allocator, .{ .name = comp.name, .id = comp.id, .width = comp.width }),
            .output_pin => try outputs.append(allocator, .{ .name = comp.name, .id = comp.id, .width = comp.width }),
            else => {},
        }
    }
    return .{ .inputs = try inputs.toOwnedSlice(allocator), .outputs = try outputs.toOwnedSlice(allocator) };
}

fn findPin(pins: []const Pin, name: []const u8) ?Pin {
    for (pins) |p| if (std.mem.eql(u8, p.name, name)) return p;
    return null;
}

const DriveCase = struct { name: []const u8, root: []const u8, sources: []const []const u8, keys: []const []const u8, vectors: []const u8 };

const drive_cases = [_]DriveCase{
    .{ .name = "inverter", .root = "/playground/main.circ", .sources = &.{"tests/fixtures/circuits/inverter.circ"}, .keys = &.{"/playground/main.circ"}, .vectors = "tests/fixtures/expected-wasm/inverter.txt" },
    .{ .name = "slice_basic", .root = "/playground/main.circ", .sources = &.{"tests/fixtures/circuits/slice_basic.circ"}, .keys = &.{"/playground/main.circ"}, .vectors = "tests/fixtures/expected-wasm/slice_basic.txt" },
    // four_bit_adder is deliberately absent: `compile` takes the import-free
    // fast path, which does not resolve implicit builtins (`xor`), exactly as
    // the CLI does; the full_adder project below covers macro expansion.
    .{ .name = "chain", .root = "/playground/main.circ", .sources = &.{"tests/fixtures/circuits/chain.circ"}, .keys = &.{"/playground/main.circ"}, .vectors = "tests/fixtures/expected-wasm/chain.txt" },
    .{ .name = "full_adder", .root = "/playground/root.circ", .sources = &.{ "tests/fixtures/projects/full_adder/root.circ", "tests/fixtures/projects/full_adder/half_adder.circ" }, .keys = &.{ "/playground/root.circ", "/playground/half_adder.circ" }, .vectors = "tests/fixtures/expected-wasm/projects/full_adder.txt" },
};

test "libcirc.wasm: compile inverter, slice_basic, chain, full_adder project and drive expected-wasm vectors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (try shouldSkip(a)) return;

    for (drive_cases) |case| {
        const files = try a.alloc(File, case.sources.len);
        for (case.sources, 0..) |src, i| files[i] = .{ .path = case.keys[i], .text = try std.fs.cwd().readFileAlloc(a, src, 1 << 20) };
        const req = try request(a, case.root, files, null);
        const pins = try rootPins(a, case.root, files);
        const steps = try parseSteps(a, try std.fs.cwd().readFileAlloc(a, case.vectors, 1 << 20));

        var script: std.ArrayList(u8) = .{};
        const w = script.writer(a);
        try w.print(
            \\const req = {s};
            \\const out = circ.call("compile", req);
            \\circ.emit("artifact", out.status, out.bytes);
            \\if (out.status !== 0) throw new Error("compile status " + out.status);
            \\const art = await WebAssembly.compile(out.bytes);
            \\if (WebAssembly.Module.customSections(art, "circ.topology.v0.min").length !== 1) throw new Error("no .min section");
            \\if (WebAssembly.Module.customSections(art, "circ.topology.v0.full").length !== 1) throw new Error("no .full section");
            \\const inst = await WebAssembly.instantiate(art, {{ env: {{
            \\  print: () => {{}}, printFmt: () => {{}}, flushBuffer: () => {{}},
            \\  _log: () => {{}}, _log_flush: () => {{}}, _log_set_name: () => {{}},
            \\  debugEnabled: () => 0, onDebugLog: () => {{}}
            \\}} }});
            \\const x = inst.exports;
            \\const topo = new Uint8Array(WebAssembly.Module.customSections(art, "circ.topology.v0.min")[0]);
            \\const tp = x.topology_alloc(topo.length);
            \\new Uint8Array(x.memory.buffer).set(topo, tp);
            \\x.init();
            \\const fmtState = (v, d, w) => {{ let s = ''; for (let b = w - 1; b >= 0; b--) {{ const m = 1n << BigInt(b); s += ((d & m) === 0n) ? '?' : (((v & m) === 0n) ? '0' : '1'); }} return s; }};
            \\const lines = [];
            \\
        , .{req});
        var expected: std.ArrayList(u8) = .{};
        const ew = expected.writer(a);
        for (steps, 0..) |step, idx| {
            for (step.inputs) |inp| {
                const pin = findPin(pins.inputs, inp.name) orelse return error.UnknownInputPin;
                try w.print("x.setPin({d}, {d}n, {d}n);\n", .{ pin.id, inp.value, inp.defined });
            }
            try w.writeAll("x.run();\n");
            try w.print("const p{d} = [];\n", .{idx});
            var first = true;
            for (step.outputs) |out| {
                const pin = findPin(pins.outputs, out.name) orelse return error.UnknownOutputPin;
                try w.print("p{d}.push('{s}=' + fmtState(x.getOutputValue({d}), x.getOutputDefined({d}), {d}));\n", .{ idx, out.name, pin.id, pin.id, pin.width });
                if (!first) try ew.writeAll(" ");
                first = false;
                try ew.print("{s}={s}", .{ out.name, out.text });
            }
            try w.print("lines.push(p{d}.join(' '));\n", .{idx});
            try ew.writeAll("\n");
        }
        try w.writeAll("circ.emit(\"drive\", 0, lines.join('\\n') + '\\n');\n");

        const run = try runNode(a, script.items);
        const artifact = run.get("artifact").?;
        try std.testing.expectEqual(@as(u32, 0), artifact.status);
        const ref = native(.compile, req);
        try std.testing.expectEqual(@as(u32, 0), ref.status);
        std.testing.expect(std.mem.eql(u8, ref.bytes, artifact.bytes)) catch |err| {
            std.debug.print("artifact differs from native for {s}\n", .{case.name});
            return err;
        };
        std.testing.expectEqualStrings(expected.items, run.get("drive").?.bytes) catch |err| {
            std.debug.print("vector drive differs for {s}\n", .{case.name});
            return err;
        };
    }
}

// ---- byte equality with native ----

const equality_fixtures = [_][]const u8{
    "tests/fixtures/circuits/chain.circ",
    "tests/fixtures/circuits/builtin_xor.circ",
    "tests/fixtures/circuits/alu_4bit_multibit.circ",
    "tests/fixtures/circuits/four_bit_adder.circ",
    "tests/fixtures/circuits/slice_basic.circ",
};

test "libcirc.wasm: analyze, preview, and truth table are byte-equal to native for five fixtures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (try shouldSkip(a)) return;

    var script: std.ArrayList(u8) = .{};
    const w = script.writer(a);
    var expected: std.ArrayList(struct { name: []const u8, bytes: []const u8 }) = .{};

    for (equality_fixtures, 0..) |fixture, i| {
        const files = try fixtureFiles(a, fixture);
        const plain = try request(a, "/playground/main.circ", files, null);
        const prev = try request(a, "/playground/main.circ", files, "{\"color\":\"never\"}");
        const tt_json = try request(a, "/playground/main.circ", files, "{\"format\":\"json\"}");
        const cases = [_]struct { op: []const u8, req: []const u8, tag: []const u8 }{
            .{ .op = "analyze", .req = plain, .tag = "analyze" },
            .{ .op = "preview", .req = prev, .tag = "preview" },
            .{ .op = "truth_table", .req = plain, .tag = "tt_md" },
            .{ .op = "truth_table", .req = tt_json, .tag = "tt_json" },
        };
        for (cases) |c| {
            const name = try std.fmt.allocPrint(a, "{d}_{s}", .{ i, c.tag });
            try w.print("{{ const r = circ.call(\"{s}\", {s}); circ.emit(\"{s}\", r.status, r.bytes); }}\n", .{ c.op, c.req, name });
            const ref = if (std.mem.eql(u8, c.op, "analyze")) native(.analyze, c.req) else if (std.mem.eql(u8, c.op, "preview")) native(.preview, c.req) else native(.truth_table, c.req);
            try std.testing.expectEqual(@as(u32, 0), ref.status);
            try expected.append(a, .{ .name = name, .bytes = try a.dupe(u8, ref.bytes) });
        }
    }

    const run = try runNode(a, script.items);
    for (expected.items) |e| {
        const got = run.get(e.name) orelse return error.MissingResult;
        try std.testing.expectEqual(@as(u32, 0), got.status);
        std.testing.expect(std.mem.eql(u8, e.bytes, got.bytes)) catch |err| {
            std.debug.print("wasm result differs from native for {s}\n", .{e.name});
            return err;
        };
    }
    // Tie the wasm build to the CLI's own goldens, not only to the native library.
    try golden.expectGolden(run.get("0_preview").?.bytes, "tests/fixtures/preview/renders/chain.preview.golden");
    try golden.expectGolden(run.get("1_tt_md").?.bytes, "tests/fixtures/truth_table/builtin_xor.truth.golden");
    try golden.expectGolden(run.get("1_tt_json").?.bytes, "tests/fixtures/truth_table/builtin_xor.json.golden");
}

test "libcirc.wasm: E004 source returns status 1 with analyze-shaped diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (try shouldSkip(a)) return;

    const files = try fixtureFiles(a, "tests/fixtures/circuits/E004_unconnected_required_input.circ");
    const req = try request(a, "/playground/main.circ", files, null);
    var script: std.ArrayList(u8) = .{};
    try script.writer(a).print(
        \\const req = {s};
        \\const c = circ.call("compile", req); circ.emit("compile", c.status, c.bytes);
        \\const an = circ.call("analyze", req); circ.emit("analyze", an.status, an.bytes);
        \\
    , .{req});
    const run = try runNode(a, script.items);

    const compiled = run.get("compile").?;
    try std.testing.expectEqual(@as(u32, 1), compiled.status);
    const ref = native(.compile, req);
    try std.testing.expectEqual(@as(u32, 1), ref.status);
    try std.testing.expectEqualStrings(ref.bytes, compiled.bytes);

    const parsed = try std.json.parseFromSlice(std.json.Value, a, compiled.bytes, .{});
    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("/playground/main.circ", obj.get("files").?.array.items[0].object.get("path").?.string);
    const diags = obj.get("diagnostics").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), diags.len);
    const d = diags[0].object;
    try std.testing.expectEqualStrings("error", d.get("severity").?.string);
    try std.testing.expectEqualStrings("E004", d.get("code").?.string);
    try std.testing.expectEqualStrings("required input 'b' is unconnected", d.get("message").?.string);
    try std.testing.expectEqual(@as(i64, 2), d.get("range").?.object.get("start_line").?.integer);
    try std.testing.expectEqual(@as(i64, 1), d.get("range").?.object.get("start_col").?.integer);

    const analyzed = run.get("analyze").?;
    try std.testing.expectEqual(@as(u32, 0), analyzed.status);
    const an = try std.json.parseFromSlice(std.json.Value, a, analyzed.bytes, .{});
    const an_diags = an.value.object.get("diagnostics").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), an_diags.len);
    try std.testing.expectEqualStrings("E004", an_diags[0].object.get("code").?.string);
}

test "libcirc.wasm: bad request → 2, cap refusal → 3" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (try shouldSkip(a)) return;

    const wide = [_]File{.{ .path = "/playground/main.circ", .text = "input[17] a\noutput[17] o(in=a)\n" }};
    const wide_req = try request(a, "/playground/main.circ", &wide, null);
    var script: std.ArrayList(u8) = .{};
    try script.writer(a).print(
        \\{{ const r = circ.call("compile", "{{"); circ.emit("brace", r.status, r.bytes); }}
        \\{{ const r = circ.call("compile", ""); circ.emit("empty", r.status, r.bytes); }}
        \\{{ const r = circ.call("compile", {{ root: "/playground/nowhere.circ", files: {{ "/playground/main.circ": "input a\n" }} }}); circ.emit("noroot", r.status, r.bytes); }}
        \\{{ const r = circ.call("truth_table", {s}); circ.emit("wide_tt", r.status, r.bytes); }}
        \\{{ const r = circ.call("compile", {s}); circ.emit("wide_compile", r.status, r.bytes); }}
        \\
    , .{ wide_req, wide_req });
    const run = try runNode(a, script.items);

    for ([_][]const u8{ "brace", "empty", "noroot" }) |name| {
        const r = run.get(name).?;
        try std.testing.expectEqual(@as(u32, 2), r.status);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, r.bytes, .{});
        try std.testing.expect(parsed.value.object.get("error").?.string.len > 0);
    }
    const wide_tt = run.get("wide_tt").?;
    try std.testing.expectEqual(@as(u32, 3), wide_tt.status);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, wide_tt.bytes, .{});
    try std.testing.expect(std.mem.indexOf(u8, parsed.value.object.get("error").?.string, "17") != null);
    try std.testing.expectEqual(@as(u32, 0), run.get("wide_compile").?.status);
}
