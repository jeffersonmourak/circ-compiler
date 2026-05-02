const std = @import("std");

pub const Mode = enum {
    compile,
    emit_zig,
    inspect,
};

pub const Args = struct {
    input_path: []const u8,
    mode: Mode,
    output_path: ?[]const u8 = null,
    warnings_as_errors: bool = false,
    build_dir: ?[]const u8 = null,
};

pub const ParseError = error{
    MissingInput,
    MissingOutput,
    UnknownFlag,
    ConflictingModes,
    BuildDirInWrongMode,
    InvalidFlagValue,
};

pub fn parse(argv: []const []const u8) ParseError!Args {
    var args = Args{
        .input_path = undefined,
        .mode = .compile,
        .output_path = null,
        .warnings_as_errors = false,
        .build_dir = null,
    };

    var have_input = false;
    var seen_emit_zig = false;
    var seen_inspect = false;

    var i: usize = if (argv.len > 0) 1 else 0;
    while (i < argv.len) : (i += 1) {
        const token = argv[i];

        if (std.mem.eql(u8, token, "--emit-zig")) {
            if (seen_inspect) return error.ConflictingModes;
            seen_emit_zig = true;
            args.mode = .emit_zig;
            continue;
        }
        if (std.mem.eql(u8, token, "--inspect")) {
            if (seen_emit_zig) return error.ConflictingModes;
            seen_inspect = true;
            args.mode = .inspect;
            continue;
        }
        if (std.mem.eql(u8, token, "--warnings-as-errors") or std.mem.eql(u8, token, "-Werror")) {
            args.warnings_as_errors = true;
            continue;
        }
        if (std.mem.eql(u8, token, "-o")) {
            if (i + 1 >= argv.len) return error.InvalidFlagValue;
            i += 1;
            args.output_path = argv[i];
            continue;
        }
        if (std.mem.eql(u8, token, "--build-dir")) {
            if (i + 1 >= argv.len) return error.InvalidFlagValue;
            i += 1;
            args.build_dir = argv[i];
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
    if (args.mode != .inspect and args.output_path == null) return error.MissingOutput;
    if (args.mode != .compile and args.build_dir != null) return error.BuildDirInWrongMode;

    return args;
}

test "parse compile mode with output" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "-o", "out.wasm" });
    try std.testing.expectEqualStrings("in.circ", parsed.input_path);
    try std.testing.expectEqual(Mode.compile, parsed.mode);
    try std.testing.expectEqualStrings("out.wasm", parsed.output_path.?);
    try std.testing.expect(!parsed.warnings_as_errors);
    try std.testing.expect(parsed.build_dir == null);
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

test "parse build-dir in compile mode" {
    const parsed = try parse(&.{ "circ-compile", "in.circ", "-o", "out.wasm", "--build-dir", "/tmp/x" });
    try std.testing.expectEqualStrings("/tmp/x", parsed.build_dir.?);
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

test "parse error build-dir in emit-zig mode" {
    try std.testing.expectError(error.BuildDirInWrongMode, parse(&.{ "circ-compile", "in.circ", "--emit-zig", "-o", "out.zig", "--build-dir", "/tmp/x" }));
}
