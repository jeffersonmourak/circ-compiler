const std = @import("std");
const cli_args = @import("cli_args");
const translate = @import("translate");
const resolver = @import("resolver");
const diagnostics = @import("diagnostics");
const validator_run = @import("validator_run");
const validator_run_project = @import("validator_run_project");
const emit_main = @import("emit_main");
const inspect_dump = @import("inspect_dump");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");
const serializer = @import("serializer");
const full_serializer = @import("full_serializer");
const section_writer = @import("section_writer");
const runtime_embed = @import("runtime_embed");
const preview_dump = @import("preview_dump");
const layout_orchestrator = @import("layout_orchestrator");
const preview_render = @import("preview_render");
const truth_table_builder = @import("truth_table_builder");
const truth_table_markdown = @import("truth_table_markdown");
const truth_table_csv = @import("truth_table_csv");
const truth_table_json = @import("truth_table_json");

fn makePathAny(path: []const u8) !void {
    if (!std.fs.path.isAbsolute(path)) {
        try std.fs.cwd().makePath(path);
        return;
    }
    var root_dir = try std.fs.openDirAbsolute("/", .{});
    defer root_dir.close();
    try root_dir.makePath(path[1..]);
}

fn writeFileAny(path: []const u8, data: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try makePathAny(parent);
    if (std.fs.path.isAbsolute(path)) {
        var file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(data);
        return;
    }
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

/// Walks `table.rows` looking for any output cell that settled to `.undef`.
/// Writes one diagnostic line per offending cell to `stderr_writer` and
/// returns true if at least one was found. Used by --truth-table --strict to
/// turn "I observed undefined output" from a quiet `?` into a hard exit.
fn scanStrict(table: truth_table_builder.Table, stderr_writer: anytype) !bool {
    var found = false;
    for (table.rows, 0..) |row, row_idx| {
        for (row.outputs, 0..) |out_state, col_idx| {
            if (out_state == .undef) {
                found = true;
                try stderr_writer.print(
                    "truth-table: undefined output at row {d}, output '{s}'\n",
                    .{ row_idx, table.header.outputs[col_idx].name },
                );
            }
        }
    }
    return found;
}

fn parseErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.MissingInput => "missing input path",
        error.MissingOutput => "missing -o <output> for this mode",
        error.UnknownFlag => "unknown flag",
        error.ConflictingModes => "cannot combine --emit-zig and --inspect",
        error.InvalidFlagValue => "invalid flag value",
        else => "invalid arguments",
    };
}

fn countDiagnostics(diagnostic_list: []const diagnostics.Diagnostic) struct { errors: usize, warnings: usize } {
    var errors: usize = 0;
    var warnings: usize = 0;
    for (diagnostic_list) |diagnostic| {
        switch (diagnostic.level) {
            .err => errors += 1,
            .warning => warnings += 1,
        }
    }
    return .{ .errors = errors, .warnings = warnings };
}

fn printDiagnosticSet(
    allocator: std.mem.Allocator,
    writer: anytype,
    input_path: []const u8,
    diagnostic_list: []const diagnostics.Diagnostic,
) !struct { errors: usize, warnings: usize } {
    var errors: usize = 0;
    var warnings: usize = 0;

    for (diagnostic_list) |diagnostic| {
        switch (diagnostic.level) {
            .err => errors += 1,
            .warning => warnings += 1,
        }
        const line = try diagnostics.formatDiagnosticLine(allocator, input_path, diagnostic);
        try writer.writeAll(line);
        try writer.writeByte('\n');

        for (diagnostic.notes) |note| {
            try writer.print(
                "  note: {s}:{d}:{d}: {s}\n",
                .{ input_path, note.span.start_line, note.span.start_col, note.message },
            );
        }
    }

    return .{ .errors = errors, .warnings = warnings };
}

