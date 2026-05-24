const std = @import("std");
const full_format = @import("full_format");
const layout = @import("layout");
const types = @import("layout_types");

const FullTopology = full_format.FullTopology;
const FullComponentRecord = full_format.FullComponentRecord;
const FullConnectionRecord = full_format.FullConnectionRecord;
const OriginFrame = full_format.OriginFrame;
const VirtualNode = types.VirtualNode;
const VirtualGraph = types.VirtualGraph;
const InputEdge = types.InputEdge;
const OutputEdge = types.OutputEdge;
const NodeKind = types.NodeKind;

const GroupKey = struct {
    alias: []const u8,
    subcircuit: []const u8,

    fn eql(a: GroupKey, b: GroupKey) bool {
        return std.mem.eql(u8, a.alias, b.alias) and std.mem.eql(u8, a.subcircuit, b.subcircuit);
    }
};

const SRC_PORT_OUT: u8 = @intFromEnum(full_format.PortName.out);

/// Stage 1: produce a `VirtualGraph` from a `FullTopology`.
///
/// Always:
///   - Drops every `wire` primitive. Edges that flowed `A → wire → B` (possibly
///     through chains of wires) are reissued as direct `A → B` edges.
///
/// Opaque mode (`opts.expand_macros == false`):
///   - Primitives sharing the same outermost `OriginFrame` (alias + subcircuit)
///     collapse into one virtual subcircuit node with a synthetic id allocated
///     above `max(component.id) + 1`. The group's internal connections vanish;
///     external connections remap to/from the virtual node.
///
/// Expanded mode (`opts.expand_macros == true`):
///   - Every non-wire primitive becomes its own VirtualNode preserving its real
///     id and full origin chain.
pub fn collapse(arena: std.mem.Allocator, topology: FullTopology, opts: layout.LayoutOptions) !VirtualGraph {
    // ---------- 1. Build kind + name lookups, identify passthroughs ----------
    var kind_of = std.AutoHashMap(u32, full_format.ComponentKind).init(arena);
    var name_of = std.AutoHashMap(u32, []const u8).init(arena);
    // Inner subcircuit pins (non-empty origin chain) act as signal pass-throughs
    // in expanded mode: they only exist to give a macro its `a`/`b`/`out` ports
    // a name, and have no electrical effect. We collapse them into the wire
    // chain so the rendered graph shows only the OUTER pins plus the actual
    // gates inside expanded macros.
    var is_inner_pin = std.AutoHashMap(u32, void).init(arena);
    var max_id: u32 = 0;
    for (topology.components) |comp| {
        try kind_of.put(comp.id, comp.kind);
        try name_of.put(comp.id, comp.name);
        if (comp.origin.len > 0 and (comp.kind == .input_pin or comp.kind == .output_pin)) {
            try is_inner_pin.put(comp.id, {});
        }
        if (comp.id > max_id) max_id = comp.id;
    }

    // ---------- 2. Resolve passthrough chains ----------
    // A *passthrough* is any component the renderer should look past:
    //   - Wires (always).
    //   - Inner subcircuit pins (only in expanded mode).
    // For each passthrough, find the non-passthrough source that ultimately
    // drives it. Components with no driver leave no entry; their dangling
    // edges are silently dropped downstream.
    var driver_of = std.AutoHashMap(u32, u32).init(arena);
    for (topology.connections) |conn| {
        if (isPassthrough(conn.to_id, kind_of, is_inner_pin, opts.expand_macros)) {
            try driver_of.put(conn.to_id, conn.from_id);
        }
    }
    var resolved_source = std.AutoHashMap(u32, u32).init(arena);
    for (topology.components) |comp| {
        if (!isPassthrough(comp.id, kind_of, is_inner_pin, opts.expand_macros)) continue;
        var current = comp.id;
        var depth: u8 = 0;
        while (depth < 64) : (depth += 1) {
            const drv = driver_of.get(current) orelse break;
            if (!isPassthrough(drv, kind_of, is_inner_pin, opts.expand_macros)) {
                try resolved_source.put(comp.id, drv);
                break;
            }
            current = drv;
        }
    }

    // ---------- 3. Determine groups (opaque mode only) ----------
    var group_keys: std.ArrayList(GroupKey) = .{};
    var group_of_id = std.AutoHashMap(u32, u32).init(arena);
    if (!opts.expand_macros) {
        for (topology.components) |comp| {
            if (comp.kind == .wire) continue;
            if (comp.origin.len == 0) continue;
            const outer = comp.origin[0];
            const key = GroupKey{ .alias = outer.alias, .subcircuit = outer.subcircuit };
            var found_idx: ?u32 = null;
            for (group_keys.items, 0..) |existing, i| {
                if (GroupKey.eql(existing, key)) {
                    found_idx = @intCast(i);
                    break;
                }
            }
            const idx = if (found_idx) |i| i else blk: {
                const new_idx: u32 = @intCast(group_keys.items.len);
                try group_keys.append(arena, key);
                break :blk new_idx;
            };
            try group_of_id.put(comp.id, idx);
        }
    }

    // ---------- 4. Allocate virtual ids ----------
    var next_synthetic_id = max_id + 1;
    const group_virtual_id = try arena.alloc(u32, group_keys.items.len);
    for (group_virtual_id) |*gvid| {
        gvid.* = next_synthetic_id;
        next_synthetic_id += 1;
    }

    var virtual_id_of = std.AutoHashMap(u32, u32).init(arena);
    for (topology.components) |comp| {
        if (isPassthrough(comp.id, kind_of, is_inner_pin, opts.expand_macros)) continue;
        if (group_of_id.get(comp.id)) |group_idx| {
            try virtual_id_of.put(comp.id, group_virtual_id[group_idx]);
        } else {
            try virtual_id_of.put(comp.id, comp.id);
        }
    }

    // ---------- 5. Walk connections, accumulate edges per virtual node ----------
    var node_inputs = std.AutoHashMap(u32, std.ArrayList(InputEdge)).init(arena);
    var node_outputs = std.AutoHashMap(u32, std.ArrayList(OutputEdge)).init(arena);

    // Initialize per-virtual-node edge buckets.
    for (topology.components) |comp| {
        if (isPassthrough(comp.id, kind_of, is_inner_pin, opts.expand_macros)) continue;
        const vid = virtual_id_of.get(comp.id) orelse continue;
        if (!node_inputs.contains(vid)) {
            try node_inputs.put(vid, .{});
            try node_outputs.put(vid, .{});
        }
    }

    for (topology.connections) |conn| {
        // Skip edges whose destination is a passthrough — the renderer will
        // reissue them from the passthrough's resolved upstream when we
        // encounter the next non-passthrough downstream of the chain.
        if (isPassthrough(conn.to_id, kind_of, is_inner_pin, opts.expand_macros)) continue;

        // Resolve source: if `from` is a passthrough (wire or inner pin),
        // walk through it to the real driving component upstream.
        var effective_source = conn.from_id;
        if (isPassthrough(conn.from_id, kind_of, is_inner_pin, opts.expand_macros)) {
            effective_source = resolved_source.get(conn.from_id) orelse continue; // dangling
        }

        const src_vid = virtual_id_of.get(effective_source) orelse continue;
        const dst_vid = virtual_id_of.get(conn.to_id) orelse continue;
        if (src_vid == dst_vid) continue; // internal to a collapsed group

        // Boundary remap: when the destination is a collapsed group, the
        // raw `conn.port` describes the *internal* component's port (e.g.
        // an input_pin's `in`), not the macro's external port. Re-key by
        // the internal pin's name (`a`, `b`, …) so each macro input lands
        // on a distinct slot. Same idea on the source side for completeness.
        const dst_port = remappedPort(conn.port, conn.to_id, dst_vid, kind_of, name_of);
        const src_port = remappedPort(SRC_PORT_OUT, effective_source, src_vid, kind_of, name_of);

        if (node_outputs.getPtr(src_vid)) |outputs| {
            try outputs.append(arena, .{
                .dst_id = dst_vid,
                .src_port = src_port,
                .dst_port = dst_port,
            });
        }
        if (node_inputs.getPtr(dst_vid)) |inputs| {
            try inputs.append(arena, .{
                .src_id = src_vid,
                .src_port = src_port,
                .dst_port = dst_port,
            });
        }
    }

    // ---------- 6. Materialize VirtualNodes ----------
    var nodes: std.ArrayList(VirtualNode) = .{};

    for (topology.components) |comp| {
        if (isPassthrough(comp.id, kind_of, is_inner_pin, opts.expand_macros)) continue;
        if (group_of_id.contains(comp.id)) continue;
        const vid = virtual_id_of.get(comp.id).?;
        const inputs_list = node_inputs.get(vid).?;
        const outputs_list = node_outputs.get(vid).?;
        try nodes.append(arena, .{
            .id = comp.id,
            .kind = .{ .primitive = comp.kind },
            .name = comp.name,
            .origin = comp.origin,
            .inputs = inputs_list.items,
            .outputs = outputs_list.items,
            .signal_width = comp.width,
        });
    }

    for (group_keys.items, 0..) |key, idx| {
        const vid = group_virtual_id[idx];
        const inputs_list = node_inputs.get(vid).?;
        const outputs_list = node_outputs.get(vid).?;
        try nodes.append(arena, .{
            .id = vid,
            .kind = .{ .subcircuit = key.subcircuit },
            .name = key.alias,
            .origin = &.{},
            .inputs = inputs_list.items,
            .outputs = outputs_list.items,
        });
    }

    // Sort by id ascending for deterministic iteration.
    std.mem.sort(VirtualNode, nodes.items, {}, struct {
        fn lessThan(_: void, a: VirtualNode, b: VirtualNode) bool {
            return a.id < b.id;
        }
    }.lessThan);

    return VirtualGraph{
        .nodes = try nodes.toOwnedSlice(arena),
        .next_id = next_synthetic_id,
    };
}

