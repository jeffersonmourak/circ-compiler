//! Phase 9.3 — one formatted snapshot per diagnostic code (E001–E013, W001–W003).
const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const diagnostics = @import("diagnostics");
const validator_run = @import("validator_run");
const validator_run_project = @import("validator_run_project");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const golden = @import("golden");

fn relFixturePath(abs: []const u8) ?[]const u8 {
    const needle = "tests/fixtures/";
    if (std.mem.indexOf(u8, abs, needle)) |i| return abs[i..];
    return null;
}

fn normalizePathDisplay(abs: []const u8) []const u8 {
    return relFixturePath(abs) orelse abs;
}

fn normalizeMessage(allocator: std.mem.Allocator, msg: []const u8, paths: []const []const u8) ![]u8 {
    var rest = msg;
    var acc: std.ArrayList(u8) = .{};
    errdefer acc.deinit(allocator);

    while (rest.len > 0) {
        var best_pos: ?usize = null;
        var best_path: ?[]const u8 = null;

        for (paths) |p| {
            if (p.len == 0) continue;
            if (std.mem.indexOf(u8, rest, p)) |pos| {
                if (best_pos == null or pos < best_pos.? or
                    (pos == best_pos.? and p.len > best_path.?.len))
                {
                    best_pos = pos;
                    best_path = p;
                }
            }
        }

        const picked = best_path orelse {
            try acc.appendSlice(allocator, rest);
            return acc.toOwnedSlice(allocator);
        };
        const pos = best_pos.?;
        if (pos > 0) try acc.appendSlice(allocator, rest[0..pos]);
        try acc.appendSlice(allocator, normalizePathDisplay(picked));
        rest = rest[pos + picked.len ..];
    }

    return acc.toOwnedSlice(allocator);
}

fn normalizeDiagnostic(
    allocator: std.mem.Allocator,
    original: diagnostics.Diagnostic,
    paths: []const []const u8,
) !diagnostics.Diagnostic {
    const msg = try normalizeMessage(allocator, original.message, paths);
    errdefer allocator.free(msg);

    var note_list: std.ArrayList(diagnostics.DiagnosticNote) = .{};
    defer {
        for (note_list.items) |n| allocator.free(n.message);
        note_list.deinit(allocator);
    }

    for (original.notes) |note| {
        const nm = try normalizeMessage(allocator, note.message, paths);
        try note_list.append(allocator, .{
            .span = note.span,
            .message = nm,
        });
    }

    const notes_out = try note_list.toOwnedSlice(allocator);

    return .{
        .level = original.level,
        .code = original.code,
        .span = original.span,
        .message = msg,
        .notes = notes_out,
    };
}

fn hasHardErrors(items: []const diagnostics.Diagnostic) bool {
    for (items) |d| {
        if (d.level == .err) return true;
    }
    return false;
}

fn lessByLocation(_: void, lhs: diagnostics.Diagnostic, rhs: diagnostics.Diagnostic) bool {
    if (lhs.span.file_id != rhs.span.file_id) return lhs.span.file_id < rhs.span.file_id;
    if (lhs.span.start_line != rhs.span.start_line) return lhs.span.start_line < rhs.span.start_line;
    if (lhs.span.start_col != rhs.span.start_col) return lhs.span.start_col < rhs.span.start_col;
    return @intFromEnum(lhs.code) < @intFromEnum(rhs.code);
}

fn dumpDiagnostics(
    allocator: std.mem.Allocator,
    file_paths: []const []const u8,
    diagnostic_list: []const diagnostics.Diagnostic,
) ![]u8 {
    var owned: std.ArrayList(diagnostics.Diagnostic) = .{};
    defer {
        for (owned.items) |*d| {
            allocator.free(d.message);
            for (d.notes) |n| allocator.free(n.message);
            allocator.free(d.notes);
        }
        owned.deinit(allocator);
    }

    for (diagnostic_list) |d| {
        try owned.append(allocator, try normalizeDiagnostic(allocator, d, file_paths));
    }

    std.mem.sort(diagnostics.Diagnostic, owned.items, {}, lessByLocation);

    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    const writer = out.writer(allocator);

    if (owned.items.len == 0) {
        try writer.writeAll("<clean>\n");
        return out.toOwnedSlice(allocator);
    }

    for (owned.items) |diagnostic| {
        const display_path = normalizePathDisplay(file_paths[diagnostic.span.file_id]);
        const line = try diagnostics.formatDiagnosticLine(allocator, display_path, diagnostic);
        defer allocator.free(line);
        try writer.writeAll(line);
        try writer.writeByte('\n');

        for (diagnostic.notes) |note| {
            const note_path = normalizePathDisplay(file_paths[note.span.file_id]);
            const note_line = try std.fmt.allocPrint(
                allocator,
                "  note: {s}:{d}:{d}: {s}",
                .{ note_path, note.span.start_line, note.span.start_col, note.message },
            );
            defer allocator.free(note_line);
            try writer.writeAll(note_line);
            try writer.writeByte('\n');
        }
    }

    return out.toOwnedSlice(allocator);
}

