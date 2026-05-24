const std = @import("std");

fn writeIndent(writer: anytype, depth: usize) !void {
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        try writer.writeAll("  ");
    }
}

fn dumpComponentKind(writer: anytype, kind: anytype) !void {
    switch (kind) {
        .primitive => |primitive| try writer.print("primitive:{s}", .{@tagName(primitive)}),
        .sub_circuit_ref => |sub_ref| try writer.print("sub_circuit_ref:{s}", .{sub_ref.name}),
        .unresolved_name => |name| try writer.print("unresolved_name:{s}", .{name}),
        .slice => |s| try writer.print("slice:[{d}..{d})", .{ s.lo, s.hi }),
        .concat => try writer.writeAll("concat"),
    }
}

pub fn dumpModule(allocator: std.mem.Allocator, module: anytype) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.print("Module file_id={d}\n", .{module.file_id.value});

    try writer.print("Imports ({d})\n", .{module.imports.len});
    for (module.imports) |imp| {
        try writer.print("  alias={s} path={s}\n", .{ imp.alias, imp.path });
    }

    try writer.print("Inputs ({d})\n", .{module.inputs.len});
    for (module.inputs) |input_pin| {
        try writer.print("  id={d} name={s} component={d} width={d}\n", .{
            input_pin.id.value,
            input_pin.name,
            input_pin.component.value,
            input_pin.width,
        });
    }

    try writer.print("Outputs ({d})\n", .{module.outputs.len});
    for (module.outputs) |output_pin| {
        try writer.print("  id={d} name={s} driver={d}.{s} width={d}\n", .{
            output_pin.id.value,
            output_pin.name,
            output_pin.driver.component.value,
            output_pin.driver.port,
            output_pin.width,
        });
    }

    try writer.print("Components ({d})\n", .{module.components.len});
    for (module.components) |component| {
        try writeIndent(writer, 1);
        try writer.print("id={d} name=", .{component.id.value});
        if (component.instance_name) |name| {
            try writer.print("{s} kind=", .{name});
        } else {
            try writer.writeAll("<none> kind=");
        }
        try dumpComponentKind(writer, component.kind);
        try writer.print(" width={d}\n", .{component.width});
    }

    try writer.print("Connections ({d})\n", .{module.connections.len});
    for (module.connections) |connection| {
        try writer.print("  {d}.{s} -> {d}.{s}\n", .{
            connection.from.component.value,
            connection.from.port,
            connection.to.component.value,
            connection.to.port,
        });
    }

    return out.toOwnedSlice(allocator);
}