pub fn run(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    stdout_writer: anytype,
    stderr_writer: anytype,
) !u8 {
    const args = cli_args.parse(argv) catch |err| {
        try stderr_writer.print("usage error: {s}\n", .{parseErrorMessage(err)});
        return 2;
    };
    if (args.mode == .inspect and args.output_path != null) {
        try stderr_writer.writeAll("usage error: -o is not valid in --inspect mode\n");
        return 2;
    }

    const source = std.fs.cwd().readFileAlloc(allocator, args.input_path, 16 * 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) {
            try stderr_writer.print("input file not found: {s}\n", .{args.input_path});
            return 2;
        }
        try stderr_writer.print("failed reading input file: {s}\n", .{@errorName(err)});
        return 2;
    };

    const ast_file = translate.parseSource(allocator, 0, source) catch |err| {
        try stderr_writer.print("parse failed: {s}\n", .{@errorName(err)});
        return 1;
    };

    const ir_module = resolver.resolve(allocator, ast_file, 0) catch |err| {
        try stderr_writer.print("resolve failed: {s}\n", .{@errorName(err)});
        return 1;
    };

    const has_imports = ast_file.imports.len > 0;

    var diagnostic_list: diagnostics.DiagnosticList = undefined;
    var maybe_project: ?@import("ir_types").Project = null;

    // Preview and truth_table always go through the project pipeline so implicit
    // builtin-macro usages (e.g. `xor` without an explicit import) get resolved via
    // scan_imports' implicit_builtin path. Compile/emit_zig keep the cheaper
    // has_imports gate to avoid the extra disk I/O on macro-free fixtures (locked
    // by perf-budget tests).
    const needs_project_resolution = args.mode != .inspect and (has_imports or args.mode == .preview or args.mode == .truth_table);

    if (needs_project_resolution) {
        const scan_result = scan_imports.scanProjectImports(allocator, args.input_path) catch |err| {
            try stderr_writer.print("import scan failed: {s}\n", .{@errorName(err)});
            return 1;
        };
        if (scan_result.diagnostics.items.len > 0) {
            const counts_scan = try printDiagnosticSet(allocator, stderr_writer, args.input_path, scan_result.diagnostics.items);
            if (counts_scan.errors > 0) return 1;
        }

        const cycle_result = import_cycle.analyzeImports(allocator, scan_result.file_paths, scan_result.import_table) catch |err| {
            try stderr_writer.print("import cycle analysis failed: {s}\n", .{@errorName(err)});
            return 1;
        };
        if (cycle_result.diagnostics.items.len > 0) {
            const counts_cycle = try printDiagnosticSet(allocator, stderr_writer, args.input_path, cycle_result.diagnostics.items);
            if (counts_cycle.errors > 0) return 1;
        }

        const project = resolve_bodies.resolveBodies(
            allocator,
            scan_result.file_paths,
            scan_result.import_table,
            cycle_result.topo_order,
        ) catch |err| {
            try stderr_writer.print("body resolution failed: {s}\n", .{@errorName(err)});
            return 1;
        };
        maybe_project = project;
        diagnostic_list = validator_run_project.run(allocator, &project) catch |err| {
            try stderr_writer.print("project validation failed: {s}\n", .{@errorName(err)});
            return 1;
        };
    } else {
        diagnostic_list = validator_run.run(allocator, &ir_module) catch |err| {
            try stderr_writer.print("validation failed: {s}\n", .{@errorName(err)});
            return 1;
        };
    }
    defer diagnostic_list.deinit(allocator);

    const counts = countDiagnostics(diagnostic_list.items);

    if (args.mode == .inspect) {
        const ast_dump = try inspect_dump.dumpAstFile(allocator, ast_file);
        const ir_dump = try inspect_dump.dumpIrModule(allocator, ir_module);

        try stdout_writer.writeAll("=== Parse Tree ===\n");
        try stdout_writer.writeAll(ast_dump);
        try stdout_writer.writeAll("\n\n=== Resolved IR ===\n");
        try stdout_writer.writeAll(ir_dump);
        try stdout_writer.writeAll("\n\n=== Diagnostics ===\n");
        _ = try printDiagnosticSet(allocator, stdout_writer, args.input_path, diagnostic_list.items);
        if (diagnostic_list.items.len == 0) try stdout_writer.writeByte('\n');
        try stdout_writer.writeAll("\n=== Summary ===\n");
        try stdout_writer.print("{d} errors, {d} warnings\n", .{ counts.errors, counts.warnings });
        return if (counts.errors > 0) 1 else 0;
    }

    _ = try printDiagnosticSet(allocator, stderr_writer, args.input_path, diagnostic_list.items);

    if (counts.errors > 0 or (args.warnings_as_errors and counts.warnings > 0)) {
        return 1;
    }

    switch (args.mode) {
        .emit_zig => {
            const emitted = blk: {
                if (maybe_project) |*project| {
                    break :blk emit_main.emitProjectSource(allocator, project, .{
                        .source_name = std.fs.path.basename(args.input_path),
                        .compile_timestamp = "2026-05-01T22:00:00Z",
                        .compiler_version = "circ-compiler/dev",
                    }) catch |err| {
                        try stderr_writer.print("emission failed: {s}\n", .{@errorName(err)});
                        return 1;
                    };
                }
                break :blk emit_main.emitModuleSource(allocator, &ir_module, .{
                    .source_name = std.fs.path.basename(args.input_path),
                    .compile_timestamp = "2026-05-01T22:00:00Z",
                    .compiler_version = "circ-compiler/dev",
                }) catch |err| {
                    try stderr_writer.print("emission failed: {s}\n", .{@errorName(err)});
                    return 1;
                };
            };
            writeFileAny(args.output_path.?, emitted) catch |err| {
                try stderr_writer.print("failed writing zig output: {s}\n", .{@errorName(err)});
                return 1;
            };
            return 0;
        },
        .compile => {
            const topology_bytes = blk: {
                if (maybe_project) |*project| {
                    break :blk serializer.serializeProject(allocator, project) catch |err| {
                        try stderr_writer.print("topology serialization failed: {s}\n", .{@errorName(err)});
                        return 1;
                    };
                }
                break :blk serializer.serializeModule(allocator, &ir_module) catch |err| {
                    try stderr_writer.print("topology serialization failed: {s}\n", .{@errorName(err)});
                    return 1;
                };
            };
            defer allocator.free(topology_bytes);

            const full_topology_bytes = blk: {
                if (maybe_project) |*project| {
                    break :blk full_serializer.serializeProjectFull(allocator, project) catch |err| {
                        try stderr_writer.print("full topology serialization failed: {s}\n", .{@errorName(err)});
                        return 1;
                    };
                }
                break :blk full_serializer.serializeModuleFull(allocator, &ir_module) catch |err| {
                    try stderr_writer.print("full topology serialization failed: {s}\n", .{@errorName(err)});
                    return 1;
                };
            };
            defer allocator.free(full_topology_bytes);

            const wasm_bytes = section_writer.combineTwo(
                allocator,
                runtime_embed.runtime_wasm,
                topology_bytes,
                full_topology_bytes,
            ) catch |err| {
                try stderr_writer.print("wasm assembly failed: {s}\n", .{@errorName(err)});
                return 1;
            };
            defer allocator.free(wasm_bytes);

            writeFileAny(args.output_path.?, wasm_bytes) catch |err| {
                try stderr_writer.print("failed writing wasm output: {s}\n", .{@errorName(err)});
                return 1;
            };
            return 0;
        },
        .inspect => unreachable,
        .preview => {
            var topology = if (maybe_project) |*project|
                full_serializer.buildFromProject(allocator, project) catch |err| {
                    try stderr_writer.print("topology build failed: {s}\n", .{@errorName(err)});
                    return 1;
                }
            else
                full_serializer.buildFromModule(allocator, &ir_module) catch |err| {
                    try stderr_writer.print("topology build failed: {s}\n", .{@errorName(err)});
                    return 1;
                };
            defer topology.deinit(allocator);

            const grid = layout_orchestrator.build(allocator, topology, .{ .expand_macros = args.expand_macros }) catch |err| {
                try stderr_writer.print("layout build failed: {s}\n", .{@errorName(err)});
                return 1;
            };

            const no_color = std.process.getEnvVarOwned(allocator, "NO_COLOR") catch null;
            const stdout_handle = std.fs.File.stdout().handle;
            preview_render.render(allocator, stdout_writer, grid, .{
                .color = args.color,
                .stdout_handle = stdout_handle,
                .no_color_value = no_color,
            }) catch |err| {
                try stderr_writer.print("render failed: {s}\n", .{@errorName(err)});
                return 1;
            };
            return 0;
        },
        .truth_table => {
            var topology = if (maybe_project) |*project|
                full_serializer.buildFromProject(allocator, project) catch |err| {
                    try stderr_writer.print("topology build failed: {s}\n", .{@errorName(err)});
                    return 1;
                }
            else
                full_serializer.buildFromModule(allocator, &ir_module) catch |err| {
                    try stderr_writer.print("topology build failed: {s}\n", .{@errorName(err)});
                    return 1;
                };
            defer topology.deinit(allocator);

            var table = truth_table_builder.build(allocator, topology, .{}) catch |err| {
                try stderr_writer.print("truth-table build failed: {s}\n", .{@errorName(err)});
                return 1;
            };
            defer table.deinit();

            (switch (args.truth_table_format) {
                .markdown => truth_table_markdown.render(stdout_writer, table),
                .csv => truth_table_csv.render(stdout_writer, table),
                .json => truth_table_json.render(stdout_writer, table),
            }) catch |err| {
                try stderr_writer.print("render failed: {s}\n", .{@errorName(err)});
                return 1;
            };

            if (args.truth_table_strict) {
                const found_undef = scanStrict(table, stderr_writer) catch |err| {
                    try stderr_writer.print("strict scan failed: {s}\n", .{@errorName(err)});
                    return 1;
                };
                if (found_undef) return 1;
            }
            return 0;
        },
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);
    const stderr_writer = std.fs.File.stderr().deprecatedWriter();
    const stdout_writer = std.fs.File.stdout().deprecatedWriter();

    const exit_code = try run(allocator, argv, stdout_writer, stderr_writer);
    if (exit_code != 0) std.process.exit(exit_code);
}

