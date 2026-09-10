const std = @import("std");
const engine = @import("circuit");
const full_format = @import("full_format");

/// A pin on the root circuit, addressable by its source name. `component_id`
/// is the topology id of the underlying `input_pin`/`output_pin` primitive;
/// `nodeById` maps it to the live engine node.
pub const PinRef = struct {
    name: []const u8,
    component_id: u32,
    width: u8,
};

/// A root-level memory addressable by its declared name. `kind` is the wire
/// kind (`.rom` or `.ram`); the widths come from the `.full` record
/// (`width` = W, `aux.memory.addr_width` = A).
pub const MemRef = struct {
    name: []const u8,
    component_id: u32,
    kind: full_format.ComponentKind,
    data_width: u8,
    addr_width: u8,
};

/// A validated image bound to a memory name, applied after `Session.build`.
/// The bytes are owned by the caller and outlive the session so `reset`
/// can re-apply them.
pub const Preload = struct {
    name: []const u8,
    bytes: []const u8,
};

pub const SessionError = error{
    OutOfMemory,
    InvalidTopology,
};

/// The root-level memories of a topology, in record order. A pure walk
/// (no `Circuit`), shared by `Session.build` and the CLI's preload
/// pre-flight, which must resolve names before any circuit or handshake
/// exists. Memories inside imported/macro sub-circuits (non-empty origin)
/// are not name-addressable, mirroring pins.
pub fn collectMemories(alloc: std.mem.Allocator, topology: full_format.FullTopology) SessionError![]const MemRef {
    var list: std.ArrayList(MemRef) = .{};
    errdefer list.deinit(alloc);
    for (topology.components) |comp| {
        if (comp.origin.len != 0) continue;
        if (comp.kind != .rom and comp.kind != .ram) continue;
        const addr_width = switch (comp.aux) {
            .memory => |m| m.addr_width,
            else => return error.InvalidTopology,
        };
        try list.append(alloc, .{
            .name = comp.name,
            .component_id = comp.id,
            .kind = comp.kind,
            .data_width = comp.width,
            .addr_width = addr_width,
        });
    }
    return list.toOwnedSlice(alloc);
}

/// The codec's errors plus the read cap from `readFileAlloc`.
pub const ImageError = engine.memimage.MemoryImageError || error{FileTooBig};
/// Same cap as the CLI's input-file read. The largest legal image is
/// 8 << 16 = 512 KiB, so every over-capacity-but-under-cap file reaches
/// the codec and is reported as TooManyWords.
pub const IMAGE_READ_CAP: usize = 16 * 1024 * 1024;

/// One human-readable reason (no code, no newline) for an image `err` on
/// `mem`, given the image length. Shared by `--mem` (stderr), `--sim`'s
/// `load` (E_MEMFMT) and the library's truth-table refusal, so the three
/// surfaces never drift.
pub fn writeImageError(writer: anytype, err: ImageError, mem: MemRef, len: usize) !void {
    const bpw = engine.memimage.bytesPerWord(mem.data_width);
    switch (err) {
        error.LengthNotWordMultiple => try writer.print("length {d} is not a multiple of {d} byte(s)", .{ len, bpw }),
        error.TooManyWords => try writer.print("{d} words exceed capacity {d}", .{ len / bpw, @as(usize, 1) << @intCast(mem.addr_width) }),
        error.WordExceedsWidth => try writer.print("a word has bits set beyond data width {d}", .{mem.data_width}),
        error.FileTooBig => try writer.writeAll("image exceeds 16 MiB"),
    }
}

/// Check-only codec entry: the word count a load of `bytes` would produce,
/// or the error `applyImage` would raise. No `Circuit` involved.
pub fn validateImage(mem: MemRef, bytes: []const u8) engine.memimage.MemoryImageError!usize {
    return engine.memimage.validate(bytes, mem.data_width, mem.addr_width);
}

