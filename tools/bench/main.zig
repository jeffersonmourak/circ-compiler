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
const diagnostics = @import("diagnostics");
const ir_types = @import("ir_types");
const full_serializer = @import("full_serializer");
const truth_table_builder = @import("truth_table_builder");
const engine = @import("circuit");

/// A raw image loaded into a root-level memory before the vectors are
/// driven, the way `--truth-table --mem=<name>=<path>` does it.
const Preload = struct {
    name: []const u8,
    path: []const u8,
};

const Fixture = struct {
    name: []const u8,
    circ: []const u8,
    preload: ?Preload = null,
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
    .{ .name = "and_5bit", .circ = "tests/fixtures/circuits/and_5bit.circ" },
    .{ .name = "and_6bit", .circ = "tests/fixtures/circuits/and_6bit.circ" },
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
    // 8 inputs feeding a 7-deep AND chain. Stresses cumulative-fanin
    // behavior at a moderate vector count (256) where each input flip can
    // ripple through up to seven gate evaluations.
    .{ .name = "edge_wide_fanin", .circ = "tests/fixtures/circuits/edge_wide_fanin.circ" },
    .{ .name = "eight_bit_adder", .circ = "tests/fixtures/circuits/eight_bit_adder.circ" },
    // 1 input fanning out to three parallel NOTs into three independent
    // outputs. Smallest possible "Phase 2 visits multiple downstream
    // components from one upstream change" exercise.
    .{ .name = "fan_out", .circ = "tests/fixtures/circuits/fan_out.circ" },
    .{ .name = "five_bit_adder", .circ = "tests/fixtures/circuits/five_bit_adder.circ" },
    .{ .name = "four_bit_adder", .circ = "tests/fixtures/circuits/four_bit_adder.circ" },
    .{ .name = "full_adder", .circ = "tests/fixtures/circuits/full_adder_from_builtins.circ" },
    .{ .name = "half_adder", .circ = "tests/fixtures/circuits/half_adder.circ" },
    .{ .name = "mux_2bit_2to1", .circ = "tests/fixtures/circuits/mux_2bit_2to1.circ" },
    .{ .name = "mux_2to1", .circ = "tests/fixtures/circuits/mux_2to1.circ" },
    .{ .name = "mux_3bit_2to1", .circ = "tests/fixtures/circuits/mux_3bit_2to1.circ" },
    .{ .name = "mux_4bit_2to1", .circ = "tests/fixtures/circuits/mux_4bit_2to1.circ" },
    .{ .name = "mux_5bit_2to1", .circ = "tests/fixtures/circuits/mux_5bit_2to1.circ" },
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
    // A preloaded rom read by address: the memory kind's asynchronous read
    // path (one recalc per address change, no gates in between). The 4-bit
    // one is the single-primitive tier; the 8-bit one drives 256 vectors
    // through a 256-word image so the cell-plane lookup dominates.
    .{ .name = "rom_lookup", .circ = "tests/fixtures/circuits/rom_lookup.circ", .preload = .{ .name = "code", .path = "tests/fixtures/mem/rom_lookup.bin" } },
    .{ .name = "rom_lookup_8bit", .circ = "tests/fixtures/circuits/rom_lookup_8bit.circ", .preload = .{ .name = "code", .path = "tests/fixtures/mem/rom_lookup_8bit.bin" } },
    .{ .name = "six_bit_adder", .circ = "tests/fixtures/circuits/six_bit_adder.circ" },
    // 1 input through 100 NOT gates in series, 2 vectors. Pure cascade-depth
    // probe: peak_queue stays small, but final_time grows linearly with
    // depth, exposing any regression in per-step bookkeeping that scales
    // with logical-time advance rather than fan-out width.
    .{ .name = "stress_chain_100", .circ = "tests/fixtures/circuits/stress_chain_100.circ" },
    .{ .name = "three_bit_adder", .circ = "tests/fixtures/circuits/three_bit_adder.circ" },
    .{ .name = "two_bit_adder", .circ = "tests/fixtures/circuits/two_bit_adder.circ" },
    .{ .name = "xnor_2bit", .circ = "tests/fixtures/circuits/xnor_2bit.circ" },
    .{ .name = "xnor_3bit", .circ = "tests/fixtures/circuits/xnor_3bit.circ" },
    .{ .name = "xnor_4bit", .circ = "tests/fixtures/circuits/xnor_4bit.circ" },
    .{ .name = "xor_2bit", .circ = "tests/fixtures/circuits/xor_2bit.circ" },
    .{ .name = "xor_3bit", .circ = "tests/fixtures/circuits/xor_3bit.circ" },
    .{ .name = "xor_4bit", .circ = "tests/fixtures/circuits/xor_4bit.circ" },
    .{ .name = "xor_5bit", .circ = "tests/fixtures/circuits/xor_5bit.circ" },
};

const GOLDEN_PATH = "tests/fixtures/bench/engine.bench.golden";

/// Append-only history of the corpus, opt-in via `RECORD_MILESTONE="<label>"`.
/// First-run bootstraps the BASE section by retrieving the golden at git HEAD,
/// so the recorded BASE always reflects an honest "before" state (not the
/// current working tree's numbers). Subsequent runs parse this file, append a
/// new milestone summary row, and append a per-fixture detail block.
const HIST_PATH = "tests/fixtures/bench/engine.bench.golden.hist.md";

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

/// Channel selector for the structured diff document. Default `text` keeps
/// the existing stderr report verbatim (no extra output). `json` additionally
/// writes a machine-readable diff to stdout, intended for CI consumers
/// (`.github/workflows/perf-pr-comment.yml` pipes it through
/// `tools/bench/format-delta-comment.sh` to produce the PR comment table).
const OutputFormat = enum {
    text,
    json,

    fn parse(s: []const u8) ?OutputFormat {
        if (std.mem.eql(u8, s, "text")) return .text;
        if (std.mem.eql(u8, s, "json")) return .json;
        return null;
    }
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
/// With `with_raw=true`: 0..999 → "4 vecs"; 1_000..999_999 → "16.38k vecs
/// (16384)"; 1_000_000+ → "1.85M events (1850000)". Used on totals lines
/// where exact aggregate counts matter.
/// With `with_raw=false`: drops the `(N)` raw value, so the same numbers
/// render as "4 vecs", "16.38k vecs", "1.85M events". Used on per-fixture
/// rows where the parens just bloat the column width without helping
/// readability.
/// Returns a slice into `buf`. Pass a buf of at least 64 bytes.
fn formatCount(buf: []u8, n: u64, label: []const u8, with_raw: bool) ![]const u8 {
    if (n < 1000) return std.fmt.bufPrint(buf, "{d} {s}", .{ n, label });
    if (n < 1_000_000) {
        const k = @as(f64, @floatFromInt(n)) / 1000.0;
        if (with_raw) return std.fmt.bufPrint(buf, "{d:.2}k {s} ({d})", .{ k, label, n });
        return std.fmt.bufPrint(buf, "{d:.2}k {s}", .{ k, label });
    }
    const m = @as(f64, @floatFromInt(n)) / 1_000_000.0;
    if (with_raw) return std.fmt.bufPrint(buf, "{d:.2}M {s} ({d})", .{ m, label, n });
    return std.fmt.bufPrint(buf, "{d:.2}M {s}", .{ m, label });
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
    /// Nanoseconds spent in the inner drive loop only (excludes parse,
    /// validate, topology build, and engine construction). Sourced from
    /// `Table.drive_ns`. Lets the stderr report separate "engine vector
    /// throughput" from "parser+setup cost", which previously dominated
    /// vec/ms numbers on small fixtures.
    drive_ns: u64,
    /// Allocation counters scoped to this fixture: snapshot delta of the
    /// engine's global counting-allocator around `runFixture`. The bench's
    /// own per-fixture arena (used for parse, IR, topology) is a separate
    /// allocator and doesn't show up here — these counters reflect engine
    /// heap pressure alone. Asserted in the golden because the count and
    /// byte values are deterministic for a given algorithm + input set.
    alloc_metrics: engine.memory.AllocMetrics,
    /// CRC32 over the deterministic shape of the topology: each component's
    /// id/kind/name/origin chain, and each connection's from/to/port. Lets
    /// the diff renderer distinguish "engine changed" (hash same, counters
    /// move) from "fixture changed" (hash moves, counters follow). Written
    /// as 8 hex chars in the golden.
    topology_hash: u32,
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
    .{ .header = "allocs", .width = 7, .numeric = true },
    .{ .header = "bytes", .width = 9, .numeric = true },
    .{ .header = "topology", .width = 8, .numeric = false },
};

/// CRC32 over the topology's deterministic shape: components in order, then
/// connections in order. Catches "fixture changed" vs "engine changed" — if
/// the hash stays put but counters move, the engine drifted; if the hash
/// moves, the test input changed (or the topology builder changed).
fn hashTopology(topology: anytype) u32 {
    const Crc32 = std.hash.Crc32;
    var hasher = Crc32.init();

    const ccount: u32 = @intCast(topology.components.len);
    hasher.update(std.mem.asBytes(&ccount));
    for (topology.components) |comp| {
        hasher.update(std.mem.asBytes(&comp.id));
        const kind_byte: u8 = @intFromEnum(comp.kind);
        hasher.update(&[_]u8{kind_byte});
        hasher.update(comp.name);
        hasher.update("\x00");
        const olen: u32 = @intCast(comp.origin.len);
        hasher.update(std.mem.asBytes(&olen));
        for (comp.origin) |frame| {
            hasher.update(frame.alias);
            hasher.update("\x00");
            hasher.update(frame.subcircuit);
            hasher.update("\x00");
            hasher.update(std.mem.asBytes(&frame.target_file));
        }
    }

    const conncount: u32 = @intCast(topology.connections.len);
    hasher.update(std.mem.asBytes(&conncount));
    for (topology.connections) |conn| {
        hasher.update(std.mem.asBytes(&conn.from_id));
        hasher.update(std.mem.asBytes(&conn.to_id));
        hasher.update(&[_]u8{conn.port});
    }

    return hasher.final();
}

fn updateMode() bool {
    const env = std.posix.getenv("UPDATE_GOLDENS") orelse return false;
    return std.mem.eql(u8, env, "1");
}

/// Reads `RECORD_MILESTONE`. Empty / unset → null (feature off). Otherwise the
/// value is the milestone label, used as both the human-readable description
/// in the .hist file and the spinner-style identifier in the run report.
fn recordMilestoneLabel() ?[]const u8 {
    const env = std.posix.getenv("RECORD_MILESTONE") orelse return null;
    if (env.len == 0) return null;
    return env;
}

/// Today's date as YYYY-MM-DD using std.time's epoch helpers. Local timezone
/// is ignored on purpose: the bench is host-portable and we'd rather have a
/// consistent UTC anchor than the host's clock-on-the-wall value.
fn currentDateStr(allocator: std.mem.Allocator) ![]u8 {
    const ts = std.time.timestamp();
    if (ts < 0) return error.NegativeTimestamp;
    const es: std.time.epoch.EpochSeconds = .{ .secs = @intCast(ts) };
    const ed = es.getEpochDay();
    const yd = ed.calculateYearDay();
    const md = yd.calculateMonthDay();
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        yd.year,
        @intFromEnum(md.month),
        md.day_index + 1,
    });
}

