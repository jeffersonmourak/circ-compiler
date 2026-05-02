const std = @import("std");
const ast = @import("ast.zig");
const Span = @import("span.zig").Span;
const C_Parser = @import("CParser.zig").C_Parser;

pub const Ast = ast;

const TranslationContext = struct {
    allocator: std.mem.Allocator,
    tree: [*c]C_Parser.ll_tree,
    source: []const u8,
    file_id: u32,
    anonymous_counter: usize = 0,
};

fn nodeType(ctx: *const TranslationContext, node_id: C_Parser.ll_node_id) C_Parser.ll_node_type {
    return C_Parser.ll_tree_type(ctx.tree, node_id);
}

fn nodeName(ctx: *const TranslationContext, node_id: C_Parser.ll_node_id) []const u8 {
    return std.mem.span(C_Parser.ll_tree_name(ctx.tree, node_id));
}

fn nodeRange(ctx: *const TranslationContext, node_id: C_Parser.ll_node_id) C_Parser.ll_range {
    return C_Parser.ll_tree_range(ctx.tree, node_id);
}

fn offsetToLineCol(source: []const u8, offset: usize) struct { line: u32, col: u32 } {
    var line: u32 = 1;
    var col: u32 = 1;
    var idx: usize = 0;
    while (idx < offset and idx < source.len) : (idx += 1) {
        if (source[idx] == '\n') {
            line += 1;
            col = 1;
        } else {
            col += 1;
        }
    }
    return .{ .line = line, .col = col };
}

fn nodeSpan(ctx: *const TranslationContext, node_id: C_Parser.ll_node_id) Span {
    const range = nodeRange(ctx, node_id);
    const start: usize = @intCast(@max(range.start, 0));
    const end: usize = @intCast(@max(range.end, 0));
    const start_lc = offsetToLineCol(ctx.source, start);
    const end_lc = offsetToLineCol(ctx.source, end);
    return .{
        .file_id = ctx.file_id,
        .start_line = start_lc.line,
        .start_col = start_lc.col,
        .end_line = end_lc.line,
        .end_col = end_lc.col,
    };
}

fn childAt(ctx: *const TranslationContext, parent: C_Parser.ll_node_id, index: usize) !C_Parser.ll_node_id {
    var child: C_Parser.ll_node_id = undefined;
    if (!C_Parser.ll_tree_children_at(ctx.tree, parent, @intCast(index), &child)) {
        return error.InvalidChildIndex;
    }
    return child;
}

fn childCount(ctx: *const TranslationContext, parent: C_Parser.ll_node_id) usize {
    return @intCast(C_Parser.ll_tree_children_len(ctx.tree, parent));
}

fn firstChild(ctx: *const TranslationContext, parent: C_Parser.ll_node_id) !C_Parser.ll_node_id {
    var child: C_Parser.ll_node_id = undefined;
    if (!C_Parser.ll_tree_child(ctx.tree, parent, &child)) {
        return error.InvalidChild;
    }
    return child;
}

fn expectNamedNode(ctx: *const TranslationContext, node_id: C_Parser.ll_node_id, expected_name: []const u8) !void {
    if (nodeType(ctx, node_id) != C_Parser.LL_NODE_NODE) return error.ExpectedNamedNode;
    if (!std.mem.eql(u8, nodeName(ctx, node_id), expected_name)) return error.UnexpectedNodeName;
}

fn parseIdentifier(ctx: *const TranslationContext, node_id: C_Parser.ll_node_id) !ast.Identifier {
    try expectNamedNode(ctx, node_id, "Identifier");
    const string_node = try firstChild(ctx, node_id);
    if (nodeType(ctx, string_node) != C_Parser.LL_NODE_STRING) return error.ExpectedString;
    const range = nodeRange(ctx, node_id);
    const start: usize = @intCast(range.start);
    const end: usize = @intCast(range.end);
    return .{
        .text = ctx.source[start..end],
        .span = nodeSpan(ctx, node_id),
    };
}

fn parseComponentTypeText(ctx: *const TranslationContext, node_id: C_Parser.ll_node_id) ![]const u8 {
    try expectNamedNode(ctx, node_id, "ComponentType");
    const string_node = try firstChild(ctx, node_id);
    if (nodeType(ctx, string_node) == C_Parser.LL_NODE_NODE and std.mem.eql(u8, nodeName(ctx, string_node), "Identifier")) {
        const ident = try parseIdentifier(ctx, string_node);
        return ident.text;
    }
    if (nodeType(ctx, string_node) != C_Parser.LL_NODE_STRING) return error.ExpectedString;
    const range = nodeRange(ctx, string_node);
    const start: usize = @intCast(range.start);
    const end: usize = @intCast(range.end);
    return ctx.source[start..end];
}