/// A live `engine.Circuit` built from a `FullTopology`, with its root-level
/// input and output pins resolved by name. The truth-table builder enumerates
/// `inputs` exhaustively; `--sim` drives author-supplied vectors against the
/// same construction. Macro-expanded sub-pins (non-empty `origin`) are wired
/// through but are not independently addressable, matching the truth table.
///
/// The caller owns the `engine.Circuit` so it is never moved after its nodes
/// are created; `build` only populates it. `inputs`, `outputs`, and the id→node
/// map are allocated from the caller-supplied allocator.
pub const Session = struct {
    circuit: *engine.Circuit,
    inputs: []const PinRef,
    outputs: []const PinRef,
    /// Root-level memories by declared name; see `collectMemories`.
    memories: []const MemRef,
    id_to_node: std.AutoHashMap(u32, *engine.Component),

    pub fn build(
        alloc: std.mem.Allocator,
        circuit: *engine.Circuit,
        topology: full_format.FullTopology,
    ) SessionError!Session {
        var input_count: usize = 0;
        var output_count: usize = 0;
        for (topology.components) |comp| {
            if (comp.origin.len != 0) continue;
            switch (comp.kind) {
                .input_pin => input_count += 1,
                .output_pin => output_count += 1,
                else => {},
            }
        }

        const inputs = try alloc.alloc(PinRef, input_count);
        const outputs = try alloc.alloc(PinRef, output_count);
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

        var id_to_node = std.AutoHashMap(u32, *engine.Component).init(alloc);
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
                .rom, .ram => blk: {
                    const aux = switch (comp.aux) {
                        .memory => |m| m,
                        else => return error.InvalidTopology,
                    };
                    if (aux.addr_width == 0 or aux.addr_width > engine.MAX_ADDR_WIDTH) return error.InvalidTopology;
                    const mode: engine.MemoryMode = if (comp.kind == .rom) .rom else .ram;
                    break :blk circuit.createComponent(try engine.memoryKind(mode, aux.addr_width), comp.width);
                },
            } catch return error.InvalidTopology;
            node.id = comp.id;
            id_to_node.putAssumeCapacity(comp.id, node);
        }

        for (topology.connections) |conn| {
            const from_node = id_to_node.get(conn.from_id) orelse return error.InvalidTopology;
            const to_node = id_to_node.get(conn.to_id) orelse return error.InvalidTopology;
            // Concat destinations interpret the port byte as an operand index,
            // not a `PortName`; format it back into the `operand_<N>` string the
            // engine's `connect()` expects.
            if (to_node.kind == .concat) {
                var port_buf: [16]u8 = undefined;
                const port_str = std.fmt.bufPrint(&port_buf, "operand_{d}", .{conn.port}) catch return error.InvalidTopology;
                circuit.connect(.{ from_node, "out" }, .{ to_node, port_str }) catch return error.InvalidTopology;
            } else {
                const port_str = portByteToName(conn.port) catch return error.InvalidTopology;
                circuit.connect(.{ from_node, "out" }, .{ to_node, port_str }) catch return error.InvalidTopology;
            }
        }

        return .{
            .circuit = circuit,
            .inputs = inputs,
            .outputs = outputs,
            .memories = try collectMemories(alloc, topology),
            .id_to_node = id_to_node,
        };
    }

    pub fn nodeById(self: *const Session, id: u32) ?*engine.Component {
        return self.id_to_node.get(id);
    }

    pub fn findMemory(self: *const Session, name: []const u8) ?MemRef {
        for (self.memories) |mem| {
            if (std.mem.eql(u8, mem.name, name)) return mem;
        }
        return null;
    }

    /// Replace-all load of a raw image into `mem` through the engine hook;
    /// `out` resyncs and the circuit settles. Returns the words loaded. The
    /// engine's own memory errors cannot occur: a `MemRef` names a memory
    /// by construction, and the codec validates before any plane changes.
    pub fn applyImage(self: *const Session, mem: MemRef, bytes: []const u8) !usize {
        const node = self.nodeById(mem.component_id) orelse return error.InvalidTopology;
        return self.circuit.memoryLoadImage(node, bytes) catch |err| switch (err) {
            error.NotAMemory, error.AddressOutOfRange, error.BufferTooSmall, error.InvalidAddrWidth => unreachable,
            else => |e| return e,
        };
    }

    pub fn findInput(self: *const Session, name: []const u8) ?PinRef {
        for (self.inputs) |pin| {
            if (std.mem.eql(u8, pin.name, name)) return pin;
        }
        return null;
    }

    pub fn findOutput(self: *const Session, name: []const u8) ?PinRef {
        for (self.outputs) |pin| {
            if (std.mem.eql(u8, pin.name, name)) return pin;
        }
        return null;
    }
};

fn portByteToName(port: u8) ![]const u8 {
    const port_name = std.meta.intToEnum(full_format.PortName, port) catch return error.InvalidTopology;
    return switch (port_name) {
        .in => "in",
        .a => "a",
        .b => "b",
        .out => "out",
        .addr => "addr",
        .din => "din",
        .we => "we",
        .clk => "clk",
    };
}

// ---------- Tests ----------

const test_alloc = std.testing.allocator;
const FullComponentRecord = full_format.FullComponentRecord;
const FullConnectionRecord = full_format.FullConnectionRecord;

