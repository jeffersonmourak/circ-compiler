//! The C ABI over libcirc: ten `circ_*` exports, one library-owned result
//! buffer, and a per-call arena. This file is the root of `libcirc.a`
//! (and, through `wasm_root.zig`, of the wasm module), so its `std_options`
//! decides logging: nothing is ever written to a host's stderr.
//!
//! Not thread-safe: the result buffer, the call arena and the engine arena
//! are process globals.
const std = @import("std");
const libcirc = @import("libcirc");

pub const std_options: std.Options = .{
    .log_level = .warn,
    .logFn = quietLog,
};

fn quietLog(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = level;
    _ = scope;
    _ = format;
    _ = args;
}

const Status = libcirc.Status;

var result_buf: std.ArrayListUnmanaged(u8) = .{};
var call_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

fn setResult(bytes: []const u8) Status {
    result_buf.clearRetainingCapacity();
    result_buf.appendSlice(std.heap.page_allocator, bytes) catch {
        result_buf.clearRetainingCapacity();
        return .out_of_memory;
    };
    return .ok;
}

fn setErrorResult(message: []const u8) Status {
    result_buf.clearRetainingCapacity();
    const w = result_buf.writer(std.heap.page_allocator);
    libcirc.json.writeError(w, message) catch {
        result_buf.clearRetainingCapacity();
        return .out_of_memory;
    };
    return .bad_request;
}

const Entry = *const fn (std.mem.Allocator, libcirc.Request) std.mem.Allocator.Error!libcirc.Outcome;

fn dispatch(req_ptr: [*]const u8, len: usize, entry: Entry) u32 {
    _ = call_arena.reset(.retain_capacity);
    const allocator = call_arena.allocator();
    const bytes = req_ptr[0..len];

    const req = libcirc.json.parseRequest(allocator, bytes) catch |err| switch (err) {
        error.OutOfMemory => return @intFromEnum(Status.out_of_memory),
        else => return @intFromEnum(setErrorResult(libcirc.json.describe(err))),
    };
    const out = entry(allocator, req) catch return @intFromEnum(Status.out_of_memory);
    if (setResult(out.body) != .ok) return @intFromEnum(Status.out_of_memory);
    return @intFromEnum(out.status);
}

/// Request buffers: the caller fills what `circ_alloc` returns and frees it
/// with `circ_free` after the call (the library never keeps a pointer to it).
pub export fn circ_alloc(len: usize) callconv(.c) ?[*]u8 {
    const slice = std.heap.page_allocator.alloc(u8, len) catch return null;
    return slice.ptr;
}

pub export fn circ_free(ptr: [*]u8, len: usize) callconv(.c) void {
    std.heap.page_allocator.free(ptr[0..len]);
}

/// Status 0; the result is the version JSON.
pub export fn circ_version() callconv(.c) u32 {
    result_buf.clearRetainingCapacity();
    libcirc.writeVersionJson(result_buf.writer(std.heap.page_allocator)) catch {
        result_buf.clearRetainingCapacity();
        return @intFromEnum(Status.out_of_memory);
    };
    return @intFromEnum(Status.ok);
}

pub export fn circ_analyze(req: [*]const u8, len: usize) callconv(.c) u32 {
    return dispatch(req, len, libcirc.analyze);
}

pub export fn circ_compile(req: [*]const u8, len: usize) callconv(.c) u32 {
    return dispatch(req, len, libcirc.compile);
}

pub export fn circ_preview(req: [*]const u8, len: usize) callconv(.c) u32 {
    return dispatch(req, len, libcirc.preview);
}

pub export fn circ_truth_table(req: [*]const u8, len: usize) callconv(.c) u32 {
    return dispatch(req, len, libcirc.truthTable);
}

/// Library-owned; valid until the next `circ_*` call.
pub export fn circ_result_ptr() callconv(.c) [*]const u8 {
    return result_buf.items.ptr;
}

pub export fn circ_result_len() callconv(.c) usize {
    return result_buf.items.len;
}

/// Drop the result buffer, the call arena and the engine arena. Returns 0.
pub export fn circ_reset() callconv(.c) u32 {
    result_buf.clearAndFree(std.heap.page_allocator);
    _ = call_arena.reset(.free_all);
    libcirc.circuit.memory.reset();
    return @intFromEnum(Status.ok);
}
