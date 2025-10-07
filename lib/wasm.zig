const std = @import("std");
// const transport = @import("transport.zig");
// const memory = @import("memory.zig");

// const Circuit = @import("circuit.zig").Circuit;
// const Component = @import("circuit.zig").Component;

// pub fn init() void {
//     transport.init();
//     memory.init();
// }

export fn sum(a: i32, b: i32) i32 {
    return a + b;
}