// a (id=0) → and.a, b (id=1) → and.b, and(id=2) → out(id=3, output_pin)
const and_components = [_]FullComponentRecord{
    .{ .id = 0, .kind = .input_pin, .width = 1, .name = "a", .origin = &.{} },
    .{ .id = 1, .kind = .input_pin, .width = 1, .name = "b", .origin = &.{} },
    .{ .id = 2, .kind = .and_gate, .width = 1, .name = "g", .origin = &.{} },
    .{ .id = 3, .kind = .output_pin, .width = 1, .name = "out", .origin = &.{} },
};
const and_connections = [_]FullConnectionRecord{
    .{ .from_id = 0, .to_id = 2, .port = @intFromEnum(full_format.PortName.a) },
    .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.b) },
    .{ .from_id = 2, .to_id = 3, .port = @intFromEnum(full_format.PortName.in) },
};

test "session resolves root pins by name" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    var session = try Session.build(arena.allocator(), &circuit, .{ .components = &and_components, .connections = &and_connections });

    try std.testing.expectEqual(@as(usize, 2), session.inputs.len);
    try std.testing.expectEqual(@as(usize, 1), session.outputs.len);
    try std.testing.expect(session.findInput("a") != null);
    try std.testing.expect(session.findInput("b") != null);
    try std.testing.expect(session.findInput("missing") == null);
    const out = session.findOutput("out").?;
    try std.testing.expect(session.nodeById(out.component_id) != null);
}

test "session builds rom and ram nodes from memory records" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();

    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .input_pin, .width = 4, .name = "pc", .origin = &.{} },
        .{ .id = 1, .kind = .rom, .width = 8, .name = "code", .origin = &.{}, .aux = .{ .memory = .{ .addr_width = 4 } } },
        .{ .id = 2, .kind = .ram, .width = 8, .name = "data", .origin = &.{}, .aux = .{ .memory = .{ .addr_width = 2 } } },
    };
    const connections = [_]FullConnectionRecord{
        .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.addr) },
        .{ .from_id = 0, .to_id = 2, .port = @intFromEnum(full_format.PortName.addr) },
        .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.din) },
        .{ .from_id = 0, .to_id = 2, .port = @intFromEnum(full_format.PortName.we) },
        .{ .from_id = 0, .to_id = 2, .port = @intFromEnum(full_format.PortName.clk) },
    };
    var session = try Session.build(arena.allocator(), &circuit, .{ .components = &components, .connections = &connections });

    const rom = session.nodeById(1).?;
    const ram = session.nodeById(2).?;
    try std.testing.expect(rom.kind == .memory and rom.kind.memory.mode == .rom);
    try std.testing.expectEqual(@as(u8, 4), rom.kind.memory.cells.addr_width);
    try std.testing.expect(ram.kind.memory.mode == .ram and ram.kind.memory.din == rom);
    try std.testing.expect(ram.kind.memory.clk == session.nodeById(0).?);
}

// addr (id=0, input_pin[4]) → rom code[8,4] (id=1) → out (id=2); a ram data[8,4] (id=3)
// fed by the same pins; a nested rom (id=4) one origin frame deep.
const nested_origin = [_]full_format.OriginFrame{.{ .alias = "inner", .subcircuit = "mem_wrap", .target_file = 1 }};
const memory_components = [_]FullComponentRecord{
    .{ .id = 0, .kind = .input_pin, .width = 4, .name = "addr", .origin = &.{} },
    .{ .id = 1, .kind = .rom, .width = 8, .name = "code", .origin = &.{}, .aux = .{ .memory = .{ .addr_width = 4 } } },
    .{ .id = 2, .kind = .output_pin, .width = 8, .name = "out", .origin = &.{} },
    .{ .id = 3, .kind = .ram, .width = 8, .name = "data", .origin = &.{}, .aux = .{ .memory = .{ .addr_width = 4 } } },
    .{ .id = 4, .kind = .rom, .width = 8, .name = "hidden", .origin = &nested_origin, .aux = .{ .memory = .{ .addr_width = 2 } } },
    .{ .id = 5, .kind = .input_pin, .width = 1, .name = "we", .origin = &.{} },
};
const memory_connections = [_]FullConnectionRecord{
    .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.addr) },
    .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.in) },
    .{ .from_id = 0, .to_id = 3, .port = @intFromEnum(full_format.PortName.addr) },
    .{ .from_id = 1, .to_id = 3, .port = @intFromEnum(full_format.PortName.din) },
    .{ .from_id = 5, .to_id = 3, .port = @intFromEnum(full_format.PortName.we) },
    .{ .from_id = 5, .to_id = 3, .port = @intFromEnum(full_format.PortName.clk) },
    .{ .from_id = 0, .to_id = 4, .port = @intFromEnum(full_format.PortName.addr) },
};

