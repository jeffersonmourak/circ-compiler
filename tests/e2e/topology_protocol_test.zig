const std = @import("std");
const format = @import("format");
const runtime_embed = @import("runtime_embed");

/// True when the Node-driven tests should run. Skips (with a message)
/// under SKIP_WASM_E2E=1 or when `node` is not on PATH.
fn nodeAvailable(allocator: std.mem.Allocator) !bool {
    // CI environments using zig 0.15.1 cross-compiled wasm32 produce a
    // runtime that hangs in init() somewhere on Linux Node — runtime_initialized
    // never flips to true and every subsequent export call returns the
    // .undefined sentinel. Repros only on Linux Node runtimes; works on
    // macOS Node 22 and 24. Skipped under SKIP_WASM_E2E=1 (set by
    // .github/workflows/pr-tests.yml) until the root cause is found.
    if (std.process.getEnvVarOwned(allocator, "SKIP_WASM_E2E") catch null) |val| {
        defer allocator.free(val);
        if (std.mem.eql(u8, val, "1")) {
            std.debug.print("SKIPPED (SKIP_WASM_E2E=1 set in environment)\n", .{});
            return false;
        }
    }

    const node_path = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", "--version" },
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("SKIPPED (node not found on PATH)\n", .{});
            return false;
        }
        return err;
    };
    defer {
        allocator.free(node_path.stdout);
        allocator.free(node_path.stderr);
    }
    if (node_path.term != .Exited or node_path.term.Exited != 0) {
        std.debug.print("SKIPPED (node execution failed)\n", .{});
        return false;
    }
    return true;
}

/// Splices `topo` onto the embedded runtime as the `.min` custom section,
/// writes it and `script` into a temp dir, runs `node script combined.wasm`,
/// and expects the script to print exactly `PASS`.
fn runHostScript(allocator: std.mem.Allocator, topo: []const u8, script: []const u8) !void {
    var payload: std.ArrayList(u8) = .{};
    defer payload.deinit(allocator);

    const name = "circ.topology.v0.min";
    try payload.append(allocator, 0x00); // custom section id
    // Section length = name string length (LEB128) + name string + topology bytes length
    const name_len_leb = @as(u8, @intCast(name.len));
    const section_len = 1 + name.len + topo.len;
    try std.testing.expect(section_len < 128); // single-byte LEB128 for simplicity
    try payload.append(allocator, @as(u8, @intCast(section_len)));
    try payload.append(allocator, name_len_leb);
    try payload.appendSlice(allocator, name);
    try payload.appendSlice(allocator, topo);

    var combined_wasm: std.ArrayList(u8) = .{};
    defer combined_wasm.deinit(allocator);
    try combined_wasm.appendSlice(allocator, runtime_embed.runtime_wasm);
    try combined_wasm.appendSlice(allocator, payload.items);

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "combined.wasm", .data = combined_wasm.items });
    const wasm_path = try tmp_dir.dir.realpathAlloc(allocator, "combined.wasm");
    defer allocator.free(wasm_path);

    try tmp_dir.dir.writeFile(.{ .sub_path = "runner.js", .data = script });
    const script_path = try tmp_dir.dir.realpathAlloc(allocator, "runner.js");
    defer allocator.free(script_path);

    const node_run = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", script_path, wasm_path },
    });
    defer {
        allocator.free(node_run.stdout);
        allocator.free(node_run.stderr);
    }

    if (node_run.term != .Exited or node_run.term.Exited != 0) {
        std.debug.print("Node execution failed!\nSTDOUT:\n{s}\nSTDERR:\n{s}\n", .{ node_run.stdout, node_run.stderr });
        return error.NodeExecutionFailed;
    }

    try std.testing.expectEqualStrings("PASS\n", node_run.stdout);
}

