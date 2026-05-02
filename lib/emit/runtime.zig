const std = @import("std");
const ir = @import("ir_types");
const Writer = @import("emit_writer").Writer;

fn emitU32Array(writer: *Writer, comptime name: []const u8, values: []const u32) !void {
    try writer.writeLineFmt("const {s}: []const u32 = &.{{", .{name});
    writer.indent();
    for (values) |value| {
        try writer.writeLineFmt("{d},", .{value});
    }
    writer.dedent();
    try writer.writeLine("};");
}

fn collectInputComponentIds(allocator: std.mem.Allocator, module: *const ir.Module) ![]u32 {
    var out: std.ArrayList(u32) = .{};
    defer out.deinit(allocator);
    for (module.inputs) |input_pin| {
        try out.append(allocator, input_pin.component.value);
    }
    return out.toOwnedSlice(allocator);
}

fn collectOutputComponentIds(allocator: std.mem.Allocator, module: *const ir.Module) ![]u32 {
    var out: std.ArrayList(u32) = .{};
    defer out.deinit(allocator);
    for (module.outputs) |output_pin| {
        try out.append(allocator, output_pin.driver.component.value);
    }
    return out.toOwnedSlice(allocator);
}

pub fn emitRuntimeExports(allocator: std.mem.Allocator, module: *const ir.Module) ![]u8 {
    const input_ids = try collectInputComponentIds(allocator, module);
    defer allocator.free(input_ids);
    const output_ids = try collectOutputComponentIds(allocator, module);
    defer allocator.free(output_ids);

    var writer = Writer.init(allocator);
    defer writer.deinit();

    try writer.writeLine("const PtrLen = extern struct { ptr: ?[*]const u8, len: usize };");
    try writer.writeLineFmt("const expected_component_count: usize = {d};", .{module.components.len});
    try emitU32Array(&writer, "input_component_ids", input_ids);
    try emitU32Array(&writer, "output_component_ids", output_ids);
    try writer.writeLine("var gpa = std.heap.wasm_allocator;");
    try writer.writeLine("var runtime_initialized: bool = false;");
    try writer.writeLine("var runtime_circuit: engine.Circuit = undefined;");
    try writer.writeLine("var component_table: []const *engine.Component = &.{};");
    try writer.writeLine("");
    try writer.writeLine("fn emptyPtrLen() PtrLen {");
    writer.indent();
    try writer.writeLine("return .{ .ptr = null, .len = 0 };");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("fn containsId(list: []const u32, id: u32) bool {");
    writer.indent();
    try writer.writeLine("for (list) |candidate| {");
    writer.indent();
    try writer.writeLine("if (candidate == id) return true;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("return false;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("fn bufferFromStaticBytes(bytes: []const u8) PtrLen {");
    writer.indent();
    try writer.writeLine("if (bytes.len == 0) return emptyPtrLen();");
    try writer.writeLine("const buffer = gpa.alloc(u8, bytes.len) catch return emptyPtrLen();");
    try writer.writeLine("std.mem.copyForwards(u8, buffer, bytes);");
    try writer.writeLine("return .{ .ptr = buffer.ptr, .len = buffer.len };");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn init() void {");
    writer.indent();
    try writer.writeLine("if (runtime_initialized) return;");
    try writer.writeLine("runtime_circuit = engine.Circuit.init() catch return;");
    try writer.writeLine("_ = buildCircuit(&runtime_circuit) catch {");
    writer.indent();
    try writer.writeLine("runtime_circuit.deinit();");
    try writer.writeLine("return;");
    writer.dedent();
    try writer.writeLine("};");
    try writer.writeLine("component_table = runtime_circuit.nodes.items;");
    try writer.writeLine("if (component_table.len != expected_component_count) {");
    writer.indent();
    try writer.writeLine("runtime_circuit.deinit();");
    try writer.writeLine("component_table = &.{};");
    try writer.writeLine("return;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("runtime_initialized = true;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn deinit() void {");
    writer.indent();
    try writer.writeLine("if (!runtime_initialized) return;");
    try writer.writeLine("runtime_circuit.deinit();");
    try writer.writeLine("component_table = &.{};");
    try writer.writeLine("runtime_initialized = false;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn reset() void {");
    writer.indent();
    try writer.writeLine("if (runtime_initialized) deinit();");
    try writer.writeLine("init();");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn run() void {");
    writer.indent();
    try writer.writeLine("if (!runtime_initialized) return;");
    try writer.writeLine("runtime_circuit.propagate() catch return;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn stop() void {");
    writer.indent();
    try writer.writeLine("// v0 no-op; retained for forward-compatible runtime API shape.");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn setPin(component_id: i32, state: i32) void {");
    writer.indent();
    try writer.writeLine("if (!runtime_initialized) return;");
    try writer.writeLine("if (component_id < 0) return;");
    try writer.writeLine("const id: u32 = @intCast(component_id);");
    try writer.writeLine("if (id >= component_table.len) return;");
    try writer.writeLine("if (!containsId(input_component_ids, id)) return;");
    try writer.writeLine("runtime_circuit.propagateEvent(component_table[id], engine.State.fromInt(state)) catch return;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn getOutputState(component_id: i32) i32 {");
    writer.indent();
    try writer.writeLine("if (!runtime_initialized) return 2;");
    try writer.writeLine("if (component_id < 0) return 2;");
    try writer.writeLine("const id: u32 = @intCast(component_id);");
    try writer.writeLine("if (id >= component_table.len) return 2;");
    try writer.writeLine("if (!containsId(output_component_ids, id)) return 2;");
    try writer.writeLine("return engine.State.toInt(component_table[id].output_state);");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn getStateSnapshot() callconv(.c) PtrLen {");
    writer.indent();
    try writer.writeLine("if (!runtime_initialized) return emptyPtrLen();");
    try writer.writeLine("const encoded = runtime_circuit.encodeState() catch return emptyPtrLen();");
    try writer.writeLine("return .{ .ptr = encoded.ptr, .len = encoded.len };");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn getTopology() callconv(.c) PtrLen {");
    writer.indent();
    try writer.writeLine("return bufferFromStaticBytes(topology_blob);");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn getPendingEvents() callconv(.c) PtrLen {");
    writer.indent();
    try writer.writeLine("const empty_pending: []const u8 = &.{};");
    try writer.writeLine("return bufferFromStaticBytes(empty_pending);");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn getFileInfo() callconv(.c) PtrLen {");
    writer.indent();
    try writer.writeLine("return .{ .ptr = file_info_blob.ptr, .len = file_info_blob.len };");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn freeBuffer(ptr: ?[*]const u8, len: usize) void {");
    writer.indent();
    try writer.writeLine("if (len == 0) return;");
    try writer.writeLine("const non_null = ptr orelse return;");
    try writer.writeLine("const mutable: [*]u8 = @constCast(non_null);");
    try writer.writeLine("gpa.free(mutable[0..len]);");
    writer.dedent();
    try writer.writeLine("}");

    return writer.toOwnedSlice();
}
