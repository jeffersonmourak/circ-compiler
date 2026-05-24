const std = @import("std");
const ast = @import("translate").Ast;
const ir = @import("ir_types");

/// Concrete binding of a parametric width name (e.g. `W` in `input<W> a`)
/// to a literal width. The single-file resolver consults this table when
/// it encounters a `WidthSpec.parameter` reference; without a matching
/// entry the resolver returns `error.UnboundParameter`. Empty bindings
/// preserve pre-S7 behavior for non-parametric calls.
pub const WidthBinding = struct {
    name: []const u8,
    value: u8,
};

const PendingPorts = struct {
    component_id: ir.ComponentId,
    ports: []const ast.PortConnection,
};

const ResolveContext = struct {
    allocator: std.mem.Allocator,
    file: ast.File,
    imports: std.ArrayList(ir.UnresolvedImport),
    input_pins: std.ArrayList(ir.InputPin),
    output_pins: std.ArrayList(ir.OutputPin),
    components: std.ArrayList(ir.Component),
    connections: std.ArrayList(ir.Connection),
    pending_ports: std.ArrayList(PendingPorts),
    name_to_component: std.StringHashMap(ir.ComponentId),
    import_aliases: std.StringHashMap(void),
    next_component_id: u32,
    width_bindings: []const WidthBinding,
};

fn toIrSpan(span: anytype) ir.Span {
    return .{
        .file_id = span.file_id,
        .start_line = span.start_line,
        .start_col = span.start_col,
        .end_line = span.end_line,
        .end_col = span.end_col,
    };
}

fn widthFromSpec(ctx: *const ResolveContext, spec: ?ast.WidthSpec) !u8 {
    const w = spec orelse return 1;
    return switch (w) {
        .literal => |n| n,
        .parameter => |name| blk: {
            for (ctx.width_bindings) |binding| {
                if (std.mem.eql(u8, binding.name, name)) break :blk binding.value;
            }
            break :blk error.UnboundParameter;
        },
    };
}

fn isPrimitive(name: []const u8) ?ir.PrimitiveKind {
    if (std.mem.eql(u8, name, "and")) return .and_gate;
    if (std.mem.eql(u8, name, "not")) return .not_gate;
    if (std.mem.eql(u8, name, "wire")) return .wire;
    if (std.mem.eql(u8, name, "led")) return .led;
    if (std.mem.eql(u8, name, "input_pin")) return .input_pin;
    if (std.mem.eql(u8, name, "output_pin")) return .output_pin;
    return null;
}

fn nextComponentId(ctx: *ResolveContext) ir.ComponentId {
    const id = ir.ComponentId{ .value = ctx.next_component_id };
    ctx.next_component_id += 1;
    return id;
}

fn ensureNamedReference(ctx: *ResolveContext, named: ast.NamedSignalRef) !ir.SignalEndpoint {
    const component_id = ctx.name_to_component.get(named.target.text) orelse {
        return .{
            .component = ir.InvalidComponentId,
            .port = named.port.text,
        };
    };
    return .{
        .component = component_id,
        .port = named.port.text,
    };
}

fn addComponent(
    ctx: *ResolveContext,
    component_ast: ast.ComponentInstance,
) !ir.ComponentId {
    const id = nextComponentId(ctx);

    const kind = if (isPrimitive(component_ast.type_name.text)) |primitive|
        ir.ComponentKind{ .primitive = primitive }
    else if (ctx.import_aliases.contains(component_ast.type_name.text))
        ir.ComponentKind{
            .sub_circuit_ref = .{
                .name = component_ast.type_name.text,
                .span = toIrSpan(component_ast.type_name.span),
            },
        }
    else
        ir.ComponentKind{ .unresolved_name = component_ast.type_name.text };

    const width = try widthFromSpec(ctx, component_ast.type_name.width);

    try ctx.components.append(ctx.allocator, .{
        .id = id,
        .kind = kind,
        .instance_name = if (component_ast.instance_name) |name| name.text else null,
        .span = toIrSpan(component_ast.span),
        .width = width,
    });

    if (component_ast.instance_name) |name| {
        try ctx.name_to_component.put(name.text, id);
    }

    try ctx.pending_ports.append(ctx.allocator, .{
        .component_id = id,
        .ports = component_ast.ports,
    });

    return id;
}