fn runSingleFile(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    const source = try std.fs.cwd().readFileAlloc(allocator, source_path, 1024 * 1024);
    const ast_file = try translate.parseSource(allocator, 0, source);
    const ir_module = try resolver.resolve(allocator, ast_file, 0);
    var diagnostic_list = try validator_run.run(allocator, &ir_module);
    defer diagnostic_list.deinit(allocator);

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = source_path;

    return try dumpDiagnostics(allocator, paths, diagnostic_list.items);
}

fn runProject(allocator: std.mem.Allocator, root_path: []const u8) ![]const u8 {
    var scan = try scan_imports.scanProjectImports(allocator, root_path);
    defer scan.deinit(allocator);

    var merged: std.ArrayList(diagnostics.Diagnostic) = .{};
    defer merged.deinit(allocator);
    try merged.appendSlice(allocator, scan.diagnostics.items);

    var paths_for_dump: []const []const u8 = scan.file_paths;

    if (!hasHardErrors(scan.diagnostics.items)) {
        var cycle = try import_cycle.analyzeImports(allocator, scan.file_paths, scan.import_table);
        defer cycle.deinit(allocator);
        try merged.appendSlice(allocator, cycle.diagnostics.items);

        if (!hasHardErrors(cycle.diagnostics.items)) {
            var resolver_diagnostics = diagnostics.initDiagnosticList();
            defer resolver_diagnostics.deinit(allocator);
            const project = try resolve_bodies.resolveBodies(
                allocator,
                scan.file_paths,
                scan.import_table,
                cycle.topo_order,
                &resolver_diagnostics,
            );
            try merged.appendSlice(allocator, resolver_diagnostics.items);
            var val_list = try validator_run_project.run(allocator, &project);
            defer val_list.deinit(allocator);
            try merged.appendSlice(allocator, val_list.items);
            paths_for_dump = project.file_paths;
        }
    }

    return try dumpDiagnostics(allocator, paths_for_dump, merged.items);
}

const Single = struct { path: []const u8, golden: []const u8 };

const single_fixtures = [_]Single{
    .{ .path = "tests/fixtures/circuits/E001_undeclared.circ", .golden = "tests/fixtures/expected-diagnostics/E001_undeclared.txt" },
    .{ .path = "tests/fixtures/circuits/E002_unknown_port.circ", .golden = "tests/fixtures/expected-diagnostics/E002_unknown_port.txt" },
    .{ .path = "tests/fixtures/circuits/E003_multi_driver.circ", .golden = "tests/fixtures/expected-diagnostics/E003_multi_driver.txt" },
    .{ .path = "tests/fixtures/circuits/E004_unconnected_required_input.circ", .golden = "tests/fixtures/expected-diagnostics/E004_unconnected_required_input.txt" },
    .{ .path = "tests/fixtures/circuits/E005_duplicate_name.circ", .golden = "tests/fixtures/expected-diagnostics/E005_duplicate_name.txt" },
    .{ .path = "tests/fixtures/circuits/E006_shadows_builtin.circ", .golden = "tests/fixtures/expected-diagnostics/E006_shadows_builtin.txt" },
    .{ .path = "tests/fixtures/circuits/E007_unassigned_output.circ", .golden = "tests/fixtures/expected-diagnostics/E007_unassigned_output.txt" },
    .{ .path = "tests/fixtures/circuits/E008_simple_loop.circ", .golden = "tests/fixtures/expected-diagnostics/E008_simple_loop.txt" },
    .{ .path = "tests/fixtures/circuits/E014_width_mismatch.circ", .golden = "tests/fixtures/expected-diagnostics/E014_width_mismatch.txt" },
    .{ .path = "tests/fixtures/circuits/E017_memory_no_widths.circ", .golden = "tests/fixtures/expected-diagnostics/E017_memory_no_widths.txt" },
    .{ .path = "tests/fixtures/circuits/E017_memory_one_width.circ", .golden = "tests/fixtures/expected-diagnostics/E017_memory_one_width.txt" },
    .{ .path = "tests/fixtures/circuits/E017_memory_type_width.circ", .golden = "tests/fixtures/expected-diagnostics/E017_memory_type_width.txt" },
    .{ .path = "tests/fixtures/circuits/E017_memory_ident_list.circ", .golden = "tests/fixtures/expected-diagnostics/E017_memory_ident_list.txt" },
    .{ .path = "tests/fixtures/circuits/E018_memory_width_range.circ", .golden = "tests/fixtures/expected-diagnostics/E018_memory_width_range.txt" },
    .{ .path = "tests/fixtures/circuits/E002_memory_unknown_port.circ", .golden = "tests/fixtures/expected-diagnostics/E002_memory_unknown_port.txt" },
    .{ .path = "tests/fixtures/circuits/E004_memory_missing_ports.circ", .golden = "tests/fixtures/expected-diagnostics/E004_memory_missing_ports.txt" },
    .{ .path = "tests/fixtures/circuits/E014_memory_port_width.circ", .golden = "tests/fixtures/expected-diagnostics/E014_memory_port_width.txt" },
    .{ .path = "tests/fixtures/circuits/E006_shadows_memory.circ", .golden = "tests/fixtures/expected-diagnostics/E006_shadows_memory.txt" },
    .{ .path = "tests/fixtures/circuits/E008_rom_loop.circ", .golden = "tests/fixtures/expected-diagnostics/E008_rom_loop.txt" },
    .{ .path = "tests/fixtures/circuits/clean_ram_feedback.circ", .golden = "tests/fixtures/expected-diagnostics/clean_ram_feedback.txt" },
    .{ .path = "tests/fixtures/circuits/W001_unused_input.circ", .golden = "tests/fixtures/expected-diagnostics/W001_unused_input.txt" },
    .{ .path = "tests/fixtures/circuits/W002_dangling_output.circ", .golden = "tests/fixtures/expected-diagnostics/W002_dangling_output.txt" },
    .{ .path = "tests/fixtures/circuits/W003_unused_import.circ", .golden = "tests/fixtures/expected-diagnostics/W003_unused_import.txt" },
};

