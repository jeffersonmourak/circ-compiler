const std = @import("std");
const ir = @import("ir_types");
const Writer = @import("emit_writer").Writer;
const file_info_format = @import("file_info_format");

pub const EmitOptions = struct {
    source_name: []const u8,
    compile_timestamp: []const u8,
    compiler_version: []const u8,
};

const PathSegments = []const []const u8;

pub const ComponentEntry = struct {
    global_id: u32,
    file_id: u32,
    local_id: u32,
    segments: PathSegments,
};

pub const SubCircuitEntry = struct {
    instance_path: PathSegments,
    target_file_id: u32,
};

pub const ProjectLayout = struct {
    allocator: std.mem.Allocator,
    entries: []ComponentEntry,
    sub_circuits: []SubCircuitEntry,
    expected_count: u32,
    root_input_global_ids: []u32,
    root_output_global_ids: []u32,

    pub fn deinit(self: *ProjectLayout) void {
        for (self.entries) |entry| {
            for (entry.segments) |seg| self.allocator.free(seg);
            self.allocator.free(entry.segments);
        }
        self.allocator.free(self.entries);
        for (self.sub_circuits) |entry| {
            for (entry.instance_path) |seg| self.allocator.free(seg);
            self.allocator.free(entry.instance_path);
        }
        self.allocator.free(self.sub_circuits);
        self.allocator.free(self.root_input_global_ids);
        self.allocator.free(self.root_output_global_ids);
    }
};

fn lookupTargetFile(project: *const ir.Project, importing_file: u32, alias: []const u8) ?u32 {
    for (project.import_table) |entry| {
        if (entry.importing_file.value != importing_file) continue;
        if (!std.mem.eql(u8, entry.alias, alias)) continue;
        return entry.target_file.value;
    }
    return null;
}

fn dupeSegments(allocator: std.mem.Allocator, prefix: PathSegments, leaf: []const u8) ![][]const u8 {
    const out = try allocator.alloc([]const u8, prefix.len + 1);
    var idx: usize = 0;
    while (idx < prefix.len) : (idx += 1) {
        out[idx] = try allocator.dupe(u8, prefix[idx]);
    }
    out[prefix.len] = try allocator.dupe(u8, leaf);
    return out;
}

const WalkContext = struct {
    allocator: std.mem.Allocator,
    project: *const ir.Project,
    next_global_id: u32,
    entries: *std.ArrayList(ComponentEntry),
    sub_circuits: *std.ArrayList(SubCircuitEntry),
};

const LocalToGlobalMap = std.AutoHashMap(u32, u32);

fn walkFile(
    ctx: *WalkContext,
    file_id: u32,
    path_prefix: PathSegments,
    out_input_map: *LocalToGlobalMap,
    out_output_map: *LocalToGlobalMap,
) !void {
    const module = &ctx.project.files[file_id];
    for (module.components) |component| {
        switch (component.kind) {
            .primitive => |primitive| {
                const global_id = ctx.next_global_id;
                ctx.next_global_id += 1;

                const leaf = if (component.instance_name) |name|
                    try ctx.allocator.dupe(u8, name)
                else
                    try std.fmt.allocPrint(ctx.allocator, "comp_{d}", .{component.id.value});
                defer ctx.allocator.free(leaf);

                const segments = try dupeSegments(ctx.allocator, path_prefix, leaf);
                try ctx.entries.append(ctx.allocator, .{
                    .global_id = global_id,
                    .file_id = file_id,
                    .local_id = component.id.value,
                    .segments = segments,
                });
                if (primitive == .input_pin) {
                    try out_input_map.put(component.id.value, global_id);
                }
                if (primitive == .output_pin) {
                    try out_output_map.put(component.id.value, global_id);
                }
            },
            .sub_circuit_ref => |sub_ref| {
                const target_file_id = lookupTargetFile(ctx.project, file_id, sub_ref.name) orelse return error.UnresolvedSubCircuitTarget;

                const instance_leaf = if (component.instance_name) |name|
                    try ctx.allocator.dupe(u8, name)
                else
                    try std.fmt.allocPrint(ctx.allocator, "anon_{d}", .{component.id.value});
                defer ctx.allocator.free(instance_leaf);

                const child_prefix = try dupeSegments(ctx.allocator, path_prefix, instance_leaf);

                try ctx.sub_circuits.append(ctx.allocator, .{
                    .instance_path = child_prefix,
                    .target_file_id = target_file_id,
                });

                var inner_inputs = LocalToGlobalMap.init(ctx.allocator);
                defer inner_inputs.deinit();
                var inner_outputs = LocalToGlobalMap.init(ctx.allocator);
                defer inner_outputs.deinit();

                try walkFile(ctx, target_file_id, child_prefix, &inner_inputs, &inner_outputs);
            },
            .slice, .concat => {
                // Slice and concat components are synthesized by the
                // resolver for bit-range and concatenation lowering.
                // They behave like primitives at the project-layout
                // layer: get a global id, append an entry under the
                // current path prefix. They are never input/output
                // pins, so neither the input nor output map gets
                // updated for them.
                const global_id = ctx.next_global_id;
                ctx.next_global_id += 1;

                const fallback_prefix: []const u8 = switch (component.kind) {
                    .slice => "slice",
                    .concat => "concat",
                    else => "synthetic",
                };
                const leaf = if (component.instance_name) |name|
                    try ctx.allocator.dupe(u8, name)
                else
                    try std.fmt.allocPrint(ctx.allocator, "{s}_{d}", .{ fallback_prefix, component.id.value });
                defer ctx.allocator.free(leaf);

                const segments = try dupeSegments(ctx.allocator, path_prefix, leaf);
                try ctx.entries.append(ctx.allocator, .{
                    .global_id = global_id,
                    .file_id = file_id,
                    .local_id = component.id.value,
                    .segments = segments,
                });
            },
            .unresolved_name => return error.UnresolvedComponentName,
        }
    }
}

