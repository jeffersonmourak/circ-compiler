const std = @import("std");
const full_format = @import("full_format");
const ir = @import("ir_types");

const FullTopology = full_format.FullTopology;
const FullComponentRecord = full_format.FullComponentRecord;
const FullConnectionRecord = full_format.FullConnectionRecord;
const OriginFrame = full_format.OriginFrame;
const ComponentKind = full_format.ComponentKind;

fn appendU32LE(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try out.appendSlice(allocator, &buf);
}

fn appendString(out: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    try appendU32LE(out, allocator, @intCast(str.len));
    try out.appendSlice(allocator, str);
}

pub fn encode(allocator: std.mem.Allocator, topology: FullTopology) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, &full_format.FULL_MAGIC);
    try out.append(allocator, full_format.FULL_VERSION);

    try appendU32LE(&out, allocator, @intCast(topology.components.len));
    for (topology.components) |comp| {
        try appendU32LE(&out, allocator, comp.id);
        try out.append(allocator, @intFromEnum(comp.kind));
        try out.append(allocator, comp.width);
        try appendString(&out, allocator, comp.name);
        try appendU32LE(&out, allocator, @intCast(comp.origin.len));
        for (comp.origin) |frame| {
            try appendString(&out, allocator, frame.alias);
            try appendString(&out, allocator, frame.subcircuit);
            try appendU32LE(&out, allocator, frame.target_file);
        }
        // Kind-dispatched aux suffix. Slice records carry `(lo, hi)`.
        // Other kinds emit zero aux bytes so the existing wire-format
        // bytes are unchanged for unaffected kinds.
        switch (comp.aux) {
            .none => {},
            .slice => |s| {
                try out.append(allocator, s.lo);
                try out.append(allocator, s.hi);
            },
        }
    }

    try appendU32LE(&out, allocator, @intCast(topology.connections.len));
    for (topology.connections) |conn| {
        try appendU32LE(&out, allocator, conn.from_id);
        try appendU32LE(&out, allocator, conn.to_id);
        try out.append(allocator, conn.port);
    }

    return out.toOwnedSlice(allocator);
}

// ---------- IR-walking serializer (slice 4) ----------
// Mirrors lib/topology/serializer.zig:expandModule recursion. The min and
// full serializers must produce identical global-id sequences so a reader
// can zip records by index across the two payloads.

const ExpanderState = struct {
    allocator: std.mem.Allocator,
    project: *const ir.Project,
    components: std.ArrayList(FullComponentRecord),
    connections: std.ArrayList(FullConnectionRecord),
    next_global_id: u32,
};

const BoundInput = struct {
    global_from_id: u32,
};

fn freePartialComponents(allocator: std.mem.Allocator, items: []const FullComponentRecord) void {
    for (items) |comp| {
        allocator.free(comp.name);
        for (comp.origin) |frame| {
            allocator.free(frame.alias);
            allocator.free(frame.subcircuit);
        }
        allocator.free(comp.origin);
    }
}

fn dupOrigin(allocator: std.mem.Allocator, stack: []const OriginFrame) ![]const OriginFrame {
    const dup = try allocator.alloc(OriginFrame, stack.len);
    var built: usize = 0;
    errdefer {
        for (dup[0..built]) |frame| {
            allocator.free(frame.alias);
            allocator.free(frame.subcircuit);
        }
        allocator.free(dup);
    }
    for (stack, dup) |src, *dst| {
        const alias_copy = try allocator.dupe(u8, src.alias);
        errdefer allocator.free(alias_copy);
        const subcircuit_copy = try allocator.dupe(u8, src.subcircuit);
        dst.* = .{ .alias = alias_copy, .subcircuit = subcircuit_copy, .target_file = src.target_file };
        built += 1;
    }
    return dup;
}

fn parsePortByte(name: []const u8) !u8 {
    if (std.mem.eql(u8, name, "in")) return @intFromEnum(full_format.PortName.in);
    if (std.mem.eql(u8, name, "a")) return @intFromEnum(full_format.PortName.a);
    if (std.mem.eql(u8, name, "b")) return @intFromEnum(full_format.PortName.b);
    if (std.mem.eql(u8, name, "out")) return @intFromEnum(full_format.PortName.out);
    // Concat operand ports round-trip as the raw operand index; the
    // decoder disambiguates by `to_comp.kind == concat`.
    if (std.mem.startsWith(u8, name, "operand_")) {
        return std.fmt.parseInt(u8, name["operand_".len..], 10) catch error.UnknownPortName;
    }
    return error.UnknownPortName;
}

