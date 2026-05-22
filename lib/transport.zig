const std = @import("std");

const Component = @import("circuit.zig").Component;
const Circuit = @import("circuit.zig").Circuit;
const BitVecState = @import("circuit.zig").BitVecState;

fn kindByte(kind: anytype) u8 {
    return switch (kind) {
        .input_pin_gate => 0,
        .not_gate => 1,
        .led => 2,
        .and_gate => 3,
        .wire => 4,
        .output_pin => 5,
    };
}

pub const EncodedState = extern struct {
    state: u8,
    kind: u8,
    id: [4]u8,

    pub fn encode(self: EncodedState, gpa: std.mem.Allocator) ![]u8 {
        var data: std.ArrayList(u8) = .{};
        try data.append(gpa, self.state);
        try data.append(gpa, self.kind);
        try data.append(gpa, self.id[0]);
        // deactivated to debug purposes
        // try data.append(gpa, self.id[1]);
        // try data.append(gpa, self.id[2]);
        // try data.append(gpa, self.id[3]);

        return data.toOwnedSlice(gpa);
    }

    pub fn decode(self: []u8) EncodedState {
        return @as(EncodedState, @ptrCast(self.ptr))[0..@sizeOf(EncodedState)];
    }
};

/// Encodes a component's identity (kind + id) together with its current
/// state into the 3-byte WASM wire format. State now arrives explicitly
/// because the engine no longer carries it inline on `Component`; callers
/// fetch it via `Circuit.readState(component.state_handle)`.
///
/// For width=1, `BitVecState.toTransportByte` produces the same byte values
/// that `@intFromEnum(State)` did (undefined=0, low=1, high=2), so the wire
/// format is byte-identical across the refactor.
pub fn encodeState(component: *Component, state: BitVecState) EncodedState {
    return .{
        .state = state.toTransportByte(),
        .kind = kindByte(component.kind),
        .id = @as([4]u8, @bitCast(component.id)),
    };
}

test "transport: encodes output_pin state" {
    var circuit = try Circuit.init();
    defer circuit.deinit();

    const output_pin = try circuit.createComponent(.{ .output_pin = .{} }, 1);
    const state = circuit.readState(output_pin.state_handle);
    const encoded = try encodeState(output_pin, state).encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);

    try std.testing.expectEqual(@as(usize, 3), encoded.len);
    try std.testing.expectEqual(@as(u8, 0), encoded[0]);
    try std.testing.expectEqual(@as(u8, 5), encoded[1]);
    try std.testing.expectEqual(@as(u8, 0), encoded[2]);
}
