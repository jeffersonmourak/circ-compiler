// Engine benchmark runner. Walks the truth-table fixture corpus, drives the
// simulation engine over every input vector for each circuit, and emits a
// markdown report of deterministic counters (events popped/committed,
// recalcs, peak queue depth, settling time) at
// tests/fixtures/bench/engine.bench.golden.
//
// Counters come from `engine.Circuit.metrics`, which only exists when the
// engine module is compiled with `collect_metrics=true` — wired by the
// `zig build bench` step's parallel module chain. The same circuit source
// compiled with `collect_metrics=false` (everywhere else) has no metrics
// field at all and the counter bumps are dead code stripped.
//
// Wall-clock timings are printed to stderr per fixture but never written to
// the golden — they're noisy by nature and the goal is a stable regression
// gate. The golden only contains counters that depend on the algorithm, not
// the host.

const std = @import("std");

// Silence the engine's info-level log calls inside propagate(). They're
// useful when debugging a single circuit but here we drive 46 of them and
// would drown the per-fixture wall-clock lines.
pub const std_options: std.Options = .{
    .log_level = .warn,
};

const translate = @import("translate");
const resolver = @import("resolver");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const validator_run_project = @import("validator_run_project");
const ir_types = @import("ir_types");
const full_serializer = @import("full_serializer");
const truth_table_builder = @import("truth_table_builder");
const engine = @import("circuit");

const Fixture = struct {
    name: []const u8,
    circ: []const u8,
};

