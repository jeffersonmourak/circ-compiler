//! The compiler front end, lifted out of the CLI: load the root, parse,
//! resolve, then either the project pipeline (import scan → cycle check →
//! body resolution → project validation) or single-module validation.
//! Never prints; every failure is reported through `Failure` and the
//! diagnostics list, and the caller decides how to surface them.
const std = @import("std");
const translate = @import("translate");
const resolver = @import("resolver");
const ir = @import("ir_types");
const diagnostics = @import("diagnostics");
const validator_run = @import("validator_run");
const validator_run_project = @import("validator_run_project");
const file_loader = @import("file_loader");
const scan_imports = @import("scan_imports");
const import_cycle = @import("import_cycle");
const resolve_bodies = @import("resolve_bodies");

/// One in-memory source file: `path` is the key imports resolve against.
pub const File = struct {
    path: []const u8,
    text: []const u8,
};

/// Which pipeline the root takes. `.project_if_imports` is the CLI's
/// compile/emit fast path: a root with no imports skips the import scan.
/// Preview, truth table, sim and analyze always run the project pipeline so
/// implicit builtin macros (`xor` without an import) resolve.
pub const Route = enum { single_module, project_if_imports, project };

/// Every step that can fail with a hard error. `cliLabel` is the exact
/// prefix the CLI has always printed for that step.
pub const Stage = enum {
    root_load,
    parse,
    resolve,
    import_scan,
    import_cycle,
    body_resolution,
    project_validation,
    validation,
    topology_build,
    topology_serialization,
    full_topology_serialization,
    wasm_assembly,
    layout_build,
    render,
    truth_table_build,

    pub fn cliLabel(self: Stage) []const u8 {
        return switch (self) {
            .root_load => "failed reading input file",
            .parse => "parse failed",
            .resolve => "resolve failed",
            .import_scan => "import scan failed",
            .import_cycle => "import cycle analysis failed",
            .body_resolution => "body resolution failed",
            .project_validation => "project validation failed",
            .validation => "validation failed",
            .topology_build => "topology build failed",
            .topology_serialization => "topology serialization failed",
            .full_topology_serialization => "full topology serialization failed",
            .wasm_assembly => "wasm assembly failed",
            .layout_build => "layout build failed",
            .render => "render failed",
            .truth_table_build => "truth-table build failed",
        };
    }
};

pub const Failure = struct {
    stage: Stage,
    cause: anyerror,
};

pub const FrontError = error{
    RootLoadFailed,
    ParseFailed,
    ResolveFailed,
    ImportScanFailed,
    ImportCycleFailed,
    BodyResolutionFailed,
    ProjectValidationFailed,
    ValidationFailed,
    OutOfMemory,
};

pub const Counts = struct { errors: usize, warnings: usize };

pub fn countDiagnostics(items: []const diagnostics.Diagnostic) Counts {
    var counts: Counts = .{ .errors = 0, .warnings = 0 };
    for (items) |d| switch (d.level) {
        .err => counts.errors += 1,
        .warning => counts.warnings += 1,
    };
    return counts;
}

/// Everything the modes need after the front end ran.
pub const Front = struct {
    /// The root's canonical path: the overlay key, or the realpath on disk.
    root_key: []const u8,
    ast_file: translate.Ast.File,
    /// Single-module resolve of the root; the fast path's only IR.
    ir_module: ir.Module,
    /// Null when the import-free fast path was taken.
    project: ?ir.Project,
    /// `scan_result.file_paths`, or just `root_key` on the fast path.
    file_paths: []const []const u8,
    /// scan ∪ cycle ∪ bodies ∪ validator, in that order.
    diagnostics: diagnostics.DiagnosticList,
    /// Set when the import scan or the cycle check reported errors: the
    /// pipeline stopped there, and `diagnostics` holds only its output.
    early_stop: ?Stage,
    errors: usize,
    warnings: usize,

    pub fn deinit(self: *Front, allocator: std.mem.Allocator) void {
        self.diagnostics.deinit(allocator);
    }

    pub fn hasErrors(self: *const Front) bool {
        return self.errors > 0;
    }
};