fn primitiveToKind(p: ir.PrimitiveKind) ComponentKind {
    return switch (p) {
        .and_gate => .and_gate,
        .not_gate => .not_gate,
        .wire => .wire,
        .led => .led,
        .input_pin => .input_pin,
        .output_pin => .output_pin,
    };
}

fn findComponent(module: *const ir.Module, id: ir.ComponentId) ?*const ir.Component {
    for (module.components) |*comp| {
        if (comp.id.value == id.value) return comp;
    }
    return null;
}

fn resolveSignalGlobalId(
    module: *const ir.Module,
    endpoint: ir.SignalEndpoint,
    local_to_global: std.AutoHashMap(u32, u32),
    sub_output_map: std.AutoHashMap(u32, std.StringHashMap(u32)),
) !u32 {
    const comp = findComponent(module, endpoint.component) orelse return error.ComponentNotFound;
    switch (comp.kind) {
        .primitive, .slice, .concat => return local_to_global.get(endpoint.component.value) orelse error.InternalError,
        .sub_circuit_ref => {
            const outputs = sub_output_map.get(endpoint.component.value) orelse return error.InternalError;
            return outputs.get(endpoint.port) orelse return error.UnknownPortName;
        },
        .unresolved_name => return error.UnresolvedComponent,
        .memory => return error.MemoryNotYetSupported,
    }
}

