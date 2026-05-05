const std = @import("std");

const GRAMMAR_FILE = "lib/grammar/proto-circ.peg";

/// Must match `Dev.Env` in the Zig compiler's `src/dev.zig` field-for-field.
const ZigCompilerDevEnv = enum {
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

/// Must match `value_interpret_mode` in the Zig compiler's `src/build_options`.
const ZigCompilerValueInterpretMode = enum { direct, by_name };

fn validateZigLangCheckout(allocator: std.mem.Allocator, zig_src: []const u8) void {
    const markers = [_][]const u8{
        "src/Compilation.zig",
        "lib/compiler/aro/aro.zig",
        "lib/compiler/aro_translate_c.zig",
    };
    for (markers) |rel| {
        const full = std.fs.path.join(allocator, &.{ zig_src, rel }) catch @panic("OOM");
        defer allocator.free(full);
        std.fs.accessAbsolute(full, .{}) catch {
            std.debug.panic(
                "ZIG_COMPILER_SRC ('{s}') missing '{s}'. Use a full ziglang/zig source checkout at the matching release tag; the Zig install lib/ directory does not ship `src/Compilation.zig`.",
                .{ zig_src, rel },
            );
        };
    }
}

fn ensureCircZigCompilerExports(b: *std.Build, zig_src: []const u8) void {
    const arena = b.allocator;
    const dest = std.fs.path.join(arena, &.{ zig_src, "src", "circ_zig_compiler_exports.zig" }) catch @panic("OOM");
    defer arena.free(dest);
    std.fs.accessAbsolute(dest, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const src = b.build_root.join(arena, &.{ "lib", "zig_compiler_exports", "zig_compiler_exports.zig" }) catch @panic("OOM");
            defer arena.free(src);
            std.fs.copyFileAbsolute(src, dest, .{}) catch |e| {
                std.debug.panic(
                    "install circ_zig_compiler_exports.zig to '{s}' failed ({s}); copy manually from lib/zig_compiler_exports/zig_compiler_exports.zig",
                    .{ dest, @errorName(e) },
                );
            };
        },
        else => |e| std.debug.panic("access '{s}': {s}", .{ dest, @errorName(e) }),
    };
}

fn zigSrcLazyPath(b: *std.Build, zig_src: []const u8, rel: []const u8) std.Build.LazyPath {
    const abs = std.fs.path.join(b.allocator, &.{ zig_src, rel }) catch @panic("OOM");
    return .{ .cwd_relative = abs };
}