pub fn computeLayout(allocator: std.mem.Allocator, project: *const ir.Project) !ProjectLayout {
    var entries: std.ArrayList(ComponentEntry) = .{};
    errdefer entries.deinit(allocator);
    var sub_circuits: std.ArrayList(SubCircuitEntry) = .{};
    errdefer sub_circuits.deinit(allocator);

    var ctx = WalkContext{
        .allocator = allocator,
        .project = project,
        .next_global_id = 0,
        .entries = &entries,
        .sub_circuits = &sub_circuits,
    };

    const root_file_id = project.root_file_id.value;
    const root_module = &project.files[root_file_id];
    const root_basename = std.fs.path.basename(project.file_paths[root_file_id]);

    const root_prefix = try allocator.alloc([]const u8, 1);
    root_prefix[0] = try allocator.dupe(u8, root_basename);
    defer {
        allocator.free(root_prefix[0]);
        allocator.free(root_prefix);
    }

    var root_input_map = LocalToGlobalMap.init(allocator);
    defer root_input_map.deinit();
    var root_output_map = LocalToGlobalMap.init(allocator);
    defer root_output_map.deinit();

    try walkFile(&ctx, root_file_id, root_prefix, &root_input_map, &root_output_map);

    var root_input_ids = try allocator.alloc(u32, root_module.inputs.len);
    errdefer allocator.free(root_input_ids);
    for (root_module.inputs, 0..) |pin, idx| {
        root_input_ids[idx] = root_input_map.get(pin.component.value) orelse return error.MissingRootInputId;
    }

    var root_output_ids: std.ArrayList(u32) = .{};
    errdefer root_output_ids.deinit(allocator);
    for (root_module.outputs) |output_pin| {
        const output_component_id = findOutputPinComponent(root_module, output_pin.name) orelse continue;
        const global = root_output_map.get(output_component_id) orelse return error.MissingRootOutputId;
        try root_output_ids.append(allocator, global);
    }

    return .{
        .allocator = allocator,
        .entries = try entries.toOwnedSlice(allocator),
        .sub_circuits = try sub_circuits.toOwnedSlice(allocator),
        .expected_count = ctx.next_global_id,
        .root_input_global_ids = root_input_ids,
        .root_output_global_ids = try root_output_ids.toOwnedSlice(allocator),
    };
}

fn findOutputPinComponent(module: *const ir.Module, name: []const u8) ?u32 {
    for (module.components) |component| {
        const inst_name = component.instance_name orelse continue;
        if (!std.mem.eql(u8, inst_name, name)) continue;
        switch (component.kind) {
            .primitive => |primitive| {
                if (primitive == .output_pin) return component.id.value;
            },
            else => {},
        }
    }
    return null;
}

