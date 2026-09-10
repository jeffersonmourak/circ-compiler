const std = @import("std");
const ast = @import("ast.zig");
const Span = @import("span.zig").Span;
const parser = @import("parser");

pub const Ast = ast;

// The langlang-generated parser (lib/parser/parser.zig) re-exports nothing
// from its pasted runtime, so every type is spelled through parser.runtime.
const NodeType = parser.runtime.NodeType;

// Byte-offset range (end exclusive). The tree keeps byte offsets only;
// offsetToLineCol stays the single source of truth for line/column.
const Range = parser.runtime.Range;

const TranslationContext = struct {
    allocator: std.mem.Allocator,
    tree: *const parser.runtime.Tree,
    source: []const u8,
    file_id: u32,
    anonymous_counter: usize = 0,
};

fn nodeType(ctx: *const TranslationContext, node_id: u32) NodeType {
    return ctx.tree.typ(node_id);
}

fn nodeName(ctx: *const TranslationContext, node_id: u32) []const u8 {
    return ctx.tree.name(node_id);
}

fn nodeRange(ctx: *const TranslationContext, node_id: u32) Range {
    return ctx.tree.range(node_id);
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
    const start_lc = offsetToLineCol(ctx.source, range.start);
    const end_lc = offsetToLineCol(ctx.source, range.end);
    return .{
        .file_id = ctx.file_id,
        .start_line = start_lc.line,
        .start_col = start_lc.col,
        .end_line = end_lc.line,
        .end_col = end_lc.col,
    };
}

fn childAt(ctx: *const TranslationContext, parent: u32, index: usize) !u32 {
    return ctx.tree.childAt(parent, index) orelse error.InvalidChildIndex;
}

fn childCount(ctx: *const TranslationContext, parent: u32) usize {
    return ctx.tree.childrenLen(parent);
}

fn firstChild(ctx: *const TranslationContext, parent: u32) !u32 {
    return ctx.tree.child(parent) orelse error.InvalidChild;
}

fn expectNamedNode(ctx: *const TranslationContext, node_id: u32, expected_name: []const u8) !void {
    if (nodeType(ctx, node_id) != .node) return error.ExpectedNamedNode;
    if (!std.mem.eql(u8, nodeName(ctx, node_id), expected_name)) return error.UnexpectedNodeName;
}

fn parseIdentifier(ctx: *const TranslationContext, node_id: u32) !ast.Identifier {
    try expectNamedNode(ctx, node_id, "Identifier");
    const string_node = try firstChild(ctx, node_id);
    if (nodeType(ctx, string_node) != .string) return error.ExpectedString;
    const range = nodeRange(ctx, node_id);
    const start = range.start;
    const end = range.end;
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
    if (nodeType(ctx, inner) == .node) {
        return try parseWidthArgNode(ctx, inner);
    }
    if (nodeType(ctx, inner) != .sequence) return error.InvalidWidthAnnot;
    const len = childCount(ctx, inner);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const child = try childAt(ctx, inner, i);
        if (nodeType(ctx, child) != .node) continue;
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
        if (nodeType(ctx, inner) != .node) return error.InvalidWidthArg;
        return parseWidthArgNode(ctx, inner);
    }
    return error.InvalidWidthArg;
}

fn parseIntegerAsWidth(ctx: *const TranslationContext, node_id: u32) !ast.WidthSpec {
    try expectNamedNode(ctx, node_id, "Integer");
    const range = nodeRange(ctx, node_id);
    const start = range.start;
    const end = range.end;
    const text = ctx.source[start..end];
    const value = std.fmt.parseInt(u8, text, 10) catch return error.InvalidIntegerWidth;
    return .{ .literal = value };
}

