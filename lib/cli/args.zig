const std = @import("std");
const render_color = @import("render_color");

pub const Mode = enum {
    compile,
    emit_zig,
    inspect,
    preview,
    truth_table,
    sim,
};

pub const ColorMode = render_color.ColorMode;

pub const TruthTableFormat = enum {
    markdown,
    csv,
    json,
};

/// Per-cell value format for `--truth-table`. Scalar (width=1) cells
/// look identical across all three formats, so existing scalar fixtures
/// stay byte-identical regardless of the selected value format. Wider
/// bit-vectors render differently per format (binary digits, hex
/// nibbles, or a decimal integer).
pub const TruthTableValueFormat = enum {
    binary,
    hex,
    decimal,
};

/// Hard ceiling on the `--truth-table-cap` value. A 24-bit table is
/// roughly 16 million rows; beyond that the renderer would take long
/// enough that the cap is doing its job.
pub const truth_table_cap_max: u8 = 24;

/// Default cap on total input bits. Matches the conservative target
/// (65k-row markdown is around the edge of "still reviewable"); users
/// who need wider can opt in with `--truth-table-cap` up to 24.
pub const truth_table_cap_default: u8 = 16;

pub const Args = struct {
    input_path: []const u8,
    mode: Mode,
    output_path: ?[]const u8 = null,
    warnings_as_errors: bool = false,
    expand_macros: bool = false,
    expand_display: bool = false,
    color: ColorMode = .auto,
    truth_table_format: TruthTableFormat = .markdown,
    truth_table_value_format: TruthTableValueFormat = .binary,
    truth_table_strict: bool = false,
    truth_table_verbose: bool = false,
    truth_table_cap: u8 = truth_table_cap_default,
};

pub const ParseError = error{
    MissingInput,
    MissingOutput,
    UnknownFlag,
    ConflictingModes,
    InvalidFlagValue,
    TruthTableCapTooLarge,
    HelpRequested,
    VersionRequested,
};

pub const help_text =
    \\circ-compile — compile and inspect .circ digital-logic source files
    \\
    \\USAGE:
    \\    circ-compile <input.circ> [mode] [options]
    \\
    \\MODES (mutually exclusive; default is compile):
    \\    (none)            Compile to a self-contained .wasm artifact. Requires -o.
    \\    --emit-zig        Emit standalone generated Zig source. Requires -o.
    \\    --inspect         Print parse tree, resolved IR, and diagnostics to stdout.
    \\    --preview         Render an ASCII schematic of the circuit to stdout.
    \\    --truth-table     Enumerate every input vector and print a truth table to stdout.
    \\    --sim             Drive the circuit over a stdio line protocol (proto=1; see DOCS/sim-protocol.md).
    \\
    \\OPTIONS:
    \\    -o <path>                       Output file. Required by compile and --emit-zig modes.
    \\    -h, --help                      Show this help text and exit.
    \\    --version, -v                   Print version and HEAD revision, then exit.
    \\    --warnings-as-errors, -Werror   Treat warnings (W001–W003) as errors.
    \\
    \\  Preview-only:
    \\    --expand-macros                 Render builtin macros (xor, nand, …) as expanded primitives.
    \\    --expand-display                Render multi-bit LEDs as a row of indicator glyphs
    \\                                    (LSB on the left) instead of a single hex display.
    \\                                    Honored for widths 2..7; widths >=8 fall back to hex.
    \\    --color=auto|always|never       ANSI styling. Default 'auto' (on when stdout is a TTY;
    \\                                    the NO_COLOR environment variable also disables colour).
    \\
    \\  Truth-table-only:
    \\    --format=markdown|csv|json      Output format. Default 'markdown'. CSV uses 0/1/? cells;
    \\                                    JSON encodes undefined cells as null.
    \\    --truth-table-format=binary|hex|decimal
    \\                                    Per-cell value format for multi-bit pins (default 'binary').
    \\                                    Scalar (width-1) cells render identically across formats.
    \\    --truth-table-cap=N             Cap on total input bits (default 16, max 24). Truth tables
    \\                                    grow as 2^N rows; raise this only if you really want a wide
    \\                                    table. Cap exceeded yields a stderr error and non-zero exit.
    \\    --strict                        Exit 1 on any undefined ('?') output cell, with one
    \\                                    diagnostic line per offending row on stderr.
    \\    --verbose                       Print per-vector engine simulation traces on stderr
    \\                                    (default: silent; useful for debugging propagation).
    \\
    \\EXIT CODES:
    \\    0   Success.
    \\    1   Diagnostic errors, build failure, or --strict regression.
    \\    2   Usage error (bad flags, missing input, etc).
    \\
    \\EXAMPLES:
    \\    circ-compile inverter.circ -o inverter.wasm
    \\    circ-compile alu.circ --inspect
    \\    circ-compile half_adder.circ --preview --color=always
    \\    circ-compile xor.circ --truth-table --format=json
    \\