// Shared script prologue: error plumbing, instantiation, topology upload.
// Top-level try wraps the sync requires + readFileSync so any error there
// surfaces on stderr instead of getting swallowed. The async IIFE handles
// its own rejections via .catch.
const script_prologue =
    \\process.on('uncaughtException', e => { console.error('UNCAUGHT:', e && e.stack || e); process.exit(2); });
    \\process.on('unhandledRejection', e => { console.error('UNHANDLED:', e && e.stack || e); process.exit(3); });
    \\try {
    \\    const fs = require('fs');
    \\    const wasmBytes = fs.readFileSync(process.argv[2]);
    \\    (async () => {
    \\        const mod = await WebAssembly.compile(wasmBytes);
    \\        const instance = await WebAssembly.instantiate(mod, { env: {
    \\            print: () => {}, printFmt: () => {}, flushBuffer: () => {},
    \\            _log: () => {}, _log_flush: () => {}, _log_set_name: () => {},
    \\            debugEnabled: () => 0,
    \\            onDebugLog: () => {}
    \\        } });
    \\        const topoSections = WebAssembly.Module.customSections(mod, 'circ.topology.v0.min');
    \\        if (topoSections.length === 0) throw new Error("No circ.topology.v0.min section found");
    \\        const topoBytes = new Uint8Array(topoSections[0]);
    \\        const ptr = instance.exports.topology_alloc(topoBytes.length);
    \\        new Uint8Array(instance.exports.memory.buffer).set(topoBytes, ptr);
    \\        instance.exports.init();
    \\        const x = instance.exports;
    \\        const expect = (label, got, want) => { if (got !== want) throw new Error(label + ": expected " + want + ", got " + got); };
    \\
;

const script_epilogue =
    \\        console.log("PASS");
    \\    })().catch(e => { console.error('REJECTED:', e && e.stack || e); process.exit(1); });
    \\} catch (e) {
    \\    console.error('SYNC:', e && e.stack || e);
    \\    process.exit(4);
    \\}
    \\
;

test "topology host protocol: inverter round-trip via Node" {
    const allocator = std.testing.allocator;
    if (!try nodeAvailable(allocator)) return;

    var topo: std.ArrayList(u8) = .{};
    defer topo.deinit(allocator);
    try topo.appendSlice(allocator, &format.MAGIC);
    try topo.append(allocator, format.VERSION);
    try topo.appendSlice(allocator, &[_]u8{ 2, 0, 0, 0 }); // comp_count = 2
    try topo.appendSlice(allocator, &[_]u8{ 1, 0, 0, 0 }); // conn_count = 1

    // Component 0: input_pin (width=1)
    try topo.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
    try topo.append(allocator, @intFromEnum(format.ComponentKind.input_pin));
    try topo.append(allocator, 1);

    // Component 1: not_gate (width=1)
    try topo.appendSlice(allocator, &[_]u8{ 1, 0, 0, 0 });
    try topo.append(allocator, @intFromEnum(format.ComponentKind.not_gate));
    try topo.append(allocator, 1);

    // Connection: from 0, to 1, port "in"
    try topo.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0 });
    try topo.appendSlice(allocator, &[_]u8{ 1, 0, 0, 0 });
    try topo.append(allocator, @intFromEnum(format.PortName.in));

    const script = script_prologue ++
        \\        const readScalar = (id) => (x.getOutputDefined(id) === 0n) ? 2 : (x.getOutputValue(id) === 0n ? 0 : 1);
        \\        const initialOut = readScalar(1);
        \\        x.setPin(0, 0n, 1n);
        \\        const afterSetLow = readScalar(1);
        \\        x.run();
        \\        const out0 = readScalar(1);
        \\        if (out0 !== 1) throw new Error("Expected 1 (low->high via NOT), got " + out0 + " | initial=" + initialOut + " | after_setPin(0,0)=" + afterSetLow);
        \\        x.setPin(0, 1n, 1n);
        \\        x.run();
        \\        const out1 = readScalar(1);
        \\        if (out1 !== 0) throw new Error("Expected 0 (high->low via NOT), got " + out1);
        \\
    ++ script_epilogue;

    try runHostScript(allocator, topo.items, script);
}

