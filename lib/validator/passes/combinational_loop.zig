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

fn isCycleBreaking(component: ir.Component) bool {
    return switch (component.kind) {
        .primitive => |primitive| switch (primitive) {
            .and_gate, .not_gate => true,
            else => false,
        },
        else => false,
    };
}

fn findComponent(module: *const ir.Module, id: ir.ComponentId) ?ir.Component {
    for (module.components) |component| {
        if (component.id.value == id.value) return component;
    }
    return null;
}

fn appendCycleDiagnostic(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
    cycle_nodes: []const ir.ComponentId,
) !void {
    if (cycle_nodes.len == 0) return;

    const head_component = findComponent(module, cycle_nodes[0]) orelse return;
    const message = "combinational loop detected";
    var diagnostic = diagnostics.makeDiagnostic(.E008, toDiagnosticSpan(head_component.span));
    diagnostic.message = message;

    var notes: std.ArrayList(diagnostics.DiagnosticNote) = .{};
    for (cycle_nodes) |component_id| {
        const component = findComponent(module, component_id) orelse continue;
        const note_message = try std.fmt.allocPrint(
            allocator,
            "cycle includes component {d}",
            .{component_id.value},
        );
        try notes.append(allocator, .{
            .span = toDiagnosticSpan(component.span),
            .message = note_message,
        });
    }
    diagnostic.notes = try notes.toOwnedSlice(allocator);
    try diagnostic_list.append(allocator, diagnostic);
}

fn cycleKey(allocator: std.mem.Allocator, nodes: []const ir.ComponentId) ![]u8 {
    var sorted = try allocator.alloc(u32, nodes.len);
    for (nodes, 0..) |node, idx| sorted[idx] = node.value;
    std.mem.sort(u32, sorted, {}, std.sort.asc(u32));
    var out: std.ArrayList(u8) = .{};
    for (sorted, 0..) |value, idx| {
        if (idx > 0) try out.append(allocator, ',');
        try out.writer(allocator).print("{d}", .{value});
    }
    return out.toOwnedSlice(allocator);
}

fn visit(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    adjacency: *const std.AutoHashMap(u32, std.ArrayList(ir.ComponentId)),
    id_to_index: *std.AutoHashMap(u32, usize),
    visited: *std.AutoHashMap(u32, bool),
    in_stack: *std.AutoHashMap(u32, bool),
    stack: *std.ArrayList(ir.ComponentId),
    seen_cycles: *std.StringHashMap(void),
    node: ir.ComponentId,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    try visited.put(node.value, true);
    try in_stack.put(node.value, true);
    try id_to_index.put(node.value, stack.items.len);
    try stack.append(allocator, node);

    const neighbors = adjacency.get(node.value);
    if (neighbors) |items| {
        for (items.items) |neighbor| {
            const already_visited = visited.get(neighbor.value) orelse false;
            if (!already_visited) {
                try visit(allocator, module, adjacency, id_to_index, visited, in_stack, stack, seen_cycles, neighbor, diagnostic_list);
                continue;
            }

            const in_current_stack = in_stack.get(neighbor.value) orelse false;
            if (!in_current_stack) continue;

            const cycle_start = id_to_index.get(neighbor.value) orelse continue;
            const cycle_nodes = stack.items[cycle_start..];
            const key = try cycleKey(allocator, cycle_nodes);
            if (seen_cycles.contains(key)) continue;
            try seen_cycles.put(key, {});
            try appendCycleDiagnostic(allocator, module, diagnostic_list, cycle_nodes);
        }
    }

    _ = stack.pop();
    _ = id_to_index.remove(node.value);
    try in_stack.put(node.value, false);
}

pub fn run(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    var adjacency = std.AutoHashMap(u32, std.ArrayList(ir.ComponentId)).init(allocator);
    defer adjacency.deinit();
    var visited = std.AutoHashMap(u32, bool).init(allocator);
    defer visited.deinit();
    var in_stack = std.AutoHashMap(u32, bool).init(allocator);
    defer in_stack.deinit();
    var seen_cycles = std.StringHashMap(void).init(allocator);
    defer seen_cycles.deinit();
    var stack: std.ArrayList(ir.ComponentId) = .{};
    defer stack.deinit(allocator);

    for (module.connections) |connection| {
        if (connection.from.component.value == connection.to.component.value) {
            const component = findComponent(module, connection.from.component) orelse continue;
            try appendCycleDiagnostic(allocator, module, diagnostic_list, &.{component.id});
            continue;
        }

        const from_component = findComponent(module, connection.from.component) orelse continue;
        const to_component = findComponent(module, connection.to.component) orelse continue;
        if (isCycleBreaking(from_component) or isCycleBreaking(to_component)) continue;

        const entry = try adjacency.getOrPut(connection.from.component.value);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{};
        }
        try entry.value_ptr.append(allocator, connection.to.component);
    }

    for (module.components) |component| {
        if (isCycleBreaking(component)) continue;
        if (visited.get(component.id.value) orelse false) continue;

        var id_to_index = std.AutoHashMap(u32, usize).init(allocator);
        defer id_to_index.deinit();

        try visit(
            allocator,
            module,
            &adjacency,
            &id_to_index,
            &visited,
            &in_stack,
            &stack,
            &seen_cycles,
            component.id,
            diagnostic_list,
        );
    }
}