/// Hand-maintained mapping from golden display name to its source `.circ`.
/// Most entries are 1:1 with the file stem; a few historical renames
/// (primitive_* → various, full_adder → full_adder_from_builtins) live here
/// rather than in golden filenames so the goldens themselves can stay
/// human-readable.
const fixtures = [_]Fixture{
    .{ .name = "alu_4bit", .circ = "tests/fixtures/circuits/alu_4bit.circ" },
    .{ .name = "and_2bit", .circ = "tests/fixtures/circuits/and_2bit.circ" },
    .{ .name = "and_3bit", .circ = "tests/fixtures/circuits/and_3bit.circ" },
    .{ .name = "and_4bit", .circ = "tests/fixtures/circuits/and_4bit.circ" },
    .{ .name = "and_two_inputs", .circ = "tests/fixtures/circuits/and_two_inputs.circ" },
    .{ .name = "builtin_nand", .circ = "tests/fixtures/circuits/builtin_nand.circ" },
    .{ .name = "builtin_nor", .circ = "tests/fixtures/circuits/builtin_nor.circ" },
    .{ .name = "builtin_or", .circ = "tests/fixtures/circuits/builtin_or.circ" },
    .{ .name = "builtin_xnor", .circ = "tests/fixtures/circuits/builtin_xnor.circ" },
    .{ .name = "builtin_xor", .circ = "tests/fixtures/circuits/builtin_xor.circ" },
    .{ .name = "chain", .circ = "tests/fixtures/circuits/chain.circ" },
    .{ .name = "demux_1to2", .circ = "tests/fixtures/circuits/demux_1to2.circ" },
    .{ .name = "demux_2bit_1to2", .circ = "tests/fixtures/circuits/demux_2bit_1to2.circ" },
    .{ .name = "demux_3bit_1to2", .circ = "tests/fixtures/circuits/demux_3bit_1to2.circ" },
    .{ .name = "demux_4bit_1to2", .circ = "tests/fixtures/circuits/demux_4bit_1to2.circ" },
    .{ .name = "four_bit_adder", .circ = "tests/fixtures/circuits/four_bit_adder.circ" },
    .{ .name = "full_adder", .circ = "tests/fixtures/circuits/full_adder_from_builtins.circ" },
    .{ .name = "half_adder", .circ = "tests/fixtures/circuits/half_adder.circ" },
    .{ .name = "mux_2bit_2to1", .circ = "tests/fixtures/circuits/mux_2bit_2to1.circ" },
    .{ .name = "mux_2to1", .circ = "tests/fixtures/circuits/mux_2to1.circ" },
    .{ .name = "mux_3bit_2to1", .circ = "tests/fixtures/circuits/mux_3bit_2to1.circ" },
    .{ .name = "mux_4bit_2to1", .circ = "tests/fixtures/circuits/mux_4bit_2to1.circ" },
    .{ .name = "nand_2bit", .circ = "tests/fixtures/circuits/nand_2bit.circ" },
    .{ .name = "nand_3bit", .circ = "tests/fixtures/circuits/nand_3bit.circ" },
    .{ .name = "nand_4bit", .circ = "tests/fixtures/circuits/nand_4bit.circ" },
    .{ .name = "nor_2bit", .circ = "tests/fixtures/circuits/nor_2bit.circ" },
    .{ .name = "nor_3bit", .circ = "tests/fixtures/circuits/nor_3bit.circ" },
    .{ .name = "nor_4bit", .circ = "tests/fixtures/circuits/nor_4bit.circ" },
    .{ .name = "not_2bit", .circ = "tests/fixtures/circuits/not_2bit.circ" },
    .{ .name = "not_3bit", .circ = "tests/fixtures/circuits/not_3bit.circ" },
    .{ .name = "not_4bit", .circ = "tests/fixtures/circuits/not_4bit.circ" },
    .{ .name = "or_2bit", .circ = "tests/fixtures/circuits/or_2bit.circ" },
    .{ .name = "or_3bit", .circ = "tests/fixtures/circuits/or_3bit.circ" },
    .{ .name = "or_4bit", .circ = "tests/fixtures/circuits/or_4bit.circ" },
    .{ .name = "primitive_and", .circ = "tests/fixtures/circuits/and_gate.circ" },
    .{ .name = "primitive_led", .circ = "tests/fixtures/circuits/edge_single_component.circ" },
    .{ .name = "primitive_not", .circ = "tests/fixtures/circuits/single_gate.circ" },
    .{ .name = "primitive_wire", .circ = "tests/fixtures/circuits/wire_passthrough.circ" },
    .{ .name = "three_bit_adder", .circ = "tests/fixtures/circuits/three_bit_adder.circ" },
    .{ .name = "two_bit_adder", .circ = "tests/fixtures/circuits/two_bit_adder.circ" },
    .{ .name = "xnor_2bit", .circ = "tests/fixtures/circuits/xnor_2bit.circ" },
    .{ .name = "xnor_3bit", .circ = "tests/fixtures/circuits/xnor_3bit.circ" },
    .{ .name = "xnor_4bit", .circ = "tests/fixtures/circuits/xnor_4bit.circ" },
    .{ .name = "xor_2bit", .circ = "tests/fixtures/circuits/xor_2bit.circ" },
    .{ .name = "xor_3bit", .circ = "tests/fixtures/circuits/xor_3bit.circ" },
    .{ .name = "xor_4bit", .circ = "tests/fixtures/circuits/xor_4bit.circ" },
};

const GOLDEN_PATH = "tests/fixtures/bench/engine.bench.golden";

const TimeUnit = enum {
    s,
    ms,
    ns,

    fn parse(s: []const u8) ?TimeUnit {
        if (std.mem.eql(u8, s, "s")) return .s;
        if (std.mem.eql(u8, s, "ms")) return .ms;
        if (std.mem.eql(u8, s, "ns")) return .ns;
        return null;
    }

    fn label(self: TimeUnit) []const u8 {
        return switch (self) {
            .s => "s",
            .ms => "ms",
            .ns => "ns",
        };
    }
};

const ReportMode = union(enum) {
    default,
    human: TimeUnit,
};

/// Column to sort the per-fixture stderr report by. Sorting only affects the
/// stderr output; the golden file is always written in fixture-manifest
/// (alphabetical) order so diffs stay reviewable.
const SortKey = enum {
    inputs,
    comps,
    events,
    time,

    fn parse(s: []const u8) ?SortKey {
        if (std.mem.eql(u8, s, "inputs")) return .inputs;
        if (std.mem.eql(u8, s, "comps")) return .comps;
        if (std.mem.eql(u8, s, "events")) return .events;
        if (std.mem.eql(u8, s, "time")) return .time;
        return null;
    }
};

