const std = @import("std");
const ir = @import("ir_types");
const Writer = @import("emit_writer").Writer;

pub const EmitOptions = struct {
    root_name: []const u8,
};

fn componentPathLeaf(allocator: std.mem.Allocator, component: ir.Component) ![]u8 {
    if (component.instance_name) |name| return allocator.dupe(u8, name);
    return std.fmt.allocPrint(allocator, "component_{d}", .{component.id.value});
}

pub fn emitDebugPathsConstants(allocator: std.mem.Allocator, module: *const ir.Module, options: EmitOptions) ![]u8 {
    var writer = Writer.init(allocator);
    defer writer.deinit();

    try writer.writeLine("const DebugPath = struct {");
    writer.indent();
    try writer.writeLine("component_id: u32,");
    try writer.writeLine("segments: []const []const u8,");
    writer.dedent();
    try writer.writeLine("};");
    try writer.writeLine("const debug_paths: []const DebugPath = &.{");
    writer.indent();

    const root_lit = try writer.zigStringLiteral(options.root_name);
    defer allocator.free(root_lit);

    for (module.components) |component| {
        const leaf = try componentPathLeaf(allocator, component);
        defer allocator.free(leaf);
        const leaf_lit = try writer.zigStringLiteral(leaf);
        defer allocator.free(leaf_lit);
        try writer.writeLineFmt(
            ".{{ .component_id = {d}, .segments = &.{{ {s}, {s} }} }},",
            .{ component.id.value, root_lit, leaf_lit },
        );
    }

    writer.dedent();
    try writer.writeLine("};");

    return writer.toOwnedSlice();
}
