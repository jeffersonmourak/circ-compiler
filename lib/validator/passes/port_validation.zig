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

fn findComponent(module: *const ir.Module, id: ir.ComponentId) ?ir.Component {
    for (module.components) |component| {
        if (component.id.value == id.value) return component;
    }
    return null;
}

fn isValidInputPort(component: ir.Component, port: []const u8) bool {
    return switch (component.kind) {
        .primitive => |primitive| switch (primitive) {
            .and_gate => std.mem.eql(u8, port, "a") or std.mem.eql(u8, port, "b"),
            .not_gate, .wire, .led, .output_pin => std.mem.eql(u8, port, "in"),
            .input_pin => false,
        },
        .sub_circuit_ref => true,
        .unresolved_name => true,
    };
}

fn isValidOutputPort(component: ir.Component, port: []const u8) bool {
    return switch (component.kind) {
        .primitive => |primitive| switch (primitive) {
            // All primitives (including LED visualizer) expose `.out` as the driven signal.
            .and_gate, .not_gate, .wire, .led, .output_pin, .input_pin => std.mem.eql(u8, port, "out"),
        },
        .sub_circuit_ref => true,
        .unresolved_name => true,
    };
}

pub fn run(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    for (module.connections) |connection| {
        const to_component = findComponent(module, connection.to.component) orelse continue;
        if (!isValidInputPort(to_component, connection.to.port)) {
            const message = try std.fmt.allocPrint(
                allocator,
                "unknown input port '{s}'",
                .{connection.to.port},
            );
            var diagnostic = diagnostics.makeDiagnostic(.E002, toDiagnosticSpan(connection.span));
            diagnostic.message = message;
            try diagnostic_list.append(allocator, diagnostic);
        }

        const from_component = findComponent(module, connection.from.component) orelse continue;
        if (!isValidOutputPort(from_component, connection.from.port)) {
            const message = try std.fmt.allocPrint(
                allocator,
                "unknown output port '{s}'",
                .{connection.from.port},
            );
            var diagnostic = diagnostics.makeDiagnostic(.E002, toDiagnosticSpan(connection.span));
            diagnostic.message = message;
            try diagnostic_list.append(allocator, diagnostic);
        }
    }
}
