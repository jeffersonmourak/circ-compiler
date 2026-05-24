const std = @import("std");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const diagnostics = @import("diagnostics");

fn fixtureRoot(comptime project_name: []const u8) []const u8 {
    return "tests/fixtures/projects/" ++ project_name ++ "/root.circ";
}

fn resolveProject(allocator: std.mem.Allocator, root_path: []const u8) !@import("ir_types").Project {
    var scan = try scan_imports.scanProjectImports(allocator, root_path);
    defer scan.deinit(allocator);

    var cycle = try import_cycle.analyzeImports(allocator, scan.file_paths, scan.import_table);
    defer cycle.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), scan.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 0), cycle.diagnostics.items.len);

    var resolver_diagnostics = diagnostics.initDiagnosticList();
    return try resolve_bodies.resolveBodies(
        allocator,
        scan.file_paths,
        scan.import_table,
        cycle.topo_order,
        &resolver_diagnostics,
    );
}

test "resolve bodies links imported alias to sub_circuit_ref" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("two_file"));
    try std.testing.expectEqual(@as(usize, 7), project.files.len);

    const root_module = project.files[0];
    var linked = false;
    for (root_module.components) |component| {
        if (component.instance_name == null) continue;
        if (!std.mem.eql(u8, component.instance_name.?, "u1")) continue;
        switch (component.kind) {
            .sub_circuit_ref => |sub| {
                try std.testing.expectEqualStrings("child", sub.name);
                linked = true;
            },
            else => {},
        }
    }

    try std.testing.expect(linked);
}

test "resolve bodies preserves unresolved names not imported" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("unresolved_name"));
    const root_module = project.files[0];

    var found_unresolved = false;
    for (root_module.components) |component| {
        if (component.instance_name == null) continue;
        if (!std.mem.eql(u8, component.instance_name.?, "u1")) continue;
        switch (component.kind) {
            .unresolved_name => |name| {
                try std.testing.expectEqualStrings("mystery", name);
                found_unresolved = true;
            },
            else => {},
        }
    }

    try std.testing.expect(found_unresolved);
}

test "resolve bodies preserves primitive components" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("primitive_preserve"));
    const root_module = project.files[0];

    var found_and_gate = false;
    for (root_module.components) |component| {
        if (component.instance_name == null) continue;
        if (!std.mem.eql(u8, component.instance_name.?, "g")) continue;
        switch (component.kind) {
            .primitive => |kind| {
                try std.testing.expectEqual(.and_gate, kind);
                found_and_gate = true;
            },
            else => {},
        }
    }

    try std.testing.expect(found_and_gate);
}

test "resolve bodies propagates widths through imported sub-circuits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("multibit_import"));

    // Find the imported module by file path suffix (file ids depend on scan order).
    var lib_module: ?@import("ir_types").Module = null;
    for (project.files, project.file_paths) |module, path| {
        if (std.mem.endsWith(u8, path, "wide_and_lib.circ")) {
            lib_module = module;
            break;
        }
    }
    const lib = lib_module orelse return error.LibModuleMissing;

    for (lib.inputs) |input| try std.testing.expectEqual(@as(u8, 4), input.width);
    for (lib.outputs) |output| try std.testing.expectEqual(@as(u8, 4), output.width);
    for (lib.components) |component| try std.testing.expectEqual(@as(u8, 4), component.width);

    // Root module pins are also width 4; the imported sub_circuit_ref instance
    // inherits no width itself (width gates on primitive expansion downstream).
    const root = project.files[project.root_file_id.value];
    for (root.inputs) |input| try std.testing.expectEqual(@as(u8, 4), input.width);
    for (root.outputs) |output| try std.testing.expectEqual(@as(u8, 4), output.width);

    var linked_sub_ref = false;
    for (root.components) |component| {
        if (component.instance_name == null) continue;
        if (!std.mem.eql(u8, component.instance_name.?, "inst")) continue;
        switch (component.kind) {
            .sub_circuit_ref => |sub| {
                try std.testing.expectEqualStrings("wide_and", sub.name);
                linked_sub_ref = true;
            },
            else => {},
        }
    }
    try std.testing.expect(linked_sub_ref);
}

