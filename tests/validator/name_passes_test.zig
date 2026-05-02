const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const diagnostics = @import("diagnostics");
const name_resolution = @import("name_resolution");
const name_collision = @import("name_collision");
const golden = @import("golden");

const Fixture = struct {
    name: []const u8,
    source_path: []const u8,
    expected_path: []const u8,
};

const fixtures = [_]Fixture{
    .{
        .name = "E001 undeclared",
        .source_path = "tests/fixtures/circuits/E001_undeclared.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/E001_undeclared.txt",
    },
    .{
        .name = "E005 duplicate name",
        .source_path = "tests/fixtures/circuits/E005_duplicate_name.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/E005_duplicate_name.txt",
    },
    .{
        .name = "E006 shadows builtin",
        .source_path = "tests/fixtures/circuits/E006_shadows_builtin.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/E006_shadows_builtin.txt",
    },
    .{
        .name = "clean",
        .source_path = "tests/fixtures/circuits/and_two_inputs.circ",
        .expected_path = "tests/fixtures/expected-diagnostics/clean.txt",
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

test "name resolution and collision passes fixtures" {
    for (fixtures) |fixture| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const source = try std.fs.cwd().readFileAlloc(allocator, fixture.source_path, 1024 * 1024);
        const ast_file = try translate.parseSource(allocator, 0, source);
        const ir_module = try resolver.resolve(allocator, ast_file, 0);

        var diagnostic_list = diagnostics.initDiagnosticList();
        defer diagnostic_list.deinit(allocator);

        try name_resolution.run(allocator, &ir_module, &diagnostic_list);
        try name_collision.run(allocator, &ir_module, &diagnostic_list);

        std.mem.sort(diagnostics.Diagnostic, diagnostic_list.items, {}, lessByLocation);
        const dump = try dumpDiagnostics(allocator, fixture.source_path, diagnostic_list.items);

        golden.expectGolden(dump, fixture.expected_path) catch |err| {
            std.debug.print("Diagnostic fixture failed: {s}\n", .{fixture.name});
            return err;
        };
    }
}
