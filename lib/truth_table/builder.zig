const std = @import("std");
const engine = @import("circuit");
const full_format = @import("full_format");

/// Re-export of the engine's `BitVecState`. Callers that only depend on
/// the truth-table layer can construct cell values without taking a
/// separate dependency on `circuit`.
pub const BitVecState = engine.BitVecState;

pub const State = enum(u2) {
    low = 0,
    high = 1,
    undef = 2,

    /// Scalar-only summary of a `BitVecState`. Multi-bit cells should be
    /// inspected directly via the `BitVecState` value/defined pair; this
    /// helper exists for callers (like `--strict`) that need a quick
    /// "is this bit undefined" check.
    pub fn fromEngine(s: engine.BitVecState) State {
        if (s.isUndefined()) return .undef;
        if (s.width == 1) {
            if (s.isLow()) return .low;
            return .high;
        }
        // Multi-bit fully-defined cells collapse to `.high` for legacy
        // scalar consumers. The renderers should prefer the underlying
        // `BitVecState` instead of going through `State`.
        return .high;
    }
};

pub const PinRef = struct {
    name: []const u8,
    component_id: u32,
    width: u8,
};

pub const Header = struct {
    inputs: []const PinRef,
    outputs: []const PinRef,
};

pub const Row = struct {
    /// Packed concatenation of every input pin's value, low pin first.
    /// Bit positions `[offset, offset + pin.width)` belong to the i-th
    /// input, where `offset = sum(inputs[0..i].width)`. Total active
    /// bits never exceed `total_input_bits`.
    input_bits: u64,
    outputs: []const engine.BitVecState,
};

pub const Table = struct {
    arena: std.heap.ArenaAllocator,
    header: Header,
    rows: []const Row,
    /// Total bits across all inputs. Equals `sum(inputs[i].width)` and
    /// caps the row count at `1 << total_input_bits`. Recorded on the
    /// table so callers (CLI, renderers) can format messages without
    /// re-walking the inputs.
    total_input_bits: u8,
    /// Engine-level counters captured from the underlying Circuit just
    /// before it was deinit'd. Populated only when the linked engine module
    /// has `COLLECT_METRICS=true` (i.e. inside `zig build bench`); zero
    /// elsewhere. Consumers that don't care about benchmarking can ignore.
    metrics: engine.Metrics = .{},
    /// Wall-clock nanoseconds spent in the `2^N` vector drive loop only,
    /// excluding circuit construction and connection wiring. Lets the bench
    /// separate engine throughput from one-shot setup cost. Always populated
    /// (the timestamp call is cheap); consumers can ignore.
    drive_ns: u64 = 0,

    pub fn deinit(self: *Table) void {
        self.arena.deinit();
    }
};

pub const BuildOptions = struct {
    /// Hard cap on `sum(inputs[i].width)`. Exceeding it returns
    /// `error.TooManyInputs`. The CLI default is 16 with a `--truth-
    /// table-cap` escape hatch up to 24 (per S10's locked design).
    max_input_bits: u8 = 16,
};

pub const BuildError = error{
    TooManyInputs,
    NoOutputs,
    OutOfMemory,
    InvalidTopology,
};

fn portByteToName(port: u8) ![]const u8 {
    const port_name = std.meta.intToEnum(full_format.PortName, port) catch return error.InvalidTopology;
    return switch (port_name) {
        .in => "in",
        .a => "a",
        .b => "b",
        .out => "out",
    };
}

fn widthMaskU64(width: u8) u64 {
    if (width == 0) return 0;
    if (width >= 64) return std.math.maxInt(u64);
    return (@as(u64, 1) << @intCast(width)) - 1;
}

/// Sum the widths of every root-level input pin in the topology. Used
/// by the CLI to size the cap-exceeded error message before invoking
/// `build()`, so the user sees the actual bit count rather than an
/// opaque `TooManyInputs`.
pub fn countInputBits(topology: full_format.FullTopology) u32 {
    var total: u32 = 0;
    for (topology.components) |comp| {
        if (comp.origin.len != 0) continue;
        if (comp.kind != .input_pin) continue;
        total += comp.width;
    }
    return total;
}

