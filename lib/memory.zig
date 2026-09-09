const std = @import("std");
const build_options = @import("build_options");

/// Compile-time switch. Mirrors the same flag the engine uses for its
/// `Metrics` struct — when false, the counting wrapper is bypassed and
/// `allocator` is the raw arena, byte-identical to a pre-instrumentation
/// build. The bench step is the only consumer that turns this on.
pub const COLLECT_METRICS: bool = build_options.collect_metrics;

pub const AllocMetrics = struct {
    /// Number of successful alloc() calls.
    allocs: u64 = 0,
    /// Total bytes requested across all successful alloc() calls.
    bytes: u64 = 0,
};

/// `std.mem.Allocator` wrapper that counts successful `alloc()` calls and
/// bytes. `resize`/`remap`/`free` pass straight through without counting:
/// the backing arena treats `free` as a no-op anyway, and `std.ArrayList`
/// growth ultimately calls `alloc()` for fresh buffers (the old buffer is
/// abandoned in the arena), so `alloc()`-only is a faithful proxy for engine
/// heap pressure.
const Counter = struct {
    inner: std.mem.Allocator,
    metrics: AllocMetrics = .{},

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Counter = @ptrCast(@alignCast(ctx));
        const result = self.inner.vtable.alloc(self.inner.ptr, len, alignment, ret_addr);
        if (result != null) {
            self.metrics.allocs += 1;
            self.metrics.bytes += len;
        }
        return result;
    }

    fn resize(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Counter = @ptrCast(@alignCast(ctx));
        return self.inner.vtable.resize(self.inner.ptr, mem, alignment, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *Counter = @ptrCast(@alignCast(ctx));
        return self.inner.vtable.remap(self.inner.ptr, mem, alignment, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, mem: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *Counter = @ptrCast(@alignCast(ctx));
        self.inner.vtable.free(self.inner.ptr, mem, alignment, ret_addr);
    }

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn allocator(self: *Counter) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }
};

// Use ArenaAllocator for WASM compatibility - it doesn't rely on system calls
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var counter: Counter = .{ .inner = arena.allocator() };

pub const allocator: std.mem.Allocator = if (COLLECT_METRICS)
    counter.allocator()
else
    arena.allocator();

pub fn deinit() void {
    arena.deinit();
}

/// Releases every byte the engine arena holds and keeps the allocator
/// usable. Legal only while no `Circuit`/`Session` is alive; a library host
/// calls it between independent runs so a long-lived process does not grow
/// without bound. The `COLLECT_METRICS` counters are not touched.
pub fn reset() void {
    _ = arena.reset(.free_all);
}

/// Bytes the engine arena currently holds. Test-only observability for
/// `reset()`.
pub fn arenaCapacityForTest() usize {
    return arena.queryCapacity();
}

/// Returns a snapshot of cumulative allocation counters. Always zero when
/// `COLLECT_METRICS` is false. The bench computes per-fixture deltas by
/// snapshotting before and after `runFixture`; the global counter is never
/// reset because the bench is the only consumer that reads it.
pub fn snapshotAllocMetrics() AllocMetrics {
    if (COLLECT_METRICS) return counter.metrics;
    return .{};
}
