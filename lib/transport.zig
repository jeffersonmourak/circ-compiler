const std = @import("std");

const Component = @import("circuit.zig").Component;

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

pub fn encodeState(component: *Component) EncodedState {
    return .{
        .state = @as(u8, @intFromEnum(component.output_state)),
        .kind = @as(u8, @intFromEnum(component.kind)),
        .id = @as([4]u8, @bitCast(component.id)),
    };
}
