const std = @import("std");
const diagnostics = @import("diagnostics");
const ir = @import("ir_types");
const memory_validation = @import("memory_validation");

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
        .slice => std.mem.eql(u8, port, "in"),
        // Concat operand ports are unbounded: any `operand_<idx>` is a
        // valid input. The resolver always emits well-formed names, so
        // we just check the prefix here.
        .concat => std.mem.startsWith(u8, port, "operand_"),
        .memory => |m| switch (m.mode) {
            .rom => std.mem.eql(u8, port, "addr"),
            .ram => std.mem.eql(u8, port, "addr") or std.mem.eql(u8, port, "din") or
                std.mem.eql(u8, port, "we") or std.mem.eql(u8, port, "clk"),
        },
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
        .slice => std.mem.eql(u8, port, "out"),
        .concat => std.mem.eql(u8, port, "out"),
        .memory => std.mem.eql(u8, port, "out"),
    };
}

/// Width contract of one connection end inside this module, or null when
/// the end has no single-width contract here (sub-circuit ports are checked
/// with project context in sub_circuit_validation; slice/concat inputs vary
/// per operand and surface their mismatches through the shape checks below).
fn endpointWidth(component: ir.Component, port: []const u8, side: memory_validation.Side) ?u8 {
    return switch (component.kind) {
        .primitive => component.width,
        .memory => |m| memory_validation.memoryPortWidth(m, port, side),
        .sub_circuit_ref, .unresolved_name, .slice, .concat => null,
    };
}

fn findSliceSource(module: *const ir.Module, slice_id: ir.ComponentId) ?ir.Component {
    // The resolver synthesizes exactly one `(source.out -> slice.in)`
    // connection per slice component. Returning the first matching
    // source is sufficient; multi-driver scenarios are caught by a
    // separate pass.
    for (module.connections) |conn| {
        if (conn.to.component.value == slice_id.value and std.mem.eql(u8, conn.to.port, "in")) {
            return findComponent(module, conn.from.component);
        }
    }
    return null;
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

        // E014: width mismatch on connections where both endpoints carry a
        // single-width contract in this module (primitives and memory ports).
        // Cross-boundary cases involving sub_circuit_ref are handled by
        // lib/validator/passes/sub_circuit_validation.zig, which has the
        // project context to look up the target module's pin widths.
        const from_width = endpointWidth(from_component, connection.from.port, .from);
        const to_width = endpointWidth(to_component, connection.to.port, .to);
        if (from_width != null and to_width != null and from_width.? != to_width.?) {
            const message = try std.fmt.allocPrint(
                allocator,
                "width mismatch: source width {d}, destination expects {d}",
                .{ from_width.?, to_width.? },
            );
            var diagnostic = diagnostics.makeDiagnostic(.E014, toDiagnosticSpan(connection.span));
            diagnostic.message = message;
            try diagnostic_list.append(allocator, diagnostic);
        }
    }

    // Slice-bound validation. Two failure modes:
    //   - inverted range (lo >= hi): legal indices form an empty set
    //   - out-of-bounds (hi > source.width): slice would read past MSB
    // Both reuse E002 with a slice-specific message until the dedicated
    // width-mismatch code (E014) lands in S6.
    for (module.components) |comp| {
        const slice = switch (comp.kind) {
            .slice => |s| s,
            else => continue,
        };
        if (slice.lo >= slice.hi) {
            const message = try std.fmt.allocPrint(
                allocator,
                "slice range [{d}..{d}) is empty or inverted (lo must be < hi)",
                .{ slice.lo, slice.hi },
            );
            var diagnostic = diagnostics.makeDiagnostic(.E002, toDiagnosticSpan(comp.span));
            diagnostic.message = message;
            try diagnostic_list.append(allocator, diagnostic);
            continue;
        }
        const source = findSliceSource(module, comp.id) orelse continue;
        if (slice.hi > source.width) {
            const message = try std.fmt.allocPrint(
                allocator,
                "slice range [{d}..{d}) exceeds source width {d}",
                .{ slice.lo, slice.hi, source.width },
            );
            var diagnostic = diagnostics.makeDiagnostic(.E002, toDiagnosticSpan(comp.span));
            diagnostic.message = message;
            try diagnostic_list.append(allocator, diagnostic);
        }
    }

    // Concat width-sum validation. The resolver sets `concat.width` to
    // the sum of operand widths at synthesis time, so the check here is
    // "does the concat's output width equal the destination's expected
    // input width?". Any mismatch surfaces as the user-visible "sum
    // doesn't fit" diagnostic.
    //
    // Sub-circuit destinations are deliberately skipped here: the
    // per-call port widths aren't on `Component.width` (that field
    // captures the call-site `[N]` for type-position widths only; the
    // instance-position `[N]` is parsed into `width_args` and consumed
    // by the project resolver during specialization). The cross-boundary
    // width check in lib/validator/passes/sub_circuit_validation.zig
    // has the project context to look up the specialized target's input
    // port width and reports the mismatch as E014.
    for (module.components) |comp| {
        if (comp.kind != .concat) continue;
        var operand_count: u8 = 0;
        for (module.connections) |connection| {
            if (connection.to.component.value == comp.id.value and
                std.mem.startsWith(u8, connection.to.port, "operand_"))
            {
                operand_count += 1;
            }
        }
        // Find the connection feeding concat.out into its destination.
        for (module.connections) |connection| {
            if (connection.from.component.value != comp.id.value) continue;
            if (!std.mem.eql(u8, connection.from.port, "out")) continue;
            const dest = findComponent(module, connection.to.component) orelse continue;
            if (dest.kind == .sub_circuit_ref) continue;
            if (dest.width == comp.width) continue;
            const message = try std.fmt.allocPrint(
                allocator,
                "concat width {d} from {d} operand(s) does not match destination width {d}",
                .{ comp.width, operand_count, dest.width },
            );
            var diagnostic = diagnostics.makeDiagnostic(.E002, toDiagnosticSpan(comp.span));
            diagnostic.message = message;
            try diagnostic_list.append(allocator, diagnostic);
        }
    }
}
