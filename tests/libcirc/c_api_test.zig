//! The `circ_*` exports called directly: status codes, result-buffer
//! lifetime, and agreement with the Zig API.
const std = @import("std");
const c_api = @import("libcirc_c_api");
const libcirc = @import("libcirc");

fn result() []const u8 {
    return c_api.circ_result_ptr()[0..c_api.circ_result_len()];
}

fn call(f: fn ([*]const u8, usize) callconv(.c) u32, req: []const u8) u32 {
    return f(req.ptr, req.len);
}

const and_source = "input a\ninput b\nand g(a=a, b=b)\noutput out(in=g.out)\n";

fn requestFor(allocator: std.mem.Allocator, path: []const u8, source: []const u8, options: []const u8) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    const w = buf.writer(allocator);
    try w.writeAll("{\"root\":");
    try libcirc.analyzer.writeJsonString(w, path);
    try w.writeAll(",\"files\":{");
    try libcirc.analyzer.writeJsonString(w, path);
    try w.writeAll(":");
    try libcirc.analyzer.writeJsonString(w, source);
    try w.writeAll("}");
    if (options.len > 0) {
        try w.writeAll(",\"options\":");
        try w.writeAll(options);
    }
    try w.writeAll("}");
    return buf.toOwnedSlice(allocator);
}

test "c_api: circ_version is status 0 with the version JSON" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try std.testing.expectEqual(@as(u32, 0), c_api.circ_version());
    const parsed = try std.json.parseFromSlice(std.json.Value, a, result(), .{});
    const obj = parsed.value.object;
    try std.testing.expectEqual(@as(i64, libcirc.full_format.FULL_VERSION), obj.get("full_version").?.integer);
    try std.testing.expectEqual(@as(i64, libcirc.format.VERSION), obj.get("topology_version").?.integer);
    try std.testing.expectEqualStrings(libcirc.build_info.version, obj.get("version").?.string);
    try std.testing.expectEqual(@as(usize, 64), obj.get("grammar_sha256").?.string.len);
}

test "c_api: circ_analyze equals analyzer.renderJson" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const req = try requestFor(a, "/virtual/and.circ", and_source, "");
    try std.testing.expectEqual(@as(u32, 0), call(c_api.circ_analyze, req));

    var overlay = libcirc.analyzer.Overlay{};
    try overlay.put(a, "/virtual/and.circ", and_source);
    const analysis = try libcirc.analyzer.analyze(a, "/virtual/and.circ", overlay);
    var expected: std.ArrayList(u8) = .{};
    try libcirc.analyzer.renderJson(expected.writer(a), analysis);
    try std.testing.expectEqualStrings(expected.items, result());
}

test "c_api: bad request statuses" {
    const not_json = "not json";
    try std.testing.expectEqual(@as(u32, 2), call(c_api.circ_analyze, not_json));
    try std.testing.expectEqualStrings("{\"error\":\"invalid request JSON\"}", result());

    try std.testing.expectEqual(@as(u32, 2), call(c_api.circ_compile, "{}"));
    try std.testing.expectEqualStrings("{\"error\":\"request missing 'root'\"}", result());

    const relative = "{\"root\":\"r.circ\",\"files\":{\"r.circ\":\"\"}}";
    try std.testing.expectEqual(@as(u32, 2), call(c_api.circ_preview, relative));
    try std.testing.expectEqualStrings("{\"error\":\"files keys must be absolute paths\"}", result());

    const auto_color = "{\"root\":\"/r.circ\",\"options\":{\"color\":\"auto\"}}";
    try std.testing.expectEqual(@as(u32, 2), call(c_api.circ_preview, auto_color));
    try std.testing.expectEqualStrings("{\"error\":\"unknown or mistyped option\"}", result());

    const missing_root = "{\"root\":\"/nowhere/x.circ\",\"files\":{\"/elsewhere.circ\":\"\"}}";
    try std.testing.expectEqual(@as(u32, 2), call(c_api.circ_compile, missing_root));
    try std.testing.expectEqualStrings("{\"error\":\"failed reading input file: FileNotFound\"}", result());
}

test "c_api: circ_compile returns a wasm module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const req = try requestFor(a, "/virtual/and.circ", and_source, "");
    try std.testing.expectEqual(@as(u32, 0), call(c_api.circ_compile, req));
    try std.testing.expectEqualStrings("\x00asm", result()[0..4]);
    const wasm_len = c_api.circ_result_len();
    try std.testing.expect(wasm_len > 1000);

    const zig_api = try libcirc.compile(a, .{ .root = "/virtual/and.circ", .files = &.{.{ .path = "/virtual/and.circ", .text = and_source }} });
    try std.testing.expectEqual(libcirc.Status.ok, zig_api.status);
    try std.testing.expect(std.mem.eql(u8, zig_api.body, result()));
}