fn parsePortRef(ctx: *TranslationContext, node_id: C_Parser.ll_node_id) anyerror!ast.SignalSource {
    try expectNamedNode(ctx, node_id, "PortRef");
    const payload = try firstChild(ctx, node_id);
    switch (nodeType(ctx, payload)) {
        C_Parser.LL_NODE_NODE => {
            const ident = try parseIdentifier(ctx, payload);
            const out_ident = ast.Identifier{ .text = "out", .span = ident.span };
            return .{
                .named = .{
                    .target = ident,
                    .port = out_ident,
                    .span = nodeSpan(ctx, node_id),
                },
            };
        },
        C_Parser.LL_NODE_SEQUENCE => {
            const seq_len = childCount(ctx, payload);
            if (seq_len != 3) return error.InvalidPortReference;
            const left = try childAt(ctx, payload, 0);
            const right = try childAt(ctx, payload, 2);

            if (nodeType(ctx, left) == C_Parser.LL_NODE_NODE and std.mem.eql(u8, nodeName(ctx, left), "Identifier")) {
                const left_ident = try parseIdentifier(ctx, left);
                const right_ident = try parseIdentifier(ctx, right);
                return .{
                    .named = .{
                        .target = left_ident,
                        .port = right_ident,
                        .span = nodeSpan(ctx, node_id),
                    },
                };
            }

            if (nodeType(ctx, left) == C_Parser.LL_NODE_NODE and std.mem.eql(u8, nodeName(ctx, left), "AnonDecl")) {
                const anon_component = try parseAnonymousComponent(ctx, left);
                return .{ .anonymous = anon_component };
            }

            return error.InvalidPortReference;
        },
        else => return error.InvalidPortReference,
    }
}

fn parseBusType(ctx: *TranslationContext, node_id: C_Parser.ll_node_id) anyerror![]ast.PortConnection {
    try expectNamedNode(ctx, node_id, "BusType");
    const seq = try firstChild(ctx, node_id);
    if (nodeType(ctx, seq) != C_Parser.LL_NODE_SEQUENCE) return error.InvalidBusType;

    var connections: std.ArrayList(ast.PortConnection) = .{};
    const seq_len = childCount(ctx, seq);
    var index: usize = 0;
    while (index < seq_len) : (index += 1) {
        const child = try childAt(ctx, seq, index);
        if (nodeType(ctx, child) == C_Parser.LL_NODE_NODE and std.mem.eql(u8, nodeName(ctx, child), "Identifier")) {
            if (index + 2 >= seq_len) return error.InvalidBusType;
            const maybe_equal = try childAt(ctx, seq, index + 1);
            const maybe_ref = try childAt(ctx, seq, index + 2);
            if (nodeType(ctx, maybe_equal) != C_Parser.LL_NODE_STRING) return error.InvalidBusType;
            if (nodeType(ctx, maybe_ref) != C_Parser.LL_NODE_NODE or !std.mem.eql(u8, nodeName(ctx, maybe_ref), "PortRef")) {
                return error.InvalidBusType;
            }

            const port_ident = try parseIdentifier(ctx, child);
            const source = try parsePortRef(ctx, maybe_ref);
            try connections.append(ctx.allocator, .{
                .port = port_ident,
                .value = source,
                .span = nodeSpan(ctx, child),
            });
            index += 2;
        }
    }

    return connections.toOwnedSlice(ctx.allocator);
}

fn parseAnonymousComponent(ctx: *TranslationContext, node_id: C_Parser.ll_node_id) anyerror!*const ast.ComponentInstance {
    try expectNamedNode(ctx, node_id, "AnonDecl");
    const seq = try firstChild(ctx, node_id);
    if (nodeType(ctx, seq) != C_Parser.LL_NODE_SEQUENCE) return error.InvalidAnonymousDeclaration;
    if (childCount(ctx, seq) != 2) return error.InvalidAnonymousDeclaration;

    const type_node = try childAt(ctx, seq, 0);
    const bus_node = try childAt(ctx, seq, 1);
    const type_name_text = try parseComponentTypeText(ctx, type_node);
    const ports = try parseBusType(ctx, bus_node);

    const generated_name = try std.fmt.allocPrint(ctx.allocator, "__anon_{d}", .{ctx.anonymous_counter});
    ctx.anonymous_counter += 1;

    const component = try ctx.allocator.create(ast.ComponentInstance);
    component.* = .{
        .type_name = .{ .text = type_name_text, .span = nodeSpan(ctx, type_node) },
        .instance_name = .{ .text = generated_name, .span = nodeSpan(ctx, node_id) },
        .ports = ports,
        .span = nodeSpan(ctx, node_id),
    };
    return component;
}