fn parseCallWidths(ctx: *const TranslationContext, node_id: u32) ![]const ast.WidthSpec {
    try expectNamedNode(ctx, node_id, "CallWidths");
    const seq = try firstChild(ctx, node_id);
    var widths: std.ArrayList(ast.WidthSpec) = .{};
    if (nodeType(ctx, seq) == .node) {
        try widths.append(ctx.allocator, try parseWidthArgNode(ctx, seq));
        return widths.toOwnedSlice(ctx.allocator);
    }
    if (nodeType(ctx, seq) != .sequence) return error.InvalidCallWidths;
    const len = childCount(ctx, seq);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const child = try childAt(ctx, seq, i);
        if (nodeType(ctx, child) != .node) continue;
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
    if (nodeType(ctx, seq) == .node and std.mem.eql(u8, nodeName(ctx, seq), "Identifier")) {
        try params.append(ctx.allocator, try parseIdentifier(ctx, seq));
        return params.toOwnedSlice(ctx.allocator);
    }
    if (nodeType(ctx, seq) != .sequence) return error.InvalidParamIntro;
    const len = childCount(ctx, seq);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const child = try childAt(ctx, seq, i);
        if (nodeType(ctx, child) == .node and std.mem.eql(u8, nodeName(ctx, child), "Identifier")) {
            try params.append(ctx.allocator, try parseIdentifier(ctx, child));
        }
    }
    return params.toOwnedSlice(ctx.allocator);
}

fn parseComponentTypeText(ctx: *const TranslationContext, node_id: u32) ![]const u8 {
    try expectNamedNode(ctx, node_id, "ComponentType");
    const string_node = try firstChild(ctx, node_id);
    if (nodeType(ctx, string_node) == .node and std.mem.eql(u8, nodeName(ctx, string_node), "Identifier")) {
        const ident = try parseIdentifier(ctx, string_node);
        return ident.text;
    }
    if (nodeType(ctx, string_node) != .string) return error.ExpectedString;
    const range = nodeRange(ctx, string_node);
    const start = range.start;
    const end = range.end;
    return ctx.source[start..end];
}

fn parsePortRef(ctx: *TranslationContext, node_id: u32) anyerror!ast.SignalSource {
    try expectNamedNode(ctx, node_id, "PortRef");
    const child = try firstChild(ctx, node_id);
    if (nodeType(ctx, child) != .node) return error.InvalidPortReference;
    const name = nodeName(ctx, child);
    if (std.mem.eql(u8, name, "Concat")) return parseConcat(ctx, child);
    if (std.mem.eql(u8, name, "IndexedRef")) return parseIndexedRef(ctx, child);
    return error.InvalidPortReference;
}

fn parseConcat(ctx: *TranslationContext, node_id: u32) anyerror!ast.SignalSource {
    try expectNamedNode(ctx, node_id, "Concat");
    const seq = try firstChild(ctx, node_id);
    var parts: std.ArrayList(ast.SignalSource) = .{};
    if (nodeType(ctx, seq) == .node and std.mem.eql(u8, nodeName(ctx, seq), "PortRef")) {
        try parts.append(ctx.allocator, try parsePortRef(ctx, seq));
    } else if (nodeType(ctx, seq) == .sequence) {
        const len = childCount(ctx, seq);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const c = try childAt(ctx, seq, i);
            if (nodeType(ctx, c) == .node and std.mem.eql(u8, nodeName(ctx, c), "PortRef")) {
                try parts.append(ctx.allocator, try parsePortRef(ctx, c));
            }
        }
    } else return error.InvalidConcat;
    if (parts.items.len == 0) return error.InvalidConcat;
    return .{ .concat = .{
        .parts = try parts.toOwnedSlice(ctx.allocator),
        .span = nodeSpan(ctx, node_id),
    } };
}

fn parseIndexedRef(ctx: *TranslationContext, node_id: u32) anyerror!ast.SignalSource {
    try expectNamedNode(ctx, node_id, "IndexedRef");
    const child = try firstChild(ctx, node_id);
    var base_node: ?u32 = null;
    var sub_node: ?u32 = null;
    if (nodeType(ctx, child) == .node) {
        const cname = nodeName(ctx, child);
        if (std.mem.eql(u8, cname, "BaseRef")) base_node = child;
    } else if (nodeType(ctx, child) == .sequence) {
        const len = childCount(ctx, child);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const c = try childAt(ctx, child, i);
            if (nodeType(ctx, c) != .node) continue;
            const cname = nodeName(ctx, c);
            if (std.mem.eql(u8, cname, "BaseRef")) base_node = c;
            if (std.mem.eql(u8, cname, "Subscript")) sub_node = c;
        }
    }
    const bn = base_node orelse return error.InvalidIndexedRef;
    const base_source = try parseBaseRef(ctx, bn);
    if (sub_node) |sn| {
        const heap_source = try ctx.allocator.create(ast.SignalSource);
        heap_source.* = base_source;
        return parseSubscript(ctx, sn, heap_source);
    }
    return base_source;
}

