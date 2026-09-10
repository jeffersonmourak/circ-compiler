//! The previewable fixture corpus, built the way `circ-compile --preview`
//! and the site's `circ_preview` build it: the library front end on the
//! `.project` route, then `modes.buildTopology` and `modes.buildLayout`.
//!
//! `walk` enumerates every `tests/fixtures/circuits/*.circ` and every
//! `tests/fixtures/projects/<dir>/root.circ`, sorted by path, keeps the ones
//! that lay out with no hard error, and lists them in opaque mode always and
//! in expanded mode only when the opaque grid contains a subcircuit box (a
//! macro-free fixture lays out identically in both modes, so the second
//! entry would only duplicate the first). Fixtures that fail on the
//! `.project` route — the `E0xx_*` and `recovery_*` negatives, roots whose
//! imports are absent — are skipped and counted, never listed.
const std = @import("std");
const libcirc = @import("libcirc");
const layout = @import("layout");
const orchestrator = @import("orchestrator");

pub const Mode = enum {
    collapsed,
    expanded,

    pub fn name(self: Mode) []const u8 {
        return switch (self) {
            .collapsed => "opaque",
            .expanded => "expanded",
        };
    }
};

pub const Entry = struct {
    /// The file stem for a circuit; `project-<dir>` for a project root (two
    /// project directories, `half_adder` and `W003_unused_import`, share a
    /// stem with a circuit fixture).
    name: []const u8,
    path: []const u8,
    mode: Mode,
};

pub const Walk = struct {
    entries: []const Entry,
    skipped: u32,
};

/// The grid exactly as the CLI and the site build it. Everything lives in
/// the caller's arena.
pub fn buildGrid(arena: std.mem.Allocator, path: []const u8, expand_macros: bool) !layout.LayoutGrid {
    var failure: libcirc.frontend.Failure = undefined;
    const front = try libcirc.frontend.run(arena, path, &.{}, .project, &failure);
    if (front.hasErrors()) return error.UnexpectedDiagnostics;
    const topology = try libcirc.modes.buildTopology(arena, &front, &failure);
    return libcirc.modes.buildLayout(arena, topology, .{ .expand_macros = expand_macros }, &failure);
}

/// Every stage's output for the same build (the tests that measure a
/// stage read this; `buildGrid` is the same pipeline without the extras).
pub fn buildStages(arena: std.mem.Allocator, path: []const u8, expand_macros: bool) !orchestrator.Stages {
    var failure: libcirc.frontend.Failure = undefined;
    const front = try libcirc.frontend.run(arena, path, &.{}, .project, &failure);
    if (front.hasErrors()) return error.UnexpectedDiagnostics;
    const topology = try libcirc.modes.buildTopology(arena, &front, &failure);
    return orchestrator.buildStages(arena, topology, .{ .expand_macros = expand_macros });
}

fn hasSubcircuit(grid: layout.LayoutGrid) bool {
    for (grid.components) |c| {
        if (c.kind == .subcircuit) return true;
    }
    return false;
}

const Candidate = struct { name: []const u8, path: []const u8 };

fn lessByPath(_: void, a: Candidate, b: Candidate) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

fn collectCandidates(arena: std.mem.Allocator) ![]Candidate {
    var list: std.ArrayList(Candidate) = .{};

    var circuits = try std.fs.cwd().openDir("tests/fixtures/circuits", .{ .iterate = true });
    defer circuits.close();
    var it = circuits.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".circ")) continue;
        const stem = try arena.dupe(u8, entry.name[0 .. entry.name.len - ".circ".len]);
        try list.append(arena, .{
            .name = stem,
            .path = try std.fmt.allocPrint(arena, "tests/fixtures/circuits/{s}", .{entry.name}),
        });
    }

    var projects = try std.fs.cwd().openDir("tests/fixtures/projects", .{ .iterate = true });
    defer projects.close();
    var pit = projects.iterate();
    while (try pit.next()) |entry| {
        if (entry.kind != .directory) continue;
        const root = try std.fmt.allocPrint(arena, "tests/fixtures/projects/{s}/root.circ", .{entry.name});
        std.fs.cwd().access(root, .{}) catch continue;
        try list.append(arena, .{ .name = try std.fmt.allocPrint(arena, "project-{s}", .{entry.name}), .path = root });
    }

    std.mem.sort(Candidate, list.items, {}, lessByPath);
    return list.toOwnedSlice(arena);
}

/// Every previewable fixture-mode, sorted by (path, mode). Each candidate is
/// laid out in a scratch arena of its own so the walk's memory stays flat.
pub fn walk(arena: std.mem.Allocator) !Walk {
    const candidates = try collectCandidates(arena);
    var entries: std.ArrayList(Entry) = .{};
    var skipped: u32 = 0;
    var seen = std.StringHashMap(void).init(arena);

    for (candidates) |c| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const s = scratch.allocator();

        const opaque_grid = buildGrid(s, c.path, false) catch {
            skipped += 1;
            continue;
        };
        if (seen.contains(c.name)) return error.DuplicateCorpusName;
        try seen.put(c.name, {});
        try entries.append(arena, .{ .name = c.name, .path = c.path, .mode = .collapsed });

        if (hasSubcircuit(opaque_grid)) {
            _ = buildGrid(s, c.path, true) catch {
                skipped += 1;
                continue;
            };
            try entries.append(arena, .{ .name = c.name, .path = c.path, .mode = .expanded });
        }
    }

    return .{ .entries = try entries.toOwnedSlice(arena), .skipped = skipped };
}

// ---------- Tests ----------

test "corpus: the walk is sorted, unique and non-empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const w = try walk(a);
    try std.testing.expect(w.entries.len > 0);

    var saw_and_of_not_opaque = false;
    var saw_and_of_not_expanded = false;
    var saw_xor_opaque = false;
    var saw_xor_expanded = false;
    for (w.entries, 0..) |e, i| {
        if (i > 0) {
            const prev = w.entries[i - 1];
            const by_path = std.mem.order(u8, prev.path, e.path);
            try std.testing.expect(by_path != .gt);
            if (by_path == .eq) {
                // Same fixture: opaque precedes expanded, and there are only two.
                try std.testing.expectEqual(Mode.collapsed, prev.mode);
                try std.testing.expectEqual(Mode.expanded, e.mode);
            }
        }
        try std.testing.expect(!std.mem.startsWith(u8, e.name, "E001"));
        if (std.mem.eql(u8, e.name, "and_of_not")) {
            if (e.mode == .collapsed) saw_and_of_not_opaque = true else saw_and_of_not_expanded = true;
        }
        if (std.mem.eql(u8, e.name, "builtin_xor")) {
            if (e.mode == .collapsed) saw_xor_opaque = true else saw_xor_expanded = true;
        }
    }
    try std.testing.expect(saw_and_of_not_opaque);
    try std.testing.expect(!saw_and_of_not_expanded);
    try std.testing.expect(saw_xor_opaque);
    try std.testing.expect(saw_xor_expanded);
}