fn expandModule(
    state: *ExpanderState,
    module: *const ir.Module,
    parent_input_bindings: ?std.StringHashMap(BoundInput),
    origin_stack: *std.ArrayList(OriginFrame),
) !std.StringHashMap(u32) {
    var local_to_global = std.AutoHashMap(u32, u32).init(state.allocator);
    defer local_to_global.deinit();

    var sub_output_map = std.AutoHashMap(u32, std.StringHashMap(u32)).init(state.allocator);
    defer {
        var it = sub_output_map.valueIterator();
        while (it.next()) |map| map.deinit();
        sub_output_map.deinit();
    }

    // Pass 1a: emit in-module primitives, slices, and concats and register
    //          their global IDs. Sub-circuit instances are handled in
    //          Pass 1b so their recursion sees every sibling already in
    //          `local_to_global` regardless of declaration order.
    for (module.components) |comp| {
        switch (comp.kind) {
            .sub_circuit_ref => continue,
            .unresolved_name => return error.UnresolvedComponent,
            .memory => return error.MemoryNotYetSupported,
            else => {},
        }
        switch (comp.kind) {
            .primitive => |p| {
                const global_id = state.next_global_id;
                state.next_global_id += 1;
                try local_to_global.put(comp.id.value, global_id);

                const name_src = comp.instance_name orelse "";
                const name_copy = try state.allocator.dupe(u8, name_src);
                errdefer state.allocator.free(name_copy);
                const origin_copy = try dupOrigin(state.allocator, origin_stack.items);
                errdefer {
                    for (origin_copy) |frame| {
                        state.allocator.free(frame.alias);
                        state.allocator.free(frame.subcircuit);
                    }
                    state.allocator.free(origin_copy);
                }

                try state.components.append(state.allocator, .{
                    .id = global_id,
                    .kind = primitiveToKind(p),
                    .width = comp.width,
                    .name = name_copy,
                    .origin = origin_copy,
                });
            },
            .slice => |s| {
                const global_id = state.next_global_id;
                state.next_global_id += 1;
                try local_to_global.put(comp.id.value, global_id);

                const name_src = comp.instance_name orelse "";
                const name_copy = try state.allocator.dupe(u8, name_src);
                errdefer state.allocator.free(name_copy);
                const origin_copy = try dupOrigin(state.allocator, origin_stack.items);
                errdefer {
                    for (origin_copy) |frame| {
                        state.allocator.free(frame.alias);
                        state.allocator.free(frame.subcircuit);
                    }
                    state.allocator.free(origin_copy);
                }

                try state.components.append(state.allocator, .{
                    .id = global_id,
                    .kind = .slice,
                    .width = comp.width,
                    .name = name_copy,
                    .origin = origin_copy,
                    .aux = .{ .slice = .{ .lo = s.lo, .hi = s.hi } },
                });
            },
            .concat => {
                const global_id = state.next_global_id;
                state.next_global_id += 1;
                try local_to_global.put(comp.id.value, global_id);

                const name_src = comp.instance_name orelse "";
                const name_copy = try state.allocator.dupe(u8, name_src);
                errdefer state.allocator.free(name_copy);
                const origin_copy = try dupOrigin(state.allocator, origin_stack.items);
                errdefer {
                    for (origin_copy) |frame| {
                        state.allocator.free(frame.alias);
                        state.allocator.free(frame.subcircuit);
                    }
                    state.allocator.free(origin_copy);
                }

                try state.components.append(state.allocator, .{
                    .id = global_id,
                    .kind = .concat,
                    .width = comp.width,
                    .name = name_copy,
                    .origin = origin_copy,
                });
            },
            .sub_circuit_ref, .unresolved_name, .memory => unreachable,
        }
    }

    // Pass 1b: recurse into sub-circuit instances. All in-module primitives,
    //          slices, and concats are registered in `local_to_global` by
    //          now, so each instance's input bindings resolve regardless of
    //          declaration order.
    for (module.components) |comp| {
        switch (comp.kind) {
            .sub_circuit_ref => |ref| {
                var child_module: ?*const ir.Module = null;
                var target_file_id: u32 = 0;
                // The import_table lookup resolves the alias to the source
                // file the user wrote the import for (e.g. or.circ for `or`).
                // That is the file id we want in the OriginFrame so tooling
                // sees real source paths in stack traces. The specialized
                // child_module, when present, is the post-substitution body
                // the topology walks; it lives at a synthetic file id that
                // wouldn't make sense for diagnostics.
                //
                // The lookup uses `effectiveSourceFileId` so that nested call
                // sites inside a specialization match against the original
                // callee's imports rather than the spec's synthetic file id
                // (the import_table only has entries for original file ids).
                const lookup_file_id = module.effectiveSourceFileId();
                for (state.project.import_table) |imp| {
                    if (imp.importing_file.value == lookup_file_id.value and std.mem.eql(u8, imp.alias, ref.name)) {
                        target_file_id = imp.target_file.value;
                        child_module = &state.project.files[imp.target_file.value];
                        break;
                    }
                }
                if (ref.specialized_target_file) |spec| {
                    child_module = &state.project.files[spec.value];
                }
                if (child_module == null) return error.ModuleNotFound;

                var input_bindings = std.StringHashMap(BoundInput).init(state.allocator);
                defer input_bindings.deinit();
                for (module.connections) |conn| {
                    if (conn.to.component.value == comp.id.value) {
                        const from_global_id = try resolveSignalGlobalId(module, conn.from, local_to_global, sub_output_map);
                        try input_bindings.put(conn.to.port, .{ .global_from_id = from_global_id });
                    }
                }

                // Push origin frame for this subcircuit instance, recurse, pop on return.
                const frame = OriginFrame{
                    .alias = comp.instance_name orelse "",
                    .subcircuit = ref.name,
                    .target_file = target_file_id,
                };
                try origin_stack.append(state.allocator, frame);

                const child_outputs = expandModule(state, child_module.?, input_bindings, origin_stack) catch |err| {
                    _ = origin_stack.pop();
                    return err;
                };
                _ = origin_stack.pop();
                try sub_output_map.put(comp.id.value, child_outputs);
            },
            else => {},
        }
    }

    // Pass 2: emit module-level connections targeting primitives, slices, or concats in this module.
    for (module.connections) |conn| {
        const to_comp = findComponent(module, conn.to.component) orelse return error.ComponentNotFound;
        switch (to_comp.kind) {
            .primitive, .slice, .concat => {},
            else => continue,
        }

        const from_global_id = try resolveSignalGlobalId(module, conn.from, local_to_global, sub_output_map);
        const to_global_id = local_to_global.get(conn.to.component.value) orelse return error.InternalError;

        try state.connections.append(state.allocator, .{
            .from_id = from_global_id,
            .to_id = to_global_id,
            .port = try parsePortByte(conn.to.port),
        });
    }

    // Boundary: connect parent inputs that drive this module's input pins.
    if (parent_input_bindings) |bindings| {
        for (module.inputs) |input| {
            if (bindings.get(input.name)) |binding| {
                const to_global_id = local_to_global.get(input.component.value) orelse return error.InternalError;
                try state.connections.append(state.allocator, .{
                    .from_id = binding.global_from_id,
                    .to_id = to_global_id,
                    .port = @intFromEnum(full_format.PortName.in),
                });
            }
        }
    }

    // Boundary: return this module's output map for the parent.
    var module_outputs = std.StringHashMap(u32).init(state.allocator);
    errdefer module_outputs.deinit();
    for (module.outputs) |output| {
        const driver_global_id = try resolveSignalGlobalId(module, output.driver, local_to_global, sub_output_map);
        try module_outputs.put(output.name, driver_global_id);
    }

    return module_outputs;
}

