const std = @import("std");
const ir = @import("ir_types");
const Writer = @import("emit_writer").Writer;

fn componentVarName(allocator: std.mem.Allocator, writer: *Writer, component: ir.Component) ![]u8 {
    if (component.instance_name) |instance_name| {
        const escaped = try writer.escapeIdentifier(instance_name);
        defer allocator.free(escaped);
        return std.fmt.allocPrint(allocator, "comp_{s}_{d}", .{ escaped, component.id.value });
    }
    return std.fmt.allocPrint(allocator, "comp_{d}", .{component.id.value});
}

fn primitiveExpr(kind: ir.PrimitiveKind) []const u8 {
    return switch (kind) {
        .and_gate => ".{ .and_gate = .{} }",
        .not_gate => ".{ .not_gate = .{} }",
        .wire => ".{ .wire = .{} }",
        .led => ".{ .led = .{} }",
        .input_pin => ".{ .input_pin_gate = .{} }",
        .output_pin => ".{ .output_pin = .{} }",
    };
}

fn fieldName(allocator: std.mem.Allocator, writer: *Writer, prefix: []const u8, raw: []const u8) ![]u8 {
    const escaped = try writer.escapeIdentifier(raw);
    defer allocator.free(escaped);
    return std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, escaped });
}

fn findOutputComponentId(module: *const ir.Module, output_name: []const u8) ?ir.ComponentId {
    for (module.components) |component| {
        if (component.instance_name) |name| {
            if (!std.mem.eql(u8, name, output_name)) continue;
            const primitive = switch (component.kind) {
                .primitive => |value| value,
                else => continue,
            };
            if (primitive == .output_pin) return component.id;
        }
    }
    return null;
}

fn findComponentById(module: *const ir.Module, id: ir.ComponentId) ?ir.Component {
    for (module.components) |component| {
        if (component.id.value == id.value) return component;
    }
    return null;
}

pub fn emitBuildFunction(allocator: std.mem.Allocator, module: *const ir.Module) ![]u8 {
    var writer = Writer.init(allocator);
    defer writer.deinit();

    try writer.writeLine("fn buildCircuit(circuit: *engine.Circuit) !struct {");
    writer.indent();
    for (module.inputs) |input_pin| {
        const field = try fieldName(allocator, &writer, "input", input_pin.name);
        defer allocator.free(field);
        try writer.writeLineFmt("{s}: *engine.Component,", .{field});
    }
    for (module.outputs) |output_pin| {
        const field = try fieldName(allocator, &writer, "output", output_pin.name);
        defer allocator.free(field);
        try writer.writeLineFmt("{s}: *engine.Component,", .{field});
    }
    writer.dedent();
    try writer.writeLine("} {");
    writer.indent();

    for (module.components) |component| {
        const var_name = try componentVarName(allocator, &writer, component);
        defer allocator.free(var_name);
        const expr = switch (component.kind) {
            .primitive => |primitive| primitiveExpr(primitive),
            .sub_circuit_ref => return error.UnsupportedSubCircuitInPhase4,
            .unresolved_name => return error.UnresolvedComponentName,
        };
        try writer.writeLineFmt("const {s} = try circuit.createComponent({s});", .{ var_name, expr });
    }

    for (module.connections) |connection| {
        const from_component = findComponentById(module, connection.from.component) orelse return error.InvalidFromComponentId;
        const from_var = try componentVarName(allocator, &writer, from_component);
        defer allocator.free(from_var);
        const to_component = findComponentById(module, connection.to.component) orelse return error.InvalidToComponentId;
        const to_var = try componentVarName(allocator, &writer, to_component);
        defer allocator.free(to_var);
        const from_port = try writer.zigStringLiteral(connection.from.port);
        defer allocator.free(from_port);
        const to_port = try writer.zigStringLiteral(connection.to.port);
        defer allocator.free(to_port);
        try writer.writeLineFmt(
            "try circuit.connect({s}.port({s}), {s}.port({s}));",
            .{ from_var, from_port, to_var, to_port },
        );
    }

    try writer.writeLine("return .{");
    writer.indent();
    for (module.inputs) |input_pin| {
        const field = try fieldName(allocator, &writer, "input", input_pin.name);
        defer allocator.free(field);
        const input_component = findComponentById(module, input_pin.component) orelse return error.InvalidInputComponentId;
        const var_name = try componentVarName(allocator, &writer, input_component);
        defer allocator.free(var_name);
        try writer.writeLineFmt(".{s} = {s},", .{ field, var_name });
    }
    for (module.outputs) |output_pin| {
        const field = try fieldName(allocator, &writer, "output", output_pin.name);
        defer allocator.free(field);
        const output_component_id = findOutputComponentId(module, output_pin.name) orelse return error.MissingOutputComponent;
        const output_component = findComponentById(module, output_component_id) orelse return error.InvalidOutputComponentId;
        const output_component_var = try componentVarName(allocator, &writer, output_component);
        defer allocator.free(output_component_var);
        try writer.writeLineFmt(".{s} = {s},", .{ field, output_component_var });
    }
    writer.dedent();
    try writer.writeLine("};");
    writer.dedent();
    try writer.writeLine("}");

    return writer.toOwnedSlice();
}
