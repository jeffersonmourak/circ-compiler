//! circ's compiler front end as a library: parse, resolve, validate, and
//! then compile to a self-contained `.wasm`, render a preview, enumerate a
//! truth table, or analyze for editor tooling — all over an in-memory
//! project, with no disk access when every file is supplied.
//!
//! Root of the `libcirc` module created by `build/frontend_modules.zig`.
//! The CLI is a client of this API; `lib/libcirc/c_api.zig` wraps it in a
//! C ABI for the static library and the wasm build.
const std = @import("std");

pub const parser = @import("parser");
pub const build_info = @import("build_info");
pub const format = @import("format");
pub const full_format = @import("full_format");
pub const diagnostics = @import("diagnostics");
pub const ir_types = @import("ir_types");
pub const engine_session = @import("engine_session");
pub const truth_table_builder = @import("truth_table_builder");
pub const preview_render = @import("preview_render");
pub const analyzer = @import("analyze");
pub const layout = @import("layout");
pub const circuit = @import("circuit");
pub const file_loader = @import("file_loader");

pub const frontend = @import("libcirc/frontend.zig");
pub const modes = @import("libcirc/modes.zig");
pub const json = @import("libcirc/json.zig");

pub const File = frontend.File;
pub const TableFormat = modes.TableFormat;
pub const ValueFormat = modes.ValueFormat;

/// The library has no TTY, so there is no `auto`.
pub const Color = enum { never, always };

pub const truth_table_cap_max: u8 = 24;

pub const Options = struct {
    /// Preview: draw the macro internals instead of a collapsed box.
    expand_macros: bool = false,
    /// Preview: multi-bit LEDs (widths 2..7) as indicator rows.
    expand_display: bool = false,
    /// Preview: ANSI colour.
    color: Color = .never,
    /// Truth table output format.
    format: TableFormat = .markdown,
    /// Truth table cell format.
    value_format: ValueFormat = .binary,
    /// Truth table: hard cap on `sum(input widths)`, 1..24.
    truth_table_cap: u8 = 16,
    /// Truth table: images loaded into root memories by declared name
    /// before any vector is driven, so a rom tabulates as a lookup table.
    preloads: []const engine_session.Preload = &.{},
    /// Compile/preview/truth table: warnings count as errors (status 1).
    warnings_as_errors: bool = false,
};

pub const Request = struct {
    /// A key into `files`, or (hosted targets) a disk path.
    root: []const u8,
    /// The in-memory project; keys are normalised by `file_loader.normalizeKey`.
    files: []const File = &.{},
    options: Options = .{},
};

pub const Status = enum(u32) {
    /// `body` is the artifact, the text, or the JSON.
    ok = 0,
    /// `body` is `{"files":[…],"diagnostics":[…],"symbols":[],"references":[]}`.
    diagnostics = 1,
    /// `body` is `{"error":"…"}`: the request itself was unusable.
    bad_request = 2,
    /// `body` is `{"error":"…"}` (truth table) or the plain refusal text.
    refused = 3,
    out_of_memory = 4,
    /// `body` is `{"error":"<stage>: <ErrName>"}`.
    internal = 5,
};

pub const Outcome = struct {
    status: Status,
    /// From the caller's allocator.
    body: []const u8,
};

fn outcome(allocator: std.mem.Allocator, status: Status, buf: *std.ArrayList(u8)) std.mem.Allocator.Error!Outcome {
    return .{ .status = status, .body = try buf.toOwnedSlice(allocator) };
}

fn internal(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), failure: frontend.Failure) std.mem.Allocator.Error!Outcome {
    buf.clearRetainingCapacity();
    const message = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ failure.stage.cliLabel(), @errorName(failure.cause) });
    try json.writeError(buf.writer(allocator), message);
    return outcome(allocator, .internal, buf);
}

