// build.zig
const std = @import("std");

const GRAMMAR_FILE = "lib/grammar/proto-circ.peg";

pub fn build(b: *std.Build) void {
    //
    // Build the application
    //
    const target = b.standardTargetOptions(.{});
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const optimize = b.standardOptimizeOption(.{});

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
    // parser_lib.step.dependOn(&generate_parser_cmd.step);

    //
    // Build the application
    //
    const exe_debug_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const compiler_mod = b.createModule(.{
        .root_source_file = b.path("lib/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });

    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("lib/wasm.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });

    // Set export symbols for WASM
    wasm_mod.export_symbol_names = &.{ "init", "deinit", "createComponent", "connect", "propagateEvent", "propagate", "getComponentState", "freeLogMessage" };

    const wasm_lib = b.addExecutable(.{
        .name = "circ-renderer-lib-wasm",
        .root_module = wasm_mod,
    });

    wasm_lib.addIncludePath(b.path("./lib"));
    wasm_lib.addLibraryPath(b.path("./lib"));

    // wasm_lib.linkSystemLibrary("parser");
    // wasm_lib.linkLibC();

    wasm_lib.entry = .disabled;
    wasm_lib.rdynamic = false;

    b.installArtifact(wasm_lib);

    const exe = b.addExecutable(.{
        .name = "logic-sim",
        .root_module = exe_debug_mod,
    });

    exe.addIncludePath(b.path("./lib"));

    exe.linkLibrary(parser_lib);

    exe.linkLibC();

    b.installArtifact(exe);

    const compiler = b.addExecutable(.{
        .name = "compiler",
        .root_module = compiler_mod,
    });

    compiler.addIncludePath(b.path("./lib"));

    compiler.linkLibrary(parser_lib);

    compiler.linkLibC();

    b.installArtifact(compiler);

    const compiler_run_cmd = b.addRunArtifact(compiler);
    compiler_run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        compiler_run_cmd.addArgs(args);
    }

    const compiler_step = b.step("compiler", "Build the compiler");

    const compiler_cmd = b.addRunArtifact(compiler);
    compiler_cmd.step.dependOn(b.getInstallStep());

    // compiler_step.dependOn(&generate_parser_cmd.step);
    compiler_step.dependOn(&compiler_cmd.step);

    const compiler_run_step = b.step("compiler:run", "Run the compiler");
    // compiler_run_step.dependOn(&generate_parser_cmd.step);
    compiler_run_step.dependOn(&compiler_run_cmd.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    // run_step.dependOn(&generate_parser_cmd.step);
    run_step.dependOn(&run_cmd.step);

    const wasm_step = b.step("wasm", "Build the application for WebAssembly");

    const install_wasm_step = b.addInstallFile(
        wasm_lib.getEmittedBin(),
        "wasm/circ-renderer-lib.wasm",
    );

    // wasm_step.dependOn(&generate_parser_cmd.step);
    wasm_step.dependOn(&wasm_lib.step);
    wasm_step.dependOn(&install_wasm_step.step);

    const wasm_src_step = b.addInstallFile(
        wasm_lib.getEmittedBin(),
        "../example/circ-renderer-lib.wasm",
    );

    wasm_step.dependOn(&wasm_src_step.step);

    const unit_tests = b.addTest(.{
        .root_module = exe_debug_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const golden_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/helpers/golden_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_golden_tests = b.addRunArtifact(golden_tests);
    const test_step = b.step("test", "Run project test suite");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_golden_tests.step);
}
