const std = @import("std");
const ast = @import("ast.zig");
const Span = @import("span.zig").Span;
const C_Parser = @import("CParser.zig").C_Parser;

pub const Ast = ast;

// langlang's Go API exposes NodeType discriminants as a Go iota; the
// c-archive header omits them. Mirror the values from
// lib/parser/parser.go (NodeType_String = iota, ...).
const NodeType_String: u8 = 0;
const NodeType_Sequence: u8 = 1;
const NodeType_Node: u8 = 2;
const NodeType_Error: u8 = 3;

// Byte-offset range. Replaces C_Parser.ll_range; the Go API exposes
// richer Span (line/column) info via TreeSpanStart/TreeSpanEnd, but we
// flatten to byte offsets here so offsetToLineCol stays the source of
// truth for line/column derivation.
const Range = struct {
    start: c_int,
    end: c_int,
};

const TranslationContext = struct {
    allocator: std.mem.Allocator,
    handle: @TypeOf(C_Parser.ParserNew()),
    source: []const u8,
    file_id: u32,
    anonymous_counter: usize = 0,
};

fn nodeType(ctx: *const TranslationContext, node_id: u32) u8 {
    return C_Parser.TreeType(ctx.handle, node_id);
}

fn nodeName(ctx: *const TranslationContext, node_id: u32) []const u8 {
    return std.mem.span(C_Parser.TreeName(ctx.handle, node_id));
}

fn nodeRange(ctx: *const TranslationContext, node_id: u32) Range {
    return .{
        .start = C_Parser.TreeSpanStart(ctx.handle, node_id),
        .end = C_Parser.TreeSpanEnd(ctx.handle, node_id),
    };
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

fn nodeSpan(ctx: *const TranslationContext, node_id: u32) Span {
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

fn childAt(ctx: *const TranslationContext, parent: u32, index: usize) !u32 {
    var child: u32 = undefined;
    if (!C_Parser.TreeChildrenAt(ctx.handle, parent, @intCast(index), &child)) {
        return error.InvalidChildIndex;
    }
    return child;
}

fn childCount(ctx: *const TranslationContext, parent: u32) usize {
    return @intCast(C_Parser.TreeChildrenLen(ctx.handle, parent));
}

fn firstChild(ctx: *const TranslationContext, parent: u32) !u32 {
    var child: u32 = undefined;
    if (!C_Parser.TreeChild(ctx.handle, parent, &child)) {
        return error.InvalidChild;
    }
    return child;
}

fn expectNamedNode(ctx: *const TranslationContext, node_id: u32, expected_name: []const u8) !void {
    if (nodeType(ctx, node_id) != NodeType_Node) return error.ExpectedNamedNode;
    if (!std.mem.eql(u8, nodeName(ctx, node_id), expected_name)) return error.UnexpectedNodeName;
}

fn parseIdentifier(ctx: *const TranslationContext, node_id: u32) !ast.Identifier {
    try expectNamedNode(ctx, node_id, "Identifier");
    const string_node = try firstChild(ctx, node_id);
    if (nodeType(ctx, string_node) != NodeType_String) return error.ExpectedString;
    const range = nodeRange(ctx, node_id);
    const start: usize = @intCast(range.start);
    const end: usize = @intCast(range.end);
    return .{
        .text = ctx.source[start..end],
        .span = nodeSpan(ctx, node_id),
    };
}

fn parseWidthAnnot(ctx: *const TranslationContext, node_id: u32) !ast.WidthSpec {
    try expectNamedNode(ctx, node_id, "WidthAnnot");
    return parseFirstWidthArg(ctx, node_id);
}

fn parseFirstWidthArg(ctx: *const TranslationContext, node_id: u32) !ast.WidthSpec {
    const inner = try firstChild(ctx, node_id);
    if (nodeType(ctx, inner) == NodeType_Node) {
        return try parseWidthArgNode(ctx, inner);
    }
    if (nodeType(ctx, inner) != NodeType_Sequence) return error.InvalidWidthAnnot;
    const len = childCount(ctx, inner);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const child = try childAt(ctx, inner, i);
        if (nodeType(ctx, child) != NodeType_Node) continue;
        const name = nodeName(ctx, child);
        if (std.mem.eql(u8, name, "Integer") or std.mem.eql(u8, name, "Identifier") or std.mem.eql(u8, name, "WidthArg")) {
            return try parseWidthArgNode(ctx, child);
        }
    }
    return error.InvalidWidthAnnot;
}

fn parseWidthArgNode(ctx: *const TranslationContext, node_id: u32) !ast.WidthSpec {
    const name = nodeName(ctx, node_id);
    if (std.mem.eql(u8, name, "Integer")) return parseIntegerAsWidth(ctx, node_id);
    if (std.mem.eql(u8, name, "Identifier")) {
        const ident = try parseIdentifier(ctx, node_id);
        return .{ .parameter = ident.text };
    }
    if (std.mem.eql(u8, name, "WidthArg")) {
        const inner = try firstChild(ctx, node_id);
        if (nodeType(ctx, inner) != NodeType_Node) return error.InvalidWidthArg;
        return parseWidthArgNode(ctx, inner);
    }
    return error.InvalidWidthArg;
}

fn parseIntegerAsWidth(ctx: *const TranslationContext, node_id: u32) !ast.WidthSpec {
    try expectNamedNode(ctx, node_id, "Integer");
    const range = nodeRange(ctx, node_id);
    const start: usize = @intCast(range.start);
    const end: usize = @intCast(range.end);
    const text = ctx.source[start..end];
    const value = std.fmt.parseInt(u8, text, 10) catch return error.InvalidIntegerWidth;
    return .{ .literal = value };
}

fn parseCallWidths(ctx: *const TranslationContext, node_id: u32) ![]const ast.WidthSpec {
    try expectNamedNode(ctx, node_id, "CallWidths");
    const seq = try firstChild(ctx, node_id);
    var widths: std.ArrayList(ast.WidthSpec) = .{};
    if (nodeType(ctx, seq) == NodeType_Node) {
        try widths.append(ctx.allocator, try parseWidthArgNode(ctx, seq));
        return widths.toOwnedSlice(ctx.allocator);
    }
    if (nodeType(ctx, seq) != NodeType_Sequence) return error.InvalidCallWidths;
    const len = childCount(ctx, seq);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const child = try childAt(ctx, seq, i);
        if (nodeType(ctx, child) != NodeType_Node) continue;
        const name = nodeName(ctx, child);
        if (std.mem.eql(u8, name, "Integer") or std.mem.eql(u8, name, "Identifier") or std.mem.eql(u8, name, "WidthArg")) {
            try widths.append(ctx.allocator, try parseWidthArgNode(ctx, child));
        }
    }
    return widths.toOwnedSlice(ctx.allocator);
}

