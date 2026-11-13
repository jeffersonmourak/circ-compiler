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
        // A ram holds state across the clock edge; a rom's addr -> out
        // path is a genuine combinational path.
        .memory => |m| m.mode == .ram,
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

/// One input-to-output path through a sub-circuit that crosses no
/// cycle-breaking component.
const Pair = struct { in: []const u8, out: []const u8 };

/// Project-wide state for the port-aware check: which input-to-output
/// paths of each file are transparent, computed once per file.
pub const Context = struct {
    project: *const ir.Project,
    arena: std.heap.ArenaAllocator,
    memo: std.AutoHashMap(u32, []const Pair),
    in_progress: std.AutoHashMap(u32, void),

    pub fn init(allocator: std.mem.Allocator, project: *const ir.Project) Context {
        return .{
            .project = project,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .memo = std.AutoHashMap(u32, []const Pair).init(allocator),
            .in_progress = std.AutoHashMap(u32, void).init(allocator),
        };
    }

    pub fn deinit(self: *Context) void {
        self.memo.deinit();
        self.in_progress.deinit();
        self.arena.deinit();
    }
};

fn targetModule(project: *const ir.Project, module: *const ir.Module, ref: ir.UnresolvedRef) ?*const ir.Module {
    if (ref.specialized_target_file) |spec| {
        if (spec.value < project.files.len) return &project.files[spec.value];
        return null;
    }
    const importers = [_]u32{ module.file_id.value, module.effectiveSourceFileId().value };
    for (importers) |importing_file| {
        for (project.import_table) |entry| {
            if (entry.importing_file.value == importing_file and std.mem.eql(u8, entry.alias, ref.name)) {
                if (entry.target_file.value < project.files.len) return &project.files[entry.target_file.value];
            }
        }
    }
    return null;
}

const PortDir = enum { in, out };

/// The signal graph of one module with every cycle-breaking edge dropped.
/// A plain component is one node. A sub-circuit instance is one node per
/// port, joined input to output only where the callee passes the signal
/// through without a cycle-breaking component.
const Graph = struct {
    scratch: std.mem.Allocator,
    module: *const ir.Module,
    node_component: std.ArrayList(ir.ComponentId) = .{},
    adjacency: std.ArrayList(std.ArrayList(u32)) = .{},
    component_nodes: std.AutoHashMap(u32, u32),
    port_nodes: std.StringHashMap(u32),
    nodes_of: std.AutoHashMap(u32, std.ArrayList(u32)),
    self_loops: std.ArrayList(ir.ComponentId) = .{},

    fn addNode(self: *Graph, component: ir.ComponentId) !u32 {
        const node: u32 = @intCast(self.node_component.items.len);
        try self.node_component.append(self.scratch, component);
        try self.adjacency.append(self.scratch, .{});
        const entry = try self.nodes_of.getOrPut(component.value);
        if (!entry.found_existing) entry.value_ptr.* = .{};
        try entry.value_ptr.append(self.scratch, node);
        return node;
    }

    fn componentNode(self: *Graph, component: ir.ComponentId) !u32 {
        if (self.component_nodes.get(component.value)) |node| return node;
        const node = try self.addNode(component);
        try self.component_nodes.put(component.value, node);
        return node;
    }

    fn portKey(self: *Graph, component: ir.ComponentId, dir: PortDir, port: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.scratch, "{d}:{s}:{s}", .{ component.value, @tagName(dir), port });
    }

    fn findPortNode(self: *Graph, component: ir.ComponentId, dir: PortDir, port: []const u8) !?u32 {
        return self.port_nodes.get(try self.portKey(component, dir, port));
    }

    fn portNode(self: *Graph, component: ir.ComponentId, dir: PortDir, port: []const u8) !u32 {
        const key = try self.portKey(component, dir, port);
        if (self.port_nodes.get(key)) |node| return node;
        const node = try self.addNode(component);
        try self.port_nodes.put(key, node);
        return node;
    }

    fn addEdge(self: *Graph, from: u32, to: u32) !void {
        try self.adjacency.items[from].append(self.scratch, to);
    }
};

fn isSubCircuit(component: ir.Component) bool {
    return component.kind == .sub_circuit_ref;
}