;

pub fn parse(argv: []const []const u8) ParseError!Args {
    for (argv[@min(argv.len, 1)..]) |token| {
        if (std.mem.eql(u8, token, "--help") or std.mem.eql(u8, token, "-h")) {
            return error.HelpRequested;
        }
        if (std.mem.eql(u8, token, "--version") or std.mem.eql(u8, token, "-v")) {
            return error.VersionRequested;
        }
    }

    var args = Args{
        .input_path = undefined,
        .mode = .compile,
        .output_path = null,
        .warnings_as_errors = false,
    };

    var have_input = false;
    var seen_emit_zig = false;
    var seen_inspect = false;
    var seen_preview = false;
    var seen_truth_table = false;
    var seen_sim = false;

    var i: usize = if (argv.len > 0) 1 else 0;
    while (i < argv.len) : (i += 1) {
        const token = argv[i];

        if (std.mem.eql(u8, token, "--emit-zig")) {
            if (seen_inspect or seen_preview or seen_truth_table or seen_sim) return error.ConflictingModes;
            seen_emit_zig = true;
            args.mode = .emit_zig;
            continue;
        }
        if (std.mem.eql(u8, token, "--inspect")) {
            if (seen_emit_zig or seen_preview or seen_truth_table or seen_sim) return error.ConflictingModes;
            seen_inspect = true;
            args.mode = .inspect;
            continue;
        }
        if (std.mem.eql(u8, token, "--preview")) {
            if (seen_emit_zig or seen_inspect or seen_truth_table or seen_sim) return error.ConflictingModes;
            seen_preview = true;
            args.mode = .preview;
            continue;
        }
        if (std.mem.eql(u8, token, "--truth-table")) {
            if (seen_emit_zig or seen_inspect or seen_preview or seen_sim) return error.ConflictingModes;
            seen_truth_table = true;
            args.mode = .truth_table;
            continue;
        }
        if (std.mem.eql(u8, token, "--sim")) {
            if (seen_emit_zig or seen_inspect or seen_preview or seen_truth_table) return error.ConflictingModes;
            seen_sim = true;
            args.mode = .sim;
            continue;
        }
        if (std.mem.eql(u8, token, "--warnings-as-errors") or std.mem.eql(u8, token, "-Werror")) {
            args.warnings_as_errors = true;
            continue;
        }
        if (std.mem.eql(u8, token, "--expand-macros")) {
            args.expand_macros = true;
            continue;
        }
        if (std.mem.eql(u8, token, "--expand-display")) {
            args.expand_display = true;
            continue;
        }
        if (std.mem.eql(u8, token, "--strict")) {
            args.truth_table_strict = true;
            continue;
        }
        if (std.mem.eql(u8, token, "--verbose")) {
            args.truth_table_verbose = true;
            continue;
        }
        if (std.mem.startsWith(u8, token, "--color=")) {
            const value = token["--color=".len..];
            if (std.mem.eql(u8, value, "auto")) {
                args.color = .auto;
            } else if (std.mem.eql(u8, value, "always")) {
                args.color = .always;
            } else if (std.mem.eql(u8, value, "never")) {
                args.color = .never;
            } else {
                return error.InvalidFlagValue;
            }
            continue;
        }
        if (std.mem.startsWith(u8, token, "--format=")) {
            const value = token["--format=".len..];
            if (std.mem.eql(u8, value, "markdown")) {
                args.truth_table_format = .markdown;
            } else if (std.mem.eql(u8, value, "csv")) {
                args.truth_table_format = .csv;
            } else if (std.mem.eql(u8, value, "json")) {
                args.truth_table_format = .json;
            } else {
                return error.InvalidFlagValue;
            }
            continue;
        }
        if (std.mem.startsWith(u8, token, "--truth-table-format=")) {
            const value = token["--truth-table-format=".len..];
            if (std.mem.eql(u8, value, "binary")) {
                args.truth_table_value_format = .binary;
            } else if (std.mem.eql(u8, value, "hex")) {
                args.truth_table_value_format = .hex;
            } else if (std.mem.eql(u8, value, "decimal")) {
                args.truth_table_value_format = .decimal;
            } else {
                return error.InvalidFlagValue;
            }
            continue;
        }
        if (std.mem.startsWith(u8, token, "--truth-table-cap=")) {
            const value = token["--truth-table-cap=".len..];
            const parsed_cap = std.fmt.parseInt(u32, value, 10) catch return error.InvalidFlagValue;
            // Reject values past the documented ceiling rather than
            // silently clamping. The CLI dispatches on this error to
            // print the spec'd diagnostic message.
            if (parsed_cap > truth_table_cap_max) return error.TruthTableCapTooLarge;
            args.truth_table_cap = @intCast(parsed_cap);
            continue;
        }
        if (std.mem.eql(u8, token, "-o")) {
            if (i + 1 >= argv.len) return error.InvalidFlagValue;
            i += 1;
            args.output_path = argv[i];
            continue;
        }
        if (std.mem.startsWith(u8, token, "-")) {
            return error.UnknownFlag;
        }

        if (have_input) return error.InvalidFlagValue;
        args.input_path = token;
        have_input = true;
    }

    if (!have_input) return error.MissingInput;
    if (args.mode != .inspect and args.mode != .preview and args.mode != .truth_table and args.mode != .sim and args.output_path == null) return error.MissingOutput;
    if (args.mode == .preview and args.output_path != null) return error.InvalidFlagValue;
    if (args.mode == .truth_table and args.output_path != null) return error.InvalidFlagValue;
    if (args.mode == .sim and args.output_path != null) return error.InvalidFlagValue;
    if (args.expand_macros and args.mode != .preview) return error.InvalidFlagValue;
    if (args.expand_display and args.mode != .preview) return error.InvalidFlagValue;
    if (args.truth_table_format != .markdown and args.mode != .truth_table) return error.InvalidFlagValue;
    if (args.truth_table_value_format != .binary and args.mode != .truth_table) return error.InvalidFlagValue;
    if (args.truth_table_strict and args.mode != .truth_table) return error.InvalidFlagValue;
    if (args.truth_table_verbose and args.mode != .truth_table) return error.InvalidFlagValue;
    if (args.truth_table_cap != truth_table_cap_default and args.mode != .truth_table) return error.InvalidFlagValue;

    return args;
}