fn parseParamIntro(ctx: *TranslationContext, node_id: u32) ![]const ast.Identifier {
    try expectNamedNode(ctx, node_id, "ParamIntro");
    const seq = try firstChild(ctx, node_id);
    var params: std.ArrayList(ast.Identifier) = .{};
    if (nodeType(ctx, seq) == NodeType_Node and std.mem.eql(u8, nodeName(ctx, seq), "Identifier")) {
        try params.append(ctx.allocator, try parseIdentifier(ctx, seq));
        return params.toOwnedSlice(ctx.allocator);
    }
    if (nodeType(ctx, seq) != NodeType_Sequence) return error.InvalidParamIntro;
    const len = childCount(ctx, seq);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const child = try childAt(ctx, seq, i);
        if (nodeType(ctx, child) == NodeType_Node and std.mem.eql(u8, nodeName(ctx, child), "Identifier")) {
            try params.append(ctx.allocator, try parseIdentifier(ctx, child));
        }
    }
    return params.toOwnedSlice(ctx.allocator);
}

fn parseComponentTypeText(ctx: *const TranslationContext, node_id: u32) ![]const u8 {
    try expectNamedNode(ctx, node_id, "ComponentType");
    const string_node = try firstChild(ctx, node_id);
    if (nodeType(ctx, string_node) == NodeType_Node and std.mem.eql(u8, nodeName(ctx, string_node), "Identifier")) {
        const ident = try parseIdentifier(ctx, string_node);
        return ident.text;
    }
    if (nodeType(ctx, string_node) != NodeType_String) return error.ExpectedString;
    const range = nodeRange(ctx, string_node);
    const start: usize = @intCast(range.start);
    const end: usize = @intCast(range.end);
    return ctx.source[start..end];
}

