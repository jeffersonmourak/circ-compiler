const std = @import("std");

// Use ArenaAllocator for WASM compatibility - it doesn't rely on system calls
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const allocator = arena.allocator();

pub fn deinit() void {
    arena.deinit();
}
