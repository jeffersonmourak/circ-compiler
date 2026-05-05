const std = @import("std");
const zc = @import("zig_compiler");

/// C-ABI entry point compiled into `libinprocess.a`.
///
/// `workspace_path`: prepared compilation workspace (relative paths resolved against CWD).
/// `zig_lib_dir`: Zig standard library directory (same string as `zig env`'s `lib_dir`).
/// `compiler_rt`: path to the wasm32 `compiler_rt` static archive from the host `zig build-lib` step.
///
/// Returns 0 on success, -1 on failure (diagnostics rendered to stderr). Uses `c_allocator` internally because
/// the export has no Zig `Allocator` parameter; keep in sync with in-process compilation logic otherwise.
export fn circ_inprocess_compile(
    workspace_path_z: [*:0]const u8,
    zig_lib_dir_z: [*:0]const u8,
    compiler_rt_z: [*:0]const u8,
) callconv(.c) c_int {
    compileImpl(
        std.mem.span(workspace_path_z),
        std.mem.span(zig_lib_dir_z),
        std.mem.span(compiler_rt_z),
    ) catch return -1;
    return 0;
}

fn compileImpl(workspace_path: []const u8, zig_lib_dir: []const u8, compiler_rt: []const u8) !void {
    var tsa: std.heap.ThreadSafeAllocator = .{ .child_allocator = std.heap.c_allocator };
    const gpa = tsa.allocator();

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{ .allocator = gpa, .track_ids = true });
    defer thread_pool.deinit();

    const self_exe = try std.fs.selfExePathAlloc(arena);

    const abs_workspace = if (std.fs.path.isAbsolute(workspace_path))
        workspace_path
    else
        try std.fs.cwd().realpathAlloc(arena, workspace_path);

    {
        var ws_dir = try std.fs.openDirAbsolute(abs_workspace, .{});
        defer ws_dir.close();
        try ws_dir.makePath("zig-out/bin");
    }
    const out_wasm = try std.fmt.allocPrint(arena, "{s}/zig-out/bin/compiled.wasm", .{abs_workspace});

    var dirs: zc.Compilation.Directories = .init(
        arena,
        zig_lib_dir,
        null,
        .{ .override = abs_workspace },
        {},
        self_exe,
    );
    defer dirs.deinit();

    const target_query = std.zig.parseTargetQueryOrReportFatalError(arena, .{
        .arch_os_abi = "wasm32-freestanding",
    });
    const comp_target = std.zig.resolveTargetQueryOrFatal(target_query);
    const resolved_target: zc.Package.Module.ResolvedTarget = .{
        .result = comp_target,
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

    const crt_file = try std.fs.cwd().openFile(compiler_rt, .{});
    const crt_path = std.Build.Cache.Path.initCwd(compiler_rt);
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
        .linker_import_symbols = true,
    }) catch |err| {
        std.debug.print("Compilation.create failed ({s}): see above for details\n", .{@errorName(err)});
        return error.ZigBuildFailed;
    };
    defer comp.destroy();

    try comp.update(std.Progress.Node.none);

    var error_bundle = try comp.getAllErrorsAlloc();
    defer error_bundle.deinit(gpa);
    if (error_bundle.errorMessageCount() > 0) {
        error_bundle.renderToStdErr(.{ .ttyconf = .no_color });
        return error.ZigBuildFailed;
    }
}