fn parseSubscript(ctx: *TranslationContext, node_id: u32, source: *ast.SignalSource) anyerror!ast.SignalSource {
    try expectNamedNode(ctx, node_id, "Subscript");
    const seq = try firstChild(ctx, node_id);
    var integers: std.ArrayList(u8) = .{};
    defer integers.deinit(ctx.allocator);
    if (nodeType(ctx, seq) == .node and std.mem.eql(u8, nodeName(ctx, seq), "Integer")) {
        const w = try parseIntegerAsWidth(ctx, seq);
        try integers.append(ctx.allocator, w.literal);
    } else if (nodeType(ctx, seq) == .sequence) {
        const len = childCount(ctx, seq);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const c = try childAt(ctx, seq, i);
            if (nodeType(ctx, c) == .node and std.mem.eql(u8, nodeName(ctx, c), "Integer")) {
                const w = try parseIntegerAsWidth(ctx, c);
                try integers.append(ctx.allocator, w.literal);
            }
        }
    } else return error.InvalidSubscript;
    if (integers.items.len == 1) {
        return .{ .indexed = .{
            .source = source,
            .bit = integers.items[0],
            .span = nodeSpan(ctx, node_id),
        } };
    }
    if (integers.items.len == 2) {
        return .{ .sliced = .{
            .source = source,
            .lo = integers.items[0],
            .hi = integers.items[1],
            .span = nodeSpan(ctx, node_id),
        } };
    }
    return error.InvalidSubscript;
}

