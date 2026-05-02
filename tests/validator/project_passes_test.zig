const std = @import("std");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const diagnostics = @import("diagnostics");
const validator_run_project = @import("validator_run_project");

fn fixtureRoot(comptime project_name: []const u8) []const u8 {
    return "tests/fixtures/projects/" ++ project_name ++ "/root.circ";
}

fn resolveProject(allocator: std.mem.Allocator, root_path: []const u8) !@import("ir_types").Project {
    var scan = try scan_imports.scanProjectImports(allocator, root_path);
    defer scan.deinit(allocator);
    var cycle = try import_cycle.analyzeImports(allocator, scan.file_paths, scan.import_table);
    defer cycle.deinit(allocator);
    return try resolve_bodies.resolveBodies(
        allocator,
        scan.file_paths,
        scan.import_table,
        cycle.topo_order,
    );
}

fn lessByLocation(_: void, lhs: diagnostics.Diagnostic, rhs: diagnostics.Diagnostic) bool {
    if (lhs.span.file_id != rhs.span.file_id) return lhs.span.file_id < rhs.span.file_id;
    if (lhs.span.start_line != rhs.span.start_line) return lhs.span.start_line < rhs.span.start_line;
    if (lhs.span.start_col != rhs.span.start_col) return lhs.span.start_col < rhs.span.start_col;
    return @intFromEnum(lhs.code) < @intFromEnum(rhs.code);
}

fn collectCodes(
    allocator: std.mem.Allocator,
    items: []const diagnostics.Diagnostic,
) ![]diagnostics.DiagnosticCode {
    var codes = std.ArrayList(diagnostics.DiagnosticCode).init(allocator);
    for (items) |d| try codes.append(d.code);
    return codes.toOwnedSlice(allocator);
}

test "project validator: clean_two_file produces no diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("clean_two_file"));
    var diag_list = try validator_run_project.run(allocator, &project);
    defer diag_list.deinit(allocator);

    const found_errors = blk: {
        for (diag_list.items) |d| {
            if (d.level == .err) break :blk true;
        }
        break :blk false;
    };
    try std.testing.expect(!found_errors);
}

test "project validator: E012 unknown sub-circuit port" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("E012_unknown_port"));
    var diag_list = try validator_run_project.run(allocator, &project);
    defer diag_list.deinit(allocator);

    std.mem.sort(diagnostics.Diagnostic, diag_list.items, {}, lessByLocation);

    var found_e012 = false;
    for (diag_list.items) |d| {
        if (d.code == .E012) { found_e012 = true; break; }
    }
    try std.testing.expect(found_e012);
}

test "project validator: E013 sub-circuit arity mismatch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("E013_missing_input"));
    var diag_list = try validator_run_project.run(allocator, &project);
    defer diag_list.deinit(allocator);

    var found_e013 = false;
    for (diag_list.items) |d| {
        if (d.code == .E013) { found_e013 = true; break; }
    }
    try std.testing.expect(found_e013);
}

test "project validator: E008 combinational loop through sub-circuit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("E008_loop_through_subcircuit"));
    var diag_list = try validator_run_project.run(allocator, &project);
    defer diag_list.deinit(allocator);

    var found_e008 = false;
    for (diag_list.items) |d| {
        if (d.code == .E008) { found_e008 = true; break; }
    }
    try std.testing.expect(found_e008);
}

test "project validator: W003 unused import in project" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("W003_unused_import"));
    var diag_list = try validator_run_project.run(allocator, &project);
    defer diag_list.deinit(allocator);

    var found_w003 = false;
    for (diag_list.items) |d| {
        if (d.code == .W003) { found_w003 = true; break; }
    }
    try std.testing.expect(found_w003);
}

test "project validator: W002 dangling sub-circuit output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const project = try resolveProject(allocator, fixtureRoot("W002_dangling_subcircuit_output"));
    var diag_list = try validator_run_project.run(allocator, &project);
    defer diag_list.deinit(allocator);

    var found_w002 = false;
    for (diag_list.items) |d| {
        if (d.code == .W002) { found_w002 = true; break; }
    }
    try std.testing.expect(found_w002);
}
