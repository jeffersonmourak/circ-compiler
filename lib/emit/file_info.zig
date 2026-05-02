const std = @import("std");
const ir = @import("ir_types");
const format = @import("file_info_format");
const Writer = @import("emit_writer").Writer;

pub const EmitOptions = struct {
    source_name: []const u8,
    compile_timestamp: []const u8,
    compiler_version: []const u8,
};

fn collectInputPins(allocator: std.mem.Allocator, module: *const ir.Module) ![]format.NamedPin {
    var pins: std.ArrayList(format.NamedPin) = .{};
    defer pins.deinit(allocator);
    for (module.inputs) |input_pin| {
        try pins.append(allocator, .{
            .component_id = input_pin.component.value,
            .name = input_pin.name,
        });
    }
    return pins.toOwnedSlice(allocator);
}

fn collectOutputPins(allocator: std.mem.Allocator, module: *const ir.Module) ![]format.NamedPin {
    var pins: std.ArrayList(format.NamedPin) = .{};
    defer pins.deinit(allocator);
    for (module.outputs) |output_pin| {
        try pins.append(allocator, .{
            .component_id = output_pin.driver.component.value,
            .name = output_pin.name,
        });
    }
    return pins.toOwnedSlice(allocator);
}

pub fn encodeFileInfoBlob(allocator: std.mem.Allocator, module: *const ir.Module, options: EmitOptions) ![]u8 {
    const inputs = try collectInputPins(allocator, module);
    defer allocator.free(inputs);
    const outputs = try collectOutputPins(allocator, module);
    defer allocator.free(outputs);

    const info: format.FileInfo = .{
        .file_id = module.file_id.value,
        .source_name = options.source_name,
        .compile_timestamp = options.compile_timestamp,
        .compiler_version = options.compiler_version,
        .component_count = @intCast(module.components.len),
        .connection_count = @intCast(module.connections.len),
        .inputs = inputs,
        .outputs = outputs,
    };
    return format.encodeFileInfo(allocator, info);
}

pub fn emitFileInfoConstants(allocator: std.mem.Allocator, module: *const ir.Module, options: EmitOptions) ![]u8 {
    const blob = try encodeFileInfoBlob(allocator, module, options);
    defer allocator.free(blob);

    var writer = Writer.init(allocator);
    defer writer.deinit();

    try writer.writeLine("const file_info_blob: []const u8 = &.{");
    writer.indent();

    var idx: usize = 0;
    while (idx < blob.len) {
        var line: std.ArrayList(u8) = .{};
        defer line.deinit(allocator);
        const line_writer = line.writer(allocator);

        var count: usize = 0;
        while (idx < blob.len and count < 16) : ({
            idx += 1;
            count += 1;
        }) {
            if (count > 0) try line_writer.writeAll(" ");
            try line_writer.print("{d},", .{blob[idx]});
        }
        try writer.writeLine(line.items);
    }

    writer.dedent();
    try writer.writeLine("};");
    return writer.toOwnedSlice();
}
