const std = @import("std");

const log = std.log.scoped(.log);

const C_Parser = @import("CParser.zig").C_Parser;

pub const getNodeChild = @import("helpers.zig").getNodeChild;
pub const iterateChildren = @import("helpers.zig").iterateChildren;

pub const DeclarationNode = @import("nodes/declaration.zig").DeclarationNode;
pub const translateDeclaration = @import("nodes/declaration.zig").translateDeclaration;

pub const StringNode = struct {
    text: []const u8,
};

pub const Node = union(enum) {
    declaration: DeclarationNode,
    string: StringNode,
};

fn translateRecursively(tree: [*c]C_Parser.ll_tree, node_id: C_Parser.ll_node_id, allocator: std.mem.Allocator) !void {
    switch (C_Parser.ll_tree_type(tree, node_id)) {
        C_Parser.LL_NODE_SEQUENCE => {
            var it = iterateChildren(tree, node_id);
            while (try it.next()) |child| {
                try translateRecursively(tree, child, allocator);
            }
        },
        C_Parser.LL_NODE_NODE => {
            const cName = C_Parser.ll_tree_name(tree, node_id);

            const name: []const u8 = std.mem.span(cName);

            if (std.mem.eql(u8, name, "Declaration")) {
                try translateDeclaration(tree, node_id, allocator);
            } else {
                if (std.mem.eql(u8, name, "ComponentType")) {} else {
                    std.debug.print("Node: {s}\n", .{cName});
                }

                var child: C_Parser.ll_node_id = undefined;
                try getNodeChild(tree, node_id, &child);
                try translateRecursively(tree, child, allocator);
            }
        },
        C_Parser.LL_NODE_ERROR => {
            const name = C_Parser.ll_tree_name(tree, node_id);
            std.debug.print("Error: {s}\n", .{name});
            var child: C_Parser.ll_node_id = undefined;
            try getNodeChild(tree, node_id, &child);
            try translateRecursively(tree, child, allocator);
        },
        C_Parser.LL_NODE_STRING => {
            const text = C_Parser.ll_tree_text(tree, node_id);
            std.debug.print("String: {s}\n", .{text});
            C_Parser.free(text);
        },
        else => {
            return error.InvalidNodeType;
        },
    }
}

pub fn translate(tree: [*c]C_Parser.ll_tree) !void {
    if (tree == null) {
        return error.ParsingFailed;
    }

    var root: C_Parser.ll_node_id = undefined;

    if (!C_Parser.ll_tree_root(tree, &root)) {
        return error.ParsingFailed;
    }

    var treeArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const treeAllocator = treeArena.allocator();
    defer treeArena.deinit();

    const pretty = C_Parser.ll_tree_pretty(tree, root);
    defer C_Parser.free(pretty);

    std.debug.print("Pretty: {s}\n", .{pretty});

    try translateRecursively(tree, root, treeAllocator);
}