/// Short git SHA of HEAD. Returns "?" (rather than failing the bench) when git
/// is missing or the working tree isn't a repo; the milestone log still gets
/// written, just without an attribution column the reader could click into.
fn gitShortSha(allocator: std.mem.Allocator) ![]u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "rev-parse", "--short", "HEAD" },
        .cwd = ".",
        .max_output_bytes = 256,
    }) catch return try allocator.dupe(u8, "?");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (result.term != .Exited or result.term.Exited != 0) {
        return try allocator.dupe(u8, "?");
    }
    const trimmed = std.mem.trim(u8, result.stdout, " \r\n\t");
    if (trimmed.len == 0) return try allocator.dupe(u8, "?");
    return try allocator.dupe(u8, trimmed);
}

/// Retrieves the golden table that lives at HEAD's `engine.bench.golden`. Used
/// only at bootstrap time to seed `.hist`'s BASE section, so the BASE
/// numbers reflect a pre-change snapshot regardless of the current working
/// tree's golden. Caller owns the returned bytes.
fn gitShowBaseGolden(allocator: std.mem.Allocator) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "show", "HEAD:" ++ GOLDEN_PATH },
        .cwd = ".",
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stderr);
    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.GitShowFailed;
    }
    return result.stdout;
}

/// One row in the milestone summary table: corpus-level totals captured at
/// record-time. Holds every deterministic counter the engine bench tracks,
/// plus drv_ns for wall-clock visibility. `drive_ns` is optional because the
/// golden never stored wall-clock; rows reconstructed from BASE leave it
/// null and any "Δ drv vs base" cells render as `?`.
///
/// Aggregation rule: every counter is summed across the 53 fixtures EXCEPT
/// `peak_queue`, which takes the max — depth is per-iteration, not additive,
/// and the rollup code (see family rollups around line 750) uses the same
/// convention for the same reason.
const MilestoneRecord = struct {
    number: u32,
    date: []const u8,
    commit: []const u8,
    label: []const u8,
    events_popped: u64,
    events_committed: u64,
    recalcs: u64,
    /// Max across fixtures (depth is per-iteration, not additive).
    peak_queue: u64,
    final_time: u64,
    allocs: u64,
    bytes: u64,
    /// Nanoseconds spent across all fixture drive loops. Null for any
    /// milestone where wall-clock wasn't available (e.g., BASE itself).
    drive_ns: ?u64,
};

/// Parses the cached `.hist` file just enough to compute deltas for the
/// next milestone: extracts the verbatim BASE section text (preserved on
/// re-write), the BASE totals (for "Δ vs base" math), prior milestone
/// summary rows (for the running table and "Δ vs prev"), and prior per-
/// milestone detail blocks (preserved verbatim — re-rendering them
/// would require per-fixture data we don't store at this granularity).
const ParsedHist = struct {
    base_section: []const u8,
    base_date: []const u8,
    base_commit: []const u8,
    base_totals: MilestoneRecord,
    milestones: []MilestoneRecord,
    detail_blocks: []const u8,
};

/// Compute corpus totals from a slice of golden-format rows. Used both to
/// derive BASE totals at bootstrap and to derive the current-run totals when
/// writing a new milestone. `peak_queue` uses max, everything else sums.
fn totalsFromParsedRows(rows: []const ParsedRow) MilestoneRecord {
    var ep: u64 = 0;
    var ec: u64 = 0;
    var rc: u64 = 0;
    var pq: u64 = 0;
    var ft: u64 = 0;
    var al: u64 = 0;
    var by: u64 = 0;
    for (rows) |r| {
        ep += r.events_popped;
        ec += r.events_committed;
        rc += r.recalcs;
        if (r.peak_queue > pq) pq = r.peak_queue;
        ft += r.final_time;
        al += r.allocs;
        by += r.bytes;
    }
    return .{
        .number = 0,
        .date = "",
        .commit = "",
        .label = "baseline",
        .events_popped = ep,
        .events_committed = ec,
        .recalcs = rc,
        .peak_queue = pq,
        .final_time = ft,
        .allocs = al,
        .bytes = by,
        .drive_ns = null,
    };
}

/// Extract the leading integer from a combined cell like
/// `9515490 (+0.0% / ?)`. Returns an error if the cell doesn't start with a
/// digit (caller skips the row, on the same "tolerate malformed rows"
/// principle as parseGoldenRows).
fn absFromCombinedCellU64(cell: []const u8) !u64 {
    var end: usize = 0;
    while (end < cell.len and std.ascii.isDigit(cell[end])) end += 1;
    if (end == 0) return error.NoLeadingNumber;
    return std.fmt.parseInt(u64, cell[0..end], 10);
}

/// Same idea but for the drv_ms cell, which holds a floating-point number
/// (e.g. `1846.158`) or the literal `?` for milestones that weren't taken
/// with wall-clock visibility. Returns null on `?` or unparseable input,
/// matching the writer's "render `?` when drv_ns is null" convention.
fn absFromCombinedCellDrv(cell: []const u8) ?u64 {
    if (cell.len == 0 or cell[0] == '?') return null;
    var end: usize = 0;
    while (end < cell.len and (std.ascii.isDigit(cell[end]) or cell[end] == '.')) end += 1;
    if (end == 0) return null;
    const ms = std.fmt.parseFloat(f64, cell[0..end]) catch return null;
    return @intFromFloat(ms * @as(f64, std.time.ns_per_ms));
}

