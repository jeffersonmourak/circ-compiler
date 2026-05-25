//! Structured analysis surface for the LSP server.
//!
//! `analyze` runs the existing pipeline (scan imports -> cycle check ->
//! resolve bodies -> validate) against an optional in-memory source
//! overlay and returns structured results: the file table, diagnostics,
//! document symbols, and a reference -> definition table. `renderJson`
//! serializes that to the JSON contract the external server consumes.
//!
//! Positions are emitted as the pipeline's native 1-based byte line/col.
//! The server converts to LSP 0-based UTF-16 positions.

const std = @import("std");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const validator_run_project = @import("validator_run_project");
const diagnostics = @import("diagnostics");
const ir = @import("ir_types");
const translate = @import("translate");
const file_loader = @import("file_loader");

/// Re-export so the CLI can build an overlay without importing file_loader.
pub const Overlay = file_loader.Overlay;

pub const Range = struct {
    start_line: u32,
    start_col: u32,
    end_line: u32,
    end_col: u32,
};

pub const Related = struct {
    file_id: u32,
    range: Range,
    message: []const u8,
};

pub const Diagnostic = struct {
    file_id: u32,
    severity: []const u8,
    code: []const u8,
    range: Range,
    message: []const u8,
    related: []const Related,
};

pub const FileEntry = struct {
    file_id: u32,
    path: []const u8,
};

pub const Symbol = struct {
    file_id: u32,
    name: []const u8,
    kind: []const u8,
    width: u8,
    range: Range,
};

pub const Reference = struct {
    file_id: u32,
    range: Range,
    target_file: u32,
    target_range: Range,
    hover: []const u8,
};

pub const Analysis = struct {
    files: []const FileEntry,
    diagnostics: []const Diagnostic,
    symbols: []const Symbol,
    references: []const Reference,
};

fn rangeFromSpan(span: anytype) Range {
    return .{
        .start_line = span.start_line,
        .start_col = span.start_col,
        .end_line = span.end_line,
        .end_col = span.end_col,
    };
}

fn severityString(level: diagnostics.DiagnosticLevel) []const u8 {
    return switch (level) {
        .err => "error",
        .warning => "warning",
    };
}

fn anyError(items: []const diagnostics.Diagnostic) bool {
    for (items) |d| if (d.level == .err) return true;
    return false;
}

fn appendDiag(allocator: std.mem.Allocator, list: *std.ArrayList(Diagnostic), d: diagnostics.Diagnostic) !void {
    var related: std.ArrayList(Related) = .{};
    for (d.notes) |note| {
        try related.append(allocator, .{
            .file_id = note.span.file_id,
            .range = rangeFromSpan(note.span),
            .message = note.message,
        });
    }
    try list.append(allocator, .{
        .file_id = d.span.file_id,
        .severity = severityString(d.level),
        .code = @tagName(d.code),
        .range = rangeFromSpan(d.span),
        .message = d.message,
        .related = try related.toOwnedSlice(allocator),
    });
}

/// Invert offsetToLineCol: walk the source to the byte offset of a
/// 1-based (line, col). Used by truncation detection to compare how far
/// the parser consumed against the file's real content extent.
fn lineColToOffset(source: []const u8, line: u32, col: u32) usize {
    var cur_line: u32 = 1;
    var cur_col: u32 = 1;
    var idx: usize = 0;
    while (idx < source.len) : (idx += 1) {
        if (cur_line == line and cur_col == col) return idx;
        if (source[idx] == '\n') {
            cur_line += 1;
            cur_col = 1;
        } else {
            cur_col += 1;
        }
    }
    return source.len;
}