fn buildGraph(scratch: std.mem.Allocator, context: ?*Context, module: *const ir.Module) anyerror!Graph {
    var graph = Graph{
        .scratch = scratch,
        .module = module,
        .component_nodes = std.AutoHashMap(u32, u32).init(scratch),
        .port_nodes = std.StringHashMap(u32).init(scratch),
        .nodes_of = std.AutoHashMap(u32, std.ArrayList(u32)).init(scratch),
    };

    for (module.connections) |connection| {
        const from_component = findComponent(module, connection.from.component) orelse continue;
        const to_component = findComponent(module, connection.to.component) orelse continue;

        if (from_component.id.value == to_component.id.value and !isSubCircuit(from_component)) {
            try graph.self_loops.append(scratch, from_component.id);
            continue;
        }
        if (isCycleBreaking(from_component) or isCycleBreaking(to_component)) continue;

        const from_node = if (isSubCircuit(from_component))
            try graph.portNode(from_component.id, .out, connection.from.port)
        else
            try graph.componentNode(from_component.id);
        const to_node = if (isSubCircuit(to_component))
            try graph.portNode(to_component.id, .in, connection.to.port)
        else
            try graph.componentNode(to_component.id);
        try graph.addEdge(from_node, to_node);
    }

    // Join each instance's input ports to the output ports they reach.
    for (module.components) |component| {
        const ref = switch (component.kind) {
            .sub_circuit_ref => |ref| ref,
            else => continue,
        };
        const target = if (context) |ctx| targetModule(ctx.project, module, ref) else null;
        if (target) |child| {
            for (try transparentPairs(context.?, child)) |pair| {
                const in_node = (try graph.findPortNode(component.id, .in, pair.in)) orelse continue;
                const out_node = (try graph.findPortNode(component.id, .out, pair.out)) orelse continue;
                try graph.addEdge(in_node, out_node);
            }
            continue;
        }

        // The callee is unknown (no project, or an unresolved import):
        // assume every input reaches every output.
        var in_prefix_buf: [32]u8 = undefined;
        const in_prefix = try std.fmt.bufPrint(&in_prefix_buf, "{d}:in:", .{component.id.value});
        var out_prefix_buf: [32]u8 = undefined;
        const out_prefix = try std.fmt.bufPrint(&out_prefix_buf, "{d}:out:", .{component.id.value});
        var ins: std.ArrayList(u32) = .{};
        var outs: std.ArrayList(u32) = .{};
        var it = graph.port_nodes.iterator();
        while (it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, in_prefix)) try ins.append(scratch, entry.value_ptr.*);
            if (std.mem.startsWith(u8, entry.key_ptr.*, out_prefix)) try outs.append(scratch, entry.value_ptr.*);
        }
        std.mem.sort(u32, ins.items, {}, std.sort.asc(u32));
        std.mem.sort(u32, outs.items, {}, std.sort.asc(u32));
        for (ins.items) |in_node| {
            for (outs.items) |out_node| try graph.addEdge(in_node, out_node);
        }
    }

    return graph;
}

/// The (input, output) pairs of `module` joined by a path that crosses no
/// cycle-breaking component, memoized per file.
fn transparentPairs(context: *Context, module: *const ir.Module) anyerror![]const Pair {
    const file = module.file_id.value;
    if (context.memo.get(file)) |pairs| return pairs;
    // An import cycle (E010) would recurse forever; call the file opaque.
    if (context.in_progress.contains(file)) return &.{};
    try context.in_progress.put(file, {});
    defer _ = context.in_progress.remove(file);

    var scratch_arena = std.heap.ArenaAllocator.init(context.arena.child_allocator);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();
    const keep = context.arena.allocator();

    var graph = try buildGraph(scratch, context, module);
    var pairs: std.ArrayList(Pair) = .{};

    for (module.inputs) |input| {
        const start = graph.component_nodes.get(input.component.value) orelse continue;
        const reached = try scratch.alloc(bool, graph.node_component.items.len);
        @memset(reached, false);
        var queue: std.ArrayList(u32) = .{};
        reached[start] = true;
        try queue.append(scratch, start);
        var head: usize = 0;
        while (head < queue.items.len) : (head += 1) {
            for (graph.adjacency.items[queue.items[head]].items) |next| {
                if (reached[next]) continue;
                reached[next] = true;
                try queue.append(scratch, next);
            }
        }

        for (module.outputs) |output| {
            const driver = findComponent(module, output.driver.component) orelse continue;
            const driver_node = if (isSubCircuit(driver))
                try graph.findPortNode(driver.id, .out, output.driver.port)
            else
                graph.component_nodes.get(driver.id.value);
            const node = driver_node orelse continue;
            if (reached[node]) try pairs.append(keep, .{ .in = input.name, .out = output.name });
        }
    }

    const owned = try pairs.toOwnedSlice(keep);
    try context.memo.put(file, owned);
    return owned;
}