/// Best-effort parser for `.hist`. Locates the BASE section (verbatim text
/// from "## BASE" up to "## Milestone Summary"), parses the milestone summary
/// table for absolutes, and preserves the per-milestone detail blocks as a
/// single opaque trailing slice. Anything malformed is reported via an error
/// so the writer can refuse to clobber a broken file.
fn parseHist(allocator: std.mem.Allocator, content: []const u8) !ParsedHist {
    const base_header = std.mem.indexOf(u8, content, "## BASE") orelse return error.MissingBaseSection;
    const summary_header = std.mem.indexOf(u8, content[base_header..], "## Milestone Summary") orelse return error.MissingSummarySection;
    const summary_abs = base_header + summary_header;

    const base_section = content[base_header..summary_abs];

    // Pull date and commit out of the "## BASE  (recorded YYYY-MM-DD, commit XXXXXXX)" line.
    var base_date: []const u8 = "?";
    var base_commit: []const u8 = "?";
    if (std.mem.indexOf(u8, base_section, "(recorded ")) |open_idx| {
        const rest = base_section[open_idx + "(recorded ".len ..];
        if (std.mem.indexOfScalar(u8, rest, ',')) |comma| {
            base_date = std.mem.trim(u8, rest[0..comma], " \r\n\t");
            const after_comma = rest[comma + 1 ..];
            if (std.mem.indexOf(u8, after_comma, "commit ")) |commit_idx| {
                const after_commit = after_comma[commit_idx + "commit ".len ..];
                if (std.mem.indexOfScalar(u8, after_commit, ')')) |close_idx| {
                    base_commit = std.mem.trim(u8, after_commit[0..close_idx], " \r\n\t");
                }
            }
        }
    }

    // Parse the BASE table rows so we can derive corpus totals for delta math.
    const base_rows = try parseGoldenRows(allocator, base_section);
    defer allocator.free(base_rows);
    var base_totals = totalsFromParsedRows(base_rows);
    base_totals.date = base_date;
    base_totals.commit = base_commit;

    // Find the end of the summary section. The summary stops at the first
    // "## Milestone " (detail block) heading, or EOF.
    const detail_start_rel = std.mem.indexOf(u8, content[summary_abs..], "\n## Milestone ");
    const summary_end = if (detail_start_rel) |off| summary_abs + off + 1 else content.len;
    const summary_section = content[summary_abs..summary_end];
    const detail_blocks: []const u8 = if (summary_end < content.len) content[summary_end..] else "";

    var milestones: std.ArrayList(MilestoneRecord) = .{};
    errdefer milestones.deinit(allocator);

    var line_it = std.mem.splitScalar(u8, summary_section, '\n');
    var seen_separator: bool = false;
    while (line_it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \r");
        if (line.len == 0 or line[0] != '|') continue;
        // Two header lines: the column titles and the dashed separator.
        if (!seen_separator) {
            if (std.mem.indexOfScalar(u8, line, '-') != null and
                std.mem.indexOfAny(u8, line, "0123456789") == null)
            {
                seen_separator = true;
            }
            continue;
        }

        var cells: [16][]const u8 = undefined;
        var n: usize = 0;
        var col_it = std.mem.splitScalar(u8, line, '|');
        while (col_it.next()) |raw| {
            if (n >= cells.len) break;
            cells[n] = std.mem.trim(u8, raw, " ");
            n += 1;
        }
        // 4 metadata cells + 8 combined-value cells + leading/trailing
        // splitScalar empties = at least 14 cells expected. Anything less
        // means a row we don't recognize (header / separator / decoration).
        if (n < 14) continue;

        const num = std.fmt.parseInt(u32, cells[1], 10) catch continue;
        const date_owned = try allocator.dupe(u8, cells[2]);
        const commit_owned = try allocator.dupe(u8, cells[3]);
        const label_owned = try allocator.dupe(u8, cells[4]);
        const ev = absFromCombinedCellU64(cells[5]) catch continue;
        const ec = absFromCombinedCellU64(cells[6]) catch continue;
        const rc = absFromCombinedCellU64(cells[7]) catch continue;
        const pq = absFromCombinedCellU64(cells[8]) catch continue;
        const ft = absFromCombinedCellU64(cells[9]) catch continue;
        const allocs = absFromCombinedCellU64(cells[10]) catch continue;
        const bytes_val = absFromCombinedCellU64(cells[11]) catch continue;
        const drv_ns: ?u64 = absFromCombinedCellDrv(cells[12]);

        try milestones.append(allocator, .{
            .number = num,
            .date = date_owned,
            .commit = commit_owned,
            .label = label_owned,
            .events_popped = ev,
            .events_committed = ec,
            .recalcs = rc,
            .peak_queue = pq,
            .final_time = ft,
            .allocs = allocs,
            .bytes = bytes_val,
            .drive_ns = drv_ns,
        });
    }

    return .{
        .base_section = base_section,
        .base_date = base_date,
        .base_commit = base_commit,
        .base_totals = base_totals,
        .milestones = try milestones.toOwnedSlice(allocator),
        .detail_blocks = detail_blocks,
    };
}

/// Render an absolute → absolute percentage delta as either "+X.X%" / "-X.X%"
/// or the sentinel "?" when the reference side is unknown (used for BASE drv,
/// which the golden never asserted).
fn formatPctDelta(buf: []u8, ref: ?u64, cur: u64) ![]const u8 {
    const r = ref orelse return std.fmt.bufPrint(buf, "?", .{});
    if (r == 0) return std.fmt.bufPrint(buf, "n/a", .{});
    const diff: f64 = @as(f64, @floatFromInt(cur)) - @as(f64, @floatFromInt(r));
    const pct: f64 = 100.0 * diff / @as(f64, @floatFromInt(r));
    const sign: u8 = if (pct >= 0) '+' else '-';
    const abs_pct = if (pct >= 0) pct else -pct;
    return std.fmt.bufPrint(buf, "{c}{d:.1}%", .{ sign, abs_pct });
}

/// Render one metric cell for the summary table: `<value> (Δb%/Δp%)`. Width
/// covers the entire combined cell, not just the leading number, so the
/// delta tail aligns across rows. Pass `is_drv=true` to render the value as
/// floating-point milliseconds; otherwise it's an integer.
fn writeCombinedSummaryCell(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    base_ref: ?u64,
    prev_ref: ?u64,
    cur: ?u64,
    width: usize,
    is_drv: bool,
) !void {
    var cell_buf: [96]u8 = undefined;
    var base_buf: [24]u8 = undefined;
    var prev_buf: [24]u8 = undefined;
    var cell_s: []const u8 = "?";
    if (cur) |c| {
        const base_s = try formatPctDelta(&base_buf, base_ref, c);
        const prev_s = try formatPctDelta(&prev_buf, prev_ref, c);
        if (is_drv) {
            const ms_f = @as(f64, @floatFromInt(c)) / std.time.ns_per_ms;
            cell_s = try std.fmt.bufPrint(&cell_buf, "{d:.3} ({s}/{s})", .{ ms_f, base_s, prev_s });
        } else {
            cell_s = try std.fmt.bufPrint(&cell_buf, "{d} ({s}/{s})", .{ c, base_s, prev_s });
        }
    }
    try out.append(allocator, ' ');
    // Right-align numeric cells: pad spaces before the value.
    if (cell_s.len < width) try out.appendNTimes(allocator, ' ', width - cell_s.len);
    try out.appendSlice(allocator, cell_s);
    try out.appendSlice(allocator, " |");
}

const MilestoneSummaryColumns = struct {
    const num: usize = 3;
    const date: usize = 10;
    const commit: usize = 7;
    const label: usize = 32;
    /// Combined-cell widths. Set to comfortably fit `<largest-value> (<largest-delta>)`
    /// for that metric on the current corpus. Wider than strictly necessary
    /// so future regressions don't push cells past their column boundary.
    const ev_cell: usize = 26;
    const ec_cell: usize = 26;
    const rc_cell: usize = 26;
    const pq_cell: usize = 22;
    const ft_cell: usize = 26;
    const allocs_cell: usize = 26;
    const bytes_cell: usize = 28;
    const drv_cell: usize = 26;
};

fn writeMilestoneSummaryHeader(out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    const M = MilestoneSummaryColumns;
    const headers = [_]struct { text: []const u8, width: usize }{
        .{ .text = "#", .width = M.num },
        .{ .text = "date", .width = M.date },
        .{ .text = "commit", .width = M.commit },
        .{ .text = "label", .width = M.label },
        .{ .text = "events_popped (Δb/Δp)", .width = M.ev_cell },
        .{ .text = "events_committed (Δb/Δp)", .width = M.ec_cell },
        .{ .text = "recalcs (Δb/Δp)", .width = M.rc_cell },
        .{ .text = "peak_queue (Δb/Δp)", .width = M.pq_cell },
        .{ .text = "final_time (Δb/Δp)", .width = M.ft_cell },
        .{ .text = "allocs (Δb/Δp)", .width = M.allocs_cell },
        .{ .text = "bytes (Δb/Δp)", .width = M.bytes_cell },
        .{ .text = "drv_ms (Δb/Δp)", .width = M.drv_cell },
    };
    try out.append(allocator, '|');
    for (headers) |h| {
        try out.append(allocator, ' ');
        try out.appendSlice(allocator, h.text);
        // Account for the Greek delta being 2 bytes in UTF-8 while occupying 1 column.
        const visible_len = visibleLen(h.text);
        if (visible_len < h.width) try out.appendNTimes(allocator, ' ', h.width - visible_len);
        try out.appendSlice(allocator, " |");
    }
    try out.append(allocator, '\n');
    try out.append(allocator, '|');
    for (headers) |h| {
        try out.append(allocator, '-');
        try out.appendNTimes(allocator, '-', h.width);
        try out.appendSlice(allocator, "-|");
    }
    try out.append(allocator, '\n');
}

/// Visible column width of a header label, treating the literal Δ (`U+0394`,
/// 2 bytes in UTF-8) as 1 column. Keeps the dashed separator line aligned
/// with the header line in monospace.
fn visibleLen(s: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const b = s[i];
        if (b < 0x80) {
            count += 1;
            i += 1;
        } else if ((b & 0xE0) == 0xC0) {
            count += 1;
            i += 2;
        } else if ((b & 0xF0) == 0xE0) {
            count += 1;
            i += 3;
        } else {
            count += 1;
            i += 4;
        }
    }
    return count;
}

