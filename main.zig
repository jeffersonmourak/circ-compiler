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

    // demo_input.circ @ Ln 1 Col 7-11
    const pin1 = try circuit.createComponent(.{ .input_pin_gate = .{} });
    // demo_input.circ @ Ln 1 Col 13-17
    const pin2 = try circuit.createComponent(.{ .input_pin_gate = .{} });

    // demo_input.circ @ Ln 3 Col 1-12
    const combine = try circuit.createComponent(.{ .and_gate = .{} });
    // demo_input.circ @ Ln 4 Col 5-17
    try circuit.connect(pin1.port("out"), combine.port("a"));

    // demo_input.circ @ Ln 5 Col 9-12
    const anon_1 = try circuit.createComponent(.{ .not_gate = .{} });

    // demo_input.circ @ Ln 6 Col 9-22
    try circuit.connect(pin2.port("out"), anon_1.port("in"));

    // demo_input.circ @ Ln 5 Col 5-12
    try circuit.connect(anon_1.port("out"), combine.port("b"));

    // demo_input.circ @ Ln 10 Col 1-11
    const result = try circuit.createComponent(.{ .led = .{} });
    // demo_input.circ @ Ln 11 Col 5-21
    try circuit.connect(combine.port("out"), result.port("in"));

    log.info("Circuit: demo_input.circ", .{});
    log.info("Initial LED state: {s}\n", .{@tagName(result.output_state)});

    log.info("--- User flips switch ON ---", .{});

    log.info("BATCH 1", .{});
    try circuit.propagateEvent(pin1, .low);
    try circuit.propagateEvent(pin2, .low);
    circuit.printState();

    log.info("\n\nBATCH 2", .{});
    try circuit.propagateEvent(pin1, .low);
    try circuit.propagateEvent(pin2, .high);
    circuit.printState();

    log.info("\n\nBATCH 3", .{});
    try circuit.propagateEvent(pin1, .high);
    try circuit.propagateEvent(pin2, .high);
    circuit.printState();

    // try circuit.propagateEvent(input1, .high);
    // try circuit.propagateEvent(input2, .low);

    log.info("Final LED state: {s}", .{@tagName(result.output_state)});

    const state = try circuit.encodeState();
    defer memory.allocator.free(state);
    log.info("Encoded state: {any}", .{state});
}
