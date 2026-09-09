//! Root of `libcirc.wasm` (wasm32-freestanding). The exports live in
//! `c_api.zig`; this file only pins the logging policy for the whole graph
//! and forces analysis of each export so a missing one fails the link
//! (`--export=<name>`) instead of vanishing silently.
const std = @import("std");
const c_api = @import("c_api");

pub const std_options: std.Options = .{
    // ReleaseSmall's default is .info; .err keeps the argument tuples dead.
    .log_level = .err,
    // std.log.defaultLog reaches File.stderr(), which does not exist here.
    .logFn = silentLog,
};

fn silentLog(
    comptime _: std.log.Level,
    comptime _: @Type(.enum_literal),
    comptime _: []const u8,
    _: anytype,
) void {}

comptime {
    _ = &c_api.circ_alloc;
    _ = &c_api.circ_free;
    _ = &c_api.circ_version;
    _ = &c_api.circ_analyze;
    _ = &c_api.circ_compile;
    _ = &c_api.circ_preview;
    _ = &c_api.circ_truth_table;
    _ = &c_api.circ_result_ptr;
    _ = &c_api.circ_result_len;
    _ = &c_api.circ_reset;
}
