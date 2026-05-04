const std = @import("std");
const build_options = @import("build_options");
const zc = @import("zig_compiler");

const input_source =
    \\pub export fn add(a: i32, b: i32) i32 {
    \\    return a + b;
    \\}
    \\
;

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_writer.interface;

    try out.print("spike: starting\n", .{});
    try out.print("zig_lib_dir: {s}\n", .{build_options.zig_lib_dir});

    // ---- 1. Stage input source on disk. ----
    try std.fs.cwd().makePath("out/work");
    {
        var f = try std.fs.cwd().createFile("out/work/add.zig", .{});
        defer f.close();
        try f.writeAll(input_source);
    }
    const work_abs = try std.fs.cwd().realpathAlloc(arena, "out/work");
    const out_abs = try std.fs.cwd().realpathAlloc(arena, "out");
    const out_wasm_abs = try std.fmt.allocPrint(arena, "{s}/add.wasm", .{out_abs});

    // ---- 2. Thread pool. ----
    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{ .allocator = gpa, .track_ids = true });
    defer thread_pool.deinit();

    // ---- 3. Directories. ----
    const self_exe = try std.fs.selfExePathAlloc(arena);
    var dirs: zc.Compilation.Directories = .init(
        arena,
        build_options.zig_lib_dir,
        null,
        .{ .override = work_abs },
        {},
        self_exe,
    );
    defer dirs.deinit();

    // ---- 4. Resolved target: wasm32-freestanding. ----
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

    // ---- 5. Compilation.Config. ----
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
    });

    // ---- 6. Root module pointing at the staged input. ----
    const root_path: zc.Compilation.Path = try .fromRoot(arena, dirs, .none, work_abs);
    const root_mod = try zc.Package.Module.create(arena, .{
        .paths = .{
            .root = root_path,
            .root_src_path = "add.zig",
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

    // ---- 7. Compilation.create. ----
    var diag: zc.Compilation.CreateDiagnostic = undefined;
    const comp = zc.Compilation.create(gpa, arena, &diag, .{
        .dirs = dirs,
        .thread_pool = &thread_pool,
        .self_exe_path = self_exe,
        .config = config,
        .root_name = "add",
        .root_mod = root_mod,
        .cache_mode = .none,
        .emit_bin = .{ .yes_path = out_wasm_abs },
        .entry = .disabled,
    }) catch |err| {
        try out.print("Compilation.create failed: {s}\n", .{@errorName(err)});
        diag.format(out) catch {};
        try out.print("\n", .{});
        try out.flush();
        std.process.exit(1);
    };
    defer comp.destroy();

    // ---- 8. Drive compilation. ----
    const progress = std.Progress.start(.{ .disable_printing = true });
    defer progress.end();

    try comp.update(progress);

    // Surface any errors the compiler produced.
    var error_bundle = try comp.getAllErrorsAlloc();
    defer error_bundle.deinit(gpa);
    if (error_bundle.errorMessageCount() > 0) {
        try out.print("compilation errors: {d}\n", .{error_bundle.errorMessageCount()});
        try out.flush();
        error_bundle.renderToStdErr(.{ .ttyconf = .no_color });
        std.process.exit(2);
    }

    // ---- 9. Verify output. ----
    const wasm = try std.fs.cwd().readFileAlloc(arena, out_wasm_abs, 1 << 20);
    const has_magic = wasm.len >= 4 and std.mem.eql(u8, wasm[0..4], "\x00asm");
    try out.print("emit ok={}, size={d} bytes, path={s}\n", .{ has_magic, wasm.len, out_wasm_abs });
    try out.flush();

    if (!has_magic) std.process.exit(3);
}
