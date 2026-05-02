const std = @import("std");
const translate = @import("translate");
const diagnostics = @import("diagnostics");
const file_loader = @import("file_loader");

pub const FileId = u32;

pub const ResolvedImport = struct {
    importing_file: FileId,
    alias: []const u8,
    target_file: FileId,
    span: diagnostics.Span,
};

pub const ScanResult = struct {
    file_paths: []const []const u8,
    import_table: []const ResolvedImport,
    diagnostics: diagnostics.DiagnosticList,

    pub fn deinit(self: *ScanResult, allocator: std.mem.Allocator) void {
        for (self.file_paths) |path| allocator.free(path);
        allocator.free(self.file_paths);
        for (self.import_table) |entry| allocator.free(entry.alias);
        allocator.free(self.import_table);
        self.diagnostics.deinit(allocator);
    }
};

fn isBuiltinAlias(alias: []const u8) bool {
    const builtins = [_][]const u8{
        "input", "output", "and", "not", "wire", "led", "input_pin", "output_pin",
    };
    for (builtins) |name| {
        if (std.mem.eql(u8, alias, name)) return true;
    }
    return false;
}

fn toDiagnosticSpan(span: anytype) diagnostics.Span {
    return .{
        .file_id = span.file_id,
        .start_line = span.start_line,
        .start_col = span.start_col,
        .end_line = span.end_line,
        .end_col = span.end_col,
    };
}

fn appendImportAliasCollisionDiagnostic(
    allocator: std.mem.Allocator,
    list: *diagnostics.DiagnosticList,
    alias: []const u8,
    span: diagnostics.Span,
    note_span: ?diagnostics.Span,
    note_message: []const u8,
) !void {
    const message = try std.fmt.allocPrint(allocator, "import alias collision '{s}'", .{alias});
    const notes = if (note_span) |ns| blk: {
        const item = try allocator.alloc(diagnostics.DiagnosticNote, 1);
        item[0] = .{ .span = ns, .message = note_message };
        break :blk item;
    } else &.{};

    try list.append(allocator, .{
        .level = .err,
        .code = .E011,
        .span = span,
        .message = message,
        .notes = notes,
    });
}

fn appendImportNotFoundDiagnostic(
    allocator: std.mem.Allocator,
    list: *diagnostics.DiagnosticList,
    import_path: []const u8,
    span: diagnostics.Span,
) !void {
    const message = try std.fmt.allocPrint(allocator, "import not found '{s}'", .{import_path});
    try list.append(allocator, .{
        .level = .err,
        .code = .E009,
        .span = span,
        .message = message,
        .notes = &.{},
    });
}

pub fn scanProjectImports(allocator: std.mem.Allocator, root_path: []const u8) !ScanResult {
    var file_paths: std.ArrayList([]const u8) = .{};
    errdefer {
        for (file_paths.items) |path| allocator.free(path);
        file_paths.deinit(allocator);
    }

    var import_table: std.ArrayList(ResolvedImport) = .{};
    errdefer {
        for (import_table.items) |entry| allocator.free(entry.alias);
        import_table.deinit(allocator);
    }

    var diagnostics_list = diagnostics.initDiagnosticList();
    errdefer diagnostics_list.deinit(allocator);

    var path_to_id = std.StringHashMap(FileId).init(allocator);
    defer path_to_id.deinit();
    var queue: std.ArrayList(FileId) = .{};
    defer queue.deinit(allocator);

    const root_loaded = try file_loader.loadFile(allocator, root_path);
    const root_file_id: FileId = 0;
    try file_paths.append(allocator, root_loaded.absolute_path);
    try path_to_id.put(root_loaded.absolute_path, root_file_id);
    try queue.append(allocator, root_file_id);

    var sources: std.ArrayList([]u8) = .{};
    defer {
        for (sources.items) |source| allocator.free(source);
        sources.deinit(allocator);
    }
    try sources.append(allocator, root_loaded.source);

    var queue_idx: usize = 0;
    while (queue_idx < queue.items.len) : (queue_idx += 1) {
        const file_id = queue.items[queue_idx];
        const file_path = file_paths.items[file_id];
        const source = sources.items[file_id];

        const ast_file = translate.parseSource(allocator, file_id, source) catch continue;

        var alias_to_span = std.StringHashMap(diagnostics.Span).init(allocator);
        defer alias_to_span.deinit();

        for (ast_file.imports) |import_decl| {
            const alias = import_decl.alias.text;
            const import_span = toDiagnosticSpan(import_decl.span);

            if (isBuiltinAlias(alias)) {
                try appendImportAliasCollisionDiagnostic(
                    allocator,
                    &diagnostics_list,
                    alias,
                    import_span,
                    null,
                    "",
                );
                continue;
            }

            if (alias_to_span.get(alias)) |existing_span| {
                try appendImportAliasCollisionDiagnostic(
                    allocator,
                    &diagnostics_list,
                    alias,
                    import_span,
                    existing_span,
                    "first import alias declared here",
                );
                continue;
            }
            try alias_to_span.put(alias, import_span);

            const resolved_path = file_loader.resolveImportPath(allocator, file_path, import_decl.path.text) catch |err| {
                if (err == error.FileNotFound) {
                    try appendImportNotFoundDiagnostic(
                        allocator,
                        &diagnostics_list,
                        import_decl.path.text,
                        import_span,
                    );
                    continue;
                }
                return err;
            };

            const target_file_id = if (path_to_id.get(resolved_path)) |existing_id| blk: {
                allocator.free(resolved_path);
                break :blk existing_id;
            } else blk: {
                const new_id: FileId = @intCast(file_paths.items.len);
                try path_to_id.put(resolved_path, new_id);
                try file_paths.append(allocator, resolved_path);
                const loaded = try file_loader.loadFile(allocator, resolved_path);
                allocator.free(loaded.absolute_path);
                try sources.append(allocator, loaded.source);
                try queue.append(allocator, new_id);
                break :blk new_id;
            };

            try import_table.append(allocator, .{
                .importing_file = file_id,
                .alias = try allocator.dupe(u8, alias),
                .target_file = target_file_id,
                .span = import_span,
            });
        }
    }

    return .{
        .file_paths = try file_paths.toOwnedSlice(allocator),
        .import_table = try import_table.toOwnedSlice(allocator),
        .diagnostics = diagnostics_list,
    };
}
