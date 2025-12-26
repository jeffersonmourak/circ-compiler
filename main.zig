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
    const and1 = try circuit.createComponent(.{ .and_gate = .{} });
    const wire1 = try circuit.createComponent(.{ .wire = .{} });
    const wire2 = try circuit.createComponent(.{ .wire = .{} });
    const led1 = try circuit.createComponent(.{ .led = .{} });
    const led2 = try circuit.createComponent(.{ .led = .{} });

    try circuit.connect(input1.port("out"), and1.port("a"));
    try circuit.connect(input2.port("out"), and1.port("b"));
    try circuit.connect(and1.port("out"), wire1.port("in"));
    try circuit.connect(wire1.port("out"), led1.port("in"));
    try circuit.connect(wire1.port("out"), wire2.port("in"));
    try circuit.connect(wire2.port("out"), led2.port("in"));

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
