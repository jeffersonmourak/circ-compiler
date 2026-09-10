//! The compiler front end as one module graph, created once per target.
//!
//! Every consumer of the front end (the CLI, the `libcirc` library, and the
//! per-module test artifacts) must reach a given source file through the
//! same `*std.Build.Module` object: two modules over the same file are a
//! type-identity error the moment a value crosses between them (`args.color`
//! into `RenderOptions.color`, a `Session` into the truth-table builder), and
//! Zig rejects the duplicate outright with "file exists in modules 'x' and
//! 'x0'". `create` is the one place the `addImport` edges are drawn.
const std = @import("std");

const Module = std.Build.Module;

pub const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// `-fstrip` for every module in the graph (the wasm build strips).
    strip: ?bool = null,
    /// The engine's `build_options` module, materialised once from its
    /// `addOptions` step by the caller (the wasm runtime twin shares it).
    build_options_mod: *Module,
    /// The version/revision/sha options step; materialised here exactly once.
    build_info: *std.Build.Step.Options,
    /// The WriteFiles-backed module that `@embedFile`s `circ-runtime.wasm`.
    runtime_embed: *Module,
};

pub const Modules = struct {
    parser: *Module,
    translate: *Module,
    ir_types: *Module,
    resolver: *Module,
    validator_codes: *Module,
    diagnostics: *Module,
    name_resolution: *Module,
    name_collision: *Module,
    port_validation: *Module,
    multi_driver: *Module,
    required_input: *Module,
    output_assignment: *Module,
    combinational_loop: *Module,
    dead_code: *Module,
    unused_import: *Module,
    memory_validation: *Module,
    validator_run: *Module,
    sub_circuit_validation: *Module,
    validator_run_project: *Module,
    builtins: *Module,
    file_loader: *Module,
    scan_imports: *Module,
    import_cycle: *Module,
    resolve_bodies: *Module,
    analyze: *Module,
    format: *Module,
    serializer: *Module,
    section_writer: *Module,
    full_format: *Module,
    full_serializer: *Module,
    circuit: *Module,
    engine_session: *Module,
    truth_table_builder: *Module,
    truth_table_markdown: *Module,
    truth_table_csv: *Module,
    truth_table_json: *Module,
    preview_layout: *Module,
    preview_layout_types: *Module,
    preview_layout_sizing: *Module,
    preview_layout_collapse: *Module,
    preview_layout_layering: *Module,
    preview_layout_rows: *Module,
    preview_layout_ordering: *Module,
    preview_layout_place: *Module,
    preview_layout_route: *Module,
    preview_layout_orchestrator: *Module,
    preview_layout_invariants: *Module,
    preview_layout_ports: *Module,
    preview_render_color: *Module,
    preview_render_canvas: *Module,
    preview_render_glyphs: *Module,
    preview_render: *Module,
    build_info: *Module,
    libcirc: *Module,
    /// Root of libcirc.a and of libcirc.wasm: the ten `circ_*` exports.
    c_api: *Module,
};

/// One module per target for the vendored, langlang-generated parser.
/// Exposed so a wasm consumer can mint its twin with the same literal.
pub fn createParserModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *Module {
    return b.createModule(.{
        .root_source_file = b.path("lib/parser/parser.zig"),
        .target = target,
        .optimize = optimize,
    });
}