fn primitiveExpr(kind: ir.PrimitiveKind) []const u8 {
    return switch (kind) {
        .and_gate => ".{ .and_gate = .{} }",
        .not_gate => ".{ .not_gate = .{} }",
        .wire => ".{ .wire = .{} }",
        .led => ".{ .led = .{} }",
        .input_pin => ".{ .input_pin_gate = .{} }",
        .output_pin => ".{ .output_pin = .{} }",
    };
}

fn componentVarName(allocator: std.mem.Allocator, writer: *Writer, component: ir.Component) ![]u8 {
    if (component.instance_name) |instance_name| {
        const escaped = try writer.escapeIdentifier(instance_name);
        defer allocator.free(escaped);
        return std.fmt.allocPrint(allocator, "comp_{s}_{d}", .{ escaped, component.id.value });
    }
    return std.fmt.allocPrint(allocator, "comp_{d}", .{component.id.value});
}

fn instanceVarName(allocator: std.mem.Allocator, writer: *Writer, component: ir.Component) ![]u8 {
    if (component.instance_name) |instance_name| {
        const escaped = try writer.escapeIdentifier(instance_name);
        defer allocator.free(escaped);
        return std.fmt.allocPrint(allocator, "inst_{s}_{d}", .{ escaped, component.id.value });
    }
    return std.fmt.allocPrint(allocator, "inst_{d}", .{component.id.value});
}

fn fieldName(allocator: std.mem.Allocator, writer: *Writer, prefix: []const u8, raw: []const u8) ![]u8 {
    const escaped = try writer.escapeIdentifier(raw);
    defer allocator.free(escaped);
    return std.fmt.allocPrint(allocator, "{s}_{s}", .{ prefix, escaped });
}

fn findComponentById(module: *const ir.Module, id: ir.ComponentId) ?ir.Component {
    for (module.components) |component| {
        if (component.id.value == id.value) return component;
    }
    return null;
}

fn endpointExprFrom(
    allocator: std.mem.Allocator,
    writer: *Writer,
    module: *const ir.Module,
    endpoint: ir.SignalEndpoint,
) ![]u8 {
    const component = findComponentById(module, endpoint.component) orelse return error.InvalidFromComponentId;
    switch (component.kind) {
        .sub_circuit_ref => {
            const inst = try instanceVarName(allocator, writer, component);
            defer allocator.free(inst);
            const field = try fieldName(allocator, writer, "output", endpoint.port);
            defer allocator.free(field);
            return std.fmt.allocPrint(allocator, "{s}.{s}.port(\"out\")", .{ inst, field });
        },
        else => {
            const var_name = try componentVarName(allocator, writer, component);
            defer allocator.free(var_name);
            const port_lit = try writer.zigStringLiteral(endpoint.port);
            defer allocator.free(port_lit);
            return std.fmt.allocPrint(allocator, "{s}.port({s})", .{ var_name, port_lit });
        },
    }
}

fn endpointExprTo(
    allocator: std.mem.Allocator,
    writer: *Writer,
    module: *const ir.Module,
    endpoint: ir.PortEndpoint,
) ![]u8 {
    const component = findComponentById(module, endpoint.component) orelse return error.InvalidToComponentId;
    switch (component.kind) {
        .sub_circuit_ref => {
            const inst = try instanceVarName(allocator, writer, component);
            defer allocator.free(inst);
            const field = try fieldName(allocator, writer, "input", endpoint.port);
            defer allocator.free(field);
            return std.fmt.allocPrint(allocator, "{s}.{s}.port(\"in\")", .{ inst, field });
        },
        else => {
            const var_name = try componentVarName(allocator, writer, component);
            defer allocator.free(var_name);
            const port_lit = try writer.zigStringLiteral(endpoint.port);
            defer allocator.free(port_lit);
            return std.fmt.allocPrint(allocator, "{s}.port({s})", .{ var_name, port_lit });
        },
    }
}

