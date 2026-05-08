const std = @import("std");
const render_color = @import("render_color");

pub const Mode = enum {
    compile,
    emit_zig,
    inspect,
    preview,
    truth_table,
};

pub const ColorMode = render_color.ColorMode;

pub const Args = struct {
    input_path: []const u8,
    mode: Mode,
    output_path: ?[]const u8 = null,
    warnings_as_errors: bool = false,
    expand_macros: bool = false,
    color: ColorMode = .auto,
};

pub const ParseError = error{
    MissingInput,
    MissingOutput,
    UnknownFlag,
    ConflictingModes,
    InvalidFlagValue,
};

pub fn parse(argv: []const []const u8) ParseError!Args {
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

    var i: usize = if (argv.len > 0) 1 else 0;
    while (i < argv.len) : (i += 1) {
        const token = argv[i];

        if (std.mem.eql(u8, token, "--emit-zig")) {
            if (seen_inspect or seen_preview or seen_truth_table) return error.ConflictingModes;
            seen_emit_zig = true;
            args.mode = .emit_zig;
            continue;
        }
        if (std.mem.eql(u8, token, "--inspect")) {
            if (seen_emit_zig or seen_preview or seen_truth_table) return error.ConflictingModes;
            seen_inspect = true;
            args.mode = .inspect;
            continue;
        }
        if (std.mem.eql(u8, token, "--preview")) {
            if (seen_emit_zig or seen_inspect or seen_truth_table) return error.ConflictingModes;
            seen_preview = true;
            args.mode = .preview;
            continue;
        }
        if (std.mem.eql(u8, token, "--truth-table")) {
            if (seen_emit_zig or seen_inspect or seen_preview) return error.ConflictingModes;
            seen_truth_table = true;
            args.mode = .truth_table;
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
    if (args.mode != .inspect and args.mode != .preview and args.mode != .truth_table and args.output_path == null) return error.MissingOutput;
    if (args.mode == .preview and args.output_path != null) return error.InvalidFlagValue;
    if (args.mode == .truth_table and args.output_path != null) return error.InvalidFlagValue;
    if (args.expand_macros and args.mode != .preview) return error.InvalidFlagValue;

    return args;
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