const Walk = struct {
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    graph: *const Graph,
    visited: []bool,
    in_stack: []bool,
    stack_index: []usize,
    stack: std.ArrayList(u32) = .{},
    seen_cycles: std.StringHashMap(void),
    diagnostic_list: *diagnostics.DiagnosticList,

    fn visit(self: *Walk, node: u32) anyerror!void {
        self.visited[node] = true;
        self.in_stack[node] = true;
        self.stack_index[node] = self.stack.items.len;
        try self.stack.append(self.scratch, node);

        for (self.graph.adjacency.items[node].items) |neighbor| {
            if (!self.visited[neighbor]) {
                try self.visit(neighbor);
                continue;
            }
            if (!self.in_stack[neighbor]) continue;
            try self.report(self.stack.items[self.stack_index[neighbor]..]);
        }

        _ = self.stack.pop();
        self.in_stack[node] = false;
    }

    /// Reports a cycle of graph nodes as the components they belong to;
    /// the port nodes of one instance collapse into that instance.
    fn report(self: *Walk, cycle: []const u32) !void {
        var components: std.ArrayList(ir.ComponentId) = .{};
        for (cycle) |node| {
            const component = self.graph.node_component.items[node];
            if (components.items.len > 0 and components.items[components.items.len - 1].value == component.value) continue;
            try components.append(self.scratch, component);
        }
        if (components.items.len > 1 and components.items[0].value == components.items[components.items.len - 1].value) {
            _ = components.pop();
        }

        const key = try cycleKey(self.scratch, components.items);
        if (self.seen_cycles.contains(key)) return;
        try self.seen_cycles.put(key, {});
        try appendCycleDiagnostic(self.allocator, self.graph.module, self.diagnostic_list, components.items);
    }
};

fn check(
    allocator: std.mem.Allocator,
    context: ?*Context,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    var scratch_arena = std.heap.ArenaAllocator.init(allocator);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    const graph = try buildGraph(scratch, context, module);

    for (graph.self_loops.items) |component| {
        try appendCycleDiagnostic(allocator, module, diagnostic_list, &.{component});
    }

    const node_count = graph.node_component.items.len;
    var walk = Walk{
        .allocator = allocator,
        .scratch = scratch,
        .graph = &graph,
        .visited = try scratch.alloc(bool, node_count),
        .in_stack = try scratch.alloc(bool, node_count),
        .stack_index = try scratch.alloc(usize, node_count),
        .seen_cycles = std.StringHashMap(void).init(scratch),
        .diagnostic_list = diagnostic_list,
    };
    @memset(walk.visited, false);
    @memset(walk.in_stack, false);

    for (module.components) |component| {
        if (isCycleBreaking(component)) continue;
        const nodes = graph.nodes_of.get(component.id.value) orelse continue;
        for (nodes.items) |node| {
            if (walk.visited[node]) continue;
            try walk.visit(node);
        }
    }
}

/// Single-module check. With no project to consult, every sub-circuit
/// instance counts as transparent from each input to each output.
pub fn run(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    try check(allocator, null, module, diagnostic_list);
}

/// Project check. A sub-circuit instance is transparent only from an
/// input to an output that the callee joins without a cycle-breaking
/// component, so a register built as a sub-circuit breaks a loop the way
/// the gates inside it do.
pub fn runInProject(
    allocator: std.mem.Allocator,
    context: *Context,
    module: *const ir.Module,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    try check(allocator, context, module, diagnostic_list);
}
