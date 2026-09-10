//! Cross-language layout-parity goldens over the whole previewable corpus.
//!
//! For every fixture-mode `tests/preview/corpus.zig` lists, the `LayoutGrid`
//! built through the library front end is pinned as JSON under
//! `tests/fixtures/preview/layouts-json/<name>.<mode>.layout.json` — the
//! contract `circ-renderer/test/layout-parity.test.ts` compares its own
//! `buildLayout()` against (`DOCS/decisions/preview-layout.md`). Regenerate
//! with `UPDATE_GOLDENS=1 zig build test`; the run step is declared
//! `has_side_effects` in `build.zig` so a regeneration is never served from
//! the run-step cache.
const std = @import("std");
const corpus = @import("corpus");
const preview_dump_json = @import("preview_dump_json");
const invariants = @import("invariants");
const ordering = @import("ordering");
const golden = @import("golden");

test {
    _ = corpus;
}

pub const JSON_DIR = "tests/fixtures/preview/layouts-json";

fn goldenPath(arena: std.mem.Allocator, entry: corpus.Entry) ![]const u8 {
    return std.fmt.allocPrint(arena, JSON_DIR ++ "/{s}.{s}.layout.json", .{ entry.name, entry.mode.name() });
}

test "layout_conformance_corpus" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const w = try corpus.walk(a);
    for (w.entries) |entry| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const s = scratch.allocator();

        const grid = try corpus.buildGrid(s, entry.path, entry.mode == .expanded);
        var buf: std.ArrayList(u8) = .{};
        try preview_dump_json.dumpLayoutJson(buf.writer(s), grid);

        const path = try goldenPath(s, entry);
        golden.expectGolden(buf.items, path) catch |err| {
            std.debug.print("layout-conformance golden mismatch: {s} ({s}) — {s}\n", .{ entry.name, entry.mode.name(), path });
            return err;
        };
    }
}

// ---------- Corpus invariants ----------
//
// The measurement of record (`DOCS/PLANS_PROMPT.md`, decision 10): for every
// fixture-mode the walk lists, `invariants.check` over the grid — I0 wire
// cells inside a box, I1 cells two nets share colinearly, I2 cells where
// nets meet other than as a clean crossing, I3 nets that are not a tree from
// their source — plus crossings, bends, straight wires and the grid size.
// Every fixture-mode is listed, zero rows included, so the corpus itself is
// visible in the golden; the totals line closes it. Until Phase 3 the counts
// describe the old algorithm; from Phase 3 on I0–I3 are zero everywhere and
// a non-zero row is a failing test.

pub const INVARIANTS_GOLDEN = "tests/fixtures/preview/layout-invariants.golden";

fn corpusInvariantsTable(out: std.mem.Allocator) ![]const u8 {
    var list_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer list_arena.deinit();
    const w = try corpus.walk(list_arena.allocator());

    var buf: std.ArrayList(u8) = .{};
    const writer = buf.writer(out);
    try writer.writeAll("# corpus layout invariants — every previewable fixture-mode; regenerate with UPDATE_GOLDENS=1 zig build test\n");
    try writer.writeAll("# I0 body cells, I1 shared cells, I2 junctions, I3 non-tree nets, X crossings, B bends, S straight wires of W wires, C ordering crossings, size WxH\n");

    var total = invariants.Report{};
    var total_c: u64 = 0;
    for (w.entries) |entry| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const s = scratch.allocator();

        const st = try corpus.buildStages(s, entry.path, entry.mode == .expanded);
        const grid = st.grid;
        const r = try invariants.check(s, grid);
        const c = try ordering.countCrossings(s, st.graph, st.layered, st.ordering);
        total_c += c;
        try writer.print("{s} {s} I0={d} I1={d} I2={d} I3={d} X={d} B={d} S={d}/{d} C={d} size={d}x{d}\n", .{
            entry.name, entry.mode.name(), r.body, r.shared, r.junction, r.tree, r.crossings, r.bends, r.straight, r.wires, c, grid.width, grid.height,
        });
        total.body += r.body;
        total.shared += r.shared;
        total.junction += r.junction;
        total.tree += r.tree;
        total.crossings += r.crossings;
        total.bends += r.bends;
        total.straight += r.straight;
        total.wires += r.wires;
    }
    try writer.print("# totals: fixture-modes={d} skipped={d} I0={d} I1={d} I2={d} I3={d} X={d} B={d} S={d}/{d} C={d}\n", .{
        w.entries.len, w.skipped, total.body, total.shared, total.junction, total.tree, total.crossings, total.bends, total.straight, total.wires, total_c,
    });
    return buf.toOwnedSlice(out);
}

test "corpus_layout_invariants" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const table = try corpusInvariantsTable(a);
    golden.expectGolden(table, INVARIANTS_GOLDEN) catch |err| {
        std.debug.print("layout invariants moved — current table:\n{s}", .{table});
        return err;
    };
}
