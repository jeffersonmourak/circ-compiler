const std = @import("std");
const diagnostics = @import("diagnostics");
const ir = @import("ir_types");

fn toDiagnosticSpan(span: ir.Span) diagnostics.Span {
    return .{
        .file_id = span.file_id,
        .start_line = span.start_line,
        .start_col = span.start_col,
        .end_line = span.end_line,
        .end_col = span.end_col,
    };
}

fn findTargetModule(project: *const ir.Project, importing_file: ir.FileId, alias: []const u8) ?*const ir.Module {
    for (project.import_table) |entry| {
        if (entry.importing_file.value == importing_file.value and
            std.mem.eql(u8, entry.alias, alias))
        {
            return &project.files[entry.target_file.value];
        }
    }
    return null;
}

fn targetForRef(project: *const ir.Project, importing_file: ir.FileId, ref: ir.UnresolvedRef) ?*const ir.Module {
    if (ref.specialized_target_file) |spec| return &project.files[spec.value];
    return findTargetModule(project, importing_file, ref.name);
}

fn hasInputPort(target: *const ir.Module, port: []const u8) bool {
    for (target.inputs) |input| {
        if (std.mem.eql(u8, input.name, port)) return true;
    }
    return false;
}

fn hasOutputPort(target: *const ir.Module, port: []const u8) bool {
    for (target.outputs) |output| {
        if (std.mem.eql(u8, output.name, port)) return true;
    }
    return false;
}

fn inputPortWidth(target: *const ir.Module, port: []const u8) ?u8 {
    for (target.inputs) |input| {
        if (std.mem.eql(u8, input.name, port)) return input.width;
    }
    return null;
}

fn outputPortWidth(target: *const ir.Module, port: []const u8) ?u8 {
    for (target.outputs) |output| {
        if (std.mem.eql(u8, output.name, port)) return output.width;
    }
    return null;
}

fn endpointWidth(
    project: *const ir.Project,
    module: *const ir.Module,
    component: ir.Component,
    port: []const u8,
    side: enum { from, to },
) ?u8 {
    return switch (component.kind) {
        .primitive => component.width,
        .sub_circuit_ref => |ref| blk: {
            const target = targetForRef(project, module.file_id, ref) orelse break :blk null;
            break :blk switch (side) {
                .from => outputPortWidth(target, port),
                .to => inputPortWidth(target, port),
            };
        },
        .slice, .concat, .unresolved_name => null,
    };
}

fn findComponent(module: *const ir.Module, id: ir.ComponentId) ?ir.Component {
    for (module.components) |c| {
        if (c.id.value == id.value) return c;
    }
    return null;
}

fn hasDriver(module: *const ir.Module, component_id: ir.ComponentId, port: []const u8) bool {
    for (module.connections) |conn| {
        if (conn.to.component.value == component_id.value and std.mem.eql(u8, conn.to.port, port)) return true;
    }
    return false;
}

pub fn runForModule(
    allocator: std.mem.Allocator,
    project: *const ir.Project,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    // E012: unknown sub-circuit port on connections
    for (module.connections) |conn| {
        // Check destination port (input side of target)
        if (findComponent(module, conn.to.component)) |to_comp| {
            if (to_comp.kind == .sub_circuit_ref) {
                const ref = to_comp.kind.sub_circuit_ref;
                if (targetForRef(project, module.file_id, ref)) |target| {
                    if (!hasInputPort(target, conn.to.port)) {
                        const message = try std.fmt.allocPrint(
                            allocator,
                            "sub-circuit '{s}' has no input port '{s}'",
                            .{ ref.name, conn.to.port },
                        );
                        var d = diagnostics.makeDiagnostic(.E012, toDiagnosticSpan(conn.span));
                        d.message = message;
                        try diagnostic_list.append(allocator, d);
                    }
                }
            }
        }

        // Check source port (output side of target)
        if (findComponent(module, conn.from.component)) |from_comp| {
            if (from_comp.kind == .sub_circuit_ref) {
                const ref = from_comp.kind.sub_circuit_ref;
                if (targetForRef(project, module.file_id, ref)) |target| {
                    if (!hasOutputPort(target, conn.from.port)) {
                        const message = try std.fmt.allocPrint(
                            allocator,
                            "sub-circuit '{s}' has no output port '{s}'",
                            .{ ref.name, conn.from.port },
                        );
                        var d = diagnostics.makeDiagnostic(.E012, toDiagnosticSpan(conn.span));
                        d.message = message;
                        try diagnostic_list.append(allocator, d);
                    }
                }
            }
        }
    }

    // E013: sub-circuit arity — required inputs not connected
    for (module.components) |component| {
        if (component.kind != .sub_circuit_ref) continue;
        const ref = component.kind.sub_circuit_ref;
        const target = targetForRef(project, module.file_id, ref) orelse continue;
        const alias = ref.name;

        for (target.inputs) |target_input| {
            if (hasDriver(module, component.id, target_input.name)) continue;
            const message = try std.fmt.allocPrint(
                allocator,
                "sub-circuit '{s}' is missing required input '{s}'",
                .{ alias, target_input.name },
            );
            var d = diagnostics.makeDiagnostic(.E013, toDiagnosticSpan(component.span));
            d.message = message;
            try diagnostic_list.append(allocator, d);
        }
    }

    // E014: width mismatch on connections crossing a sub_circuit_ref boundary.
    // In-module connections (both endpoints primitive) are handled by
    // lib/validator/passes/port_validation.zig.
    for (module.connections) |conn| {
        const from_comp = findComponent(module, conn.from.component) orelse continue;
        const to_comp = findComponent(module, conn.to.component) orelse continue;
        if (from_comp.kind != .sub_circuit_ref and to_comp.kind != .sub_circuit_ref) continue;

        const from_width = endpointWidth(project, module, from_comp, conn.from.port, .from) orelse continue;
        const to_width = endpointWidth(project, module, to_comp, conn.to.port, .to) orelse continue;
        if (from_width == to_width) continue;

        const message = try std.fmt.allocPrint(
            allocator,
            "width mismatch: source width {d}, destination expects {d}",
            .{ from_width, to_width },
        );
        var d = diagnostics.makeDiagnostic(.E014, toDiagnosticSpan(conn.span));
        d.message = message;
        try diagnostic_list.append(allocator, d);
    }

    // W002: sub-circuit output never read by parent
    for (module.components) |component| {
        if (component.kind != .sub_circuit_ref) continue;
        const ref = component.kind.sub_circuit_ref;
        const target = targetForRef(project, module.file_id, ref) orelse continue;
        const alias = ref.name;

        for (target.outputs) |target_output| {
            var used = false;
            for (module.connections) |conn| {
                if (conn.from.component.value == component.id.value and
                    std.mem.eql(u8, conn.from.port, target_output.name))
                {
                    used = true;
                    break;
                }
            }
            if (!used) {
                const message = try std.fmt.allocPrint(
                    allocator,
                    "output '{s}' of sub-circuit '{s}' is never read",
                    .{ target_output.name, alias },
                );
                var d = diagnostics.makeDiagnostic(.W002, toDiagnosticSpan(component.span));
                d.message = message;
                try diagnostic_list.append(allocator, d);
            }
        }
    }
}