fn parsePortRef(ctx: *TranslationContext, node_id: u32) anyerror!ast.SignalSource {
    try expectNamedNode(ctx, node_id, "PortRef");
    const payload = try firstChild(ctx, node_id);
    switch (nodeType(ctx, payload)) {
        NodeType_Node => {
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
        NodeType_Sequence => {
            const seq_len = childCount(ctx, payload);
            if (seq_len != 3) return error.InvalidPortReference;
            const left = try childAt(ctx, payload, 0);
            const right = try childAt(ctx, payload, 2);

            if (nodeType(ctx, left) == NodeType_Node and std.mem.eql(u8, nodeName(ctx, left), "Identifier")) {
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

            if (nodeType(ctx, left) == NodeType_Node and std.mem.eql(u8, nodeName(ctx, left), "AnonDecl")) {
                const anon_component = try parseAnonymousComponent(ctx, left);
                return .{ .anonymous = anon_component };
            }

            return error.InvalidPortReference;
        },
        else => return error.InvalidPortReference,
    }
}

fn parseBusType(ctx: *TranslationContext, node_id: u32) anyerror![]ast.PortConnection {
    try expectNamedNode(ctx, node_id, "BusType");
    const seq = try firstChild(ctx, node_id);
    if (nodeType(ctx, seq) != NodeType_Sequence) return error.InvalidBusType;

    var connections: std.ArrayList(ast.PortConnection) = .{};
    const seq_len = childCount(ctx, seq);
    var index: usize = 0;
    while (index < seq_len) : (index += 1) {
        const child = try childAt(ctx, seq, index);
        if (nodeType(ctx, child) == NodeType_Node and std.mem.eql(u8, nodeName(ctx, child), "Identifier")) {
            if (index + 2 >= seq_len) return error.InvalidBusType;
            const maybe_equal = try childAt(ctx, seq, index + 1);
            const maybe_ref = try childAt(ctx, seq, index + 2);
            if (nodeType(ctx, maybe_equal) != NodeType_String) return error.InvalidBusType;
            if (nodeType(ctx, maybe_ref) != NodeType_Node or !std.mem.eql(u8, nodeName(ctx, maybe_ref), "PortRef")) {
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

fn parseAnonymousComponent(ctx: *TranslationContext, node_id: u32) anyerror!*const ast.ComponentInstance {
    try expectNamedNode(ctx, node_id, "AnonDecl");
    const seq = try firstChild(ctx, node_id);
    if (nodeType(ctx, seq) != NodeType_Sequence) return error.InvalidAnonymousDeclaration;
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

fn parseImportDecl(ctx: *TranslationContext, node_id: u32) !ast.Import {
    try expectNamedNode(ctx, node_id, "ImportDecl");
    const seq = try firstChild(ctx, node_id);
    if (nodeType(ctx, seq) != NodeType_Sequence) return error.InvalidImportDecl;

    const seq_len = childCount(ctx, seq);
    if (seq_len < 4) return error.InvalidImportDecl;
    const alias_node = try childAt(ctx, seq, 1);
    const path_node = try childAt(ctx, seq, 3);

    const alias = try parseIdentifier(ctx, alias_node);
    if (nodeType(ctx, path_node) != NodeType_String) return error.InvalidImportDecl;
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

fn parseInputDeclNode(ctx: *TranslationContext, node_id: u32) !ast.InputDecl {
    try expectNamedNode(ctx, node_id, "InputDecl");
    const seq = try firstChild(ctx, node_id);
    if (nodeType(ctx, seq) != NodeType_Sequence) return error.InvalidInputDecl;
    const len = childCount(ctx, seq);

    var parameters: []const ast.Identifier = &.{};
    var width: ?ast.WidthSpec = null;
    var ident_list_node: ?u32 = null;

    var i: usize = 0;
    while (i < len) : (i += 1) {
        const child = try childAt(ctx, seq, i);
        if (nodeType(ctx, child) != NodeType_Node) continue;
        const name = nodeName(ctx, child);
        if (std.mem.eql(u8, name, "ParamIntro")) {
            parameters = try parseParamIntro(ctx, child);
        } else if (std.mem.eql(u8, name, "WidthAnnot")) {
            width = try parseWidthAnnot(ctx, child);
        } else if (std.mem.eql(u8, name, "IdentList")) {
            ident_list_node = child;
        }
    }

    const idents_node = ident_list_node orelse return error.InvalidInputDecl;
    var decl = try parseInputDecl(ctx, idents_node);
    decl.parameters = parameters;
    decl.span = nodeSpan(ctx, node_id);
    if (width) |w| {
        const decorated = try ctx.allocator.alloc(ast.Identifier, decl.names.len);
        for (decl.names, decorated) |src, *dst| {
            dst.* = .{ .text = src.text, .span = src.span, .width = w };
        }
        decl.names = decorated;
    }
    return decl;
}

fn parseInputDecl(ctx: *TranslationContext, ident_list_node: u32) !ast.InputDecl {
    try expectNamedNode(ctx, ident_list_node, "IdentList");
    const payload = try firstChild(ctx, ident_list_node);

    var names: std.ArrayList(ast.Identifier) = .{};
    if (nodeType(ctx, payload) == NodeType_Node) {
        try names.append(ctx.allocator, try parseIdentifier(ctx, payload));
    } else {
        const payload_len = childCount(ctx, payload);
        var i: usize = 0;
        while (i < payload_len) : (i += 1) {
            const c = try childAt(ctx, payload, i);
            if (nodeType(ctx, c) == NodeType_Node and std.mem.eql(u8, nodeName(ctx, c), "Identifier")) {
                try names.append(ctx.allocator, try parseIdentifier(ctx, c));
            }
        }
    }

    return .{
        .names = try names.toOwnedSlice(ctx.allocator),
        .span = nodeSpan(ctx, ident_list_node),
    };
}

fn parseOutputFromBusType(ctx: *TranslationContext, instance_name: ast.Identifier, bus_node: u32, declaration_span: Span) !ast.OutputDecl {
    const ports = try parseBusType(ctx, bus_node);
    if (ports.len == 0) return error.InvalidOutputDecl;

    return .{
        .name = instance_name,
        .value = ports[0].value,
        .span = declaration_span,
    };
}

fn parseComponentDecl(ctx: *TranslationContext, type_name_text: []const u8, instance_name: ast.Identifier, bus_node: u32, declaration_span: Span) !ast.ComponentInstance {
    return .{
        .type_name = .{ .text = type_name_text, .span = nodeSpan(ctx, bus_node) },
        .instance_name = instance_name,
        .ports = try parseBusType(ctx, bus_node),
        .span = declaration_span,
    };
}

fn parseDeclaration(
    ctx: *TranslationContext,
    node_id: u32,
    outputs: *std.ArrayList(ast.OutputDecl),
    components: *std.ArrayList(ast.ComponentInstance),
) !void {
    try expectNamedNode(ctx, node_id, "Declaration");
    const seq = try firstChild(ctx, node_id);
    if (nodeType(ctx, seq) != NodeType_Sequence) return error.InvalidDeclaration;
    const len = childCount(ctx, seq);
    if (len < 2) return error.InvalidDeclaration;

    const type_node = try childAt(ctx, seq, 0);
    const type_name = try parseComponentTypeText(ctx, type_node);
    const declaration_span = nodeSpan(ctx, node_id);

    var width: ?ast.WidthSpec = null;
    var call_widths: []const ast.WidthSpec = &.{};
    var instance_name_node: ?u32 = null;
    var ident_list_node: ?u32 = null;
    var bus_node: ?u32 = null;

    var i: usize = 1;
    while (i < len) : (i += 1) {
        const child = try childAt(ctx, seq, i);
        if (nodeType(ctx, child) != NodeType_Node) continue;
        const name = nodeName(ctx, child);
        if (std.mem.eql(u8, name, "WidthAnnot")) {
            width = try parseWidthAnnot(ctx, child);
        } else if (std.mem.eql(u8, name, "CallWidths")) {
            call_widths = try parseCallWidths(ctx, child);
        } else if (std.mem.eql(u8, name, "Identifier")) {
            instance_name_node = child;
        } else if (std.mem.eql(u8, name, "IdentList")) {
            ident_list_node = child;
        } else if (std.mem.eql(u8, name, "BusType")) {
            bus_node = child;
        }
    }

    const type_identifier = ast.Identifier{
        .text = type_name,
        .span = nodeSpan(ctx, type_node),
        .width = width,
    };

    if (instance_name_node) |inst_node| {
        const raw_instance = try parseIdentifier(ctx, inst_node);
        const instance_name = ast.Identifier{ .text = raw_instance.text, .span = raw_instance.span, .width = width };
        const bn = bus_node orelse return error.InvalidDeclaration;

        if (std.mem.eql(u8, type_name, "output")) {
            const ports = try parseBusType(ctx, bn);
            if (ports.len == 0) return error.InvalidOutputDecl;
            try outputs.append(ctx.allocator, .{
                .name = instance_name,
                .value = ports[0].value,
                .span = declaration_span,
            });
            return;
        }

        try components.append(ctx.allocator, .{
            .type_name = type_identifier,
            .instance_name = instance_name,
            .ports = try parseBusType(ctx, bn),
            .width_args = call_widths,
            .span = declaration_span,
        });
        return;
    }

    if (ident_list_node) |idents| {
        if (std.mem.eql(u8, type_name, "output")) {
            const names = try parseInputDecl(ctx, idents);
            for (names.names) |name| {
                const widened_name = ast.Identifier{ .text = name.text, .span = name.span, .width = width };
                const out_ident = ast.Identifier{ .text = "out", .span = name.span };
                try outputs.append(ctx.allocator, .{
                    .name = widened_name,
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

        const names = try parseInputDecl(ctx, idents);
        for (names.names) |name| {
            const widened_name = ast.Identifier{ .text = name.text, .span = name.span, .width = width };
            try components.append(ctx.allocator, .{
                .type_name = type_identifier,
                .instance_name = widened_name,
                .ports = &.{},
                .span = declaration_span,
            });
        }
        return;
    }

    return error.InvalidDeclaration;
}

fn translateTree(ctx: *TranslationContext) !ast.File {
    var root: u32 = undefined;
    if (!C_Parser.TreeRoot(ctx.handle, &root)) return error.ParsingFailed;
    try expectNamedNode(ctx, root, "Program");

    var imports: std.ArrayList(ast.Import) = .{};
    var inputs: std.ArrayList(ast.InputDecl) = .{};
    var outputs: std.ArrayList(ast.OutputDecl) = .{};
    var components: std.ArrayList(ast.ComponentInstance) = .{};
    const payload = try firstChild(ctx, root);
    if (nodeType(ctx, payload) == NodeType_Sequence) {
        const len = childCount(ctx, payload);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const child = try childAt(ctx, payload, i);
            if (nodeType(ctx, child) != NodeType_Node) continue;
            const name = nodeName(ctx, child);

            if (std.mem.eql(u8, name, "ImportDecl")) {
                try imports.append(ctx.allocator, try parseImportDecl(ctx, child));
                continue;
            }

            if (std.mem.eql(u8, name, "InputDecl")) {
                try inputs.append(ctx.allocator, try parseInputDeclNode(ctx, child));
                continue;
            }

            if (std.mem.eql(u8, name, "Declaration")) {
                try parseDeclaration(ctx, child, &outputs, &components);
                continue;
            }
        }
    } else if (nodeType(ctx, payload) == NodeType_Node) {
        const name = nodeName(ctx, payload);
        if (std.mem.eql(u8, name, "ImportDecl")) {
            try imports.append(ctx.allocator, try parseImportDecl(ctx, payload));
        } else if (std.mem.eql(u8, name, "InputDecl")) {
            try inputs.append(ctx.allocator, try parseInputDeclNode(ctx, payload));
        } else if (std.mem.eql(u8, name, "Declaration")) {
            try parseDeclaration(ctx, payload, &outputs, &components);
        } else {
            return error.InvalidProgram;
        }
    } else {
        return error.InvalidProgram;
    }

    return .{
        .imports = try imports.toOwnedSlice(ctx.allocator),
        .inputs = try inputs.toOwnedSlice(ctx.allocator),
        .outputs = try outputs.toOwnedSlice(ctx.allocator),
        .components = try components.toOwnedSlice(ctx.allocator),
        .span = nodeSpan(ctx, root),
    };
}

pub fn translate(allocator: std.mem.Allocator, handle: @TypeOf(C_Parser.ParserNew()), file_id: u32) !ast.File {
    var source_len: c_int = 0;
    const source_ptr = C_Parser.TreeInput(handle, &source_len);
    if (source_ptr == null or source_len <= 0) return error.ParsingFailed;
    const source_bytes: [*]const u8 = @ptrCast(source_ptr);
    const source: []const u8 = source_bytes[0..@intCast(source_len)];
    var ctx = TranslationContext{
        .allocator = allocator,
        .handle = handle,
        .source = source,
        .file_id = file_id,
    };
    return translateTree(&ctx);
}

pub fn parseSource(allocator: std.mem.Allocator, file_id: u32, source: []const u8) !ast.File {
    const handle = C_Parser.ParserNew();
    defer C_Parser.ParserDelete(handle);

    if (!C_Parser.ParserParse(handle, @ptrCast(@constCast(source.ptr)), @intCast(source.len))) {
        return error.ParsingFailed;
    }

    var ctx = TranslationContext{
        .allocator = allocator,
        .handle = handle,
        .source = source,
        .file_id = file_id,
    };
    return translateTree(&ctx);
}
