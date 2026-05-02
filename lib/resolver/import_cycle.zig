const std = @import("std");
const diagnostics = @import("diagnostics");
const scan_imports = @import("scan_imports");

pub const AnalyzeResult = struct {
    topo_order: []const scan_imports.FileId,
    diagnostics: diagnostics.DiagnosticList,

    pub fn deinit(self: *AnalyzeResult, allocator: std.mem.Allocator) void {
        allocator.free(self.topo_order);
        self.diagnostics.deinit(allocator);
    }
};

fn appendCycleDiagnostic(
    allocator: std.mem.Allocator,
    list: *diagnostics.DiagnosticList,
    file_paths: []const []const u8,
    cycle: []const scan_imports.FileId,
    span: diagnostics.Span,
) !void {
    var message_buf: std.ArrayList(u8) = .{};
    defer message_buf.deinit(allocator);
    const writer = message_buf.writer(allocator);
    try writer.writeAll("import cycle detected: ");
    for (cycle, 0..) |file_id, idx| {
        if (idx > 0) try writer.writeAll(" -> ");
        try writer.writeAll(file_paths[file_id]);
    }
    const message = try message_buf.toOwnedSlice(allocator);

    const notes = try allocator.alloc(diagnostics.DiagnosticNote, cycle.len);
    for (cycle, 0..) |file_id, idx| {
        notes[idx] = .{
            .span = span,
            .message = try std.fmt.allocPrint(allocator, "cycle member: {s}", .{file_paths[file_id]}),
        };
    }

    try list.append(allocator, .{
        .level = .err,
        .code = .E010,
        .span = span,
        .message = message,
        .notes = notes,
    });
}

fn cycleKey(allocator: std.mem.Allocator, cycle: []const scan_imports.FileId) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    for (cycle, 0..) |file_id, idx| {
        if (idx > 0) try writer.writeByte('-');
        try writer.print("{d}", .{file_id});
    }
    return buf.toOwnedSlice(allocator);
}

pub fn analyzeImports(
    allocator: std.mem.Allocator,
    file_paths: []const []const u8,
    import_table: []const scan_imports.ResolvedImport,
) !AnalyzeResult {
    var by_importer = try allocator.alloc(std.ArrayList(scan_imports.ResolvedImport), file_paths.len);
    defer {
        for (by_importer) |*list| list.deinit(allocator);
        allocator.free(by_importer);
    }
    for (by_importer) |*list| list.* = .{};
    for (import_table) |entry| {
        try by_importer[entry.importing_file].append(allocator, entry);
    }

    const State = enum { white, gray, black };
    const states = try allocator.alloc(State, file_paths.len);
    defer allocator.free(states);
    @memset(states, .white);

    var stack: std.ArrayList(scan_imports.FileId) = .{};
    defer stack.deinit(allocator);
    var topo: std.ArrayList(scan_imports.FileId) = .{};
    defer topo.deinit(allocator);
    var diagnostics_list = diagnostics.initDiagnosticList();
    errdefer diagnostics_list.deinit(allocator);
    var seen_cycles = std.StringHashMap(void).init(allocator);
    defer seen_cycles.deinit();

    const Ctx = struct {
        allocator: std.mem.Allocator,
        file_paths: []const []const u8,
        by_importer: []std.ArrayList(scan_imports.ResolvedImport),
        states: []State,
        stack: *std.ArrayList(scan_imports.FileId),
        topo: *std.ArrayList(scan_imports.FileId),
        diagnostics_list: *diagnostics.DiagnosticList,
        seen_cycles: *std.StringHashMap(void),

        fn dfs(self: *@This(), node: scan_imports.FileId) !void {
            self.states[node] = .gray;
            try self.stack.append(self.allocator, node);

            for (self.by_importer[node].items) |edge| {
                const target = edge.target_file;
                switch (self.states[target]) {
                    .white => try self.dfs(target),
                    .gray => {
                        var start_idx: usize = 0;
                        while (start_idx < self.stack.items.len and self.stack.items[start_idx] != target) : (start_idx += 1) {}
                        if (start_idx < self.stack.items.len) {
                            const cycle = self.stack.items[start_idx..];
                            const key = try cycleKey(self.allocator, cycle);
                            defer self.allocator.free(key);
                            if (!self.seen_cycles.contains(key)) {
                                try self.seen_cycles.put(try self.allocator.dupe(u8, key), {});
                                try appendCycleDiagnostic(
                                    self.allocator,
                                    self.diagnostics_list,
                                    self.file_paths,
                                    cycle,
                                    edge.span,
                                );
                            }
                        }
                    },
                    .black => {},
                }
            }

            _ = self.stack.pop();
            self.states[node] = .black;
            try self.topo.append(self.allocator, node);
        }
    };

    var ctx = Ctx{
        .allocator = allocator,
        .file_paths = file_paths,
        .by_importer = by_importer,
        .states = states,
        .stack = &stack,
        .topo = &topo,
        .diagnostics_list = &diagnostics_list,
        .seen_cycles = &seen_cycles,
    };

    for (file_paths, 0..) |_, idx| {
        const file_id: scan_imports.FileId = @intCast(idx);
        if (states[file_id] == .white) try ctx.dfs(file_id);
    }

    return .{
        .topo_order = try topo.toOwnedSlice(allocator),
        .diagnostics = diagnostics_list,
    };
}
