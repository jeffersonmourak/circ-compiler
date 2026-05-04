const std = @import("std");

const DevEnv = enum {
    bootstrap,
    core,
    full,
    c_source,
    ast_gen,
    sema,
    @"aarch64-linux",
    cbe,
    @"powerpc-linux",
    @"riscv64-linux",
    spirv,
    wasm,
    @"x86_64-linux",
};

const ValueInterpretMode = enum { direct, by_name };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_lib_dir = b.graph.zig_lib_directory.path orelse
        @panic("zig_lib_directory has no path; spike requires a resolvable system Zig lib dir");

    const zig_src_dir = std.process.getEnvVarOwned(b.allocator, "ZIG_SRC_DIR") catch
        @panic("ZIG_SRC_DIR must be set to the unpacked Zig 0.15.1 source tree (must contain src/Compilation.zig and src/spike_exports.zig)");

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "zig_lib_dir", zig_lib_dir);
    build_options.addOption([]const u8, "zig_src_dir", zig_src_dir);

    const exe = b.addExecutable(.{
        .name = "spike",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("build_options", build_options);

    // ---- Embedded Zig compiler module (mirrors Zig's addCompilerMod). ----
    const compiler_root_path = b.pathJoin(&.{ zig_src_dir, "src", "spike_exports.zig" });

    const compiler_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = compiler_root_path },
        .target = target,
        .optimize = optimize,
    });
    compiler_mod.link_libc = true;

    const aro_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ zig_src_dir, "lib", "compiler", "aro", "aro.zig" }) },
        .target = target,
        .optimize = optimize,
    });
    const aro_translate_c_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ zig_src_dir, "lib", "compiler", "aro_translate_c.zig" }) },
        .target = target,
        .optimize = optimize,
    });
    aro_translate_c_mod.addImport("aro", aro_mod);

    compiler_mod.addImport("aro", aro_mod);
    compiler_mod.addImport("aro_translate_c", aro_translate_c_mod);

    // ---- build_options expected by the embedded Zig compiler source. ----
    const zig_options = b.addOptions();
    zig_options.addOption(u32, "mem_leak_frames", 0);
    zig_options.addOption(bool, "skip_non_native", false);
    zig_options.addOption(bool, "have_llvm", false);
    zig_options.addOption(bool, "llvm_has_m68k", false);
    zig_options.addOption(bool, "llvm_has_csky", false);
    zig_options.addOption(bool, "llvm_has_arc", false);
    zig_options.addOption(bool, "llvm_has_xtensa", false);
    zig_options.addOption(bool, "debug_gpa", false);
    zig_options.addOption(DevEnv, "dev", .full);
    zig_options.addOption(ValueInterpretMode, "value_interpret_mode", .direct);
    zig_options.addOption([:0]const u8, "version", "0.15.1");
    zig_options.addOption(std.SemanticVersion, "semver", .{ .major = 0, .minor = 15, .patch = 1 });
    zig_options.addOption(bool, "enable_debug_extensions", true);
    zig_options.addOption(bool, "enable_logging", false);
    zig_options.addOption(bool, "enable_link_snapshots", false);
    zig_options.addOption(bool, "enable_tracy", false);
    zig_options.addOption(bool, "enable_tracy_callstack", false);
    zig_options.addOption(bool, "enable_tracy_allocation", false);
    zig_options.addOption(u32, "tracy_callstack_depth", 0);
    zig_options.addOption(bool, "value_tracing", false);
    compiler_mod.addOptions("build_options", zig_options);

    exe.root_module.addImport("zig_compiler", compiler_mod);
    exe.root_module.link_libc = true;

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the spike binary");
    run_step.dependOn(&run_cmd.step);
}