test "topology host protocol: memory exports over a hand-built v03 payload" {
    const allocator = std.testing.allocator;
    if (!try nodeAvailable(allocator)) return;

    var topo: std.ArrayList(u8) = .{};
    defer topo.deinit(allocator);
    try topo.appendSlice(allocator, &format.MAGIC);
    try topo.append(allocator, format.VERSION);
    try topo.appendSlice(allocator, &[_]u8{ 5, 0, 0, 0 }); // comp_count = 5
    try topo.appendSlice(allocator, &[_]u8{ 2, 0, 0, 0 }); // conn_count = 2

    // 0: input_pin[4]; 1: rom[8,4]; 2: output_pin[8]; 3: rom[12,2] (bpw 2, so -2 is reachable);
    // 4: rom[4,2] (padding bits, so -3 is reachable).
    try topo.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0, @intFromEnum(format.ComponentKind.input_pin), 4 });
    try topo.appendSlice(allocator, &[_]u8{ 1, 0, 0, 0, @intFromEnum(format.ComponentKind.rom), 8, 4 });
    try topo.appendSlice(allocator, &[_]u8{ 2, 0, 0, 0, @intFromEnum(format.ComponentKind.output_pin), 8 });
    try topo.appendSlice(allocator, &[_]u8{ 3, 0, 0, 0, @intFromEnum(format.ComponentKind.rom), 12, 2 });
    try topo.appendSlice(allocator, &[_]u8{ 4, 0, 0, 0, @intFromEnum(format.ComponentKind.rom), 4, 2 });
    // 0 -> 1.addr, 1 -> 2.in
    try topo.appendSlice(allocator, &[_]u8{ 0, 0, 0, 0, 1, 0, 0, 0, @intFromEnum(format.PortName.addr) });
    try topo.appendSlice(allocator, &[_]u8{ 1, 0, 0, 0, 2, 0, 0, 0, @intFromEnum(format.PortName.in) });

    const script = script_prologue ++
        \\        for (const name of ["getMemInfo","memBuffer","memLoad","memStore","memClear","setMemWord","getMemValue","getMemDefined"]) {
        \\            if (typeof x[name] !== "function") throw new Error("missing export " + name);
        \\        }
        \\        // Memory views must be re-taken after memBuffer: allocation may grow linear memory.
        \\        const view = () => new Uint8Array(x.memory.buffer);
        \\        expect("getMemInfo(1)", x.getMemInfo(1), (8 << 16) | (8 << 8) | 4);
        \\        expect("getMemInfo(3)", x.getMemInfo(3), (8 << 16) | (12 << 8) | 2);
        \\        expect("getMemInfo(0)", x.getMemInfo(0), -1);
        \\        expect("getMemInfo(99)", x.getMemInfo(99), -1);
        \\        expect("memLoad before memBuffer", x.memLoad(1, 16), -6);
        \\        expect("memStore before memBuffer", x.memStore(1), -6);
        \\        const p1 = x.memBuffer(1);
        \\        expect("memBuffer twice is stable", x.memBuffer(1), p1);
        \\        expect("memLoad oversize", x.memLoad(1, 17), -5);
        \\        expect("memLoad negative", x.memLoad(1, -1), -5);
        \\        const p3 = x.memBuffer(3);
        \\        expect("memLoad odd length on bpw=2", x.memLoad(3, 3), -2);
        \\        const p4 = x.memBuffer(4);
        \\        view()[p4] = 0x1f;
        \\        expect("memLoad padding bits on W=4", x.memLoad(4, 1), -3);
        \\        expect("setMemWord out of range", x.setMemWord(1, 16, 0n, 0n), -7);
        \\        expect("setMemWord negative", x.setMemWord(1, -1, 0n, 0n), -7);
        \\        expect("setMemWord on non-memory", x.setMemWord(2, 0, 0n, 0n), -1);
        \\        // Load 16 words 0x00, 0x11, ..., 0xff and read cell 3 through the circuit.
        \\        const v = view();
        \\        for (let i = 0; i < 16; i++) v[p1 + i] = i * 0x11;
        \\        expect("memLoad ok", x.memLoad(1, 16), 0);
        \\        x.setPin(0, 3n, 0xfn);
        \\        expect("out value after load", x.getOutputValue(2), 0x33n);
        \\        expect("out defined after load", x.getOutputDefined(2), 0xffn);
        \\        // A host write to the presented cell resyncs out without run().
        \\        expect("setMemWord ok", x.setMemWord(1, 3, 0x77n, 0xffn), 0);
        \\        expect("out after setMemWord", x.getOutputValue(2), 0x77n);
        \\        expect("getMemValue", x.getMemValue(1, 3), 0x77n);
        \\        expect("getMemDefined", x.getMemDefined(1, 3), 0xffn);
        \\        expect("getMemValue out of range", x.getMemValue(1, 16), 0n);
        \\        expect("getMemValue non-memory", x.getMemValue(0, 0), 0n);
        \\        expect("memClear ok", x.memClear(1), 0);
        \\        expect("out undefined after clear", x.getOutputDefined(2), 0n);
        \\        expect("cell undefined after clear", x.getMemDefined(1, 3), 0n);
        \\        // Store writes value & defined: 0xab with mask 0x0f exports as 0x0b.
        \\        expect("setMemWord partial", x.setMemWord(1, 5, 0xabn, 0x0fn), 0);
        \\        expect("memStore bytes", x.memStore(1), 16);
        \\        const stored = view().slice(p1, p1 + 16);
        \\        expect("stored[5]", stored[5], 0x0b);
        \\        expect("stored[3]", stored[3], 0);
        \\        expect("memClear non-memory", x.memClear(0), -1);
        \\
    ++ script_epilogue;

    try runHostScript(allocator, topo.items, script);
}
