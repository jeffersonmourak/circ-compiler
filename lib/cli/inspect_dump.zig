const std = @import("std");

fn writeIndent(writer: anytype, depth: usize) !void {
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        try writer.writeAll("  ");
    }
}

fn writeSpan(writer: anytype, span: anytype) !void {
    try writer.print("[f{d}:{d}:{d}-{d}:{d}]", .{
        span.file_id,
        span.start_line,
        span.start_col,
        span.end_line,
        span.end_col,
    });
}

fn dumpSignalSource(writer: anytype, source: anytype, depth: usize) anyerror!void {
    switch (source) {
        .named => |named| {
            try writeIndent(writer, depth);
            try writer.print("NamedRef {s}.{s} ", .{ named.target.text, named.port.text });
            try writeSpan(writer, named.span);
            try writer.writeByte('\n');
        },
        .anonymous => |anon| {
            try writeIndent(writer, depth);
            try writer.writeAll("AnonymousComponent\n");
            try dumpComponent(writer, anon.*, depth + 1);
        },
        .indexed => |idx| {
            try writeIndent(writer, depth);
            try writer.print("Indexed bit={d}\n", .{idx.bit});
            try dumpSignalSource(writer, idx.source.*, depth + 1);
        },
        .sliced => |s| {
            try writeIndent(writer, depth);
            try writer.print("Sliced lo={d} hi={d}\n", .{ s.lo, s.hi });
            try dumpSignalSource(writer, s.source.*, depth + 1);
        },
        .concat => |c| {
            try writeIndent(writer, depth);
            try writer.print("Concat parts={d}\n", .{c.parts.len});
            for (c.parts) |part| try dumpSignalSource(writer, part, depth + 1);
        },
    }
}

fn dumpPortConnection(writer: anytype, conn: anytype, depth: usize) anyerror!void {
    try writeIndent(writer, depth);
    try writer.print("Port {s} ", .{conn.port.text});
    try writeSpan(writer, conn.span);
    try writer.writeByte('\n');
    try dumpSignalSource(writer, conn.value, depth + 1);
}

fn dumpComponent(writer: anytype, comp: anytype, depth: usize) anyerror!void {
    try writeIndent(writer, depth);
    try writer.print("Component type={s} instance=", .{comp.type_name.text});
    if (comp.instance_name) |name| {
        try writer.print("{s} ", .{name.text});
    } else {
        try writer.writeAll("<anonymous> ");
    }
    if (comp.width_args.len > 0) {
        try writer.writeAll("width_args=[");
        for (comp.width_args, 0..) |arg, idx| {
            if (idx > 0) try writer.writeAll(", ");
            switch (arg) {
                .literal => |n| try writer.print("{d}", .{n}),
                .parameter => |name| try writer.writeAll(name),
            }
        }
        try writer.writeAll("] ");
    }
    try writeSpan(writer, comp.span);
    try writer.writeByte('\n');
    for (comp.ports) |port| {
        try dumpPortConnection(writer, port, depth + 1);
    }
}

pub fn dumpAstFile(allocator: std.mem.Allocator, file: anytype) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.writeAll("File ");
    try writeSpan(writer, file.span);
    try writer.writeByte('\n');

    try writer.print("Imports ({d})\n", .{file.imports.len});
    for (file.imports) |imp| {
        try writer.print("  Import alias={s} path={s} ", .{ imp.alias.text, imp.path.text });
        try writeSpan(writer, imp.span);
        try writer.writeByte('\n');
    }

    try writer.print("Inputs ({d})\n", .{file.inputs.len});
    for (file.inputs) |input_decl| {
        try writer.writeAll("  Input ");
        for (input_decl.names, 0..) |name, idx| {
            if (idx > 0) try writer.writeAll(", ");
            try writer.writeAll(name.text);
        }
        try writer.writeByte(' ');
        try writeSpan(writer, input_decl.span);
        try writer.writeByte('\n');
    }

    try writer.print("Outputs ({d})\n", .{file.outputs.len});
    for (file.outputs) |output_decl| {
        try writer.print("  Output {s} ", .{output_decl.name.text});
        try writeSpan(writer, output_decl.span);
        try writer.writeByte('\n');
        try dumpSignalSource(writer, output_decl.value, 2);
    }

    try writer.print("Components ({d})\n", .{file.components.len});
    for (file.components) |component| {
        try dumpComponent(writer, component, 1);
    }

    return out.toOwnedSlice(allocator);
}

fn dumpComponentKind(writer: anytype, kind: anytype) !void {
    switch (kind) {
        .primitive => |primitive| try writer.print("primitive:{s}", .{@tagName(primitive)}),
        .sub_circuit_ref => |sub_ref| try writer.print("sub_circuit_ref:{s}", .{sub_ref.name}),
        .unresolved_name => |name| try writer.print("unresolved_name:{s}", .{name}),
        .slice => |s| try writer.print("slice:[{d}..{d})", .{ s.lo, s.hi }),
        .concat => try writer.writeAll("concat"),
        .memory => |m| try writer.print("{s}[W={d},A={d}]", .{ @tagName(m.mode), m.data_width, m.addr_width }),
    }
}

pub fn dumpIrModule(allocator: std.mem.Allocator, module: anytype) ![]u8 {
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
        try writer.print("  id={d} name={s} component={d}\n", .{
            input_pin.id.value,
            input_pin.name,
            input_pin.component.value,
        });
    }

    try writer.print("Outputs ({d})\n", .{module.outputs.len});
    for (module.outputs) |output_pin| {
        try writer.print("  id={d} name={s} driver={d}.{s}\n", .{
            output_pin.id.value,
            output_pin.name,
            output_pin.driver.component.value,
            output_pin.driver.port,
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
        try writer.print(" width={d}", .{component.width});
        try writer.writeByte('\n');
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