pub fn build(
    parent_allocator: std.mem.Allocator,
    topology: full_format.FullTopology,
    options: BuildOptions,
) BuildError!Table {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena.deinit();
    const arena_alloc = arena.allocator();

    // Only the root circuit's pins matter for the truth table. Macro-expanded
    // sub-circuits also emit input_pin / output_pin primitives, but those are
    // wired through to root drivers and aren't independent test vectors. The
    // origin chain is empty exactly for root-level components.
    var input_count: usize = 0;
    var output_count: usize = 0;
    var total_input_bits: u32 = 0;
    for (topology.components) |comp| {
        if (comp.origin.len != 0) continue;
        switch (comp.kind) {
            .input_pin => {
                input_count += 1;
                total_input_bits += comp.width;
            },
            .output_pin => output_count += 1,
            else => {},
        }
    }
    if (total_input_bits > options.max_input_bits) return error.TooManyInputs;
    if (output_count == 0) return error.NoOutputs;

    var inputs = try arena_alloc.alloc(PinRef, input_count);
    var outputs = try arena_alloc.alloc(PinRef, output_count);
    var i_idx: usize = 0;
    var o_idx: usize = 0;
    for (topology.components) |comp| {
        if (comp.origin.len != 0) continue;
        switch (comp.kind) {
            .input_pin => {
                inputs[i_idx] = .{ .name = comp.name, .component_id = comp.id, .width = comp.width };
                i_idx += 1;
            },
            .output_pin => {
                outputs[o_idx] = .{ .name = comp.name, .component_id = comp.id, .width = comp.width };
                o_idx += 1;
            },
            else => {},
        }
    }

    var circuit = engine.Circuit.init() catch return error.InvalidTopology;
    defer circuit.deinit();

    var id_to_node = std.AutoHashMap(u32, *engine.Component).init(arena_alloc);
    try id_to_node.ensureTotalCapacity(@intCast(topology.components.len));
    for (topology.components) |comp| {
        const node = switch (comp.kind) {
            .input_pin => circuit.createComponent(.{ .input_pin_gate = .{} }, comp.width),
            .not_gate => circuit.createComponent(.{ .not_gate = .{} }, comp.width),
            .and_gate => circuit.createComponent(.{ .and_gate = .{} }, comp.width),
            .wire => circuit.createComponent(.{ .wire = .{} }, comp.width),
            .led => circuit.createComponent(.{ .led = .{} }, comp.width),
            .output_pin => circuit.createComponent(.{ .output_pin = .{} }, comp.width),
            .slice => blk: {
                const aux = switch (comp.aux) {
                    .slice => |s| s,
                    else => return error.InvalidTopology,
                };
                break :blk circuit.createComponent(
                    .{ .slice = .{ .lo = aux.lo, .hi = aux.hi } },
                    comp.width,
                );
            },
            .concat => circuit.createComponent(.{ .concat = .{} }, comp.width),
        } catch return error.InvalidTopology;
        node.id = comp.id;
        id_to_node.putAssumeCapacity(comp.id, node);
    }

    for (topology.connections) |conn| {
        const from_node = id_to_node.get(conn.from_id) orelse return error.InvalidTopology;
        const to_node = id_to_node.get(conn.to_id) orelse return error.InvalidTopology;
        // Concat destinations interpret the port byte as an operand
        // index, not a `PortName`. Format the byte back into the
        // `operand_<N>` string the engine's `connect()` expects.
        if (to_node.kind == .concat) {
            var port_buf: [16]u8 = undefined;
            const port_str = std.fmt.bufPrint(&port_buf, "operand_{d}", .{conn.port}) catch return error.InvalidTopology;
            circuit.connect(.{ from_node, "out" }, .{ to_node, port_str }) catch return error.InvalidTopology;
        } else {
            const port_str = portByteToName(conn.port) catch return error.InvalidTopology;
            circuit.connect(.{ from_node, "out" }, .{ to_node, port_str }) catch return error.InvalidTopology;
        }
    }

    const row_count: u64 = if (total_input_bits == 0) 1 else (@as(u64, 1) << @intCast(total_input_bits));
    var rows = try arena_alloc.alloc(Row, @intCast(row_count));

    const drive_start = std.time.nanoTimestamp();
    var mask: u64 = 0;
    while (mask < row_count) : (mask += 1) {
        var bit_offset: u8 = 0;
        for (inputs) |pin| {
            const pin_mask = widthMaskU64(pin.width);
            const shift: u6 = @intCast(bit_offset);
            const value = (mask >> shift) & pin_mask;
            const new_state = engine.BitVecState{
                .value = value,
                .defined = pin_mask,
                .width = pin.width,
            };
            const node = id_to_node.get(pin.component_id) orelse return error.InvalidTopology;
            circuit.propagateEvent(node, new_state) catch return error.InvalidTopology;
            bit_offset += pin.width;
        }

        const row_outputs = try arena_alloc.alloc(engine.BitVecState, output_count);
        for (outputs, 0..) |pin, idx| {
            const node = id_to_node.get(pin.component_id) orelse return error.InvalidTopology;
            row_outputs[idx] = circuit.readState(node.state_handle);
        }
        rows[@intCast(mask)] = .{ .input_bits = mask, .outputs = row_outputs };
    }
    const drive_ns: u64 = @intCast(std.time.nanoTimestamp() - drive_start);

    const metrics_snapshot: engine.Metrics = if (engine.COLLECT_METRICS) circuit.metrics else .{};

    return .{
        .arena = arena,
        .header = .{ .inputs = inputs, .outputs = outputs },
        .rows = rows,
        .total_input_bits = @intCast(total_input_bits),
        .metrics = metrics_snapshot,
        .drive_ns = drive_ns,
    };
}