fn lookupPinWidth(module: @import("ir_types").Module, name: []const u8, comptime kind: enum { input, output }) ?u8 {
    return switch (kind) {
        .input => blk: {
            for (module.inputs) |p| {
                if (std.mem.eql(u8, p.name, name)) break :blk p.width;
            }
            break :blk null;
        },
        .output => blk: {
            for (module.outputs) |p| {
                if (std.mem.eql(u8, p.name, name)) break :blk p.width;
            }
            break :blk null;
        },
    };
}

fn findSpecializedModule(project: @import("ir_types").Project, original_path_suffix: []const u8) ?@import("ir_types").Module {
    // Synthetic spec paths are formatted "<specialization:alias@<original-path>>"
    for (project.files, project.file_paths) |module, path| {
        if (!std.mem.startsWith(u8, path, "<specialization:")) continue;
        if (std.mem.indexOf(u8, path, original_path_suffix) == null) continue;
        return module;
    }
    return null;
}

test "multi-parameter specialization binds widths positionally" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("parametric_multi"));
    const spec = findSpecializedModule(project, "mux_lib.circ") orelse return error.SpecializationMissing;

    try std.testing.expectEqual(@as(u8, 4), lookupPinWidth(spec, "data", .input).?);
    try std.testing.expectEqual(@as(u8, 2), lookupPinWidth(spec, "select", .input).?);
    try std.testing.expectEqual(@as(u8, 4), lookupPinWidth(spec, "data_out", .output).?);
    try std.testing.expectEqual(@as(u8, 2), lookupPinWidth(spec, "sel_out", .output).?);
}

test "three-parameter specialization extends to arity 3" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("parametric_multi_3"));
    const spec = findSpecializedModule(project, "triple_lib.circ") orelse return error.SpecializationMissing;

    try std.testing.expectEqual(@as(u8, 4), lookupPinWidth(spec, "a", .input).?);
    try std.testing.expectEqual(@as(u8, 2), lookupPinWidth(spec, "b", .input).?);
    try std.testing.expectEqual(@as(u8, 8), lookupPinWidth(spec, "c", .input).?);
}

test "default-to-1 applies to all parameters when no call-site widths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("parametric_multi_default"));
    const spec = findSpecializedModule(project, "mux_lib.circ") orelse return error.SpecializationMissing;

    try std.testing.expectEqual(@as(u8, 1), lookupPinWidth(spec, "data", .input).?);
    try std.testing.expectEqual(@as(u8, 1), lookupPinWidth(spec, "select", .input).?);
    try std.testing.expectEqual(@as(u8, 1), lookupPinWidth(spec, "data_out", .output).?);
    try std.testing.expectEqual(@as(u8, 1), lookupPinWidth(spec, "sel_out", .output).?);
}

test "parameter binding order follows source declaration, not reference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // lib.circ declares <W, X> but uses X first then W in input declarations.
    // root.circ calls with [4, 8]. Per decision #9, W=4 (first declared) and X=8.
    const project = try resolveProject(allocator, fixtureRoot("parametric_ordering"));
    const spec = findSpecializedModule(project, "lib.circ") orelse return error.SpecializationMissing;

    try std.testing.expectEqual(@as(u8, 4), lookupPinWidth(spec, "data", .input).?);
    try std.testing.expectEqual(@as(u8, 8), lookupPinWidth(spec, "aux", .input).?);
    try std.testing.expectEqual(@as(u8, 4), lookupPinWidth(spec, "data_out", .output).?);
    try std.testing.expectEqual(@as(u8, 8), lookupPinWidth(spec, "aux_out", .output).?);
}

fn countSpecializations(project: @import("ir_types").Project) usize {
    var count: usize = 0;
    for (project.file_paths) |path| {
        if (std.mem.startsWith(u8, path, "<specialization:")) count += 1;
    }
    return count;
}

fn countCallSitesTargeting(project: @import("ir_types").Project, expected_target_file_id_min: u32) usize {
    // Count caller-side sub_circuit_ref components whose specialized_target_file
    // points at some appended specialization (file_id >= original_file_count).
    var count: usize = 0;
    for (project.files) |module| {
        for (module.components) |comp| {
            switch (comp.kind) {
                .sub_circuit_ref => |ref| {
                    if (ref.specialized_target_file) |target| {
                        if (target.value >= expected_target_file_id_min) count += 1;
                    }
                },
                else => {},
            }
        }
    }
    return count;
}

