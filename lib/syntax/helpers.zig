const C_Parser = @import("CParser.zig").C_Parser;

pub fn getNodeChild(tree: [*c]C_Parser.ll_tree, node_id: C_Parser.ll_node_id, out_child: *C_Parser.ll_node_id) !void {
    if (!C_Parser.ll_tree_child(tree, node_id, out_child)) {
        return error.InvalidChild;
    }
}

pub const ChildrenIterator = struct {
    tree: [*c]C_Parser.ll_tree,
    parent: C_Parser.ll_node_id,
    index: c_int = 0,
    len: c_int,

    pub fn next(self: *ChildrenIterator) !?C_Parser.ll_node_id {
        if (self.index >= self.len) return null;

        var child: C_Parser.ll_node_id = undefined;
        if (!C_Parser.ll_tree_children_at(self.tree, self.parent, self.index, &child)) {
            return error.InvalidChildIndex;
        }
        self.index += 1;
        return child;
    }
};

pub fn iterateChildren(tree: [*c]C_Parser.ll_tree, node_id: C_Parser.ll_node_id) ChildrenIterator {
    return .{
        .tree = tree,
        .parent = node_id,
        .len = C_Parser.ll_tree_children_len(tree, node_id),
    };
}
