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
