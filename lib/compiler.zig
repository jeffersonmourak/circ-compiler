const std = @import("std");

const log = std.log.scoped(.log);

const translate = @import("syntax/translate.zig").translate;
const CParser = @import("syntax/CParser.zig").C_Parser;

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len != 2) {
        std.debug.print("Usage: {s} <input_file>\n", .{args[0]});
        return error.InvalidArguments;
    }

    const input_file = args[1];

    const input_file_content = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, input_file, 1024 * 1024);

    const parser = CParser.Parser_New();

    var cursor: c_int = 0;

    CParser.Parser_SetInput(parser, @ptrCast(input_file_content.ptr), @intCast(input_file_content.len));

    const tree = CParser.Parser_Parse(parser, &cursor, null);
    defer CParser.Parser_Delete(parser);
    defer CParser.ll_tree_free(tree);

    if (tree == null) {
        return error.ParsingFailed;
    }

    _ = try translate(std.heap.page_allocator, tree, 0);
}
