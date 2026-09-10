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

// One unit of specialization work. Original-file callers enter with empty
// bindings; each specialization enters with the bindings that produced it
// and the original-AST file_id it was specialized from (for import lookups
// and to find the same AST the resolver was driven by).
const SpecWorkItem = struct {
    module_file_id: u32,
    ast_source_file_id: u32,
    ast_file: ast.File,
    bindings: []single_resolver.WidthBinding,
};

fn resolveWidthArg(
    spec_arg: ast.WidthSpec,
    caller_bindings: []const single_resolver.WidthBinding,
) ?u8 {
    return switch (spec_arg) {
        .literal => |n| n,
        .parameter => |name| blk: {
            for (caller_bindings) |b| {
                if (std.mem.eql(u8, b.name, name)) break :blk b.value;
            }
            break :blk null;
        },
    };
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
    var worklist: std.ArrayList(SpecWorkItem) = .{};
    defer {
        for (worklist.items) |item| {
            if (item.bindings.len > 0) allocator.free(item.bindings);
        }
        worklist.deinit(allocator);
    }

    // Seed the worklist with non-parametric original callers; parametric
    // callees are never directly resolved (the stub module fills their slot
    // and downstream lookups follow specialized_target_file instead).
    for (asts, 0..) |maybe_caller_ast, file_id_usize| {
        if (file_id_usize >= original_file_count) break;
        const caller_ast = maybe_caller_ast orelse continue;
        if (fileIsParametric(caller_ast)) continue;
        try worklist.append(allocator, .{
            .module_file_id = @intCast(file_id_usize),
            .ast_source_file_id = @intCast(file_id_usize),
            .ast_file = caller_ast,
            .bindings = &.{},
        });
    }

    while (worklist.items.len > 0) {
        const item = worklist.orderedRemove(0);
        defer if (item.bindings.len > 0) allocator.free(item.bindings);

        const input_pin_count = countInputPins(item.ast_file);
        const caller_module = &modules_list.items[item.module_file_id];
        const caller_components = @constCast(caller_module.components);

        for (item.ast_file.components, 0..) |ast_inst, ast_idx| {
            const ir_comp_idx = input_pin_count + @as(u32, @intCast(ast_idx));
            if (ir_comp_idx >= caller_components.len) continue;
            const ir_comp = &caller_components[ir_comp_idx];
            if (ir_comp.kind != .sub_circuit_ref) continue;

            // Import lookup uses the ORIGINAL file_id the AST came from, not
            // the spec's synthetic module_file_id (which the import_table
            // doesn't know about).
            const target_file_id_opt: ?u32 = blk: {
                for (import_table) |entry| {
                    if (entry.importing_file != item.ast_source_file_id) continue;
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
                    const value = resolveWidthArg(spec_arg, item.bindings) orelse {
                        const passed_name = switch (spec_arg) {
                            .parameter => |n| n,
                            else => "?",
                        };
                        const message = try std.fmt.allocPrint(
                            allocator,
                            "unbound parameter '{s}' at call site of '{s}'",
                            .{ passed_name, ast_inst.type_name.text },
                        );
                        var d = diagnostics.makeDiagnostic(.E016, diagnosticSpan(ast_inst.span));
                        d.message = message;
                        try diagnostic_list.append(allocator, d);
                        ok = false;
                        break;
                    };
                    try bindings.append(allocator, .{ .name = name, .value = value });
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
            var specialized = single_resolver.resolveWithBindings(
                allocator,
                target_ast,
                spec_file_id,
                bindings.items,
            ) catch |err| {
                allocator.free(cache_key);
                std.log.scoped(.resolver).warn("specialization failed for '{s}': {s}", .{ ast_inst.type_name.text, @errorName(err) });
                continue;
            };
            // Record the original AST source so downstream lookups
            // (topology origin frames, project-level import resolution)
            // can resolve against the user-written file path rather than
            // the spec's synthetic file id.
            specialized.source_file_id = .{ .value = target_file_id };

            // Apply the same alias rewrite the topo loop performs on original
            // file resolutions: any component whose kind is .unresolved_name
            // and whose name matches an import alias for the spec's source
            // file becomes a sub_circuit_ref. Without this, nested call sites
            // inside a spec (e.g. `or inner[W]` in nor.circ) would stay
            // unresolved and trip E001.
            const spec_components = @constCast(specialized.components);
            for (spec_components) |*c| {
                for (import_table) |entry| {
                    if (entry.importing_file != target_file_id) continue;
                    if (!componentMatchesAlias(c.*, entry.alias)) continue;
                    c.kind = .{
                        .sub_circuit_ref = .{
                            .name = entry.alias,
                            .span = c.span,
                        },
                    };
                    break;
                }
            }

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

            // Enqueue the new spec for recursive specialization of any call
            // sites in its body. Duplicate the bindings into the worklist
            // entry so the original `bindings` ArrayList can be reused/freed.
            const owned_bindings = try allocator.dupe(single_resolver.WidthBinding, bindings.items);
            try worklist.append(allocator, .{
                .module_file_id = spec_file_id,
                .ast_source_file_id = target_file_id,
                .ast_file = target_ast,
                .bindings = owned_bindings,
            });
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
    return resolveBodiesWithOverlay(allocator, file_paths, import_table, topo_order, diagnostic_list, null);
}

pub fn resolveBodiesWithOverlay(
    allocator: std.mem.Allocator,
    file_paths: []const []const u8,
    import_table: []const scan_imports.ResolvedImport,
    topo_order: []const scan_imports.FileId,
    diagnostic_list: *diagnostics.DiagnosticList,
    overlay: ?file_loader.Overlay,
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
        const loaded = try file_loader.loadFileWithOverlay(allocator, file_paths[file_id], overlay);
        allocator.free(loaded.absolute_path);
        sources_list.items[file_id] = loaded.source;

        // A file that fails to parse (empty, or syntactically broken beyond
        // the parser's silent-truncation tolerance) must not abort the whole
        // project resolution: editor tooling relies on getting results for
        // every other file. Substitute an empty module and let the caller
        // (e.g. the --analyze surface) report the syntax error separately.
        const ast_file = translate.parseSource(allocator, file_id, sources_list.items[file_id]) catch ast.File{
            .imports = &.{},
            .inputs = &.{},
            .outputs = &.{},
            .components = &.{},
            .span = .{
                .file_id = file_id,
                .start_line = 1,
                .start_col = 1,
                .end_line = 1,
                .end_col = 1,
            },
        };
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