pub fn buildFromProject(allocator: std.mem.Allocator, project: *const ir.Project) !FullTopology {
    var state = ExpanderState{
        .allocator = allocator,
        .project = project,
        .components = .{},
        .connections = .{},
        .next_global_id = 0,
    };
    errdefer {
        freePartialComponents(allocator, state.components.items);
        state.components.deinit(allocator);
        state.connections.deinit(allocator);
    }

    var origin_stack: std.ArrayList(OriginFrame) = .{};
    defer origin_stack.deinit(allocator);

    const root_module = &project.files[project.root_file_id.value];
    var output_map = try expandModule(&state, root_module, null, &origin_stack);
    output_map.deinit();

    return FullTopology{
        .components = try state.components.toOwnedSlice(allocator),
        .connections = try state.connections.toOwnedSlice(allocator),
    };
}

pub fn serializeProjectFull(allocator: std.mem.Allocator, project: *const ir.Project) ![]u8 {
    var topo = try buildFromProject(allocator, project);
    defer topo.deinit(allocator);
    return encode(allocator, topo);
}

/// Single-file (no project) full-payload walk. Mirrors lib/topology/serializer.zig's
/// serializeModule: errors on sub_circuit_ref since there is no import_table to
/// resolve against. Used when the CLI compiles a `.circ` that has no imports.
pub fn buildFromModule(allocator: std.mem.Allocator, module: *const ir.Module) !FullTopology {
    var components: std.ArrayList(FullComponentRecord) = .{};
    errdefer {
        freePartialComponents(allocator, components.items);
        components.deinit(allocator);
    }
    var connections: std.ArrayList(FullConnectionRecord) = .{};
    errdefer connections.deinit(allocator);

    for (module.components) |comp| {
        switch (comp.kind) {
            .primitive => |p| {
                const name_src = comp.instance_name orelse "";
                const name_copy = try allocator.dupe(u8, name_src);
                errdefer allocator.free(name_copy);
                const empty_origin = try allocator.alloc(OriginFrame, 0);
                try components.append(allocator, .{
                    .id = comp.id.value,
                    .kind = primitiveToKind(p),
                    .width = comp.width,
                    .name = name_copy,
                    .origin = empty_origin,
                });
            },
            .slice => |s| {
                const name_src = comp.instance_name orelse "";
                const name_copy = try allocator.dupe(u8, name_src);
                errdefer allocator.free(name_copy);
                const empty_origin = try allocator.alloc(OriginFrame, 0);
                try components.append(allocator, .{
                    .id = comp.id.value,
                    .kind = .slice,
                    .width = comp.width,
                    .name = name_copy,
                    .origin = empty_origin,
                    .aux = .{ .slice = .{ .lo = s.lo, .hi = s.hi } },
                });
            },
            .concat => {
                const name_src = comp.instance_name orelse "";
                const name_copy = try allocator.dupe(u8, name_src);
                errdefer allocator.free(name_copy);
                const empty_origin = try allocator.alloc(OriginFrame, 0);
                try components.append(allocator, .{
                    .id = comp.id.value,
                    .kind = .concat,
                    .width = comp.width,
                    .name = name_copy,
                    .origin = empty_origin,
                });
            },
            .sub_circuit_ref => return error.SubCircuitInFlatModule,
            .unresolved_name => return error.UnresolvedComponent,
            .memory => return error.MemoryNotYetSupported,
        }
    }

    for (module.connections) |conn| {
        try connections.append(allocator, .{
            .from_id = conn.from.component.value,
            .to_id = conn.to.component.value,
            .port = try parsePortByte(conn.to.port),
        });
    }

    return FullTopology{
        .components = try components.toOwnedSlice(allocator),
        .connections = try connections.toOwnedSlice(allocator),
    };
}

