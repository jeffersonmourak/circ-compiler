const std = @import("std");
const ir = @import("ir_types");
const format = @import("format");

pub fn serializeModule(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
) ![]u8 {
    var components: std.ArrayList(format.ComponentRecord) = .{};
    defer components.deinit(allocator);
    var connections: std.ArrayList(format.ConnectionRecord) = .{};
    defer connections.deinit(allocator);

    for (module.components) |comp| {
        var aux_lo: u8 = 0;
        var aux_hi: u8 = 0;
        const kind: format.ComponentKind = switch (comp.kind) {
            .primitive => |p| switch (p) {
                .and_gate => .and_gate,
                .not_gate => .not_gate,
                .wire => .wire,
                .led => .led,
                .input_pin => .input_pin,
                .output_pin => .output_pin,
            },
            .slice => |s| blk: {
                aux_lo = s.lo;
                aux_hi = s.hi;
                break :blk .slice;
            },
            else => return error.SubCircuitInFlatModule,
        };
        try components.append(allocator, .{
            .id = comp.id.value,
            .kind = @intFromEnum(kind),
            .width = comp.width,
            .aux_lo = aux_lo,
            .aux_hi = aux_hi,
        });
    }

    for (module.connections) |conn| {
        try connections.append(allocator, .{
            .from_id = conn.from.component.value,
            .to_id = conn.to.component.value,
            .port = @intFromEnum(try parsePortName(conn.to.port)),
        });
    }

    return try encodePayload(allocator, components.items, connections.items);
}

const ExpanderState = struct {
    allocator: std.mem.Allocator,
    project: *const ir.Project,
    components: std.ArrayList(format.ComponentRecord),
    connections: std.ArrayList(format.ConnectionRecord),
    next_global_id: u32,

    pub fn deinit(self: *ExpanderState) void {
        self.components.deinit(self.allocator);
        self.connections.deinit(self.allocator);
    }
};

const BoundInput = struct {
    global_from_id: u32,
};

pub const PinMapping = struct {
    name: []const u8,
    global_id: u32,
};

pub const ProjectTopology = struct {
    payload: []u8,
    input_ids: []PinMapping,
    output_ids: []PinMapping,

    pub fn deinit(self: *ProjectTopology, allocator: std.mem.Allocator) void {
        allocator.free(self.payload);
        allocator.free(self.input_ids);
        allocator.free(self.output_ids);
    }
};

pub fn serializeProjectFull(
    allocator: std.mem.Allocator,
    project: *const ir.Project,
) !ProjectTopology {
    var state = ExpanderState{
        .allocator = allocator,
        .project = project,
        .components = .{},
        .connections = .{},
        .next_global_id = 0,
    };
    defer state.deinit();

    const root_module = &project.files[project.root_file_id.value];

    var root_local_to_global = std.AutoHashMap(u32, u32).init(allocator);
    defer root_local_to_global.deinit();

    var output_map = try expandModule(&state, root_module, null, &root_local_to_global);
    defer output_map.deinit();

    var input_ids_list: std.ArrayList(PinMapping) = .{};
    errdefer input_ids_list.deinit(allocator);
    for (root_module.inputs) |input| {
        const global_id = root_local_to_global.get(input.component.value) orelse continue;
        try input_ids_list.append(allocator, .{ .name = input.name, .global_id = global_id });
    }

    var output_ids_list: std.ArrayList(PinMapping) = .{};
    errdefer output_ids_list.deinit(allocator);
    for (root_module.outputs) |output| {
        const global_id = output_map.get(output.name) orelse continue;
        try output_ids_list.append(allocator, .{ .name = output.name, .global_id = global_id });
    }

    const payload = try encodePayload(allocator, state.components.items, state.connections.items);
    errdefer allocator.free(payload);

    return ProjectTopology{
        .payload = payload,
        .input_ids = try input_ids_list.toOwnedSlice(allocator),
        .output_ids = try output_ids_list.toOwnedSlice(allocator),
    };
}

pub fn serializeProject(
    allocator: std.mem.Allocator,
    project: *const ir.Project,
) ![]u8 {
    const topo = try serializeProjectFull(allocator, project);
    allocator.free(topo.input_ids);
    allocator.free(topo.output_ids);
    return topo.payload;
}