const SortedRow = struct {
    row: Row,
    elapsed_ns: u64,

    fn extract(self: SortedRow, key: SortKey) u64 {
        return switch (key) {
            .inputs => self.row.vectors,
            .comps => self.row.components,
            .events => self.row.metrics.events_popped,
            .time => self.elapsed_ns,
        };
    }
};

fn sortDesc(key: SortKey, lhs: SortedRow, rhs: SortedRow) bool {
    return lhs.extract(key) > rhs.extract(key);
}

/// Format a labeled count with a thousands/millions suffix when worth it.
/// 0..999 → "4 vecs"; 1_000..999_999 → "16.38k vecs (16384)"; 1_000_000+ →
/// "1.85M events (1850000)". The label is inlined between the humanized
/// magnitude and the raw value.
/// Returns a slice into `buf`. Pass a buf of at least 64 bytes.
fn formatCount(buf: []u8, n: u64, label: []const u8) ![]const u8 {
    if (n < 1000) return std.fmt.bufPrint(buf, "{d} {s}", .{ n, label });
    if (n < 1_000_000) {
        const k = @as(f64, @floatFromInt(n)) / 1000.0;
        return std.fmt.bufPrint(buf, "{d:.2}k {s} ({d})", .{ k, label, n });
    }
    const m = @as(f64, @floatFromInt(n)) / 1_000_000.0;
    return std.fmt.bufPrint(buf, "{d:.2}M {s} ({d})", .{ m, label, n });
}

/// Format an elapsed-nanosecond duration in the user-chosen unit. The
/// `unit` parameter fixes the denomination across all rows so columns line
/// up. Decimal precision adapts so sub-unit times stay readable.
fn formatTimeIn(buf: []u8, elapsed_ns: u64, unit: TimeUnit) ![]const u8 {
    const ns_f = @as(f64, @floatFromInt(elapsed_ns));
    return switch (unit) {
        .s => blk: {
            const v = ns_f / std.time.ns_per_s;
            if (v >= 1.0) break :blk std.fmt.bufPrint(buf, "{d:.3} s", .{v});
            // sub-second: bump precision so "0.0014 s" reads instead of "0.001 s"
            break :blk std.fmt.bufPrint(buf, "{d:.4} s", .{v});
        },
        .ms => std.fmt.bufPrint(buf, "{d:.3} ms", .{ns_f / std.time.ns_per_ms}),
        .ns => std.fmt.bufPrint(buf, "{d} ns", .{elapsed_ns}),
    };
}

/// Format a per-second rate as items/<unit>. Applies k/M suffixes when the
/// resulting magnitude exceeds 1000; falls back to scientific notation for
/// values too small to read at fixed precision (typically <1 with .ns).
fn formatRateIn(buf: []u8, per_sec: f64, item_label: []const u8, unit: TimeUnit) ![]const u8 {
    const value = switch (unit) {
        .s => per_sec,
        .ms => per_sec / 1000.0,
        .ns => per_sec / 1e9,
    };
    const u = unit.label();

    if (value >= 1_000_000.0) {
        return std.fmt.bufPrint(buf, "{d:.2}M {s}/{s}", .{ value / 1_000_000.0, item_label, u });
    }
    if (value >= 1000.0) {
        return std.fmt.bufPrint(buf, "{d:.2}k {s}/{s}", .{ value / 1000.0, item_label, u });
    }
    if (value >= 1.0) {
        return std.fmt.bufPrint(buf, "{d:.2} {s}/{s}", .{ value, item_label, u });
    }
    if (value >= 0.01) {
        return std.fmt.bufPrint(buf, "{d:.4} {s}/{s}", .{ value, item_label, u });
    }
    // very small (mostly hits when --human ns is chosen): use scientific
    // so the number stays compact instead of "0.0000073 vec/ns"
    return std.fmt.bufPrint(buf, "{e:.2} {s}/{s}", .{ value, item_label, u });
}

const Row = struct {
    name: []const u8,
    vectors: u64,
    components: u64,
    metrics: engine.Metrics,
};