fn addZigCompilerModuleFromSrc(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zig_src: []const u8,
) *std.Build.Module {
    const aro_mod = b.createModule(.{
        .root_source_file = zigSrcLazyPath(b, zig_src, "lib/compiler/aro/aro.zig"),
        .target = target,
        .optimize = optimize,
    });
    const aro_translate_c_mod = b.createModule(.{
        .root_source_file = zigSrcLazyPath(b, zig_src, "lib/compiler/aro_translate_c.zig"),
        .target = target,
        .optimize = optimize,
    });
    aro_translate_c_mod.addImport("aro", aro_mod);

    const zig_options = b.addOptions();
    zig_options.addOption(u32, "mem_leak_frames", 0);
    zig_options.addOption(bool, "skip_non_native", false);
    zig_options.addOption(bool, "have_llvm", false);
    zig_options.addOption(bool, "llvm_has_m68k", false);
    zig_options.addOption(bool, "llvm_has_csky", false);
    zig_options.addOption(bool, "llvm_has_arc", false);
    zig_options.addOption(bool, "llvm_has_xtensa", false);
    zig_options.addOption(bool, "debug_gpa", false);
    zig_options.addOption(ZigCompilerDevEnv, "dev", .full);
    zig_options.addOption(ZigCompilerValueInterpretMode, "value_interpret_mode", .direct);
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

    const mod = b.createModule(.{
        .root_source_file = zigSrcLazyPath(b, zig_src, "src/circ_zig_compiler_exports.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.link_libc = true;
    mod.addImport("aro", aro_mod);
    mod.addImport("aro_translate_c", aro_translate_c_mod);
    mod.addOptions("build_options", zig_options);
    return mod;
}

/// `zig_lib_dir` + wasm32 `compiler_rt` options for `inprocess.zig` / `inprocess_stub.zig`.
fn addInprocessWasmBuildOptions(b: *std.Build, mod: *std.Build.Module) void {
    const build_wasm_compiler_rt = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build-lib",
        "-target",
        "wasm32-freestanding",
        "-O",
        "Debug",
        "-fno-compiler-rt",
        b.fmt("{s}/compiler_rt.zig", .{b.graph.zig_lib_directory.path orelse @panic("zig_lib_directory.path is null")}),
    });
    const wasm_compiler_rt_lazy = build_wasm_compiler_rt.addPrefixedOutputFileArg("-femit-bin=", "libcompiler_rt.a");
    const inprocess_build_options = b.addOptions();
    inprocess_build_options.addOption(
        []const u8,
        "zig_lib_dir",
        b.graph.zig_lib_directory.path orelse @panic("zig_lib_directory.path is null"),
    );
    inprocess_build_options.addOptionPath("wasm_compiler_rt", wasm_compiler_rt_lazy);
    mod.addOptions("build_options", inprocess_build_options);
}

fn linkInprocessForStub(
    compile: *std.Build.Step.Compile,
    link_prebuilt_archive: bool,
    prebuilt_libinprocess: std.Build.LazyPath,
    maybe_inprocess_static_lib: ?*std.Build.Step.Compile,
) void {
    if (link_prebuilt_archive) {
        compile.root_module.addObjectFile(prebuilt_libinprocess);
    } else {
        compile.linkLibrary(maybe_inprocess_static_lib.?);
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    var zig_compiler_src_env: ?[]const u8 = null;
    defer if (zig_compiler_src_env) |s| b.allocator.free(s);

    const zig_compiler_src_raw = b.option(
        []const u8,
        "zig-compiler-src",
        "Path to ziglang/zig source checkout matching this Zig (needs src/Compilation.zig). Or set ZIG_COMPILER_SRC.",
    ) orelse blk: {
        zig_compiler_src_env = std.process.getEnvVarOwned(b.allocator, "ZIG_COMPILER_SRC") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => break :blk null,
            else => std.debug.panic("reading ZIG_COMPILER_SRC: {s}", .{@errorName(err)}),
        };
        break :blk zig_compiler_src_env;
    };

    const zig_compiler_src_abs: ?[]const u8 = if (zig_compiler_src_raw) |raw| blk: {
        const resolved = if (std.fs.path.isAbsolute(raw))
            std.fs.path.resolve(b.allocator, &.{raw}) catch @panic("OOM")
        else
            std.fs.cwd().realpathAlloc(b.allocator, raw) catch |err| {
                std.debug.panic("zig-compiler-src '{s}': {s}", .{ raw, @errorName(err) });
            };
        validateZigLangCheckout(b.allocator, resolved);
        ensureCircZigCompilerExports(b, resolved);
        break :blk resolved;
    } else null;
    defer if (zig_compiler_src_abs) |p| b.allocator.free(p);

    const zig_compiler_embed_mod: ?*std.Build.Module = if (zig_compiler_src_abs) |root|
        addZigCompilerModuleFromSrc(b, target, optimize, root)
    else
        null;

    var maybe_inprocess_static_lib: ?*std.Build.Step.Compile = null;
    const inprocess_lib_step = b.step(
        "inprocess-lib",
        "Build libinprocess.a (FFI + embedded Zig compiler); requires ziglang/zig checkout via ZIG_COMPILER_SRC or -Dzig-compiler-src",
    );
    if (zig_compiler_embed_mod) |zc_mod| {
        const inprocess_ffi_lib_mod = b.createModule(.{
            .root_source_file = b.path("lib/orchestrator/inprocess_ffi.zig"),
            .target = target,
            .optimize = optimize,
        });
        inprocess_ffi_lib_mod.addImport("zig_compiler", zc_mod);
        const inprocess_static_lib = b.addLibrary(.{
            .name = "inprocess",
            .linkage = .static,
            .root_module = inprocess_ffi_lib_mod,
        });
        inprocess_static_lib.linkLibC();
        maybe_inprocess_static_lib = inprocess_static_lib;
        const install_inprocess_lib = b.addInstallArtifact(inprocess_static_lib, .{});
        inprocess_lib_step.dependOn(&install_inprocess_lib.step);
    } else {
        const fail = b.addFail(
            \\zig build inprocess-lib needs the Zig *compiler sources* (ziglang/zig checkout), not only Zig's installed lib/.
            \\Example: git clone https://github.com/ziglang/zig --branch 0.15.1 --depth 1 ~/zig-src
            \\Then: export ZIG_COMPILER_SRC=~/zig-src   OR   zig build inprocess-lib -Dzig-compiler-src=/path/to/zig
            \\The build uses your installed Zig's lib dir (see `zig env`) when resolving std/compiler_rt for wasm assists.
        );
        inprocess_lib_step.dependOn(&fail.step);
    }

    const use_inprocess_stub = b.option(
        bool,
        "orchestrator-inprocess-stub",
        "Use FFI stub + libinprocess.a (no zig_compiler in circ-compile / orchestrator in-process module)",
    ) orelse false;
    const have_prebuilt_inprocess_a = blk: {
        var prebuilt_dir = b.build_root.handle.openDir("prebuilt", .{}) catch break :blk false;
        defer prebuilt_dir.close();
        prebuilt_dir.access("libinprocess.a", .{}) catch break :blk false;
        break :blk true;
    };
    const circ_prebuilt_inprocess = b.option(
        bool,
        "circ-prebuilt-inprocess",
        "Link prebuilt/libinprocess.a (FFI stub path; skips compiling embedded zig_compiler into dependents)",
    ) orelse false;
    if (circ_prebuilt_inprocess and !have_prebuilt_inprocess_a) {
        @panic("-Dcirc-prebuilt-inprocess=true requires prebuilt/libinprocess.a (run: zig build inprocess-lib -p zig-out && mkdir -p prebuilt && cp zig-out/lib/libinprocess.a prebuilt/)");
    }
    const link_prebuilt_inprocess_archive = circ_prebuilt_inprocess and have_prebuilt_inprocess_a;
    const use_stub_inprocess_graph = use_inprocess_stub or link_prebuilt_inprocess_archive;
    const prebuilt_libinprocess_lp = b.path("prebuilt/libinprocess.a");

    if (use_stub_inprocess_graph and !link_prebuilt_inprocess_archive and maybe_inprocess_static_lib == null) {
        @panic("-Dorchestrator-inprocess-stub=true requires ZIG_COMPILER_SRC (or -Dzig-compiler-src) to build libinprocess, or use -Dcirc-prebuilt-inprocess=true with prebuilt/libinprocess.a");
    }

    const orchestrator_use_inprocess = b.option(
        bool,
        "orchestrator-use-inprocess",
        "Use embedded Zig Compilation (or FFI stub) for wasm instead of zig subprocess",
    ) orelse false;
    const need_inprocess_side_module = use_stub_inprocess_graph or zig_compiler_embed_mod != null;
    const orchestrator_subprocess_for_wasm = blk: {
        if (!orchestrator_use_inprocess) break :blk true;
        if (!need_inprocess_side_module) {
            @panic("orchestrator-use-inprocess=true requires ZIG_COMPILER_SRC / stub / prebuilt libinprocess wiring");
        }
        break :blk false;
    };

    const orchestrator_route_opts = b.addOptions();
    orchestrator_route_opts.addOption(bool, "use_subprocess_for_wasm", orchestrator_subprocess_for_wasm);

    var maybe_inprocess_mod: ?*std.Build.Module = null;
    if (need_inprocess_side_module) {
        maybe_inprocess_mod = b.createModule(.{
            .root_source_file = if (use_stub_inprocess_graph)
                b.path("lib/orchestrator/inprocess_stub.zig")
            else
                b.path("lib/orchestrator/inprocess.zig"),
            .target = target,
            .optimize = optimize,
        });
        const ip = maybe_inprocess_mod.?;
        if (use_stub_inprocess_graph) {
            addInprocessWasmBuildOptions(b, ip);
        } else if (zig_compiler_embed_mod) |zm| {
            ip.addImport("zig_compiler", zm);
            addInprocessWasmBuildOptions(b, ip);
        }
    }

    const golden_mod = b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    });

    const parser_gen = b.step("parser:gen", "Generate C Parser");

    const generate_parser_cmd = b.addSystemCommand(&.{
        "langlang",
        "-grammar",
        GRAMMAR_FILE,
        "-disable-capture-spaces",
        "-output-language",
        "c",
        "-output-path",
        "lib/parser.c",
        "-c-header-path",
        "lib/parser.h",
    });

    parser_gen.dependOn(&generate_parser_cmd.step);

    const parser_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "parser",
        .root_module = b.createModule(.{
            .root_source_file = null,
            .target = target,
            .optimize = optimize,
        }),
    });

    parser_lib.addCSourceFile(.{
        .file = b.path("lib/parser.c"),
        .flags = &.{},
    });

    parser_lib.addIncludePath(b.path("."));
    parser_lib.linkLibC();

    const golden_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/helpers/golden_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_golden_tests = b.addRunArtifact(golden_tests);
    const translate_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/syntax/translate_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const translate_mod = b.createModule(.{
        .root_source_file = b.path("lib/syntax/translate.zig"),
        .target = target,
        .optimize = optimize,
    });
    translate_mod.addIncludePath(b.path("."));
    translate_mod.addIncludePath(b.path("./lib"));
    translate_tests_mod.addImport("translate", translate_mod);
    translate_tests_mod.addImport("golden", golden_mod);
    const ast_dump_mod = b.createModule(.{
        .root_source_file = b.path("tests/helpers/ast_dump.zig"),
        .target = target,
        .optimize = optimize,
    });
    translate_tests_mod.addImport("ast_dump", ast_dump_mod);
    const translate_tests = b.addTest(.{
        .root_module = translate_tests_mod,
    });
    translate_tests.addIncludePath(b.path("."));
    translate_tests.addIncludePath(b.path("./lib"));
    translate_tests.linkLibrary(parser_lib);
    translate_tests.linkLibC();
    const run_translate_tests = b.addRunArtifact(translate_tests);
    const ir_types_mod = b.createModule(.{
        .root_source_file = b.path("lib/ir/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ir_types_tests = b.addTest(.{
        .root_module = ir_types_mod,
    });
    const run_ir_types_tests = b.addRunArtifact(ir_types_tests);
    const resolver_mod = b.createModule(.{
        .root_source_file = b.path("lib/ir/resolver.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_mod.addImport("translate", translate_mod);
    resolver_mod.addImport("ir_types", ir_types_mod);
    const resolver_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/ir/resolver_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_tests_mod.addImport("translate", translate_mod);
    resolver_tests_mod.addImport("resolver", resolver_mod);
    resolver_tests_mod.addImport("ir_dump", b.createModule(.{
        .root_source_file = b.path("tests/helpers/ir_dump.zig"),
        .target = target,
        .optimize = optimize,
    }));
    resolver_tests_mod.addImport("golden", golden_mod);
    const resolver_tests = b.addTest(.{
        .root_module = resolver_tests_mod,
    });
    resolver_tests.addIncludePath(b.path("."));
    resolver_tests.addIncludePath(b.path("./lib"));
    resolver_tests.linkLibrary(parser_lib);
    resolver_tests.linkLibC();
    const run_resolver_tests = b.addRunArtifact(resolver_tests);
    const validator_codes_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/codes.zig"),
        .target = target,
        .optimize = optimize,
    });
    const validator_diagnostics_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/diagnostics.zig"),
        .target = target,
        .optimize = optimize,
    });
    validator_diagnostics_mod.addImport("codes", validator_codes_mod);
    const validator_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/validator/diagnostics_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    validator_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    validator_tests_mod.addImport("codes", validator_codes_mod);
    const validator_tests = b.addTest(.{
        .root_module = validator_tests_mod,
    });
    const run_validator_tests = b.addRunArtifact(validator_tests);
    const name_resolution_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/passes/name_resolution.zig"),
        .target = target,
        .optimize = optimize,
    });
    name_resolution_mod.addImport("diagnostics", validator_diagnostics_mod);
    name_resolution_mod.addImport("ir_types", ir_types_mod);
    const name_collision_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/passes/name_collision.zig"),
        .target = target,
        .optimize = optimize,
    });
    name_collision_mod.addImport("diagnostics", validator_diagnostics_mod);
    name_collision_mod.addImport("ir_types", ir_types_mod);
    const port_validation_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/passes/port_validation.zig"),
        .target = target,
        .optimize = optimize,
    });
    port_validation_mod.addImport("diagnostics", validator_diagnostics_mod);
    port_validation_mod.addImport("ir_types", ir_types_mod);
    const multi_driver_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/passes/multi_driver.zig"),
        .target = target,
        .optimize = optimize,
    });
    multi_driver_mod.addImport("diagnostics", validator_diagnostics_mod);
    multi_driver_mod.addImport("ir_types", ir_types_mod);
    const required_input_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/passes/required_input.zig"),
        .target = target,
        .optimize = optimize,
    });
    required_input_mod.addImport("diagnostics", validator_diagnostics_mod);
    required_input_mod.addImport("ir_types", ir_types_mod);
    const output_assignment_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/passes/output_assignment.zig"),
        .target = target,
        .optimize = optimize,
    });
    output_assignment_mod.addImport("diagnostics", validator_diagnostics_mod);
    output_assignment_mod.addImport("ir_types", ir_types_mod);
    const combinational_loop_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/passes/combinational_loop.zig"),
        .target = target,
        .optimize = optimize,
    });
    combinational_loop_mod.addImport("diagnostics", validator_diagnostics_mod);
    combinational_loop_mod.addImport("ir_types", ir_types_mod);
    const dead_code_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/passes/dead_code.zig"),
        .target = target,
        .optimize = optimize,
    });
    dead_code_mod.addImport("diagnostics", validator_diagnostics_mod);
    dead_code_mod.addImport("ir_types", ir_types_mod);
    const unused_import_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/passes/unused_import.zig"),
        .target = target,
        .optimize = optimize,
    });
    unused_import_mod.addImport("diagnostics", validator_diagnostics_mod);
    unused_import_mod.addImport("ir_types", ir_types_mod);
    const validator_run_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/run.zig"),
        .target = target,
        .optimize = optimize,
    });
    validator_run_mod.addImport("diagnostics", validator_diagnostics_mod);
    validator_run_mod.addImport("ir_types", ir_types_mod);
    validator_run_mod.addImport("name_resolution", name_resolution_mod);
    validator_run_mod.addImport("name_collision", name_collision_mod);
    validator_run_mod.addImport("port_validation", port_validation_mod);
    validator_run_mod.addImport("multi_driver", multi_driver_mod);
    validator_run_mod.addImport("required_input", required_input_mod);
    validator_run_mod.addImport("output_assignment", output_assignment_mod);
    validator_run_mod.addImport("combinational_loop", combinational_loop_mod);
    validator_run_mod.addImport("dead_code", dead_code_mod);
    validator_run_mod.addImport("unused_import", unused_import_mod);
    const sub_circuit_validation_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/passes/sub_circuit_validation.zig"),
        .target = target,
        .optimize = optimize,
    });
    sub_circuit_validation_mod.addImport("diagnostics", validator_diagnostics_mod);
    sub_circuit_validation_mod.addImport("ir_types", ir_types_mod);
    const validator_run_project_mod = b.createModule(.{
        .root_source_file = b.path("lib/validator/run_project.zig"),
        .target = target,
        .optimize = optimize,
    });
    validator_run_project_mod.addImport("diagnostics", validator_diagnostics_mod);
    validator_run_project_mod.addImport("ir_types", ir_types_mod);
    validator_run_project_mod.addImport("validator_run", validator_run_mod);
    validator_run_project_mod.addImport("sub_circuit_validation", sub_circuit_validation_mod);
    const validator_name_passes_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/validator/name_passes_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    validator_name_passes_tests_mod.addImport("translate", translate_mod);
    validator_name_passes_tests_mod.addImport("resolver", resolver_mod);
    validator_name_passes_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    validator_name_passes_tests_mod.addImport("name_resolution", name_resolution_mod);
    validator_name_passes_tests_mod.addImport("name_collision", name_collision_mod);
    validator_name_passes_tests_mod.addImport("golden", golden_mod);
    const validator_name_passes_tests = b.addTest(.{
        .root_module = validator_name_passes_tests_mod,
    });
    validator_name_passes_tests.addIncludePath(b.path("."));
    validator_name_passes_tests.addIncludePath(b.path("./lib"));
    validator_name_passes_tests.linkLibrary(parser_lib);
    validator_name_passes_tests.linkLibC();
    const run_validator_name_passes_tests = b.addRunArtifact(validator_name_passes_tests);
    const validator_structural_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/validator/structural_passes_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    validator_structural_tests_mod.addImport("translate", translate_mod);
    validator_structural_tests_mod.addImport("resolver", resolver_mod);
    validator_structural_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    validator_structural_tests_mod.addImport("name_resolution", name_resolution_mod);
    validator_structural_tests_mod.addImport("port_validation", port_validation_mod);
    validator_structural_tests_mod.addImport("multi_driver", multi_driver_mod);
    validator_structural_tests_mod.addImport("required_input", required_input_mod);
    validator_structural_tests_mod.addImport("output_assignment", output_assignment_mod);
    validator_structural_tests_mod.addImport("golden", golden_mod);
    const validator_structural_tests = b.addTest(.{
        .root_module = validator_structural_tests_mod,
    });
    validator_structural_tests.addIncludePath(b.path("."));
    validator_structural_tests.addIncludePath(b.path("./lib"));
    validator_structural_tests.linkLibrary(parser_lib);
    validator_structural_tests.linkLibC();
    const run_validator_structural_tests = b.addRunArtifact(validator_structural_tests);
    const validator_loop_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/validator/loop_passes_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    validator_loop_tests_mod.addImport("translate", translate_mod);
    validator_loop_tests_mod.addImport("resolver", resolver_mod);
    validator_loop_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    validator_loop_tests_mod.addImport("combinational_loop", combinational_loop_mod);
    validator_loop_tests_mod.addImport("golden", golden_mod);
    const validator_loop_tests = b.addTest(.{
        .root_module = validator_loop_tests_mod,
    });
    validator_loop_tests.addIncludePath(b.path("."));
    validator_loop_tests.addIncludePath(b.path("./lib"));
    validator_loop_tests.linkLibrary(parser_lib);
    validator_loop_tests.linkLibC();
    const run_validator_loop_tests = b.addRunArtifact(validator_loop_tests);
    const validator_run_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/validator/run_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    validator_run_tests_mod.addImport("translate", translate_mod);
    validator_run_tests_mod.addImport("resolver", resolver_mod);
    validator_run_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    validator_run_tests_mod.addImport("validator_run", validator_run_mod);
    validator_run_tests_mod.addImport("golden", golden_mod);
    const validator_run_tests = b.addTest(.{
        .root_module = validator_run_tests_mod,
    });
    validator_run_tests.addIncludePath(b.path("."));
    validator_run_tests.addIncludePath(b.path("./lib"));
    validator_run_tests.linkLibrary(parser_lib);
    validator_run_tests.linkLibC();
    const run_validator_run_tests = b.addRunArtifact(validator_run_tests);
    const emit_build_fn_mod = b.createModule(.{
        .root_source_file = b.path("lib/emit/build_fn.zig"),
        .target = target,
        .optimize = optimize,
    });
    const emit_writer_mod = b.createModule(.{
        .root_source_file = b.path("lib/emit/writer.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_build_fn_mod.addImport("ir_types", ir_types_mod);
    emit_build_fn_mod.addImport("emit_writer", emit_writer_mod);
    const emit_file_info_format_mod = b.createModule(.{
        .root_source_file = b.path("lib/emit/file_info_format.zig"),
        .target = target,
        .optimize = optimize,
    });
    const emit_file_info_mod = b.createModule(.{
        .root_source_file = b.path("lib/emit/file_info.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_file_info_mod.addImport("ir_types", ir_types_mod);
    emit_file_info_mod.addImport("file_info_format", emit_file_info_format_mod);
    emit_file_info_mod.addImport("emit_writer", emit_writer_mod);
    const emit_debug_paths_mod = b.createModule(.{
        .root_source_file = b.path("lib/emit/debug_paths.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_debug_paths_mod.addImport("ir_types", ir_types_mod);
    emit_debug_paths_mod.addImport("emit_writer", emit_writer_mod);
    const emit_runtime_mod = b.createModule(.{
        .root_source_file = b.path("lib/emit/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_runtime_mod.addImport("ir_types", ir_types_mod);
    emit_runtime_mod.addImport("emit_writer", emit_writer_mod);
    const emit_project_mod = b.createModule(.{
        .root_source_file = b.path("lib/emit/project.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_project_mod.addImport("ir_types", ir_types_mod);
    emit_project_mod.addImport("emit_writer", emit_writer_mod);
    emit_project_mod.addImport("file_info_format", emit_file_info_format_mod);
    const emit_main_mod = b.createModule(.{
        .root_source_file = b.path("lib/emit/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_main_mod.addImport("ir_types", ir_types_mod);
    emit_main_mod.addImport("emit_writer", emit_writer_mod);
    emit_main_mod.addImport("emit_build_fn", emit_build_fn_mod);
    emit_main_mod.addImport("emit_file_info", emit_file_info_mod);
    emit_main_mod.addImport("emit_debug_paths", emit_debug_paths_mod);
    emit_main_mod.addImport("emit_runtime", emit_runtime_mod);
    emit_main_mod.addImport("emit_project", emit_project_mod);
    const emit_build_fn_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/emit/build_fn_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_build_fn_tests_mod.addImport("translate", translate_mod);
    emit_build_fn_tests_mod.addImport("resolver", resolver_mod);
    emit_build_fn_tests_mod.addImport("validator_run", validator_run_mod);
    emit_build_fn_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    emit_build_fn_tests_mod.addImport("build_fn", emit_build_fn_mod);
    emit_build_fn_tests_mod.addImport("golden", golden_mod);
    const emit_build_fn_tests = b.addTest(.{
        .root_module = emit_build_fn_tests_mod,
    });
    emit_build_fn_tests.addIncludePath(b.path("."));
    emit_build_fn_tests.addIncludePath(b.path("./lib"));
    emit_build_fn_tests.linkLibrary(parser_lib);
    emit_build_fn_tests.linkLibC();
    const run_emit_build_fn_tests = b.addRunArtifact(emit_build_fn_tests);
    const emit_metadata_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/emit/metadata_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_metadata_tests_mod.addImport("translate", translate_mod);
    emit_metadata_tests_mod.addImport("resolver", resolver_mod);
    emit_metadata_tests_mod.addImport("validator_run", validator_run_mod);
    emit_metadata_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    emit_metadata_tests_mod.addImport("ir_types", ir_types_mod);
    emit_metadata_tests_mod.addImport("emit_file_info", emit_file_info_mod);
    emit_metadata_tests_mod.addImport("emit_file_info_format", emit_file_info_format_mod);
    emit_metadata_tests_mod.addImport("emit_debug_paths", emit_debug_paths_mod);
    emit_metadata_tests_mod.addImport("golden", golden_mod);
    const emit_metadata_tests = b.addTest(.{
        .root_module = emit_metadata_tests_mod,
    });
    emit_metadata_tests.addIncludePath(b.path("."));
    emit_metadata_tests.addIncludePath(b.path("./lib"));
    emit_metadata_tests.linkLibrary(parser_lib);
    emit_metadata_tests.linkLibC();
    const run_emit_metadata_tests = b.addRunArtifact(emit_metadata_tests);
    const emit_full_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/emit/full_emit_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_full_tests_mod.addImport("translate", translate_mod);
    emit_full_tests_mod.addImport("resolver", resolver_mod);
    emit_full_tests_mod.addImport("validator_run", validator_run_mod);
    emit_full_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    emit_full_tests_mod.addImport("emit_main", emit_main_mod);
    emit_full_tests_mod.addImport("golden", golden_mod);
    const emit_full_tests = b.addTest(.{
        .root_module = emit_full_tests_mod,
    });
    emit_full_tests.addIncludePath(b.path("."));
    emit_full_tests.addIncludePath(b.path("./lib"));
    emit_full_tests.linkLibrary(parser_lib);
    emit_full_tests.linkLibC();
    const run_emit_full_tests = b.addRunArtifact(emit_full_tests);
    const wasm_run_mod = b.createModule(.{
        .root_source_file = b.path("tests/helpers/wasm_run.zig"),
        .target = target,
        .optimize = optimize,
    });
    const emit_behavior_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/emit/behavior_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_behavior_tests_mod.addImport("translate", translate_mod);
    emit_behavior_tests_mod.addImport("resolver", resolver_mod);
    emit_behavior_tests_mod.addImport("validator_run", validator_run_mod);
    emit_behavior_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    emit_behavior_tests_mod.addImport("emit_main", emit_main_mod);
    emit_behavior_tests_mod.addImport("wasm_run", wasm_run_mod);
    const emit_behavior_tests = b.addTest(.{
        .root_module = emit_behavior_tests_mod,
    });
    emit_behavior_tests.addIncludePath(b.path("."));
    emit_behavior_tests.addIncludePath(b.path("./lib"));
    emit_behavior_tests.linkLibrary(parser_lib);
    emit_behavior_tests.linkLibC();
    const run_emit_behavior_tests = b.addRunArtifact(emit_behavior_tests);
    const orchestrator_embed_mod = b.createModule(.{
        .root_source_file = b.path("orchestrator_embed_module.zig"),
        .target = target,
        .optimize = optimize,
    });
    const orchestrator_embed_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/orchestrator/embed_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    orchestrator_embed_tests_mod.addImport("orchestrator_embed", orchestrator_embed_mod);
    const orchestrator_embed_tests = b.addTest(.{
        .root_module = orchestrator_embed_tests_mod,
    });
    const run_orchestrator_embed_tests = b.addRunArtifact(orchestrator_embed_tests);
    const orchestrator_workspace_mod = b.createModule(.{
        .root_source_file = b.path("lib/orchestrator/workspace.zig"),
        .target = target,
        .optimize = optimize,
    });
    orchestrator_workspace_mod.addImport("orchestrator_embed", orchestrator_embed_mod);
    const orchestrator_workspace_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/orchestrator/workspace_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    orchestrator_workspace_tests_mod.addImport("orchestrator_workspace", orchestrator_workspace_mod);
    orchestrator_workspace_tests_mod.addImport("orchestrator_embed", orchestrator_embed_mod);
    const orchestrator_workspace_tests = b.addTest(.{
        .root_module = orchestrator_workspace_tests_mod,
    });
    const run_orchestrator_workspace_tests = b.addRunArtifact(orchestrator_workspace_tests);
    const orchestrator_subprocess_mod = b.createModule(.{
        .root_source_file = b.path("lib/orchestrator/subprocess.zig"),
        .target = target,
        .optimize = optimize,
    });
    const orchestrator_subprocess_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/orchestrator/subprocess_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    orchestrator_subprocess_tests_mod.addImport("orchestrator_subprocess", orchestrator_subprocess_mod);
    const orchestrator_subprocess_tests = b.addTest(.{
        .root_module = orchestrator_subprocess_tests_mod,
    });
    const run_orchestrator_subprocess_tests = b.addRunArtifact(orchestrator_subprocess_tests);
    const orchestrator_finalize_mod = b.createModule(.{
        .root_source_file = b.path("lib/orchestrator/finalize.zig"),
        .target = target,
        .optimize = optimize,
    });
    orchestrator_finalize_mod.addImport("orchestrator_workspace", orchestrator_workspace_mod);
    const orchestrator_finalize_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/orchestrator/finalize_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    orchestrator_finalize_tests_mod.addImport("orchestrator_workspace", orchestrator_workspace_mod);
    orchestrator_finalize_tests_mod.addImport("orchestrator_finalize", orchestrator_finalize_mod);
    const orchestrator_finalize_tests = b.addTest(.{
        .root_module = orchestrator_finalize_tests_mod,
    });
    const run_orchestrator_finalize_tests = b.addRunArtifact(orchestrator_finalize_tests);

    var maybe_run_inprocess_tests: ?*std.Build.Step.Run = null;
    if (need_inprocess_side_module) {
        const inprocess_tests_mod = b.createModule(.{
            .root_source_file = b.path("tests/orchestrator/inprocess_test.zig"),
            .target = target,
            .optimize = optimize,
        });
        inprocess_tests_mod.addImport("orchestrator_inprocess", maybe_inprocess_mod.?);
        inprocess_tests_mod.addImport("orchestrator_workspace", orchestrator_workspace_mod);
        const inprocess_tests = b.addTest(.{
            .root_module = inprocess_tests_mod,
        });
        if (use_stub_inprocess_graph) {
            linkInprocessForStub(inprocess_tests, link_prebuilt_inprocess_archive, prebuilt_libinprocess_lp, maybe_inprocess_static_lib);
        }
        maybe_run_inprocess_tests = b.addRunArtifact(inprocess_tests);
    }

    const orchestrator_main_mod = b.createModule(.{
        .root_source_file = b.path("lib/orchestrator/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    orchestrator_main_mod.addImport("orchestrator_workspace", orchestrator_workspace_mod);
    orchestrator_main_mod.addImport("orchestrator_subprocess", orchestrator_subprocess_mod);
    orchestrator_main_mod.addImport("orchestrator_finalize", orchestrator_finalize_mod);
    orchestrator_main_mod.addOptions("orchestrator_build_options", orchestrator_route_opts);
    if (!orchestrator_subprocess_for_wasm) {
        orchestrator_main_mod.addImport("orchestrator_inprocess", maybe_inprocess_mod.?);
    }
    const orchestrator_main_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/orchestrator/main_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    orchestrator_main_tests_mod.addImport("translate", translate_mod);
    orchestrator_main_tests_mod.addImport("resolver", resolver_mod);
    orchestrator_main_tests_mod.addImport("validator_run", validator_run_mod);
    orchestrator_main_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    orchestrator_main_tests_mod.addImport("emit_main", emit_main_mod);
    orchestrator_main_tests_mod.addImport("orchestrator_main", orchestrator_main_mod);
    const orchestrator_main_tests = b.addTest(.{
        .root_module = orchestrator_main_tests_mod,
    });
    orchestrator_main_tests.addIncludePath(b.path("."));
    orchestrator_main_tests.addIncludePath(b.path("./lib"));
    orchestrator_main_tests.linkLibrary(parser_lib);
    orchestrator_main_tests.linkLibC();
    if (use_stub_inprocess_graph) {
        linkInprocessForStub(orchestrator_main_tests, link_prebuilt_inprocess_archive, prebuilt_libinprocess_lp, maybe_inprocess_static_lib);
    }
    const run_orchestrator_main_tests = b.addRunArtifact(orchestrator_main_tests);

    const stub_link_smoke_step = b.step(
        "stub-link-smoke",
        "FFI stub + libinprocess: compile minimal workspace to wasm (link proof)",
    );
    if (maybe_inprocess_static_lib) |ilib| {
        const stub_smoke_inprocess_mod = b.createModule(.{
            .root_source_file = b.path("lib/orchestrator/inprocess_stub.zig"),
            .target = target,
            .optimize = optimize,
        });
        addInprocessWasmBuildOptions(b, stub_smoke_inprocess_mod);
        const stub_link_smoke_root = b.createModule(.{
            .root_source_file = b.path("tests/orchestrator/stub_link_smoke_main.zig"),
            .target = target,
            .optimize = optimize,
        });
        stub_link_smoke_root.addImport("orchestrator_workspace", orchestrator_workspace_mod);
        stub_link_smoke_root.addImport("orchestrator_inprocess", stub_smoke_inprocess_mod);
        const stub_link_smoke_exe = b.addExecutable(.{
            .name = "stub-link-smoke",
            .root_module = stub_link_smoke_root,
        });
        stub_link_smoke_exe.linkLibrary(ilib);
        stub_link_smoke_exe.linkLibC();
        const run_stub_link_smoke = b.addRunArtifact(stub_link_smoke_exe);
        stub_link_smoke_step.dependOn(&run_stub_link_smoke.step);
    } else {
        stub_link_smoke_step.dependOn(&b.addFail(
            \\stub-link-smoke requires libinprocess.a — build with ZIG_COMPILER_SRC (zig build inprocess-lib) or provide prebuilt/libinprocess.a for linking steps that need it.
        ).step);
    }

    const cli_args_mod = b.createModule(.{
        .root_source_file = b.path("lib/cli/args.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cli_inspect_dump_mod = b.createModule(.{
        .root_source_file = b.path("lib/cli/inspect_dump.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cli_args_tests = b.addTest(.{
        .root_module = cli_args_mod,
    });
    const run_cli_args_tests = b.addRunArtifact(cli_args_tests);
    const cli_integration_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/cli/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cli_integration_tests = b.addTest(.{
        .root_module = cli_integration_tests_mod,
    });
    const run_cli_integration_tests = b.addRunArtifact(cli_integration_tests);
    const resolver_file_loader_mod = b.createModule(.{
        .root_source_file = b.path("lib/resolver/file_loader.zig"),
        .target = target,
        .optimize = optimize,
    });
    const resolver_builtins_mod = b.createModule(.{
        .root_source_file = b.path("lib/resolver/builtins.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_file_loader_mod.addImport("builtins", resolver_builtins_mod);
    const resolver_scan_imports_mod = b.createModule(.{
        .root_source_file = b.path("lib/resolver/scan_imports.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_scan_imports_mod.addImport("translate", translate_mod);
    resolver_scan_imports_mod.addImport("diagnostics", validator_diagnostics_mod);
    resolver_scan_imports_mod.addImport("file_loader", resolver_file_loader_mod);
    resolver_scan_imports_mod.addImport("builtins", resolver_builtins_mod);
    const resolver_scan_imports_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/resolver/scan_imports_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_scan_imports_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    resolver_scan_imports_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    const resolver_scan_imports_tests = b.addTest(.{
        .root_module = resolver_scan_imports_tests_mod,
    });
    resolver_scan_imports_tests.addIncludePath(b.path("."));
    resolver_scan_imports_tests.addIncludePath(b.path("./lib"));
    resolver_scan_imports_tests.linkLibrary(parser_lib);
    resolver_scan_imports_tests.linkLibC();
    const run_resolver_scan_imports_tests = b.addRunArtifact(resolver_scan_imports_tests);
    const resolver_import_cycle_mod = b.createModule(.{
        .root_source_file = b.path("lib/resolver/import_cycle.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_import_cycle_mod.addImport("diagnostics", validator_diagnostics_mod);
    resolver_import_cycle_mod.addImport("scan_imports", resolver_scan_imports_mod);
    resolver_import_cycle_mod.addImport("file_loader", resolver_file_loader_mod);
    const resolver_import_cycle_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/resolver/import_cycle_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_import_cycle_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    resolver_import_cycle_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    resolver_import_cycle_tests_mod.addImport("import_cycle", resolver_import_cycle_mod);
    const resolver_import_cycle_tests = b.addTest(.{
        .root_module = resolver_import_cycle_tests_mod,
    });
    resolver_import_cycle_tests.addIncludePath(b.path("."));
    resolver_import_cycle_tests.addIncludePath(b.path("./lib"));
    resolver_import_cycle_tests.linkLibrary(parser_lib);
    resolver_import_cycle_tests.linkLibC();
    const run_resolver_import_cycle_tests = b.addRunArtifact(resolver_import_cycle_tests);
    const resolver_resolve_bodies_mod = b.createModule(.{
        .root_source_file = b.path("lib/resolver/resolve_bodies.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_resolve_bodies_mod.addImport("translate", translate_mod);
    resolver_resolve_bodies_mod.addImport("resolver", resolver_mod);
    resolver_resolve_bodies_mod.addImport("ir_types", ir_types_mod);
    resolver_resolve_bodies_mod.addImport("scan_imports", resolver_scan_imports_mod);
    resolver_resolve_bodies_mod.addImport("file_loader", resolver_file_loader_mod);
    const resolver_resolve_bodies_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/resolver/resolve_bodies_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_resolve_bodies_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    resolver_resolve_bodies_tests_mod.addImport("import_cycle", resolver_import_cycle_mod);
    resolver_resolve_bodies_tests_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    resolver_resolve_bodies_tests_mod.addImport("ir_types", ir_types_mod);
    const resolver_resolve_bodies_tests = b.addTest(.{
        .root_module = resolver_resolve_bodies_tests_mod,
    });
    resolver_resolve_bodies_tests.addIncludePath(b.path("."));
    resolver_resolve_bodies_tests.addIncludePath(b.path("./lib"));
    resolver_resolve_bodies_tests.linkLibrary(parser_lib);
    resolver_resolve_bodies_tests.linkLibC();
    const run_resolver_resolve_bodies_tests = b.addRunArtifact(resolver_resolve_bodies_tests);
    const resolver_builtins_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/resolver/builtins_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_builtins_tests_mod.addImport("builtins", resolver_builtins_mod);
    resolver_builtins_tests_mod.addImport("translate", translate_mod);
    const resolver_builtins_tests = b.addTest(.{
        .root_module = resolver_builtins_tests_mod,
    });
    resolver_builtins_tests.addIncludePath(b.path("."));
    resolver_builtins_tests.addIncludePath(b.path("./lib"));
    resolver_builtins_tests.linkLibrary(parser_lib);
    resolver_builtins_tests.linkLibC();
    const run_resolver_builtins_tests = b.addRunArtifact(resolver_builtins_tests);
    const resolver_file_loader_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/resolver/file_loader_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_file_loader_tests_mod.addImport("file_loader", resolver_file_loader_mod);
    resolver_file_loader_tests_mod.addImport("builtins", resolver_builtins_mod);
    const resolver_file_loader_tests = b.addTest(.{
        .root_module = resolver_file_loader_tests_mod,
    });
    resolver_file_loader_tests.addIncludePath(b.path("."));
    resolver_file_loader_tests.addIncludePath(b.path("./lib"));
    resolver_file_loader_tests.linkLibrary(parser_lib);
    resolver_file_loader_tests.linkLibC();
    const run_resolver_file_loader_tests = b.addRunArtifact(resolver_file_loader_tests);
    const circ_compile_mod = b.createModule(.{
        .root_source_file = b.path("cmd/circ-compile/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    circ_compile_mod.addImport("cli_args", cli_args_mod);
    circ_compile_mod.addImport("translate", translate_mod);
    circ_compile_mod.addImport("resolver", resolver_mod);
    circ_compile_mod.addImport("diagnostics", validator_diagnostics_mod);
    circ_compile_mod.addImport("validator_run", validator_run_mod);
    circ_compile_mod.addImport("validator_run_project", validator_run_project_mod);
    circ_compile_mod.addImport("emit_main", emit_main_mod);
    circ_compile_mod.addImport("orchestrator_main", orchestrator_main_mod);
    circ_compile_mod.addImport("inspect_dump", cli_inspect_dump_mod);
    circ_compile_mod.addImport("scan_imports", resolver_scan_imports_mod);
    circ_compile_mod.addImport("import_cycle", resolver_import_cycle_mod);
    circ_compile_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    circ_compile_mod.addImport("ir_types", ir_types_mod);
    if (!use_stub_inprocess_graph) {
        if (zig_compiler_embed_mod) |zm| {
            circ_compile_mod.addImport("zig_compiler", zm);
        }
    }
    const circ_compile_exe = b.addExecutable(.{
        .name = "circ-compile",
        .root_module = circ_compile_mod,
    });
    circ_compile_exe.addIncludePath(b.path("."));
    circ_compile_exe.addIncludePath(b.path("./lib"));
    circ_compile_exe.linkLibrary(parser_lib);
    circ_compile_exe.linkLibC();
    if (use_stub_inprocess_graph) {
        linkInprocessForStub(circ_compile_exe, link_prebuilt_inprocess_archive, prebuilt_libinprocess_lp, maybe_inprocess_static_lib);
    }
    b.installArtifact(circ_compile_exe);
    const circ_compile_step = b.step("circ-compile", "Build circ-compile CLI");
    circ_compile_step.dependOn(b.getInstallStep());
    const validator_project_passes_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/validator/project_passes_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    validator_project_passes_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    validator_project_passes_tests_mod.addImport("import_cycle", resolver_import_cycle_mod);
    validator_project_passes_tests_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    validator_project_passes_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    validator_project_passes_tests_mod.addImport("ir_types", ir_types_mod);
    validator_project_passes_tests_mod.addImport("validator_run_project", validator_run_project_mod);
    const validator_project_passes_tests = b.addTest(.{
        .root_module = validator_project_passes_tests_mod,
    });
    validator_project_passes_tests.addIncludePath(b.path("."));
    validator_project_passes_tests.addIncludePath(b.path("./lib"));
    validator_project_passes_tests.linkLibrary(parser_lib);
    validator_project_passes_tests.linkLibC();
    const run_validator_project_passes_tests = b.addRunArtifact(validator_project_passes_tests);
    const validator_codes_snapshot_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/validator/codes_snapshot_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    validator_codes_snapshot_tests_mod.addImport("translate", translate_mod);
    validator_codes_snapshot_tests_mod.addImport("resolver", resolver_mod);
    validator_codes_snapshot_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    validator_codes_snapshot_tests_mod.addImport("validator_run", validator_run_mod);
    validator_codes_snapshot_tests_mod.addImport("validator_run_project", validator_run_project_mod);
    validator_codes_snapshot_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    validator_codes_snapshot_tests_mod.addImport("import_cycle", resolver_import_cycle_mod);
    validator_codes_snapshot_tests_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    validator_codes_snapshot_tests_mod.addImport("golden", golden_mod);
    const validator_codes_snapshot_tests = b.addTest(.{
        .root_module = validator_codes_snapshot_tests_mod,
    });
    validator_codes_snapshot_tests.addIncludePath(b.path("."));
    validator_codes_snapshot_tests.addIncludePath(b.path("./lib"));
    validator_codes_snapshot_tests.linkLibrary(parser_lib);
    validator_codes_snapshot_tests.linkLibC();
    const run_validator_codes_snapshot_tests = b.addRunArtifact(validator_codes_snapshot_tests);
    const test_step = b.step("test", "Run project test suite");
    test_step.dependOn(&run_golden_tests.step);
    test_step.dependOn(&run_translate_tests.step);
    test_step.dependOn(&run_ir_types_tests.step);
    test_step.dependOn(&run_resolver_tests.step);
    test_step.dependOn(&run_validator_tests.step);
    test_step.dependOn(&run_validator_name_passes_tests.step);
    test_step.dependOn(&run_validator_structural_tests.step);
    test_step.dependOn(&run_validator_loop_tests.step);
    test_step.dependOn(&run_validator_run_tests.step);
    test_step.dependOn(&run_validator_codes_snapshot_tests.step);
    test_step.dependOn(&run_emit_build_fn_tests.step);
    test_step.dependOn(&run_emit_metadata_tests.step);
    test_step.dependOn(&run_emit_full_tests.step);
    test_step.dependOn(&run_emit_behavior_tests.step);
    test_step.dependOn(&run_orchestrator_embed_tests.step);
    test_step.dependOn(&run_orchestrator_workspace_tests.step);
    test_step.dependOn(&run_orchestrator_subprocess_tests.step);
    test_step.dependOn(&run_orchestrator_finalize_tests.step);
    if (maybe_run_inprocess_tests) |r| test_step.dependOn(&r.step);
    test_step.dependOn(&run_orchestrator_main_tests.step);
    test_step.dependOn(&run_cli_args_tests.step);
    test_step.dependOn(&circ_compile_exe.step);
    test_step.dependOn(&run_cli_integration_tests.step);
    test_step.dependOn(&run_resolver_scan_imports_tests.step);
    test_step.dependOn(&run_resolver_import_cycle_tests.step);
    test_step.dependOn(&run_resolver_resolve_bodies_tests.step);
    test_step.dependOn(&run_resolver_builtins_tests.step);
    test_step.dependOn(&run_resolver_file_loader_tests.step);
    test_step.dependOn(&run_validator_project_passes_tests.step);

    const emit_project_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/emit/project_emit_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_project_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    emit_project_tests_mod.addImport("import_cycle", resolver_import_cycle_mod);
    emit_project_tests_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    emit_project_tests_mod.addImport("validator_run_project", validator_run_project_mod);
    emit_project_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    emit_project_tests_mod.addImport("emit_main", emit_main_mod);
    emit_project_tests_mod.addImport("golden", golden_mod);
    const emit_project_tests = b.addTest(.{
        .root_module = emit_project_tests_mod,
    });
    emit_project_tests.addIncludePath(b.path("."));
    emit_project_tests.addIncludePath(b.path("./lib"));
    emit_project_tests.linkLibrary(parser_lib);
    emit_project_tests.linkLibC();
    const run_emit_project_tests = b.addRunArtifact(emit_project_tests);
    test_step.dependOn(&run_emit_project_tests.step);

    const project_behavior_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/emit/project_behavior_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    project_behavior_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    project_behavior_tests_mod.addImport("import_cycle", resolver_import_cycle_mod);
    project_behavior_tests_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    project_behavior_tests_mod.addImport("validator_run_project", validator_run_project_mod);
    project_behavior_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    project_behavior_tests_mod.addImport("emit_main", emit_main_mod);
    project_behavior_tests_mod.addImport("emit_project", emit_project_mod);
    project_behavior_tests_mod.addImport("ir_types", ir_types_mod);
    project_behavior_tests_mod.addImport("wasm_run", wasm_run_mod);
    const project_behavior_tests = b.addTest(.{
        .root_module = project_behavior_tests_mod,
    });
    project_behavior_tests.addIncludePath(b.path("."));
    project_behavior_tests.addIncludePath(b.path("./lib"));
    project_behavior_tests.linkLibrary(parser_lib);
    project_behavior_tests.linkLibC();
    const run_project_behavior_tests = b.addRunArtifact(project_behavior_tests);
    test_step.dependOn(&run_project_behavior_tests.step);

    const e2e_linux_docker_step = b.step(
        "e2e-linux-docker",
        "Linux Docker E2E: host-built ELF, inspect / emit-zig / wasm / Node (requires Docker)",
    );
    const run_e2e_linux_docker = b.addSystemCommand(&.{
        "bash",
        "tests/e2e/linux-docker/run.sh",
    });
    e2e_linux_docker_step.dependOn(&run_e2e_linux_docker.step);
}