/// Expands a module and returns a map of its output pin names to their global driver component IDs.
/// When `local_to_global_out` is non-null (root call only), the caller's local→global map is
/// populated before `local_to_global` is freed, so the caller can look up root input pin IDs.
fn expandModule(
    state: *ExpanderState,
    module: *const ir.Module,
    parent_input_bindings: ?std.StringHashMap(BoundInput),
    local_to_global_out: ?*std.AutoHashMap(u32, u32),
) !std.StringHashMap(u32) {
    var local_to_global = std.AutoHashMap(u32, u32).init(state.allocator);
    errdefer local_to_global.deinit();

    var sub_output_map = std.AutoHashMap(u32, std.StringHashMap(u32)).init(state.allocator);
    errdefer {
        var it = sub_output_map.valueIterator();
        while (it.next()) |map| map.deinit();
        sub_output_map.deinit();
    }

    // 1. First pass: Assign global IDs to all primitives and recursively expand sub-circuits.
    for (module.components) |comp| {
        switch (comp.kind) {
            .primitive => |p| {
                const global_id = state.next_global_id;
                state.next_global_id += 1;
                try local_to_global.put(comp.id.value, global_id);

                const kind: format.ComponentKind = switch (p) {
                    .and_gate => .and_gate,
                    .not_gate => .not_gate,
                    .wire => .wire,
                    .led => .led,
                    .input_pin => .input_pin,
                    .output_pin => .output_pin,
                };
                try state.components.append(state.allocator, .{
                    .id = global_id,
                    .kind = @intFromEnum(kind),
                    .width = comp.width,
                });
            },
            .slice => |s| {
                const global_id = state.next_global_id;
                state.next_global_id += 1;
                try local_to_global.put(comp.id.value, global_id);

                try state.components.append(state.allocator, .{
                    .id = global_id,
                    .kind = @intFromEnum(format.ComponentKind.slice),
                    .width = comp.width,
                    .aux_lo = s.lo,
                    .aux_hi = s.hi,
                });
            },
            .sub_circuit_ref => |ref| {
                var child_module: ?*const ir.Module = null;
                for (state.project.import_table) |imp| {
                    if (imp.importing_file.value == module.file_id.value and std.mem.eql(u8, imp.alias, ref.name)) {
                        child_module = &state.project.files[imp.target_file.value];
                        break;
                    }
                }
                if (child_module == null) return error.ModuleNotFound;

                var input_bindings = std.StringHashMap(BoundInput).init(state.allocator);
                errdefer input_bindings.deinit();
                for (module.connections) |conn| {
                    if (conn.to.component.value == comp.id.value) {
                        const from_global_id = try resolveSignalGlobalId(module, conn.from, local_to_global, sub_output_map);
                        try input_bindings.put(conn.to.port, .{ .global_from_id = from_global_id });
                    }
                }

                const child_outputs = try expandModule(state, child_module.?, input_bindings, null);
                try sub_output_map.put(comp.id.value, child_outputs);
                input_bindings.deinit();
            },
            .unresolved_name => return error.UnresolvedComponent,
        }
    }

    // 2. Second pass: Handle module-level connections (rewiring primitives and slices)
    for (module.connections) |conn| {
        const to_comp = findComponent(module, conn.to.component) orelse return error.ComponentNotFound;
        switch (to_comp.kind) {
            .primitive, .slice => {},
            else => continue,
        }

        const from_global_id = try resolveSignalGlobalId(module, conn.from, local_to_global, sub_output_map);
        const to_global_id = local_to_global.get(conn.to.component.value) orelse return error.InternalError;

        try state.connections.append(state.allocator, .{
            .from_id = from_global_id,
            .to_id = to_global_id,
            .port = @intFromEnum(try parsePortName(conn.to.port)),
        });
    }

    // 3. Handle boundary: Input pins of THIS module
    if (parent_input_bindings) |bindings| {
        for (module.inputs) |input| {
            if (bindings.get(input.name)) |binding| {
                const to_global_id = local_to_global.get(input.component.value) orelse return error.InternalError;
                try state.connections.append(state.allocator, .{
                    .from_id = binding.global_from_id,
                    .to_id = to_global_id,
                    .port = @intFromEnum(format.PortName.in),
                });
            }
        }
    }

    // 4. Handle boundary: Output pins of THIS module (return map for parent)
    var module_outputs = std.StringHashMap(u32).init(state.allocator);
    errdefer module_outputs.deinit();
    for (module.outputs) |output| {
        const driver_global_id = try resolveSignalGlobalId(module, output.driver, local_to_global, sub_output_map);
        try module_outputs.put(output.name, driver_global_id);
    }

    // Optionally export local_to_global before freeing (used by serializeProjectFull for root call)
    if (local_to_global_out) |out| {
        var it = local_to_global.iterator();
        while (it.next()) |entry| {
            try out.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    // Explicit cleanup (errdefers above handle error paths)
    local_to_global.deinit();
    {
        var it = sub_output_map.valueIterator();
        while (it.next()) |map| map.deinit();
        sub_output_map.deinit();
    }

    return module_outputs;
}

fn resolveSignalGlobalId(
    module: *const ir.Module,
    endpoint: ir.SignalEndpoint,
    local_to_global: std.AutoHashMap(u32, u32),
    sub_output_map: std.AutoHashMap(u32, std.StringHashMap(u32)),
) !u32 {
    const comp = findComponent(module, endpoint.component) orelse return error.ComponentNotFound;
    switch (comp.kind) {
        .primitive, .slice => {
            return local_to_global.get(endpoint.component.value) orelse error.InternalError;
        },
        .sub_circuit_ref => {
            const outputs = sub_output_map.get(endpoint.component.value) orelse return error.InternalError;
            return outputs.get(endpoint.port) orelse return error.UnknownPortName;
        },
        .unresolved_name => return error.UnresolvedComponent,
    }
}

fn findComponent(module: *const ir.Module, id: ir.ComponentId) ?*const ir.Component {
    for (module.components) |*comp| {
        if (comp.id.value == id.value) return comp;
    }
    return null;
}

fn parsePortName(name: []const u8) !format.PortName {
    if (std.mem.eql(u8, name, "in")) return .in;
    if (std.mem.eql(u8, name, "a")) return .a;
    if (std.mem.eql(u8, name, "b")) return .b;
    if (std.mem.eql(u8, name, "out")) return .out;
    return error.UnknownPortName;
}

fn encodePayload(
    allocator: std.mem.Allocator,
    components: []const format.ComponentRecord,
    connections: []const format.ConnectionRecord,
) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, &format.MAGIC);
    try out.append(allocator, format.VERSION);

    var buf: [4]u8 = undefined;
    
    std.mem.writeInt(u32, &buf, @intCast(components.len), .little);
    try out.appendSlice(allocator, &buf);
    
    std.mem.writeInt(u32, &buf, @intCast(connections.len), .little);
    try out.appendSlice(allocator, &buf);

    for (components) |comp| {
        std.mem.writeInt(u32, &buf, comp.id, .little);
        try out.appendSlice(allocator, &buf);
        try out.append(allocator, comp.kind);
        try out.append(allocator, comp.width);
        // Kind-dispatched suffix: slice records carry `(lo, hi)` after
        // the fixed prefix. Older kinds keep their historical 6 bytes.
        if (comp.kind == @intFromEnum(format.ComponentKind.slice)) {
            try out.append(allocator, comp.aux_lo);
            try out.append(allocator, comp.aux_hi);
        }
    }

    for (connections) |connection| {
        std.mem.writeInt(u32, &buf, connection.from_id, .little);
        try out.appendSlice(allocator, &buf);
        std.mem.writeInt(u32, &buf, connection.to_id, .little);
        try out.appendSlice(allocator, &buf);
        try out.append(allocator, connection.port);
    }

    return out.toOwnedSlice(allocator);
}