pub fn serializeModuleFull(allocator: std.mem.Allocator, module: *const ir.Module) ![]u8 {
    var topo = try buildFromModule(allocator, module);
    defer topo.deinit(allocator);
    return encode(allocator, topo);
}

// ---------- Tests ----------

test "full_encode_empty: locks the wire format" {
    const allocator = std.testing.allocator;
    const topo = FullTopology{ .components = &.{}, .connections = &.{} };

    const bytes = try encode(allocator, topo);
    defer allocator.free(bytes);

    // magic(4) + version(1) + num_components(4) + num_connections(4) = 13 bytes
    const expected = [_]u8{
        'C', 'I', 'R', 'F',
        0x02,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    };
    try std.testing.expectEqualSlices(u8, &expected, bytes);
}

test "full_encode: single component with no origin emits expected layout" {
    const allocator = std.testing.allocator;
    const components = [_]FullComponentRecord{
        .{ .id = 7, .kind = .not_gate, .width = 1, .name = "n1", .origin = &.{} },
    };
    const topo = FullTopology{ .components = &components, .connections = &.{} };

    const bytes = try encode(allocator, topo);
    defer allocator.free(bytes);

    // magic(4)+ver(1)+num_components(4) + id(4)+kind(1)+width(1)+name_len(4)+name(2)+origin_len(4) + num_connections(4) = 29
    try std.testing.expectEqual(@as(usize, 29), bytes.len);
    try std.testing.expectEqualSlices(u8, "CIRF", bytes[0..4]);
    try std.testing.expectEqual(@as(u8, 0x02), bytes[4]);
    // num_components = 1
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, bytes[5..9], .little));
    // id = 7
    try std.testing.expectEqual(@as(u32, 7), std.mem.readInt(u32, bytes[9..13], .little));
    // kind = not_gate
    try std.testing.expectEqual(@intFromEnum(full_format.ComponentKind.not_gate), bytes[13]);
    // width = 1
    try std.testing.expectEqual(@as(u8, 1), bytes[14]);
    // name_len = 2
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, bytes[15..19], .little));
    // name = "n1"
    try std.testing.expectEqualSlices(u8, "n1", bytes[19..21]);
    // origin_len = 0
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, bytes[21..25], .little));
    // num_connections = 0
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, bytes[25..29], .little));
}

// ---------- IR-walk tests (slice 4) ----------
// These tests hand-build minimal ir.Project values and verify that buildFromProject
// emits FullComponentRecords with correct names, kinds, and origin chains. The
// fixtures intentionally mirror the shape of ".circ" sources without depending
// on the parser/resolver so the tests stay focused on the serializer's walk.

const span_zero = ir.Span{ .file_id = 0, .start_line = 0, .start_col = 0, .end_line = 0, .end_col = 0 };

fn findByName(components: []const FullComponentRecord, name: []const u8) ?FullComponentRecord {
    for (components) |comp| {
        if (std.mem.eql(u8, comp.name, name)) return comp;
    }
    return null;
}