/// Run the front end for a compile-like mode; `null` means it succeeded
/// with no blocking diagnostics and `front` is populated.
fn runFront(allocator: std.mem.Allocator, req: Request, route: frontend.Route, front: *frontend.Front, buf: *std.ArrayList(u8)) std.mem.Allocator.Error!?Outcome {
    var failure: frontend.Failure = undefined;
    front.* = frontend.run(allocator, req.root, req.files, route, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RootLoadFailed => {
            const message = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ failure.stage.cliLabel(), @errorName(failure.cause) });
            try json.writeError(buf.writer(allocator), message);
            return try outcome(allocator, .bad_request, buf);
        },
        error.ParseFailed => {
            const key = file_loader.normalizeKey(allocator, req.root) catch req.root;
            try json.writeSyntaxFailure(allocator, buf.writer(allocator), key, failure.cause);
            return try outcome(allocator, .diagnostics, buf);
        },
        else => return try internal(allocator, buf, failure),
    };
    // A recovered syntax error is still an error: the parser dropped the
    // declaration it could not read, so the artifact would silently lack
    // it. (The CLI compiles such a file today; the library refuses.)
    const syntax_errors = front.ast_file.errors.len > 0;
    if (syntax_errors or front.errors > 0 or (req.options.warnings_as_errors and front.warnings > 0)) {
        try json.writeDiagnostics(allocator, buf.writer(allocator), front);
        return try outcome(allocator, .diagnostics, buf);
    }
    return null;
}

/// `--analyze`: the editor-facing JSON for the root and its overlay.
pub fn analyze(allocator: std.mem.Allocator, req: Request) std.mem.Allocator.Error!Outcome {
    var buf: std.ArrayList(u8) = .{};
    const overlay = try frontend.buildOverlay(allocator, req.files);
    const analysis = modes.analyze(allocator, req.root, overlay) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        const message = try std.fmt.allocPrint(allocator, "analyze: {s}", .{@errorName(err)});
        try json.writeError(buf.writer(allocator), message);
        return outcome(allocator, .internal, &buf);
    };
    try modes.renderAnalysis(buf.writer(allocator), analysis);
    return outcome(allocator, .ok, &buf);
}

/// `circ-compile in.circ -o out.wasm`: the self-contained `.wasm` bytes.
pub fn compile(allocator: std.mem.Allocator, req: Request) std.mem.Allocator.Error!Outcome {
    var buf: std.ArrayList(u8) = .{};
    var front: frontend.Front = undefined;
    if (try runFront(allocator, req, .project_if_imports, &front, &buf)) |early| return early;
    var failure: frontend.Failure = undefined;
    const wasm = modes.compile(allocator, &front, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Failed => return internal(allocator, &buf, failure),
    };
    return .{ .status = .ok, .body = wasm };
}

/// `--preview`: the ASCII schematic.
pub fn preview(allocator: std.mem.Allocator, req: Request) std.mem.Allocator.Error!Outcome {
    var buf: std.ArrayList(u8) = .{};
    var front: frontend.Front = undefined;
    if (try runFront(allocator, req, .project, &front, &buf)) |early| return early;
    var failure: frontend.Failure = undefined;
    const topology = modes.buildTopology(allocator, &front, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Failed => return internal(allocator, &buf, failure),
    };
    const grid = modes.buildLayout(allocator, topology, .{
        .expand_macros = req.options.expand_macros,
        .expand_display = req.options.expand_display,
    }, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Failed => {
            const message = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ failure.stage.cliLabel(), @errorName(failure.cause) });
            try json.writeError(buf.writer(allocator), message);
            return outcome(allocator, .refused, &buf);
        },
    };
    modes.renderPreview(allocator, buf.writer(allocator), grid, .{
        .color = switch (req.options.color) {
            .never => .never,
            .always => .always,
        },
        .stdout_handle = null,
        .no_color_value = null,
        .expand_display = req.options.expand_display,
    }, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Failed => return internal(allocator, &buf, failure),
    };
    return outcome(allocator, .ok, &buf);
}

