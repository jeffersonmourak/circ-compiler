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
const channels = @import("channels");
const layout_types = @import("layout_types");
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

// ---------- Determinism ----------
//
// The pipeline must be a pure function of its input: two builds of the same
// fixture-mode in fresh arenas produce byte-identical JSON. Hash-map
// iteration order, uninitialised memory and allocator-dependent tie-breaks
// are what this catches.

test "layout_determinism" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const w = try corpus.walk(a);
    for (w.entries) |entry| {
        var first: std.ArrayList(u8) = .{};
        var second: std.ArrayList(u8) = .{};
        {
            var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer scratch.deinit();
            const grid = try corpus.buildGrid(scratch.allocator(), entry.path, entry.mode == .expanded);
            try preview_dump_json.dumpLayoutJson(first.writer(a), grid);
        }
        {
            var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer scratch.deinit();
            const grid = try corpus.buildGrid(scratch.allocator(), entry.path, entry.mode == .expanded);
            try preview_dump_json.dumpLayoutJson(second.writer(a), grid);
        }
        if (!std.mem.eql(u8, first.items, second.items)) {
            std.debug.print("layout is not deterministic: {s} ({s})\n", .{ entry.name, entry.mode.name() });
            return error.NonDeterministicLayout;
        }
    }
}

// ---------- Channel planning over the corpus ----------
//
// The plan every fixture-mode was routed with: how many spacer rows it
// needed, how many return lanes, how many nets fell back, and the widest
// gap. Fallbacks are the number to watch — zero means every net found a
// track or a dogleg.

test "channels_corpus_plan" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const w = try corpus.walk(a);
    var spacers: usize = 0;
    var lanes: usize = 0;
    var fallbacks: usize = 0;
    var widest: u32 = 0;
    var widest_name: []const u8 = "";
    var doglegs: usize = 0;
    var multi_driven_modes: usize = 0;
    for (w.entries) |entry| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const s = scratch.allocator();
        const st = try corpus.buildStages(s, entry.path, entry.mode == .expanded);
        spacers += st.plan.spacer_rows.len;
        lanes += st.plan.return_rows;
        fallbacks += st.plan.fallbacks;
        for (st.plan.gaps) |g| {
            if (g.tracks > widest) {
                widest = g.tracks;
                widest_name = try a.dupe(u8, entry.name);
            }
            for (g.nets) |net| doglegs += net.jogs.len;
        }
        const md = try multiDrivenPorts(s, st.layered);
        if (md > 0) {
            multi_driven_modes += 1;
            std.debug.print("multi-driven ports: {s} {s} ({d})\n", .{ entry.name, entry.mode.name(), md });
        }
    }
    std.debug.print("channels corpus: spacers={d} return_lanes={d} doglegs={d} fallbacks={d} widest={d} tracks ({s}) multi_driven_modes={d}\n", .{ spacers, lanes, doglegs, fallbacks, widest, widest_name, multi_driven_modes });
}

/// Sink ports that more than one net drives. The collapse stage maps every
/// macro input port whose name is not `a`, `in` or `b` onto `in`, so a
/// parametric macro with two such inputs receives two nets on one port
/// cell — a topology-level fan-in no router can draw without the two
/// wires sharing that cell (`DOCS/decisions/preview-layout.md`).
fn multiDrivenPorts(arena: std.mem.Allocator, layered: layout_types.LayeredGraph) !usize {
    const Key = struct { dst: usize, port: u8 };
    var drivers = std.AutoHashMap(Key, std.AutoHashMap(u64, void)).init(arena);
    for (layered.originals) |o| {
        const entry = try drivers.getOrPut(.{ .dst = o.dst, .port = o.dst_port });
        if (!entry.found_existing) entry.value_ptr.* = std.AutoHashMap(u64, void).init(arena);
        try entry.value_ptr.put((@as(u64, @intCast(o.src)) << 8) | o.src_port, {});
    }
    var n: usize = 0;
    var it = drivers.valueIterator();
    while (it.next()) |set| {
        if (set.count() > 1) n += 1;
    }
    return n;
}
