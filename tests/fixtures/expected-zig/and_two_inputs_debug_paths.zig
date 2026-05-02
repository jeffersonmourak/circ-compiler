const DebugPath = struct {
    component_id: u32,
    segments: []const []const u8,
};
const debug_paths: []const DebugPath = &.{
    .{ .component_id = 0, .segments = &.{ "and_two_inputs.circ", "a" } },
    .{ .component_id = 1, .segments = &.{ "and_two_inputs.circ", "b" } },
    .{ .component_id = 2, .segments = &.{ "and_two_inputs.circ", "gate1" } },
    .{ .component_id = 3, .segments = &.{ "and_two_inputs.circ", "result" } },
};