/// `--truth-table`: the enumerated table. Releases the engine arena after
/// rendering, so a long-lived host does not accumulate engine memory.
pub fn truthTable(allocator: std.mem.Allocator, req: Request) std.mem.Allocator.Error!Outcome {
    var buf: std.ArrayList(u8) = .{};
    if (req.options.truth_table_cap == 0 or req.options.truth_table_cap > truth_table_cap_max) {
        try json.writeError(buf.writer(allocator), "options.truth_table_cap must be 1..24");
        return outcome(allocator, .bad_request, &buf);
    }
    var front: frontend.Front = undefined;
    if (try runFront(allocator, req, .project, &front, &buf)) |early| return early;
    var failure: frontend.Failure = undefined;
    const topology = modes.buildTopology(allocator, &front, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Failed => return internal(allocator, &buf, failure),
    };
    if (try modes.truthTablePreflight(allocator, topology, req.options.truth_table_cap, req.options.preloads)) |refusal| {
        var text: std.ArrayList(u8) = .{};
        try refusal.write(text.writer(allocator), .{ .flag = "options.truth_table_cap", .cap_max = truth_table_cap_max });
        try json.writeError(buf.writer(allocator), text.items);
        return outcome(allocator, .refused, &buf);
    }
    var table = modes.buildTruthTable(allocator, topology, .{
        .max_input_bits = req.options.truth_table_cap,
        .preloads = req.options.preloads,
    }, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Failed => return internal(allocator, &buf, failure),
    };
    // The table's arena is separate from the engine arena; the engine
    // objects were freed by build()'s own deinit, so the arena can go.
    defer circuit.memory.reset();
    defer table.deinit();
    modes.renderTruthTable(buf.writer(allocator), table, req.options.format, req.options.value_format, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Failed => return internal(allocator, &buf, failure),
    };
    return outcome(allocator, .ok, &buf);
}

pub const Version = struct {
    /// From the VERSION file.
    version: []const u8,
    /// Short git revision at build time, or "unknown".
    revision: []const u8,
    /// `circ.topology.v0.min` format version.
    topology_version: u8,
    /// `circ.topology.v0.full` format version.
    full_version: u8,
    /// The generator the vendored parser came from and its bytecode ABI.
    parser: []const u8,
    /// sha256 of the runtime pasted into `lib/parser/parser.zig` (its header
    /// line 3): the reliable parser-skew signal.
    parser_runtime_sha256: []const u8,
    /// sha256 of `lib/grammar/proto-circ.peg` at build time.
    grammar_sha256: []const u8,
};

pub fn version() Version {
    return .{
        .version = build_info.version,
        .revision = build_info.revision,
        .topology_version = format.VERSION,
        .full_version = full_format.FULL_VERSION,
        .parser = "langlang " ++ parser.runtime.langlang_version ++ " abi=" ++ std.fmt.comptimePrint("{d}", .{parser.runtime.abi_version}),
        .parser_runtime_sha256 = build_info.parser_runtime_sha256,
        .grammar_sha256 = build_info.grammar_sha256,
    };
}

/// One JSON object, keys in `Version` order, no trailing newline.
pub fn writeVersionJson(writer: anytype) !void {
    const v = version();
    try writer.writeAll("{\"version\":");
    try analyzer.writeJsonString(writer, v.version);
    try writer.writeAll(",\"revision\":");
    try analyzer.writeJsonString(writer, v.revision);
    try writer.print(",\"topology_version\":{d},\"full_version\":{d},\"parser\":", .{ v.topology_version, v.full_version });
    try analyzer.writeJsonString(writer, v.parser);
    try writer.writeAll(",\"parser_runtime_sha256\":");
    try analyzer.writeJsonString(writer, v.parser_runtime_sha256);
    try writer.writeAll(",\"grammar_sha256\":");
    try analyzer.writeJsonString(writer, v.grammar_sha256);
    try writer.writeAll("}");
}

test {
    _ = json;
}

test "version reports the topology versions and a 64-hex grammar sha" {
    const v = version();
    try std.testing.expectEqual(format.VERSION, v.topology_version);
    try std.testing.expectEqual(full_format.FULL_VERSION, v.full_version);
    try std.testing.expectEqual(@as(usize, 64), v.grammar_sha256.len);
    try std.testing.expectEqual(@as(usize, 64), v.parser_runtime_sha256.len);
    try std.testing.expect(std.mem.startsWith(u8, v.parser, "langlang "));
}