/// Emit a syntax diagnostic for a file the parser rejects. A hard parse
/// failure carries a labeled ParsingError (position + message) surfaced by
/// the shim, so the diagnostic lands at the precise stall point. A rare
/// success-with-truncation is caught by the consumed-extent check below.
/// Returns null for clean or empty files.
fn truncationDiag(allocator: std.mem.Allocator, file_id: u32, source: []const u8) !?Diagnostic {
    if (std.mem.trim(u8, source, " \t\r\n").len == 0) return null;

    var failure = translate.ParseFailure{ .start_line = 0, .start_col = 0, .end_line = 0, .end_col = 0, .message = "" };
    const file = translate.parseSourceCapturing(allocator, file_id, source, &failure) catch {
        // start_line stays 0 only when no located error was produced (a
        // post-parse translate failure); fall back to a generic message.
        if (failure.start_line != 0) {
            // Guarantee a non-empty range so the editor highlights a span.
            var end_col = failure.end_col;
            if (failure.end_line == failure.start_line and end_col <= failure.start_col) end_col = failure.start_col + 1;
            return Diagnostic{
                .file_id = file_id,
                .severity = "error",
                .code = "syntax",
                .range = .{ .start_line = failure.start_line, .start_col = failure.start_col, .end_line = failure.end_line, .end_col = end_col },
                .message = if (failure.message.len > 0) failure.message else "syntax error",
                .related = &.{},
            };
        }
        return Diagnostic{
            .file_id = file_id,
            .severity = "error",
            .code = "syntax",
            .range = .{ .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 2 },
            .message = "syntax error: unable to parse file",
            .related = &.{},
        };
    };

    const end_line = file.span.end_line;
    const end_col = file.span.end_col;
    const ast_end = lineColToOffset(source, end_line, end_col);
    const trimmed_len = std.mem.trimRight(u8, source, " \t\r\n").len;
    if (ast_end < trimmed_len) {
        return Diagnostic{
            .file_id = file_id,
            .severity = "error",
            .code = "syntax",
            .range = .{ .start_line = end_line, .start_col = end_col, .end_line = end_line, .end_col = end_col + 1 },
            .message = "syntax error: unexpected input here (expected a declaration)",
            .related = &.{},
        };
    }
    return null;
}

pub fn analyze(
    allocator: std.mem.Allocator,
    root_path: []const u8,
    overlay: ?Overlay,
) !Analysis {
    var files: std.ArrayList(FileEntry) = .{};
    var diags: std.ArrayList(Diagnostic) = .{};
    var symbols: std.ArrayList(Symbol) = .{};
    var references: std.ArrayList(Reference) = .{};

    const scan_result = try scan_imports.scanProjectImportsWithOverlay(allocator, root_path, overlay);
    for (scan_result.file_paths, 0..) |p, i| {
        try files.append(allocator, .{ .file_id = @intCast(i), .path = p });
    }
    for (scan_result.diagnostics.items) |d| try appendDiag(allocator, &diags, d);

    const cycle_result = try import_cycle.analyzeImports(allocator, scan_result.file_paths, scan_result.import_table);
    for (cycle_result.diagnostics.items) |d| try appendDiag(allocator, &diags, d);

    // A cycle breaks the topological order, so body resolution can loop or
    // read partial state. Resolve and validate only when the graph is sound.
    if (!anyError(cycle_result.diagnostics.items)) {
        var project_diag = diagnostics.initDiagnosticList();
        const project = try resolve_bodies.resolveBodiesWithOverlay(
            allocator,
            scan_result.file_paths,
            scan_result.import_table,
            cycle_result.topo_order,
            &project_diag,
            overlay,
        );
        for (project_diag.items) |d| try appendDiag(allocator, &diags, d);

        const validator_diag = try validator_run_project.run(allocator, &project);
        for (validator_diag.items) |d| try appendDiag(allocator, &diags, d);

        try collectSymbolsAndReferences(allocator, &project, &symbols, &references);
    }

    // Truncation detection over user-authored (non-builtin) files.
    for (scan_result.file_paths, 0..) |p, i| {
        if (std.mem.startsWith(u8, p, file_loader.builtin_path_prefix)) continue;
        const loaded = file_loader.loadFileWithOverlay(allocator, p, overlay) catch continue;
        if (try truncationDiag(allocator, @intCast(i), loaded.source)) |td| {
            try diags.append(allocator, td);
        }
    }

    return .{
        .files = try files.toOwnedSlice(allocator),
        .diagnostics = try diags.toOwnedSlice(allocator),
        .symbols = try symbols.toOwnedSlice(allocator),
        .references = try references.toOwnedSlice(allocator),
    };
}

fn primKindName(p: ir.PrimitiveKind) []const u8 {
    return switch (p) {
        .and_gate => "and",
        .not_gate => "not",
        .led => "led",
        .wire => "wire",
        .input_pin => "input",
        .output_pin => "output",
    };
}

/// Document-symbol kind for a component, or null for kinds that are not
/// user-meaningful as outline entries (wires, the input/output pin
/// primitives already covered by module.inputs/outputs, and the
/// synthesized slice/concat shape kinds).
fn symbolKind(kind: ir.ComponentKind) ?[]const u8 {
    return switch (kind) {
        .primitive => |p| switch (p) {
            .and_gate => "and",
            .not_gate => "not",
            .led => "led",
            .wire, .input_pin, .output_pin => null,
        },
        .sub_circuit_ref, .unresolved_name => "instance",
        .slice, .concat => null,
    };
}

fn componentRangeById(module: *const ir.Module, id: ir.ComponentId) ?Range {
    for (module.components) |c| {
        if (c.id.value == id.value) return rangeFromSpan(c.span);
    }
    return null;
}