test "Mode set matches its docs (update README / CLAUDE.md / DOCS/architecture.md on change)" {
    // Tripwire against doc drift: the CLI mode list is mirrored in the README
    // "Usage" table and the CLAUDE.md "CLI shape" table, and DOCS/architecture.md
    // points at this enum's dispatch. If you add or remove a `Mode`, update those
    // docs (and DOCS/sim-protocol.md or DOCS/analyze-api.md as relevant) so they
    // cannot silently disagree with the code.
    const expected = [_][]const u8{ "compile", "emit_zig", "inspect", "preview", "truth_table", "sim" };
    const fields = std.meta.fields(Mode);
    try std.testing.expectEqual(expected.len, fields.len);
    inline for (fields, 0..) |field, i| {
        try std.testing.expectEqualStrings(expected[i], field.name);
    }
}

test "parse compile mode with output" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "-o", "out.wasm" });
    try std.testing.expectEqualStrings("in.circ", parsed.input_path);
    try std.testing.expectEqual(Mode.compile, parsed.mode);
    try std.testing.expectEqualStrings("out.wasm", parsed.output_path.?);
    try std.testing.expect(!parsed.warnings_as_errors);
}

test "parse emit-zig mode with output" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--emit-zig", "-o", "out.zig" });
    try std.testing.expectEqual(Mode.emit_zig, parsed.mode);
    try std.testing.expectEqualStrings("out.zig", parsed.output_path.?);
}

test "parse inspect mode" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--inspect" });
    try std.testing.expectEqual(Mode.inspect, parsed.mode);
    try std.testing.expect(parsed.output_path == null);
}