fn writeMilestoneRow(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    m: MilestoneRecord,
    base: MilestoneRecord,
    prev: ?MilestoneRecord,
) !void {
    const M = MilestoneSummaryColumns;
    var buf: [64]u8 = undefined;

    try out.append(allocator, '|');

    const s = try std.fmt.bufPrint(&buf, "{d}", .{m.number});
    try writeCell(out, allocator, s, .{ .header = "#", .width = M.num, .numeric = true });

    try writeCell(out, allocator, m.date, .{ .header = "date", .width = M.date, .numeric = false });
    try writeCell(out, allocator, m.commit, .{ .header = "commit", .width = M.commit, .numeric = false });
    try writeCell(out, allocator, m.label, .{ .header = "label", .width = M.label, .numeric = false });

    // Each metric cell carries `<value> (Δ vs base / Δ vs prev)`. When prev
    // is null (first milestone), the prev half renders as "?". When the
    // metric is drv_ms and the run never recorded it, the whole cell is "?".
    try writeCombinedSummaryCell(out, allocator, base.events_popped, if (prev) |p| p.events_popped else null, m.events_popped, M.ev_cell, false);
    try writeCombinedSummaryCell(out, allocator, base.events_committed, if (prev) |p| p.events_committed else null, m.events_committed, M.ec_cell, false);
    try writeCombinedSummaryCell(out, allocator, base.recalcs, if (prev) |p| p.recalcs else null, m.recalcs, M.rc_cell, false);
    try writeCombinedSummaryCell(out, allocator, base.peak_queue, if (prev) |p| p.peak_queue else null, m.peak_queue, M.pq_cell, false);
    try writeCombinedSummaryCell(out, allocator, base.final_time, if (prev) |p| p.final_time else null, m.final_time, M.ft_cell, false);
    try writeCombinedSummaryCell(out, allocator, base.allocs, if (prev) |p| p.allocs else null, m.allocs, M.allocs_cell, false);
    try writeCombinedSummaryCell(out, allocator, base.bytes, if (prev) |p| p.bytes else null, m.bytes, M.bytes_cell, false);
    try writeCombinedSummaryCell(out, allocator, base.drive_ns, if (prev) |p| p.drive_ns else null, m.drive_ns, M.drv_cell, true);

    try out.append(allocator, '\n');
}

/// Write per-fixture detail rows for one milestone, joined against BASE for
/// the "Δ vs base" parenthetical. `current_rows` must be in fixture-manifest
/// (alphabetical) order; BASE rows are looked up by fixture name. Each metric
/// cell carries `<value> (Δ%)`; the prev-side delta isn't shown per-fixture
/// because we don't persist per-fixture data for prior milestones — the
/// summary table is where vs-prev lives.
fn writeDetailBlock(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    base_rows: []const ParsedRow,
    current_rows: []const Row,
) !void {
    var base_by_name = std.StringHashMap(ParsedRow).init(allocator);
    defer base_by_name.deinit();
    try base_by_name.ensureTotalCapacity(@intCast(base_rows.len));
    for (base_rows) |br| base_by_name.putAssumeCapacity(br.name, br);

    const fixture_w: usize = 24;
    const ev_w: usize = 18;
    const ec_w: usize = 18;
    const rc_w: usize = 18;
    const pq_w: usize = 12;
    const ft_w: usize = 20;
    const allocs_w: usize = 18;
    const bytes_w: usize = 20;

    // Header
    try out.append(allocator, '|');
    const headers = [_]struct { text: []const u8, width: usize }{
        .{ .text = "circuit", .width = fixture_w },
        .{ .text = "events_popped (Δ%)", .width = ev_w },
        .{ .text = "events_committed (Δ%)", .width = ec_w },
        .{ .text = "recalcs (Δ%)", .width = rc_w },
        .{ .text = "peak_queue (Δ%)", .width = pq_w },
        .{ .text = "final_time (Δ%)", .width = ft_w },
        .{ .text = "allocs (Δ%)", .width = allocs_w },
        .{ .text = "bytes (Δ%)", .width = bytes_w },
    };
    for (headers) |h| {
        try out.append(allocator, ' ');
        try out.appendSlice(allocator, h.text);
        const visible = visibleLen(h.text);
        if (visible < h.width) try out.appendNTimes(allocator, ' ', h.width - visible);
        try out.appendSlice(allocator, " |");
    }
    try out.append(allocator, '\n');
    try out.append(allocator, '|');
    for (headers) |h| {
        try out.append(allocator, '-');
        try out.appendNTimes(allocator, '-', h.width);
        try out.appendSlice(allocator, "-|");
    }
    try out.append(allocator, '\n');

    var pct_buf: [24]u8 = undefined;
    var cell_buf: [64]u8 = undefined;
    for (current_rows) |row| {
        try out.append(allocator, '|');
        try writeCell(out, allocator, row.name, .{ .header = "circuit", .width = fixture_w, .numeric = false });

        const base_opt = base_by_name.get(row.name);

        const ev_base: ?u64 = if (base_opt) |b| b.events_popped else null;
        const ev_pct = try formatPctDelta(&pct_buf, ev_base, row.metrics.events_popped);
        var s = try std.fmt.bufPrint(&cell_buf, "{d} ({s})", .{ row.metrics.events_popped, ev_pct });
        try writeCell(out, allocator, s, .{ .header = "ev", .width = ev_w, .numeric = true });

        const ec_base: ?u64 = if (base_opt) |b| b.events_committed else null;
        const ec_pct = try formatPctDelta(&pct_buf, ec_base, row.metrics.events_committed);
        s = try std.fmt.bufPrint(&cell_buf, "{d} ({s})", .{ row.metrics.events_committed, ec_pct });
        try writeCell(out, allocator, s, .{ .header = "ec", .width = ec_w, .numeric = true });

        const rc_base: ?u64 = if (base_opt) |b| b.recalcs else null;
        const rc_pct = try formatPctDelta(&pct_buf, rc_base, row.metrics.recalcs);
        s = try std.fmt.bufPrint(&cell_buf, "{d} ({s})", .{ row.metrics.recalcs, rc_pct });
        try writeCell(out, allocator, s, .{ .header = "rc", .width = rc_w, .numeric = true });

        const pq_base: ?u64 = if (base_opt) |b| b.peak_queue else null;
        const pq_pct = try formatPctDelta(&pct_buf, pq_base, row.metrics.peak_queue);
        s = try std.fmt.bufPrint(&cell_buf, "{d} ({s})", .{ row.metrics.peak_queue, pq_pct });
        try writeCell(out, allocator, s, .{ .header = "pq", .width = pq_w, .numeric = true });

        const ft_base: ?u64 = if (base_opt) |b| b.final_time else null;
        const ft_pct = try formatPctDelta(&pct_buf, ft_base, row.metrics.final_time);
        s = try std.fmt.bufPrint(&cell_buf, "{d} ({s})", .{ row.metrics.final_time, ft_pct });
        try writeCell(out, allocator, s, .{ .header = "ft", .width = ft_w, .numeric = true });

        const allocs_base: ?u64 = if (base_opt) |b| b.allocs else null;
        const a_pct = try formatPctDelta(&pct_buf, allocs_base, row.alloc_metrics.allocs);
        s = try std.fmt.bufPrint(&cell_buf, "{d} ({s})", .{ row.alloc_metrics.allocs, a_pct });
        try writeCell(out, allocator, s, .{ .header = "allocs", .width = allocs_w, .numeric = true });

        const bytes_base: ?u64 = if (base_opt) |b| b.bytes else null;
        const b_pct = try formatPctDelta(&pct_buf, bytes_base, row.alloc_metrics.bytes);
        s = try std.fmt.bufPrint(&cell_buf, "{d} ({s})", .{ row.alloc_metrics.bytes, b_pct });
        try writeCell(out, allocator, s, .{ .header = "bytes", .width = bytes_w, .numeric = true });

        try out.append(allocator, '\n');
    }
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

    s = try std.fmt.bufPrint(&buf, "{d}", .{row.alloc_metrics.allocs});
    try writeCell(out, allocator, s, columns[8]);

    s = try std.fmt.bufPrint(&buf, "{d}", .{row.alloc_metrics.bytes});
    try writeCell(out, allocator, s, columns[9]);

    // Hash rendered as 8 hex chars (lowercase). Fixed width keeps the column
    // alignment stable across runs even when leading nibbles happen to be zero.
    s = try std.fmt.bufPrint(&buf, "{x:0>8}", .{row.topology_hash});
    try writeCell(out, allocator, s, columns[10]);

    try out.append(allocator, '\n');
}

/// Group a fixture name by family for the rollup view. Suffix-match on
/// "_adder" lumps half/full/N_bit adders together; otherwise the family is
/// the substring before the first underscore (so "and_4bit" → "and",
/// "primitive_led" → "primitive"). Names without underscores are their own
/// family ("chain", "alu_4bit" → "alu" via the first-underscore rule).
fn familyOf(name: []const u8) []const u8 {
    if (std.mem.endsWith(u8, name, "_adder")) return "adder";
    if (std.mem.indexOfScalar(u8, name, '_')) |idx| return name[0..idx];
    return name;
}

const RollupRow = struct {
    family: []const u8,
    fixtures: u32 = 0,
    vectors: u64 = 0,
    events_popped: u64 = 0,
    events_committed: u64 = 0,
    /// Max across the family — depth is per-iteration, not additive.
    peak_queue: u64 = 0,
    allocs: u64 = 0,
    bytes: u64 = 0,
    drive_ns: u64 = 0,
};

/// Parsed-back view of a single golden row. Lives just long enough to feed
/// the mismatch diff renderer; the names are slices into the on-disk file
/// buffer so the parsed slice cannot outlive that buffer.
const ParsedRow = struct {
    name: []const u8,
    vectors: u64,
    components: u64,
    events_popped: u64,
    events_committed: u64,
    recalcs: u64,
    peak_queue: u64,
    final_time: u64,
    allocs: u64,
    bytes: u64,
    topology_hash: u32,
};