fn parseImportDecl(ctx: *TranslationContext, node_id: C_Parser.ll_node_id) !ast.Import {
    try expectNamedNode(ctx, node_id, "ImportDecl");
    const seq = try firstChild(ctx, node_id);
    if (nodeType(ctx, seq) != C_Parser.LL_NODE_SEQUENCE) return error.InvalidImportDecl;

    const seq_len = childCount(ctx, seq);
    if (seq_len < 4) return error.InvalidImportDecl;
    const alias_node = try childAt(ctx, seq, 1);
    const path_node = try childAt(ctx, seq, 3);

    const alias = try parseIdentifier(ctx, alias_node);
    if (nodeType(ctx, path_node) != C_Parser.LL_NODE_STRING) return error.InvalidImportDecl;
    const path_range = nodeRange(ctx, path_node);
    const path_start: usize = @intCast(path_range.start);
    const path_end: usize = @intCast(path_range.end);

    return .{
        .alias = alias,
        .path = .{
            .text = ctx.source[path_start..path_end],
            .span = nodeSpan(ctx, path_node),
        },
        .span = nodeSpan(ctx, node_id),
    };
}

fn parseInputDecl(ctx: *TranslationContext, ident_list_node: C_Parser.ll_node_id) !ast.InputDecl {
    try expectNamedNode(ctx, ident_list_node, "IdentList");
    const payload = try firstChild(ctx, ident_list_node);

    var names: std.ArrayList(ast.Identifier) = .{};
    if (nodeType(ctx, payload) == C_Parser.LL_NODE_NODE) {
        try names.append(ctx.allocator, try parseIdentifier(ctx, payload));
    } else {
        const payload_len = childCount(ctx, payload);
        var i: usize = 0;
        while (i < payload_len) : (i += 1) {
            const c = try childAt(ctx, payload, i);
            if (nodeType(ctx, c) == C_Parser.LL_NODE_NODE and std.mem.eql(u8, nodeName(ctx, c), "Identifier")) {
                try names.append(ctx.allocator, try parseIdentifier(ctx, c));
            }
        }
    }

    return .{
        .names = try names.toOwnedSlice(ctx.allocator),
        .span = nodeSpan(ctx, ident_list_node),
    };
}

fn parseOutputFromBusType(ctx: *TranslationContext, instance_name: ast.Identifier, bus_node: C_Parser.ll_node_id, declaration_span: Span) !ast.OutputDecl {
    const ports = try parseBusType(ctx, bus_node);
    if (ports.len == 0) return error.InvalidOutputDecl;

    return .{
        .name = instance_name,
        .value = ports[0].value,
        .span = declaration_span,
    };
}

fn parseComponentDecl(ctx: *TranslationContext, type_name_text: []const u8, instance_name: ast.Identifier, bus_node: C_Parser.ll_node_id, declaration_span: Span) !ast.ComponentInstance {
    return .{
        .type_name = .{ .text = type_name_text, .span = nodeSpan(ctx, bus_node) },
        .instance_name = instance_name,
        .ports = try parseBusType(ctx, bus_node),
        .span = declaration_span,
    };
}

