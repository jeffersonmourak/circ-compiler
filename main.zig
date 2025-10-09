const std = @import("std");
const transport = @import("lib/transport.zig");
const memory = @import("lib/memory.zig");

const Circuit = @import("lib/circuit.zig").Circuit;
const Component = @import("lib/circuit.zig").Component;

const log = std.log.scoped(.log);

pub fn main() !void {
    defer memory.deinit();

    var circuit = try Circuit.init();
    defer circuit.deinit();

    const input1 = try circuit.createComponent(.{ .input_pin_gate = .{} });
    const input2 = try circuit.createComponent(.{ .input_pin_gate = .{} });
    const and1 = try circuit.createComponent(.{ .and_gate = .{ .inputs = .{ null, null } } });
    const wire1 = try circuit.createComponent(.{ .wire = .{ .inputs = .{} } });
    const wire2 = try circuit.createComponent(.{ .wire = .{ .inputs = .{} } });
    const led1 = try circuit.createComponent(.{ .led = .{} });
    const led2 = try circuit.createComponent(.{ .led = .{} });

    try circuit.connect(input1, 0, and1, 0);
    try circuit.connect(input2, 0, and1, 1);
    try circuit.connect(and1, 0, wire1, 0);
    try circuit.connect(wire1, 0, led1, 0);
    try circuit.connect(wire1, 0, wire2, 0);
    try circuit.connect(wire2, 0, led2, 0);

    log.info("Circuit: (InputA, InputB) -> AND -> WIRE -> LED", .{});
    log.info("Initial LED state: {s}\n", .{@tagName(led1.output_state)});

    log.info("--- User flips switch ON ---", .{});

    log.info("BATCH 1", .{});
    try circuit.propagateEvent(input1, .low);
    try circuit.propagateEvent(input2, .low);
    circuit.printState();

    log.info("\n\nBATCH 2", .{});
    try circuit.propagateEvent(input1, .low);
    try circuit.propagateEvent(input2, .high);
    circuit.printState();

    log.info("\n\nBATCH 3", .{});
    try circuit.propagateEvent(input1, .high);
    try circuit.propagateEvent(input2, .high);
    circuit.printState();

    // try circuit.propagateEvent(input1, .high);
    // try circuit.propagateEvent(input2, .low);

    log.info("Final LED state: {s}", .{@tagName(led1.output_state)});

    const state = try circuit.encodeState();
    defer memory.allocator.free(state);
    log.info("Encoded state: {any}", .{state});
}
