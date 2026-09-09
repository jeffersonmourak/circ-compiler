//! Per-mode back halves over a finished `Front`: topology, the `.wasm`
//! artifact, the preview grid and render, the truth table, and analysis.
//! Each step reports a hard error through `Failure` and never prints.
const std = @import("std");
const frontend = @import("frontend.zig");
const serializer = @import("serializer");
const full_serializer = @import("full_serializer");
const full_format = @import("full_format");
const section_writer = @import("section_writer");
const runtime_embed = @import("runtime_embed");
const layout = @import("layout");
const layout_orchestrator = @import("layout_orchestrator");
const preview_render = @import("preview_render");
const truth_table_builder = @import("truth_table_builder");
const truth_table_markdown = @import("truth_table_markdown");
const truth_table_csv = @import("truth_table_csv");
const truth_table_json = @import("truth_table_json");
const analyzer = @import("analyze");

const Front = frontend.Front;
const Failure = frontend.Failure;
const Stage = frontend.Stage;

pub const Failed = error{ Failed, OutOfMemory };

pub const TableFormat = enum { markdown, csv, json };
pub const ValueFormat = enum { binary, hex, decimal };

fn failWith(failure: ?*Failure, stage: Stage, cause: anyerror) Failed {
    if (cause == error.OutOfMemory) return error.OutOfMemory;
    if (failure) |f| f.* = .{ .stage = stage, .cause = cause };
    return error.Failed;
}

/// The full topology (the same structure `--preview`, `--truth-table` and
/// `--sim` build). Caller owns it: `topology.deinit(allocator)`.
pub fn buildTopology(allocator: std.mem.Allocator, front: *const Front, failure: ?*Failure) Failed!full_format.FullTopology {
    if (front.project) |*project| {
        return full_serializer.buildFromProject(allocator, project) catch |err| return failWith(failure, .topology_build, err);
    }
    return full_serializer.buildFromModule(allocator, &front.ir_module) catch |err| return failWith(failure, .topology_build, err);
}

/// The self-contained `.wasm` artifact: the embedded runtime plus both
/// topology sections, byte-identical to what `circ-compile -o` writes.
pub fn compile(allocator: std.mem.Allocator, front: *const Front, failure: ?*Failure) Failed![]u8 {
    const min_bytes = blk: {
        if (front.project) |*project| {
            break :blk serializer.serializeProject(allocator, project) catch |err| return failWith(failure, .topology_serialization, err);
        }
        break :blk serializer.serializeModule(allocator, &front.ir_module) catch |err| return failWith(failure, .topology_serialization, err);
    };
    defer allocator.free(min_bytes);

    const full_bytes = blk: {
        if (front.project) |*project| {
            break :blk full_serializer.serializeProjectFull(allocator, project) catch |err| return failWith(failure, .full_topology_serialization, err);
        }
        break :blk full_serializer.serializeModuleFull(allocator, &front.ir_module) catch |err| return failWith(failure, .full_topology_serialization, err);
    };
    defer allocator.free(full_bytes);

    return section_writer.combineTwo(allocator, runtime_embed.runtime_wasm, min_bytes, full_bytes) catch |err| return failWith(failure, .wasm_assembly, err);
}

pub fn buildLayout(allocator: std.mem.Allocator, topology: full_format.FullTopology, opts: layout.LayoutOptions, failure: ?*Failure) Failed!layout.LayoutGrid {
    return layout_orchestrator.build(allocator, topology, opts) catch |err| return failWith(failure, .layout_build, err);
}

/// LEDs that asked for `expand_display` but sit above the indicator cap
/// (width >= 8): the render falls back to numeric, and the CLI warns.
pub fn countExpandDisplayFallbacks(grid: layout.LayoutGrid) usize {
    var n: usize = 0;
    for (grid.components) |placed| switch (placed.kind) {
        .primitive => |p| if (p == .led and placed.signal_width >= 8) {
            n += 1;
        },
        else => {},
    };
    return n;
}

pub fn renderPreview(allocator: std.mem.Allocator, writer: anytype, grid: layout.LayoutGrid, opts: preview_render.RenderOptions, failure: ?*Failure) Failed!void {
    preview_render.render(allocator, writer, grid, opts) catch |err| return failWith(failure, .render, err);
}

/// Why a truth table is refused before the engine runs. `write` produces
/// the CLI's exact message (no trailing newline); `flag`/`cap_max` name the
/// knob to raise the cap with in the caller's vocabulary.
pub const Refusal = union(enum) {
    too_many_bits: struct { bits: u32, cap: u8 },

    pub const CliText = struct { flag: []const u8, cap_max: u8 };

    pub fn write(self: Refusal, writer: anytype, text: CliText) !void {
        switch (self) {
            .too_many_bits => |t| try writer.print(
                "truth table requires {d} input bits, exceeds cap of {d} (raise with {s}, max {d})",
                .{ t.bits, t.cap, text.flag, text.cap_max },
            ),
        }
    }
};

/// Pre-flight the cap so the caller can give a specific bit-count message
/// instead of the builder's generic `TooManyInputs`.
pub fn truthTablePreflight(topology: full_format.FullTopology, cap: u8) ?Refusal {
    const bits = truth_table_builder.countInputBits(topology);
    if (bits > cap) return .{ .too_many_bits = .{ .bits = bits, .cap = cap } };
    return null;
}

pub fn buildTruthTable(allocator: std.mem.Allocator, topology: full_format.FullTopology, opts: truth_table_builder.BuildOptions, failure: ?*Failure) Failed!truth_table_builder.Table {
    return truth_table_builder.build(allocator, topology, opts) catch |err| return failWith(failure, .truth_table_build, err);
}

pub fn renderTruthTable(writer: anytype, table: truth_table_builder.Table, format: TableFormat, value_format: ValueFormat, failure: ?*Failure) Failed!void {
    (switch (format) {
        .markdown => truth_table_markdown.render(writer, table, switch (value_format) {
            .binary => truth_table_markdown.ValueFormat.binary,
            .hex => .hex,
            .decimal => .decimal,
        }),
        .csv => truth_table_csv.render(writer, table, switch (value_format) {
            .binary => truth_table_csv.ValueFormat.binary,
            .hex => .hex,
            .decimal => .decimal,
        }),
        .json => truth_table_json.render(writer, table, switch (value_format) {
            .binary => truth_table_json.ValueFormat.binary,
            .hex => .hex,
            .decimal => .decimal,
        }),
    }) catch |err| return failWith(failure, .render, err);
}

pub fn analyze(allocator: std.mem.Allocator, root: []const u8, overlay: ?analyzer.Overlay) !analyzer.Analysis {
    return analyzer.analyze(allocator, root, overlay);
}

pub fn renderAnalysis(writer: anytype, a: analyzer.Analysis) !void {
    return analyzer.renderJson(writer, a);
}
