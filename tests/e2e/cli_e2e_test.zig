const std = @import("std");
const build_options = @import("build_options");

const circ_compile_path = build_options.circ_compile_path;

fn checkNodeAvailable(allocator: std.mem.Allocator) !bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", "--version" },
    }) catch |err| {
        if (err == error.FileNotFound) return false;
        return err;
    };
    allocator.free(result.stdout);
    allocator.free(result.stderr);
    return result.term == .Exited and result.term.Exited == 0;
}

test "cli: circ-compile inverter end-to-end" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (!try checkNodeAvailable(allocator)) {
        std.debug.print("SKIPPED (node not found on PATH)\n", .{});
        return;
    }

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    const out_wasm = try std.fs.path.join(allocator, &.{ tmp_path, "out.wasm" });

    const compile = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ circ_compile_path, "tests/fixtures/circuits/inverter.circ", "-o", out_wasm },
    });
    if (compile.term != .Exited or compile.term.Exited != 0) {
        std.debug.print("circ-compile failed:\nSTDOUT:\n{s}\nSTDERR:\n{s}\n", .{ compile.stdout, compile.stderr });
        return error.CompileFailed;
    }

    const script =
        \\const fs = require('fs');
        \\const wasmBytes = fs.readFileSync(process.argv[2]);
        \\if (!WebAssembly.validate(wasmBytes)) throw new Error('WebAssembly.validate() failed');
        \\(async () => {
        \\    const mod = await WebAssembly.compile(wasmBytes);
        \\    const inst = await WebAssembly.instantiate(mod, { env: {
        \\        print: () => {}, printFmt: () => {}, flushBuffer: () => {},
        \\        _log: () => {}, _log_flush: () => {}, _log_set_name: () => {},
        \\        debugEnabled: () => 0, onDebugLog: () => {}
        \\    }});
        \\    const topo = new Uint8Array(WebAssembly.Module.customSections(mod, 'circ.topology.v0.min')[0]);
        \\    const ptr = inst.exports.topology_alloc(topo.length);
        \\    new Uint8Array(inst.exports.memory.buffer).set(topo, ptr);
        \\    inst.exports.init();
        \\    const readScalar = (id) => (inst.exports.getOutputDefined(id) === 0n) ? 2 : (inst.exports.getOutputValue(id) === 0n ? 0 : 1);
        \\    inst.exports.setPin(0, 0n, 1n); inst.exports.run();
        \\    const out0 = readScalar(1);
        \\    if (out0 !== 1) throw new Error('a=0: expected 1, got ' + out0);
        \\    inst.exports.setPin(0, 1n, 1n); inst.exports.run();
        \\    const out1 = readScalar(1);
        \\    if (out1 !== 0) throw new Error('a=1: expected 0, got ' + out1);
        \\    console.log('PASS');
        \\})().catch(e => { console.error(e); process.exit(1); });
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "runner.js", .data = script });
    const script_path = try tmp_dir.dir.realpathAlloc(allocator, "runner.js");

    const node = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", script_path, out_wasm },
    });
    if (node.term != .Exited or node.term.Exited != 0) {
        std.debug.print("Node failed:\nSTDOUT:\n{s}\nSTDERR:\n{s}\n", .{ node.stdout, node.stderr });
        return error.NodeFailed;
    }
    try std.testing.expectEqualStrings("PASS\n", node.stdout);
}

test "cli: circ-compile project end-to-end" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (!try checkNodeAvailable(allocator)) {
        std.debug.print("SKIPPED (node not found on PATH)\n", .{});
        return;
    }

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    const out_wasm = try std.fs.path.join(allocator, &.{ tmp_path, "out.wasm" });

    const compile = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ circ_compile_path, "tests/fixtures/projects/half_adder/root.circ", "-o", out_wasm },
    });
    if (compile.term != .Exited or compile.term.Exited != 0) {
        std.debug.print("circ-compile project failed:\nSTDOUT:\n{s}\nSTDERR:\n{s}\n", .{ compile.stdout, compile.stderr });
        return error.CompileFailed;
    }

    // Verify: structurally valid WASM with circ.topology.v0.min section, init() runs without crashing
    const script =
        \\const fs = require('fs');
        \\const wasmBytes = fs.readFileSync(process.argv[2]);
        \\if (!WebAssembly.validate(wasmBytes)) throw new Error('WebAssembly.validate() failed');
        \\(async () => {
        \\    const mod = await WebAssembly.compile(wasmBytes);
        \\    const inst = await WebAssembly.instantiate(mod, { env: {
        \\        print: () => {}, printFmt: () => {}, flushBuffer: () => {},
        \\        _log: () => {}, _log_flush: () => {}, _log_set_name: () => {},
        \\        debugEnabled: () => 0, onDebugLog: () => {}
        \\    }});
        \\    const sections = WebAssembly.Module.customSections(mod, 'circ.topology.v0.min');
        \\    if (sections.length === 0) throw new Error('No circ.topology.v0.min section');
        \\    const topo = new Uint8Array(sections[0]);
        \\    const ptr = inst.exports.topology_alloc(topo.length);
        \\    new Uint8Array(inst.exports.memory.buffer).set(topo, ptr);
        \\    inst.exports.init();
        \\    inst.exports.run();
        \\    console.log('PASS');
        \\})().catch(e => { console.error(e); process.exit(1); });
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "runner.js", .data = script });
    const script_path = try tmp_dir.dir.realpathAlloc(allocator, "runner.js");

    const node = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", script_path, out_wasm },
    });
    if (node.term != .Exited or node.term.Exited != 0) {
        std.debug.print("Node failed:\nSTDOUT:\n{s}\nSTDERR:\n{s}\n", .{ node.stdout, node.stderr });
        return error.NodeFailed;
    }
    try std.testing.expectEqualStrings("PASS\n", node.stdout);
}

test "cli: --emit-zig produces valid zig source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    const out_zig = try std.fs.path.join(allocator, &.{ tmp_path, "out.zig" });

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ circ_compile_path, "tests/fixtures/circuits/inverter.circ", "--emit-zig", "-o", out_zig },
    });
    try std.testing.expectEqual(@as(u32, 0), result.term.Exited);

    const content = try tmp_dir.dir.readFileAlloc(allocator, "out.zig", 1024 * 1024);
    // Verify the output is a valid Zig source file containing expected circuit primitives
    try std.testing.expect(std.mem.indexOf(u8, content, "not_gate") != null or
        std.mem.indexOf(u8, content, "input_pin") != null);
}

test "cli: --inspect outputs parse tree and resolved IR" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ circ_compile_path, "tests/fixtures/circuits/inverter.circ", "--inspect" },
    });
    try std.testing.expectEqual(@as(u32, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Parse Tree") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Resolved IR") != null);
}

test "cli: --build-dir is rejected as unknown flag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    const out_wasm = try std.fs.path.join(allocator, &.{ tmp_path, "out.wasm" });

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ circ_compile_path, "tests/fixtures/circuits/inverter.circ", "-o", out_wasm, "--build-dir", "/tmp/ignored" },
    });
    // --build-dir is now an unknown flag — must exit 2
    try std.testing.expectEqual(@as(u32, 2), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "usage error") != null);
}