fn parseDeclaration(
    ctx: *TranslationContext,
    node_id: C_Parser.ll_node_id,
    imports: *std.ArrayList(ast.Import),
    inputs: *std.ArrayList(ast.InputDecl),
    outputs: *std.ArrayList(ast.OutputDecl),
    components: *std.ArrayList(ast.ComponentInstance),
) !void {
    try expectNamedNode(ctx, node_id, "Declaration");
    const seq = try firstChild(ctx, node_id);
    if (nodeType(ctx, seq) != C_Parser.LL_NODE_SEQUENCE) return error.InvalidDeclaration;
    const len = childCount(ctx, seq);
    if (len < 2) return error.InvalidDeclaration;

    const type_node = try childAt(ctx, seq, 0);
    const type_name = try parseComponentTypeText(ctx, type_node);
    const declaration_span = nodeSpan(ctx, node_id);

    if (len == 2) {
        const ident_list_node = try childAt(ctx, seq, 1);
        if (std.mem.eql(u8, type_name, "input")) {
            try inputs.append(ctx.allocator, try parseInputDecl(ctx, ident_list_node));
            return;
        }

        if (std.mem.eql(u8, type_name, "output")) {
            const names = try parseInputDecl(ctx, ident_list_node);
            for (names.names) |name| {
                const out_ident = ast.Identifier{ .text = "out", .span = name.span };
                try outputs.append(ctx.allocator, .{
                    .name = name,
                    .value = .{
                        .named = .{
                            .target = name,
                            .port = out_ident,
                            .span = name.span,
                        },
                    },
                    .span = declaration_span,
                });
            }
            return;
        }

        const names = try parseInputDecl(ctx, ident_list_node);
        for (names.names) |name| {
            try components.append(ctx.allocator, .{
                .type_name = .{ .text = type_name, .span = nodeSpan(ctx, type_node) },
                .instance_name = name,
                .ports = &.{},
                .span = declaration_span,
            });
        }
        return;
    }

    if (len == 3) {
        const instance_name_node = try childAt(ctx, seq, 1);
        const bus_node = try childAt(ctx, seq, 2);
        const instance_name = try parseIdentifier(ctx, instance_name_node);

        if (std.mem.eql(u8, type_name, "output")) {
            try outputs.append(ctx.allocator, try parseOutputFromBusType(ctx, instance_name, bus_node, declaration_span));
            return;
        }

        try components.append(ctx.allocator, try parseComponentDecl(ctx, type_name, instance_name, bus_node, declaration_span));
        return;
    }

    _ = imports;
    return error.InvalidDeclaration;
}

fn translateTree(ctx: *TranslationContext) !ast.File {
    var root: C_Parser.ll_node_id = undefined;
    if (!C_Parser.ll_tree_root(ctx.tree, &root)) return error.ParsingFailed;
    try expectNamedNode(ctx, root, "Program");

    const sequence = try firstChild(ctx, root);
    if (nodeType(ctx, sequence) != C_Parser.LL_NODE_SEQUENCE) return error.InvalidProgram;

    var imports: std.ArrayList(ast.Import) = .{};
    var inputs: std.ArrayList(ast.InputDecl) = .{};
    var outputs: std.ArrayList(ast.OutputDecl) = .{};
    var components: std.ArrayList(ast.ComponentInstance) = .{};

    const len = childCount(ctx, sequence);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const child = try childAt(ctx, sequence, i);
        if (nodeType(ctx, child) != C_Parser.LL_NODE_NODE) continue;
        const name = nodeName(ctx, child);

        if (std.mem.eql(u8, name, "ImportDecl")) {
            try imports.append(ctx.allocator, try parseImportDecl(ctx, child));
            continue;
        }

        if (std.mem.eql(u8, name, "Declaration")) {
            try parseDeclaration(ctx, child, &imports, &inputs, &outputs, &components);
            continue;
        }
    }

    return .{
        .imports = try imports.toOwnedSlice(ctx.allocator),
        .inputs = try inputs.toOwnedSlice(ctx.allocator),
        .outputs = try outputs.toOwnedSlice(ctx.allocator),
        .components = try components.toOwnedSlice(ctx.allocator),
        .span = nodeSpan(ctx, root),
    };
}

pub fn translate(allocator: std.mem.Allocator, tree: [*c]C_Parser.ll_tree, file_id: u32) !ast.File {
    if (tree == null) return error.ParsingFailed;
    const source_ptr: [*]const u8 = @ptrCast(tree.*.input);
    const source: []const u8 = source_ptr[0..@intCast(tree.*.input_len)];
    var ctx = TranslationContext{
        .allocator = allocator,
        .tree = tree,
        .source = source,
        .file_id = file_id,
    };
    return translateTree(&ctx);
}

pub fn parseSource(allocator: std.mem.Allocator, file_id: u32, source: []const u8) !ast.File {
    const parser = C_Parser.Parser_New();
    defer C_Parser.Parser_Delete(parser);

    var cursor: c_int = 0;
    C_Parser.Parser_SetInput(parser, @ptrCast(source.ptr), @intCast(source.len));
    const tree = C_Parser.Parser_Parse(parser, &cursor, null);
    if (tree == null) return error.ParsingFailed;
    defer C_Parser.ll_tree_free(tree);

    var ctx = TranslationContext{
        .allocator = allocator,
        .tree = tree,
        .source = source,
        .file_id = file_id,
    };
    return translateTree(&ctx);
}