fn parseBaseRef(ctx: *TranslationContext, node_id: u32) anyerror!ast.SignalSource {
    try expectNamedNode(ctx, node_id, "BaseRef");
    const payload = try firstChild(ctx, node_id);
    switch (nodeType(ctx, payload)) {
        .node => {
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
        .sequence => {
            const seq_len = childCount(ctx, payload);
            if (seq_len != 3) return error.InvalidPortReference;
            const left = try childAt(ctx, payload, 0);
            const right = try childAt(ctx, payload, 2);

            if (nodeType(ctx, left) == .node and std.mem.eql(u8, nodeName(ctx, left), "Identifier")) {
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

            if (nodeType(ctx, left) == .node and std.mem.eql(u8, nodeName(ctx, left), "AnonDecl")) {
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
    if (nodeType(ctx, seq) != .sequence) return error.InvalidBusType;

    var connections: std.ArrayList(ast.PortConnection) = .{};
    const seq_len = childCount(ctx, seq);
    var index: usize = 0;
    while (index < seq_len) : (index += 1) {
        const child = try childAt(ctx, seq, index);
        if (nodeType(ctx, child) == .node and std.mem.eql(u8, nodeName(ctx, child), "Identifier")) {
            if (index + 2 >= seq_len) return error.InvalidBusType;
            const maybe_equal = try childAt(ctx, seq, index + 1);
            const maybe_ref = try childAt(ctx, seq, index + 2);
            if (nodeType(ctx, maybe_equal) != .string) return error.InvalidBusType;
            if (nodeType(ctx, maybe_ref) != .node or !std.mem.eql(u8, nodeName(ctx, maybe_ref), "PortRef")) {
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
    if (nodeType(ctx, seq) != .sequence) return error.InvalidAnonymousDeclaration;
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
    if (nodeType(ctx, seq) != .sequence) return error.InvalidImportDecl;

    const seq_len = childCount(ctx, seq);
    if (seq_len < 4) return error.InvalidImportDecl;
    const alias_node = try childAt(ctx, seq, 1);
    const path_node = try childAt(ctx, seq, 3);

    const alias = try parseIdentifier(ctx, alias_node);
    if (nodeType(ctx, path_node) != .string) return error.InvalidImportDecl;
    const path_range = nodeRange(ctx, path_node);
    const path_start = path_range.start;
    const path_end = path_range.end;

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
    if (nodeType(ctx, seq) != .sequence) return error.InvalidInputDecl;
    const len = childCount(ctx, seq);

    var parameters: []const ast.Identifier = &.{};
    var width: ?ast.WidthSpec = null;
    var ident_list_node: ?u32 = null;

    var i: usize = 0;
    while (i < len) : (i += 1) {
        const child = try childAt(ctx, seq, i);
        if (nodeType(ctx, child) != .node) continue;
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
    if (nodeType(ctx, payload) == .node) {
        try names.append(ctx.allocator, try parseIdentifier(ctx, payload));
    } else {
        const payload_len = childCount(ctx, payload);
        var i: usize = 0;
        while (i < payload_len) : (i += 1) {
            const c = try childAt(ctx, payload, i);
            if (nodeType(ctx, c) == .node and std.mem.eql(u8, nodeName(ctx, c), "Identifier")) {
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
    if (nodeType(ctx, seq) != .sequence) return error.InvalidDeclaration;
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
        if (nodeType(ctx, child) != .node) continue;
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

/// The one label -> message table for the grammar's thrown labels
/// (proto-circ.peg). Bound into every Parser, so a hard failure's
/// ParseFailure carries the same text a recovered error node gets from
/// collectErrorMarks.
pub const circ_label_messages = [_]parser.runtime.LabelMessage{
    .{ .label = "trailing", .message = "unexpected input; expected a declaration" },
    .{ .label = "busname", .message = "expected a port name" },
    .{ .label = "busassign", .message = "expected '=' after the port name" },
    .{ .label = "busvalue", .message = "expected a signal reference after '='" },
    .{ .label = "busclose", .message = "expected ')' to close the connection list" },
};

fn labelMessage(label: []const u8) []const u8 {
    for (&circ_label_messages) |lm| {
        if (std.mem.eql(u8, lm.label, label)) return lm.message;
    }
    return "syntax error";
}

comptime {
    // Every bound label must exist in the grammar's string table, and every
    // label with a recovery production must have a message, so a new ^label
    // in the .peg fails the build here instead of surfacing "syntax error".
    for (&circ_label_messages) |lm| {
        if (parser.Parser.labelId(lm.label) == null) {
            @compileError("translate.zig binds a label the grammar does not define: " ++ lm.label);
        }
    }
    for (parser.bytecode.rxps, 0..) |addr, i| {
        if (addr != -1 and std.mem.eql(u8, labelMessage(parser.bytecode.strs[i]), "syntax error")) {
            @compileError("grammar label without a message in circ_label_messages: " ++ parser.bytecode.strs[i]);
        }
    }
    std.debug.assert(parser.entry_rule == .Program);
    // The left-recursion opcodes never appear in the shipped bytecode.
    std.debug.assert(parser.left_recursive_rules.len == 0);
}

/// Walk the recovered parse tree collecting error markers: error
/// nodes (a recovered label throw, named after the label) and RecoverLine
/// nodes (a wholly-unparseable line). The --analyze surface turns these
/// into syntax diagnostics while the valid declarations still resolve.
fn collectErrorMarks(ctx: *TranslationContext, node_id: u32, marks: *std.ArrayList(ast.ErrorMark)) anyerror!void {
    const t = nodeType(ctx, node_id);
    if (t == .err) {
        try marks.append(ctx.allocator, .{ .span = nodeSpan(ctx, node_id), .message = labelMessage(nodeName(ctx, node_id)) });
        return;
    }
    if (t == .node and std.mem.eql(u8, nodeName(ctx, node_id), "RecoverLine")) {
        try marks.append(ctx.allocator, .{ .span = nodeSpan(ctx, node_id), .message = "unexpected input; expected a declaration" });
        return;
    }
    if (t == .node or t == .sequence) {
        const len = childCount(ctx, node_id);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const child = childAt(ctx, node_id, i) catch break;
            try collectErrorMarks(ctx, child, marks);
        }
    }
}

/// Dispatch one top-level Program child. Parse failures are swallowed so a
/// single mangled declaration never aborts the whole file (the syntax
/// error is reported separately via collectErrorMarks); RecoverLine and
/// other unrecognized nodes are skipped here.
fn translateTopLevel(
    ctx: *TranslationContext,
    child: u32,
    imports: *std.ArrayList(ast.Import),
    inputs: *std.ArrayList(ast.InputDecl),
    outputs: *std.ArrayList(ast.OutputDecl),
    components: *std.ArrayList(ast.ComponentInstance),
) !void {
    const name = nodeName(ctx, child);
    if (std.mem.eql(u8, name, "ImportDecl")) {
        if (parseImportDecl(ctx, child)) |imp| {
            try imports.append(ctx.allocator, imp);
        } else |_| {}
    } else if (std.mem.eql(u8, name, "InputDecl")) {
        if (parseInputDeclNode(ctx, child)) |in| {
            try inputs.append(ctx.allocator, in);
        } else |_| {}
    } else if (std.mem.eql(u8, name, "Declaration")) {
        parseDeclaration(ctx, child, outputs, components) catch {};
    }
}

fn translateTree(ctx: *TranslationContext) !ast.File {
    // An empty input captures nothing, so there is no root: the same
    // error.ParsingFailed the c-archive's TreeRoot=false used to produce.
    const root = ctx.tree.root() orelse return error.ParsingFailed;
    try expectNamedNode(ctx, root, "Program");

    var imports: std.ArrayList(ast.Import) = .{};
    var inputs: std.ArrayList(ast.InputDecl) = .{};
    var outputs: std.ArrayList(ast.OutputDecl) = .{};
    var components: std.ArrayList(ast.ComponentInstance) = .{};
    var errors: std.ArrayList(ast.ErrorMark) = .{};

    const payload = try firstChild(ctx, root);
    if (nodeType(ctx, payload) == .sequence) {
        const len = childCount(ctx, payload);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const child = try childAt(ctx, payload, i);
            if (nodeType(ctx, child) != .node) continue;
            try translateTopLevel(ctx, child, &imports, &inputs, &outputs, &components);
        }
    } else if (nodeType(ctx, payload) == .node) {
        try translateTopLevel(ctx, payload, &imports, &inputs, &outputs, &components);
    } else {
        return error.InvalidProgram;
    }

    try collectErrorMarks(ctx, root, &errors);

    return .{
        .imports = try imports.toOwnedSlice(ctx.allocator),
        .inputs = try inputs.toOwnedSlice(ctx.allocator),
        .outputs = try outputs.toOwnedSlice(ctx.allocator),
        .components = try components.toOwnedSlice(ctx.allocator),
        .span = nodeSpan(ctx, root),
        .errors = try errors.toOwnedSlice(ctx.allocator),
    };
}

pub const ParseFailure = struct {
    start_line: u32,
    start_col: u32,
    end_line: u32,
    end_col: u32,
    message: []const u8,
};

pub fn parseSource(allocator: std.mem.Allocator, file_id: u32, source: []const u8) !ast.File {
    return parseSourceCapturing(allocator, file_id, source, null);
}

/// Like parseSource, but on a parse failure fills `failure_out` (when
/// given) with the labeled ParsingError's position and message. The
/// --analyze surface uses this to emit a located syntax diagnostic
/// instead of a generic one.
///
/// The parser (and the tree it owns) lives only for this call: ast.File
/// never aliases tree memory, since identifiers slice `source` and error
/// messages are comptime literals.
pub fn parseSourceCapturing(
    allocator: std.mem.Allocator,
    file_id: u32,
    source: []const u8,
    failure_out: ?*ParseFailure,
) !ast.File {
    var p = try parser.Parser.init(allocator);
    defer p.deinit();
    p.setLabelMessages(&circ_label_messages);

    const tree = p.parse(source) catch |err| switch (err) {
        error.ParseFailed => {
            if (failure_out) |out| {
                const last = p.lastError();
                const start: usize = last.start;
                // `end` is -1 when nothing failed; clamp like the c-archive path did.
                const end: usize = @intCast(@max(last.end, 0));
                const start_lc = offsetToLineCol(source, start);
                const end_lc = offsetToLineCol(source, end);
                out.* = .{
                    .start_line = start_lc.line,
                    .start_col = start_lc.col,
                    .end_line = end_lc.line,
                    .end_col = end_lc.col,
                    .message = try last.messageAlloc(allocator, &parser.bytecode, p.messages()),
                };
            }
            return error.ParsingFailed;
        },
        error.OutOfMemory => return error.OutOfMemory,
        // verifyTables runs in the generated file's own test.
        error.InvalidBytecode => unreachable,
    };

    var ctx = TranslationContext{
        .allocator = allocator,
        .tree = tree,
        .source = source,
        .file_id = file_id,
    };
    return translateTree(&ctx);
}
