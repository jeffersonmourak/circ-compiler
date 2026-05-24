const std = @import("std");

pub const Span = struct {
    file_id: u32,
    start_line: u32,
    start_col: u32,
    end_line: u32,
    end_col: u32,
};

pub const FileId = struct { value: u32 };
pub const InputId = struct { value: u32 };
pub const OutputId = struct { value: u32 };
pub const ComponentId = struct { value: u32 };
pub const InvalidComponentId = ComponentId{ .value = std.math.maxInt(u32) };

pub const PrimitiveKind = enum {
    and_gate,
    not_gate,
    wire,
    led,
    input_pin,
    output_pin,
};

pub const UnresolvedRef = struct {
    name: []const u8,
    span: Span,
};

pub const Slice = struct {
    lo: u8,
    hi: u8,
};

pub const ComponentKind = union(enum) {
    primitive: PrimitiveKind,
    sub_circuit_ref: UnresolvedRef,
    unresolved_name: []const u8,
    /// Bit-range extraction component synthesized by the resolver when
    /// lowering AST `.indexed` / `.sliced` SignalSource variants. Carries
    /// the half-open range `[lo, hi)`; the IR `Component.width` field is
    /// set to `hi - lo`. The source feeds in through a regular IR
    /// Connection (`source.out -> slice.in`), so name resolution and
    /// loop detection see slice components like any other primitive.
    slice: Slice,
    /// Bit concatenation synthesized by the resolver when lowering an
    /// AST `.concat` SignalSource. Operand inputs flow through regular
    /// IR Connections with port names `"operand_<i>"`; the destination
    /// width on `Component.width` is the sum of operand widths. The
    /// arity is implicit in how many connections target this concat.
    concat,
};

pub const Component = struct {
    id: ComponentId,
    kind: ComponentKind,
    instance_name: ?[]const u8,
    span: Span,
    width: u8 = 1,
};

pub const SignalEndpoint = struct {
    component: ComponentId,
    port: []const u8,
};

pub const PortEndpoint = struct {
    component: ComponentId,
    port: []const u8,
};

pub const Connection = struct {
    from: SignalEndpoint,
    to: PortEndpoint,
    span: Span,
};

pub const InputPin = struct {
    id: InputId,
    name: []const u8,
    component: ComponentId,
    span: Span,
    width: u8 = 1,
};

pub const OutputPin = struct {
    id: OutputId,
    name: []const u8,
    driver: SignalEndpoint,
    span: Span,
    width: u8 = 1,
};

pub const UnresolvedImport = struct {
    alias: []const u8,
    path: []const u8,
    span: Span,
    implicit_builtin: bool = false,
};

pub const ResolvedImport = struct {
    importing_file: FileId,
    alias: []const u8,
    target_file: FileId,
    span: Span,
};

pub const Module = struct {
    file_id: FileId,
    inputs: []const InputPin,
    outputs: []const OutputPin,
    components: []const Component,
    connections: []const Connection,
    imports: []const UnresolvedImport,
};

pub const Project = struct {
    files: []const Module,
    root_file_id: FileId,
    import_table: []const ResolvedImport,
    file_paths: []const []const u8,
    source_blobs: []const []const u8,
};

test "ir types construct and round-trip fields" {
    const span = Span{
        .file_id = 0,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 12,
    };

    const input_component_id = ComponentId{ .value = 0 };
    const and_component_id = ComponentId{ .value = 1 };

    const components = [_]Component{
        .{
            .id = input_component_id,
            .kind = .{ .primitive = .input_pin },
            .instance_name = "a",
            .span = span,
        },
        .{
            .id = and_component_id,
            .kind = .{ .primitive = .and_gate },
            .instance_name = "gate1",
            .span = span,
        },
    };

    const input_pins = [_]InputPin{
        .{
            .id = .{ .value = 0 },
            .name = "a",
            .component = input_component_id,
            .span = span,
        },
    };

    const output_pins = [_]OutputPin{
        .{
            .id = .{ .value = 0 },
            .name = "result",
            .driver = .{
                .component = and_component_id,
                .port = "out",
            },
            .span = span,
        },
    };

    const connections = [_]Connection{
        .{
            .from = .{
                .component = input_component_id,
                .port = "out",
            },
            .to = .{
                .component = and_component_id,
                .port = "a",
            },
            .span = span,
        },
    };

    const imports = [_]UnresolvedImport{
        .{
            .alias = "dep",
            .path = "dep.circ",
            .span = span,
        },
    };

    const module = Module{
        .file_id = .{ .value = 0 },
        .inputs = &input_pins,
        .outputs = &output_pins,
        .components = &components,
        .connections = &connections,
        .imports = &imports,
    };

    try std.testing.expectEqual(@as(u32, 0), module.file_id.value);
    try std.testing.expectEqual(@as(usize, 2), module.components.len);
    try std.testing.expectEqualStrings("gate1", module.components[1].instance_name.?);
    try std.testing.expectEqual(@as(u32, 1), module.connections[0].to.component.value);
    try std.testing.expectEqualStrings("dep.circ", module.imports[0].path);
}
