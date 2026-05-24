const std = @import("std");
const translate = @import("translate");
const ast = translate.Ast;
const single_resolver = @import("resolver");
const ir = @import("ir_types");
const scan_imports = @import("scan_imports");
const file_loader = @import("file_loader");
const diagnostics = @import("diagnostics");

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

fn fileIsParametric(file: ast.File) bool {
    for (file.inputs) |input_decl| {
        if (input_decl.parameters.len > 0) return true;
    }
    return false;
}

fn writeWidthArgs(writer: anytype, width_args: []const ast.WidthSpec) !void {
    try writer.writeByte('[');
    for (width_args, 0..) |spec, idx| {
        if (idx > 0) try writer.writeAll(", ");
        switch (spec) {
            .literal => |n| try writer.print("{d}", .{n}),
            .parameter => |name| try writer.writeAll(name),
        }
    }
    try writer.writeByte(']');
}

fn diagnosticSpan(span: anytype) diagnostics.Span {
    return .{
        .file_id = span.file_id,
        .start_line = span.start_line,
        .start_col = span.start_col,
        .end_line = span.end_line,
        .end_col = span.end_col,
    };
}

fn checkParametricCalls(
    allocator: std.mem.Allocator,
    asts: []const ?ast.File,
    import_table: []const scan_imports.ResolvedImport,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    for (asts, 0..) |maybe_caller, file_id_usize| {
        const caller = maybe_caller orelse continue;
        const file_id: u32 = @intCast(file_id_usize);

        for (caller.components) |comp_instance| {
            if (comp_instance.width_args.len == 0) continue;

            const target_file_id = for (import_table) |entry| {
                if (entry.importing_file != file_id) continue;
                if (!std.mem.eql(u8, entry.alias, comp_instance.type_name.text)) continue;
                break entry.target_file;
            } else continue;

            const target = asts[target_file_id] orelse continue;
            if (fileIsParametric(target)) continue;

            var formatted: std.ArrayList(u8) = .{};
            defer formatted.deinit(allocator);
            try writeWidthArgs(formatted.writer(allocator), comp_instance.width_args);

            const message = try std.fmt.allocPrint(
                allocator,
                "sub-circuit '{s}' is not parametric; supplied {s} widths",
                .{ comp_instance.type_name.text, formatted.items },
            );

            var notes: []diagnostics.DiagnosticNote = &.{};
            if (target.inputs.len > 0) {
                const note_message = try std.fmt.allocPrint(
                    allocator,
                    "add '<W>' before the input names in '{s}' to make it parametric",
                    .{comp_instance.type_name.text},
                );
                const allocated_notes = try allocator.alloc(diagnostics.DiagnosticNote, 1);
                allocated_notes[0] = .{
                    .span = diagnosticSpan(target.inputs[0].span),
                    .message = note_message,
                };
                notes = allocated_notes;
            }

            var d = diagnostics.makeDiagnostic(.E015, diagnosticSpan(comp_instance.span));
            d.message = message;
            d.notes = notes;
            try diagnostic_list.append(allocator, d);
        }
    }
}

pub fn resolveBodies(
    allocator: std.mem.Allocator,
    file_paths: []const []const u8,
    import_table: []const scan_imports.ResolvedImport,
    topo_order: []const scan_imports.FileId,
    diagnostic_list: *diagnostics.DiagnosticList,
) !ir.Project {
    var modules = try allocator.alloc(ir.Module, file_paths.len);
    errdefer allocator.free(modules);
    var sources = try allocator.alloc([]const u8, file_paths.len);
    errdefer allocator.free(sources);
    var resolved_modules = try allocator.alloc(bool, file_paths.len);
    defer allocator.free(resolved_modules);
    var asts = try allocator.alloc(?ast.File, file_paths.len);
    defer allocator.free(asts);
    @memset(sources, "");
    @memset(resolved_modules, false);
    @memset(asts, null);

    for (topo_order) |file_id| {
        const loaded = try file_loader.loadFile(allocator, file_paths[file_id]);
        allocator.free(loaded.absolute_path);
        sources[file_id] = loaded.source;

        const ast_file = try translate.parseSource(allocator, file_id, sources[file_id]);
        asts[file_id] = ast_file;
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

    try checkParametricCalls(allocator, asts, import_table, diagnostic_list);

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
