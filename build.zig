const std = @import("std");

const GRAMMAR_FILE = "lib/grammar/proto-circ.peg";


pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // The two wasm artifacts (circ-runtime.wasm, libcirc.wasm) follow their
    // own optimize mode: a Debug CLI must still embed a small runtime, and a
    // Debug wasm build (names + DWARF, ~47x larger) is only for bisecting.
    const wasm_optimize = b.option(
        std.builtin.OptimizeMode,
        "wasm-optimize",
        "Optimize mode for circ-runtime.wasm and libcirc.wasm (default ReleaseSmall)",
    ) orelse .ReleaseSmall;
    const wasm_strip: bool = wasm_optimize != .Debug;

    const parser_gen = b.step("parser:gen", "Regenerate lib/parser/parser.zig from lib/grammar/proto-circ.peg (needs the langlang fork on PATH)");

    // Only the maintainer's fork emits Zig (upstream go/v0.0.12 rejects
    // -output-language zig), so refuse any other langlang before generating.
    // has_side_effects keeps the check out of the cache after a toolchain swap.
    const check_langlang = b.addSystemCommand(&.{ "langlang", "-version" });
    check_langlang.addCheck(.{ .expect_stdout_match = "v0.0.13-zig.2" });
    check_langlang.has_side_effects = true;

    // GRAMMAR_FILE stays relative to the build root: the generated header
    // copies the argument verbatim into its "Source File:" line.
    const generate_parser_cmd = b.addSystemCommand(&.{
        "langlang",
        "-grammar",
        GRAMMAR_FILE,
        "-disable-capture-spaces",
        "-output-language",
        "zig",
        "-output-path",
        "lib/parser/parser.zig",
    });
    generate_parser_cmd.step.dependOn(&check_langlang.step);

    parser_gen.dependOn(&generate_parser_cmd.step);

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
        .optimize = wasm_optimize,
        .strip = wasm_strip,
    });
    
    runtime_module.addImport("compiled.zig", b.createModule(.{
        .root_source_file = dummy_compiled_file,
        .target = wasm_target,
        .optimize = wasm_optimize,
        .strip = wasm_strip,
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
        .optimize = wasm_optimize,
        .strip = wasm_strip,
    });
    circuit_mod_for_wasm.addImport("build_options", circuit_options_default_mod);

    const memory_mod_for_wasm = b.createModule(.{
        .root_source_file = b.path("lib/memory.zig"),
        .target = wasm_target,
        .optimize = wasm_optimize,
        .strip = wasm_strip,
    });
    // memory.zig now imports build_options for the COLLECT_METRICS gate. The
    // WASM runtime keeps it off (zero overhead), same as every non-bench path.
    memory_mod_for_wasm.addImport("build_options", circuit_options_default_mod);
    
    const transport_mod_for_wasm = b.createModule(.{
        .root_source_file = b.path("lib/transport.zig"),
        .target = wasm_target,
        .optimize = wasm_optimize,
        .strip = wasm_strip,
    });
    
    const log_mod_for_wasm = b.createModule(.{
        .root_source_file = b.path("lib/log.zig"),
        .target = wasm_target,
        .optimize = wasm_optimize,
        .strip = wasm_strip,
    });
    
    log_mod_for_wasm.addImport("memory.zig", memory_mod_for_wasm);
    
    circuit_mod_for_wasm.addImport("memory.zig", memory_mod_for_wasm);
    circuit_mod_for_wasm.addImport("log.zig", log_mod_for_wasm);
    circuit_mod_for_wasm.addImport("transport.zig", transport_mod_for_wasm);
    
    transport_mod_for_wasm.addImport("circuit.zig", circuit_mod_for_wasm);
    
    const interpreter_mod_for_wasm = b.createModule(.{
        .root_source_file = b.path("templates/interpreter.zig"),
        .target = wasm_target,
        .optimize = wasm_optimize,
        .strip = wasm_strip,
    });
    
    const format_mod_for_wasm = b.createModule(.{
        .root_source_file = b.path("lib/topology/format.zig"),
        .target = wasm_target,
        .optimize = wasm_optimize,
        .strip = wasm_strip,
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
    // The same embed for the wasm target, so libcirc.wasm carries byte for
    // byte the runtime this build produced.
    const runtime_embed_wasm_mod = b.createModule(.{
        .root_source_file = embed_zig_file,
        .target = wasm_target,
        .optimize = wasm_optimize,
        .strip = wasm_strip,
    });

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
        // sha256 of the grammar and of the runtime pasted into the generated
        // parser (its header line 3): the skew signals a library host reads
        // through circ_version.
        const grammar_sha256 = blk: {
            const peg = b.build_root.handle.readFileAlloc(b.allocator, GRAMMAR_FILE, 1 << 20) catch break :blk "unknown";
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(peg, &digest, .{});
            break :blk b.fmt("{x}", .{digest});
        };
        const parser_runtime_sha256 = blk: {
            const file = b.build_root.handle.openFile("lib/parser/parser.zig", .{}) catch break :blk "unknown";
            defer file.close();
            const buf = b.allocator.alloc(u8, 4096) catch break :blk "unknown";
            const n = file.readAll(buf) catch break :blk "unknown";
            const head = buf[0..n];
            const key = "sha256=";
            const at = std.mem.indexOf(u8, head, key) orelse break :blk "unknown";
            const hex = head[at + key.len ..];
            if (hex.len < 64) break :blk "unknown";
            break :blk hex[0..64];
        };
        build_info.addOption([]const u8, "version", version);
        build_info.addOption([]const u8, "revision", revision);
        build_info.addOption([]const u8, "grammar_sha256", grammar_sha256);
        build_info.addOption([]const u8, "parser_runtime_sha256", parser_runtime_sha256);
    }

    // The compiler front end, one module graph shared by the CLI, the
    // libcirc library, and the per-module test artifacts below.
    const fe = @import("build/frontend_modules.zig").create(b, .{
        .target = target,
        .optimize = optimize,
        .build_options_mod = circuit_options_default_mod,
        .build_info = build_info,
        .runtime_embed = runtime_embed_mod,
    });

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
    const translate_mod = fe.translate;
    const parser_mod = fe.parser;
    // Runs the generated file's own `langlang tables` test (verifyTables).
    const parser_tests = b.addTest(.{
        .name = "parser_tests",
        .root_module = parser_mod,
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);
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
    const run_translate_tests = b.addRunArtifact(translate_tests);
    const ir_types_mod = fe.ir_types;
    const ir_types_tests = b.addTest(.{
        .root_module = ir_types_mod,
    });
    const run_ir_types_tests = b.addRunArtifact(ir_types_tests);
    const resolver_mod = fe.resolver;
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
    const run_resolver_tests = b.addRunArtifact(resolver_tests);
    const validator_codes_mod = fe.validator_codes;
    const validator_diagnostics_mod = fe.diagnostics;
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
    const name_resolution_mod = fe.name_resolution;
    const memory_validation_mod = fe.memory_validation;
    const name_collision_mod = fe.name_collision;
    const port_validation_mod = fe.port_validation;
    const multi_driver_mod = fe.multi_driver;
    const required_input_mod = fe.required_input;
    const output_assignment_mod = fe.output_assignment;
    const combinational_loop_mod = fe.combinational_loop;
    const validator_run_mod = fe.validator_run;
    const validator_run_project_mod = fe.validator_run_project;
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
    const run_validator_name_passes_tests = b.addRunArtifact(validator_name_passes_tests);
    // Zig collects tests only from a test root's own module, so a pass with
    // inline tests must be its own root.
    const memory_validation_tests = b.addTest(.{ .root_module = memory_validation_mod });
    const run_memory_validation_tests = b.addRunArtifact(memory_validation_tests);
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
    // tests/helpers/wasm_run.zig uses std.c.getpid on non-Windows hosts.
    emit_behavior_tests.linkLibC();
    const run_emit_behavior_tests = b.addRunArtifact(emit_behavior_tests);
    // Phase 3 slice 1: color resolution module (depends only on std, used by cli_args).
    const preview_render_color_mod = fe.preview_render_color;
    const preview_render_color_tests = b.addTest(.{
        .root_module = preview_render_color_mod,
    });
    const run_preview_render_color_tests = b.addRunArtifact(preview_render_color_tests);

    // Phase 3 slice 2: Canvas — in-memory cell grid with per-cell color tags.
    const preview_render_canvas_mod = fe.preview_render_canvas;
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
    const resolver_file_loader_mod = fe.file_loader;
    const resolver_builtins_mod = fe.builtins;
    const resolver_scan_imports_mod = fe.scan_imports;
    const resolver_scan_imports_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/resolver/scan_imports_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    resolver_scan_imports_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    resolver_scan_imports_tests_mod.addImport("file_loader", resolver_file_loader_mod);
    resolver_scan_imports_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    const resolver_scan_imports_tests = b.addTest(.{
        .root_module = resolver_scan_imports_tests_mod,
    });
    const run_resolver_scan_imports_tests = b.addRunArtifact(resolver_scan_imports_tests);
    const resolver_import_cycle_mod = fe.import_cycle;
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
    const run_resolver_import_cycle_tests = b.addRunArtifact(resolver_import_cycle_tests);
    const resolver_resolve_bodies_mod = fe.resolve_bodies;
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
    const run_resolver_file_loader_tests = b.addRunArtifact(resolver_file_loader_tests);


    // Native build of the simulation engine. Used by the topology interpreter
    // tests and by the truth-table mode (which drives the engine on the host
    // to enumerate input vectors).
    const circuit_mod = fe.circuit;

    const topology_protocol_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/e2e/topology_protocol_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    // A native test must not be built from the stripped wasm-target unit.
    topology_protocol_tests_mod.addImport("format", fe.format);
    topology_protocol_tests_mod.addImport("runtime_embed", runtime_embed_mod);
    const topology_protocol_tests = b.addTest(.{
        .root_module = topology_protocol_tests_mod,
    });
    const run_topology_protocol_tests = b.addRunArtifact(topology_protocol_tests);
    run_topology_protocol_tests.step.dependOn(&install_runtime.step);

    const analyze_mod = fe.analyze;


    const circ_compile_mod = b.createModule(.{
        .root_source_file = b.path("cmd/circ-compile/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    circ_compile_mod.addImport("cli_args", cli_args_mod);
    circ_compile_mod.addImport("diagnostics", validator_diagnostics_mod);
    circ_compile_mod.addImport("emit_main", emit_main_mod);
    circ_compile_mod.addImport("inspect_dump", cli_inspect_dump_mod);
    circ_compile_mod.addImport("build_info", fe.build_info);
    circ_compile_mod.addImport("libcirc", fe.libcirc);
    const circ_compile_exe = b.addExecutable(.{
        .name = "circ-compile",
        .root_module = circ_compile_mod,
    });
    circ_compile_exe.step.dependOn(&install_runtime.step);
    b.installArtifact(circ_compile_exe);
    const circ_compile_step = b.step("circ-compile", "Build circ-compile CLI");
    circ_compile_step.dependOn(b.getInstallStep());

    const circ_compile_tests = b.addTest(.{
        .root_module = circ_compile_mod,
    });
    const run_circ_compile_tests = b.addRunArtifact(circ_compile_tests);
    run_circ_compile_tests.step.dependOn(&install_runtime.step);

    const libcirc_tests = b.addTest(.{
        .name = "libcirc_tests",
        .root_module = fe.libcirc,
    });
    const run_libcirc_tests = b.addRunArtifact(libcirc_tests);
    run_libcirc_tests.step.dependOn(&install_runtime.step);


    const analyze_tests = b.addTest(.{
        .root_module = analyze_mod,
    });
    const run_analyze_tests = b.addRunArtifact(analyze_tests);

    const analyze_golden_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/analyze/analyze_golden_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    analyze_golden_tests_mod.addImport("analyze", analyze_mod);
    analyze_golden_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const analyze_golden_tests = b.addTest(.{
        .name = "analyze_golden_tests",
        .root_module = analyze_golden_tests_mod,
    });
    const run_analyze_golden_tests = b.addRunArtifact(analyze_golden_tests);
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
    const run_validator_codes_snapshot_tests = b.addRunArtifact(validator_codes_snapshot_tests);
    const test_step = b.step("test", "Run project test suite");
    test_step.dependOn(&run_golden_tests.step);
    test_step.dependOn(&run_parser_tests.step);
    test_step.dependOn(&run_translate_tests.step);
    test_step.dependOn(&run_ir_types_tests.step);
    test_step.dependOn(&run_resolver_tests.step);
    test_step.dependOn(&run_validator_tests.step);
    test_step.dependOn(&run_validator_name_passes_tests.step);
    test_step.dependOn(&run_memory_validation_tests.step);
    test_step.dependOn(&run_validator_structural_tests.step);
    test_step.dependOn(&run_validator_loop_tests.step);
    test_step.dependOn(&run_validator_run_tests.step);
    test_step.dependOn(&run_validator_codes_snapshot_tests.step);
    test_step.dependOn(&run_analyze_tests.step);
    test_step.dependOn(&run_analyze_golden_tests.step);
    test_step.dependOn(&run_emit_build_fn_tests.step);
    test_step.dependOn(&run_emit_metadata_tests.step);
    test_step.dependOn(&run_emit_full_tests.step);
    test_step.dependOn(&run_cli_args_tests.step);
    test_step.dependOn(&run_preview_render_color_tests.step);
    test_step.dependOn(&run_preview_render_canvas_tests.step);
    test_step.dependOn(&run_circ_compile_tests.step);
    test_step.dependOn(&run_libcirc_tests.step);
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
    // tests/helpers/wasm_run.zig uses std.c.getpid on non-Windows hosts.
    project_behavior_tests.linkLibC();
    const run_project_behavior_tests = b.addRunArtifact(project_behavior_tests);
    // Detached from `test`; wired into `test-emit` near the end of build().

    const topology_format_tests_mod = fe.format;
    const topology_format_tests = b.addTest(.{
        .root_module = topology_format_tests_mod,
    });
    const run_topology_format_tests = b.addRunArtifact(topology_format_tests);
    test_step.dependOn(&run_topology_format_tests.step);

    const topology_serializer_tests_mod = fe.serializer;
    const topology_serializer_tests = b.addTest(.{
        .root_module = topology_serializer_tests_mod,
    });
    const run_topology_serializer_tests = b.addRunArtifact(topology_serializer_tests);
    test_step.dependOn(&run_topology_serializer_tests.step);

    const section_writer_mod = fe.section_writer;

    // Shared with the libcirc driver tests, which import the CLI module and
    // so must see the same golden module object.
    const cli_golden_mod = b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    });
    circ_compile_mod.addImport("golden", cli_golden_mod);

    // Proves the library equals the CLI byte for byte, mode by mode, and
    // drives the compiled artifact through Node.
    const libcirc_driver_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/libcirc/driver_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    libcirc_driver_tests_mod.addImport("libcirc", fe.libcirc);
    libcirc_driver_tests_mod.addImport("circ_compile", circ_compile_mod);
    libcirc_driver_tests_mod.addImport("golden", cli_golden_mod);
    const libcirc_driver_tests = b.addTest(.{
        .name = "libcirc_driver_tests",
        .root_module = libcirc_driver_tests_mod,
    });
    const run_libcirc_driver_tests = b.addRunArtifact(libcirc_driver_tests);
    run_libcirc_driver_tests.step.dependOn(&install_runtime.step);
    test_step.dependOn(&run_libcirc_driver_tests.step);

    // The C ABI over libcirc: root of libcirc.a (slice 7) and of the wasm
    // module (Phase 3). Tested by calling the exports directly.
    const libcirc_c_api_mod = fe.c_api;
    const libcirc_c_api_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/libcirc/c_api_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    libcirc_c_api_tests_mod.addImport("libcirc_c_api", libcirc_c_api_mod);
    libcirc_c_api_tests_mod.addImport("libcirc", fe.libcirc);
    const libcirc_c_api_tests = b.addTest(.{
        .name = "libcirc_c_api_tests",
        .root_module = libcirc_c_api_tests_mod,
    });
    const run_libcirc_c_api_tests = b.addRunArtifact(libcirc_c_api_tests);
    run_libcirc_c_api_tests.step.dependOn(&install_runtime.step);
    test_step.dependOn(&run_libcirc_c_api_tests.step);

    // `zig build libcirc`: the static library plus its C header.
    // b.addLibrary prefixes "lib", so .name = "circ" yields libcirc.a.
    const libcirc_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "circ",
        .root_module = libcirc_c_api_mod,
    });
    libcirc_lib.step.dependOn(&install_runtime.step);
    libcirc_lib.installHeader(b.path("include/libcirc.h"), "libcirc.h");
    const install_libcirc = b.addInstallArtifact(libcirc_lib, .{});
    const libcirc_step = b.step("libcirc", "Build zig-out/lib/libcirc.a and zig-out/include/libcirc.h");
    libcirc_step.dependOn(&install_libcirc.step);

    // `zig build libcirc-smoke`: a C program linked against the archive.
    const libcirc_smoke_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    libcirc_smoke_mod.addCSourceFile(.{ .file = b.path("examples/c/analyze.c") });
    libcirc_smoke_mod.addIncludePath(b.path("include"));
    libcirc_smoke_mod.linkLibrary(libcirc_lib);
    const libcirc_smoke_exe = b.addExecutable(.{
        .name = "libcirc-smoke",
        .root_module = libcirc_smoke_mod,
    });
    const run_libcirc_smoke = b.addRunArtifact(libcirc_smoke_exe);
    run_libcirc_smoke.expectExitCode(0);
    const libcirc_smoke_step = b.step("libcirc-smoke", "Compile and run examples/c/analyze.c against libcirc.a");
    libcirc_smoke_step.dependOn(&run_libcirc_smoke.step);

    // `zig build libcirc-wasm`: the same front end for wasm32-freestanding.
    // A second module graph (separate compilation, separate target), sharing
    // only the materialised build_options/build_info objects.
    const fe_wasm = @import("build/frontend_modules.zig").create(b, .{
        .target = wasm_target,
        .optimize = wasm_optimize,
        .strip = wasm_strip,
        .build_options_mod = circuit_options_default_mod,
        .build_info = build_info,
        .runtime_embed = runtime_embed_wasm_mod,
    });
    const circ_exports = [_][]const u8{
        "circ_alloc",      "circ_free",       "circ_version",    "circ_analyze",    "circ_compile",
        "circ_preview",    "circ_truth_table", "circ_result_ptr", "circ_result_len", "circ_reset",
    };
    const libcirc_wasm_mod = b.createModule(.{
        .root_source_file = b.path("lib/libcirc/wasm_root.zig"),
        .target = wasm_target,
        .optimize = wasm_optimize,
        .strip = wasm_strip,
    });
    libcirc_wasm_mod.addImport("c_api", fe_wasm.c_api);
    // --export=<name> per entry; no rdynamic, so nothing else leaks out.
    libcirc_wasm_mod.export_symbol_names = &circ_exports;
    const libcirc_wasm = b.addExecutable(.{
        .name = "libcirc",
        .root_module = libcirc_wasm_mod,
    });
    libcirc_wasm.entry = .disabled;
    const install_libcirc_wasm = b.addInstallArtifact(libcirc_wasm, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    const libcirc_wasm_step = b.step("libcirc-wasm", "Build zig-out/lib/libcirc.wasm (wasm32-freestanding, -Dwasm-optimize)");
    libcirc_wasm_step.dependOn(&install_libcirc_wasm.step);

    // The Node-driven proof for libcirc.wasm (skips under SKIP_WASM_E2E=1).
    const libcirc_wasm_embed_files = b.addWriteFiles();
    _ = libcirc_wasm_embed_files.addCopyFile(libcirc_wasm.getEmittedBin(), "libcirc.wasm");
    const libcirc_wasm_embed_file = libcirc_wasm_embed_files.add("libcirc_wasm_embed.zig",
        \\pub const wasm = @embedFile("libcirc.wasm");
    );
    const libcirc_wasm_embed_mod = b.createModule(.{
        .root_source_file = libcirc_wasm_embed_file,
        .target = target,
        .optimize = optimize,
    });
    const libcirc_wasm_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/e2e/libcirc_wasm_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    libcirc_wasm_tests_mod.addImport("libcirc_wasm_embed", libcirc_wasm_embed_mod);
    libcirc_wasm_tests_mod.addImport("libcirc_c_api", fe.c_api);
    libcirc_wasm_tests_mod.addImport("libcirc", fe.libcirc);
    libcirc_wasm_tests_mod.addImport("golden", cli_golden_mod);
    const libcirc_wasm_tests = b.addTest(.{
        .name = "libcirc_wasm_tests",
        .root_module = libcirc_wasm_tests_mod,
    });
    const run_libcirc_wasm_tests = b.addRunArtifact(libcirc_wasm_tests);
    run_libcirc_wasm_tests.step.dependOn(&install_libcirc_wasm.step);
    run_libcirc_wasm_tests.step.dependOn(&install_runtime.step);
    test_step.dependOn(&run_libcirc_wasm_tests.step);

    const section_writer_tests = b.addTest(.{
        .root_module = section_writer_mod,
    });
    const run_section_writer_tests = b.addRunArtifact(section_writer_tests);
    test_step.dependOn(&run_section_writer_tests.step);

    // Phase 0 slice 3: circ.topology.v0.full schema + encoder + decoder
    const topology_full_format_mod = fe.full_format;
    const topology_full_format_tests = b.addTest(.{
        .root_module = topology_full_format_mod,
    });
    const run_topology_full_format_tests = b.addRunArtifact(topology_full_format_tests);
    test_step.dependOn(&run_topology_full_format_tests.step);

    const topology_full_serializer_mod = fe.full_serializer;
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
    const preview_layout_mod = fe.preview_layout;
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
    const preview_dump_tests = b.addTest(.{
        .root_module = preview_dump_mod,
    });
    const run_preview_dump_tests = b.addRunArtifact(preview_dump_tests);
    test_step.dependOn(&run_preview_dump_tests.step);

    // Layout-parity contract: JSON LayoutGrid dump shared with circ-renderer's
    // bun test (see DOCS/decisions/preview-layout.md).
    const preview_dump_json_mod = b.createModule(.{
        .root_source_file = b.path("lib/preview/dump_json.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_dump_json_mod.addImport("full_format", topology_full_format_mod);
    preview_dump_json_mod.addImport("layout", preview_layout_mod);
    const preview_dump_json_tests = b.addTest(.{
        .name = "preview_dump_json_tests",
        .root_module = preview_dump_json_mod,
    });
    const run_preview_dump_json_tests = b.addRunArtifact(preview_dump_json_tests);
    test_step.dependOn(&run_preview_dump_json_tests.step);

    // Layout invariants (I0–I3 and the extra measurements) — unit tests on
    // hand-built grids; the corpus table lives in tests/preview.
    const preview_layout_invariants_tests = b.addTest(.{
        .name = "preview_layout_invariants_tests",
        .root_module = fe.preview_layout_invariants,
    });
    const run_preview_layout_invariants_tests = b.addRunArtifact(preview_layout_invariants_tests);
    test_step.dependOn(&run_preview_layout_invariants_tests.step);

    // Port tables — the agreement test against place.zig's private copy.
    const preview_layout_ports_tests = b.addTest(.{
        .name = "preview_layout_ports_tests",
        .root_module = fe.preview_layout_ports,
    });
    const run_preview_layout_ports_tests = b.addRunArtifact(preview_layout_ports_tests);
    test_step.dependOn(&run_preview_layout_ports_tests.step);

    const preview_layout_ordering_tests = b.addTest(.{
        .name = "preview_layout_ordering_tests",
        .root_module = fe.preview_layout_ordering,
    });
    const run_preview_layout_ordering_tests = b.addRunArtifact(preview_layout_ordering_tests);
    test_step.dependOn(&run_preview_layout_ordering_tests.step);

    // Shared engine session: builds a live engine.Circuit from a full topology
    // and resolves root pins by name. Consumed by the truth-table builder and
    // the --sim drive loop.
    const engine_session_mod = fe.engine_session;
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
    const truth_table_builder_mod = fe.truth_table_builder;
    const truth_table_builder_tests = b.addTest(.{
        .root_module = truth_table_builder_mod,
    });
    const run_truth_table_builder_tests = b.addRunArtifact(truth_table_builder_tests);
    test_step.dependOn(&run_truth_table_builder_tests.step);

    const truth_table_markdown_mod = fe.truth_table_markdown;
    const truth_table_markdown_tests = b.addTest(.{
        .root_module = truth_table_markdown_mod,
    });
    const run_truth_table_markdown_tests = b.addRunArtifact(truth_table_markdown_tests);
    test_step.dependOn(&run_truth_table_markdown_tests.step);

    const truth_table_csv_mod = fe.truth_table_csv;
    const truth_table_csv_tests = b.addTest(.{
        .root_module = truth_table_csv_mod,
    });
    const run_truth_table_csv_tests = b.addRunArtifact(truth_table_csv_tests);
    test_step.dependOn(&run_truth_table_csv_tests.step);

    const truth_table_json_mod = fe.truth_table_json;
    const truth_table_json_tests = b.addTest(.{
        .root_module = truth_table_json_mod,
    });
    const run_truth_table_json_tests = b.addRunArtifact(truth_table_json_tests);
    test_step.dependOn(&run_truth_table_json_tests.step);

    const preview_layout_types_mod = fe.preview_layout_types;
    const preview_layout_types_tests = b.addTest(.{
        .root_module = preview_layout_types_mod,
    });
    const run_preview_layout_types_tests = b.addRunArtifact(preview_layout_types_tests);
    test_step.dependOn(&run_preview_layout_types_tests.step);

    const preview_layout_sizing_mod = fe.preview_layout_sizing;
    const preview_layout_sizing_tests = b.addTest(.{
        .root_module = preview_layout_sizing_mod,
    });
    const run_preview_layout_sizing_tests = b.addRunArtifact(preview_layout_sizing_tests);
    test_step.dependOn(&run_preview_layout_sizing_tests.step);

    // Phase 2 slice 2: Stage 1 — collapse
    const preview_layout_collapse_mod = fe.preview_layout_collapse;
    const preview_layout_collapse_tests = b.addTest(.{
        .root_module = preview_layout_collapse_mod,
    });
    const run_preview_layout_collapse_tests = b.addRunArtifact(preview_layout_collapse_tests);
    test_step.dependOn(&run_preview_layout_collapse_tests.step);

    // Phase 2 slice 3: Stage 2 — columns
    const preview_layout_layering_mod = fe.preview_layout_layering;
    const preview_layout_layering_tests = b.addTest(.{
        .name = "preview_layout_layering_tests",
        .root_module = preview_layout_layering_mod,
    });
    const run_preview_layout_layering_tests = b.addRunArtifact(preview_layout_layering_tests);
    test_step.dependOn(&run_preview_layout_layering_tests.step);

    // Phase 2 slice 4: Stage 3 — rows
    const preview_layout_rows_mod = fe.preview_layout_rows;
    const preview_layout_rows_tests = b.addTest(.{
        .root_module = preview_layout_rows_mod,
    });
    const run_preview_layout_rows_tests = b.addRunArtifact(preview_layout_rows_tests);
    test_step.dependOn(&run_preview_layout_rows_tests.step);

    // Phase 2 slice 5: Stage 4 — place
    const preview_layout_place_mod = fe.preview_layout_place;
    const preview_layout_place_tests = b.addTest(.{
        .root_module = preview_layout_place_mod,
    });
    const run_preview_layout_place_tests = b.addRunArtifact(preview_layout_place_tests);
    test_step.dependOn(&run_preview_layout_place_tests.step);

    // Phase 2 slice 6a: Stage 5 — route
    const preview_layout_route_mod = fe.preview_layout_route;
    const preview_layout_route_tests = b.addTest(.{
        .root_module = preview_layout_route_mod,
    });
    const run_preview_layout_route_tests = b.addRunArtifact(preview_layout_route_tests);
    test_step.dependOn(&run_preview_layout_route_tests.step);

    // Phase 3 slice 3: glyphs — depends on layout types.
    const preview_render_glyphs_mod = fe.preview_render_glyphs;
    const preview_render_glyphs_tests = b.addTest(.{
        .root_module = preview_render_glyphs_mod,
    });
    const run_preview_render_glyphs_tests = b.addRunArtifact(preview_render_glyphs_tests);
    test_step.dependOn(&run_preview_render_glyphs_tests.step);

    // Phase 3 slice 4: render orchestrator — composes Canvas + glyphs + wire rendering.
    const preview_render_mod = fe.preview_render;
    const preview_render_tests = b.addTest(.{
        .root_module = preview_render_mod,
    });
    const run_preview_render_tests = b.addRunArtifact(preview_render_tests);
    test_step.dependOn(&run_preview_render_tests.step);

    // Phase 2 slice 6b: orchestrator composing all five stages
    const preview_layout_orchestrator_mod = fe.preview_layout_orchestrator;

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
    const run_preview_layout_integration_tests = b.addRunArtifact(preview_layout_integration_tests);
    test_step.dependOn(&run_preview_layout_integration_tests.step);

    // The previewable fixture corpus, built through the library front end
    // (the CLI's and the site's exact path), and the layout-parity goldens
    // over it: one JSON LayoutGrid per fixture-mode that
    // circ-renderer/test/layout-parity.test.ts compares buildLayout() against.
    const preview_corpus_mod = b.createModule(.{
        .root_source_file = b.path("tests/preview/corpus.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_corpus_mod.addImport("libcirc", fe.libcirc);
    preview_corpus_mod.addImport("layout", preview_layout_mod);
    preview_corpus_mod.addImport("orchestrator", fe.preview_layout_orchestrator);
    const preview_layout_conformance_mod = b.createModule(.{
        .root_source_file = b.path("tests/preview/layout_conformance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    preview_layout_conformance_mod.addImport("corpus", preview_corpus_mod);
    preview_layout_conformance_mod.addImport("layout", preview_layout_mod);
    preview_layout_conformance_mod.addImport("preview_dump_json", preview_dump_json_mod);
    preview_layout_conformance_mod.addImport("invariants", fe.preview_layout_invariants);
    preview_layout_conformance_mod.addImport("ordering", fe.preview_layout_ordering);
    preview_layout_conformance_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const preview_layout_conformance_tests = b.addTest(.{
        .name = "preview_layout_conformance_tests",
        .root_module = preview_layout_conformance_mod,
    });
    const run_preview_layout_conformance_tests = b.addRunArtifact(preview_layout_conformance_tests);
    run_preview_layout_conformance_tests.step.dependOn(&install_runtime.step);
    // Reads every fixture and (under UPDATE_GOLDENS) rewrites goldens: never
    // serve it from the run-step cache, or a regeneration silently no-ops.
    run_preview_layout_conformance_tests.has_side_effects = true;
    test_step.dependOn(&run_preview_layout_conformance_tests.step);

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
    const run_serializer_fixtures_tests = b.addRunArtifact(serializer_fixtures_tests);
    run_serializer_fixtures_tests.step.dependOn(&install_runtime.step);
    test_step.dependOn(&run_serializer_fixtures_tests.step);

    const sim_golden_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/sim/golden_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    sim_golden_tests_mod.addImport("scan_imports", resolver_scan_imports_mod);
    sim_golden_tests_mod.addImport("import_cycle", resolver_import_cycle_mod);
    sim_golden_tests_mod.addImport("resolve_bodies", resolver_resolve_bodies_mod);
    sim_golden_tests_mod.addImport("validator_run_project", validator_run_project_mod);
    sim_golden_tests_mod.addImport("diagnostics", validator_diagnostics_mod);
    sim_golden_tests_mod.addImport("full_serializer", topology_full_serializer_mod);
    sim_golden_tests_mod.addImport("sim_loop", sim_loop_mod);
    sim_golden_tests_mod.addImport("golden", b.createModule(.{
        .root_source_file = b.path("tests/helpers/golden.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const sim_golden_tests = b.addTest(.{
        .root_module = sim_golden_tests_mod,
    });
    const run_sim_golden_tests = b.addRunArtifact(sim_golden_tests);
    test_step.dependOn(&run_sim_golden_tests.step);

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

    // lib/circuit.zig is otherwise only ever a dependency module, and Zig
    // collects tests only from a root module, so the engine's inline tests
    // (and, via its relative imports, transport.zig's) need their own root.
    const engine_tests = b.addTest(.{ .root_module = circuit_mod });
    const run_engine_tests = b.addRunArtifact(engine_tests);
    test_step.dependOn(&run_engine_tests.step);

    // The emit-zig backend behavioral smoke tests each spawn a nested
    // `zig build wasm` per fixture, which is dramatically slower than the rest
    // of the suite. They guard the experimental --emit-zig pipeline only;
    // circuit *behavior* on the production path (prebuilt runtime + topology
    // sections) is already covered by serializer_fixtures_test, which stays in
    // the default `test` step. So keep them out of the dev-loop `test` step and
    // behind an opt-in `test-emit` step. CI runs everything via `test-all`.
    const test_emit_step = b.step("test-emit", "Emit-zig backend behavioral smoke (nested wasm builds; slow)");
    test_emit_step.dependOn(&run_emit_behavior_tests.step);
    test_emit_step.dependOn(&run_project_behavior_tests.step);

    const test_all_step = b.step("test-all", "Full suite: `test` plus the emit-zig smoke (`test-emit`)");
    test_all_step.dependOn(test_step);
    test_all_step.dependOn(test_emit_step);

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

    // Bench-mode engine_session: must bind to bench_circuit_mod (collect_metrics
    // = true) so its `Circuit` type matches the one bench_truth_table_builder_mod
    // passes into Session.build. Reusing the non-bench engine_session_mod here
    // would be a type mismatch (two distinct circuit modules).
    const bench_engine_session_mod = b.createModule(.{
        .root_source_file = b.path("lib/engine_session.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    bench_engine_session_mod.addImport("circuit", bench_circuit_mod);
    bench_engine_session_mod.addImport("full_format", topology_full_format_mod);

    const bench_truth_table_builder_mod = b.createModule(.{
        .root_source_file = b.path("lib/truth_table/builder.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    bench_truth_table_builder_mod.addImport("circuit", bench_circuit_mod);
    bench_truth_table_builder_mod.addImport("full_format", topology_full_format_mod);
    bench_truth_table_builder_mod.addImport("engine_session", bench_engine_session_mod);

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
