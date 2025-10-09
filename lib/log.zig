// logging

const std = @import("std");
const builtin = @import("builtin");

const is_wasm = builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64;

fn printOnBrowser(comptime _: []const u8) void {
    // const msgPtr: *const u8 = @ptrCast(@alignCast(&format));
    // browser_log(msgPtr, format.len);
}

fn wasmLog(comptime _: @Type(.enum_literal)) type {
    return struct {
        pub fn err(
            comptime format: []const u8,
            _: anytype,
        ) void {
            @branchHint(.cold);
            printOnBrowser(format);
        }

        pub fn warn(
            comptime format: []const u8,
            _: anytype,
        ) void {
            printOnBrowser(format);
        }

        pub fn info(
            comptime format: []const u8,
            _: anytype,
        ) void {
            printOnBrowser(format);
        }

        pub fn debug(
            comptime format: []const u8,
            _: anytype,
        ) void {
            printOnBrowser(format);
        }
    };
}

pub const log = if (is_wasm)
    wasmLog(.log)
else
    std.log.scoped(.log);

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