fn emitFileBuildFunction(
    allocator: std.mem.Allocator,
    writer: *Writer,
    module: *const ir.Module,
) !void {
    try writer.writeLineFmt("fn buildFile_{d}(circuit: *engine.Circuit) !struct {{", .{module.file_id.value});
    writer.indent();
    for (module.inputs) |input_pin| {
        const field = try fieldName(allocator, writer, "input", input_pin.name);
        defer allocator.free(field);
        try writer.writeLineFmt("{s}: *engine.Component,", .{field});
    }
    for (module.outputs) |output_pin| {
        const field = try fieldName(allocator, writer, "output", output_pin.name);
        defer allocator.free(field);
        try writer.writeLineFmt("{s}: *engine.Component,", .{field});
    }
    writer.dedent();
    try writer.writeLine("} {");
    writer.indent();

    for (module.components) |component| {
        switch (component.kind) {
            .primitive => |primitive| {
                const var_name = try componentVarName(allocator, writer, component);
                defer allocator.free(var_name);
                try writer.writeLineFmt(
                    "const {s} = try circuit.createComponent({s}, {d});",
                    .{ var_name, primitiveExpr(primitive), component.width },
                );
            },
            .slice => |s| {
                const var_name = try componentVarName(allocator, writer, component);
                defer allocator.free(var_name);
                try writer.writeLineFmt(
                    "const {s} = try circuit.createComponent(.{{ .slice = .{{ .lo = {d}, .hi = {d} }} }}, {d});",
                    .{ var_name, s.lo, s.hi, component.width },
                );
            },
            .concat => {
                const var_name = try componentVarName(allocator, writer, component);
                defer allocator.free(var_name);
                try writer.writeLineFmt(
                    "const {s} = try circuit.createComponent(.{{ .concat = .{{}} }}, {d});",
                    .{ var_name, component.width },
                );
            },
            .sub_circuit_ref => |sub_ref| {
                const target_file_id = lookupSubCircuitTargetForModule(module, sub_ref) orelse return error.UnresolvedSubCircuitTarget;
                const inst = try instanceVarName(allocator, writer, component);
                defer allocator.free(inst);
                try writer.writeLineFmt(
                    "const {s} = try buildFile_{d}(circuit);",
                    .{ inst, target_file_id },
                );
            },
            .unresolved_name => return error.UnresolvedComponentName,
        }
    }

    for (module.connections) |connection| {
        const from_expr = try endpointExprFrom(allocator, writer, module, connection.from);
        defer allocator.free(from_expr);
        const to_expr = try endpointExprTo(allocator, writer, module, connection.to);
        defer allocator.free(to_expr);
        try writer.writeLineFmt("try circuit.connect({s}, {s});", .{ from_expr, to_expr });
    }

    try writer.writeLine("return .{");
    writer.indent();
    for (module.inputs) |input_pin| {
        const field = try fieldName(allocator, writer, "input", input_pin.name);
        defer allocator.free(field);
        const input_component = findComponentById(module, input_pin.component) orelse return error.InvalidInputComponentId;
        const var_name = try componentVarName(allocator, writer, input_component);
        defer allocator.free(var_name);
        try writer.writeLineFmt(".{s} = {s},", .{ field, var_name });
    }
    for (module.outputs) |output_pin| {
        const field = try fieldName(allocator, writer, "output", output_pin.name);
        defer allocator.free(field);
        const output_component_id = findOutputPinComponent(module, output_pin.name) orelse return error.MissingOutputComponent;
        const output_component = findComponentById(module, .{ .value = output_component_id }) orelse return error.InvalidOutputComponentId;
        const output_component_var = try componentVarName(allocator, writer, output_component);
        defer allocator.free(output_component_var);
        try writer.writeLineFmt(".{s} = {s},", .{ field, output_component_var });
    }
    writer.dedent();
    try writer.writeLine("};");
    writer.dedent();
    try writer.writeLine("}");
}

// Finding the target file for a sub-circuit ref needs project context; we
// cache an alternative lookup using the import table copied into each module
// at scan time. The current IR keeps `sub_circuit_ref` carrying only an alias,
// so `emitFileBuildFunction` looks the target up via a project-scoped map
// passed in implicitly through this thread-local-like helper.
//
// To keep emitFileBuildFunction reusable per-module without the project handle,
// we set a module->project mapping in `emitProjectSource` before emitting each
// module.
threadlocal var current_project: ?*const ir.Project = null;

fn lookupSubCircuitTargetForModule(module: *const ir.Module, sub_ref: ir.UnresolvedRef) ?u32 {
    const project = current_project orelse return null;
    return lookupTargetFile(project, module.file_id.value, sub_ref.name);
}

