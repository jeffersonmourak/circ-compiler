const std = @import("std");

const GRAMMAR_FILE = "lib/grammar/proto-circ.peg";

// Link the langlang Go c-archive (lib/parser/parser.a) into a Compile step.
// Skips wrapping the archive in a Zig Library because `zig build-lib` on Linux
// can't re-bundle a CGo c-archive into another static archive cross-platform;
// adding it as a direct object file lets each consumer's linker handle it.
fn linkParserArchive(b: *std.Build, compile: *std.Build.Step.Compile, build_archive_cmd: *std.Build.Step.Run) void {
    compile.addObjectFile(b.path("lib/parser/parser.a"));
    compile.step.dependOn(&build_archive_cmd.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const parser_gen = b.step("parser:gen", "Generate Go Parser");

    const generate_parser_cmd = b.addSystemCommand(&.{
        "langlang",
        "-grammar",
        GRAMMAR_FILE,
        "-disable-capture-spaces",
        "-output-language",
        "go",
        "-output-path",
        "lib/parser/parser.go",
        "-go-package",
        "parser",
        "-go-parser",
        "Parser",
    });

    parser_gen.dependOn(&generate_parser_cmd.step);

    const parser_archive = b.step("parser:archive", "Build CGo c-archive (lib/parser/parser.a) from Go shim");

    // Tell Go to cross-compile to the same arch/OS as the Zig target. Without
    // this, a Go toolchain installed for amd64 (e.g. running under Rosetta on
    // Apple Silicon) emits an x86_64 archive that the arm64 linker rejects.
    const goarch = switch (target.result.cpu.arch) {
        .aarch64 => "arm64",
        .x86_64 => "amd64",
        else => @panic("unsupported CPU arch for Go c-archive build"),
    };
    const goos = switch (target.result.os.tag) {
        .macos => "darwin",
        .linux => "linux",
        .windows => "windows",
        else => @panic("unsupported OS for Go c-archive build"),
    };

    // Route Go's CGo C compiler through `zig cc -target <triple>`. Go's
    // runtime/cgo includes Linux-only C (linux_syscall.c uses setresuid /
    // setresgid) that the host's clang can't compile when cross-building
    // from macOS. Zig's bundled libc headers cover every target triple, so
    // using it as CC makes both native and cross-builds hermetic.
    const zig_triple = target.result.zigTriple(b.allocator) catch @panic("OOM");
    const cc_value = b.fmt("zig cc -target {s}", .{zig_triple});

    const build_archive_cmd = b.addSystemCommand(&.{
        "go",
        "build",
        "-buildmode=c-archive",
        "-o",
        "parser.a",
        "./shim",
    });
    build_archive_cmd.setCwd(b.path("lib/parser"));
    build_archive_cmd.setEnvironmentVariable("GOARCH", goarch);
    build_archive_cmd.setEnvironmentVariable("GOOS", goos);
    build_archive_cmd.setEnvironmentVariable("CGO_ENABLED", "1");
    build_archive_cmd.setEnvironmentVariable("CC", cc_value);

    parser_archive.dependOn(&build_archive_cmd.step);

    const golden_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/helpers/golden_test.zig"),
            .target = target,
            .optimize = optimize,
            // golden_test.zig uses @cImport to call setenv/unsetenv. macOS
            // SDK ships libc headers by default; Linux runners need an
            // explicit link_libc flag for Zig to find <stdlib.h>.
            .link_libc = true,
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
    linkParserArchive(b, translate_tests, build_archive_cmd);
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
    linkParserArchive(b, resolver_tests, build_archive_cmd);
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
    linkParserArchive(b, validator_name_passes_tests, build_archive_cmd);
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
    linkParserArchive(b, validator_structural_tests, build_archive_cmd);
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
    linkParserArchive(b, validator_loop_tests, build_archive_cmd);
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
    linkParserArchive(b, validator_run_tests, build_archive_cmd);
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
    linkParserArchive(b, emit_build_fn_tests, build_archive_cmd);
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
    linkParserArchive(b, emit_metadata_tests, build_archive_cmd);
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
    linkParserArchive(b, emit_full_tests, build_archive_cmd);
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
    linkParserArchive(b, emit_behavior_tests, build_archive_cmd);
    emit_behavior_tests.linkLibC();
    const run_emit_behavior_tests = b.addRunArtifact(emit_behavior_tests);
    // Phase 3 slice 1: color resolution module (depends only on std, used by cli_args).
    const preview_render_color_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/render/color.zig"),
        .target = target,
        .optimize = optimize,
    });
    const preview_render_color_tests = b.addTest(.{
        .root_module = preview_render_color_mod,
    });
    const run_preview_render_color_tests = b.addRunArtifact(preview_render_color_tests);

    // Phase 3 slice 2: Canvas — in-memory cell grid with per-cell color tags.
    const preview_render_canvas_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/render/canvas.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_render_canvas_mod.addImport("color", preview_render_color_mod);
    const preview_render_canvas_tests = b.addTest(.{
        .root_module = preview_render_canvas_mod,
    });
    const run_preview_render_canvas_tests = b.addRunArtifact(preview_render_canvas_tests);

    // Phase 3 slice 3: glyphs — per-kind drawing functions that fill a Canvas.
    // (preview_layout_mod is already declared earlier in the build script.)

    const cli_args_mod = b.createModule(.{
        .root_source_file = b.path("lib/cli/args.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_args_mod.addImport("render_color", preview_render_color_mod);
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
    linkParserArchive(b, resolver_scan_imports_tests, build_archive_cmd);
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
    linkParserArchive(b, resolver_import_cycle_tests, build_archive_cmd);
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
    resolver_resolve_bodies_mod.addImport("diagnostics", validator_diagnostics_mod);
    const resolver_resolve_bodies_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/resolver/resolve_bodies_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_resolve_bodies_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    resolver_resolve_bodies_tests_mod.addImport("import_cycle", resolver_import_cycle_mod);
    resolver_resolve_bodies_tests_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    resolver_resolve_bodies_tests_mod.addImport("ir_types", ir_types_mod);
    resolver_resolve_bodies_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    const resolver_resolve_bodies_tests = b.addTest(.{
        .root_module = resolver_resolve_bodies_tests_mod,
    });
    resolver_resolve_bodies_tests.addIncludePath(b.path("."));
    resolver_resolve_bodies_tests.addIncludePath(b.path("./lib"));
    linkParserArchive(b, resolver_resolve_bodies_tests, build_archive_cmd);
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
    linkParserArchive(b, resolver_builtins_tests, build_archive_cmd);
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
    linkParserArchive(b, resolver_file_loader_tests, build_archive_cmd);
    resolver_file_loader_tests.linkLibC();
    const run_resolver_file_loader_tests = b.addRunArtifact(resolver_file_loader_tests);

    // --- Pre-built Runtime WASM ---
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    
    // We create a dummy compiled.zig file for the runtime embed
    const write_dummy_compiled = b.addWriteFiles();
    const dummy_compiled_file = write_dummy_compiled.add("compiled.zig", "pub const is_prebuilt_runtime = true;\n");

    const runtime_module = b.createModule(.{
        .root_source_file = b.path("templates/main.zig"),
        .target = wasm_target,
        .optimize = optimize, // Usually ReleaseSmall or ReleaseFast for WASM, but follow global optimize option
    });
    
    runtime_module.addImport("compiled.zig", b.createModule(.{
        .root_source_file = dummy_compiled_file,
        .target = wasm_target,
        .optimize = optimize,
    }));
    
    // build_options with collect_metrics=false for non-bench circuit consumers.
    // The bench step creates its own options with collect_metrics=true and a
    // parallel circuit module that imports them — see `zig build bench` below.
    //
    // The options step is materialized into a Module exactly once. Both
    // circuit_mod_for_wasm and memory_mod_for_wasm import that same module
    // by name. Calling `addOptions("build_options", step)` twice with the
    // same step would create two distinct anonymous build_options modules
    // pointing at the same file, which Zig rejects with
    // "file exists in modules 'build_options' and 'build_options0'".
    const circuit_options_default = b.addOptions();
    circuit_options_default.addOption(bool, "collect_metrics", false);
    const circuit_options_default_mod = circuit_options_default.createModule();

    const circuit_mod_for_wasm = b.createModule(.{
        .root_source_file = b.path("lib/circuit.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    circuit_mod_for_wasm.addImport("build_options", circuit_options_default_mod);

    const memory_mod_for_wasm = b.createModule(.{
        .root_source_file = b.path("lib/memory.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    // memory.zig now imports build_options for the COLLECT_METRICS gate. The
    // WASM runtime keeps it off (zero overhead), same as every non-bench path.
    memory_mod_for_wasm.addImport("build_options", circuit_options_default_mod);
    
    const transport_mod_for_wasm = b.createModule(.{
        .root_source_file = b.path("lib/transport.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    
    const log_mod_for_wasm = b.createModule(.{
        .root_source_file = b.path("lib/log.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    
    log_mod_for_wasm.addImport("memory.zig", memory_mod_for_wasm);
    
    circuit_mod_for_wasm.addImport("memory.zig", memory_mod_for_wasm);
    circuit_mod_for_wasm.addImport("log.zig", log_mod_for_wasm);
    circuit_mod_for_wasm.addImport("transport.zig", transport_mod_for_wasm);
    
    transport_mod_for_wasm.addImport("circuit.zig", circuit_mod_for_wasm);
    
    const interpreter_mod_for_wasm = b.createModule(.{
        .root_source_file = b.path("templates/interpreter.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    
    const format_mod_for_wasm = b.createModule(.{
        .root_source_file = b.path("lib/topology/format.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    
    interpreter_mod_for_wasm.addImport("format", format_mod_for_wasm);
    interpreter_mod_for_wasm.addImport("circuit.zig", circuit_mod_for_wasm);
    
    runtime_module.addImport("circuit.zig", circuit_mod_for_wasm);
    runtime_module.addImport("memory.zig", memory_mod_for_wasm);
    runtime_module.addImport("interpreter.zig", interpreter_mod_for_wasm);
    
    const runtime_artifact = b.addExecutable(.{
        .name = "circ-runtime",
        .root_module = runtime_module,
    });
    runtime_artifact.entry = .disabled;
    runtime_artifact.rdynamic = true;
    
    // We install the WASM so we can use it as a dependency for the CLI embed
    const install_runtime = b.addInstallArtifact(runtime_artifact, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    
    const embed_write_files = b.addWriteFiles();
    _ = embed_write_files.addCopyFile(runtime_artifact.getEmittedBin(), "circ-runtime.wasm");
    const embed_zig_file = embed_write_files.add("runtime_embed.zig", 
        \\pub const runtime_wasm = @embedFile("circ-runtime.wasm");
    );
    
    const runtime_embed_mod = b.createModule(.{
        .root_source_file = embed_zig_file,
        .target = target,
        .optimize = optimize,
    });

    // Native build of the simulation engine. Used by the topology interpreter
    // tests and by the truth-table mode (which drives the engine on the host
    // to enumerate input vectors).
    const circuit_mod = b.createModule(.{
        .root_source_file = b.path("lib/circuit.zig"),
        .target = target,
        .optimize = optimize,
    });
    circuit_mod.addOptions("build_options", circuit_options_default);

    const topology_protocol_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/e2e/topology_protocol_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    topology_protocol_tests_mod.addImport("format", format_mod_for_wasm);
    topology_protocol_tests_mod.addImport("runtime_embed", runtime_embed_mod);
    const topology_protocol_tests = b.addTest(.{
        .root_module = topology_protocol_tests_mod,
    });
    const run_topology_protocol_tests = b.addRunArtifact(topology_protocol_tests);
    run_topology_protocol_tests.step.dependOn(&install_runtime.step);

    const analyze_mod = b.createModule(.{
        .root_source_file = b.path("lib/analyze/analyze.zig"),
        .target = target,
        .optimize = optimize,
    });
    analyze_mod.addImport("scan_imports", resolver_scan_imports_mod);
    analyze_mod.addImport("import_cycle", resolver_import_cycle_mod);
    analyze_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    analyze_mod.addImport("validator_run_project", validator_run_project_mod);
    analyze_mod.addImport("diagnostics", validator_diagnostics_mod);
    analyze_mod.addImport("ir_types", ir_types_mod);
    analyze_mod.addImport("translate", translate_mod);
    analyze_mod.addImport("file_loader", resolver_file_loader_mod);

    // Version (from the VERSION file) and HEAD revision (git, at configure
    // time) exposed to the CLI's --version flag. A missing file or git
    // failure degrades to "unknown" rather than breaking the build.
    const build_info = b.addOptions();
    {
        const version_raw = b.build_root.handle.readFileAlloc(b.allocator, "VERSION", 256) catch "unknown";
        const version = std.mem.trim(u8, version_raw, " \t\r\n");
        const revision = blk: {
            const result = std.process.Child.run(.{
                .allocator = b.allocator,
                .argv = &.{ "git", "rev-parse", "--short", "HEAD" },
                .cwd = b.build_root.path,
            }) catch break :blk "unknown";
            if (result.term != .Exited or result.term.Exited != 0) break :blk "unknown";
            const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
            break :blk if (trimmed.len == 0) "unknown" else trimmed;
        };
        build_info.addOption([]const u8, "version", version);
        build_info.addOption([]const u8, "revision", revision);
    }

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
    circ_compile_mod.addImport("inspect_dump", cli_inspect_dump_mod);
    circ_compile_mod.addImport("scan_imports", resolver_scan_imports_mod);
    circ_compile_mod.addImport("import_cycle", resolver_import_cycle_mod);
    circ_compile_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    circ_compile_mod.addImport("ir_types", ir_types_mod);
    circ_compile_mod.addImport("runtime_embed", runtime_embed_mod);
    circ_compile_mod.addImport("analyze", analyze_mod);
    circ_compile_mod.addOptions("build_info", build_info);
    const circ_compile_exe = b.addExecutable(.{
        .name = "circ-compile",
        .root_module = circ_compile_mod,
    });
    circ_compile_exe.step.dependOn(&install_runtime.step);
    circ_compile_exe.addIncludePath(b.path("."));
    circ_compile_exe.addIncludePath(b.path("./lib"));
    linkParserArchive(b, circ_compile_exe, build_archive_cmd);
    circ_compile_exe.linkLibC();
    b.installArtifact(circ_compile_exe);
    const circ_compile_step = b.step("circ-compile", "Build circ-compile CLI");
    circ_compile_step.dependOn(b.getInstallStep());

    const circ_compile_tests = b.addTest(.{
        .root_module = circ_compile_mod,
    });
    circ_compile_tests.addIncludePath(b.path("."));
    circ_compile_tests.addIncludePath(b.path("./lib"));
    linkParserArchive(b, circ_compile_tests, build_archive_cmd);
    circ_compile_tests.linkLibC();
    const run_circ_compile_tests = b.addRunArtifact(circ_compile_tests);
    run_circ_compile_tests.step.dependOn(&install_runtime.step);

    const analyze_tests = b.addTest(.{
        .root_module = analyze_mod,
    });
    analyze_tests.addIncludePath(b.path("."));
    analyze_tests.addIncludePath(b.path("./lib"));
    linkParserArchive(b, analyze_tests, build_archive_cmd);
    analyze_tests.linkLibC();
    const run_analyze_tests = b.addRunArtifact(analyze_tests);
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
    linkParserArchive(b, validator_project_passes_tests, build_archive_cmd);
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
    validator_codes_snapshot_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const validator_codes_snapshot_tests = b.addTest(.{
        .root_module = validator_codes_snapshot_tests_mod,
    });
    validator_codes_snapshot_tests.addIncludePath(b.path("."));
    validator_codes_snapshot_tests.addIncludePath(b.path("./lib"));
    linkParserArchive(b, validator_codes_snapshot_tests, build_archive_cmd);
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
    test_step.dependOn(&run_analyze_tests.step);
    test_step.dependOn(&run_emit_build_fn_tests.step);
    test_step.dependOn(&run_emit_metadata_tests.step);
    test_step.dependOn(&run_emit_full_tests.step);
    test_step.dependOn(&run_emit_behavior_tests.step);
    test_step.dependOn(&run_cli_args_tests.step);
    test_step.dependOn(&run_preview_render_color_tests.step);
    test_step.dependOn(&run_preview_render_canvas_tests.step);
    test_step.dependOn(&run_circ_compile_tests.step);
    test_step.dependOn(&circ_compile_exe.step);
    test_step.dependOn(&run_cli_integration_tests.step);
    test_step.dependOn(&run_resolver_scan_imports_tests.step);
    test_step.dependOn(&run_resolver_import_cycle_tests.step);
    test_step.dependOn(&run_resolver_resolve_bodies_tests.step);
    test_step.dependOn(&run_resolver_builtins_tests.step);
    test_step.dependOn(&run_resolver_file_loader_tests.step);
    test_step.dependOn(&run_validator_project_passes_tests.step);
    test_step.dependOn(&run_topology_protocol_tests.step);

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
    emit_project_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const emit_project_tests = b.addTest(.{
        .root_module = emit_project_tests_mod,
    });
    emit_project_tests.addIncludePath(b.path("."));
    emit_project_tests.addIncludePath(b.path("./lib"));
    linkParserArchive(b, emit_project_tests, build_archive_cmd);
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
    linkParserArchive(b, project_behavior_tests, build_archive_cmd);
    project_behavior_tests.linkLibC();
    const run_project_behavior_tests = b.addRunArtifact(project_behavior_tests);
    test_step.dependOn(&run_project_behavior_tests.step);

    const topology_format_tests_mod = b.createModule(.{
        .root_source_file = b.path("lib/topology/format.zig"),
        .target = target,
        .optimize = optimize,
    });
    const topology_format_tests = b.addTest(.{
        .root_module = topology_format_tests_mod,
    });
    const run_topology_format_tests = b.addRunArtifact(topology_format_tests);
    test_step.dependOn(&run_topology_format_tests.step);

    const topology_serializer_tests_mod = b.createModule(.{
        .root_source_file = b.path("lib/topology/serializer.zig"),
        .target = target,
        .optimize = optimize,
    });
    topology_serializer_tests_mod.addImport("format", topology_format_tests_mod);
    topology_serializer_tests_mod.addImport("ir_types", ir_types_mod);
    const topology_serializer_tests = b.addTest(.{
        .root_module = topology_serializer_tests_mod,
    });
    const run_topology_serializer_tests = b.addRunArtifact(topology_serializer_tests);
    test_step.dependOn(&run_topology_serializer_tests.step);

    const section_writer_mod = b.createModule(.{
        .root_source_file = b.path("lib/topology/section_writer.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Wire serializer and section_writer into the circ-compile binary
    circ_compile_mod.addImport("serializer", topology_serializer_tests_mod);
    circ_compile_mod.addImport("section_writer", section_writer_mod);
    circ_compile_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
    // full_serializer and preview_dump added below; the import wiring happens after the modules are created.

    const section_writer_tests = b.addTest(.{
        .root_module = section_writer_mod,
    });
    const run_section_writer_tests = b.addRunArtifact(section_writer_tests);
    test_step.dependOn(&run_section_writer_tests.step);

    // Phase 0 slice 3: circ.topology.v0.full schema + encoder + decoder
    const topology_full_format_mod = b.createModule(.{
        .root_source_file = b.path("lib/topology/full_format.zig"),
        .target = target,
        .optimize = optimize,
    });
    topology_full_format_mod.addImport("format", topology_format_tests_mod);
    const topology_full_format_tests = b.addTest(.{
        .root_module = topology_full_format_mod,
    });
    const run_topology_full_format_tests = b.addRunArtifact(topology_full_format_tests);
    test_step.dependOn(&run_topology_full_format_tests.step);

    const topology_full_serializer_mod = b.createModule(.{
        .root_source_file = b.path("lib/topology/full_serializer.zig"),
        .target = target,
        .optimize = optimize,
    });
    topology_full_serializer_mod.addImport("full_format", topology_full_format_mod);
    topology_full_serializer_mod.addImport("ir_types", ir_types_mod);
    circ_compile_mod.addImport("full_serializer", topology_full_serializer_mod);
    const topology_full_serializer_tests = b.addTest(.{
        .root_module = topology_full_serializer_mod,
    });
    const run_topology_full_serializer_tests = b.addRunArtifact(topology_full_serializer_tests);
    test_step.dependOn(&run_topology_full_serializer_tests.step);

    const topology_full_decoder_mod = b.createModule(.{
        .root_source_file = b.path("lib/topology/full_decoder.zig"),
        .target = target,
        .optimize = optimize,
    });
    topology_full_decoder_mod.addImport("full_format", topology_full_format_mod);
    const topology_full_decoder_tests = b.addTest(.{
        .root_module = topology_full_decoder_mod,
    });
    const run_topology_full_decoder_tests = b.addRunArtifact(topology_full_decoder_tests);
    test_step.dependOn(&run_topology_full_decoder_tests.step);

    const topology_full_roundtrip_mod = b.createModule(.{
        .root_source_file = b.path("tests/topology/full_roundtrip_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    topology_full_roundtrip_mod.addImport("full_format", topology_full_format_mod);
    topology_full_roundtrip_mod.addImport("full_serializer", topology_full_serializer_mod);
    topology_full_roundtrip_mod.addImport("full_decoder", topology_full_decoder_mod);
    const topology_full_roundtrip_tests = b.addTest(.{
        .root_module = topology_full_roundtrip_mod,
    });
    const run_topology_full_roundtrip_tests = b.addRunArtifact(topology_full_roundtrip_tests);
    test_step.dependOn(&run_topology_full_roundtrip_tests.step);

    // Phase 2 slice 1: layout public types + sizing constants
    const preview_layout_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/layout.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_layout_mod.addImport("full_format", topology_full_format_mod);
    const preview_layout_tests = b.addTest(.{
        .root_module = preview_layout_mod,
    });
    const run_preview_layout_tests = b.addRunArtifact(preview_layout_tests);
    test_step.dependOn(&run_preview_layout_tests.step);

    // Phase 1 slice 3: preview.dump.dump implementation (depends on layout types)
    const preview_dump_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/dump.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_dump_mod.addImport("full_format", topology_full_format_mod);
    preview_dump_mod.addImport("layout", preview_layout_mod);
    circ_compile_mod.addImport("preview_dump", preview_dump_mod);
    const preview_dump_tests = b.addTest(.{
        .root_module = preview_dump_mod,
    });
    const run_preview_dump_tests = b.addRunArtifact(preview_dump_tests);
    test_step.dependOn(&run_preview_dump_tests.step);

    // Shared engine session: builds a live engine.Circuit from a full topology
    // and resolves root pins by name. Consumed by the truth-table builder and
    // the --sim drive loop.
    const engine_session_mod = b.createModule(.{
        .root_source_file = b.path("lib/engine_session.zig"),
        .target = target,
        .optimize = optimize,
    });
    engine_session_mod.addImport("circuit", circuit_mod);
    engine_session_mod.addImport("full_format", topology_full_format_mod);
    const engine_session_tests = b.addTest(.{
        .root_module = engine_session_mod,
    });
    const run_engine_session_tests = b.addRunArtifact(engine_session_tests);
    test_step.dependOn(&run_engine_session_tests.step);

    // --sim drive protocol: a pure line-protocol codec (no I/O).
    const sim_protocol_mod = b.createModule(.{
        .root_source_file = b.path("lib/sim/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sim_protocol_tests = b.addTest(.{
        .root_module = sim_protocol_mod,
    });
    const run_sim_protocol_tests = b.addRunArtifact(sim_protocol_tests);
    test_step.dependOn(&run_sim_protocol_tests.step);

    // --sim drive loop: builds the circuit via engine_session and serves the
    // request/response protocol against it (set/get/run/eval/dump/reset).
    const sim_loop_mod = b.createModule(.{
        .root_source_file = b.path("lib/sim/loop.zig"),
        .target = target,
        .optimize = optimize,
    });
    sim_loop_mod.addImport("protocol", sim_protocol_mod);
    sim_loop_mod.addImport("engine_session", engine_session_mod);
    sim_loop_mod.addImport("circuit", circuit_mod);
    sim_loop_mod.addImport("full_format", topology_full_format_mod);
    sim_loop_mod.addImport("diagnostics", validator_diagnostics_mod);
    circ_compile_mod.addImport("sim_loop", sim_loop_mod);
    const sim_loop_tests = b.addTest(.{
        .root_module = sim_loop_mod,
    });
    const run_sim_loop_tests = b.addRunArtifact(sim_loop_tests);
    test_step.dependOn(&run_sim_loop_tests.step);

    // Truth-table mode: enumerates input vectors against a native engine.Circuit
    // built from the full topology, then renders to Markdown.
    const truth_table_builder_mod = b.createModule(.{
        .root_source_file = b.path("lib/truth_table/builder.zig"),
        .target = target,
        .optimize = optimize,
    });
    truth_table_builder_mod.addImport("circuit", circuit_mod);
    truth_table_builder_mod.addImport("full_format", topology_full_format_mod);
    truth_table_builder_mod.addImport("engine_session", engine_session_mod);
    circ_compile_mod.addImport("truth_table_builder", truth_table_builder_mod);
    const truth_table_builder_tests = b.addTest(.{
        .root_module = truth_table_builder_mod,
    });
    const run_truth_table_builder_tests = b.addRunArtifact(truth_table_builder_tests);
    test_step.dependOn(&run_truth_table_builder_tests.step);

    const truth_table_markdown_mod = b.createModule(.{
        .root_source_file = b.path("lib/truth_table/markdown.zig"),
        .target = target,
        .optimize = optimize,
    });
    truth_table_markdown_mod.addImport("builder", truth_table_builder_mod);
    truth_table_markdown_mod.addImport("circuit", circuit_mod);
    circ_compile_mod.addImport("truth_table_markdown", truth_table_markdown_mod);
    const truth_table_markdown_tests = b.addTest(.{
        .root_module = truth_table_markdown_mod,
    });
    const run_truth_table_markdown_tests = b.addRunArtifact(truth_table_markdown_tests);
    test_step.dependOn(&run_truth_table_markdown_tests.step);

    const truth_table_csv_mod = b.createModule(.{
        .root_source_file = b.path("lib/truth_table/csv.zig"),
        .target = target,
        .optimize = optimize,
    });
    truth_table_csv_mod.addImport("builder", truth_table_builder_mod);
    truth_table_csv_mod.addImport("circuit", circuit_mod);
    circ_compile_mod.addImport("truth_table_csv", truth_table_csv_mod);
    const truth_table_csv_tests = b.addTest(.{
        .root_module = truth_table_csv_mod,
    });
    const run_truth_table_csv_tests = b.addRunArtifact(truth_table_csv_tests);
    test_step.dependOn(&run_truth_table_csv_tests.step);

    const truth_table_json_mod = b.createModule(.{
        .root_source_file = b.path("lib/truth_table/json.zig"),
        .target = target,
        .optimize = optimize,
    });
    truth_table_json_mod.addImport("builder", truth_table_builder_mod);
    truth_table_json_mod.addImport("circuit", circuit_mod);
    circ_compile_mod.addImport("truth_table_json", truth_table_json_mod);
    const truth_table_json_tests = b.addTest(.{
        .root_module = truth_table_json_mod,
    });
    const run_truth_table_json_tests = b.addRunArtifact(truth_table_json_tests);
    test_step.dependOn(&run_truth_table_json_tests.step);

    const preview_layout_types_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/layout/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_layout_types_mod.addImport("full_format", topology_full_format_mod);
    preview_layout_types_mod.addImport("layout", preview_layout_mod);
    const preview_layout_types_tests = b.addTest(.{
        .root_module = preview_layout_types_mod,
    });
    const run_preview_layout_types_tests = b.addRunArtifact(preview_layout_types_tests);
    test_step.dependOn(&run_preview_layout_types_tests.step);

    const preview_layout_sizing_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/layout/sizing.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_layout_sizing_mod.addImport("full_format", topology_full_format_mod);
    const preview_layout_sizing_tests = b.addTest(.{
        .root_module = preview_layout_sizing_mod,
    });
    const run_preview_layout_sizing_tests = b.addRunArtifact(preview_layout_sizing_tests);
    test_step.dependOn(&run_preview_layout_sizing_tests.step);

    // Phase 2 slice 2: Stage 1 — collapse
    const preview_layout_collapse_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/layout/collapse.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_layout_collapse_mod.addImport("full_format", topology_full_format_mod);
    preview_layout_collapse_mod.addImport("layout", preview_layout_mod);
    preview_layout_collapse_mod.addImport("layout_types", preview_layout_types_mod);
    const preview_layout_collapse_tests = b.addTest(.{
        .root_module = preview_layout_collapse_mod,
    });
    const run_preview_layout_collapse_tests = b.addRunArtifact(preview_layout_collapse_tests);
    test_step.dependOn(&run_preview_layout_collapse_tests.step);

    // Phase 2 slice 3: Stage 2 — columns
    const preview_layout_columns_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/layout/columns.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_layout_columns_mod.addImport("full_format", topology_full_format_mod);
    preview_layout_columns_mod.addImport("layout_types", preview_layout_types_mod);
    const preview_layout_columns_tests = b.addTest(.{
        .root_module = preview_layout_columns_mod,
    });
    const run_preview_layout_columns_tests = b.addRunArtifact(preview_layout_columns_tests);
    test_step.dependOn(&run_preview_layout_columns_tests.step);

    // Phase 2 slice 4: Stage 3 — rows
    const preview_layout_rows_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/layout/rows.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_layout_rows_mod.addImport("full_format", topology_full_format_mod);
    preview_layout_rows_mod.addImport("layout_types", preview_layout_types_mod);
    const preview_layout_rows_tests = b.addTest(.{
        .root_module = preview_layout_rows_mod,
    });
    const run_preview_layout_rows_tests = b.addRunArtifact(preview_layout_rows_tests);
    test_step.dependOn(&run_preview_layout_rows_tests.step);

    // Phase 2 slice 5: Stage 4 — place
    const preview_layout_place_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/layout/place.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_layout_place_mod.addImport("full_format", topology_full_format_mod);
    preview_layout_place_mod.addImport("layout", preview_layout_mod);
    preview_layout_place_mod.addImport("layout_types", preview_layout_types_mod);
    preview_layout_place_mod.addImport("sizing", preview_layout_sizing_mod);
    const preview_layout_place_tests = b.addTest(.{
        .root_module = preview_layout_place_mod,
    });
    const run_preview_layout_place_tests = b.addRunArtifact(preview_layout_place_tests);
    test_step.dependOn(&run_preview_layout_place_tests.step);

    // Phase 2 slice 6a: Stage 5 — route
    const preview_layout_route_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/layout/route.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_layout_route_mod.addImport("full_format", topology_full_format_mod);
    preview_layout_route_mod.addImport("layout", preview_layout_mod);
    preview_layout_route_mod.addImport("layout_types", preview_layout_types_mod);
    const preview_layout_route_tests = b.addTest(.{
        .root_module = preview_layout_route_mod,
    });
    const run_preview_layout_route_tests = b.addRunArtifact(preview_layout_route_tests);
    test_step.dependOn(&run_preview_layout_route_tests.step);

    // Phase 3 slice 3: glyphs — depends on layout types.
    const preview_render_glyphs_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/render/glyphs.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_render_glyphs_mod.addImport("layout", preview_layout_mod);
    preview_render_glyphs_mod.addImport("canvas", preview_render_canvas_mod);
    preview_render_glyphs_mod.addImport("color", preview_render_color_mod);
    const preview_render_glyphs_tests = b.addTest(.{
        .root_module = preview_render_glyphs_mod,
    });
    const run_preview_render_glyphs_tests = b.addRunArtifact(preview_render_glyphs_tests);
    test_step.dependOn(&run_preview_render_glyphs_tests.step);

    // Phase 3 slice 4: render orchestrator — composes Canvas + glyphs + wire rendering.
    const preview_render_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/render.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_render_mod.addImport("layout", preview_layout_mod);
    preview_render_mod.addImport("layout_types", preview_layout_types_mod);
    preview_render_mod.addImport("canvas", preview_render_canvas_mod);
    preview_render_mod.addImport("color", preview_render_color_mod);
    preview_render_mod.addImport("glyphs", preview_render_glyphs_mod);
    const preview_render_tests = b.addTest(.{
        .root_module = preview_render_mod,
    });
    const run_preview_render_tests = b.addRunArtifact(preview_render_tests);
    test_step.dependOn(&run_preview_render_tests.step);

    // Phase 2 slice 6b: orchestrator composing all five stages
    const preview_layout_orchestrator_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/layout/orchestrator.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_layout_orchestrator_mod.addImport("full_format", topology_full_format_mod);
    preview_layout_orchestrator_mod.addImport("layout", preview_layout_mod);
    preview_layout_orchestrator_mod.addImport("collapse", preview_layout_collapse_mod);
    preview_layout_orchestrator_mod.addImport("columns", preview_layout_columns_mod);
    preview_layout_orchestrator_mod.addImport("rows", preview_layout_rows_mod);
    preview_layout_orchestrator_mod.addImport("place", preview_layout_place_mod);
    preview_layout_orchestrator_mod.addImport("route", preview_layout_route_mod);
    circ_compile_mod.addImport("layout_orchestrator", preview_layout_orchestrator_mod);
    circ_compile_mod.addImport("preview_render", preview_render_mod);

    // Phase 2 slice 6b: golden integration tests via the orchestrator + dumpLayout
    const preview_layout_integration_mod = b.createModule(.{
        .root_source_file = b.path("tests/preview/layout_integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_layout_integration_mod.addImport("scan_imports", resolver_scan_imports_mod);
    preview_layout_integration_mod.addImport("import_cycle", resolver_import_cycle_mod);
    preview_layout_integration_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    preview_layout_integration_mod.addImport("validator_run_project", validator_run_project_mod);
    preview_layout_integration_mod.addImport("diagnostics", validator_diagnostics_mod);
    preview_layout_integration_mod.addImport("full_serializer", topology_full_serializer_mod);
    preview_layout_integration_mod.addImport("layout", preview_layout_mod);
    preview_layout_integration_mod.addImport("orchestrator", preview_layout_orchestrator_mod);
    preview_layout_integration_mod.addImport("preview_dump", preview_dump_mod);
    preview_layout_integration_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const preview_layout_integration_tests = b.addTest(.{
        .root_module = preview_layout_integration_mod,
    });
    preview_layout_integration_tests.addIncludePath(b.path("."));
    preview_layout_integration_tests.addIncludePath(b.path("./lib"));
    linkParserArchive(b, preview_layout_integration_tests, build_archive_cmd);
    preview_layout_integration_tests.linkLibC();
    const run_preview_layout_integration_tests = b.addRunArtifact(preview_layout_integration_tests);
    test_step.dependOn(&run_preview_layout_integration_tests.step);

    const topology_full_emit_integration_mod = b.createModule(.{
        .root_source_file = b.path("tests/topology/full_emit_integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    topology_full_emit_integration_mod.addImport("scan_imports", resolver_scan_imports_mod);
    topology_full_emit_integration_mod.addImport("import_cycle", resolver_import_cycle_mod);
    topology_full_emit_integration_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    topology_full_emit_integration_mod.addImport("validator_run_project", validator_run_project_mod);
    topology_full_emit_integration_mod.addImport("diagnostics", validator_diagnostics_mod);
    topology_full_emit_integration_mod.addImport("serializer", topology_serializer_tests_mod);
    topology_full_emit_integration_mod.addImport("full_serializer", topology_full_serializer_mod);
    topology_full_emit_integration_mod.addImport("full_decoder", topology_full_decoder_mod);
    topology_full_emit_integration_mod.addImport("section_writer", section_writer_mod);
    topology_full_emit_integration_mod.addImport("runtime_embed", runtime_embed_mod);
    const topology_full_emit_integration_tests = b.addTest(.{
        .root_module = topology_full_emit_integration_mod,
    });
    topology_full_emit_integration_tests.addIncludePath(b.path("."));
    topology_full_emit_integration_tests.addIncludePath(b.path("./lib"));
    linkParserArchive(b, topology_full_emit_integration_tests, build_archive_cmd);
    topology_full_emit_integration_tests.linkLibC();
    const run_topology_full_emit_integration_tests = b.addRunArtifact(topology_full_emit_integration_tests);
    run_topology_full_emit_integration_tests.step.dependOn(&install_runtime.step);
    test_step.dependOn(&run_topology_full_emit_integration_tests.step);

    const section_writer_fixtures_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/e2e/section_writer_fixtures_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    section_writer_fixtures_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    section_writer_fixtures_tests_mod.addImport("import_cycle", resolver_import_cycle_mod);
    section_writer_fixtures_tests_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    section_writer_fixtures_tests_mod.addImport("validator_run_project", validator_run_project_mod);
    section_writer_fixtures_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    section_writer_fixtures_tests_mod.addImport("serializer", topology_serializer_tests_mod);
    section_writer_fixtures_tests_mod.addImport("section_writer", section_writer_mod);
    section_writer_fixtures_tests_mod.addImport("runtime_embed", runtime_embed_mod);
    const section_writer_fixtures_tests = b.addTest(.{
        .root_module = section_writer_fixtures_tests_mod,
    });
    section_writer_fixtures_tests.addIncludePath(b.path("."));
    section_writer_fixtures_tests.addIncludePath(b.path("./lib"));
    linkParserArchive(b, section_writer_fixtures_tests, build_archive_cmd);
    section_writer_fixtures_tests.linkLibC();
    const run_section_writer_fixtures_tests = b.addRunArtifact(section_writer_fixtures_tests);
    run_section_writer_fixtures_tests.step.dependOn(&install_runtime.step);
    test_step.dependOn(&run_section_writer_fixtures_tests.step);

    const serializer_fixtures_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/e2e/serializer_fixtures_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    serializer_fixtures_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    serializer_fixtures_tests_mod.addImport("import_cycle", resolver_import_cycle_mod);
    serializer_fixtures_tests_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    serializer_fixtures_tests_mod.addImport("validator_run_project", validator_run_project_mod);
    serializer_fixtures_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    serializer_fixtures_tests_mod.addImport("serializer", topology_serializer_tests_mod);
    serializer_fixtures_tests_mod.addImport("runtime_embed", runtime_embed_mod);
    const serializer_fixtures_tests = b.addTest(.{
        .root_module = serializer_fixtures_tests_mod,
    });
    serializer_fixtures_tests.addIncludePath(b.path("."));
    serializer_fixtures_tests.addIncludePath(b.path("./lib"));
    linkParserArchive(b, serializer_fixtures_tests, build_archive_cmd);
    serializer_fixtures_tests.linkLibC();
    const run_serializer_fixtures_tests = b.addRunArtifact(serializer_fixtures_tests);
    run_serializer_fixtures_tests.step.dependOn(&install_runtime.step);
    test_step.dependOn(&run_serializer_fixtures_tests.step);

    const cli_e2e_options = b.addOptions();
    cli_e2e_options.addOption([]const u8, "circ_compile_path", b.getInstallPath(.bin, "circ-compile"));
    const cli_e2e_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/e2e/cli_e2e_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_e2e_tests_mod.addOptions("build_options", cli_e2e_options);
    const cli_e2e_tests = b.addTest(.{
        .root_module = cli_e2e_tests_mod,
    });
    const run_cli_e2e_tests = b.addRunArtifact(cli_e2e_tests);
    // The test spawns the *installed* circ-compile binary via
    // b.getInstallPath(.bin, "circ-compile"). Depending on circ_compile_exe.step
    // alone only builds it; we also need the install step to run so the
    // binary actually lands at the path the test queries.
    run_cli_e2e_tests.step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_cli_e2e_tests.step);

    const topology_interpreter_tests_mod = b.createModule(.{
        .root_source_file = b.path("templates/interpreter.zig"),
        .target = target,
        .optimize = optimize,
    });
    topology_interpreter_tests_mod.addImport("format", topology_format_tests_mod);
    topology_interpreter_tests_mod.addImport("circuit.zig", circuit_mod);
    const topology_interpreter_tests = b.addTest(.{
        .root_module = topology_interpreter_tests_mod,
    });
    const run_topology_interpreter_tests = b.addRunArtifact(topology_interpreter_tests);
    test_step.dependOn(&run_topology_interpreter_tests.step);

    // ---- Engine benchmark step ----
    // The bench step compiles a *parallel* circuit module with
    // collect_metrics=true so the engine's Circuit struct gains a `metrics`
    // field and counter bumps. Everything else (parser, resolver, validators,
    // full topology serializer) is reused unchanged — they don't transitively
    // import the engine, so they don't care which circuit module is wired.
    // Only the truth-table builder, which actually instantiates a Circuit,
    // needs a bench-mode copy.
    //
    // Bench-specific optimize mode: defaults to ReleaseFast even when the
    // rest of the build is Debug. Algorithmic counters are deterministic
    // across optimize levels (the golden matches in either mode), but
    // wall-clock is ~11x faster in ReleaseFast, which makes the drv_ms
    // numbers the bench reports — and surfaces via the perf-pr-comment
    // workflow on PRs — actually informative rather than dominated by
    // Debug-mode safety checks and `@tagName` lookups for stripped log
    // args. Override with `-Dbench-optimize=Debug` to debug the bench
    // tool itself or to compare timing semantics under unoptimized code.
    const bench_optimize = b.option(
        std.builtin.OptimizeMode,
        "bench-optimize",
        "Optimize mode for the engine bench (default: ReleaseFast)",
    ) orelse .ReleaseFast;

    const circuit_options_bench = b.addOptions();
    circuit_options_bench.addOption(bool, "collect_metrics", true);

    const bench_circuit_mod = b.createModule(.{
        .root_source_file = b.path("lib/circuit.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    bench_circuit_mod.addOptions("build_options", circuit_options_bench);

    const bench_truth_table_builder_mod = b.createModule(.{
        .root_source_file = b.path("lib/truth_table/builder.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    bench_truth_table_builder_mod.addImport("circuit", bench_circuit_mod);
    bench_truth_table_builder_mod.addImport("full_format", topology_full_format_mod);

    const bench_mod = b.createModule(.{
        .root_source_file = b.path("tools/bench/main.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    bench_mod.addImport("translate", translate_mod);
    bench_mod.addImport("resolver", resolver_mod);
    bench_mod.addImport("scan_imports", resolver_scan_imports_mod);
    bench_mod.addImport("import_cycle", resolver_import_cycle_mod);
    bench_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    bench_mod.addImport("validator_run_project", validator_run_project_mod);
    bench_mod.addImport("diagnostics", validator_diagnostics_mod);
    bench_mod.addImport("ir_types", ir_types_mod);
    bench_mod.addImport("full_serializer", topology_full_serializer_mod);
    bench_mod.addImport("truth_table_builder", bench_truth_table_builder_mod);
    bench_mod.addImport("circuit", bench_circuit_mod);

    const bench_exe = b.addExecutable(.{
        .name = "engine-bench",
        .root_module = bench_mod,
    });
    bench_exe.addIncludePath(b.path("."));
    bench_exe.addIncludePath(b.path("./lib"));
    linkParserArchive(b, bench_exe, build_archive_cmd);
    bench_exe.linkLibC();

    const run_bench = b.addRunArtifact(bench_exe);
    // The Run step inherits the parent's environment by default (env_map
    // null → process.getEnvMap), so UPDATE_GOLDENS=1 zig build bench
    // already propagates without explicit forwarding.
    //
    // Forward everything after `--` on the build command line so callers can
    // pass runtime flags (e.g. `zig build bench -- --human`).
    if (b.args) |args| run_bench.addArgs(args);
    const bench_step = b.step("bench", "Run engine benchmark over truth-table fixtures");
    bench_step.dependOn(&run_bench.step);

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
