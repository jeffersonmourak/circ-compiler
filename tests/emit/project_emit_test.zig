const std = @import("std");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const validator_run_project = @import("validator_run_project");
const diagnostics = @import("diagnostics");
const emit_main = @import("emit_main");
const golden = @import("golden");

const Fixture = struct {
    name: []const u8,
    root_path: []const u8,
    source_name: []const u8,
    expected_path: []const u8,
};

const fixtures = [_]Fixture{
    .{
        .name = "passthrough_chain",
        .root_path = "tests/fixtures/projects/passthrough_chain/root.circ",
        .source_name = "root.circ",
        .expected_path = "tests/fixtures/expected-zig/projects/passthrough_chain/main.zig",
    },
    .{
        .name = "and_pair",
        .root_path = "tests/fixtures/projects/and_pair/root.circ",
        .source_name = "root.circ",
        .expected_path = "tests/fixtures/expected-zig/projects/and_pair/main.zig",
    },
    .{
        .name = "nested_invert",
        .root_path = "tests/fixtures/projects/nested_invert/root.circ",
        .source_name = "root.circ",
        .expected_path = "tests/fixtures/expected-zig/projects/nested_invert/main.zig",
    },
    .{
        .name = "diamond",
        .root_path = "tests/fixtures/projects/diamond/root.circ",
        .source_name = "root.circ",
        .expected_path = "tests/fixtures/expected-zig/projects/diamond/main.zig",
    },
    .{
        .name = "deep_chain",
        .root_path = "tests/fixtures/projects/deep_chain/root.circ",
        .source_name = "root.circ",
        .expected_path = "tests/fixtures/expected-zig/projects/deep_chain/main.zig",
    },
    .{
        .name = "same_name_half_adder",
        .root_path = "tests/fixtures/projects/same_name_half_adder/root.circ",
        .source_name = "root.circ",
        .expected_path = "tests/fixtures/expected-zig/projects/same_name_half_adder/main.zig",
    },
};

fn hasHardErrors(diagnostic_list: []const diagnostics.Diagnostic) bool {
    for (diagnostic_list) |diagnostic| {
        if (diagnostic.level == .err) return true;
    }
    return false;
}

test "project emitter fixture files" {
    for (fixtures) |fixture| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const scan_result = try scan_imports.scanProjectImports(allocator, fixture.root_path);
        if (hasHardErrors(scan_result.diagnostics.items)) return error.InvalidFixtureScan;

        const cycle_result = try import_cycle.analyzeImports(allocator, scan_result.file_paths, scan_result.import_table);
        if (hasHardErrors(cycle_result.diagnostics.items)) return error.InvalidFixtureCycle;

        const project = try resolve_bodies.resolveBodies(
            allocator,
            scan_result.file_paths,
            scan_result.import_table,
            cycle_result.topo_order,
        );

        var diags = try validator_run_project.run(allocator, &project);
        defer diags.deinit(allocator);
        if (hasHardErrors(diags.items)) {
            std.debug.print("project validation failed for {s}:\n", .{fixture.name});
            for (diags.items) |d| {
                std.debug.print("  {s}\n", .{d.message});
            }
            return error.InvalidFixtureValidation;
        }

        const emitted = try emit_main.emitProjectSource(allocator, &project, .{
            .source_name = fixture.source_name,
            .compile_timestamp = "2026-05-01T22:00:00Z",
            .compiler_version = "circ-compiler/dev",
        });

        golden.expectGolden(emitted, fixture.expected_path) catch |err| {
            std.debug.print("Project emission fixture failed: {s}\n", .{fixture.name});
            return err;
        };
    }
}
