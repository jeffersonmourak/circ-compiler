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

    const resolved = try file_loader.resolveImportPath(allocator, "/any/root.circ", "<builtin>/xor.circ", null);
    defer allocator.free(resolved);
    try std.testing.expectEqualStrings("<builtin>/xor.circ", resolved);
}

test "resolveImportPath overlay-only sibling returns the key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var overlay = file_loader.Overlay{};
    try overlay.put(allocator, "/virtual/dep.circ", "input x\n");

    const resolved = try file_loader.resolveImportPath(allocator, "/virtual/root.circ", "dep.circ", overlay);
    try std.testing.expectEqualStrings("/virtual/dep.circ", resolved);
}

test "resolveImportPath normalises dot segments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var overlay = file_loader.Overlay{};
    try overlay.put(allocator, "/virtual/dep.circ", "input x\n");
    try overlay.put(allocator, "/virtual/x.circ", "input x\n");

    const dotted = try file_loader.resolveImportPath(allocator, "/virtual/root.circ", "./sub/../dep.circ", overlay);
    try std.testing.expectEqualStrings("/virtual/dep.circ", dotted);
    const parent = try file_loader.resolveImportPath(allocator, "/virtual/a/root.circ", "../x.circ", overlay);
    try std.testing.expectEqualStrings("/virtual/x.circ", parent);
}

test "resolveImportPath disk sibling still realpaths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const root = "tests/fixtures/projects/two_file/root.circ";
    const resolved = try file_loader.resolveImportPath(allocator, root, "child.circ", null);
    const expected = try std.fs.cwd().realpathAlloc(allocator, "tests/fixtures/projects/two_file/child.circ");
    try std.testing.expectEqualStrings(expected, resolved);

    const missing = file_loader.resolveImportPath(allocator, root, "nosuch.circ", null);
    try std.testing.expectError(error.FileNotFound, missing);
}

test "loadFileWithOverlay hits the overlay for a never-saved key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var overlay = file_loader.Overlay{};
    try overlay.put(allocator, "/nowhere/x.circ", "input q\n");

    const loaded = try file_loader.loadFileWithOverlay(allocator, "/nowhere/x.circ", overlay);
    try std.testing.expectEqualStrings("/nowhere/x.circ", loaded.absolute_path);
    try std.testing.expectEqualStrings("input q\n", loaded.source);

    const missing = file_loader.loadFileWithOverlay(allocator, "/nowhere/y.circ", overlay);
    try std.testing.expectError(error.FileNotFound, missing);
}