test "serialize: inverter module bytes" {
    const allocator = std.testing.allocator;
    const span = ir.Span{ .file_id = 0, .start_line = 0, .start_col = 0, .end_line = 0, .end_col = 0 };
    
    const components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .primitive = .input_pin }, .instance_name = "in", .span = span },
        .{ .id = .{ .value = 1 }, .kind = .{ .primitive = .not_gate }, .instance_name = "n1", .span = span },
        .{ .id = .{ .value = 2 }, .kind = .{ .primitive = .output_pin }, .instance_name = "out", .span = span },
    };
    
    const connections = [_]ir.Connection{
        .{
            .from = .{ .component = .{ .value = 0 }, .port = "out" },
            .to = .{ .component = .{ .value = 1 }, .port = "in" },
            .span = span,
        },
        .{
            .from = .{ .component = .{ .value = 1 }, .port = "out" },
            .to = .{ .component = .{ .value = 2 }, .port = "in" },
            .span = span,
        },
    };
    
    const module = ir.Module{
        .file_id = .{ .value = 0 },
        .inputs = &.{},
        .outputs = &.{},
        .components = &components,
        .connections = &connections,
        .imports = &.{},
    };
    
    const payload = try serializeModule(allocator, &module);
    defer allocator.free(payload);
    
    try std.testing.expectEqualStrings(&format.MAGIC, payload[0..4]);
    try std.testing.expectEqual(format.VERSION, payload[4]);
    
    // comp_count = 3
    try std.testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, payload[5..9][0..4], .little));
    // conn_count = 2
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, payload[9..13][0..4], .little));
    
    // Verify records (each: id(4)+kind(1)+width(1) = 6 bytes)
    var offset: usize = 13;
    // Comp 0
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, payload[offset..offset+4][0..4], .little));
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.input_pin), payload[offset+4]);
    try std.testing.expectEqual(@as(u8, 1), payload[offset+5]);
    offset += 6;
    // Comp 1
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, payload[offset..offset+4][0..4], .little));
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.not_gate), payload[offset+4]);
    try std.testing.expectEqual(@as(u8, 1), payload[offset+5]);
    offset += 6;
    // Comp 2
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, payload[offset..offset+4][0..4], .little));
    try std.testing.expectEqual(@intFromEnum(format.ComponentKind.output_pin), payload[offset+4]);
    try std.testing.expectEqual(@as(u8, 1), payload[offset+5]);
    offset += 6;
    
    // Conn 0
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, payload[offset..offset+4][0..4], .little));
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, payload[offset+4..offset+8][0..4], .little));
    try std.testing.expectEqual(@intFromEnum(format.PortName.in), payload[offset+8]);
}