/// Build the overlay from the request's files, keys normalised the way the
/// loader looks them up.
pub fn buildOverlay(allocator: std.mem.Allocator, files: []const File) std.mem.Allocator.Error!?file_loader.Overlay {
    if (files.len == 0) return null;
    var overlay = file_loader.Overlay{};
    for (files) |f| {
        const key = try file_loader.normalizeKey(allocator, f.path);
        try overlay.put(allocator, key, f.text);
    }
    return overlay;
}

fn fail(failure: ?*Failure, stage: Stage, cause: anyerror) void {
    if (failure) |f| f.* = .{ .stage = stage, .cause = cause };
}

/// Run the front end over `root` (a key into `files`, or a disk path on
/// hosted targets). On error the stage and cause are in `failure`.
pub fn run(
    allocator: std.mem.Allocator,
    root: []const u8,
    files: []const File,
    route: Route,
    failure: ?*Failure,
) FrontError!Front {
    const overlay = try buildOverlay(allocator, files);

    const loaded = file_loader.loadFileWithOverlay(allocator, root, overlay) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        fail(failure, .root_load, err);
        return error.RootLoadFailed;
    };

    const ast_file = translate.parseSource(allocator, 0, loaded.source) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        fail(failure, .parse, err);
        return error.ParseFailed;
    };

    const ir_module = resolver.resolve(allocator, ast_file, 0) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        fail(failure, .resolve, err);
        return error.ResolveFailed;
    };

    const project_route = switch (route) {
        .single_module => false,
        .project_if_imports => ast_file.imports.len > 0,
        .project => true,
    };

    var front = Front{
        .root_key = loaded.absolute_path,
        .ast_file = ast_file,
        .ir_module = ir_module,
        .project = null,
        .file_paths = &.{},
        .diagnostics = diagnostics.initDiagnosticList(),
        .early_stop = null,
        .errors = 0,
        .warnings = 0,
    };

    if (project_route) {
        const scan_result = scan_imports.scanProjectImportsWithOverlay(allocator, root, overlay) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            fail(failure, .import_scan, err);
            return error.ImportScanFailed;
        };
        front.file_paths = scan_result.file_paths;
        if (scan_result.file_paths.len > 0) front.root_key = scan_result.file_paths[0];
        try front.diagnostics.appendSlice(allocator, scan_result.diagnostics.items);
        if (countDiagnostics(scan_result.diagnostics.items).errors > 0) {
            front.early_stop = .import_scan;
            return finish(front);
        }

        const cycle_result = import_cycle.analyzeImports(allocator, scan_result.file_paths, scan_result.import_table) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            fail(failure, .import_cycle, err);
            return error.ImportCycleFailed;
        };
        try front.diagnostics.appendSlice(allocator, cycle_result.diagnostics.items);
        if (countDiagnostics(cycle_result.diagnostics.items).errors > 0) {
            front.early_stop = .import_cycle;
            return finish(front);
        }

        const project = resolve_bodies.resolveBodiesWithOverlay(
            allocator,
            scan_result.file_paths,
            scan_result.import_table,
            cycle_result.topo_order,
            &front.diagnostics,
            overlay,
        ) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            fail(failure, .body_resolution, err);
            return error.BodyResolutionFailed;
        };
        front.project = project;
        var validator_list = validator_run_project.run(allocator, &front.project.?) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            fail(failure, .project_validation, err);
            return error.ProjectValidationFailed;
        };
        defer validator_list.deinit(allocator);
        try front.diagnostics.appendSlice(allocator, validator_list.items);
    } else {
        const paths = try allocator.alloc([]const u8, 1);
        paths[0] = front.root_key;
        front.file_paths = paths;
        var validator_list = validator_run.run(allocator, &front.ir_module) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            fail(failure, .validation, err);
            return error.ValidationFailed;
        };
        defer validator_list.deinit(allocator);
        try front.diagnostics.appendSlice(allocator, validator_list.items);
    }
    return finish(front);
}

fn finish(front: Front) Front {
    var out = front;
    const counts = countDiagnostics(out.diagnostics.items);
    out.errors = counts.errors;
    out.warnings = counts.warnings;
    return out;
}