test "run with --inspect on existing fixture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const argv = [_][]const u8{
        "circ-compile",
        "tests/fixtures/circuits/and_two_inputs.circ",
        "--inspect",
    };
    const exit_code = try run(allocator, &argv, stdout_buf.writer(allocator), stderr_buf.writer(allocator));
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(stdout_buf.items.len > 0);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

const golden = @import("golden");

fn runPreview(allocator: std.mem.Allocator, fixture_path: []const u8, stdout_buf: *std.ArrayList(u8), stderr_buf: *std.ArrayList(u8)) !u8 {
    const argv = [_][]const u8{ "circ-compile", fixture_path, "--preview" };
    return run(allocator, &argv, stdout_buf.writer(allocator), stderr_buf.writer(allocator));
}

test "phase1_preview_primitives_fixture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/chain.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/chain.preview.golden");
}

test "phase1_preview_xor_fixture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/builtin_xor.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/builtin_xor.preview.golden");
}

test "phase1_preview_xnor_fixture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/builtin_xnor.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/builtin_xnor.preview.golden");
}

test "phase1_preview_parse_error_to_stderr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    // E001 is a validation error (unknown component type). Preview emits the
    // diagnostic to stderr and returns non-zero before reaching the dispatch
    // arm — locks the stream-split contract.
    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/E001_undeclared.circ", &stdout_buf, &stderr_buf);
    try std.testing.expect(exit_code != 0);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expect(stderr_buf.items.len > 0);
}

