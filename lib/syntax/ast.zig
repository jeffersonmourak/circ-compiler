const std = @import("std");
pub const Span = @import("span.zig").Span;

pub const File = struct {
    imports: []const Import,
    inputs: []const InputDecl,
    outputs: []const OutputDecl,
    components: []const ComponentInstance,
    span: Span,
};

pub const Import = struct {
    alias: Identifier,
    path: StringLiteral,
    span: Span,
};

pub const InputDecl = struct {
    names: []const Identifier,
    parameters: []const Identifier = &.{},
    span: Span,
};

pub const OutputDecl = struct {
    name: Identifier,
    value: SignalSource,
    span: Span,
};

pub const ComponentInstance = struct {
    type_name: Identifier,
    instance_name: ?Identifier,
    ports: []const PortConnection,
    width_args: []const WidthSpec = &.{},
    span: Span,
};

pub const PortConnection = struct {
    port: Identifier,
    value: SignalSource,
    span: Span,
};

pub const SignalSource = union(enum) {
    named: NamedSignalRef,
    anonymous: *const ComponentInstance,
    indexed: IndexedSignalSource,
    sliced: SlicedSignalSource,
    concat: ConcatSignalSource,
};

pub const NamedSignalRef = struct {
    target: Identifier,
    port: Identifier,
    span: Span,
};

pub const IndexedSignalSource = struct {
    source: *const SignalSource,
    bit: u8,
    span: Span,
};

pub const SlicedSignalSource = struct {
    source: *const SignalSource,
    lo: u8,
    hi: u8,
    span: Span,
};

pub const ConcatSignalSource = struct {
    parts: []const SignalSource,
    span: Span,
};

pub const WidthSpec = union(enum) {
    literal: u8,
    parameter: []const u8,
};

pub const Identifier = struct {
    text: []const u8,
    span: Span,
    width: ?WidthSpec = null,
};

pub const StringLiteral = struct {
    text: []const u8,
    span: Span,
};

test "ast nodes carry span data" {
    const id_span = Span{
        .file_id = 0,
        .start_line = 3,
        .start_col = 5,
        .end_line = 3,
        .end_col = 10,
    };

    const output_span = Span{
        .file_id = 0,
        .start_line = 7,
        .start_col = 1,
        .end_line = 7,
        .end_col = 21,
    };

    const output_decl = OutputDecl{
        .name = Identifier{ .text = "result", .span = id_span },
        .value = .{
            .named = NamedSignalRef{
                .target = Identifier{ .text = "gate1", .span = id_span },
                .port = Identifier{ .text = "out", .span = id_span },
                .span = id_span,
            },
        },
        .span = output_span,
    };

    try std.testing.expectEqual(@as(u32, 3), output_decl.name.span.start_line);
    try std.testing.expectEqual(@as(u32, 1), output_decl.span.start_col);
    try std.testing.expectEqualStrings("gate1", output_decl.value.named.target.text);
}
