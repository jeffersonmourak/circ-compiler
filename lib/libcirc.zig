//! circ's compiler front end as a library: parse, resolve, validate, and
//! then compile to a self-contained `.wasm`, render a preview, enumerate a
//! truth table, or analyze for editor tooling — all over an in-memory
//! project, with no disk access when every file is supplied.
//!
//! Root of the `libcirc` module created by `build/frontend_modules.zig`.
//! The CLI is a client of this API; `lib/libcirc/c_api.zig` wraps it in a
//! C ABI for the static library and the wasm build.
const std = @import("std");

pub const parser = @import("parser");
pub const build_info = @import("build_info");
pub const format = @import("format");
pub const full_format = @import("full_format");
pub const diagnostics = @import("diagnostics");
pub const ir_types = @import("ir_types");
pub const engine_session = @import("engine_session");
pub const truth_table_builder = @import("truth_table_builder");
pub const preview_render = @import("preview_render");
pub const analyzer = @import("analyze");

pub const Version = struct {
    /// From the VERSION file.
    version: []const u8,
    /// Short git revision at build time, or "unknown".
    revision: []const u8,
    /// `circ.topology.v0.min` format version.
    topology_version: u8,
    /// `circ.topology.v0.full` format version.
    full_version: u8,
    /// The generator the vendored parser came from and its bytecode ABI.
    parser: []const u8,
    /// sha256 of the runtime pasted into `lib/parser/parser.zig` (its header
    /// line 3): the reliable parser-skew signal.
    parser_runtime_sha256: []const u8,
    /// sha256 of `lib/grammar/proto-circ.peg` at build time.
    grammar_sha256: []const u8,
};

pub fn version() Version {
    return .{
        .version = build_info.version,
        .revision = build_info.revision,
        .topology_version = format.VERSION,
        .full_version = full_format.FULL_VERSION,
        .parser = "langlang " ++ parser.runtime.langlang_version ++ " abi=" ++ std.fmt.comptimePrint("{d}", .{parser.runtime.abi_version}),
        .parser_runtime_sha256 = build_info.parser_runtime_sha256,
        .grammar_sha256 = build_info.grammar_sha256,
    };
}

/// One JSON object, keys in `Version` order, no trailing newline.
pub fn writeVersionJson(writer: anytype) !void {
    const v = version();
    try writer.writeAll("{\"version\":");
    try analyzer.writeJsonString(writer, v.version);
    try writer.writeAll(",\"revision\":");
    try analyzer.writeJsonString(writer, v.revision);
    try writer.print(",\"topology_version\":{d},\"full_version\":{d},\"parser\":", .{ v.topology_version, v.full_version });
    try analyzer.writeJsonString(writer, v.parser);
    try writer.writeAll(",\"parser_runtime_sha256\":");
    try analyzer.writeJsonString(writer, v.parser_runtime_sha256);
    try writer.writeAll(",\"grammar_sha256\":");
    try analyzer.writeJsonString(writer, v.grammar_sha256);
    try writer.writeAll("}");
}

test "version reports the topology versions and a 64-hex grammar sha" {
    const v = version();
    try std.testing.expectEqual(format.VERSION, v.topology_version);
    try std.testing.expectEqual(full_format.FULL_VERSION, v.full_version);
    try std.testing.expectEqual(@as(usize, 64), v.grammar_sha256.len);
    try std.testing.expectEqual(@as(usize, 64), v.parser_runtime_sha256.len);
    try std.testing.expect(std.mem.startsWith(u8, v.parser, "langlang "));
}