fn runPreviewWithFlags(
    allocator: std.mem.Allocator,
    fixture_path: []const u8,
    extra_flags: []const []const u8,
    stdout_buf: *std.ArrayList(u8),
    stderr_buf: *std.ArrayList(u8),
) !u8 {
    var argv = std.ArrayList([]const u8){};
    defer argv.deinit(allocator);
    try argv.append(allocator, "circ-compile");
    try argv.append(allocator, fixture_path);
    try argv.append(allocator, "--preview");
    for (extra_flags) |f| try argv.append(allocator, f);
    return run(allocator, argv.items, stdout_buf.writer(allocator), stderr_buf.writer(allocator));
}

test "phase3_render_single_gate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/single_gate.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/single_gate.render.golden");
}

test "phase3_render_fan_out" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/fan_out.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/fan_out.render.golden");
}

test "phase3_render_fan_in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/fan_in.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/fan_in.render.golden");
}

test "phase3_render_multi_led" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/multi_led.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/multi_led.render.golden");
}

test "phase3_render_and_of_not_detours_around_inv" {
    // Wire from `a` reaches the AND gate's `a` port two columns away — without
    // the route detour fix, the wire ran straight across row 1 and overdrew
    // the intermediate NOT gate's body. Lock in the detour rendering.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/and_of_not.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/and_of_not.render.golden");
}

test "phase3_render_clean_gated_feedback_leftward" {
    // Two NOT gates form a feedback loop: n1.out→n2.in (forward) and
    // n2.out→n1.in (leftward). The leftward wire must wrap UNDER both gates
    // rather than draw a straight line across their body row.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/clean_gated_feedback.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/clean_gated_feedback.render.golden");
}

test "phase3_render_regression_led_out_drives_gate" {
    // LED's spurious out-port drives an AND gate further right; the
    // resulting routing must stay clear of every component body cell.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/regression_led_out_drives_gate.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/regression_led_out_drives_gate.render.golden");
}

test "phase3_render_edge_single_component_led_loops_back" {
    // LED has an out-port that loops back to an output pin; without the
    // detour the loop wire ran across the LED body row.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreview(allocator, "tests/fixtures/circuits/edge_single_component.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/edge_single_component.render.golden");
}

test "phase3_render_full_adder_from_builtins_expanded" {
    // Stress test for the routing pipeline: 5 XOR macros expanded into NOT
    // and AND primitives, packed into a dense layout. Locks in the
    // tx_dst-fallback (clean wire termination instead of east-then-west
    // backtracking) and the port-aware trunk allocation that keeps `┼`
    // crossings off port-approach columns.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreviewWithFlags(allocator, "tests/fixtures/circuits/full_adder_from_builtins.circ", &.{"--expand-macros"}, &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/full_adder_from_builtins.render.expanded.golden");
}

test "phase3_render_builtin_xor_expanded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreviewWithFlags(allocator, "tests/fixtures/circuits/builtin_xor.circ", &.{"--expand-macros"}, &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/builtin_xor.render.expanded.golden");
}

test "phase3_render_builtin_xnor_expanded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreviewWithFlags(allocator, "tests/fixtures/circuits/builtin_xnor.circ", &.{"--expand-macros"}, &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/builtin_xnor.render.expanded.golden");
}

test "phase3_render_color_always" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreviewWithFlags(allocator, "tests/fixtures/circuits/single_gate.circ", &.{"--color=always"}, &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    // Color-on output contains ANSI escape bytes.
    var saw_esc = false;
    for (stdout_buf.items) |b| {
        if (b == 0x1B) {
            saw_esc = true;
            break;
        }
    }
    try std.testing.expect(saw_esc);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/preview/renders/single_gate.render.color.golden");
}

