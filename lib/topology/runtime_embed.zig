const std = @import("std");

// We import the pre-built WASM blob via an anonymous import mapped in build.zig
// This ensures the dependency order is correct.
pub const runtime_wasm = @import("circ-runtime.wasm");

comptime {
    std.debug.assert(runtime_wasm.len > 0);
}
