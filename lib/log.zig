// logging

const std = @import("std");
const builtin = @import("builtin");
const memory = @import("memory.zig");

const bufPrint = std.fmt.bufPrint;

extern fn onDebugLog(msg: *const u8, msgLen: usize, logType: u8) void;
extern fn debugEnabled() bool;

const is_wasm = builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64;

var wasmLogArena = std.heap.ArenaAllocator.init(memory.allocator);

pub fn clearLogArena() void {
    _ = wasmLogArena.reset(.free_all);
}

pub fn deinitLogArena() void {
    wasmLogArena.deinit();
}

pub fn clearLogPointer(ptr: *const u8, len: usize) void {
    var logPtr: []const u8 = @ptrCast(@alignCast(ptr));
    const logPtrSlice = logPtr[0..len];

    wasmLogArena.allocator().free(logPtrSlice);
}

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

        // const result = bufPrint(&buffer.*, formatString, args) catch {
        //     return formatString;
        // };

        // const finalMsg = allocPrint(memory.allocator, "{s} {s}", .{ @tagName(self), formattedMsg }) catch {
        //     return formatString;
        // };

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
    const msg = printType.format(format, args);
    const msgPtr = &msg[0];

    if (debugEnabled()) {
        onDebugLog(msgPtr, msg.len, printType.toInt());
    }

    // const msgPtr: *const u8 = @ptrCast(@alignCast(&format));
    // browser_log(msgPtr, format.len);

    // printOnBrowser(format);
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

pub const log = if (true or is_wasm)
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