/// True when this component should be looked past during edge resolution.
/// Wires are always passthroughs. Inner subcircuit pins (origin chain non-
/// empty) are passthroughs only in expanded mode — opaque mode swallows
/// them via group collapsing instead.
fn isPassthrough(
    id: u32,
    kind_of: std.AutoHashMap(u32, full_format.ComponentKind),
    is_inner_pin: std.AutoHashMap(u32, void),
    expand: bool,
) bool {
    const k = kind_of.get(id) orelse return false;
    // Slice and concat act as passthroughs at the preview layer: they
    // have no glyph and downstream consumers see their upstream sources
    // directly. Bit-range and concat semantics aren't rendered today.
    if (k == .wire or k == .slice or k == .concat) return true;
    if (!expand) return false;
    return is_inner_pin.contains(id);
}

/// When `real_id` was collapsed into a macro group (`real_id != vid`) and the
/// underlying primitive is an `input_pin` / `output_pin` whose `name` matches a
/// known `PortName` (`a`, `b`, `in`, `out`), return that name's port byte.
/// Otherwise return `default_port` unchanged.
fn remappedPort(
    default_port: u8,
    real_id: u32,
    vid: u32,
    kind_of: std.AutoHashMap(u32, full_format.ComponentKind),
    name_of: std.AutoHashMap(u32, []const u8),
) u8 {
    if (real_id == vid) return default_port; // not collapsed.
    const inner_kind = kind_of.get(real_id) orelse return default_port;
    if (inner_kind != .input_pin and inner_kind != .output_pin) return default_port;
    const inner_name = name_of.get(real_id) orelse return default_port;
    return portByteFromName(inner_name) orelse default_port;
}