test "full_walk_primitives_have_empty_origin" {
    const allocator = std.testing.allocator;

    const components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .primitive = .input_pin }, .instance_name = "a", .span = span_zero },
        .{ .id = .{ .value = 1 }, .kind = .{ .primitive = .not_gate }, .instance_name = "n1", .span = span_zero },
        .{ .id = .{ .value = 2 }, .kind = .{ .primitive = .output_pin }, .instance_name = "out", .span = span_zero },
    };
    const connections = [_]ir.Connection{
        .{ .from = .{ .component = .{ .value = 0 }, .port = "out" }, .to = .{ .component = .{ .value = 1 }, .port = "in" }, .span = span_zero },
        .{ .from = .{ .component = .{ .value = 1 }, .port = "out" }, .to = .{ .component = .{ .value = 2 }, .port = "in" }, .span = span_zero },
    };
    const root_module = ir.Module{
        .file_id = .{ .value = 0 },
        .inputs = &.{},
        .outputs = &.{},
        .components = &components,
        .connections = &connections,
        .imports = &.{},
    };
    const project = ir.Project{
        .files = &[_]ir.Module{root_module},
        .root_file_id = .{ .value = 0 },
        .import_table = &.{},
        .file_paths = &.{},
        .source_blobs = &.{},
    };

    var topo = try buildFromProject(allocator, &project);
    defer topo.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), topo.components.len);
    try std.testing.expectEqualStrings("a", topo.components[0].name);
    try std.testing.expectEqualStrings("n1", topo.components[1].name);
    try std.testing.expectEqualStrings("out", topo.components[2].name);
    for (topo.components) |comp| try std.testing.expectEqual(@as(usize, 0), comp.origin.len);
    try std.testing.expectEqual(@as(usize, 2), topo.connections.len);
}

test "full_walk_one_subcircuit_records_origin" {
    const allocator = std.testing.allocator;

    // Subcircuit: my_not.circ — input "in" → not gate → output "out"
    const sub_components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .primitive = .not_gate }, .instance_name = "n1", .span = span_zero },
    };
    const sub_inputs = [_]ir.InputPin{
        .{ .id = .{ .value = 0 }, .name = "in", .component = .{ .value = 0 }, .span = span_zero },
    };
    const sub_outputs = [_]ir.OutputPin{
        .{ .id = .{ .value = 0 }, .name = "out", .driver = .{ .component = .{ .value = 0 }, .port = "out" }, .span = span_zero },
    };
    const sub_module = ir.Module{
        .file_id = .{ .value = 1 },
        .inputs = &sub_inputs,
        .outputs = &sub_outputs,
        .components = &sub_components,
        .connections = &.{},
        .imports = &.{},
    };

    // Root: input "i1" → sub_circuit_ref "combine" of "MyNot" → output "o1"
    const root_components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .primitive = .input_pin }, .instance_name = "i1", .span = span_zero },
        .{ .id = .{ .value = 1 }, .kind = .{ .sub_circuit_ref = .{ .name = "MyNot", .span = span_zero } }, .instance_name = "combine", .span = span_zero },
        .{ .id = .{ .value = 2 }, .kind = .{ .primitive = .output_pin }, .instance_name = "o1", .span = span_zero },
    };
    const root_connections = [_]ir.Connection{
        .{ .from = .{ .component = .{ .value = 0 }, .port = "out" }, .to = .{ .component = .{ .value = 1 }, .port = "in" }, .span = span_zero },
        .{ .from = .{ .component = .{ .value = 1 }, .port = "out" }, .to = .{ .component = .{ .value = 2 }, .port = "in" }, .span = span_zero },
    };
    const root_module = ir.Module{
        .file_id = .{ .value = 0 },
        .inputs = &.{},
        .outputs = &.{},
        .components = &root_components,
        .connections = &root_connections,
        .imports = &.{},
    };

    const import_table = [_]ir.ResolvedImport{
        .{ .importing_file = .{ .value = 0 }, .alias = "MyNot", .target_file = .{ .value = 1 }, .span = span_zero },
    };

    const project = ir.Project{
        .files = &[_]ir.Module{ root_module, sub_module },
        .root_file_id = .{ .value = 0 },
        .import_table = &import_table,
        .file_paths = &.{},
        .source_blobs = &.{},
    };

    var topo = try buildFromProject(allocator, &project);
    defer topo.deinit(allocator);

    // Three primitives total: input_pin (root), not_gate (from sub), output_pin (root).
    // The serializer emits all in-module primitives before recursing into
    // sub-circuit children, so the not_gate lands after the root primitives.
    // Look components up by name rather than asserting a fixed index — emit
    // order is internal and shouldn't be locked in here.
    try std.testing.expectEqual(@as(usize, 3), topo.components.len);

    const i1_comp = findByName(topo.components, "i1") orelse return error.MissingI1;
    const o1_comp = findByName(topo.components, "o1") orelse return error.MissingO1;
    const n1_comp = findByName(topo.components, "n1") orelse return error.MissingN1;

    // Root primitives: empty origin.
    try std.testing.expectEqual(@as(usize, 0), i1_comp.origin.len);
    try std.testing.expectEqual(@as(usize, 0), o1_comp.origin.len);

    // Sub primitive: one-frame origin chain.
    try std.testing.expectEqual(@as(usize, 1), n1_comp.origin.len);
    try std.testing.expectEqualStrings("combine", n1_comp.origin[0].alias);
    try std.testing.expectEqualStrings("MyNot", n1_comp.origin[0].subcircuit);
    try std.testing.expectEqual(@as(u32, 1), n1_comp.origin[0].target_file);
}