fn emitDebugPathsBlock(
    allocator: std.mem.Allocator,
    writer: *Writer,
    layout: *const ProjectLayout,
) !void {
    try writer.writeLine("const DebugPath = struct {");
    writer.indent();
    try writer.writeLine("component_id: u32,");
    try writer.writeLine("segments: []const []const u8,");
    writer.dedent();
    try writer.writeLine("};");
    try writer.writeLine("const debug_paths: []const DebugPath = &.{");
    writer.indent();
    for (layout.entries) |entry| {
        var segments_buf: std.ArrayList(u8) = .{};
        defer segments_buf.deinit(allocator);
        const seg_writer = segments_buf.writer(allocator);
        try seg_writer.writeAll("&.{ ");
        for (entry.segments, 0..) |seg, idx| {
            if (idx > 0) try seg_writer.writeAll(", ");
            const lit = try writer.zigStringLiteral(seg);
            defer allocator.free(lit);
            try seg_writer.writeAll(lit);
        }
        try seg_writer.writeAll(" }");
        try writer.writeLineFmt(
            ".{{ .component_id = {d}, .segments = {s} }},",
            .{ entry.global_id, segments_buf.items },
        );
    }
    writer.dedent();
    try writer.writeLine("};");
}

fn emitU32ArrayLine(writer: *Writer, comptime name: []const u8, values: []const u32) !void {
    try writer.writeLineFmt("const {s}: []const u32 = &.{{", .{name});
    writer.indent();
    for (values) |value| {
        try writer.writeLineFmt("{d},", .{value});
    }
    writer.dedent();
    try writer.writeLine("};");
}