/// Parse a golden file back into ParsedRow records keyed by fixture name.
/// Tolerant of empty / malformed lines (skips them) but returns an error if
/// the allocator itself fails. Header rows (the first two lines) are skipped
/// by index rather than content match because the format is stable across
/// runs and a fancier parser would just create new failure modes.
fn parseGoldenRows(
    allocator: std.mem.Allocator,
    golden: []const u8,
) ![]ParsedRow {
    var rows: std.ArrayList(ParsedRow) = .{};
    errdefer rows.deinit(allocator);

    var line_it = std.mem.splitScalar(u8, golden, '\n');
    var line_idx: usize = 0;
    while (line_it.next()) |line| : (line_idx += 1) {
        if (line_idx < 2) continue;
        if (line.len == 0) continue;
        if (line[0] != '|') continue;

        // Eight content cells live between nine pipes. splitScalar yields the
        // empties before the leading '|' and after the trailing '|' too, so
        // we just read by index.
        var cells: [12][]const u8 = undefined;
        var n: usize = 0;
        var col_it = std.mem.splitScalar(u8, line, '|');
        while (col_it.next()) |raw| {
            if (n >= cells.len) break;
            cells[n] = std.mem.trim(u8, raw, " ");
            n += 1;
        }
        if (n < 12) continue;

        try rows.append(allocator, .{
            .name = cells[1],
            .vectors = std.fmt.parseInt(u64, cells[2], 10) catch continue,
            .components = std.fmt.parseInt(u64, cells[3], 10) catch continue,
            .events_popped = std.fmt.parseInt(u64, cells[4], 10) catch continue,
            .events_committed = std.fmt.parseInt(u64, cells[5], 10) catch continue,
            .recalcs = std.fmt.parseInt(u64, cells[6], 10) catch continue,
            .peak_queue = std.fmt.parseInt(u64, cells[7], 10) catch continue,
            .final_time = std.fmt.parseInt(u64, cells[8], 10) catch continue,
            .allocs = std.fmt.parseInt(u64, cells[9], 10) catch continue,
            .bytes = std.fmt.parseInt(u64, cells[10], 10) catch continue,
            .topology_hash = std.fmt.parseInt(u32, cells[11], 16) catch continue,
        });
    }
    return try rows.toOwnedSlice(allocator);
}

/// Render a signed delta with both absolute and percentage change. Returns
/// an empty string when old == new so the caller can skip the row. The sign
/// character is rendered manually because Zig 0.15's format syntax doesn't
/// accept a `+` flag inside `{d:...}`.
fn formatDelta(buf: []u8, old: u64, new: u64) ![]const u8 {
    if (new == old) return "";
    const sign: u8 = if (new > old) '+' else '-';
    const delta = if (new > old) new - old else old - new;
    if (old == 0) {
        return std.fmt.bufPrint(buf, "{c}{d} (n/a%)", .{ sign, delta });
    }
    const pct: f64 = 100.0 * @as(f64, @floatFromInt(delta)) / @as(f64, @floatFromInt(old));
    return std.fmt.bufPrint(buf, "{c}{d} ({c}{d:.2}%)", .{ sign, delta, sign, pct });
}

/// Emit a per-column delta block for one fixture. Skips columns that didn't
/// change so the report stays focused. The topology hash is rendered as a
/// special leading line tagged "(topology changed)" so it's obvious that any
/// counter shifts that follow are likely fixture/builder drift, not engine
/// drift. When the hash is unchanged, only the counter rows show.
fn printRowDiff(
    stderr: anytype,
    name: []const u8,
    old: ParsedRow,
    new: Row,
) !void {
    const checks = [_]struct { label: []const u8, old: u64, new: u64 }{
        .{ .label = "vectors", .old = old.vectors, .new = new.vectors },
        .{ .label = "components", .old = old.components, .new = new.components },
        .{ .label = "events_popped", .old = old.events_popped, .new = new.metrics.events_popped },
        .{ .label = "events_committed", .old = old.events_committed, .new = new.metrics.events_committed },
        .{ .label = "recalcs", .old = old.recalcs, .new = new.metrics.recalcs },
        .{ .label = "peak_queue", .old = old.peak_queue, .new = new.metrics.peak_queue },
        .{ .label = "final_time", .old = old.final_time, .new = new.metrics.final_time },
        .{ .label = "allocs", .old = old.allocs, .new = new.alloc_metrics.allocs },
        .{ .label = "bytes", .old = old.bytes, .new = new.alloc_metrics.bytes },
    };

    const hash_changed = old.topology_hash != new.topology_hash;
    var any: bool = hash_changed;
    if (!any) {
        for (checks) |c| {
            if (c.old != c.new) {
                any = true;
                break;
            }
        }
    }
    if (!any) return;

    if (hash_changed) {
        try stderr.print("  {s}  (topology changed)\n", .{name});
        try stderr.print(
            "    {s: <18}  {x:0>8} → {x:0>8}\n",
            .{ "topology_hash", old.topology_hash, new.topology_hash },
        );
    } else {
        try stderr.print("  {s}\n", .{name});
    }

    var buf: [80]u8 = undefined;
    for (checks) |c| {
        if (c.old == c.new) continue;
        const delta_s = try formatDelta(&buf, c.old, c.new);
        try stderr.print(
            "    {s: <18}  {d: >10} → {d: >10}   {s}\n",
            .{ c.label, c.old, c.new, delta_s },
        );
    }
}

/// Emit a structured JSON diff to `out`. Schema:
///
///   {
///     "status": "mismatch" | "match",
///     "summary": { "changed": N, "added": N, "removed": N },
///     "fixtures": [
///       {
///         "name": "<fixture>",
///         "topology_changed": bool,
///         "changes": [
///           { "counter": "<name>", "from": N, "to": N, "delta": N, "pct_change": F }, ...
///         ]
///       }, ...
///     ]
///   }
///
/// Only fixtures with at least one counter (or topology-hash) change appear
/// in the array. Added/removed fixtures are reflected in `summary` counts
/// but not the array (they have no symmetric before/after to tabulate, and
/// the corpus manifest is stable enough that they're rare in practice).
/// Fixture names in the manifest are ASCII identifiers, so no JSON string
/// escaping is needed; if that ever changes, swap the raw `{s}` print for
/// a proper escaper.
fn emitJsonDiff(
    out: anytype,
    fixtures_list: []const Fixture,
    expected_by_name: *std.StringHashMap(ParsedRow),
    actual_by_name: *std.StringHashMap(Row),
    changed: usize,
    added: usize,
    removed: usize,
) !void {
    const status_str: []const u8 = if (changed > 0 or added > 0 or removed > 0) "mismatch" else "match";
    try out.print(
        "{{\"status\":\"{s}\",\"summary\":{{\"changed\":{d},\"added\":{d},\"removed\":{d}}},\"fixtures\":[",
        .{ status_str, changed, added, removed },
    );

    var emitted_any: bool = false;
    for (fixtures_list) |fixture| {
        const actual_opt = actual_by_name.get(fixture.name);
        const exp_opt = expected_by_name.get(fixture.name);
        // Added/removed fixtures contribute only to summary counts; their
        // per-counter shape isn't comparable so we skip the array entry.
        if (actual_opt == null or exp_opt == null) continue;
        const actual = actual_opt.?;
        const exp = exp_opt.?;

        const topology_changed = exp.topology_hash != actual.topology_hash;
        const checks = [_]struct { label: []const u8, old: u64, new: u64 }{
            .{ .label = "vectors", .old = exp.vectors, .new = actual.vectors },
            .{ .label = "components", .old = exp.components, .new = actual.components },
            .{ .label = "events_popped", .old = exp.events_popped, .new = actual.metrics.events_popped },
            .{ .label = "events_committed", .old = exp.events_committed, .new = actual.metrics.events_committed },
            .{ .label = "recalcs", .old = exp.recalcs, .new = actual.metrics.recalcs },
            .{ .label = "peak_queue", .old = exp.peak_queue, .new = actual.metrics.peak_queue },
            .{ .label = "final_time", .old = exp.final_time, .new = actual.metrics.final_time },
            .{ .label = "allocs", .old = exp.allocs, .new = actual.alloc_metrics.allocs },
            .{ .label = "bytes", .old = exp.bytes, .new = actual.alloc_metrics.bytes },
        };

        var any_counter_changed: bool = false;
        for (checks) |c| {
            if (c.old != c.new) {
                any_counter_changed = true;
                break;
            }
        }
        if (!topology_changed and !any_counter_changed) continue;

        if (emitted_any) try out.writeAll(",");
        emitted_any = true;

        try out.print(
            "{{\"name\":\"{s}\",\"topology_changed\":{s},\"changes\":[",
            .{ fixture.name, if (topology_changed) "true" else "false" },
        );

        var first_change: bool = true;
        for (checks) |c| {
            if (c.old == c.new) continue;
            if (!first_change) try out.writeAll(",");
            first_change = false;
            // Signed delta + percentage. The bench's u64 counters can only
            // go up to ~2^63 in practice on this corpus (events_popped tops
            // out around 4.8M for eight_bit_adder), so i128 arithmetic for
            // the signed delta is overkill defensiveness rather than a
            // genuine concern.
            const delta_i: i128 = @as(i128, @intCast(c.new)) - @as(i128, @intCast(c.old));
            const pct: f64 = if (c.old != 0)
                100.0 * @as(f64, @floatFromInt(delta_i)) / @as(f64, @floatFromInt(c.old))
            else
                0.0;
            try out.print(
                "{{\"counter\":\"{s}\",\"from\":{d},\"to\":{d},\"delta\":{d},\"pct_change\":{d:.4}}}",
                .{ c.label, c.old, c.new, delta_i, pct },
            );
        }

        try out.writeAll("]}");
    }

    try out.writeAll("]}\n");
}