pub fn create(b: *std.Build, opts: Options) Modules {
    const target = opts.target;
    const optimize = opts.optimize;
    const mk = struct {
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        strip: ?bool,
        fn module(self: @This(), path: []const u8) *Module {
            return self.b.createModule(.{
                .root_source_file = self.b.path(path),
                .target = self.target,
                .optimize = self.optimize,
                .strip = self.strip,
            });
        }
    }{ .b = b, .target = target, .optimize = optimize, .strip = opts.strip };

    // ---- syntax + IR ----
    const parser = createParserModule(b, target, optimize);
    parser.strip = opts.strip;
    const translate = mk.module("lib/syntax/translate.zig");
    translate.addImport("parser", parser);
    const ir_types = mk.module("lib/ir/types.zig");
    const resolver = mk.module("lib/ir/resolver.zig");
    resolver.addImport("translate", translate);
    resolver.addImport("ir_types", ir_types);

    // ---- validator ----
    const validator_codes = mk.module("lib/validator/codes.zig");
    const diagnostics = mk.module("lib/validator/diagnostics.zig");
    diagnostics.addImport("codes", validator_codes);
    const pass_files = [_][]const u8{
        "lib/validator/passes/name_resolution.zig",
        "lib/validator/passes/name_collision.zig",
        "lib/validator/passes/port_validation.zig",
        "lib/validator/passes/multi_driver.zig",
        "lib/validator/passes/required_input.zig",
        "lib/validator/passes/output_assignment.zig",
        "lib/validator/passes/combinational_loop.zig",
        "lib/validator/passes/dead_code.zig",
        "lib/validator/passes/unused_import.zig",
        "lib/validator/passes/sub_circuit_validation.zig",
        "lib/validator/passes/memory_validation.zig",
    };
    var passes: [pass_files.len]*Module = undefined;
    for (pass_files, 0..) |file, i| {
        passes[i] = mk.module(file);
        passes[i].addImport("diagnostics", diagnostics);
        passes[i].addImport("ir_types", ir_types);
    }
    const name_resolution = passes[0];
    const name_collision = passes[1];
    const port_validation = passes[2];
    const multi_driver = passes[3];
    const required_input = passes[4];
    const output_assignment = passes[5];
    const combinational_loop = passes[6];
    const dead_code = passes[7];
    const unused_import = passes[8];
    const sub_circuit_validation = passes[9];
    const memory_validation = passes[10];
    port_validation.addImport("memory_validation", memory_validation);
    sub_circuit_validation.addImport("memory_validation", memory_validation);
    const validator_run = mk.module("lib/validator/run.zig");
    validator_run.addImport("diagnostics", diagnostics);
    validator_run.addImport("ir_types", ir_types);
    validator_run.addImport("name_resolution", name_resolution);
    validator_run.addImport("name_collision", name_collision);
    validator_run.addImport("port_validation", port_validation);
    validator_run.addImport("multi_driver", multi_driver);
    validator_run.addImport("required_input", required_input);
    validator_run.addImport("output_assignment", output_assignment);
    validator_run.addImport("combinational_loop", combinational_loop);
    validator_run.addImport("dead_code", dead_code);
    validator_run.addImport("unused_import", unused_import);
    validator_run.addImport("memory_validation", memory_validation);
    const validator_run_project = mk.module("lib/validator/run_project.zig");
    validator_run_project.addImport("diagnostics", diagnostics);
    validator_run_project.addImport("ir_types", ir_types);
    validator_run_project.addImport("validator_run", validator_run);
    validator_run_project.addImport("sub_circuit_validation", sub_circuit_validation);

    // ---- resolver (project) ----
    const builtins = mk.module("lib/resolver/builtins.zig");
    const file_loader = mk.module("lib/resolver/file_loader.zig");
    file_loader.addImport("builtins", builtins);
    const scan_imports = mk.module("lib/resolver/scan_imports.zig");
    scan_imports.addImport("translate", translate);
    scan_imports.addImport("diagnostics", diagnostics);
    scan_imports.addImport("file_loader", file_loader);
    scan_imports.addImport("builtins", builtins);
    const import_cycle = mk.module("lib/resolver/import_cycle.zig");
    import_cycle.addImport("diagnostics", diagnostics);
    import_cycle.addImport("scan_imports", scan_imports);
    import_cycle.addImport("file_loader", file_loader);
    const resolve_bodies = mk.module("lib/resolver/resolve_bodies.zig");
    resolve_bodies.addImport("translate", translate);
    resolve_bodies.addImport("resolver", resolver);
    resolve_bodies.addImport("ir_types", ir_types);
    resolve_bodies.addImport("scan_imports", scan_imports);
    resolve_bodies.addImport("file_loader", file_loader);
    resolve_bodies.addImport("diagnostics", diagnostics);

    // ---- analyze ----
    const analyze = mk.module("lib/analyze/analyze.zig");
    analyze.addImport("scan_imports", scan_imports);
    analyze.addImport("import_cycle", import_cycle);
    analyze.addImport("resolve_bodies", resolve_bodies);
    analyze.addImport("validator_run_project", validator_run_project);
    analyze.addImport("diagnostics", diagnostics);
    analyze.addImport("ir_types", ir_types);
    analyze.addImport("translate", translate);
    analyze.addImport("file_loader", file_loader);

    // ---- topology ----
    const format = mk.module("lib/topology/format.zig");
    const serializer = mk.module("lib/topology/serializer.zig");
    serializer.addImport("format", format);
    serializer.addImport("ir_types", ir_types);
    const section_writer = mk.module("lib/topology/section_writer.zig");
    const full_format = mk.module("lib/topology/full_format.zig");
    full_format.addImport("format", format);
    const full_serializer = mk.module("lib/topology/full_serializer.zig");
    full_serializer.addImport("full_format", full_format);
    full_serializer.addImport("ir_types", ir_types);

    // ---- engine (native) + sessions + truth table ----
    const circuit = mk.module("lib/circuit.zig");
    circuit.addImport("build_options", opts.build_options_mod);
    const engine_session = mk.module("lib/engine_session.zig");
    engine_session.addImport("circuit", circuit);
    engine_session.addImport("full_format", full_format);
    const truth_table_builder = mk.module("lib/truth_table/builder.zig");
    truth_table_builder.addImport("circuit", circuit);
    truth_table_builder.addImport("full_format", full_format);
    truth_table_builder.addImport("engine_session", engine_session);
    const truth_table_markdown = mk.module("lib/truth_table/markdown.zig");
    truth_table_markdown.addImport("builder", truth_table_builder);
    truth_table_markdown.addImport("circuit", circuit);
    const truth_table_csv = mk.module("lib/truth_table/csv.zig");
    truth_table_csv.addImport("builder", truth_table_builder);
    truth_table_csv.addImport("circuit", circuit);
    const truth_table_json = mk.module("lib/truth_table/json.zig");
    truth_table_json.addImport("builder", truth_table_builder);
    truth_table_json.addImport("circuit", circuit);

    // ---- preview: layout ----
    const preview_layout = mk.module("lib/preview/layout.zig");
    preview_layout.addImport("full_format", full_format);
    const preview_layout_types = mk.module("lib/preview/layout/types.zig");
    preview_layout_types.addImport("full_format", full_format);
    preview_layout_types.addImport("layout", preview_layout);
    const preview_layout_sizing = mk.module("lib/preview/layout/sizing.zig");
    preview_layout_sizing.addImport("full_format", full_format);
    const preview_layout_collapse = mk.module("lib/preview/layout/collapse.zig");
    preview_layout_collapse.addImport("full_format", full_format);
    preview_layout_collapse.addImport("layout", preview_layout);
    preview_layout_collapse.addImport("layout_types", preview_layout_types);
    const preview_layout_layering = mk.module("lib/preview/layout/layering.zig");
    preview_layout_layering.addImport("full_format", full_format);
    preview_layout_layering.addImport("layout_types", preview_layout_types);
    const preview_layout_rows = mk.module("lib/preview/layout/rows.zig");
    preview_layout_rows.addImport("full_format", full_format);
    preview_layout_rows.addImport("layout_types", preview_layout_types);
    const preview_layout_place = mk.module("lib/preview/layout/place.zig");
    preview_layout_place.addImport("full_format", full_format);
    preview_layout_place.addImport("layout", preview_layout);
    preview_layout_place.addImport("layout_types", preview_layout_types);
    preview_layout_place.addImport("sizing", preview_layout_sizing);
    const preview_layout_route = mk.module("lib/preview/layout/route.zig");
    preview_layout_route.addImport("full_format", full_format);
    preview_layout_route.addImport("layout", preview_layout);
    preview_layout_route.addImport("layout_types", preview_layout_types);
    const preview_layout_orchestrator = mk.module("lib/preview/layout/orchestrator.zig");
    preview_layout_orchestrator.addImport("full_format", full_format);
    preview_layout_orchestrator.addImport("layout", preview_layout);
    preview_layout_orchestrator.addImport("layout_types", preview_layout_types);
    preview_layout_orchestrator.addImport("collapse", preview_layout_collapse);
    preview_layout_orchestrator.addImport("layering", preview_layout_layering);
    preview_layout_orchestrator.addImport("rows", preview_layout_rows);
    preview_layout_orchestrator.addImport("place", preview_layout_place);
    preview_layout_orchestrator.addImport("route", preview_layout_route);
    // Render-free invariant counters over a LayoutGrid (the layout rewrite's
    // measurement of record; see DOCS/decisions/preview-layout.md).
    const preview_layout_invariants = mk.module("lib/preview/layout/invariants.zig");
    preview_layout_invariants.addImport("layout", preview_layout);
    // Port tables (input slots in border order, output row) shared by the
    // ordering and coordinate stages; `place` is imported for the agreement
    // test only, until Phase 2 deletes place.zig.
    const preview_layout_ports = mk.module("lib/preview/layout/ports.zig");
    preview_layout_ports.addImport("full_format", full_format);
    preview_layout_ports.addImport("layout", preview_layout);
    preview_layout_ports.addImport("layout_types", preview_layout_types);
    preview_layout_ports.addImport("place", preview_layout_place);
    const preview_layout_ordering = mk.module("lib/preview/layout/ordering.zig");
    preview_layout_ordering.addImport("full_format", full_format);
    preview_layout_ordering.addImport("layout_types", preview_layout_types);
    preview_layout_ordering.addImport("ports", preview_layout_ports);
    preview_layout_ordering.addImport("layering", preview_layout_layering);
    preview_layout_orchestrator.addImport("ordering", preview_layout_ordering);

    // ---- preview: render ----
    const preview_render_color = mk.module("lib/preview/render/color.zig");
    const preview_render_canvas = mk.module("lib/preview/render/canvas.zig");
    preview_render_canvas.addImport("color", preview_render_color);
    const preview_render_glyphs = mk.module("lib/preview/render/glyphs.zig");
    preview_render_glyphs.addImport("layout", preview_layout);
    preview_render_glyphs.addImport("canvas", preview_render_canvas);
    preview_render_glyphs.addImport("color", preview_render_color);
    const preview_render = mk.module("lib/preview/render.zig");
    preview_render.addImport("layout", preview_layout);
    preview_render.addImport("layout_types", preview_layout_types);
    preview_render.addImport("canvas", preview_render_canvas);
    preview_render.addImport("color", preview_render_color);
    preview_render.addImport("glyphs", preview_render_glyphs);

    // ---- build info + the library root ----
    const build_info = opts.build_info.createModule();
    const libcirc = mk.module("lib/libcirc.zig");
    libcirc.addImport("parser", parser);
    libcirc.addImport("translate", translate);
    libcirc.addImport("ir_types", ir_types);
    libcirc.addImport("resolver", resolver);
    libcirc.addImport("diagnostics", diagnostics);
    libcirc.addImport("validator_run", validator_run);
    libcirc.addImport("validator_run_project", validator_run_project);
    libcirc.addImport("file_loader", file_loader);
    libcirc.addImport("scan_imports", scan_imports);
    libcirc.addImport("import_cycle", import_cycle);
    libcirc.addImport("resolve_bodies", resolve_bodies);
    libcirc.addImport("analyze", analyze);
    libcirc.addImport("format", format);
    libcirc.addImport("serializer", serializer);
    libcirc.addImport("section_writer", section_writer);
    libcirc.addImport("full_format", full_format);
    libcirc.addImport("full_serializer", full_serializer);
    libcirc.addImport("circuit", circuit);
    libcirc.addImport("engine_session", engine_session);
    libcirc.addImport("truth_table_builder", truth_table_builder);
    libcirc.addImport("truth_table_markdown", truth_table_markdown);
    libcirc.addImport("truth_table_csv", truth_table_csv);
    libcirc.addImport("truth_table_json", truth_table_json);
    libcirc.addImport("layout", preview_layout);
    libcirc.addImport("layout_orchestrator", preview_layout_orchestrator);
    libcirc.addImport("preview_render", preview_render);
    libcirc.addImport("preview_render_color", preview_render_color);
    libcirc.addImport("runtime_embed", opts.runtime_embed);
    libcirc.addImport("build_info", build_info);
    libcirc.addImport("builtins", builtins);
    const c_api = mk.module("lib/libcirc/c_api.zig");
    c_api.addImport("libcirc", libcirc);

    return .{
        .parser = parser,
        .translate = translate,
        .ir_types = ir_types,
        .resolver = resolver,
        .validator_codes = validator_codes,
        .diagnostics = diagnostics,
        .name_resolution = name_resolution,
        .name_collision = name_collision,
        .port_validation = port_validation,
        .multi_driver = multi_driver,
        .required_input = required_input,
        .output_assignment = output_assignment,
        .combinational_loop = combinational_loop,
        .dead_code = dead_code,
        .unused_import = unused_import,
        .memory_validation = memory_validation,
        .validator_run = validator_run,
        .sub_circuit_validation = sub_circuit_validation,
        .validator_run_project = validator_run_project,
        .builtins = builtins,
        .file_loader = file_loader,
        .scan_imports = scan_imports,
        .import_cycle = import_cycle,
        .resolve_bodies = resolve_bodies,
        .analyze = analyze,
        .format = format,
        .serializer = serializer,
        .section_writer = section_writer,
        .full_format = full_format,
        .full_serializer = full_serializer,
        .circuit = circuit,
        .engine_session = engine_session,
        .truth_table_builder = truth_table_builder,
        .truth_table_markdown = truth_table_markdown,
        .truth_table_csv = truth_table_csv,
        .truth_table_json = truth_table_json,
        .preview_layout = preview_layout,
        .preview_layout_types = preview_layout_types,
        .preview_layout_sizing = preview_layout_sizing,
        .preview_layout_collapse = preview_layout_collapse,
        .preview_layout_layering = preview_layout_layering,
        .preview_layout_rows = preview_layout_rows,
        .preview_layout_place = preview_layout_place,
        .preview_layout_route = preview_layout_route,
        .preview_layout_orchestrator = preview_layout_orchestrator,
        .preview_layout_invariants = preview_layout_invariants,
        .preview_layout_ports = preview_layout_ports,
        .preview_layout_ordering = preview_layout_ordering,
        .preview_render_color = preview_render_color,
        .preview_render_canvas = preview_render_canvas,
        .preview_render_glyphs = preview_render_glyphs,
        .preview_render = preview_render,
        .build_info = build_info,
        .libcirc = libcirc,
        .c_api = c_api,
    };
}
