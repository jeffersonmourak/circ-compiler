const std = @import("std");
const format = @import("format");
const runtime_embed = @import("runtime_embed");

test "topology host protocol: inverter round-trip via Node" {
    const allocator = std.testing.allocator;

    // Check if node is on PATH. If not, skip the test.
    const node_path = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", "--version" },
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("SKIPPED (node not found on PATH)\n", .{});
            return;
        }
        return err;
    };
    defer {
        allocator.free(node_path.stdout);
        allocator.free(node_path.stderr);
    }
    if (node_path.term != .Exited or node_path.term.Exited != 0) {
        std.debug.print("SKIPPED (node execution failed)\n", .{});
        return;
    }

    var payload: std.ArrayList(u8) = .{};
    defer payload.deinit(allocator);

    // 1. Construct the topology bytes
    var topo: std.ArrayList(u8) = .{};
    defer topo.deinit(allocator);
    try topo.appendSlice(allocator, &format.MAGIC);
    try topo.append(allocator, format.VERSION);
    try topo.appendSlice(allocator, &[_]u8{2, 0, 0, 0}); // comp_count = 2
    try topo.appendSlice(allocator, &[_]u8{1, 0, 0, 0}); // conn_count = 1
    
    // Component 0: input_pin
    try topo.appendSlice(allocator, &[_]u8{0, 0, 0, 0});
    try topo.append(allocator, @intFromEnum(format.ComponentKind.input_pin));
    
    // Component 1: not_gate
    try topo.appendSlice(allocator, &[_]u8{1, 0, 0, 0});
    try topo.append(allocator, @intFromEnum(format.ComponentKind.not_gate));
    
    // Connection: from 0, to 1, port "in"
    try topo.appendSlice(allocator, &[_]u8{0, 0, 0, 0});
    try topo.appendSlice(allocator, &[_]u8{1, 0, 0, 0});
    try topo.append(allocator, @intFromEnum(format.PortName.in));

    const name = "circ.topology.v0.min";

    // 2. Construct the WASM custom section
    try payload.append(allocator, 0x00); // section id
    // Section length = name string length (LEB128) + name string + topology bytes length
    const name_len_leb = @as(u8, @intCast(name.len));
    const section_len = 1 + name.len + topo.items.len;
    try std.testing.expect(section_len < 128); // Ensure single-byte LEB128 for simplicity
    try payload.append(allocator, @as(u8, @intCast(section_len)));
    try payload.append(allocator, name_len_leb);
    try payload.appendSlice(allocator, name);
    try payload.appendSlice(allocator, topo.items);

    // 3. Append custom section to the embedded runtime WASM
    const runtime_wasm = runtime_embed.runtime_wasm;
    var combined_wasm: std.ArrayList(u8) = .{};
    defer combined_wasm.deinit(allocator);
    try combined_wasm.appendSlice(allocator, runtime_wasm);
    try combined_wasm.appendSlice(allocator, payload.items);

    // 4. Write to temp file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "combined.wasm", .data = combined_wasm.items });
    
    const wasm_path = try tmp_dir.dir.realpathAlloc(allocator, "combined.wasm");
    defer allocator.free(wasm_path);

    const script = 
        \\const fs = require('fs');
        \\const wasmBytes = fs.readFileSync(process.argv[2]);
        \\
        \\(async () => {
        \\    const mod = await WebAssembly.compile(wasmBytes);
        \\    const instance = await WebAssembly.instantiate(mod, { env: {
        \\        print: () => {}, printFmt: () => {}, flushBuffer: () => {},
        \\        _log: () => {}, _log_flush: () => {}, _log_set_name: () => {},
        \\        debugEnabled: () => 0,
        \\        onDebugLog: () => {}
        \\    } });
        \\    
        \\    const topoSections = WebAssembly.Module.customSections(mod, 'circ.topology.v0.min');
        \\    if (topoSections.length === 0) throw new Error("No circ.topology.v0.min section found");
        \\    
        \\    const topoBytes = new Uint8Array(topoSections[0]);
        \\    const ptr = instance.exports.topology_alloc(topoBytes.length);
        \\    new Uint8Array(instance.exports.memory.buffer).set(topoBytes, ptr);
        \\    
        \\    instance.exports.init();
        \\    
        \\    // Test 0 -> 1
        \\    instance.exports.setPin(0, 0);
        \\    instance.exports.run();
        \\    const out0 = instance.exports.getOutputState(1);
        \\    if (out0 !== 1) throw new Error("Expected 1, got " + out0);
        \\    
        \\    // Test 1 -> 0
        \\    instance.exports.setPin(0, 1);
        \\    instance.exports.run();
        \\    const out1 = instance.exports.getOutputState(1);
        \\    if (out1 !== 0) throw new Error("Expected 0, got " + out1);
        \\    
        \\    console.log("PASS");
        \\})().catch(e => {
        \\    console.error(e);
        \\    process.exit(1);
        \\});
    ;

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
        std.debug.print("Node execution failed!\nSTDOUT:\n{s}\nSTDERR:\n{s}\n", .{node_run.stdout, node_run.stderr});
        return error.NodeExecutionFailed;
    }
    
    try std.testing.expectEqualStrings("PASS\n", node_run.stdout);
}
