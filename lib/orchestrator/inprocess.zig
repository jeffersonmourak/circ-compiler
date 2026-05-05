const std = @import("std");
const zc = @import("zig_compiler");
const build_options = @import("build_options");

/// Compile the Zig source previously staged in `workspace_path/src/` by
/// `workspace_mod.writeRuntime` + `workspace_mod.writeEmittedSource` and emit
/// `workspace_path/zig-out/bin/compiled.wasm`.
///
/// Mirrors the config established in the spike (Phase 0): wasm32-freestanding,
/// self-hosted backend, no LLVM/LLD, rdynamic, entry=disabled.
/// On compilation error the diagnostics are rendered to stderr and
/// `error.ZigBuildFailed` is returned.
pub fn compile(
    allocator: std.mem.Allocator,
    workspace_path: []const u8,
    stderr_writer: anytype,
) !void {
    _ = stderr_writer; // diagnostics go to real stderr via error_bundle.renderToStdErr

    // The Zig compiler dispatches work to a thread pool; all workers share the
    // allocator.  Wrap it once here so arbitrary (non-thread-safe) allocators
    // from callers — including std.testing.allocator — can be used safely.
    var tsa: std.heap.ThreadSafeAllocator = .{ .child_allocator = allocator };
    const gpa = tsa.allocator();

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{ .allocator = gpa, .track_ids = true });
    defer thread_pool.deinit();

    const self_exe = try std.fs.selfExePathAlloc(arena);

    // Resolve to absolute (workspace_path may be relative when a build_dir override is used).
    const abs_workspace = if (std.fs.path.isAbsolute(workspace_path))
        workspace_path
    else
        try std.fs.cwd().realpathAlloc(arena, workspace_path);

    // Ensure zig-out/bin/ exists inside the workspace.
    {
        var ws_dir = try std.fs.openDirAbsolute(abs_workspace, .{});
        defer ws_dir.close();
        try ws_dir.makePath("zig-out/bin");
    }
    const out_wasm = try std.fmt.allocPrint(arena, "{s}/zig-out/bin/compiled.wasm", .{abs_workspace});

    // Directories: zig_lib_dir is baked in at build time (same approach as the spike).
    // local cache points into the workspace so cache artefacts are cleaned up with it.
    var dirs: zc.Compilation.Directories = .init(
        arena,
        build_options.zig_lib_dir,
        null,
        .{ .override = abs_workspace },
        {},
        self_exe,
    );
    defer dirs.deinit();

    // Target: wasm32-freestanding (matches the workspace build.zig template).
    const target_query = std.zig.parseTargetQueryOrReportFatalError(arena, .{
        .arch_os_abi = "wasm32-freestanding",
    });
    const target = std.zig.resolveTargetQueryOrFatal(target_query);
    const resolved_target: zc.Package.Module.ResolvedTarget = .{
        .result = target,
        .is_native_os = target_query.isNativeOs(),
        .is_native_abi = target_query.isNativeAbi(),
        .is_explicit_dynamic_linker = false,
    };

    const config = try zc.Compilation.Config.resolve(.{
        .output_mode = .Exe,
        .resolved_target = resolved_target,
        .is_test = false,
        .have_zcu = true,
        .emit_bin = true,
        .root_optimize_mode = .Debug,
        .use_llvm = false,
        .use_lib_llvm = false,
        .use_lld = false,
        .link_libc = false,
        .link_libcpp = false,
        .link_libunwind = false,
        .rdynamic = true,
    });

    // Root module: workspace/src/main.zig re-exports compiled.zig (the circuit).
    const src_dir = try std.fmt.allocPrint(arena, "{s}/src", .{abs_workspace});
    const root_path: zc.Compilation.Path = try .fromRoot(arena, dirs, .none, src_dir);
    const root_mod = try zc.Package.Module.create(arena, .{
        .paths = .{
            .root = root_path,
            .root_src_path = "main.zig",
        },
        .fully_qualified_name = "root",
        .cc_argv = &.{},
        .inherited = .{
            .resolved_target = resolved_target,
            .optimize_mode = .Debug,
        },
        .global = config,
        .parent = null,
    });

    // Load the pre-built wasm32 compiler_rt archive (built at build time by the
    // system Zig which has LLVM). The Zig WASM backend cannot build compiler_rt
    // in-process due to circular intrinsic dependencies.
    const crt_file = try std.fs.cwd().openFile(build_options.wasm_compiler_rt, .{});
    const crt_path = std.Build.Cache.Path.initCwd(build_options.wasm_compiler_rt);
    const link_inputs: []const zc.link.Input = &.{
        .{ .archive = .{
            .path = crt_path,
            .file = crt_file,
            .must_link = true,
            .hidden = false,
        } },
    };

    var diag: zc.Compilation.CreateDiagnostic = undefined;
    const comp = zc.Compilation.create(gpa, arena, &diag, .{
        .dirs = dirs,
        .thread_pool = &thread_pool,
        .self_exe_path = self_exe,
        .config = config,
        .root_name = "compiled",
        .root_mod = root_mod,
        .cache_mode = .none,
        .emit_bin = .{ .yes_path = out_wasm },
        .entry = .disabled,
        .link_inputs = link_inputs,
        .want_compiler_rt = false,
        // Allow extern fn declarations to remain as WASM host imports rather
        // than being treated as unresolved undefined symbols (circuit modules
        // import debugEnabled, onDebugLog, and transport functions from JS host).
        .linker_import_symbols = true,
    }) catch |err| {
        std.debug.print("Compilation.create failed ({s}): see above for details\n", .{@errorName(err)});
        return error.ZigBuildFailed;
    };
    defer comp.destroy();

    // std.Progress.start is a global singleton that panics on a second call in
    // the same process. Use Node.none so multiple in-process compilations (e.g.
    // in a test suite) do not conflict.
    try comp.update(std.Progress.Node.none);

    var error_bundle = try comp.getAllErrorsAlloc();
    defer error_bundle.deinit(gpa);
    if (error_bundle.errorMessageCount() > 0) {
        error_bundle.renderToStdErr(.{ .ttyconf = .no_color });
        return error.ZigBuildFailed;
    }
}
