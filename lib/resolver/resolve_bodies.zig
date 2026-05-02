const std = @import("std");
const translate = @import("translate");
const single_resolver = @import("resolver");
const ir = @import("ir_types");
const scan_imports = @import("scan_imports");
const file_loader = @import("file_loader");

fn toIrSpan(span: anytype) ir.Span {
    return .{
        .file_id = span.file_id,
        .start_line = span.start_line,
        .start_col = span.start_col,
        .end_line = span.end_line,
        .end_col = span.end_col,
    };
}

fn componentMatchesAlias(component: ir.Component, alias: []const u8) bool {
    return switch (component.kind) {
        .unresolved_name => |name| std.mem.eql(u8, name, alias),
        else => false,
    };
}

pub fn resolveBodies(
    allocator: std.mem.Allocator,
    file_paths: []const []const u8,
    import_table: []const scan_imports.ResolvedImport,
    topo_order: []const scan_imports.FileId,
) !ir.Project {
    var modules = try allocator.alloc(ir.Module, file_paths.len);
    errdefer allocator.free(modules);
    var sources = try allocator.alloc([]const u8, file_paths.len);
    errdefer allocator.free(sources);
    var resolved_modules = try allocator.alloc(bool, file_paths.len);
    defer allocator.free(resolved_modules);
    @memset(sources, "");
    @memset(resolved_modules, false);

    for (topo_order) |file_id| {
        const loaded = try file_loader.loadFile(allocator, file_paths[file_id]);
        allocator.free(loaded.absolute_path);
        sources[file_id] = loaded.source;

        const ast_file = try translate.parseSource(allocator, file_id, sources[file_id]);
        const module = try single_resolver.resolve(allocator, ast_file, file_id);

        const components = @constCast(module.components);
        for (components) |*component| {
            for (import_table) |entry| {
                if (entry.importing_file != file_id) continue;
                if (!componentMatchesAlias(component.*, entry.alias)) continue;
                component.kind = .{
                    .sub_circuit_ref = .{
                        .name = entry.alias,
                        .span = component.span,
                    },
                };
                break;
            }
        }

        var merged_imports: std.ArrayList(ir.UnresolvedImport) = .{};
        defer merged_imports.deinit(allocator);

        try merged_imports.appendSlice(allocator, module.imports);
        allocator.free(module.imports);

        const implicit_span = ir.Span{
            .file_id = module.file_id.value,
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 1,
        };

        for (import_table) |entry| {
            if (entry.importing_file != file_id or !entry.implicit_builtin) continue;
            try merged_imports.append(allocator, .{
                .alias = try allocator.dupe(u8, entry.alias),
                .path = try allocator.dupe(u8, file_paths[entry.target_file]),
                .span = implicit_span,
                .implicit_builtin = true,
            });
        }

        modules[file_id] = ir.Module{
            .file_id = module.file_id,
            .inputs = module.inputs,
            .outputs = module.outputs,
            .components = module.components,
            .connections = module.connections,
            .imports = try merged_imports.toOwnedSlice(allocator),
        };
        resolved_modules[file_id] = true;
    }

    for (resolved_modules) |done| {
        if (!done) return error.MissingResolvedModule;
    }

    var project_imports = try allocator.alloc(ir.ResolvedImport, import_table.len);
    for (import_table, 0..) |entry, idx| {
        project_imports[idx] = .{
            .importing_file = .{ .value = entry.importing_file },
            .alias = try allocator.dupe(u8, entry.alias),
            .target_file = .{ .value = entry.target_file },
            .span = toIrSpan(entry.span),
        };
    }

    var project_paths = try allocator.alloc([]const u8, file_paths.len);
    for (file_paths, 0..) |path, idx| {
        project_paths[idx] = try allocator.dupe(u8, path);
    }

    return .{
        .files = modules,
        .root_file_id = .{ .value = 0 },
        .import_table = project_imports,
        .file_paths = project_paths,
        .source_blobs = sources,
    };
}