fn hoverForComponent(allocator: std.mem.Allocator, module: *const ir.Module, id: ir.ComponentId) ![]const u8 {
    for (module.components) |c| {
        if (c.id.value != id.value) continue;
        const kname = switch (c.kind) {
            .primitive => |p| primKindName(p),
            .sub_circuit_ref => |r| r.name,
            .unresolved_name => |n| n,
            .slice => "slice",
            .concat => "concat",
        };
        const name = c.instance_name orelse "";
        if (c.width > 1) return std.fmt.allocPrint(allocator, "{s}[{d}] {s}", .{ kname, c.width, name });
        return std.fmt.allocPrint(allocator, "{s} {s}", .{ kname, name });
    }
    return "";
}

/// Walk each resolved module to emit document symbols (inputs, outputs,
/// user-meaningful components) and a reference -> definition table. Each
/// connection becomes a navigable reference from its value site to the
/// source component's declaration; each non-builtin import alias links to
/// the imported file. Spans report against effectiveSourceFileId so
/// definitions land in user-written source, not specialization stubs.
fn collectSymbolsAndReferences(
    allocator: std.mem.Allocator,
    project: *const ir.Project,
    symbols: *std.ArrayList(Symbol),
    references: *std.ArrayList(Reference),
) !void {
    for (project.files) |*module| {
        const fid = module.effectiveSourceFileId().value;

        for (module.inputs) |in| {
            try symbols.append(allocator, .{
                .file_id = fid,
                .name = in.name,
                .kind = "input",
                .width = in.width,
                .range = rangeFromSpan(in.span),
            });
        }
        for (module.outputs) |out| {
            try symbols.append(allocator, .{
                .file_id = fid,
                .name = out.name,
                .kind = "output",
                .width = out.width,
                .range = rangeFromSpan(out.span),
            });
        }
        for (module.components) |c| {
            const ks = symbolKind(c.kind) orelse continue;
            const name = c.instance_name orelse continue;
            try symbols.append(allocator, .{
                .file_id = fid,
                .name = name,
                .kind = ks,
                .width = c.width,
                .range = rangeFromSpan(c.span),
            });
        }

        for (module.connections) |conn| {
            const target_range = componentRangeById(module, conn.from.component) orelse continue;
            try references.append(allocator, .{
                .file_id = fid,
                .range = rangeFromSpan(conn.span),
                .target_file = fid,
                .target_range = target_range,
                .hover = try hoverForComponent(allocator, module, conn.from.component),
            });
        }
    }

    for (project.import_table) |imp| {
        if (imp.target_file.value >= project.file_paths.len) continue;
        const target_path = project.file_paths[imp.target_file.value];
        if (std.mem.startsWith(u8, target_path, file_loader.builtin_path_prefix)) continue;
        try references.append(allocator, .{
            .file_id = imp.span.file_id,
            .range = rangeFromSpan(imp.span),
            .target_file = imp.target_file.value,
            .target_range = .{ .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 1 },
            .hover = imp.alias,
        });
    }
}

// ---------- JSON rendering ----------

fn writeJsonString(writer: anytype, s: []const u8) !void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

fn writeRange(writer: anytype, r: Range) !void {
    try writer.print(
        "{{\"start_line\":{d},\"start_col\":{d},\"end_line\":{d},\"end_col\":{d}}}",
        .{ r.start_line, r.start_col, r.end_line, r.end_col },
    );
}

pub fn renderJson(writer: anytype, a: Analysis) !void {
    try writer.writeAll("{\"files\":[");
    for (a.files, 0..) |f, i| {
        if (i != 0) try writer.writeByte(',');
        try writer.print("{{\"file_id\":{d},\"path\":", .{f.file_id});
        try writeJsonString(writer, f.path);
        try writer.writeByte('}');
    }

    try writer.writeAll("],\"diagnostics\":[");
    for (a.diagnostics, 0..) |d, i| {
        if (i != 0) try writer.writeByte(',');
        try writer.print("{{\"file_id\":{d},\"severity\":", .{d.file_id});
        try writeJsonString(writer, d.severity);
        try writer.writeAll(",\"code\":");
        try writeJsonString(writer, d.code);
        try writer.writeAll(",\"range\":");
        try writeRange(writer, d.range);
        try writer.writeAll(",\"message\":");
        try writeJsonString(writer, d.message);
        try writer.writeAll(",\"related\":[");
        for (d.related, 0..) |rel, j| {
            if (j != 0) try writer.writeByte(',');
            try writer.print("{{\"file_id\":{d},\"range\":", .{rel.file_id});
            try writeRange(writer, rel.range);
            try writer.writeAll(",\"message\":");
            try writeJsonString(writer, rel.message);
            try writer.writeByte('}');
        }
        try writer.writeAll("]}");
    }

    try writer.writeAll("],\"symbols\":[");
    for (a.symbols, 0..) |s, i| {
        if (i != 0) try writer.writeByte(',');
        try writer.print("{{\"file_id\":{d},\"name\":", .{s.file_id});
        try writeJsonString(writer, s.name);
        try writer.writeAll(",\"kind\":");
        try writeJsonString(writer, s.kind);
        try writer.print(",\"width\":{d},\"range\":", .{s.width});
        try writeRange(writer, s.range);
        try writer.writeByte('}');
    }

    try writer.writeAll("],\"references\":[");
    for (a.references, 0..) |rf, i| {
        if (i != 0) try writer.writeByte(',');
        try writer.print("{{\"file_id\":{d},\"range\":", .{rf.file_id});
        try writeRange(writer, rf.range);
        try writer.print(",\"target_file\":{d},\"target_range\":", .{rf.target_file});
        try writeRange(writer, rf.target_range);
        try writer.writeAll(",\"hover\":");
        try writeJsonString(writer, rf.hover);
        try writer.writeByte('}');
    }

    try writer.writeAll("]}\n");
}