test "cache: identical bindings share one specialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Two call sites at width 4 → cache produces exactly one specialization
    // module despite two sub_circuit_ref components pointing into it.
    const project = try resolveProject(allocator, fixtureRoot("shared_spec"));
    try std.testing.expectEqual(@as(usize, 1), countSpecializations(project));
    try std.testing.expectEqual(@as(usize, 2), countCallSitesTargeting(project, @intCast(project.file_paths.len - 1)));
}

test "cache: distinct bindings produce separate specializations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Call sites at width 4 and width 8 → cache misses on the second key
    // and produces two distinct specialization modules.
    const project = try resolveProject(allocator, fixtureRoot("distinct_bindings"));
    try std.testing.expectEqual(@as(usize, 2), countSpecializations(project));
}

test "cache: multi-param identical bindings share one specialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Two call sites at (W=4, S=2) → one shared specialization.
    const project = try resolveProject(allocator, fixtureRoot("multi_param_shared"));
    try std.testing.expectEqual(@as(usize, 1), countSpecializations(project));
}

test "cache: multi-param distinct binding tuples are not shared" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // (4, 2) vs (2, 4) are distinct cache keys even though they share the
    // same width values — order matters.
    const project = try resolveProject(allocator, fixtureRoot("multi_param_distinct"));
    try std.testing.expectEqual(@as(usize, 2), countSpecializations(project));
}

fn macroSpecForWidth(project: @import("ir_types").Project, macro_name: []const u8, expected_width: u8) ?@import("ir_types").Module {
    for (project.files, project.file_paths) |module, path| {
        if (!std.mem.startsWith(u8, path, "<specialization:")) continue;
        if (std.mem.indexOf(u8, path, macro_name) == null) continue;
        const a_width = lookupPinWidth(module, "a", .input) orelse continue;
        if (a_width == expected_width) return module;
    }
    return null;
}

test "macro or specializes to width 4" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, "tests/fixtures/circuits/or_4bit_macro.circ");
    const spec = macroSpecForWidth(project, "or.circ", 4) orelse return error.MissingOrSpec;
    try std.testing.expectEqual(@as(u8, 4), lookupPinWidth(spec, "a", .input).?);
    try std.testing.expectEqual(@as(u8, 4), lookupPinWidth(spec, "b", .input).?);
    try std.testing.expectEqual(@as(u8, 4), lookupPinWidth(spec, "out", .output).?);
}

test "macro xor specializes to width 8" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, "tests/fixtures/circuits/xor_8bit_macro.circ");
    const spec = macroSpecForWidth(project, "xor.circ", 8) orelse return error.MissingXorSpec;
    try std.testing.expectEqual(@as(u8, 8), lookupPinWidth(spec, "out", .output).?);
}

test "macro nand specializes to width 4" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, "tests/fixtures/circuits/nand_4bit_macro.circ");
    const spec = macroSpecForWidth(project, "nand.circ", 4) orelse return error.MissingNandSpec;
    try std.testing.expectEqual(@as(u8, 4), lookupPinWidth(spec, "out", .output).?);
}

test "macro nor at width 8 propagates W through internal or call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, "tests/fixtures/circuits/nor_8bit_macro.circ");
    // The outer nor specializes at W=8.
    const nor_spec = macroSpecForWidth(project, "nor.circ", 8) orelse return error.MissingNorSpec;
    try std.testing.expectEqual(@as(u8, 8), lookupPinWidth(nor_spec, "out", .output).?);
    // The internal `or inner[W]` propagates W=8 through to a nested or specialization.
    // Without parameter pass-through support, this would either fail or default to W=1.
    const or_spec = macroSpecForWidth(project, "or.circ", 8) orelse return error.MissingNestedOrSpec;
    try std.testing.expectEqual(@as(u8, 8), lookupPinWidth(or_spec, "out", .output).?);
}

test "macro xnor at width 4 propagates W through internal xor call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, "tests/fixtures/circuits/xnor_4bit_macro.circ");
    const xnor_spec = macroSpecForWidth(project, "xnor.circ", 4) orelse return error.MissingXnorSpec;
    try std.testing.expectEqual(@as(u8, 4), lookupPinWidth(xnor_spec, "out", .output).?);
    const xor_spec = macroSpecForWidth(project, "xor.circ", 4) orelse return error.MissingNestedXorSpec;
    try std.testing.expectEqual(@as(u8, 4), lookupPinWidth(xor_spec, "out", .output).?);
}
