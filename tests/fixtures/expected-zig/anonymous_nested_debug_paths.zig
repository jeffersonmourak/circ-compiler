const DebugPath = struct {
    component_id: u32,
    segments: []const []const u8,
};
const debug_paths: []const DebugPath = &.{
    .{ .component_id = 0, .segments = &.{ "anonymous_nested.circ", "a" } },
    .{ .component_id = 1, .segments = &.{ "anonymous_nested.circ", "gate" } },
    .{ .component_id = 2, .segments = &.{ "anonymous_nested.circ", "__anon_0" } },
    .{ .component_id = 3, .segments = &.{ "anonymous_nested.circ", "result" } },
};