fn portByteFromName(name: []const u8) ?u8 {
    if (std.mem.eql(u8, name, "in")) return @intFromEnum(full_format.PortName.in);
    if (std.mem.eql(u8, name, "a")) return @intFromEnum(full_format.PortName.a);
    if (std.mem.eql(u8, name, "b")) return @intFromEnum(full_format.PortName.b);
    if (std.mem.eql(u8, name, "out")) return @intFromEnum(full_format.PortName.out);
    return null;
}

// ---------- Tests ----------

const span = full_format.OriginFrame{ .alias = "", .subcircuit = "", .target_file = 0 };

fn arenaAllocator() std.mem.Allocator {
    // Helpers for constructing test topologies use std.testing.allocator via per-test arenas.
    return undefined;
}

test "collapse_drops_wire_primitives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // pin → wire → led
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "p", .origin = &.{} },
        .{ .id = 1, .kind = .wire, .width = 1, .name = "w", .origin = &.{} },
        .{ .id = 2, .kind = .led, .width = 1, .name = "l", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.in) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.in) },
    };
    const topo = FullTopology{ .components = &components, .connections = &connections };

    const graph = try collapse(a, topo, .{ .expand_macros = false });
    try std.testing.expectEqual(@as(usize, 2), graph.nodes.len);

    // Node ids should be 0 (pin) and 2 (led); the wire (id=1) is dropped.
    try std.testing.expectEqual(@as(u32, 0), graph.nodes[0].id);
    try std.testing.expectEqual(@as(u32, 2), graph.nodes[1].id);

    // pin has one output to led.
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[0].outputs.len);
    try std.testing.expectEqual(@as(u32, 2), graph.nodes[0].outputs[0].dst_id);

    // led has one input from pin.
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[1].inputs.len);
    try std.testing.expectEqual(@as(u32, 0), graph.nodes[1].inputs[0].src_id);
}