const Column = struct {
    header: []const u8,
    width: usize,
    /// true = right-align numeric, false = left-align text.
    numeric: bool,
};

const columns = [_]Column{
    .{ .header = "circuit", .width = 24, .numeric = false },
    .{ .header = "vectors", .width = 7, .numeric = true },
    .{ .header = "components", .width = 10, .numeric = true },
    .{ .header = "events_popped", .width = 13, .numeric = true },
    .{ .header = "events_committed", .width = 16, .numeric = true },
    .{ .header = "recalcs", .width = 7, .numeric = true },
    .{ .header = "peak_queue", .width = 10, .numeric = true },
    .{ .header = "final_time", .width = 10, .numeric = true },
};

fn updateMode() bool {
    const env = std.posix.getenv("UPDATE_GOLDENS") orelse return false;
    return std.mem.eql(u8, env, "1");
}

fn writeHeader(out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try out.append(allocator, '|');
    for (columns) |col| {
        try out.append(allocator, ' ');
        try out.appendSlice(allocator, col.header);
        const pad = col.width - col.header.len;
        try out.appendNTimes(allocator, ' ', pad);
        try out.appendSlice(allocator, " |");
    }
    try out.append(allocator, '\n');
    try out.append(allocator, '|');
    for (columns) |col| {
        try out.append(allocator, '-');
        try out.appendNTimes(allocator, '-', col.width);
        try out.appendSlice(allocator, "-|");
    }
    try out.append(allocator, '\n');
}

fn writeCell(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    text: []const u8,
    col: Column,
) !void {
    try out.append(allocator, ' ');
    if (col.numeric) {
        // right-align
        if (text.len < col.width) try out.appendNTimes(allocator, ' ', col.width - text.len);
        try out.appendSlice(allocator, text);
    } else {
        try out.appendSlice(allocator, text);
        if (text.len < col.width) try out.appendNTimes(allocator, ' ', col.width - text.len);
    }
    try out.appendSlice(allocator, " |");
}

fn writeRow(out: *std.ArrayList(u8), allocator: std.mem.Allocator, row: Row) !void {
    try out.append(allocator, '|');

    var buf: [32]u8 = undefined;

    try writeCell(out, allocator, row.name, columns[0]);

    var s = try std.fmt.bufPrint(&buf, "{d}", .{row.vectors});
    try writeCell(out, allocator, s, columns[1]);

    s = try std.fmt.bufPrint(&buf, "{d}", .{row.components});
    try writeCell(out, allocator, s, columns[2]);

    s = try std.fmt.bufPrint(&buf, "{d}", .{row.metrics.events_popped});
    try writeCell(out, allocator, s, columns[3]);

    s = try std.fmt.bufPrint(&buf, "{d}", .{row.metrics.events_committed});
    try writeCell(out, allocator, s, columns[4]);

    s = try std.fmt.bufPrint(&buf, "{d}", .{row.metrics.recalcs});
    try writeCell(out, allocator, s, columns[5]);

    s = try std.fmt.bufPrint(&buf, "{d}", .{row.metrics.peak_queue});
    try writeCell(out, allocator, s, columns[6]);

    s = try std.fmt.bufPrint(&buf, "{d}", .{row.metrics.final_time});
    try writeCell(out, allocator, s, columns[7]);

    try out.append(allocator, '\n');
}

