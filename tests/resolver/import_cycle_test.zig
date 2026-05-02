const std = @import("std");
const diagnostics = @import("diagnostics");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");

fn mkSpan() diagnostics.Span {
    return .{
        .file_id = 0,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 1,
    };
}

fn hasCode(items: []const diagnostics.Diagnostic, code: diagnostics.DiagnosticCode) bool {
    for (items) |item| if (item.code == code) return true;
    return false;
}

test "linear chain has leaves-first topo and no cycle diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const files = [_][]const u8{ "A.circ", "B.circ", "C.circ" };
    const imports = [_]scan_imports.ResolvedImport{
        .{ .importing_file = 0, .alias = "B", .target_file = 1, .span = mkSpan() },
        .{ .importing_file = 1, .alias = "C", .target_file = 2, .span = mkSpan() },
    };

    var result = try import_cycle.analyzeImports(allocator, &files, &imports);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), result.topo_order.len);
    try std.testing.expectEqual(@as(scan_imports.FileId, 2), result.topo_order[0]);
    try std.testing.expectEqual(@as(scan_imports.FileId, 0), result.topo_order[2]);
    try std.testing.expect(!hasCode(result.diagnostics.items, .E010));
}

test "diamond has D first and A last" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const files = [_][]const u8{ "A.circ", "B.circ", "C.circ", "D.circ" };
    const imports = [_]scan_imports.ResolvedImport{
        .{ .importing_file = 0, .alias = "B", .target_file = 1, .span = mkSpan() },
        .{ .importing_file = 0, .alias = "C", .target_file = 2, .span = mkSpan() },
        .{ .importing_file = 1, .alias = "D", .target_file = 3, .span = mkSpan() },
        .{ .importing_file = 2, .alias = "D", .target_file = 3, .span = mkSpan() },
    };

    var result = try import_cycle.analyzeImports(allocator, &files, &imports);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(scan_imports.FileId, 3), result.topo_order[0]);
    try std.testing.expectEqual(@as(scan_imports.FileId, 0), result.topo_order[result.topo_order.len - 1]);
    try std.testing.expect(!hasCode(result.diagnostics.items, .E010));
}

test "self cycle emits E010" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const files = [_][]const u8{"A.circ"};
    const imports = [_]scan_imports.ResolvedImport{
        .{ .importing_file = 0, .alias = "A", .target_file = 0, .span = mkSpan() },
    };

    var result = try import_cycle.analyzeImports(allocator, &files, &imports);
    defer result.deinit(allocator);
    try std.testing.expect(hasCode(result.diagnostics.items, .E010));
}

test "indirect cycle emits E010" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const files = [_][]const u8{ "A.circ", "B.circ" };
    const imports = [_]scan_imports.ResolvedImport{
        .{ .importing_file = 0, .alias = "B", .target_file = 1, .span = mkSpan() },
        .{ .importing_file = 1, .alias = "A", .target_file = 0, .span = mkSpan() },
    };

    var result = try import_cycle.analyzeImports(allocator, &files, &imports);
    defer result.deinit(allocator);
    try std.testing.expect(hasCode(result.diagnostics.items, .E010));
}

test "three node cycle emits E010" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const files = [_][]const u8{ "A.circ", "B.circ", "C.circ" };
    const imports = [_]scan_imports.ResolvedImport{
        .{ .importing_file = 0, .alias = "B", .target_file = 1, .span = mkSpan() },
        .{ .importing_file = 1, .alias = "C", .target_file = 2, .span = mkSpan() },
        .{ .importing_file = 2, .alias = "A", .target_file = 0, .span = mkSpan() },
    };

    var result = try import_cycle.analyzeImports(allocator, &files, &imports);
    defer result.deinit(allocator);
    try std.testing.expect(hasCode(result.diagnostics.items, .E010));
}

test "multiple cycles are reported separately" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const files = [_][]const u8{ "A.circ", "B.circ", "C.circ", "D.circ" };
    const imports = [_]scan_imports.ResolvedImport{
        .{ .importing_file = 0, .alias = "B", .target_file = 1, .span = mkSpan() },
        .{ .importing_file = 1, .alias = "A", .target_file = 0, .span = mkSpan() },
        .{ .importing_file = 2, .alias = "D", .target_file = 3, .span = mkSpan() },
        .{ .importing_file = 3, .alias = "C", .target_file = 2, .span = mkSpan() },
    };

    var result = try import_cycle.analyzeImports(allocator, &files, &imports);
    defer result.deinit(allocator);

    var e010_count: usize = 0;
    for (result.diagnostics.items) |diag| {
        if (diag.code == .E010) e010_count += 1;
    }
    try std.testing.expect(e010_count >= 2);
}