test "parse warnings-as-errors long and short" {
    const parsed_long = try parse(&.{ "circ-compile", "in.circ", "-o", "out.wasm", "--warnings-as-errors" });
    try std.testing.expect(parsed_long.warnings_as_errors);

    const parsed_short = try parse(&.{ "circ-compile", "in.circ", "-o", "out.wasm", "-Werror" });
    try std.testing.expect(parsed_short.warnings_as_errors);
}

test "parse error missing input" {
    try std.testing.expectError(error.MissingInput, parse(&.{ "circ-compile" }));
}

test "parse error missing output in compile mode" {
    try std.testing.expectError(error.MissingOutput, parse(&.{ "circ-compile", "in.circ" }));
}

test "parse error conflicting modes" {
    try std.testing.expectError(error.ConflictingModes, parse(&.{ "circ-compile", "in.circ", "--emit-zig", "--inspect" }));
}

test "parse error unknown flag" {
    try std.testing.expectError(error.UnknownFlag, parse(&.{ "circ-compile", "in.circ", "--bogus" }));
}

test "parse error build-dir is unknown flag" {
    try std.testing.expectError(error.UnknownFlag, parse(&.{ "circ-compile", "in.circ", "-o", "out.wasm", "--build-dir", "/tmp/x" }));
}

test "cli_args_parse_preview_flag" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--preview" });
    try std.testing.expectEqual(Mode.preview, parsed.mode);
    try std.testing.expect(parsed.output_path == null);
    try std.testing.expectEqualStrings("in.circ", parsed.input_path);
}

test "cli_args_preview_rejects_emit_zig" {
    try std.testing.expectError(error.ConflictingModes, parse(&.{ "circ-compile", "in.circ", "--preview", "--emit-zig" }));
    try std.testing.expectError(error.ConflictingModes, parse(&.{ "circ-compile", "in.circ", "--emit-zig", "--preview" }));
}

test "cli_args_preview_rejects_inspect" {
    try std.testing.expectError(error.ConflictingModes, parse(&.{ "circ-compile", "in.circ", "--preview", "--inspect" }));
    try std.testing.expectError(error.ConflictingModes, parse(&.{ "circ-compile", "in.circ", "--inspect", "--preview" }));
}

test "cli_args_preview_rejects_output_path" {
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--preview", "-o", "out.wasm" }));
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "-o", "out.wasm", "--preview" }));
}

test "cli_args_parse_expand_macros_flag" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--preview", "--expand-macros" });
    try std.testing.expectEqual(Mode.preview, parsed.mode);
    try std.testing.expect(parsed.expand_macros);

    const parsed_default = try parse(&.{ "circ-compile", "in.circ", "--preview" });
    try std.testing.expect(!parsed_default.expand_macros);
}

test "cli_args_expand_macros_rejects_outside_preview" {
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--inspect", "--expand-macros" }));
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "-o", "out.wasm", "--expand-macros" }));
}

test "cli_args_parse_color_auto" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--preview", "--color=auto" });
    try std.testing.expectEqual(ColorMode.auto, parsed.color);
}

test "cli_args_parse_color_always" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--preview", "--color=always" });
    try std.testing.expectEqual(ColorMode.always, parsed.color);
}

test "cli_args_parse_color_never" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--preview", "--color=never" });
    try std.testing.expectEqual(ColorMode.never, parsed.color);
}

test "cli_args_color_default_is_auto" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--preview" });
    try std.testing.expectEqual(ColorMode.auto, parsed.color);
}

test "cli_args_color_rejects_invalid_value" {
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--preview", "--color=rainbow" }));
}

test "cli_args_parse_truth_table_flag" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--truth-table" });
    try std.testing.expectEqual(Mode.truth_table, parsed.mode);
    try std.testing.expect(parsed.output_path == null);
    try std.testing.expectEqualStrings("in.circ", parsed.input_path);
}

test "cli_args_truth_table_rejects_output_path" {
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--truth-table", "-o", "out.txt" }));
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "-o", "out.txt", "--truth-table" }));
}

test "cli_args_truth_table_rejects_other_modes" {
    try std.testing.expectError(error.ConflictingModes, parse(&.{ "circ-compile", "in.circ", "--truth-table", "--preview" }));
    try std.testing.expectError(error.ConflictingModes, parse(&.{ "circ-compile", "in.circ", "--truth-table", "--inspect" }));
    try std.testing.expectError(error.ConflictingModes, parse(&.{ "circ-compile", "in.circ", "--truth-table", "--emit-zig" }));
}