fn runFixture(
    allocator: std.mem.Allocator,
    fixture: Fixture,
) !Row {
    const scan_result = try scan_imports.scanProjectImports(allocator, fixture.circ);
    if (scan_result.diagnostics.items.len > 0) {
        for (scan_result.diagnostics.items) |d| {
            if (d.level == .err) return error.ScanFailed;
        }
    }

    const cycle_result = try import_cycle.analyzeImports(
        allocator,
        scan_result.file_paths,
        scan_result.import_table,
    );
    if (cycle_result.diagnostics.items.len > 0) {
        for (cycle_result.diagnostics.items) |d| {
            if (d.level == .err) return error.CycleAnalysisFailed;
        }
    }

    const project = try resolve_bodies.resolveBodies(
        allocator,
        scan_result.file_paths,
        scan_result.import_table,
        cycle_result.topo_order,
    );

    var validator_diagnostics = try validator_run_project.run(allocator, &project);
    defer validator_diagnostics.deinit(allocator);
    for (validator_diagnostics.items) |d| {
        if (d.level == .err) return error.ValidationFailed;
    }

    var topology = try full_serializer.buildFromProject(allocator, &project);
    defer topology.deinit(allocator);

    const component_count = topology.components.len;

    var table = try truth_table_builder.build(allocator, topology, .{});
    defer table.deinit();

    return .{
        .name = fixture.name,
        .vectors = table.rows.len,
        .components = component_count,
        .metrics = table.metrics,
    };
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stderr_buf: [4096]u8 = undefined;
    var stderr_state = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_state.interface;
    defer stderr.flush() catch {};

    if (!engine.COLLECT_METRICS) {
        try stderr.writeAll("bench: build_options.collect_metrics is false, refusing to run\n");
        return error.MetricsDisabled;
    }

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);
    var mode: ReportMode = .default;
    var sort_key: ?SortKey = null;
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (std.mem.eql(u8, arg, "--human")) {
            // Optional positional unit immediately after the flag. If the
            // next token is one of s/ms/ns, consume it; otherwise default
            // to ns (matches the existing default mode's `ns/vec`).
            if (i + 1 < argv.len) {
                if (TimeUnit.parse(argv[i + 1])) |u| {
                    mode = .{ .human = u };
                    i += 1;
                    continue;
                }
            }
            mode = .{ .human = .ns };
        } else if (std.mem.eql(u8, arg, "--sort")) {
            if (i + 1 >= argv.len) {
                try stderr.writeAll("bench: --sort requires a column name\n");
                try stderr.writeAll("usage: bench [--human [s|ms|ns]] [--sort inputs|comps|events|time]\n");
                return error.MissingArg;
            }
            sort_key = SortKey.parse(argv[i + 1]) orelse {
                try stderr.print("bench: invalid --sort column: {s}\n", .{argv[i + 1]});
                try stderr.writeAll("valid columns: inputs, comps, events, time\n");
                return error.InvalidArg;
            };
            i += 1;
        } else {
            try stderr.print("bench: unknown flag: {s}\n", .{arg});
            try stderr.writeAll("usage: bench [--human [s|ms|ns]] [--sort inputs|comps|events|time]\n");
            return error.UnknownFlag;
        }
    }

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    try writeHeader(&output, allocator);

    var total_wall_ns: u64 = 0;
    var total_events: u64 = 0;
    var total_vectors: u64 = 0;

    // Collect all rows first so we can optionally sort the stderr report
    // without disturbing golden order. Golden output is appended inside the
    // loop, in fixture-manifest order, so it stays diff-stable.
    var sorted_rows: std.ArrayList(SortedRow) = .{};
    defer sorted_rows.deinit(allocator);
    try sorted_rows.ensureTotalCapacity(allocator, fixtures.len);

    for (fixtures) |fixture| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const start = std.time.nanoTimestamp();
        const row = runFixture(arena.allocator(), fixture) catch |err| {
            try stderr.print("bench: {s} FAILED: {s}\n", .{ fixture.name, @errorName(err) });
            return err;
        };
        const elapsed_ns: u64 = @intCast(std.time.nanoTimestamp() - start);
        total_wall_ns += elapsed_ns;
        total_events += row.metrics.events_popped;
        total_vectors += row.vectors;

        try writeRow(&output, allocator, row);
        sorted_rows.appendAssumeCapacity(.{ .row = row, .elapsed_ns = elapsed_ns });
    }

    if (sort_key) |key| {
        std.mem.sort(SortedRow, sorted_rows.items, key, sortDesc);
    }

    for (sorted_rows.items) |entry| {
        const row = entry.row;
        const elapsed_ns = entry.elapsed_ns;
        const elapsed_ns_f = @as(f64, @floatFromInt(elapsed_ns));
        const elapsed_s = elapsed_ns_f / std.time.ns_per_s;
        const vecs_per_sec = if (elapsed_s > 0)
            @as(f64, @floatFromInt(row.vectors)) / elapsed_s
        else
            0.0;
        const events_per_sec = if (elapsed_s > 0)
            @as(f64, @floatFromInt(row.metrics.events_popped)) / elapsed_s
        else
            0.0;

        switch (mode) {
            .default => {
                const elapsed_ms = elapsed_ns_f / std.time.ns_per_ms;
                const ns_per_vec = if (row.vectors > 0)
                    elapsed_ns_f / @as(f64, @floatFromInt(row.vectors))
                else
                    0.0;
                const ns_per_event = if (row.metrics.events_popped > 0)
                    elapsed_ns_f / @as(f64, @floatFromInt(row.metrics.events_popped))
                else
                    0.0;
                try stderr.print(
                    "bench: {s: <24} {d: >6} vecs  {d: >9.3} ms  {d: >10.1} ns/vec  {d: >6.1} ns/event\n",
                    .{ row.name, row.vectors, elapsed_ms, ns_per_vec, ns_per_event },
                );
            },
            .human => |unit| {
                var count_buf: [64]u8 = undefined;
                var time_buf: [48]u8 = undefined;
                var vec_rate_buf: [48]u8 = undefined;
                var event_rate_buf: [48]u8 = undefined;
                const count_s = try formatCount(&count_buf, row.vectors, "vecs");
                const time_s = try formatTimeIn(&time_buf, elapsed_ns, unit);
                const vec_rate_s = try formatRateIn(&vec_rate_buf, vecs_per_sec, "vec", unit);
                const event_rate_s = try formatRateIn(&event_rate_buf, events_per_sec, "events", unit);
                try stderr.print(
                    "[bench] {s: <24} {s: <24}   {s: >14}   {s: >18}   {s: >22}\n",
                    .{ row.name, count_s, time_s, vec_rate_s, event_rate_s },
                );
            },
        }
    }

    switch (mode) {
        .default => {
            const total_ms = @as(f64, @floatFromInt(total_wall_ns)) / std.time.ns_per_ms;
            try stderr.print(
                "bench: ---  {d} fixtures  {d} vectors  {d} events  {d:.3} ms total\n",
                .{ fixtures.len, total_vectors, total_events, total_ms },
            );
        },
        .human => |unit| {
            var vec_buf: [64]u8 = undefined;
            var ev_buf: [64]u8 = undefined;
            var time_buf: [48]u8 = undefined;
            const vec_s = try formatCount(&vec_buf, total_vectors, "vectors");
            const ev_s = try formatCount(&ev_buf, total_events, "events");
            const time_s = try formatTimeIn(&time_buf, total_wall_ns, unit);
            try stderr.print(
                "[bench] ---  {d} fixtures   {s}   {s}   {s} total\n",
                .{ fixtures.len, vec_s, ev_s, time_s },
            );
        },
    }

    if (updateMode()) {
        if (std.fs.path.dirname(GOLDEN_PATH)) |parent| try std.fs.cwd().makePath(parent);
        try std.fs.cwd().writeFile(.{ .sub_path = GOLDEN_PATH, .data = output.items });
        try stderr.print("bench: wrote {s}\n", .{GOLDEN_PATH});
        return;
    }

    const expected = std.fs.cwd().readFileAlloc(allocator, GOLDEN_PATH, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.print(
                "bench: golden missing at {s}. Run with UPDATE_GOLDENS=1 to create it.\n",
                .{GOLDEN_PATH},
            );
            return error.GoldenMissing;
        },
        else => return err,
    };
    defer allocator.free(expected);

    if (!std.mem.eql(u8, expected, output.items)) {
        try stderr.writeAll("bench: golden mismatch\n");
        try stderr.writeAll("--- expected ---\n");
        try stderr.writeAll(expected);
        try stderr.writeAll("--- actual ---\n");
        try stderr.writeAll(output.items);
        return error.GoldenMismatch;
    }

    try stderr.writeAll("bench: golden matches\n");
}