fn synthesizeSlice(
    ctx: *ResolveContext,
    inner: ast.SignalSource,
    lo: u8,
    hi: u8,
    span: ast.Span,
) anyerror!ir.SignalEndpoint {
    const source_endpoint = try resolveSource(ctx, inner);
    const slice_id = nextComponentId(ctx);
    // Width must stay >= 1 because the engine's tier dispatch asserts
    // `1 <= width <= MAX_WIDTH`. Inverted ranges (`hi <= lo`) are caught
    // by the validator; the placeholder width=1 here keeps the IR
    // structurally valid until the diagnostic surfaces.
    const width: u8 = if (hi > lo) hi - lo else 1;
    try ctx.components.append(ctx.allocator, .{
        .id = slice_id,
        .kind = .{ .slice = .{ .lo = lo, .hi = hi } },
        .instance_name = null,
        .span = toIrSpan(span),
        .width = width,
    });
    if (isValidEndpoint(source_endpoint)) {
        try ctx.connections.append(ctx.allocator, .{
            .from = source_endpoint,
            .to = .{ .component = slice_id, .port = "in" },
            .span = toIrSpan(span),
        });
    }
    return .{ .component = slice_id, .port = "out" };
}

fn lookupComponentWidth(ctx: *ResolveContext, id: ir.ComponentId) u8 {
    // Component lists grow as the resolver walks; for a freshly
    // synthesized operand the entry is already in `ctx.components` by
    // the time we look it up here. Falling back to 1 keeps the
    // arithmetic well-defined when the lookup misses (an unresolved
    // reference, caught by a separate pass).
    for (ctx.components.items) |comp| {
        if (comp.id.value == id.value) return comp.width;
    }
    return 1;
}

fn synthesizeConcat(
    ctx: *ResolveContext,
    parts: []const ast.SignalSource,
    span: ast.Span,
) anyerror!ir.SignalEndpoint {
    var operand_endpoints: std.ArrayList(ir.SignalEndpoint) = .{};
    defer operand_endpoints.deinit(ctx.allocator);
    for (parts) |part| {
        const ep = try resolveSource(ctx, part);
        try operand_endpoints.append(ctx.allocator, ep);
    }

    var total_width: u8 = 0;
    for (operand_endpoints.items) |ep| {
        if (isValidEndpoint(ep)) total_width += lookupComponentWidth(ctx, ep.component);
    }
    if (total_width == 0) total_width = 1;

    const concat_id = nextComponentId(ctx);
    try ctx.components.append(ctx.allocator, .{
        .id = concat_id,
        .kind = .concat,
        .instance_name = null,
        .span = toIrSpan(span),
        .width = total_width,
    });

    for (operand_endpoints.items, 0..) |ep, idx| {
        if (!isValidEndpoint(ep)) continue;
        const port_name = try std.fmt.allocPrint(ctx.allocator, "operand_{d}", .{idx});
        try ctx.connections.append(ctx.allocator, .{
            .from = ep,
            .to = .{ .component = concat_id, .port = port_name },
            .span = toIrSpan(span),
        });
    }

    return .{ .component = concat_id, .port = "out" };
}

fn resolveSource(ctx: *ResolveContext, source: ast.SignalSource) anyerror!ir.SignalEndpoint {
    return switch (source) {
        .named => |named| try ensureNamedReference(ctx, named),
        .anonymous => |anonymous_component| blk: {
            const anonymous_id = try addComponent(ctx, anonymous_component.*);
            break :blk .{
                .component = anonymous_id,
                .port = "out",
            };
        },
        // Bit-index `a[i]` is a width-1 slice [i..i+1); the resolver
        // collapses both AST shapes onto the same IR engine kind.
        .indexed => |idx| try synthesizeSlice(ctx, idx.source.*, idx.bit, idx.bit + 1, idx.span),
        .sliced => |s| try synthesizeSlice(ctx, s.source.*, s.lo, s.hi, s.span),
        .concat => |c| try synthesizeConcat(ctx, c.parts, c.span),
    };
}

fn isValidEndpoint(endpoint: ir.SignalEndpoint) bool {
    return endpoint.component.value != ir.InvalidComponentId.value;
}

