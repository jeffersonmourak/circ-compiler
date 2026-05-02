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
    translate_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
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
    resolver_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
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
    validator_name_passes_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
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
    validator_structural_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
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
    validator_loop_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
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
    validator_run_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
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
    emit_build_fn_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
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
    emit_metadata_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
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
    emit_full_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
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
    const test_step = b.step("test", "Run project test suite");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_golden_tests.step);
    test_step.dependOn(&run_translate_tests.step);
    test_step.dependOn(&run_ir_types_tests.step);
    test_step.dependOn(&run_resolver_tests.step);
    test_step.dependOn(&run_validator_tests.step);
    test_step.dependOn(&run_validator_name_passes_tests.step);
    test_step.dependOn(&run_validator_structural_tests.step);
    test_step.dependOn(&run_validator_loop_tests.step);
    test_step.dependOn(&run_validator_run_tests.step);
    test_step.dependOn(&run_emit_build_fn_tests.step);
    test_step.dependOn(&run_emit_metadata_tests.step);
    test_step.dependOn(&run_emit_full_tests.step);
    test_step.dependOn(&run_emit_behavior_tests.step);
    test_step.dependOn(&run_orchestrator_embed_tests.step);
    test_step.dependOn(&run_orchestrator_workspace_tests.step);
}