test "serialize: unknown port name returns error" {
    const allocator = std.testing.allocator;
    const span = ir.Span{ .file_id = 0, .start_line = 0, .start_col = 0, .end_line = 0, .end_col = 0 };
    
    const components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .primitive = .input_pin }, .instance_name = "in", .span = span },
        .{ .id = .{ .value = 1 }, .kind = .{ .primitive = .not_gate }, .instance_name = "n1", .span = span },
    };
    
    const connections = [_]ir.Connection{
        .{
            .from = .{ .component = .{ .value = 0 }, .port = "out" },
            .to = .{ .component = .{ .value = 1 }, .port = "invalid" },
            .span = span,
        },
    };
    
    const module = ir.Module{
        .file_id = .{ .value = 0 },
        .inputs = &.{},
        .outputs = &.{},
        .components = &components,
        .connections = &connections,
        .imports = &.{},
    };
    
    try std.testing.expectError(error.UnknownPortName, serializeModule(allocator, &module));
}

test "serialize: width round-trip at 1, 4, 8" {
    const allocator = std.testing.allocator;
    const widths = [_]u8{ 1, 4, 8 };
    for (widths) |w| {
        const components = [_]format.ComponentRecord{
            .{ .id = 0, .kind = @intFromEnum(format.ComponentKind.and_gate), .width = w },
        };
        const payload = try encodePayload(allocator, &components, &.{});
        defer allocator.free(payload);

        try std.testing.expectEqual(format.VERSION, payload[4]);
        // Layout: magic(4)+ver(1)+comp_count(4)+conn_count(4) = 13, then id(4)+kind(1)+width(1).
        try std.testing.expectEqual(@intFromEnum(format.ComponentKind.and_gate), payload[13 + 4]);
        try std.testing.expectEqual(w, payload[13 + 5]);
    }
}

