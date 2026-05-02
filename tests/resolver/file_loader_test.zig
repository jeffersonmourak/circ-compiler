const std = @import("std");
const builtins = @import("builtins");
const file_loader = @import("file_loader");

test "loadFile returns embedded source for builtin or.circ" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const loaded = try file_loader.loadFile(allocator, "<builtin>/or.circ");
    defer {
        allocator.free(loaded.absolute_path);
        allocator.free(loaded.source);
    }

    const expected = builtins.sourceForPathSuffix("or.circ").?;
    try std.testing.expectEqualStrings(expected, loaded.source);
    try std.testing.expectEqualStrings("<builtin>/or.circ", loaded.absolute_path);
}

test "loadFile missing builtin yields BuiltinNotFound" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const outcome = file_loader.loadFile(allocator, "<builtin>/nosuch.circ");
    try std.testing.expectError(error.BuiltinNotFound, outcome);
}

test "loadFile reads disk fixture when path is not builtin" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const loaded = try file_loader.loadFile(allocator, "tests/fixtures/circuits/empty_ish.circ");
    defer {
        allocator.free(loaded.absolute_path);
        allocator.free(loaded.source);
    }
    try std.testing.expect(std.mem.indexOf(u8, loaded.source, "input") != null);
}

test "resolveImportPath leaves builtin paths absolute-virtual" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const resolved = try file_loader.resolveImportPath(allocator, "/any/root.circ", "<builtin>/xor.circ");
    defer allocator.free(resolved);
    try std.testing.expectEqualStrings("<builtin>/xor.circ", resolved);
}
