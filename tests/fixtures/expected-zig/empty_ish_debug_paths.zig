const DebugPath = struct {
    component_id: u32,
    segments: []const []const u8,
};
const debug_paths: []const DebugPath = &.{
    .{ .component_id = 0, .segments = &.{ "empty_ish.circ", "a" } },
    .{ .component_id = 1, .segments = &.{ "empty_ish.circ", "out" } },
};
