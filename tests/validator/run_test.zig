const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const diagnostics = @import("diagnostics");
const validator_run = @import("validator_run");
const golden = @import("golden");

const Fixture = struct {
    name: []const u8,
    source_path: []const u8,
    expected_path: []const u8,
};

const fixtures = [_]Fixture{
    .{
        .name = "W001 unused input",
        .source_path = "tests/fixtures/circuits/W001_unused_input.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/W001_unused_input.txt",
    },
    .{
        .name = "W002 dangling output reserved",
        .source_path = "tests/fixtures/circuits/W002_dangling_output.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/W002_dangling_output.txt",
    },
    .{
        .name = "clean warnings",
        .source_path = "tests/fixtures/circuits/clean_warning.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/clean_warning.txt",
    },
    .{
        .name = "errors and warnings",
        .source_path = "tests/fixtures/circuits/errors_and_warnings.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/errors_and_warnings.txt",
    },
    .{
        .name = "W003 unused import",
        .source_path = "tests/fixtures/circuits/W003_unused_import.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/W003_unused_import.txt",
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

test "validator run fixtures" {
    for (fixtures) |fixture| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const source = try std.fs.cwd().readFileAlloc(allocator, fixture.source_path, 1024 * 1024);
        const ast_file = try translate.parseSource(allocator, 0, source);
        const ir_module = try resolver.resolve(allocator, ast_file, 0);

        var diagnostic_list = try validator_run.run(allocator, &ir_module);
        defer diagnostic_list.deinit(allocator);

        std.mem.sort(diagnostics.Diagnostic, diagnostic_list.items, {}, lessByLocation);
        const dump = try dumpDiagnostics(allocator, fixture.source_path, diagnostic_list.items);
        golden.expectGolden(dump, fixture.expected_path) catch |err| {
            std.debug.print("Validator run fixture failed: {s}\n", .{fixture.name});
            return err;
        };
    }
}
