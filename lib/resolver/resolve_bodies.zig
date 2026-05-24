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

fn stubModule(file_id: u32) ir.Module {
    return .{
        .file_id = .{ .value = file_id },
        .inputs = &.{},
        .outputs = &.{},
        .components = &.{},
        .connections = &.{},
        .imports = &.{},
    };
}

fn countInputPins(file: ast.File) u32 {
    var total: u32 = 0;
    for (file.inputs) |decl| total += @intCast(decl.names.len);
    return total;
}

fn collectParameters(allocator: std.mem.Allocator, file: ast.File) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .{};
    errdefer names.deinit(allocator);
    for (file.inputs) |input_decl| {
        for (input_decl.parameters) |param| {
            var seen = false;
            for (names.items) |existing| {
                if (std.mem.eql(u8, existing, param.text)) {
                    seen = true;
                    break;
                }
            }
            if (!seen) try names.append(allocator, param.text);
        }
    }
    return names.toOwnedSlice(allocator);
}

const SpecResult = struct {
    paths: std.ArrayList([]const u8),
    sources: std.ArrayList([]const u8),
};

fn buildSpecializationKey(
    allocator: std.mem.Allocator,
    target_file_id: u32,
    bindings: []const single_resolver.WidthBinding,
) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.print("{d}@", .{target_file_id});
    for (bindings, 0..) |b, idx| {
        if (idx > 0) try buf.append(allocator, ',');
        try writer.print("{d}", .{b.value});
    }
    return buf.toOwnedSlice(allocator);
}

