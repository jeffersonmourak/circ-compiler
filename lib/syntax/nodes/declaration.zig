const std = @import("std");

const log = std.log.scoped(.log);

const C_Parser = @import("../CParser.zig").C_Parser;

pub const getNodeChild = @import("../helpers.zig").getNodeChild;
pub const iterateChildren = @import("../helpers.zig").iterateChildren;

pub const DeclarationType = enum {
    input,
    output,
    component,
};

pub const DeclarationNode = struct { type: DeclarationType, name: []const u8 };

pub fn readIdentifier(tree: [*c]C_Parser.ll_tree, nodeId: C_Parser.ll_node_id) ![]const u8 {
    var child: C_Parser.ll_node_id = undefined;
    try getNodeChild(tree, nodeId, &child);

    if (C_Parser.ll_tree_type(tree, child) != C_Parser.LL_NODE_STRING) {
        return error.InvalidChildType;
    }

    const identifierName = C_Parser.ll_tree_text(tree, child);
    const identifier: []const u8 = std.mem.span(identifierName);

    return identifier;
}

pub fn translateInputDeclaration(tree: [*c]C_Parser.ll_tree, nodeId: C_Parser.ll_node_id, allocator: std.mem.Allocator) !std.ArrayList(DeclarationNode) {
    var child: C_Parser.ll_node_id = undefined;
    try getNodeChild(tree, nodeId, &child);

    if (C_Parser.ll_tree_type(tree, child) != C_Parser.LL_NODE_SEQUENCE) {
        return error.InvalidChildType;
    }

    var declarationNodes: std.ArrayList(DeclarationNode) = .{};

    var it = iterateChildren(tree, child);
    while (try it.next()) |c| {
        if (C_Parser.ll_tree_type(tree, c) != C_Parser.LL_NODE_NODE) {
            continue;
        }

        const identifier = try readIdentifier(tree, c);

        try declarationNodes.append(allocator, .{ .type = .input, .name = identifier });
    }

    return declarationNodes;
}

pub fn readDeclarationType(tree: [*c]C_Parser.ll_tree, nodeId: C_Parser.ll_node_id, allocator: std.mem.Allocator) ![]const u8 {
    const identifierPointer = C_Parser.ll_tree_name(tree, nodeId);

    const identifier: []const u8 = std.mem.span(identifierPointer);

    if (!std.mem.eql(u8, identifier, "ComponentType")) {
        return error.InvalidIdentifier;
    }

    var stringChild: C_Parser.ll_node_id = undefined;
    try getNodeChild(tree, nodeId, &stringChild);

    const string: []u8 = try allocator.dupe(u8, std.mem.span(C_Parser.ll_tree_text(tree, stringChild)));

    return string;
}

pub fn translateDeclaration(tree: [*c]C_Parser.ll_tree, nodeId: C_Parser.ll_node_id, allocator: std.mem.Allocator) !void {
    var child: C_Parser.ll_node_id = undefined;
    try getNodeChild(tree, nodeId, &child);

    if (C_Parser.ll_tree_type(tree, child) != C_Parser.LL_NODE_SEQUENCE) {
        return error.InvalidChildType;
    }

    const children_len = C_Parser.ll_tree_children_len(tree, child);

    if (children_len < 2) {
        return error.InvalidChildrenLength;
    }

    var identifierChild: C_Parser.ll_node_id = undefined;
    if (!C_Parser.ll_tree_children_at(tree, child, @intCast(0), &identifierChild)) {
        return error.InvalidChildIndex;
    }

    const declarationType = try readDeclarationType(tree, identifierChild, allocator);
    const isInputDeclaration = std.mem.eql(u8, declarationType, "input");

    if (isInputDeclaration and children_len == 2) {
        var identListChild: C_Parser.ll_node_id = undefined;

        if (!C_Parser.ll_tree_children_at(tree, child, @intCast(1), &identListChild)) {
            return error.InvalidChildIndex;
        }

        const declarationNodes = try translateInputDeclaration(tree, identListChild, allocator);

        for (declarationNodes.items) |declarationNode| {
            std.debug.print("Declaration Node: {s}\n", .{declarationNode.name});
        }

        return;
    } else if (children_len == 3) {
        std.debug.print("Standard Declaration with Bus Type\n", .{});
    } else {
        return error.InvalidDeclaration;
    }
}