fn emitRuntimeBlock(
    writer: *Writer,
    layout: *const ProjectLayout,
    root_file_id: u32,
) !void {
    try writer.writeLine("const PtrLen = extern struct { ptr: ?[*]const u8, len: usize };");
    try writer.writeLineFmt("const expected_component_count: usize = {d};", .{layout.expected_count});
    try emitU32ArrayLine(writer, "input_component_ids", layout.root_input_global_ids);
    try emitU32ArrayLine(writer, "output_component_ids", layout.root_output_global_ids);
    try writer.writeLine("var gpa = std.heap.wasm_allocator;");
    try writer.writeLine("var runtime_initialized: bool = false;");
    try writer.writeLine("var runtime_circuit: engine.Circuit = undefined;");
    try writer.writeLine("var component_table: []const *engine.Component = &.{};");
    try writer.writeLine("");
    try writer.writeLine("fn emptyPtrLen() PtrLen {");
    writer.indent();
    try writer.writeLine("return .{ .ptr = null, .len = 0 };");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("fn containsId(list: []const u32, id: u32) bool {");
    writer.indent();
    try writer.writeLine("for (list) |candidate| {");
    writer.indent();
    try writer.writeLine("if (candidate == id) return true;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("return false;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("fn bufferFromStaticBytes(bytes: []const u8) PtrLen {");
    writer.indent();
    try writer.writeLine("if (bytes.len == 0) return emptyPtrLen();");
    try writer.writeLine("const buffer = gpa.alloc(u8, bytes.len) catch return emptyPtrLen();");
    try writer.writeLine("std.mem.copyForwards(u8, buffer, bytes);");
    try writer.writeLine("return .{ .ptr = buffer.ptr, .len = buffer.len };");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLineFmt("fn buildRoot(circuit: *engine.Circuit) !void {{", .{});
    writer.indent();
    try writer.writeLineFmt("_ = try buildFile_{d}(circuit);", .{root_file_id});
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn init() void {");
    writer.indent();
    try writer.writeLine("if (runtime_initialized) return;");
    try writer.writeLine("runtime_circuit = engine.Circuit.init() catch return;");
    try writer.writeLine("buildRoot(&runtime_circuit) catch {");
    writer.indent();
    try writer.writeLine("runtime_circuit.deinit();");
    try writer.writeLine("return;");
    writer.dedent();
    try writer.writeLine("};");
    try writer.writeLine("component_table = runtime_circuit.nodes.items;");
    try writer.writeLine("if (component_table.len != expected_component_count) {");
    writer.indent();
    try writer.writeLine("runtime_circuit.deinit();");
    try writer.writeLine("component_table = &.{};");
    try writer.writeLine("return;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("runtime_initialized = true;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn deinit() void {");
    writer.indent();
    try writer.writeLine("if (!runtime_initialized) return;");
    try writer.writeLine("runtime_circuit.deinit();");
    try writer.writeLine("component_table = &.{};");
    try writer.writeLine("runtime_initialized = false;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn reset() void {");
    writer.indent();
    try writer.writeLine("if (runtime_initialized) deinit();");
    try writer.writeLine("init();");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn run() void {");
    writer.indent();
    try writer.writeLine("if (!runtime_initialized) return;");
    try writer.writeLine("runtime_circuit.propagate() catch return;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn stop() void {");
    writer.indent();
    try writer.writeLine("// v0 no-op; retained for forward-compatible runtime API shape.");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn setPin(component_id: i32, state: i32) void {");
    writer.indent();
    try writer.writeLine("if (!runtime_initialized) return;");
    try writer.writeLine("if (component_id < 0) return;");
    try writer.writeLine("const id: u32 = @intCast(component_id);");
    try writer.writeLine("if (id >= component_table.len) return;");
    try writer.writeLine("if (!containsId(input_component_ids, id)) return;");
    try writer.writeLine("runtime_circuit.propagateEvent(component_table[id], engine.BitVecState.fromInt(state, 1)) catch return;");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn getOutputState(component_id: i32) i32 {");
    writer.indent();
    try writer.writeLine("if (!runtime_initialized) return 2;");
    try writer.writeLine("if (component_id < 0) return 2;");
    try writer.writeLine("const id: u32 = @intCast(component_id);");
    try writer.writeLine("if (id >= component_table.len) return 2;");
    try writer.writeLine("if (!containsId(output_component_ids, id)) return 2;");
    try writer.writeLine("return runtime_circuit.readState(component_table[id].state_handle).toInt();");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn getStateSnapshot() callconv(.c) PtrLen {");
    writer.indent();
    try writer.writeLine("if (!runtime_initialized) return emptyPtrLen();");
    try writer.writeLine("const encoded = runtime_circuit.encodeState() catch return emptyPtrLen();");
    try writer.writeLine("return .{ .ptr = encoded.ptr, .len = encoded.len };");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn getTopology() callconv(.c) PtrLen {");
    writer.indent();
    try writer.writeLine("return bufferFromStaticBytes(topology_blob);");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn getPendingEvents() callconv(.c) PtrLen {");
    writer.indent();
    try writer.writeLine("const empty_pending: []const u8 = &.{};");
    try writer.writeLine("return bufferFromStaticBytes(empty_pending);");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn getFileInfo() callconv(.c) PtrLen {");
    writer.indent();
    try writer.writeLine("return .{ .ptr = file_info_blob.ptr, .len = file_info_blob.len };");
    writer.dedent();
    try writer.writeLine("}");
    try writer.writeLine("");
    try writer.writeLine("export fn freeBuffer(ptr: ?[*]const u8, len: usize) void {");
    writer.indent();
    try writer.writeLine("if (len == 0) return;");
    try writer.writeLine("const non_null = ptr orelse return;");
    try writer.writeLine("const mutable: [*]u8 = @constCast(non_null);");
    try writer.writeLine("gpa.free(mutable[0..len]);");
    writer.dedent();
    try writer.writeLine("}");
}

fn emitFileInfoBlock(
    allocator: std.mem.Allocator,
    writer: *Writer,
    project: *const ir.Project,
    layout: *const ProjectLayout,
    options: EmitOptions,
) !void {
    const root_module = &project.files[project.root_file_id.value];

    var inputs: std.ArrayList(file_info_format.NamedPin) = .{};
    defer inputs.deinit(allocator);
    for (root_module.inputs, 0..) |pin, idx| {
        try inputs.append(allocator, .{
            .component_id = layout.root_input_global_ids[idx],
            .name = pin.name,
        });
    }

    var outputs: std.ArrayList(file_info_format.NamedPin) = .{};
    defer outputs.deinit(allocator);
    var output_idx: usize = 0;
    for (root_module.outputs) |pin| {
        if (output_idx >= layout.root_output_global_ids.len) break;
        try outputs.append(allocator, .{
            .component_id = layout.root_output_global_ids[output_idx],
            .name = pin.name,
        });
        output_idx += 1;
    }

    const info: file_info_format.FileInfo = .{
        .file_id = root_module.file_id.value,
        .source_name = options.source_name,
        .compile_timestamp = options.compile_timestamp,
        .compiler_version = options.compiler_version,
        .component_count = layout.expected_count,
        .connection_count = totalConnectionCount(project),
        .inputs = inputs.items,
        .outputs = outputs.items,
    };
    const blob = try file_info_format.encodeFileInfo(allocator, info);
    defer allocator.free(blob);

    try writer.writeLine("const file_info_blob: []const u8 = &.{");
    writer.indent();
    var idx: usize = 0;
    while (idx < blob.len) {
        var line: std.ArrayList(u8) = .{};
        defer line.deinit(allocator);
        const line_writer = line.writer(allocator);
        var count: usize = 0;
        while (idx < blob.len and count < 16) : ({
            idx += 1;
            count += 1;
        }) {
            if (count > 0) try line_writer.writeAll(" ");
            try line_writer.print("{d},", .{blob[idx]});
        }
        try writer.writeLine(line.items);
    }
    writer.dedent();
    try writer.writeLine("};");
    try writer.writeLine("");

    try writer.writeLine("const SubCircuit = struct {");
    writer.indent();
    try writer.writeLine("instance_path: []const []const u8,");
    try writer.writeLine("target_file_id: u32,");
    writer.dedent();
    try writer.writeLine("};");
    try writer.writeLine("const sub_circuits: []const SubCircuit = &.{");
    writer.indent();
    for (layout.sub_circuits) |entry| {
        var segments_buf: std.ArrayList(u8) = .{};
        defer segments_buf.deinit(allocator);
        const seg_writer = segments_buf.writer(allocator);
        try seg_writer.writeAll("&.{ ");
        for (entry.instance_path, 0..) |seg, seg_idx| {
            if (seg_idx > 0) try seg_writer.writeAll(", ");
            const lit = try writer.zigStringLiteral(seg);
            defer allocator.free(lit);
            try seg_writer.writeAll(lit);
        }
        try seg_writer.writeAll(" }");
        try writer.writeLineFmt(
            ".{{ .instance_path = {s}, .target_file_id = {d} }},",
            .{ segments_buf.items, entry.target_file_id },
        );
    }
    writer.dedent();
    try writer.writeLine("};");
}

fn totalConnectionCount(project: *const ir.Project) u32 {
    var total: usize = 0;
    for (project.files) |module| total += module.connections.len;
    return @intCast(total);
}

pub fn emitProjectSource(
    allocator: std.mem.Allocator,
    project: *const ir.Project,
    options: EmitOptions,
) ![]u8 {
    var writer = Writer.init(allocator);
    defer writer.deinit();

    const source_name_lit = try writer.zigStringLiteral(options.source_name);
    defer allocator.free(source_name_lit);
    const timestamp_lit = try writer.zigStringLiteral(options.compile_timestamp);
    defer allocator.free(timestamp_lit);
    const compiler_version_lit = try writer.zigStringLiteral(options.compiler_version);
    defer allocator.free(compiler_version_lit);

    try writer.writeLine("//! Generated by circ-compile. Do not edit.");
    try writer.writeLineFmt("//! Source: {s}", .{source_name_lit});
    try writer.writeLineFmt("//! Compiled at: {s}", .{timestamp_lit});
    try writer.writeLineFmt("//! Compiler version: {s}", .{compiler_version_lit});
    try writer.writeLine("");
    try writer.writeLine("const std = @import(\"std\");");
    try writer.writeLine("const engine = @import(\"circuit.zig\");");
    try writer.writeLine("");

    var layout = try computeLayout(allocator, project);
    defer layout.deinit();

    const previous_project = current_project;
    current_project = project;
    defer current_project = previous_project;

    for (project.files) |*module| {
        try emitFileBuildFunction(allocator, &writer, module);
        try writer.writeLine("");
    }

    try emitFileInfoBlock(allocator, &writer, project, &layout, options);
    try writer.writeLine("");

    try emitDebugPathsBlock(allocator, &writer, &layout);
    try writer.writeLine("");
    try writer.writeLine("const topology_blob: []const u8 = \"circ.topology.v0.min\";");
    try writer.writeLine("");

    try emitRuntimeBlock(&writer, &layout, project.root_file_id.value);

    return writer.toOwnedSlice();
}