fn runFixture(
    allocator: std.mem.Allocator,
    fixture: Fixture,
) !Row {
    // Snapshot the engine's global counting-allocator before the fixture runs.
    // We compute the per-fixture delta at the end of the function so the
    // golden row only reflects this fixture's heap pressure, not the
    // cumulative across all fixtures run so far.
    const alloc_before = engine.memory.snapshotAllocMetrics();

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

    var resolver_diagnostics = diagnostics.initDiagnosticList();
    defer resolver_diagnostics.deinit(allocator);
    const project = try resolve_bodies.resolveBodies(
        allocator,
        scan_result.file_paths,
        scan_result.import_table,
        cycle_result.topo_order,
        &resolver_diagnostics,
    );
    for (resolver_diagnostics.items) |d| {
        if (d.level == .err) return error.ResolveFailed;
    }

    var validator_diagnostics = try validator_run_project.run(allocator, &project);
    defer validator_diagnostics.deinit(allocator);
    for (validator_diagnostics.items) |d| {
        if (d.level == .err) return error.ValidationFailed;
    }

    var topology = try full_serializer.buildFromProject(allocator, &project);
    defer topology.deinit(allocator);

    const component_count = topology.components.len;
    const topology_hash = hashTopology(topology);

    // The image is read with the bench's own allocator, so it never shows
    // up in the engine counters; applying it writes into planes the engine
    // already allocated in createComponent.
    var preloads: [1]truth_table_builder.Preload = undefined;
    var preload_count: usize = 0;
    if (fixture.preload) |p| {
        preloads[0] = .{ .name = p.name, .bytes = try std.fs.cwd().readFileAlloc(allocator, p.path, 1 << 20) };
        preload_count = 1;
    }
    defer if (fixture.preload != null) allocator.free(preloads[0].bytes);

    var table = try truth_table_builder.build(allocator, topology, .{ .preloads = preloads[0..preload_count] });
    defer table.deinit();

    const alloc_after = engine.memory.snapshotAllocMetrics();
    const alloc_delta: engine.memory.AllocMetrics = .{
        .allocs = alloc_after.allocs - alloc_before.allocs,
        .bytes = alloc_after.bytes - alloc_before.bytes,
    };

    return .{
        .name = fixture.name,
        .vectors = table.rows.len,
        .components = component_count,
        .metrics = table.metrics,
        .drive_ns = table.drive_ns,
        .alloc_metrics = alloc_delta,
        .topology_hash = topology_hash,
    };
}

