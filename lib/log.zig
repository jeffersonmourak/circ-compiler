// logging

const std = @import("std");
const builtin = @import("builtin");
const memory = @import("memory.zig");

extern fn onDebugLog(msg: *const u8, msgLen: usize, logType: u8) void;
extern fn debugEnabled() bool;

const is_wasm = builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64;

// Backed by the page allocator, not `memory.allocator`: `memory.reset()` must
// be free to drop the engine arena without dangling this one.
var wasmLogArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

const PrintType = enum {
    Debug,
    Info,
    Warn,
    Err,

    fn format(self: PrintType, comptime formatString: []const u8, args: anytype) []const u8 {
        var buffer: std.ArrayList(u8) = .{};
        defer buffer.deinit(memory.allocator);

        buffer.print(memory.allocator, "{s}(wasm) " ++ formatString, .{@tagName(self)} ++ args) catch {
            return formatString;
        };

        const result = buffer.toOwnedSlice(wasmLogArena.allocator()) catch {
            return formatString;
        };

        return result;
    }

    fn toInt(self: PrintType) u8 {
        return switch (self) {
            .Debug => 0,
            .Info => 1,
            .Warn => 2,
            .Err => 3,
        };
    }
};

fn printOnBrowser(comptime printType: PrintType, comptime format: []const u8, args: anytype) void {
    // Ask first: formatting allocates from the engine arena, and a host with
    // logging off must not pay for lines it will never see.
    if (!debugEnabled()) return;
    const msg = printType.format(format, args);
    onDebugLog(&msg[0], msg.len, printType.toInt());
}

fn wasmLog(comptime _: @Type(.enum_literal)) type {
    return struct {
        pub fn err(
            comptime format: []const u8,
            args: anytype,
        ) void {
            @branchHint(.cold);
            printOnBrowser(.Err, format, args);
        }

        pub fn warn(
            comptime format: []const u8,
            args: anytype,
        ) void {
            printOnBrowser(.Warn, format, args);
        }

        pub fn info(
            comptime format: []const u8,
            args: anytype,
        ) void {
            printOnBrowser(.Info, format, args);
        }

        pub fn debug(
            comptime format: []const u8,
            args: anytype,
        ) void {
            printOnBrowser(.Debug, format, args);
        }
    };
}

pub const log = if (is_wasm)
    wasmLog(.log)
else
    std.log.scoped(.log);

/// Comptime-evaluable predicate: would a `log.<level>` call actually emit
/// at the current consumer's `std_options.log_level`? Callers on the hot
/// path can wrap their log invocations in `if (comptime log.enabled(.info))`
/// so the entire expression (including arg-tuple construction, which is
/// where `@tagName(...)` runtime lookups land) gets stripped at comptime
/// when the level is below threshold.
///
/// Without the guard, `@tagName(component.kind)` and friends still execute
/// inside the call site's args tuple even when the configured threshold
/// would silently drop the message. The bench profile showed ~2.5% of
/// Debug wall-clock landing in `__zig_tag_name_*` / `__zig_is_named_enum_value_*`
/// from these dead args.
///
/// For wasm builds we conservatively report enabled-always because the wasm
/// logger has its own runtime gate (`debugEnabled()`); callers there will
/// keep evaluating args, matching pre-existing behavior.
pub fn enabled(comptime level: std.log.Level) bool {
    if (is_wasm) return true;
    return std.log.logEnabled(level, .log);
}

pub fn info(comptime format: []const u8, args: anytype) void {
    log.info(format, args);
}

pub fn err(comptime format: []const u8, args: anytype) void {
    log.err(format, args);
}

pub fn warn(comptime format: []const u8, args: anytype) void {
    log.warn(format, args);
}

pub fn debug(comptime format: []const u8, args: anytype) void {
    log.debug(format, args);
}