test "c_api: diagnostics status carries E001" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const source = try std.fs.cwd().readFileAlloc(a, "tests/fixtures/circuits/E001_undeclared.circ", 1 << 20);
    const req = try requestFor(a, "/virtual/e001.circ", source, "");
    try std.testing.expectEqual(@as(u32, 1), call(c_api.circ_compile, req));
    try std.testing.expect(std.mem.indexOf(u8, result(), "\"code\":\"E001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result(), "\"symbols\":[]") != null);
}

test "c_api: preview and truth table agree with the Zig API and the cap is refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const req = try requestFor(a, "/virtual/and.circ", and_source, "{\"color\":\"never\"}");
    try std.testing.expectEqual(@as(u32, 0), call(c_api.circ_preview, req));
    const prev = try libcirc.preview(a, .{ .root = "/virtual/and.circ", .files = &.{.{ .path = "/virtual/and.circ", .text = and_source }} });
    try std.testing.expectEqualStrings(prev.body, result());

    const tt = try requestFor(a, "/virtual/and.circ", and_source, "{\"format\":\"csv\",\"value_format\":\"hex\"}");
    try std.testing.expectEqual(@as(u32, 0), call(c_api.circ_truth_table, tt));
    const table = try libcirc.truthTable(a, .{
        .root = "/virtual/and.circ",
        .files = &.{.{ .path = "/virtual/and.circ", .text = and_source }},
        .options = .{ .format = .csv, .value_format = .hex },
    });
    try std.testing.expectEqualStrings(table.body, result());

    const capped = try requestFor(a, "/virtual/and.circ", and_source, "{\"truth_table_cap\":1}");
    try std.testing.expectEqual(@as(u32, 3), call(c_api.circ_truth_table, capped));
    try std.testing.expectEqualStrings(
        "{\"error\":\"truth table requires 2 input bits, exceeds cap of 1 (raise with options.truth_table_cap, max 24)\"}",
        result(),
    );
}

test "c_api: result buffer is replaced by the next call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try std.testing.expectEqual(@as(u32, 0), c_api.circ_version());
    const version_len = c_api.circ_result_len();
    try std.testing.expect(version_len > 0);
    const req = try requestFor(a, "/virtual/and.circ", and_source, "");
    try std.testing.expectEqual(@as(u32, 0), call(c_api.circ_compile, req));
    try std.testing.expect(c_api.circ_result_len() != version_len);
    try std.testing.expect(!std.mem.startsWith(u8, result(), "{\"version\""));
}

test "c_api: alloc/free round trip and reset" {
    const buf = c_api.circ_alloc(1024) orelse return error.AllocFailed;
    buf[0] = 'x';
    buf[1023] = 'y';
    c_api.circ_free(buf, 1024);

    try std.testing.expectEqual(@as(u32, 0), c_api.circ_reset());
    try std.testing.expectEqual(@as(usize, 0), c_api.circ_result_len());
    try std.testing.expectEqual(@as(usize, 0), libcirc.circuit.memory.arenaCapacityForTest());
    try std.testing.expectEqual(@as(u32, 0), c_api.circ_version());
    try std.testing.expect(c_api.circ_result_len() > 0);
}

test "c_api: the documented request literal compiles" {
    // The literal from DOCS/libcirc-api.md and examples/c/analyze.c.
    const documented =
        \\{"root": "/playground/main.circ",
        \\ "files": {"/playground/main.circ": "input a\nnot n(in=a)\noutput o(in=n.out)\n"},
        \\ "options": {"color": "never"}}
    ;
    try std.testing.expectEqual(@as(u32, 0), call(c_api.circ_compile, documented));
    try std.testing.expectEqualStrings("\x00asm", result()[0..4]);
    try std.testing.expectEqual(@as(u32, 0), call(c_api.circ_preview, documented));
    try std.testing.expect(std.mem.indexOf(u8, result(), "NOT") != null);
}

test "c_api: truth table ram refusal is status 3 and a hex preload loads a rom" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ram_source = try std.fs.cwd().readFileAlloc(a, "tests/fixtures/circuits/ram_basic.circ", 1 << 20);
    const ram_req = try requestFor(a, "/virtual/ram.circ", ram_source, "");
    try std.testing.expectEqual(@as(u32, 3), call(c_api.circ_truth_table, ram_req));
    try std.testing.expect(std.mem.indexOf(u8, result(), "ram 'data' is stateful") != null);

    const rom_source = try std.fs.cwd().readFileAlloc(a, "tests/fixtures/circuits/rom_lookup.circ", 1 << 20);
    const rom_req = try requestFor(a, "/virtual/rom.circ", rom_source, "{\"preloads\":{\"code\":\"00112233445566778899aabbccddeeff\"}}");
    try std.testing.expectEqual(@as(u32, 0), call(c_api.circ_truth_table, rom_req));
    const expected = try std.fs.cwd().readFileAlloc(a, "tests/fixtures/truth_table/rom_lookup.truth.golden", 1 << 20);
    try std.testing.expectEqualStrings(expected, result());
}
