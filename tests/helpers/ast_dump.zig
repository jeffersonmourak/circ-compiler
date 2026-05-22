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

fn writeWidth(writer: anytype, width: anytype) !void {
    if (width) |w| {
        switch (w) {
            .literal => |n| try writer.print(" width=[{d}]", .{n}),
            .parameter => |name| try writer.print(" width=[{s}]", .{name}),
        }
    }
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
            try writer.print("Indexed bit={d} ", .{idx.bit});
            try writeSpan(writer, idx.span);
            try writer.writeByte('\n');
            try dumpSignalSource(writer, idx.source.*, depth + 1);
        },
        .sliced => |s| {
            try writeIndent(writer, depth);
            try writer.print("Sliced lo={d} hi={d} ", .{ s.lo, s.hi });
            try writeSpan(writer, s.span);
            try writer.writeByte('\n');
            try dumpSignalSource(writer, s.source.*, depth + 1);
        },
        .concat => |c| {
            try writeIndent(writer, depth);
            try writer.print("Concat parts={d} ", .{c.parts.len});
            try writeSpan(writer, c.span);
            try writer.writeByte('\n');
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
    try writer.print("Component type={s}", .{comp.type_name.text});
    try writeWidth(writer, comp.type_name.width);
    try writer.writeAll(" instance=");
    if (comp.instance_name) |name| {
        try writer.print("{s}", .{name.text});
        try writeWidth(writer, name.width);
        try writer.writeByte(' ');
    } else {
        try writer.writeAll("<anonymous> ");
    }
    if (comp.width_args.len > 0) {
        try writer.writeAll("width_args=[");
        for (comp.width_args, 0..) |w, idx| {
            if (idx > 0) try writer.writeAll(", ");
            switch (w) {
                .literal => |n| try writer.print("{d}", .{n}),
                .parameter => |name| try writer.print("{s}", .{name}),
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

pub fn dumpFile(allocator: std.mem.Allocator, file: anytype) ![]u8 {
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
        var idx: usize = 0;
        while (idx < input_decl.names.len) : (idx += 1) {
            if (idx > 0) try writer.writeAll(", ");
            try writer.print("{s}", .{input_decl.names[idx].text});
            try writeWidth(writer, input_decl.names[idx].width);
        }
        try writer.writeByte(' ');
        if (input_decl.parameters.len > 0) {
            try writer.writeAll("params=<");
            for (input_decl.parameters, 0..) |p, pidx| {
                if (pidx > 0) try writer.writeAll(", ");
                try writer.print("{s}", .{p.text});
            }
            try writer.writeAll("> ");
        }
        try writeSpan(writer, input_decl.span);
        try writer.writeByte('\n');
    }

    try writer.print("Outputs ({d})\n", .{file.outputs.len});
    for (file.outputs) |output_decl| {
        try writer.print("  Output {s}", .{output_decl.name.text});
        try writeWidth(writer, output_decl.name.width);
        try writer.writeByte(' ');
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
