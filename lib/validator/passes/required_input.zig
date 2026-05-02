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

fn hasDriver(module: *const ir.Module, component_id: ir.ComponentId, port: []const u8) bool {
    for (module.connections) |connection| {
        if (connection.to.component.value == component_id.value and std.mem.eql(u8, connection.to.port, port)) {
            return true;
        }
    }
    return false;
}

pub fn run(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    for (module.components) |component| {
        const primitive = switch (component.kind) {
            .primitive => |value| value,
            else => continue,
        };

        const required_ports: []const []const u8 = switch (primitive) {
            .and_gate => &.{ "a", "b" },
            .not_gate, .wire, .led, .output_pin => &.{"in"},
            .input_pin => &.{},
        };

        for (required_ports) |port| {
            if (hasDriver(module, component.id, port)) continue;
            const message = try std.fmt.allocPrint(allocator, "required input '{s}' is unconnected", .{port});
            var diagnostic = diagnostics.makeDiagnostic(.E004, toDiagnosticSpan(component.span));
            diagnostic.message = message;
            try diagnostic_list.append(allocator, diagnostic);
        }
    }
}
