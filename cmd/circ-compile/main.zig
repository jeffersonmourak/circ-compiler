const std = @import("std");
const cli_args = @import("cli_args");
const translate = @import("translate");
const resolver = @import("resolver");
const diagnostics = @import("diagnostics");
const validator_run = @import("validator_run");
const validator_run_project = @import("validator_run_project");
const emit_main = @import("emit_main");
const orchestrator = @import("orchestrator_main");
const inspect_dump = @import("inspect_dump");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");

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

fn parseErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.MissingInput => "missing input path",
        error.MissingOutput => "missing -o <output> for this mode",
        error.UnknownFlag => "unknown flag",
        error.ConflictingModes => "cannot combine --emit-zig and --inspect",
        error.BuildDirInWrongMode => "--build-dir is only valid in compile mode",
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

fn run() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);
    const stderr_writer = std.fs.File.stderr().deprecatedWriter();
    const stdout_writer = std.fs.File.stdout().deprecatedWriter();

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

    if (has_imports and args.mode != .inspect) {
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

    switch (args.mode) {
        .emit_zig => {
            writeFileAny(args.output_path.?, emitted) catch |err| {
                try stderr_writer.print("failed writing zig output: {s}\n", .{@errorName(err)});
                return 1;
            };
            return 0;
        },
        .compile => {
            var orchestrator_result = orchestrator.compile(allocator, emitted, .{
                .output_wasm_path = args.output_path.?,
                .build_dir = args.build_dir,
            }) catch |err| {
                if (err == error.ZigBuildFailed) return 1;
                try stderr_writer.print("compile orchestration failed: {s}\n", .{@errorName(err)});
                return 1;
            };
            defer orchestrator_result.deinit(allocator);
            return 0;
        },
        .inspect => unreachable,
    }
}

pub fn main() !void {
    const exit_code = try run();
    if (exit_code != 0) std.process.exit(exit_code);
}
