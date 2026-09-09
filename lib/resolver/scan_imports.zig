const std = @import("std");
const translate = @import("translate");
const diagnostics = @import("diagnostics");
const file_loader = @import("file_loader");
const builtins = @import("builtins");

pub const FileId = u32;

pub const ResolvedImport = struct {
    importing_file: FileId,
    alias: []const u8,
    target_file: FileId,
    span: diagnostics.Span,
    implicit_builtin: bool = false,
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
    const reserved = [_][]const u8{
        "input", "output", "and", "not", "wire", "led", "input_pin", "output_pin",
    };
    for (reserved) |name| {
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
    return scanProjectImportsWithOverlay(allocator, root_path, null);
}

pub fn scanProjectImportsWithOverlay(
    allocator: std.mem.Allocator,
    root_path: []const u8,
    overlay: ?file_loader.Overlay,
) !ScanResult {
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

    const root_loaded = try file_loader.loadFileWithOverlay(allocator, root_path, overlay);
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

            const resolved_path = file_loader.resolveImportPath(allocator, file_path, import_decl.path.text, overlay) catch |err| {
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

            if (builtins.isMacroImportAlias(alias)) {
                const expected_virt = (try builtins.virtualPathForMacroAlias(allocator, alias)) orelse unreachable;
                defer allocator.free(expected_virt);
                if (!std.mem.eql(u8, resolved_path, expected_virt)) {
                    allocator.free(resolved_path);
                    try appendImportAliasCollisionDiagnostic(
                        allocator,
                        &diagnostics_list,
                        alias,
                        import_span,
                        null,
                        "this alias refers to built-in macros; the import path must resolve to `<builtin>/<name>.circ` matching the compiler",
                    );
                    continue;
                }
            }

            const target_file_id = if (path_to_id.get(resolved_path)) |existing_id| blk: {
                allocator.free(resolved_path);
                break :blk existing_id;
            } else blk: {
                const new_id: FileId = @intCast(file_paths.items.len);
                try path_to_id.put(resolved_path, new_id);
                try file_paths.append(allocator, resolved_path);
                const loaded = try file_loader.loadFileWithOverlay(allocator, resolved_path, overlay);
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
                .implicit_builtin = false,
            });
            try alias_to_span.put(alias, import_span);
        }

        const implicit_span = diagnostics.Span{
            .file_id = file_id,
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 1,
        };

        for (builtins.table) |macro_entry| {
            const alias = macro_entry.name.slice();
            if (alias_to_span.get(alias)) |_| continue;

            const builtin_path = try builtins.virtualPathForMacroAlias(allocator, alias) orelse continue;
            defer allocator.free(builtin_path);

            if (std.mem.eql(u8, file_path, builtin_path)) continue;

            const target_file_id = if (path_to_id.get(builtin_path)) |existing_id| blk: {
                break :blk existing_id;
            } else blk: {
                const new_id: FileId = @intCast(file_paths.items.len);
                const path_owned = try allocator.dupe(u8, builtin_path);
                errdefer allocator.free(path_owned);
                try path_to_id.put(path_owned, new_id);
                try file_paths.append(allocator, path_owned);
                const loaded = try file_loader.loadFileWithOverlay(allocator, path_owned, overlay);
                allocator.free(loaded.absolute_path);
                try sources.append(allocator, loaded.source);
                try queue.append(allocator, new_id);
                break :blk new_id;
            };

            try import_table.append(allocator, .{
                .importing_file = file_id,
                .alias = try allocator.dupe(u8, alias),
                .target_file = target_file_id,
                .span = implicit_span,
                .implicit_builtin = true,
            });
        }
    }

    return .{
        .file_paths = try file_paths.toOwnedSlice(allocator),
        .import_table = try import_table.toOwnedSlice(allocator),
        .diagnostics = diagnostics_list,
    };
}
