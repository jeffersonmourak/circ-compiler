//! Golden transcripts for the `--sim` protocol: each fixture's `.script`
//! (protocol lines, `#` comments allowed) is served in-process against the
//! circuit built the way `--sim` builds it, and the full stdout transcript is
//! compared byte-for-byte against `tests/fixtures/expected-sim/<name>.txt`.
//! Regenerate with `UPDATE_GOLDENS=1 zig build test`, then read every line.
//! Scripts must never `save`: the family runs from the repo root without a
//! temp dir and must not write files.
const std = @import("std");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const validator_run_project = @import("validator_run_project");
const diagnostics = @import("diagnostics");
const full_serializer = @import("full_serializer");
const sim_loop = @import("sim_loop");
const golden = @import("golden");

/// Mirrors `--mem=<name>=<path>`.
const Preload = struct { name: []const u8, path: []const u8 };

const Fixture = struct {
    name: []const u8,
    root_path: []const u8,
    preloads: []const Preload = &.{},

    fn scriptPath(self: Fixture, alloc: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(alloc, "tests/fixtures/sim/{s}.script", .{self.name});
    }

    fn goldenPath(self: Fixture, alloc: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(alloc, "tests/fixtures/expected-sim/{s}.txt", .{self.name});
    }
};

const fixtures = [_]Fixture{
    .{ .name = "sim_and_gate", .root_path = "tests/fixtures/circuits/and_gate.circ" },
    .{
        .name = "sim_rom_pc_walk",
        .root_path = "tests/fixtures/circuits/sim_rom_pc_walk.circ",
        .preloads = &.{.{ .name = "code", .path = "tests/fixtures/mem/rom_pc_walk.bin" }},
    },
    .{ .name = "sim_ram_write_read", .root_path = "tests/fixtures/circuits/sim_ram_write_read.circ" },
    .{ .name = "sim_mem_errors", .root_path = "tests/fixtures/circuits/sim_ram_write_read.circ" },
};

fn updateModeEnabled() bool {
    const env_value = std.posix.getenv("UPDATE_GOLDENS") orelse return false;
    return std.mem.eql(u8, env_value, "1");
}

fn hasHardErrors(diags: []const diagnostics.Diagnostic) bool {
    for (diags) |d| {
        if (d.level == .err) return true;
    }
    return false;
}

fn expectFileExists(path: []const u8) !void {
    std.fs.cwd().access(path, .{}) catch |err| {
        std.debug.print("missing fixture input: {s}\n", .{path});
        return err;
    };
}

fn runFixture(f: Fixture) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The project pipeline, exactly as `--sim` resolves its input.
    const scan_result = try scan_imports.scanProjectImports(alloc, f.root_path);
    if (hasHardErrors(scan_result.diagnostics.items)) return error.ScanFailed;
    const cycle_result = try import_cycle.analyzeImports(alloc, scan_result.file_paths, scan_result.import_table);
    if (hasHardErrors(cycle_result.diagnostics.items)) return error.CycleFailed;
    var resolver_diagnostics = diagnostics.initDiagnosticList();
    const project = try resolve_bodies.resolveBodies(
        alloc,
        scan_result.file_paths,
        scan_result.import_table,
        cycle_result.topo_order,
        &resolver_diagnostics,
    );
    if (hasHardErrors(resolver_diagnostics.items)) return error.UnexpectedResolverDiagnostics;
    const diags = try validator_run_project.run(alloc, &project);
    if (hasHardErrors(diags.items)) return error.ValidationFailed;

    const topology = try full_serializer.buildFromProject(alloc, &project);

    var preloads: std.ArrayList(sim_loop.Preload) = .{};
    for (f.preloads) |p| {
        try preloads.append(alloc, .{
            .name = p.name,
            .bytes = try std.fs.cwd().readFileAlloc(alloc, p.path, sim_loop.IMAGE_READ_CAP),
        });
    }

    const script = try std.fs.cwd().readFileAlloc(alloc, try f.scriptPath(alloc), 1024 * 1024);
    var fbs = std.io.fixedBufferStream(script);
    var out: std.ArrayList(u8) = .{};
    try sim_loop.serve(alloc, topology, f.root_path, diags.items, preloads.items, fbs.reader(), out.writer(alloc));

    const golden_path = try f.goldenPath(alloc);
    golden.expectGolden(out.items, golden_path) catch |err| {
        std.debug.print("sim golden {s}: {s}\n--- actual transcript ---\n{s}--- end ---\n", .{ golden_path, @errorName(err), out.items });
        return err;
    };
}

test "sim golden: fixture inputs exist" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    for (fixtures) |f| {
        try expectFileExists(try f.scriptPath(alloc));
        try expectFileExists(f.root_path);
        for (f.preloads) |p| try expectFileExists(p.path);
        // On the first UPDATE_GOLDENS=1 run the transcripts do not exist yet.
        if (!updateModeEnabled()) try expectFileExists(try f.goldenPath(alloc));
    }
}

test "sim golden: transcripts match" {
    for (fixtures) |f| {
        runFixture(f) catch |err| {
            std.debug.print("sim golden fixture '{s}' failed: {s}\n", .{ f.name, @errorName(err) });
            return err;
        };
    }
}