test "full_walk_nested_subcircuits" {
    const allocator = std.testing.allocator;

    // Innermost: tiny.circ — input "in" → not gate "deep" → output "out"
    const tiny_components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .primitive = .not_gate }, .instance_name = "deep", .span = span_zero },
    };
    const tiny_module = ir.Module{
        .file_id = .{ .value = 2 },
        .inputs = &[_]ir.InputPin{.{ .id = .{ .value = 0 }, .name = "in", .component = .{ .value = 0 }, .span = span_zero }},
        .outputs = &[_]ir.OutputPin{.{ .id = .{ .value = 0 }, .name = "out", .driver = .{ .component = .{ .value = 0 }, .port = "out" }, .span = span_zero }},
        .components = &tiny_components,
        .connections = &.{},
        .imports = &.{},
    };

    // Middle: wrapper.circ — references "Tiny" via "inner" instance
    const mid_components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .sub_circuit_ref = .{ .name = "Tiny", .span = span_zero } }, .instance_name = "inner", .span = span_zero },
    };
    const mid_module = ir.Module{
        .file_id = .{ .value = 1 },
        .inputs = &[_]ir.InputPin{.{ .id = .{ .value = 0 }, .name = "in", .component = .{ .value = 0 }, .span = span_zero }},
        .outputs = &[_]ir.OutputPin{.{ .id = .{ .value = 0 }, .name = "out", .driver = .{ .component = .{ .value = 0 }, .port = "out" }, .span = span_zero }},
        .components = &mid_components,
        .connections = &.{},
        .imports = &.{},
    };

    // Root: references "Wrapper" via "outer" instance
    const root_components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .sub_circuit_ref = .{ .name = "Wrapper", .span = span_zero } }, .instance_name = "outer", .span = span_zero },
    };
    const root_module = ir.Module{
        .file_id = .{ .value = 0 },
        .inputs = &.{},
        .outputs = &.{},
        .components = &root_components,
        .connections = &.{},
        .imports = &.{},
    };

    const import_table = [_]ir.ResolvedImport{
        .{ .importing_file = .{ .value = 0 }, .alias = "Wrapper", .target_file = .{ .value = 1 }, .span = span_zero },
        .{ .importing_file = .{ .value = 1 }, .alias = "Tiny", .target_file = .{ .value = 2 }, .span = span_zero },
    };

    const project = ir.Project{
        .files = &[_]ir.Module{ root_module, mid_module, tiny_module },
        .root_file_id = .{ .value = 0 },
        .import_table = &import_table,
        .file_paths = &.{},
        .source_blobs = &.{},
    };

    var topo = try buildFromProject(allocator, &project);
    defer topo.deinit(allocator);

    // One primitive emitted: the deeply nested not_gate.
    try std.testing.expectEqual(@as(usize, 1), topo.components.len);
    try std.testing.expectEqualStrings("deep", topo.components[0].name);

    // Two-frame origin chain, outermost first.
    try std.testing.expectEqual(@as(usize, 2), topo.components[0].origin.len);
    try std.testing.expectEqualStrings("outer", topo.components[0].origin[0].alias);
    try std.testing.expectEqualStrings("Wrapper", topo.components[0].origin[0].subcircuit);
    try std.testing.expectEqual(@as(u32, 1), topo.components[0].origin[0].target_file);
    try std.testing.expectEqualStrings("inner", topo.components[0].origin[1].alias);
    try std.testing.expectEqualStrings("Tiny", topo.components[0].origin[1].subcircuit);
    try std.testing.expectEqual(@as(u32, 2), topo.components[0].origin[1].target_file);
}