test "collapse_chains_of_wires" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // pin → wire → wire → wire → led
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "p", .origin = &.{} },
        .{ .id = 1, .kind = .wire, .width = 1, .name = "w1", .origin = &.{} },
        .{ .id = 2, .kind = .wire, .width = 1, .name = "w2", .origin = &.{} },
        .{ .id = 3, .kind = .wire, .width = 1, .name = "w3", .origin = &.{} },
        .{ .id = 4, .kind = .led, .width = 1, .name = "l", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.in) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.in) },
        .{ .from_id = 2, .to_id = 3, .port = @intFromEnum(full_format.PortName.in) },
        .{ .from_id = 3, .to_id = 4, .port = @intFromEnum(full_format.PortName.in) },
    };
    const topo = FullTopology{ .components = &components, .connections = &connections };

    const graph = try collapse(a, topo, .{ .expand_macros = false });
    try std.testing.expectEqual(@as(usize, 2), graph.nodes.len);
    try std.testing.expectEqual(@as(u32, 0), graph.nodes[0].id);
    try std.testing.expectEqual(@as(u32, 4), graph.nodes[1].id);

    // Direct edge pin → led (collapsed through three wires).
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[0].outputs.len);
    try std.testing.expectEqual(@as(u32, 4), graph.nodes[0].outputs[0].dst_id);
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[1].inputs.len);
    try std.testing.expectEqual(@as(u32, 0), graph.nodes[1].inputs[0].src_id);
}