test "serialize: ir.Component.width threads into payload width byte" {
    const allocator = std.testing.allocator;
    const span = ir.Span{ .file_id = 0, .start_line = 0, .start_col = 0, .end_line = 0, .end_col = 0 };

    const components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .primitive = .input_pin }, .instance_name = "a", .span = span, .width = 4 },
        .{ .id = .{ .value = 1 }, .kind = .{ .primitive = .and_gate }, .instance_name = "g", .span = span, .width = 4 },
        .{ .id = .{ .value = 2 }, .kind = .{ .primitive = .output_pin }, .instance_name = "r", .span = span, .width = 4 },
    };
    const module = ir.Module{
        .file_id = .{ .value = 0 },
        .inputs = &.{},
        .outputs = &.{},
        .components = &components,
        .connections = &.{},
        .imports = &.{},
    };

    const payload = try serializeModule(allocator, &module);
    defer allocator.free(payload);

    // Header is magic(4)+ver(1)+comp_count(4)+conn_count(4) = 13. Each record is id(4)+kind(1)+width(1) = 6.
    var offset: usize = 13;
    for (components) |_| {
        try std.testing.expectEqual(@as(u8, 4), payload[offset + 5]);
        offset += 6;
    }
}

test "serialize: half-adder project flat" {
    const allocator = std.testing.allocator;
    const span = ir.Span{ .file_id = 0, .start_line = 0, .start_col = 0, .end_line = 0, .end_col = 0 };

    // Sub-circuit: half_adder.circ
    // Inputs: a, b
    // Components: xor(0), and(1)
    // Connections: a -> xor.a, b -> xor.b, a -> and.a, b -> and.b
    // Outputs: sum (from xor.out), carry (from and.out)
    // Actually, xor and and are also primitives in our engine (well, XOR is builtin but let's assume primitives for simplicity here)
    // Wait, engine only has and/not. So XOR is sub-circuit.
    // Let's use simpler: my_not.circ (input in -> not gate -> output out)
    
    const my_not_components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .primitive = .not_gate }, .instance_name = "n1", .span = span },
    };
    const my_not_inputs = [_]ir.InputPin{
        .{ .id = .{ .value = 0 }, .name = "in", .component = .{ .value = 0 }, .span = span },
    };
    const my_not_outputs = [_]ir.OutputPin{
        .{ .id = .{ .value = 0 }, .name = "out", .driver = .{ .component = .{ .value = 0 }, .port = "out" }, .span = span },
    };
    const my_not_module = ir.Module{
        .file_id = .{ .value = 1 },
        .inputs = &my_not_inputs,
        .outputs = &my_not_outputs,
        .components = &my_not_components,
        .connections = &.{},
        .imports = &.{},
    };

    // Root: main.circ
    // Components: input_pin(0), sub_circuit(1, "my_not"), output_pin(2)
    // Connections: 0 -> 1.in, 1.out -> 2.in
    const root_components = [_]ir.Component{
        .{ .id = .{ .value = 0 }, .kind = .{ .primitive = .input_pin }, .instance_name = "i1", .span = span },
        .{ .id = .{ .value = 1 }, .kind = .{ .sub_circuit_ref = .{ .name = "MyNot", .span = span } }, .instance_name = "s1", .span = span },
        .{ .id = .{ .value = 2 }, .kind = .{ .primitive = .output_pin }, .instance_name = "o1", .span = span },
    };
    const root_connections = [_]ir.Connection{
        .{ .from = .{ .component = .{ .value = 0 }, .port = "out" }, .to = .{ .component = .{ .value = 1 }, .port = "in" }, .span = span },
        .{ .from = .{ .component = .{ .value = 1 }, .port = "out" }, .to = .{ .component = .{ .value = 2 }, .port = "in" }, .span = span },
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
        .{ .importing_file = .{ .value = 0 }, .alias = "MyNot", .target_file = .{ .value = 1 }, .span = span },
    };

    const project = ir.Project{
        .files = &[_]ir.Module{ root_module, my_not_module },
        .root_file_id = .{ .value = 0 },
        .import_table = &import_table,
        .file_paths = &[_][]const u8{ "main.circ", "my_not.circ" },
        .source_blobs = &[_][]const u8{ "", "" },
    };

    const payload = try serializeProject(allocator, &project);
    defer allocator.free(payload);

    // Expected flat topology:
    // Primitives: input_pin (root.0), not_gate (sub.0), output_pin (root.2) -> 3 components
    // Connections:
    // 1. root.0 -> sub.0.in (boundary rewiring)
    // 2. sub.0.out -> root.2.in (boundary rewiring)
    // Total 2 connections.

    try std.testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, payload[5..9], .little));
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, payload[9..13], .little));
}