test "cli_args_format_default_is_markdown" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--truth-table" });
    try std.testing.expectEqual(TruthTableFormat.markdown, parsed.truth_table_format);
}

test "cli_args_parse_format_markdown_csv_json" {
    const md = try parse(&.{ "circ-compile", "in.circ", "--truth-table", "--format=markdown" });
    try std.testing.expectEqual(TruthTableFormat.markdown, md.truth_table_format);

    const csv = try parse(&.{ "circ-compile", "in.circ", "--truth-table", "--format=csv" });
    try std.testing.expectEqual(TruthTableFormat.csv, csv.truth_table_format);

    const json = try parse(&.{ "circ-compile", "in.circ", "--truth-table", "--format=json" });
    try std.testing.expectEqual(TruthTableFormat.json, json.truth_table_format);
}

test "cli_args_format_rejects_invalid_value" {
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--truth-table", "--format=yaml" }));
}

test "cli_args_format_rejects_outside_truth_table" {
    // --format=csv outside truth-table mode is meaningless.
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--preview", "--format=csv" }));
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--inspect", "--format=json" }));
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "-o", "out.wasm", "--format=csv" }));
}

test "cli_args_parse_strict_flag" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--truth-table", "--strict" });
    try std.testing.expectEqual(Mode.truth_table, parsed.mode);
    try std.testing.expect(parsed.truth_table_strict);
}

test "cli_args_strict_default_is_false" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--truth-table" });
    try std.testing.expect(!parsed.truth_table_strict);
}

test "cli_args_strict_rejects_outside_truth_table" {
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--preview", "--strict" }));
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--inspect", "--strict" }));
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "-o", "out.wasm", "--strict" }));
}

test "cli_args_parse_verbose_flag" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--truth-table", "--verbose" });
    try std.testing.expectEqual(Mode.truth_table, parsed.mode);
    try std.testing.expect(parsed.truth_table_verbose);
}

test "cli_args_verbose_default_is_false" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--truth-table" });
    try std.testing.expect(!parsed.truth_table_verbose);
}

test "cli_args_verbose_rejects_outside_truth_table" {
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--preview", "--verbose" }));
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--inspect", "--verbose" }));
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "-o", "out.wasm", "--verbose" }));
}

test "cli_args_help_long_returns_help_requested" {
    try std.testing.expectError(error.HelpRequested, parse(&.{ "circ-compile", "--help" }));
}

test "cli_args_version_long_and_short_return_VersionRequested" {
    try std.testing.expectError(error.VersionRequested, parse(&.{ "circ-compile", "--version" }));
    try std.testing.expectError(error.VersionRequested, parse(&.{ "circ-compile", "-v" }));
    // version, like help, short-circuits other validation (no input required)
    try std.testing.expectError(error.VersionRequested, parse(&.{ "circ-compile", "in.circ", "--inspect", "--version" }));
}

test "cli_args_help_short_returns_help_requested" {
    try std.testing.expectError(error.HelpRequested, parse(&.{ "circ-compile", "-h" }));
}

test "cli_args_help_short_circuits_other_validation" {
    // --help bypasses MissingInput, MissingOutput, ConflictingModes, and
    // UnknownFlag — users should be able to ask for help even when their
    // command line is otherwise broken.
    try std.testing.expectError(error.HelpRequested, parse(&.{ "circ-compile", "--help", "--bogus" }));
    try std.testing.expectError(error.HelpRequested, parse(&.{ "circ-compile", "in.circ", "--inspect", "--emit-zig", "--help" }));
    try std.testing.expectError(error.HelpRequested, parse(&.{ "circ-compile", "in.circ", "--help" }));
}

test "cli_args_help_text_mentions_every_mode_and_flag" {
    // Lock the help text against accidental drift — if a flag is added to
    // parse() without a corresponding line here, this assertion fires.
    const needles = [_][]const u8{
        "--emit-zig",   "--inspect",     "--preview",          "--truth-table",
        "-o",           "--help",        "-h",                 "--warnings-as-errors",
        "-Werror",      "--expand-macros", "--color=",        "--format=",
        "--strict",     "--verbose",      "--truth-table-format=", "--truth-table-cap=",
        "--version",    "--sim",
    };
    inline for (needles) |needle| {
        try std.testing.expect(std.mem.indexOf(u8, help_text, needle) != null);
    }
}