test "collapse_opaque_subcircuit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // pin (id 0) → not_gate (id 1, in xor:g) → and_gate (id 2, in xor:g) → led (id 3)
    // Inside subcircuit "xor" with instance alias "g": components 1 and 2.
    const xor_origin = [_]OriginFrame{
        .{ .alias = "g", .subcircuit = "xor", .target_file = 1 },
    };
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "p", .origin = &.{} },
        .{ .id = 1, .kind = .not_gate, .width = 1, .name = "n", .origin = &xor_origin },
        .{ .id = 2, .kind = .and_gate, .width = 1, .name = "a", .origin = &xor_origin },
        .{ .id = 3, .kind = .led, .width = 1, .name = "l", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.in) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.a) }, // internal — vanishes
        .{ .from_id = 2, .to_id = 3, .port = @intFromEnum(full_format.PortName.in) },
    };
    const topo = FullTopology{ .components = &components, .connections = &connections };

    const graph = try collapse(a, topo, .{ .expand_macros = false });

    // Three nodes: pin (0), virtual subcircuit (synthetic, > max_id=3 so id=4), led (3).
    try std.testing.expectEqual(@as(usize, 3), graph.nodes.len);
    try std.testing.expectEqual(@as(u32, 0), graph.nodes[0].id);
    try std.testing.expectEqual(@as(u32, 3), graph.nodes[1].id);
    try std.testing.expectEqual(@as(u32, 4), graph.nodes[2].id);

    // The virtual node is the subcircuit.
    try std.testing.expect(graph.nodes[2].kind == .subcircuit);
    try std.testing.expectEqualStrings("xor", graph.nodes[2].kind.subcircuit);
    try std.testing.expectEqualStrings("g", graph.nodes[2].name);

    // Internal not→and connection vanishes; only two external edges remain.
    // pin → virtual (one output)
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[0].outputs.len);
    try std.testing.expectEqual(@as(u32, 4), graph.nodes[0].outputs[0].dst_id);
    // virtual → led (one output), virtual ← pin (one input)
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[2].inputs.len);
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[2].outputs.len);
    try std.testing.expectEqual(@as(u32, 3), graph.nodes[2].outputs[0].dst_id);
    // led ← virtual (one input)
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[1].inputs.len);
    try std.testing.expectEqual(@as(u32, 4), graph.nodes[1].inputs[0].src_id);

    // next_id is one past the synthetic id we used.
    try std.testing.expectEqual(@as(u32, 5), graph.next_id);
}

test "collapse_expanded_subcircuit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Same shape as the opaque test, but expand_macros = true → all primitives appear separately.
    const xor_origin = [_]OriginFrame{
        .{ .alias = "g", .subcircuit = "xor", .target_file = 1 },
    };
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "p", .origin = &.{} },
        .{ .id = 1, .kind = .not_gate, .width = 1, .name = "n", .origin = &xor_origin },
        .{ .id = 2, .kind = .and_gate, .width = 1, .name = "a", .origin = &xor_origin },
        .{ .id = 3, .kind = .led, .width = 1, .name = "l", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.in) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.a) },
        .{ .from_id = 2, .to_id = 3, .port = @intFromEnum(full_format.PortName.in) },
    };
    const topo = FullTopology{ .components = &components, .connections = &connections };

    const graph = try collapse(a, topo, .{ .expand_macros = true });

    // All four primitives appear; ids preserved.
    try std.testing.expectEqual(@as(usize, 4), graph.nodes.len);
    try std.testing.expectEqual(@as(u32, 0), graph.nodes[0].id);
    try std.testing.expectEqual(@as(u32, 1), graph.nodes[1].id);
    try std.testing.expectEqual(@as(u32, 2), graph.nodes[2].id);
    try std.testing.expectEqual(@as(u32, 3), graph.nodes[3].id);

    // Origin chains preserved in expanded mode.
    try std.testing.expectEqual(@as(usize, 0), graph.nodes[0].origin.len);
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[1].origin.len);
    try std.testing.expectEqualStrings("xor", graph.nodes[1].origin[0].subcircuit);
    try std.testing.expectEqualStrings("g", graph.nodes[1].origin[0].alias);

    // All three connections survive (no group, no internal collapse).
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[0].outputs.len);
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[1].outputs.len);
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[2].outputs.len);
    try std.testing.expectEqual(@as(usize, 1), graph.nodes[3].inputs.len);
}