// ---------- Tests ----------

const test_alloc = std.testing.allocator;
const FullTopology = full_format.FullTopology;
const FullComponentRecord = full_format.FullComponentRecord;
const FullConnectionRecord = full_format.FullConnectionRecord;

fn topo(components: []const FullComponentRecord, connections: []const FullConnectionRecord) FullTopology {
    return .{ .components = components, .connections = connections };
}

test "truth_table_build_and_two_inputs" {
    // a (id=0, input_pin) → and.a, b (id=1, input_pin) → and.b, and(id=2) → out(id=3, output_pin)
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "a", .origin = &.{} },
        .{ .id = 1, .kind = .input_pin, .width = 1, .name = "b", .origin = &.{} },
        .{ .id = 2, .kind = .and_gate, .width = 1, .name = "g", .origin = &.{} },
        .{ .id = 3, .kind = .output_pin, .width = 1, .name = "result", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 2, .port = @intFromEnum(full_format.PortName.a) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.b) },
        .{ .from_id = 2, .to_id = 3, .port = @intFromEnum(full_format.PortName.in) },
    };

    var table = try build(test_alloc, topo(&components, &connections), .{});
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.header.inputs.len);
    try std.testing.expectEqualStrings("a", table.header.inputs[0].name);
    try std.testing.expectEqual(@as(u8, 1), table.header.inputs[0].width);
    try std.testing.expectEqualStrings("b", table.header.inputs[1].name);
    try std.testing.expectEqual(@as(usize, 1), table.header.outputs.len);
    try std.testing.expectEqualStrings("result", table.header.outputs[0].name);

    try std.testing.expectEqual(@as(usize, 4), table.rows.len);
    try std.testing.expectEqual(@as(u8, 2), table.total_input_bits);
    // mask=0 (a=0, b=0) → 0
    try std.testing.expectEqual(@as(u64, 0), table.rows[0].outputs[0].value);
    try std.testing.expectEqual(@as(u64, 1), table.rows[0].outputs[0].defined);
    // mask=3 (a=1, b=1) → 1
    try std.testing.expectEqual(@as(u64, 1), table.rows[3].outputs[0].value);
    try std.testing.expectEqual(@as(u64, 1), table.rows[3].outputs[0].defined);
}

test "truth_table_build_not_gate" {
    // Single-input NOT: input(0) → not(1) → output_pin(2)
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "in", .origin = &.{} },
        .{ .id = 1, .kind = .not_gate, .width = 1, .name = "n", .origin = &.{} },
        .{ .id = 2, .kind = .output_pin, .width = 1, .name = "out", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.in) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.in) },
    };

    var table = try build(test_alloc, topo(&components, &connections), .{});
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.rows.len);
    // in=0 → out=1
    try std.testing.expectEqual(@as(u64, 1), table.rows[0].outputs[0].value);
    try std.testing.expectEqual(@as(u64, 1), table.rows[0].outputs[0].defined);
    // in=1 → out=0
    try std.testing.expectEqual(@as(u64, 0), table.rows[1].outputs[0].value);
    try std.testing.expectEqual(@as(u64, 1), table.rows[1].outputs[0].defined);
}

test "truth_table_build_rejects_too_many_input_bits" {
    // 17 input pins exceeds the default 16 cap.
    var components: [17]FullComponentRecord = undefined;
    inline for (0..17) |idx| {
        components[idx] = .{ .id = idx, .kind = .input_pin, .width = 1, .name = "x", .origin = &.{} };
    }
    // Need at least one output so we don't hit NoOutputs first.
    const all_components = components ++ [_]FullComponentRecord{
        .{ .id = 17, .kind = .output_pin, .width = 1, .name = "out", .origin = &.{} },
    };
    const t = topo(&all_components, &.{});
    try std.testing.expectError(error.TooManyInputs, build(test_alloc, t, .{}));
}