test "session collects root memories" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    var session = try Session.build(arena.allocator(), &circuit, .{ .components = &memory_components, .connections = &memory_connections });

    try std.testing.expectEqual(@as(usize, 2), session.memories.len);
    try std.testing.expectEqualStrings("code", session.memories[0].name);
    const data = session.findMemory("data").?;
    try std.testing.expectEqual(full_format.ComponentKind.ram, data.kind);
    try std.testing.expectEqual(@as(u8, 8), data.data_width);
    try std.testing.expectEqual(@as(u8, 4), data.addr_width);
    try std.testing.expectEqual(@as(u32, 3), data.component_id);
    // A pin name is not a memory name, and a nested memory is not addressable.
    try std.testing.expect(session.findMemory("addr") == null);
    try std.testing.expect(session.findMemory("hidden") == null);
    try std.testing.expect(session.nodeById(4) != null);
}

test "session validateImage matches applyImage" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    var session = try Session.build(arena.allocator(), &circuit, .{ .components = &memory_components, .connections = &memory_connections });
    const code = session.findMemory("code").?;

    const four = [_]u8{ 0x10, 0x20, 0x30, 0x40 };
    try std.testing.expectEqual(@as(usize, 4), try validateImage(code, &four));
    try std.testing.expectEqual(@as(usize, 4), try session.applyImage(code, &four));

    const seventeen = [_]u8{0} ** 17;
    try std.testing.expectError(error.TooManyWords, validateImage(code, &seventeen));
    try std.testing.expectError(error.TooManyWords, session.applyImage(code, &seventeen));

    const wide = MemRef{ .name = "w", .component_id = 0, .kind = .rom, .data_width = 12, .addr_width = 2 };
    try std.testing.expectError(error.LengthNotWordMultiple, validateImage(wide, &.{ 1, 2, 3 }));
}

test "session applyImage short image leaves the tail undefined and resyncs out" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    var session = try Session.build(arena.allocator(), &circuit, .{ .components = &memory_components, .connections = &memory_connections });
    const code = session.findMemory("code").?;
    const addr = session.findInput("addr").?;
    const out = session.findOutput("out").?;

    // Present address 1 first, then load: out follows without another drive.
    try circuit.propagateEvent(session.nodeById(addr.component_id).?, .{ .value = 1, .defined = 0xF, .width = 4 });
    try std.testing.expectEqual(@as(usize, 4), try session.applyImage(code, &.{ 0x10, 0x20, 0x30, 0x40 }));
    const cells = engine.memoryCells(session.nodeById(code.component_id).?).?;
    try std.testing.expectEqual(@as(u64, 0xFF), cells.defined[3]);
    try std.testing.expectEqual(@as(u64, 0), cells.defined[4]);
    const s = circuit.readState(session.nodeById(out.component_id).?.state_handle);
    try std.testing.expectEqual(@as(u64, 0x20), s.value);
    try std.testing.expectEqual(@as(u64, 0xFF), s.defined);
}

test "session rejects a memory record without its aux" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();

    const components = [_]FullComponentRecord{
        .{ .id = 0, .kind = .rom, .width = 8, .name = "code", .origin = &.{} },
    };
    try std.testing.expectError(
        error.InvalidTopology,
        Session.build(arena.allocator(), &circuit, .{ .components = &components, .connections = &.{} }),
    );
}

test "session drives and reads through the engine" {
    var arena = std.heap.ArenaAllocator.init(test_alloc);
    defer arena.deinit();
    var circuit = try engine.Circuit.init();
    defer circuit.deinit();
    var session = try Session.build(arena.allocator(), &circuit, .{ .components = &and_components, .connections = &and_connections });

    const a = session.findInput("a").?;
    const b = session.findInput("b").?;
    const out = session.findOutput("out").?;
    try circuit.propagateEvent(session.nodeById(a.component_id).?, .{ .value = 1, .defined = 1, .width = 1 });
    try circuit.propagateEvent(session.nodeById(b.component_id).?, .{ .value = 1, .defined = 1, .width = 1 });

    const s = circuit.readState(session.nodeById(out.component_id).?.state_handle);
    try std.testing.expectEqual(@as(u64, 1), s.value);
    try std.testing.expectEqual(@as(u64, 1), s.defined);
}

test "writeImageError reasons" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    const mem = MemRef{ .name = "code", .component_id = 1, .kind = .rom, .data_width = 12, .addr_width = 2 };
    try writeImageError(buf.writer(std.testing.allocator), error.LengthNotWordMultiple, mem, 3);
    try buf.append(std.testing.allocator, '|');
    try writeImageError(buf.writer(std.testing.allocator), error.TooManyWords, mem, 10);
    try buf.append(std.testing.allocator, '|');
    try writeImageError(buf.writer(std.testing.allocator), error.WordExceedsWidth, mem, 8);
    try buf.append(std.testing.allocator, '|');
    try writeImageError(buf.writer(std.testing.allocator), error.FileTooBig, mem, 0);
    try std.testing.expectEqualStrings(
        "length 3 is not a multiple of 2 byte(s)|5 words exceed capacity 4|a word has bits set beyond data width 12|image exceeds 16 MiB",
        buf.items,
    );
}