/// Snapshot the corpus into the `.hist` log when `RECORD_MILESTONE` is set.
/// Idempotent across the updateMode / verify / mismatch paths: each codepath
/// in `main()` can call this safely; nothing happens when the env var is
/// unset. On first invocation it bootstraps the BASE section by retrieving
/// `engine.bench.golden` at git HEAD, so the BASE always reflects an honest
/// pre-change snapshot regardless of which run actually creates the file.
fn recordMilestoneIfRequested(
    allocator: std.mem.Allocator,
    stderr: anytype,
    sorted_rows: []const SortedRow,
    total_drive_ns: u64,
) !void {
    const label = recordMilestoneLabel() orelse return;

    // Reorder the per-fixture rows into alphabetical (fixture-manifest)
    // order. The stderr report may have shuffled them under --sort; the
    // .hist detail block always renders alphabetically so diffs stay stable.
    var actual_by_name = std.StringHashMap(Row).init(allocator);
    defer actual_by_name.deinit();
    try actual_by_name.ensureTotalCapacity(@intCast(sorted_rows.len));
    for (sorted_rows) |entry| try actual_by_name.put(entry.row.name, entry.row);

    var current_rows = try allocator.alloc(Row, fixtures.len);
    defer allocator.free(current_rows);
    for (fixtures, 0..) |fixture, i| {
        current_rows[i] = actual_by_name.get(fixture.name) orelse return error.FixtureMissing;
    }

    const today = try currentDateStr(allocator);
    defer allocator.free(today);
    const sha = try gitShortSha(allocator);
    defer allocator.free(sha);

    var current_totals: MilestoneRecord = .{
        .number = 0,
        .date = today,
        .commit = sha,
        .label = label,
        .events_popped = 0,
        .events_committed = 0,
        .recalcs = 0,
        .peak_queue = 0,
        .final_time = 0,
        .allocs = 0,
        .bytes = 0,
        .drive_ns = total_drive_ns,
    };
    // peak_queue is max-aggregated (see MilestoneRecord doc-comment for why).
    for (current_rows) |r| {
        current_totals.events_popped += r.metrics.events_popped;
        current_totals.events_committed += r.metrics.events_committed;
        current_totals.recalcs += r.metrics.recalcs;
        if (r.metrics.peak_queue > current_totals.peak_queue) {
            current_totals.peak_queue = r.metrics.peak_queue;
        }
        current_totals.final_time += r.metrics.final_time;
        current_totals.allocs += r.alloc_metrics.allocs;
        current_totals.bytes += r.alloc_metrics.bytes;
    }

    // Read existing .hist or bootstrap.
    const hist_content = std.fs.cwd().readFileAlloc(allocator, HIST_PATH, 8 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (hist_content) |c| allocator.free(c);

    var parsed_opt: ?ParsedHist = null;
    defer if (parsed_opt) |p| {
        for (p.milestones) |m| {
            allocator.free(m.date);
            allocator.free(m.commit);
            allocator.free(m.label);
        }
        allocator.free(p.milestones);
    };

    var bootstrap_base_section: ?[]u8 = null;
    defer if (bootstrap_base_section) |b| allocator.free(b);

    if (hist_content) |existing| {
        parsed_opt = try parseHist(allocator, existing);
    } else {
        const base_golden = gitShowBaseGolden(allocator) catch |err| {
            try stderr.print(
                "bench: RECORD_MILESTONE bootstrap requires git access (couldn't read HEAD:{s}): {s}\n",
                .{ GOLDEN_PATH, @errorName(err) },
            );
            return err;
        };
        defer allocator.free(base_golden);
        bootstrap_base_section = try std.fmt.allocPrint(
            allocator,
            "## BASE  (recorded {s}, commit {s})\n\n{s}\n",
            .{ today, sha, std.mem.trimRight(u8, base_golden, " \r\n\t") },
        );
    }

    const base_section_text: []const u8 = if (parsed_opt) |p| p.base_section else bootstrap_base_section.?;

    const base_rows = try parseGoldenRows(allocator, base_section_text);
    defer allocator.free(base_rows);

    var base_totals = totalsFromParsedRows(base_rows);
    base_totals.date = if (parsed_opt) |p| p.base_date else today;
    base_totals.commit = if (parsed_opt) |p| p.base_commit else sha;

    const existing_milestones: []const MilestoneRecord = if (parsed_opt) |p| p.milestones else &.{};
    const detail_blocks: []const u8 = if (parsed_opt) |p| std.mem.trim(u8, p.detail_blocks, " \r\n") else "";

    var max_n: u32 = 0;
    for (existing_milestones) |m| {
        if (m.number > max_n) max_n = m.number;
    }
    current_totals.number = max_n + 1;
    const prev_milestone: ?MilestoneRecord = if (existing_milestones.len > 0) existing_milestones[existing_milestones.len - 1] else null;

    var out: std.ArrayList(u8) = .{};
    defer out.deinit(allocator);

    const preamble =
        "# Engine Benchmark History\n" ++
        "#\n" ++
        "# Records the historical evolution of the engine benchmark corpus.\n" ++
        "# BASE is frozen; the milestone log grows over time. Regenerate by\n" ++
        "# running `RECORD_MILESTONE=\"<label>\" zig build bench`.\n" ++
        "#\n" ++
        "# The `Milestone Summary` table is the structured source of truth;\n" ++
        "# per-milestone detail blocks below capture per-fixture deltas vs\n" ++
        "# BASE at recording time and are preserved verbatim on re-write.\n\n";
    try out.appendSlice(allocator, preamble);

    try out.appendSlice(allocator, std.mem.trimRight(u8, base_section_text, "\n"));
    try out.appendSlice(allocator, "\n\n");

    try out.appendSlice(allocator, "## Milestone Summary\n\n");
    try writeMilestoneSummaryHeader(&out, allocator);
    for (existing_milestones, 0..) |m, idx| {
        const prev_for_m: ?MilestoneRecord = if (idx == 0) null else existing_milestones[idx - 1];
        try writeMilestoneRow(&out, allocator, m, base_totals, prev_for_m);
    }
    try writeMilestoneRow(&out, allocator, current_totals, base_totals, prev_milestone);

    if (detail_blocks.len > 0) {
        try out.appendSlice(allocator, "\n");
        try out.appendSlice(allocator, detail_blocks);
        try out.appendSlice(allocator, "\n");
    }

    try out.appendSlice(allocator, "\n");
    const heading = try std.fmt.allocPrint(
        allocator,
        "## Milestone {d}: {s}  ({s}, {s})\n\nPer-fixture (vs BASE):\n\n",
        .{ current_totals.number, current_totals.label, current_totals.date, current_totals.commit },
    );
    defer allocator.free(heading);
    try out.appendSlice(allocator, heading);
    try writeDetailBlock(&out, allocator, base_rows, current_rows);

    if (std.fs.path.dirname(HIST_PATH)) |parent| try std.fs.cwd().makePath(parent);
    try std.fs.cwd().writeFile(.{ .sub_path = HIST_PATH, .data = out.items });

    try stderr.print(
        "bench: recorded milestone {d} \"{s}\" to {s}\n",
        .{ current_totals.number, current_totals.label, HIST_PATH },
    );
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stderr_buf: [4096]u8 = undefined;
    var stderr_state = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_state.interface;
    defer stderr.flush() catch {};

    var stdout_buf: [4096]u8 = undefined;
    var stdout_state = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_state.interface;
    defer stdout.flush() catch {};

    if (!engine.COLLECT_METRICS) {
        try stderr.writeAll("bench: build_options.collect_metrics is false, refusing to run\n");
        return error.MetricsDisabled;
    }

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);
    var mode: ReportMode = .default;
    var sort_key: ?SortKey = null;
    var rollup: bool = false;
    // Output channel selector. Default text mode keeps the existing
    // human-readable stderr report exactly as it was. JSON mode additionally
    // emits a structured diff document to stdout (mismatch and match paths
    // both produce a document; updateMode does not). Stderr is unaffected so
    // local-dev readability survives.
    var output_format: OutputFormat = .text;
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
                try stderr.writeAll("usage: bench [--human [s|ms|ns]] [--sort inputs|comps|events|time] [--rollup] [--output=text|json]\n");
                return error.MissingArg;
            }
            sort_key = SortKey.parse(argv[i + 1]) orelse {
                try stderr.print("bench: invalid --sort column: {s}\n", .{argv[i + 1]});
                try stderr.writeAll("valid columns: inputs, comps, events, time\n");
                return error.InvalidArg;
            };
            i += 1;
        } else if (std.mem.eql(u8, arg, "--rollup")) {
            rollup = true;
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            // Equals form, e.g. --output=json. Matches the user-facing
            // convention used by the perf-pr-comment workflow.
            const value = arg["--output=".len..];
            output_format = OutputFormat.parse(value) orelse {
                try stderr.print("bench: invalid --output value: {s}\n", .{value});
                try stderr.writeAll("valid outputs: text, json\n");
                return error.InvalidArg;
            };
        } else if (std.mem.eql(u8, arg, "--output")) {
            // Two-token form for parity with --human/--sort.
            if (i + 1 >= argv.len) {
                try stderr.writeAll("bench: --output requires a format (text|json)\n");
                return error.MissingArg;
            }
            output_format = OutputFormat.parse(argv[i + 1]) orelse {
                try stderr.print("bench: invalid --output value: {s}\n", .{argv[i + 1]});
                try stderr.writeAll("valid outputs: text, json\n");
                return error.InvalidArg;
            };
            i += 1;
        } else {
            try stderr.print("bench: unknown flag: {s}\n", .{arg});
            try stderr.writeAll("usage: bench [--human [s|ms|ns]] [--sort inputs|comps|events|time] [--rollup] [--output=text|json]\n");
            return error.UnknownFlag;
        }
    }

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    try writeHeader(&output, allocator);

    var total_wall_ns: u64 = 0;
    var total_drive_ns: u64 = 0;
    var total_events: u64 = 0;
    var total_vectors: u64 = 0;
    var total_allocs: u64 = 0;
    var total_bytes: u64 = 0;

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
        total_drive_ns += row.drive_ns;
        total_events += row.metrics.events_popped;
        total_vectors += row.vectors;
        total_allocs += row.alloc_metrics.allocs;
        total_bytes += row.alloc_metrics.bytes;

        try writeRow(&output, allocator, row);
        sorted_rows.appendAssumeCapacity(.{ .row = row, .elapsed_ns = elapsed_ns });
    }

    if (sort_key) |key| {
        std.mem.sort(SortedRow, sorted_rows.items, key, sortDesc);
    }

    if (rollup) {
        // Group rows by family (suffix-match for adders; otherwise prefix
        // before the first underscore). Aggregate counts; track max for
        // peak_queue since it's per-iteration, not per-fixture.
        var by_family = std.StringHashMap(RollupRow).init(allocator);
        defer by_family.deinit();
        for (sorted_rows.items) |entry| {
            const fam = familyOf(entry.row.name);
            const gop = try by_family.getOrPut(fam);
            if (!gop.found_existing) {
                gop.value_ptr.* = .{ .family = fam };
            }
            gop.value_ptr.fixtures += 1;
            gop.value_ptr.vectors += entry.row.vectors;
            gop.value_ptr.events_popped += entry.row.metrics.events_popped;
            gop.value_ptr.events_committed += entry.row.metrics.events_committed;
            if (entry.row.metrics.peak_queue > gop.value_ptr.peak_queue) {
                gop.value_ptr.peak_queue = entry.row.metrics.peak_queue;
            }
            gop.value_ptr.allocs += entry.row.alloc_metrics.allocs;
            gop.value_ptr.bytes += entry.row.alloc_metrics.bytes;
            gop.value_ptr.drive_ns += entry.row.drive_ns;
        }

        // Stable alphabetical order — rollup output should diff cleanly
        // regardless of --sort.
        var rollup_rows: std.ArrayList(RollupRow) = .{};
        defer rollup_rows.deinit(allocator);
        var it = by_family.iterator();
        while (it.next()) |kv| try rollup_rows.append(allocator, kv.value_ptr.*);
        std.mem.sort(RollupRow, rollup_rows.items, {}, struct {
            fn lessThan(_: void, lhs: RollupRow, rhs: RollupRow) bool {
                return std.mem.lessThan(u8, lhs.family, rhs.family);
            }
        }.lessThan);

        for (rollup_rows.items) |r| {
            var vec_buf: [64]u8 = undefined;
            var ev_buf: [64]u8 = undefined;
            var alloc_buf: [64]u8 = undefined;
            var bytes_buf: [64]u8 = undefined;
            const vec_s = try formatCount(&vec_buf, r.vectors, "vecs", false);
            const ev_s = try formatCount(&ev_buf, r.events_popped, "events", false);
            const alloc_s = try formatCount(&alloc_buf, r.allocs, "allocs", false);
            const bytes_s = try formatCount(&bytes_buf, r.bytes, "bytes", false);
            const pop_eff_pct = if (r.events_popped > 0)
                100.0 * @as(f64, @floatFromInt(r.events_committed)) /
                    @as(f64, @floatFromInt(r.events_popped))
            else
                0.0;
            const drive_ms = @as(f64, @floatFromInt(r.drive_ns)) / std.time.ns_per_ms;
            try stderr.print(
                "bench rollup: {s: <10}  {d: >3} fix  {s: >12}  {s: >15}  {d: >3} peak  {s: >14}  {s: >14}  {d: >5.1}% pop  {d: >9.2} ms drv\n",
                .{ r.family, r.fixtures, vec_s, ev_s, r.peak_queue, alloc_s, bytes_s, pop_eff_pct, drive_ms },
            );
        }
    } else for (sorted_rows.items) |entry| {
        const row = entry.row;
        const elapsed_ns = entry.elapsed_ns;
        const elapsed_ns_f = @as(f64, @floatFromInt(elapsed_ns));
        const drive_ns_f = @as(f64, @floatFromInt(row.drive_ns));
        // Throughput is computed from drive_ns, not elapsed_ns, so the per-
        // fixture rates reflect engine work alone. The parser, validator and
        // topology builder run once per fixture and used to make small
        // circuits look ~1000x slower than they actually are.
        const drive_s = drive_ns_f / std.time.ns_per_s;
        const vecs_per_sec = if (drive_s > 0)
            @as(f64, @floatFromInt(row.vectors)) / drive_s
        else
            0.0;
        const events_per_sec = if (drive_s > 0)
            @as(f64, @floatFromInt(row.metrics.events_popped)) / drive_s
        else
            0.0;
        const pop_eff_pct = if (row.metrics.events_popped > 0)
            100.0 * @as(f64, @floatFromInt(row.metrics.events_committed)) /
                @as(f64, @floatFromInt(row.metrics.events_popped))
        else
            0.0;
        const ticks_per_vec = if (row.vectors > 0)
            @as(f64, @floatFromInt(row.metrics.final_time)) /
                @as(f64, @floatFromInt(row.vectors))
        else
            0.0;

        switch (mode) {
            .default => {
                const elapsed_ms = elapsed_ns_f / std.time.ns_per_ms;
                const drive_ms = drive_ns_f / std.time.ns_per_ms;
                const ns_per_vec = if (row.vectors > 0)
                    drive_ns_f / @as(f64, @floatFromInt(row.vectors))
                else
                    0.0;
                const ns_per_event = if (row.metrics.events_popped > 0)
                    drive_ns_f / @as(f64, @floatFromInt(row.metrics.events_popped))
                else
                    0.0;
                try stderr.print(
                    "bench: {s: <24} {d: >6} vecs  {d: >9.3} ms (drv {d: >8.3})  {d: >9.1} ns/vec  {d: >6.1} ns/event  {d: >5.1}% pop  {d: >6.1} t/vec\n",
                    .{ row.name, row.vectors, elapsed_ms, drive_ms, ns_per_vec, ns_per_event, pop_eff_pct, ticks_per_vec },
                );
            },
            .human => |unit| {
                var count_buf: [64]u8 = undefined;
                var time_buf: [48]u8 = undefined;
                var drive_buf: [48]u8 = undefined;
                var vec_rate_buf: [48]u8 = undefined;
                var event_rate_buf: [48]u8 = undefined;
                var allocs_buf: [64]u8 = undefined;
                var bytes_buf: [64]u8 = undefined;
                var pop_buf: [16]u8 = undefined;
                var ticks_buf: [24]u8 = undefined;
                // with_raw=false on per-fixture rows — the parenthetical raw
                // value bloats each cell width without adding signal. Totals
                // line still uses with_raw=true because aggregates benefit
                // from exact counts.
                const count_s = try formatCount(&count_buf, row.vectors, "vecs", false);
                const time_s = try formatTimeIn(&time_buf, elapsed_ns, unit);
                const drive_s_str = try formatTimeIn(&drive_buf, row.drive_ns, unit);
                const vec_rate_s = try formatRateIn(&vec_rate_buf, vecs_per_sec, "vec", unit);
                const event_rate_s = try formatRateIn(&event_rate_buf, events_per_sec, "events", unit);
                const allocs_s = try formatCount(&allocs_buf, row.alloc_metrics.allocs, "allocs", false);
                const bytes_s = try formatCount(&bytes_buf, row.alloc_metrics.bytes, "bytes", false);
                const pop_s = try std.fmt.bufPrint(&pop_buf, "{d:.1}% pop", .{pop_eff_pct});
                const ticks_s = try std.fmt.bufPrint(&ticks_buf, "{d:.1} t/vec", .{ticks_per_vec});
                // Widths chosen to fit the widest realistic content per
                // column across all three time units: "1907214000 ns" = 13
                // for time/drv; "2.44e-3 events/ns" = 17 for event_rate;
                // "586.61k bytes" = 13 (a 3-digit thousands value) for bytes.
                // Two-space separators give just enough visual breathing room
                // without padding cells out.
                try stderr.print(
                    "[bench] {s: <16}  {s: >11}  {s: >13} (drv {s: >13})  {s: >15}  {s: >18}  {s: >14}  {s: >14}  {s: >10}  {s: >11}\n",
                    .{ row.name, count_s, time_s, drive_s_str, vec_rate_s, event_rate_s, allocs_s, bytes_s, pop_s, ticks_s },
                );
            },
        }
    }

    switch (mode) {
        .default => {
            const total_ms = @as(f64, @floatFromInt(total_wall_ns)) / std.time.ns_per_ms;
            const drive_ms = @as(f64, @floatFromInt(total_drive_ns)) / std.time.ns_per_ms;
            const drive_pct: f64 = if (total_wall_ns > 0)
                100.0 * @as(f64, @floatFromInt(total_drive_ns)) /
                    @as(f64, @floatFromInt(total_wall_ns))
            else
                0.0;
            try stderr.print(
                "bench: ---  {d} fixtures  {d} vectors  {d} events  {d} allocs  {d} bytes  {d:.3} ms total  ({d:.3} ms drv, {d:.1}% engine)\n",
                .{ fixtures.len, total_vectors, total_events, total_allocs, total_bytes, total_ms, drive_ms, drive_pct },
            );
        },
        .human => |unit| {
            var vec_buf: [64]u8 = undefined;
            var ev_buf: [64]u8 = undefined;
            var alloc_buf: [64]u8 = undefined;
            var bytes_buf: [64]u8 = undefined;
            var time_buf: [48]u8 = undefined;
            var drive_buf: [48]u8 = undefined;
            const vec_s = try formatCount(&vec_buf, total_vectors, "vectors", true);
            const ev_s = try formatCount(&ev_buf, total_events, "events", true);
            const alloc_s = try formatCount(&alloc_buf, total_allocs, "allocs", true);
            const bytes_s = try formatCount(&bytes_buf, total_bytes, "bytes", true);
            const time_s = try formatTimeIn(&time_buf, total_wall_ns, unit);
            const drive_s = try formatTimeIn(&drive_buf, total_drive_ns, unit);
            const drive_pct: f64 = if (total_wall_ns > 0)
                100.0 * @as(f64, @floatFromInt(total_drive_ns)) /
                    @as(f64, @floatFromInt(total_wall_ns))
            else
                0.0;
            try stderr.print(
                "[bench] ---  {d} fixtures   {s}   {s}   {s}   {s}   {s} total ({s} drv, {d:.1}% engine)\n",
                .{ fixtures.len, vec_s, ev_s, alloc_s, bytes_s, time_s, drive_s, drive_pct },
            );
        },
    }

    if (updateMode()) {
        if (std.fs.path.dirname(GOLDEN_PATH)) |parent| try std.fs.cwd().makePath(parent);
        try std.fs.cwd().writeFile(.{ .sub_path = GOLDEN_PATH, .data = output.items });
        try stderr.print("bench: wrote {s}\n", .{GOLDEN_PATH});
        try recordMilestoneIfRequested(allocator, stderr, sorted_rows.items, total_drive_ns);
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

        const expected_rows = parseGoldenRows(allocator, expected) catch |err| {
            // Parser failure shouldn't swallow the regression signal — fall
            // back to the original side-by-side dump so a malformed golden is
            // still debuggable.
            try stderr.print(
                "bench: (failed to parse expected for structured diff: {s}; showing raw dump)\n",
                .{@errorName(err)},
            );
            try stderr.writeAll("--- expected ---\n");
            try stderr.writeAll(expected);
            try stderr.writeAll("--- actual ---\n");
            try stderr.writeAll(output.items);
            return error.GoldenMismatch;
        };
        defer allocator.free(expected_rows);

        var expected_by_name = std.StringHashMap(ParsedRow).init(allocator);
        defer expected_by_name.deinit();
        try expected_by_name.ensureTotalCapacity(@intCast(expected_rows.len));
        for (expected_rows) |er| try expected_by_name.put(er.name, er);

        var actual_by_name = std.StringHashMap(Row).init(allocator);
        defer actual_by_name.deinit();
        try actual_by_name.ensureTotalCapacity(@intCast(sorted_rows.items.len));
        for (sorted_rows.items) |entry| try actual_by_name.put(entry.row.name, entry.row);

        // Count first so the header reads "N fixture(s) changed" before the
        // per-row dump. Walk the fixture manifest (alphabetical) so the diff
        // order is stable regardless of any --sort the user passed in.
        var changed: usize = 0;
        var added: usize = 0;
        var removed: usize = 0;
        for (fixtures) |fixture| {
            const actual = actual_by_name.get(fixture.name) orelse {
                removed += 1;
                continue;
            };
            const exp = expected_by_name.get(fixture.name) orelse {
                added += 1;
                continue;
            };
            if (exp.vectors != actual.vectors or
                exp.components != actual.components or
                exp.events_popped != actual.metrics.events_popped or
                exp.events_committed != actual.metrics.events_committed or
                exp.recalcs != actual.metrics.recalcs or
                exp.peak_queue != actual.metrics.peak_queue or
                exp.final_time != actual.metrics.final_time or
                exp.allocs != actual.alloc_metrics.allocs or
                exp.bytes != actual.alloc_metrics.bytes or
                exp.topology_hash != actual.topology_hash)
            {
                changed += 1;
            }
        }
        try stderr.print(
            "bench: {d} changed, {d} added, {d} removed\n",
            .{ changed, added, removed },
        );

        for (fixtures) |fixture| {
            const actual = actual_by_name.get(fixture.name) orelse continue;
            if (expected_by_name.get(fixture.name)) |exp| {
                try printRowDiff(stderr, fixture.name, exp, actual);
            } else {
                try stderr.print("  + {s} (new fixture, no golden row)\n", .{fixture.name});
            }
        }

        if (output_format == .json) {
            try emitJsonDiff(stdout, &fixtures, &expected_by_name, &actual_by_name, changed, added, removed);
        }
        return error.GoldenMismatch;
    }

    try stderr.writeAll("bench: golden matches\n");
    if (output_format == .json) {
        // Match path: empty fixtures array + zero counts. Keeps consumers
        // (the workflow's table-builder script) able to read a document on
        // every successful run instead of branching on file presence.
        try stdout.writeAll("{\"status\":\"match\",\"summary\":{\"changed\":0,\"added\":0,\"removed\":0},\"fixtures\":[]}\n");
    }
    try recordMilestoneIfRequested(allocator, stderr, sorted_rows.items, total_drive_ns);
}