test "phase3_render_color_never_no_escapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);
    const exit_code = try runPreviewWithFlags(allocator, "tests/fixtures/circuits/single_gate.circ", &.{"--color=never"}, &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    for (stdout_buf.items) |b| try std.testing.expect(b != 0x1B);
}

fn runTruthTable(
    allocator: std.mem.Allocator,
    fixture_path: []const u8,
    stdout_buf: *std.ArrayList(u8),
    stderr_buf: *std.ArrayList(u8),
) !u8 {
    const argv = [_][]const u8{ "circ-compile", fixture_path, "--truth-table" };
    return run(allocator, &argv, stdout_buf.writer(allocator), stderr_buf.writer(allocator));
}

test "truth_table_and_two_inputs_fixture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const exit_code = try runTruthTable(allocator, "tests/fixtures/circuits/and_two_inputs.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/truth_table/and_two_inputs.truth.golden");
}

test "truth_table_xor_fixture_through_macro_pipeline" {
    // XOR exercises buildFromProject (macro expansion via implicit_builtin), not
    // buildFromModule. The truth table must show only the root circuit's a/b/out
    // pins; the inlined or/nand/and bodies emit their own input/output_pin
    // primitives but those carry non-empty origin chains and must be filtered.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const exit_code = try runTruthTable(allocator, "tests/fixtures/circuits/builtin_xor.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/truth_table/builtin_xor.truth.golden");
}

test "truth_table_chain_fixture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const exit_code = try runTruthTable(allocator, "tests/fixtures/circuits/chain.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/truth_table/chain.truth.golden");
}

test "truth_table_rejects_output_path" {
    // -o is only meaningful for compile/emit-zig modes. Truth tables go to stdout.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const argv = [_][]const u8{ "circ-compile", "tests/fixtures/circuits/and_two_inputs.circ", "--truth-table", "-o", "out.txt" };
    const exit_code = try run(allocator, &argv, stdout_buf.writer(allocator), stderr_buf.writer(allocator));
    try std.testing.expectEqual(@as(u8, 2), exit_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expect(stderr_buf.items.len > 0);
}

test "truth_table_propagates_validator_errors_e008" {
    // Combinational loops (E008) are validator errors. The CLI exits before the
    // truth-table arm runs, so the truth-table code itself never has to defend
    // against feedback loops — it relies on this upstream guarantee.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const exit_code = try runTruthTable(allocator, "tests/fixtures/circuits/E008_simple_loop.circ", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 1), exit_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expect(stderr_buf.items.len > 0);
}

fn expectTruthTableGolden(fixture_path: []const u8, golden_path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const exit_code = try runTruthTable(allocator, fixture_path, &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, golden_path);
}

// Primitive coverage — one fixture per simulation primitive that has observable
// boolean behaviour. input_pin / output_pin aren't exercised standalone; they
// appear in every other fixture as the boundary primitives.

test "truth_table_primitive_and" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/and_gate.circ",
        "tests/fixtures/truth_table/primitive_and.truth.golden",
    );
}

test "truth_table_primitive_not" {
    // single_gate.circ is the canonical NOT fixture: input a → not n → output out.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/single_gate.circ",
        "tests/fixtures/truth_table/primitive_not.truth.golden",
    );
}

test "truth_table_primitive_wire" {
    // The wire primitive relays its input dominant-state through to its `out`
    // port. The truth table should be the identity function.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/wire_passthrough.circ",
        "tests/fixtures/truth_table/primitive_wire.truth.golden",
    );
}

test "truth_table_primitive_led" {
    // LED mirrors its input on its `out` port and propagates downstream with
    // the wire delay (per DOCS/simulation-engine.md). The fixture wires
    // input → led → output, so the table is the identity function.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/edge_single_component.circ",
        "tests/fixtures/truth_table/primitive_led.truth.golden",
    );
}

// Built-in coverage — one fixture per macro in lib/resolver/builtin_circ/. XOR
// is already locked by truth_table_xor_fixture_through_macro_pipeline above.

test "truth_table_builtin_nand" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/builtin_nand.circ",
        "tests/fixtures/truth_table/builtin_nand.truth.golden",
    );
}

test "truth_table_builtin_nor" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/builtin_nor.circ",
        "tests/fixtures/truth_table/builtin_nor.truth.golden",
    );
}

test "truth_table_builtin_or" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/builtin_or.circ",
        "tests/fixtures/truth_table/builtin_or.truth.golden",
    );
}

test "truth_table_builtin_xnor" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/builtin_xnor.circ",
        "tests/fixtures/truth_table/builtin_xnor.truth.golden",
    );
}

