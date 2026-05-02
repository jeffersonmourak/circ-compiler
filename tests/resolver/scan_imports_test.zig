const std = @import("std");
const scan_imports = @import("scan_imports");
const diagnostics = @import("diagnostics");

fn containsPath(paths: []const []const u8, suffix: []const u8) bool {
    for (paths) |path| {
        if (std.mem.endsWith(u8, path, suffix)) return true;
    }
    return false;
}

fn countCode(items: []const diagnostics.Diagnostic, code: diagnostics.DiagnosticCode) usize {
    var count: usize = 0;
    for (items) |item| {
        if (item.code == code) count += 1;
    }
    return count;
}

test "scan imports discovers two-file project" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var result = try scan_imports.scanProjectImports(allocator, "tests/fixtures/projects/two_file/root.circ");
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.file_paths.len);
    try std.testing.expectEqual(@as(usize, 1), result.import_table.len);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
    try std.testing.expect(containsPath(result.file_paths, "/tests/fixtures/projects/two_file/root.circ"));
    try std.testing.expect(containsPath(result.file_paths, "/tests/fixtures/projects/two_file/child.circ"));
}

test "scan imports handles diamond and loads leaf once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var result = try scan_imports.scanProjectImports(allocator, "tests/fixtures/projects/diamond/root.circ");
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 4), result.file_paths.len);
    try std.testing.expectEqual(@as(usize, 4), result.import_table.len);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
    try std.testing.expect(containsPath(result.file_paths, "/tests/fixtures/projects/diamond/base.circ"));
}

test "scan imports emits E009 for missing import and continues" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var result = try scan_imports.scanProjectImports(allocator, "tests/fixtures/projects/missing_import/root.circ");
    defer result.deinit(allocator);

    try std.testing.expect(countCode(result.diagnostics.items, .E009) >= 1);
    try std.testing.expect(containsPath(result.file_paths, "/tests/fixtures/projects/missing_import/ok.circ"));
}

test "scan imports emits E011 for alias collisions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var result = try scan_imports.scanProjectImports(allocator, "tests/fixtures/projects/alias_collision/root.circ");
    defer result.deinit(allocator);

    try std.testing.expect(countCode(result.diagnostics.items, .E011) >= 2);
}