// ---------- Tests ----------

test "analyze: clean circuit has no error diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var overlay = Overlay{};
    try overlay.put(a, "/virtual/and.circ", "input a\ninput b\nand g(a=a, b=b)\noutput out(in=g.out)\n");

    const result = try analyze(a, "/virtual/and.circ", overlay);
    for (result.diagnostics) |d| {
        try std.testing.expect(!std.mem.eql(u8, d.severity, "error"));
    }
    try std.testing.expect(result.files.len >= 1);
}

test "analyze: truncated input yields a syntax diagnostic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var overlay = Overlay{};
    try overlay.put(a, "/virtual/broken.circ", "input a\nand g(a=\n");

    const result = try analyze(a, "/virtual/broken.circ", overlay);
    var found_syntax = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.code, "syntax")) found_syntax = true;
    }
    try std.testing.expect(found_syntax);
}

test "analyze: undeclared name surfaces E001" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var overlay = Overlay{};
    try overlay.put(a, "/virtual/undeclared.circ", "input a\nmystery u1(in=a)\noutput out(in=u1.out)\n");

    const result = try analyze(a, "/virtual/undeclared.circ", overlay);
    var found_e001 = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.code, "E001")) found_e001 = true;
    }
    try std.testing.expect(found_e001);
}

test "analyze: emits symbols and reference links" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var overlay = Overlay{};
    try overlay.put(a, "/virtual/and.circ", "input a\ninput b\nand g(a=a, b=b)\noutput out(in=g.out)\n");

    const result = try analyze(a, "/virtual/and.circ", overlay);

    var has_input_a = false;
    var has_gate_g = false;
    for (result.symbols) |s| {
        if (std.mem.eql(u8, s.name, "a") and std.mem.eql(u8, s.kind, "input")) has_input_a = true;
        if (std.mem.eql(u8, s.name, "g") and std.mem.eql(u8, s.kind, "and")) has_gate_g = true;
    }
    try std.testing.expect(has_input_a);
    try std.testing.expect(has_gate_g);
    try std.testing.expect(result.references.len >= 3);
}

test "analyze: garbage input yields a syntax diagnostic, not a failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var overlay = Overlay{};
    try overlay.put(a, "/virtual/garbage.circ", "%%% not circ at all %%%");

    // Must return a result (not an error): a hard parse failure is reported
    // as a diagnostic, it does not abort the analysis.
    const result = try analyze(a, "/virtual/garbage.circ", overlay);
    var found_syntax = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.code, "syntax")) found_syntax = true;
    }
    try std.testing.expect(found_syntax);
}

test "analyze: empty input resolves cleanly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var overlay = Overlay{};
    try overlay.put(a, "/virtual/empty.circ", "");

    const result = try analyze(a, "/virtual/empty.circ", overlay);
    for (result.diagnostics) |d| {
        try std.testing.expect(!std.mem.eql(u8, d.severity, "error"));
    }
}

test "analyze: syntax diagnostic carries a located message" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var overlay = Overlay{};
    try overlay.put(a, "/virtual/trunc.circ", "input a\nand g(a=");

    const result = try analyze(a, "/virtual/trunc.circ", overlay);
    var found = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.code, "syntax")) {
            // The labeled ParsingError gives a precise message and a
            // location beyond line 1, not the generic fallback at 1:1.
            try std.testing.expect(std.mem.indexOf(u8, d.message, "expected") != null);
            try std.testing.expect(d.range.start_line >= 2);
            found = true;
        }
    }
    try std.testing.expect(found);
}