const Project = struct { root: []const u8, golden: []const u8 };

const project_fixtures = [_]Project{
    .{ .root = "tests/fixtures/projects/missing_import/root.circ", .golden = "tests/fixtures/expected-diagnostics/E009_missing_import.txt" },
    .{ .root = "tests/fixtures/projects/E010_import_cycle/root.circ", .golden = "tests/fixtures/expected-diagnostics/E010_import_cycle.txt" },
    .{ .root = "tests/fixtures/projects/macro_import_collision/root.circ", .golden = "tests/fixtures/expected-diagnostics/E011_macro_import_collision.txt" },
    .{ .root = "tests/fixtures/projects/E012_unknown_port/root.circ", .golden = "tests/fixtures/expected-diagnostics/E012_unknown_port.txt" },
    .{ .root = "tests/fixtures/projects/E013_missing_input/root.circ", .golden = "tests/fixtures/expected-diagnostics/E013_missing_input.txt" },
    .{ .root = "tests/fixtures/projects/E015_scalar_subcircuit_widened/root.circ", .golden = "tests/fixtures/expected-diagnostics/E015_scalar_subcircuit_widened.txt" },
    .{ .root = "tests/fixtures/projects/E016_arity_over/root.circ", .golden = "tests/fixtures/expected-diagnostics/E016_arity_over.txt" },
    .{ .root = "tests/fixtures/projects/E016_arity_under/root.circ", .golden = "tests/fixtures/expected-diagnostics/E016_arity_under.txt" },
    .{ .root = "tests/fixtures/projects/W002_dangling_subcircuit_output/root.circ", .golden = "tests/fixtures/expected-diagnostics/W002_dangling_subcircuit_output.txt" },
    .{ .root = "tests/fixtures/projects/memory_parametric/root.circ", .golden = "tests/fixtures/expected-diagnostics/memory_parametric_clean.txt" },
    .{ .root = "tests/fixtures/projects/E011_memory_alias/root.circ", .golden = "tests/fixtures/expected-diagnostics/E011_memory_alias.txt" },
};

test "Phase 9.3 diagnostic code snapshots (single-file full validator)" {
    for (single_fixtures) |fx| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const dump = try runSingleFile(allocator, fx.path);
        golden.expectGolden(dump, fx.golden) catch |err| {
            std.debug.print("Code snapshot failed: {s}\n", .{fx.path});
            return err;
        };
    }
}

test "Phase 9.3 diagnostic code snapshots (project pipeline)" {
    for (project_fixtures) |fx| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const dump = try runProject(allocator, fx.root);
        golden.expectGolden(dump, fx.golden) catch |err| {
            std.debug.print("Project code snapshot failed: {s}\n", .{fx.root});
            return err;
        };
    }
}