fn runTruthTableWithFormat(
    allocator: std.mem.Allocator,
    fixture_path: []const u8,
    format_flag: []const u8,
    stdout_buf: *std.ArrayList(u8),
    stderr_buf: *std.ArrayList(u8),
) !u8 {
    const argv = [_][]const u8{ "circ-compile", fixture_path, "--truth-table", format_flag };
    return run(allocator, &argv, stdout_buf.writer(allocator), stderr_buf.writer(allocator));
}

test "truth_table_xor_csv_fixture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const exit_code = try runTruthTableWithFormat(allocator, "tests/fixtures/circuits/builtin_xor.circ", "--format=csv", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/truth_table/builtin_xor.csv.golden");
}

test "truth_table_xor_json_fixture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const exit_code = try runTruthTableWithFormat(allocator, "tests/fixtures/circuits/builtin_xor.circ", "--format=json", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try golden.expectGolden(stdout_buf.items, "tests/fixtures/truth_table/builtin_xor.json.golden");
}

test "truth_table_format_markdown_default_matches_explicit" {
    // --format=markdown is the default; the two invocations must produce
    // byte-identical output. This guards against drift if the default ever
    // changes silently.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var implicit_buf: std.ArrayList(u8) = .{};
    defer implicit_buf.deinit(allocator);
    var explicit_buf: std.ArrayList(u8) = .{};
    defer explicit_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    _ = try runTruthTable(allocator, "tests/fixtures/circuits/builtin_xor.circ", &implicit_buf, &stderr_buf);
    _ = try runTruthTableWithFormat(allocator, "tests/fixtures/circuits/builtin_xor.circ", "--format=markdown", &explicit_buf, &stderr_buf);
    try std.testing.expectEqualStrings(implicit_buf.items, explicit_buf.items);
}

// Boolean arithmetic coverage. Each circuit's truth table was hand-verified
// against the algebraic specification before being locked in as a golden.

test "truth_table_half_adder" {
    // Half adder: (a, b) → (sum, cout). sum = a XOR b; cout = a AND b.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/half_adder.circ",
        "tests/fixtures/truth_table/half_adder.truth.golden",
    );
}

test "truth_table_full_adder" {
    // Full adder: (a, b, cin) → (sum, cout). sum = a XOR b XOR cin;
    // cout = (a AND b) OR ((a XOR b) AND cin). Eight rows enumerating
    // every binary combination of three inputs.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/full_adder_from_builtins.circ",
        "tests/fixtures/truth_table/full_adder.truth.golden",
    );
}

test "truth_table_two_bit_adder" {
    // 2-bit ripple-carry adder: (a1 a0) + (b1 b0) → (cout s1 s0). Sixteen
    // rows. The bit order in input_bits matches declaration order:
    // bit0=a0, bit1=a1, bit2=b0, bit3=b1. The golden was hand-verified
    // against integer addition for every row (e.g. input_bits=0b1111 →
    // a=3, b=3, sum=6 → s0=0, s1=1, cout=1).
    try expectTruthTableGolden(
        "tests/fixtures/circuits/two_bit_adder.circ",
        "tests/fixtures/truth_table/two_bit_adder.truth.golden",
    );
}

// Selector / wide-primitive coverage. mux and demux are the canonical
// "control selects which signal flows where" primitives; the *_2bit
// fixtures exercise the parallel-replication pattern that scales any
// per-bit primitive to a wider operand.

test "truth_table_mux_2to1" {
    // 2-to-1 multiplexer: out = sel ? b : a. 8 rows.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/mux_2to1.circ",
        "tests/fixtures/truth_table/mux_2to1.truth.golden",
    );
}

test "truth_table_demux_1to2" {
    // 1-to-2 demultiplexer. When sel=0, out_a=in and out_b=0; when sel=1,
    // out_a=0 and out_b=in. The unselected output is held at 0 so a
    // downstream consumer can OR multiple demux outputs onto a shared bus
    // without conflicts.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/demux_1to2.circ",
        "tests/fixtures/truth_table/demux_1to2.truth.golden",
    );
}

test "truth_table_and_2bit" {
    // 2-bit bitwise AND: out_i = a_i AND b_i for i in {0, 1}. 16 rows.
    // Exercises N-parallel single-bit primitives — the standard scaling
    // pattern for any per-bit operation.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/and_2bit.circ",
        "tests/fixtures/truth_table/and_2bit.truth.golden",
    );
}

test "truth_table_not_2bit" {
    // 2-bit bitwise NOT: out_i = !a_i. 4 rows.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/not_2bit.circ",
        "tests/fixtures/truth_table/not_2bit.truth.golden",
    );
}

test "truth_table_mux_2bit_2to1" {
    // 2-bit 2-to-1 multiplexer: selects between two 2-bit operands. One
    // single-bit mux per output bit, sharing the inverted-select line.
    // 32 rows. Combines the wide-primitive pattern (parallel per-bit
    // logic) with the selector pattern (sel routes one input to output).
    try expectTruthTableGolden(
        "tests/fixtures/circuits/mux_2bit_2to1.circ",
        "tests/fixtures/truth_table/mux_2bit_2to1.truth.golden",
    );
}