test "truth_table_build_rejects_total_input_bits_above_cap" {
    // One multi-bit input of width 17 — fewer pins than the cap, but more
    // bits — should still trip TooManyInputs at the bit-total check.
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 17, .name = "wide", .origin = &.{} },
        .{ .id = 1, .kind = .output_pin, .width = 17, .name = "out", .origin = &.{} },
    };
    const t = topo(&components, &.{});
    try std.testing.expectError(error.TooManyInputs, build(test_alloc, t, .{}));
}

test "truth_table_build_respects_max_input_bits_override" {
    // Same width-17 input but with an explicit cap of 17 should succeed
    // (well, attempt to build). We don't drive the full 2^17 in a unit
    // test; the cap check is what we're exercising.
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 4, .name = "wide", .origin = &.{} },
        .{ .id = 1, .kind = .output_pin, .width = 4, .name = "out", .origin = &.{} },
    };
    const t = topo(&components, &.{});
    var table = try build(test_alloc, t, .{ .max_input_bits = 4 });
    defer table.deinit();
    try std.testing.expectEqual(@as(usize, 16), table.rows.len);
    try std.testing.expectEqual(@as(u8, 4), table.header.inputs[0].width);
}

test "truth_table_build_rejects_no_outputs" {
    // Inputs only, no outputs.
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "a", .origin = &.{} },
    };
    const t = topo(&components, &.{});
    try std.testing.expectError(error.NoOutputs, build(test_alloc, t, .{}));
}

test "truth_table_build_undefined_for_unconnected_output" {
    // input(0), output(1) but no connection between them. The output_pin has
    // no driver, so its state stays .undefined for every input vector.
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 1, .name = "a", .origin = &.{} },
        .{ .id = 1, .kind = .output_pin, .width = 1, .name = "out", .origin = &.{} },
    };
    const t = topo(&components, &.{});
    var table = try build(test_alloc, t, .{});
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.rows.len);
    try std.testing.expect(table.rows[0].outputs[0].isUndefined());
    try std.testing.expect(table.rows[1].outputs[0].isUndefined());
}

test "truth_table_build_multi_bit_and_gate" {
    // Width-4 AND of two width-4 inputs. 256 rows.
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 4, .name = "a", .origin = &.{} },
        .{ .id = 1, .kind = .input_pin, .width = 4, .name = "b", .origin = &.{} },
        .{ .id = 2, .kind = .and_gate, .width = 4, .name = "g", .origin = &.{} },
        .{ .id = 3, .kind = .output_pin, .width = 4, .name = "r", .origin = &.{} },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 2, .port = @intFromEnum(full_format.PortName.a) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.b) },
        .{ .from_id = 2, .to_id = 3, .port = @intFromEnum(full_format.PortName.in) },
    };
    var table = try build(test_alloc, topo(&components, &connections), .{});
    defer table.deinit();

    try std.testing.expectEqual(@as(u8, 8), table.total_input_bits);
    try std.testing.expectEqual(@as(usize, 256), table.rows.len);
    try std.testing.expectEqual(@as(u8, 4), table.header.inputs[0].width);
    try std.testing.expectEqual(@as(u8, 4), table.header.outputs[0].width);

    // mask=0 (a=0, b=0) -> 0
    try std.testing.expectEqual(@as(u64, 0), table.rows[0].outputs[0].value);
    try std.testing.expectEqual(@as(u64, 0xF), table.rows[0].outputs[0].defined);

    // mask=0x33 means a=0b0011, b=0b0011 -> 0b0011.
    // input_bits is concat: low 4 bits = a, high 4 bits = b. So mask = b<<4 | a.
    // For a=0b0011, b=0b0011: mask = 0b00110011 = 0x33.
    try std.testing.expectEqual(@as(u64, 0b0011), table.rows[0x33].outputs[0].value);

    // mask = b=0b1010, a=0b0110 -> AND = 0b0010.
    // mask bits 0..3 = a (0110), bits 4..7 = b (1010). mask = 0xA6.
    try std.testing.expectEqual(@as(u64, 0b0010), table.rows[0xA6].outputs[0].value);
}

test "truth_table_build_countInputBits_sums_widths" {
    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 4, .name = "a", .origin = &.{} },
        .{ .id = 1, .kind = .input_pin, .width = 2, .name = "b", .origin = &.{} },
        .{ .id = 2, .kind = .input_pin, .width = 1, .name = "c", .origin = &.{} },
        .{ .id = 3, .kind = .output_pin, .width = 4, .name = "r", .origin = &.{} },
    };
    try std.testing.expectEqual(@as(u32, 7), countInputBits(topo(&components, &.{})));
}
