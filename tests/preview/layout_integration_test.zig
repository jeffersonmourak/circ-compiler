const std = @import("std");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const validator_run_project = @import("validator_run_project");
const diagnostics = @import("diagnostics");
const full_serializer = @import("full_serializer");
const layout = @import("layout");
const orchestrator = @import("orchestrator");
const preview_dump = @import("preview_dump");
const golden = @import("golden");

fn hasHardErrors(diags: []const diagnostics.Diagnostic) bool {
    for (diags) |d| {
        if (d.level == .err) return true;
    }
    return false;
}

fn buildAndDumpLayout(
    arena: std.mem.Allocator,
    fixture_path: []const u8,
    expand_macros: bool,
) ![]const u8 {
    const scan_result = try scan_imports.scanProjectImports(arena, fixture_path);
    if (hasHardErrors(scan_result.diagnostics.items)) return error.ScanFailed;
    const cycle_result = try import_cycle.analyzeImports(arena, scan_result.file_paths, scan_result.import_table);
    if (hasHardErrors(cycle_result.diagnostics.items)) return error.CycleFailed;
    var resolver_diagnostics = diagnostics.initDiagnosticList();
    const project = try resolve_bodies.resolveBodies(
        arena,
        scan_result.file_paths,
        scan_result.import_table,
        cycle_result.topo_order,
        &resolver_diagnostics,
    );
    if (hasHardErrors(resolver_diagnostics.items)) return error.UnexpectedResolverDiagnostics;
    var diag_list = try validator_run_project.run(arena, &project);
    defer diag_list.deinit(arena);
    if (hasHardErrors(diag_list.items)) return error.UnexpectedDiagnostics;

    var topology = try full_serializer.buildFromProject(arena, &project);
    defer topology.deinit(arena);

    const grid = try orchestrator.build(arena, topology, .{ .expand_macros = expand_macros });

    var buf: std.ArrayList(u8) = .{};
    try preview_dump.dumpLayout(buf.writer(arena), grid);
    return buf.toOwnedSlice(arena);
}

test "phase2_layout_primitives_opaque" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dump = try buildAndDumpLayout(a, "tests/fixtures/circuits/chain.circ", false);
    try golden.expectGolden(dump, "tests/fixtures/preview/layouts/chain.layout.opaque.golden");
}

test "phase2_layout_builtin_xor_opaque" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dump = try buildAndDumpLayout(a, "tests/fixtures/circuits/builtin_xor.circ", false);
    try golden.expectGolden(dump, "tests/fixtures/preview/layouts/builtin_xor.layout.opaque.golden");
}

test "phase2_layout_builtin_xor_expanded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dump = try buildAndDumpLayout(a, "tests/fixtures/circuits/builtin_xor.circ", true);
    try golden.expectGolden(dump, "tests/fixtures/preview/layouts/builtin_xor.layout.expanded.golden");
}

test "phase2_layout_builtin_xnor_opaque" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dump = try buildAndDumpLayout(a, "tests/fixtures/circuits/builtin_xnor.circ", false);
    try golden.expectGolden(dump, "tests/fixtures/preview/layouts/builtin_xnor.layout.opaque.golden");
}

test "phase2_layout_builtin_xnor_expanded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dump = try buildAndDumpLayout(a, "tests/fixtures/circuits/builtin_xnor.circ", true);
    try golden.expectGolden(dump, "tests/fixtures/preview/layouts/builtin_xnor.layout.expanded.golden");
}

test "phase2_layout_deterministic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dump1 = try buildAndDumpLayout(a, "tests/fixtures/circuits/builtin_xor.circ", false);
    const dump2 = try buildAndDumpLayout(a, "tests/fixtures/circuits/builtin_xor.circ", false);
    try std.testing.expectEqualStrings(dump1, dump2);
}