test "cli_args_value_format_default_is_binary" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--truth-table" });
    try std.testing.expectEqual(TruthTableValueFormat.binary, parsed.truth_table_value_format);
}

test "cli_args_parse_value_format_binary_hex_decimal" {
    const bin = try parse(&.{ "circ-compile", "in.circ", "--truth-table", "--truth-table-format=binary" });
    try std.testing.expectEqual(TruthTableValueFormat.binary, bin.truth_table_value_format);

    const hex = try parse(&.{ "circ-compile", "in.circ", "--truth-table", "--truth-table-format=hex" });
    try std.testing.expectEqual(TruthTableValueFormat.hex, hex.truth_table_value_format);

    const dec = try parse(&.{ "circ-compile", "in.circ", "--truth-table", "--truth-table-format=decimal" });
    try std.testing.expectEqual(TruthTableValueFormat.decimal, dec.truth_table_value_format);
}

test "cli_args_value_format_rejects_invalid_value" {
    try std.testing.expectError(
        error.InvalidFlagValue,
        parse(&.{ "circ-compile", "in.circ", "--truth-table", "--truth-table-format=octal" }),
    );
}

test "cli_args_value_format_rejects_outside_truth_table" {
    try std.testing.expectError(
        error.InvalidFlagValue,
        parse(&.{ "circ-compile", "in.circ", "--preview", "--truth-table-format=hex" }),
    );
}

test "cli_args_cap_default_is_16" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--truth-table" });
    try std.testing.expectEqual(@as(u8, 16), parsed.truth_table_cap);
}

test "cli_args_parse_cap_accepts_values_up_to_24" {
    const at_default = try parse(&.{ "circ-compile", "in.circ", "--truth-table", "--truth-table-cap=16" });
    try std.testing.expectEqual(@as(u8, 16), at_default.truth_table_cap);

    const at_max = try parse(&.{ "circ-compile", "in.circ", "--truth-table", "--truth-table-cap=24" });
    try std.testing.expectEqual(@as(u8, 24), at_max.truth_table_cap);

    const low = try parse(&.{ "circ-compile", "in.circ", "--truth-table", "--truth-table-cap=1" });
    try std.testing.expectEqual(@as(u8, 1), low.truth_table_cap);
}

test "cli_args_cap_above_24_returns_TruthTableCapTooLarge" {
    try std.testing.expectError(
        error.TruthTableCapTooLarge,
        parse(&.{ "circ-compile", "in.circ", "--truth-table", "--truth-table-cap=25" }),
    );
    try std.testing.expectError(
        error.TruthTableCapTooLarge,
        parse(&.{ "circ-compile", "in.circ", "--truth-table", "--truth-table-cap=100" }),
    );
}

test "cli_args_cap_non_numeric_returns_InvalidFlagValue" {
    try std.testing.expectError(
        error.InvalidFlagValue,
        parse(&.{ "circ-compile", "in.circ", "--truth-table", "--truth-table-cap=many" }),
    );
}

test "cli_args_cap_rejects_outside_truth_table" {
    try std.testing.expectError(
        error.InvalidFlagValue,
        parse(&.{ "circ-compile", "in.circ", "--preview", "--truth-table-cap=20" }),
    );
}

test "cli_args_parse_sim_flag" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "--sim" });
    try std.testing.expectEqual(Mode.sim, parsed.mode);
    try std.testing.expect(parsed.output_path == null);
    try std.testing.expectEqualStrings("in.circ", parsed.input_path);
}

test "cli_args_sim_rejects_output_path" {
    try std.testing.expectError(error.InvalidFlagValue, parse(&.{ "circ-compile", "in.circ", "--sim", "-o", "out.txt" }));
}

test "cli_args_sim_rejects_other_modes" {
    try std.testing.expectError(error.ConflictingModes, parse(&.{ "circ-compile", "in.circ", "--sim", "--truth-table" }));
    try std.testing.expectError(error.ConflictingModes, parse(&.{ "circ-compile", "in.circ", "--inspect", "--sim" }));
}
