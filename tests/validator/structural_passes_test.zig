const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const diagnostics = @import("diagnostics");
const name_resolution = @import("name_resolution");
const port_validation = @import("port_validation");
const multi_driver = @import("multi_driver");
const required_input = @import("required_input");
const output_assignment = @import("output_assignment");
const memory_validation = @import("memory_validation");
const golden = @import("golden");

// Pulls the pass's inline tests into this test root.
test {
    _ = memory_validation;
}

const Fixture = struct {
    name: []const u8,
    source_path: []const u8,
    expected_path: []const u8,
};

const fixtures = [_]Fixture{
    .{
        .name = "E002 unknown port",
        .source_path = "tests/fixtures/circuits/E002_unknown_port.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/E002_unknown_port.txt",
    },
    .{
        .name = "E003 multi driver",
        .source_path = "tests/fixtures/circuits/E003_multi_driver.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/E003_multi_driver.txt",
    },
    .{
        .name = "E004 unconnected required input",
        .source_path = "tests/fixtures/circuits/E004_unconnected_required_input.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/E004_unconnected_required_input.txt",
    },
    .{
        .name = "E007 unassigned output",
        .source_path = "tests/fixtures/circuits/E007_unassigned_output.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/E007_unassigned_output.txt",
    },
    .{
        .name = "multi diagnostic",
        .source_path = "tests/fixtures/circuits/multi_diagnostic.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/multi_diagnostic.txt",
    },
};

fn lessByLocation(_: void, lhs: diagnostics.Diagnostic, rhs: diagnostics.Diagnostic) bool {
    if (lhs.span.start_line != rhs.span.start_line) return lhs.span.start_line < rhs.span.start_line;
    if (lhs.span.start_col != rhs.span.start_col) return lhs.span.start_col < rhs.span.start_col;
    return @intFromEnum(lhs.code) < @intFromEnum(rhs.code);
}

fn dumpDiagnostics(allocator: std.mem.Allocator, file_path: []const u8, diagnostic_list: []const diagnostics.Diagnostic) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    const writer = out.writer(allocator);

    if (diagnostic_list.len == 0) {
        try writer.writeAll("<clean>\n");
        return out.toOwnedSlice(allocator);
    }

    for (diagnostic_list) |diagnostic| {
        const line = try diagnostics.formatDiagnosticLine(allocator, file_path, diagnostic);
        defer allocator.free(line);
        try writer.writeAll(line);
        try writer.writeByte('\n');
        for (diagnostic.notes) |note| {
            const note_line = try std.fmt.allocPrint(
                allocator,
                "  note: {s}:{d}:{d}: {s}",
                .{ file_path, note.span.start_line, note.span.start_col, note.message },
            );
            defer allocator.free(note_line);
            try writer.writeAll(note_line);
            try writer.writeByte('\n');
        }
    }

    return out.toOwnedSlice(allocator);
}

test "structural validation passes fixtures" {
    for (fixtures) |fixture| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const source = try std.fs.cwd().readFileAlloc(allocator, fixture.source_path, 1024 * 1024);
        const ast_file = translate.parseSource(allocator, 0, source) catch |err| {
            std.debug.print("Parse failed for fixture: {s}\n", .{fixture.name});
            return err;
        };
        const ir_module = try resolver.resolve(allocator, ast_file, 0);

        var diagnostic_list = diagnostics.initDiagnosticList();
        defer diagnostic_list.deinit(allocator);

        try name_resolution.run(allocator, &ir_module, &diagnostic_list);
        try port_validation.run(allocator, &ir_module, &diagnostic_list);
        try multi_driver.run(allocator, &ir_module, &diagnostic_list);
        try required_input.run(allocator, &ir_module, &diagnostic_list);
        try output_assignment.run(allocator, &ir_module, &diagnostic_list);

        std.mem.sort(diagnostics.Diagnostic, diagnostic_list.items, {}, lessByLocation);
        const dump = try dumpDiagnostics(allocator, fixture.source_path, diagnostic_list.items);
        golden.expectGolden(dump, fixture.expected_path) catch |err| {
            std.debug.print("Structural fixture failed: {s}\n", .{fixture.name});
            return err;
        };
    }
}