fn specializeCallSites(
    allocator: std.mem.Allocator,
    modules_list: *std.ArrayList(ir.Module),
    file_paths: []const []const u8,
    import_table: []const scan_imports.ResolvedImport,
    asts: []const ?ast.File,
    spec: *SpecResult,
    diagnostic_list: *diagnostics.DiagnosticList,
) !void {
    // Cache keyed by "{target_file_id}@{w0},{w1},...". Two call sites with
    // the same target and the same width-binding tuple share one specialized
    // module instead of duplicating the body. Keys are owned by the cache
    // and freed on scope exit.
    var spec_cache = std.StringHashMap(u32).init(allocator);
    defer {
        var it = spec_cache.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        spec_cache.deinit();
    }

    const original_file_count = file_paths.len;
    for (asts, 0..) |maybe_caller_ast, caller_file_id_usize| {
        if (caller_file_id_usize >= original_file_count) break;
        const caller_ast = maybe_caller_ast orelse continue;
        const caller_file_id: u32 = @intCast(caller_file_id_usize);

        const input_pin_count = countInputPins(caller_ast);
        const caller_module = &modules_list.items[caller_file_id];
        const caller_components = @constCast(caller_module.components);

        for (caller_ast.components, 0..) |ast_inst, ast_idx| {
            const ir_comp_idx = input_pin_count + @as(u32, @intCast(ast_idx));
            if (ir_comp_idx >= caller_components.len) continue;
            const ir_comp = &caller_components[ir_comp_idx];
            if (ir_comp.kind != .sub_circuit_ref) continue;

            const target_file_id_opt: ?u32 = blk: {
                for (import_table) |entry| {
                    if (entry.importing_file != caller_file_id) continue;
                    if (!std.mem.eql(u8, entry.alias, ast_inst.type_name.text)) continue;
                    break :blk entry.target_file;
                }
                break :blk null;
            };
            const target_file_id = target_file_id_opt orelse continue;
            const target_ast = asts[target_file_id] orelse continue;
            if (!fileIsParametric(target_ast)) continue;

            const declared_params = try collectParameters(allocator, target_ast);
            defer allocator.free(declared_params);
            const supplied = ast_inst.width_args;

            if (supplied.len != 0 and supplied.len != declared_params.len) {
                const message = try std.fmt.allocPrint(
                    allocator,
                    "parameter count mismatch: sub-circuit '{s}' declares {d} parameter(s), call site supplies {d}",
                    .{ ast_inst.type_name.text, declared_params.len, supplied.len },
                );
                var d = diagnostics.makeDiagnostic(.E016, diagnosticSpan(ast_inst.span));
                d.message = message;
                try diagnostic_list.append(allocator, d);
                continue;
            }

            var bindings: std.ArrayList(single_resolver.WidthBinding) = .{};
            defer bindings.deinit(allocator);
            if (supplied.len == 0) {
                for (declared_params) |name| {
                    try bindings.append(allocator, .{ .name = name, .value = 1 });
                }
            } else {
                var ok = true;
                for (declared_params, supplied) |name, spec_arg| {
                    switch (spec_arg) {
                        .literal => |n| try bindings.append(allocator, .{ .name = name, .value = n }),
                        .parameter => |passed_name| {
                            const message = try std.fmt.allocPrint(
                                allocator,
                                "parameter pass-through is not yet supported; call site supplies parameter '{s}'",
                                .{passed_name},
                            );
                            var d = diagnostics.makeDiagnostic(.E016, diagnosticSpan(ast_inst.span));
                            d.message = message;
                            try diagnostic_list.append(allocator, d);
                            ok = false;
                            break;
                        },
                    }
                }
                if (!ok) continue;
            }

            const cache_key = try buildSpecializationKey(allocator, target_file_id, bindings.items);
            if (spec_cache.get(cache_key)) |cached_file_id| {
                allocator.free(cache_key);
                ir_comp.kind.sub_circuit_ref.specialized_target_file = .{ .value = cached_file_id };
                continue;
            }

            const spec_file_id: u32 = @intCast(modules_list.items.len);
            const specialized = single_resolver.resolveWithBindings(
                allocator,
                target_ast,
                spec_file_id,
                bindings.items,
            ) catch |err| {
                allocator.free(cache_key);
                std.debug.print("specialization failed for '{s}': {s}\n", .{ ast_inst.type_name.text, @errorName(err) });
                continue;
            };

            try modules_list.append(allocator, specialized);
            const synthetic_path = try std.fmt.allocPrint(
                allocator,
                "<specialization:{s}@{s}>",
                .{ ast_inst.type_name.text, file_paths[target_file_id] },
            );
            try spec.paths.append(allocator, synthetic_path);
            try spec.sources.append(allocator, "");

            try spec_cache.put(cache_key, spec_file_id);

            ir_comp.kind.sub_circuit_ref.specialized_target_file = .{ .value = spec_file_id };
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
    var modules_list: std.ArrayList(ir.Module) = .{};
    errdefer modules_list.deinit(allocator);
    try modules_list.resize(allocator, file_paths.len);
    var sources_list: std.ArrayList([]const u8) = .{};
    errdefer sources_list.deinit(allocator);
    try sources_list.resize(allocator, file_paths.len);
    @memset(sources_list.items, "");
    var resolved_modules = try allocator.alloc(bool, file_paths.len);
    defer allocator.free(resolved_modules);
    var asts = try allocator.alloc(?ast.File, file_paths.len);
    defer allocator.free(asts);
    @memset(resolved_modules, false);
    @memset(asts, null);

    for (topo_order) |file_id| {
        const loaded = try file_loader.loadFile(allocator, file_paths[file_id]);
        allocator.free(loaded.absolute_path);
        sources_list.items[file_id] = loaded.source;

        const ast_file = try translate.parseSource(allocator, file_id, sources_list.items[file_id]);
        asts[file_id] = ast_file;

        if (fileIsParametric(ast_file)) {
            // Parametric callees never materialize as a standalone IR module;
            // every call site re-resolves the AST with concrete width bindings,
            // producing a specialized module appended after the original-file
            // range. The stub here keeps modules_list[file_id] structurally
            // valid for code that iterates project.files unconditionally.
            modules_list.items[file_id] = stubModule(file_id);
            resolved_modules[file_id] = true;
            continue;
        }

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

        modules_list.items[file_id] = ir.Module{
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

    var spec_result = SpecResult{
        .paths = .{},
        .sources = .{},
    };
    errdefer {
        spec_result.paths.deinit(allocator);
        spec_result.sources.deinit(allocator);
    }

    try specializeCallSites(allocator, &modules_list, file_paths, import_table, asts, &spec_result, diagnostic_list);

    var project_imports = try allocator.alloc(ir.ResolvedImport, import_table.len);
    for (import_table, 0..) |entry, idx| {
        project_imports[idx] = .{
            .importing_file = .{ .value = entry.importing_file },
            .alias = try allocator.dupe(u8, entry.alias),
            .target_file = .{ .value = entry.target_file },
            .span = toIrSpan(entry.span),
        };
    }

    var project_paths_list: std.ArrayList([]const u8) = .{};
    errdefer project_paths_list.deinit(allocator);
    for (file_paths) |path| try project_paths_list.append(allocator, try allocator.dupe(u8, path));
    try project_paths_list.appendSlice(allocator, spec_result.paths.items);
    spec_result.paths.deinit(allocator);

    try sources_list.appendSlice(allocator, spec_result.sources.items);
    spec_result.sources.deinit(allocator);

    return .{
        .files = try modules_list.toOwnedSlice(allocator),
        .root_file_id = .{ .value = 0 },
        .import_table = project_imports,
        .file_paths = try project_paths_list.toOwnedSlice(allocator),
        .source_blobs = try sources_list.toOwnedSlice(allocator),
    };
}