// 3-bit and 4-bit replications of the same patterns. The fixtures are
// parallel: each one is the 2-bit version with the per-bit slice
// repeated. The goldens grow as 2^N where N is the input count, so
// these scale tests verify both the row enumeration and the macro/
// primitive-fanout pipeline at progressively wider sizes.

test "truth_table_and_3bit" {
    // 3-bit bitwise AND: 6 inputs, 3 outputs, 64 rows.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/and_3bit.circ",
        "tests/fixtures/truth_table/and_3bit.truth.golden",
    );
}

test "truth_table_not_3bit" {
    // 3-bit bitwise NOT: 3 inputs, 3 outputs, 8 rows.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/not_3bit.circ",
        "tests/fixtures/truth_table/not_3bit.truth.golden",
    );
}

test "truth_table_mux_3bit_2to1" {
    // 3-bit 2-to-1 multiplexer: 7 inputs (a0..a2, b0..b2, sel), 3 outputs,
    // 128 rows. The shared inverted-select line now fans out to three
    // pick_a* gates instead of two — exercises wider single-source fan-out.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/mux_3bit_2to1.circ",
        "tests/fixtures/truth_table/mux_3bit_2to1.truth.golden",
    );
}

test "truth_table_and_4bit" {
    // 4-bit bitwise AND: 8 inputs, 4 outputs, 256 rows.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/and_4bit.circ",
        "tests/fixtures/truth_table/and_4bit.truth.golden",
    );
}

test "truth_table_not_4bit" {
    // 4-bit bitwise NOT: 4 inputs, 4 outputs, 16 rows.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/not_4bit.circ",
        "tests/fixtures/truth_table/not_4bit.truth.golden",
    );
}

test "truth_table_mux_4bit_2to1" {
    // 4-bit 2-to-1 multiplexer: 9 inputs (a0..a3, b0..b3, sel), 4 outputs,
    // 512 rows. Largest table in the suite; doubles as a stress test for
    // the row-enumeration loop and topology fan-out.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/mux_4bit_2to1.circ",
        "tests/fixtures/truth_table/mux_4bit_2to1.truth.golden",
    );
}

// Multi-bit macro coverage. Each macro (or, xor, nand, nor, xnor) is
// expanded into primitives by the project pipeline; the parallel-bit
// replication then exercises N copies of the macro's expansion within
// the same flat topology. Locks both the macro expansion and the
// origin-field filtering at width.

test "truth_table_or_2bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/or_2bit.circ",
        "tests/fixtures/truth_table/or_2bit.truth.golden",
    );
}

test "truth_table_or_3bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/or_3bit.circ",
        "tests/fixtures/truth_table/or_3bit.truth.golden",
    );
}

test "truth_table_or_4bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/or_4bit.circ",
        "tests/fixtures/truth_table/or_4bit.truth.golden",
    );
}

test "truth_table_xor_2bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/xor_2bit.circ",
        "tests/fixtures/truth_table/xor_2bit.truth.golden",
    );
}

test "truth_table_xor_3bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/xor_3bit.circ",
        "tests/fixtures/truth_table/xor_3bit.truth.golden",
    );
}

test "truth_table_xor_4bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/xor_4bit.circ",
        "tests/fixtures/truth_table/xor_4bit.truth.golden",
    );
}

test "truth_table_nand_2bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/nand_2bit.circ",
        "tests/fixtures/truth_table/nand_2bit.truth.golden",
    );
}

test "truth_table_nand_3bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/nand_3bit.circ",
        "tests/fixtures/truth_table/nand_3bit.truth.golden",
    );
}

test "truth_table_nand_4bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/nand_4bit.circ",
        "tests/fixtures/truth_table/nand_4bit.truth.golden",
    );
}

test "truth_table_nor_2bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/nor_2bit.circ",
        "tests/fixtures/truth_table/nor_2bit.truth.golden",
    );
}

test "truth_table_nor_3bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/nor_3bit.circ",
        "tests/fixtures/truth_table/nor_3bit.truth.golden",
    );
}

test "truth_table_nor_4bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/nor_4bit.circ",
        "tests/fixtures/truth_table/nor_4bit.truth.golden",
    );
}

test "truth_table_xnor_2bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/xnor_2bit.circ",
        "tests/fixtures/truth_table/xnor_2bit.truth.golden",
    );
}

test "truth_table_xnor_3bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/xnor_3bit.circ",
        "tests/fixtures/truth_table/xnor_3bit.truth.golden",
    );
}

test "truth_table_xnor_4bit" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/xnor_4bit.circ",
        "tests/fixtures/truth_table/xnor_4bit.truth.golden",
    );
}