fn resolvePendingPorts(ctx: *ResolveContext) anyerror!void {
    var index: usize = 0;
    while (index < ctx.pending_ports.items.len) : (index += 1) {
        const pending = ctx.pending_ports.items[index];
        for (pending.ports) |port_connection| {
            const from_endpoint = try resolveSource(ctx, port_connection.value);
            if (!isValidEndpoint(from_endpoint)) continue;
            try ctx.connections.append(ctx.allocator, .{
                .from = from_endpoint,
                .to = .{
                    .component = pending.component_id,
                    .port = port_connection.port.text,
                },
                .span = toIrSpan(port_connection.span),
            });
        }
    }
}

pub fn resolve(allocator: std.mem.Allocator, file: ast.File, file_id: u32) anyerror!ir.Module {
    return resolveWithBindings(allocator, file, file_id, &.{});
}

pub fn resolveWithBindings(
    allocator: std.mem.Allocator,
    file: ast.File,
    file_id: u32,
    width_bindings: []const WidthBinding,
) anyerror!ir.Module {
    var ctx = ResolveContext{
        .allocator = allocator,
        .file = file,
        .imports = .{},
        .input_pins = .{},
        .output_pins = .{},
        .components = .{},
        .connections = .{},
        .pending_ports = .{},
        .name_to_component = std.StringHashMap(ir.ComponentId).init(allocator),
        .import_aliases = std.StringHashMap(void).init(allocator),
        .next_component_id = 0,
        .width_bindings = width_bindings,
    };

    for (file.imports) |import_decl| {
        try ctx.import_aliases.put(import_decl.alias.text, {});
        try ctx.imports.append(allocator, .{
            .alias = import_decl.alias.text,
            .path = import_decl.path.text,
            .span = toIrSpan(import_decl.span),
        });
    }

    for (file.inputs) |input_decl| {
        for (input_decl.names) |name| {
            const width = try widthFromSpec(&ctx, name.width);
            const component_id = nextComponentId(&ctx);
            try ctx.components.append(allocator, .{
                .id = component_id,
                .kind = .{ .primitive = .input_pin },
                .instance_name = name.text,
                .span = toIrSpan(input_decl.span),
                .width = width,
            });
            try ctx.name_to_component.put(name.text, component_id);
            try ctx.input_pins.append(allocator, .{
                .id = .{ .value = @intCast(ctx.input_pins.items.len) },
                .name = name.text,
                .component = component_id,
                .span = toIrSpan(name.span),
                .width = width,
            });
        }
    }

    for (file.components) |component_decl| {
        _ = try addComponent(&ctx, component_decl);
    }

    try resolvePendingPorts(&ctx);

    for (file.outputs) |output_decl| {
        const width = try widthFromSpec(&ctx, output_decl.name.width);
        const output_component_id = nextComponentId(&ctx);
        try ctx.components.append(allocator, .{
            .id = output_component_id,
            .kind = .{ .primitive = .output_pin },
            .instance_name = output_decl.name.text,
            .span = toIrSpan(output_decl.span),
            .width = width,
        });
        try ctx.name_to_component.put(output_decl.name.text, output_component_id);

        const driver = try resolveSource(&ctx, output_decl.value);
        try ctx.output_pins.append(allocator, .{
            .id = .{ .value = @intCast(ctx.output_pins.items.len) },
            .name = output_decl.name.text,
            .driver = driver,
            .span = toIrSpan(output_decl.span),
            .width = width,
        });
        if (!isValidEndpoint(driver)) continue;
        try ctx.connections.append(allocator, .{
            .from = driver,
            .to = .{
                .component = output_component_id,
                .port = "in",
            },
            .span = toIrSpan(output_decl.span),
        });
    }

    return .{
        .file_id = .{ .value = file_id },
        .inputs = try ctx.input_pins.toOwnedSlice(allocator),
        .outputs = try ctx.output_pins.toOwnedSlice(allocator),
        .components = try ctx.components.toOwnedSlice(allocator),
        .connections = try ctx.connections.toOwnedSlice(allocator),
        .imports = try ctx.imports.toOwnedSlice(allocator),
    };
}
