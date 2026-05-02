const std = @import("std");
const builtins = @import("builtins");
const translate = @import("translate");

fn countInputPins(file: translate.Ast.File) usize {
    var n: usize = 0;
    for (file.inputs) |decl| n += decl.names.len;
    return n;
}

test "built-in embed table covers or nand nor xor xnor with non-empty sources" {
    const expected = [_][]const u8{ "or", "nand", "nor", "xor", "xnor" };
    outer: for (expected) |needle| {
        for (builtins.table) |entry| {
            if (std.mem.eql(u8, entry.name.slice(), needle)) {
                try std.testing.expect(entry.source.len > 0);
                continue :outer;
            }
        }
        return error.MissingBuiltinEmbed;
    }
    try std.testing.expectEqual(@as(usize, expected.len), builtins.table.len);
}

test "built-in sources parse with inputs, outputs, and component instances" {
    for (builtins.table) |entry| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const ast_file = try translate.parseSource(allocator, 0, entry.source);
        try std.testing.expect(countInputPins(ast_file) >= 1);
        try std.testing.expect(ast_file.outputs.len >= 1);
        try std.testing.expect(ast_file.components.len >= 1);
    }
}