// Multi-bit demux coverage. Each fixture routes an N-bit data input to
// one of two N-bit destinations via a single sel line. The unselected
// destination's bits are all held at 0 — same wired-OR-friendly contract
// as the single-bit demux_1to2.

test "truth_table_demux_2bit_1to2" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/demux_2bit_1to2.circ",
        "tests/fixtures/truth_table/demux_2bit_1to2.truth.golden",
    );
}

test "truth_table_demux_3bit_1to2" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/demux_3bit_1to2.circ",
        "tests/fixtures/truth_table/demux_3bit_1to2.truth.golden",
    );
}

test "truth_table_demux_4bit_1to2" {
    try expectTruthTableGolden(
        "tests/fixtures/circuits/demux_4bit_1to2.circ",
        "tests/fixtures/truth_table/demux_4bit_1to2.truth.golden",
    );
}

// Wider arithmetic coverage. half_adder + full_adder + two_bit_adder
// already cover 1-bit and 2-bit arithmetic; these extend the chain to
// 3 and 4 bits. Each new bit slice is a full adder taking the previous
// bit's carry-out as cin.

test "truth_table_three_bit_adder" {
    // 3-bit adder: 6 inputs, 4 outputs (s0, s1, s2, cout). 64 rows.
    // Hand-verified: a=7 b=7 mask=63 → 14 = 0b1110 → s0=0 s1=1 s2=1 cout=1.
    try expectTruthTableGolden(
        "tests/fixtures/circuits/three_bit_adder.circ",
        "tests/fixtures/truth_table/three_bit_adder.truth.golden",
    );
}

test "truth_table_four_bit_adder" {
    // 4-bit adder: 8 inputs, 5 outputs (s0..s3, cout). 256 rows.
    // Hand-verified: a=8 b=8 mask=136 → 16 = 0b10000 → s0..s3 all 0, cout=1
    // (largest single-bit overflow case in the table).
    try expectTruthTableGolden(
        "tests/fixtures/circuits/four_bit_adder.circ",
        "tests/fixtures/truth_table/four_bit_adder.truth.golden",
    );
}

// scanStrict is unit-tested directly because no parser-valid, validator-
// accepting fixture currently produces .undef under the truth-table mode —
// the validator rejects every shape that would reach an undefined output.
// So we synthesise a Table by hand to exercise both branches.

fn synthTableForStrict(
    arena: *std.heap.ArenaAllocator,
    output_states: []const truth_table_builder.State,
) !truth_table_builder.Table {
    const a = arena.allocator();
    const inputs = try a.alloc(truth_table_builder.PinRef, 1);
    inputs[0] = .{ .name = "a", .component_id = 0 };
    const outputs = try a.alloc(truth_table_builder.PinRef, 1);
    outputs[0] = .{ .name = "out", .component_id = 1 };

    const rows = try a.alloc(truth_table_builder.Row, output_states.len);
    for (output_states, 0..) |state, i| {
        const cell = try a.alloc(truth_table_builder.State, 1);
        cell[0] = state;
        rows[i] = .{ .input_bits = i, .outputs = cell };
    }
    return .{
        .arena = arena.*,
        .header = .{ .inputs = inputs, .outputs = outputs },
        .rows = rows,
    };
}

test "scan_strict_reports_undef_rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    var table = try synthTableForStrict(&arena, &.{ .low, .undef, .high, .undef });
    defer table.deinit();

    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(std.testing.allocator);
    const found = try scanStrict(table, stderr_buf.writer(std.testing.allocator));
    try std.testing.expect(found);
    // Both undef rows should produce diagnostics, neither defined row should.
    const text = stderr_buf.items;
    try std.testing.expect(std.mem.indexOf(u8, text, "row 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "row 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "row 0") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "row 2") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "'out'") != null);
}

test "scan_strict_clean_table_returns_false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    var table = try synthTableForStrict(&arena, &.{ .low, .high });
    defer table.deinit();

    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(std.testing.allocator);
    const found = try scanStrict(table, stderr_buf.writer(std.testing.allocator));
    try std.testing.expect(!found);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

test "truth_table_strict_passes_on_xor" {
    // XOR's truth table is fully defined — strict mode should exit 0 and
    // write nothing to stderr (no diagnostics, no extra noise).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .{};
    defer stderr_buf.deinit(allocator);

    const argv = [_][]const u8{ "circ-compile", "tests/fixtures/circuits/builtin_xor.circ", "--truth-table", "--strict" };
    const exit_code = try run(allocator, &argv, stdout_buf.writer(allocator), stderr_buf.writer(allocator));
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(stdout_buf.items.len > 0);
    // Strict produces no stderr output when the table is fully defined.
    for (stderr_buf.items) |b| {
        if (b != ' ' and b != '\n' and b != '\t') {
            // Allow no non-whitespace characters on stderr.
            try std.testing.expect(false);
        }
    }
}
