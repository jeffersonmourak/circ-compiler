const std = @import("std");
const protocol = @import("protocol");
const engine_session = @import("engine_session");
const engine = @import("circuit");
const full_format = @import("full_format");
const diagnostics = @import("diagnostics");

const Diagnostic = diagnostics.Diagnostic;

/// Wire-format version. Bump only on a breaking change to the command set,
/// the value encoding, or the framing (see DOCS/sim-protocol.md).
pub const PROTO_VERSION: u32 = 1;

// Re-exports for cmd/circ-compile/main.zig, which imports neither
// engine_session nor circuit; the preload pre-flight reaches everything
// it needs through here.
pub const Preload = engine_session.Preload;
pub const MemRef = engine_session.MemRef;
pub const collectMemories = engine_session.collectMemories;
pub const validateImage = engine_session.validateImage;
pub const MemoryImageError = engine.memimage.MemoryImageError;
/// The codec's errors plus the read cap from `readFileAlloc`.
pub const ImageError = MemoryImageError || error{FileTooBig};
/// Same cap as the CLI's input-file read. The largest legal image is
/// 8 << 16 = 512 KiB, so every over-capacity-but-under-cap file reaches
/// the codec and is reported as TooManyWords.
pub const IMAGE_READ_CAP: usize = 16 * 1024 * 1024;

const MAX_LINE = 8192;

/// One human-readable reason (no code, no newline) for an image `err` on
/// `mem`, given the image length. Shared by `--mem` (stderr) and `load`
/// (E_MEMFMT) so the two surfaces never drift.
pub fn writeImageError(writer: anytype, err: ImageError, mem: MemRef, len: usize) !void {
    const bpw = engine.memimage.bytesPerWord(mem.data_width);
    switch (err) {
        error.LengthNotWordMultiple => try writer.print("length {d} is not a multiple of {d} byte(s)", .{ len, bpw }),
        error.TooManyWords => try writer.print("{d} words exceed capacity {d}", .{ len / bpw, @as(usize, 1) << @intCast(mem.addr_width) }),
        error.WordExceedsWidth => try writer.print("a word has bits set beyond data width {d}", .{mem.data_width}),
        error.FileTooBig => try writer.writeAll("image exceeds 16 MiB"),
    }
}

/// Load every preload into its memory. Names and images were validated by
/// the caller, so a failure here is an internal error, not a user one.
fn applyPreloads(session: *const engine_session.Session, preloads: []const Preload) !void {
    for (preloads) |preload| {
        const mem = session.findMemory(preload.name) orelse return error.UnknownMemory;
        _ = try session.applyImage(mem, preload.bytes);
    }
}

fn widthMask(width: u8) u64 {
    if (width >= 64) return std.math.maxInt(u64);
    return (@as(u64, 1) << @intCast(width)) - 1;
}

fn writeErr(writer: anytype, code: protocol.ErrorCode, msg: []const u8) !void {
    try writer.print("err {s} {s}\n", .{ code.tag(), msg });
}

fn writeErrFmt(writer: anytype, code: protocol.ErrorCode, comptime fmt: []const u8, args: anytype) !void {
    try writer.print("err {s} ", .{code.tag()});
    try writer.print(fmt, args);
    try writer.writeByte('\n');
}

fn writeDiag(writer: anytype, file_path: []const u8, d: Diagnostic) !void {
    const sev = switch (d.level) {
        .err => "error",
        .warning => "warning",
    };
    try writer.print("diag {s} {s} {s}:{d}:{d} {s}\n", .{
        sev,           @tagName(d.code), file_path,
        d.span.start_line, d.span.start_col, d.message,
    });
}

fn writePinList(writer: anytype, session: *const engine_session.Session) !void {
    for (session.inputs) |pin| try writer.print("pin {s} in {d}\n", .{ pin.name, pin.width });
    for (session.outputs) |pin| try writer.print("pin {s} out {d}\n", .{ pin.name, pin.width });
}

/// `ok <value> <defined>` style read: undefined bits and bits beyond the pin
/// width are emitted as 0, matching the engine's BitVecState equality rule.
fn readPin(session: *const engine_session.Session, pin: engine_session.PinRef) struct { value: u64, defined: u64 } {
    const node = session.nodeById(pin.component_id).?;
    const s = session.circuit.readState(node.state_handle);
    const mask = widthMask(pin.width);
    const defined = s.defined & mask;
    return .{ .value = s.value & defined, .defined = defined };
}

/// Failure handshake: the circuit didn't compile, so there's no session to
/// drive. Emit `error diags=<N>` then one `diag` line per hard error.
pub fn serveError(writer: anytype, file_path: []const u8, diags: []const Diagnostic) !void {
    var n: usize = 0;
    for (diags) |d| {
        if (d.level == .err) n += 1;
    }
    try writer.print("error diags={d}\n", .{n});
    for (diags) |d| {
        if (d.level == .err) try writeDiag(writer, file_path, d);
    }
}

/// Build the circuit from `topology`, emit the `ready` handshake, then run the
/// request/response loop until EOF or `quit`. `diags` carries warnings to
/// report in the handshake (the caller has already gated hard errors).
/// `preloads` are applied after the session is built — and again after every
/// `reset`, so "reset" means "back to the configured initial state".
///
/// `set` enqueues-and-settles via `propagateEvent` and `run` calls
/// `propagate`, mirroring the shipped artifact's `setPin`/`run` exports 1:1,
/// so a circuit's behavior under `--sim` matches its compiled `.wasm`.
pub fn serve(
    parent_alloc: std.mem.Allocator,
    topology: full_format.FullTopology,
    file_path: []const u8,
    diags: []const Diagnostic,
    preloads: []const Preload,
    reader: anytype,
    writer: anytype,
) !void {
    var sess_arena = std.heap.ArenaAllocator.init(parent_alloc);
    defer sess_arena.deinit();

    var circuit = engine.Circuit.init() catch return error.InvalidTopology;
    defer circuit.deinit();
    var session = try engine_session.Session.build(sess_arena.allocator(), &circuit, topology);
    try applyPreloads(&session, preloads);

    var warnings: usize = 0;
    for (diags) |d| {
        if (d.level == .warning) warnings += 1;
    }
    try writer.print("ready proto={d} pins={d} warnings={d}\n", .{
        PROTO_VERSION, session.inputs.len + session.outputs.len, warnings,
    });
    try writePinList(writer, &session);
    for (diags) |d| {
        if (d.level == .warning) try writeDiag(writer, file_path, d);
    }

    var scratch = std.heap.ArenaAllocator.init(parent_alloc);
    defer scratch.deinit();

    var line_buf: [MAX_LINE]u8 = undefined;
    while (true) {
        const maybe_line = reader.readUntilDelimiterOrEof(&line_buf, '\n') catch |err| switch (err) {
            error.StreamTooLong => {
                try writeErr(writer, .proto, "command line exceeds limit");
                break;
            },
            else => return err,
        };
        const raw = maybe_line orelse break;

        _ = scratch.reset(.retain_capacity);
        const cmd = protocol.parseLine(scratch.allocator(), raw) catch |err| switch (err) {
            error.Empty => continue,
            error.Malformed => {
                try writeErr(writer, .proto, "malformed command");
                continue;
            },
            error.BadValue => {
                try writeErr(writer, .badval, "invalid integer literal");
                continue;
            },
            error.OutOfMemory => return err,
        };

        switch (cmd) {
            .quit => {
                try writer.writeAll("ok bye\n");
                break;
            },
            .pins => {
                try writer.print("pins {d}\n", .{session.inputs.len + session.outputs.len});
                try writePinList(writer, &session);
            },
            .run => {
                session.circuit.propagate() catch {};
                try writer.writeAll("ok\n");
            },
            .reset => {
                circuit.deinit();
                circuit = engine.Circuit.init() catch return error.InvalidTopology;
                _ = sess_arena.reset(.retain_capacity);
                session = try engine_session.Session.build(sess_arena.allocator(), &circuit, topology);
                try applyPreloads(&session, preloads);
                try writer.writeAll("ok\n");
            },
            .set => |a| try doSet(writer, &session, a),
            .get => |name| try doGet(writer, &session, name),
            .dump => |which| try doDump(writer, &session, which),
            .eval => |e| try doEval(writer, &session, e),
            .mems => try doMems(writer, &session),
            .load => |l| try doLoad(scratch.allocator(), writer, &session, l.mem, l.path),
            .save => |s| try doSave(scratch.allocator(), writer, &session, s.mem, s.path),
            .peek => |p| try doPeek(writer, &session, p),
            .poke => |p| try doPoke(writer, &session, p),
            .mem => |m| try doMemDump(writer, &session, m.mem, m.start, m.count),
            .clear => |name| try doClear(writer, &session, name),
        }
    }
}

// ---------- Memory verbs ----------
// Thin wrappers over the engine hooks; every mutator settles like `set`.
// Paths are whitespace-free tokens resolved against the process cwd, and
// `load`/`save` are the loop's only filesystem access.

fn wordCount(mem: MemRef) u64 {
    return @as(u64, 1) << @intCast(mem.addr_width);
}

/// Resolve a memory name or write `err E_NOMEM <name>` and return null.
fn resolveMem(writer: anytype, session: *const engine_session.Session, name: []const u8) !?MemRef {
    return session.findMemory(name) orelse {
        try writeErr(writer, .nomem, name);
        return null;
    };
}

fn doMems(writer: anytype, session: *const engine_session.Session) !void {
    try writer.print("mems {d}\n", .{session.memories.len});
    for (session.memories) |mem| {
        try writer.print("mem {s} {s} {d} {d}\n", .{ mem.name, @tagName(mem.kind), mem.data_width, mem.addr_width });
    }
}

fn doLoad(scratch: std.mem.Allocator, writer: anytype, session: *const engine_session.Session, name: []const u8, path: []const u8) !void {
    const mem = (try resolveMem(writer, session, name)) orelse return;
    const bytes = std.fs.cwd().readFileAlloc(scratch, path, IMAGE_READ_CAP) catch |err| switch (err) {
        error.FileTooBig => {
            try writer.print("err E_MEMFMT {s}: ", .{path});
            try writeImageError(writer, error.FileTooBig, mem, 0);
            try writer.writeByte('\n');
            return;
        },
        error.OutOfMemory => return err,
        else => {
            try writeErrFmt(writer, .io, "{s}: {s}", .{ path, @errorName(err) });
            return;
        },
    };
    const words = session.applyImage(mem, bytes) catch |err| switch (err) {
        error.LengthNotWordMultiple, error.WordExceedsWidth, error.TooManyWords => |e| {
            try writer.print("err E_MEMFMT {s}: ", .{path});
            try writeImageError(writer, e, mem, bytes.len);
            try writer.writeByte('\n');
            return;
        },
        else => |e| return e,
    };
    try writer.print("ok words={d}\n", .{words});
}

fn doSave(scratch: std.mem.Allocator, writer: anytype, session: *const engine_session.Session, name: []const u8, path: []const u8) !void {
    const mem = (try resolveMem(writer, session, name)) orelse return;
    const node = session.nodeById(mem.component_id).?;
    const buf = try scratch.alloc(u8, engine.memimage.maxImageSize(mem.data_width, mem.addr_width));
    // The buffer is exactly one full image and the node is a memory by
    // construction of MemRef, so the hook cannot fail.
    const written = session.circuit.memoryStoreImage(node, buf) catch unreachable;
    const file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch |err| {
        try writeErrFmt(writer, .io, "{s}: {s}", .{ path, @errorName(err) });
        return;
    };
    defer file.close();
    file.writeAll(buf[0..written]) catch |err| {
        try writeErrFmt(writer, .io, "{s}: {s}", .{ path, @errorName(err) });
        return;
    };
    try writer.print("ok words={d}\n", .{wordCount(mem)});
}

fn writeCell(writer: anytype, session: *const engine_session.Session, mem: MemRef, addr: u64) !void {
    const cells = engine.memoryCells(session.nodeById(mem.component_id).?).?;
    // Planes are canonical (`value & defined`), like readPin's output.
    try protocol.writeHex(writer, cells.values[@intCast(addr)]);
    try writer.writeByte(' ');
    try protocol.writeHex(writer, cells.defined[@intCast(addr)]);
}

fn doPeek(writer: anytype, session: *const engine_session.Session, p: protocol.MemAddr) !void {
    const mem = (try resolveMem(writer, session, p.mem)) orelse return;
    if (p.addr >= wordCount(mem)) {
        try writeErrFmt(writer, .addr, "{s} 0x{x}", .{ p.mem, p.addr });
        return;
    }
    try writer.writeAll("ok ");
    try writeCell(writer, session, mem, p.addr);
    try writer.writeByte('\n');
}

fn doPoke(writer: anytype, session: *const engine_session.Session, p: anytype) !void {
    const mem = (try resolveMem(writer, session, p.mem)) orelse return;
    if (p.addr >= wordCount(mem)) {
        try writeErrFmt(writer, .addr, "{s} 0x{x}", .{ p.mem, p.addr });
        return;
    }
    const full = widthMask(mem.data_width);
    const mask = p.mask orelse full;
    if ((p.value & ~full) != 0 or (mask & ~full) != 0) {
        try writeErr(writer, .width, p.mem);
        return;
    }
    const node = session.nodeById(mem.component_id).?;
    session.circuit.memoryWriteWord(node, @intCast(p.addr), .{ .value = p.value, .defined = mask, .width = mem.data_width }) catch {
        try writeErr(writer, .proto, "write failed");
        return;
    };
    try writer.writeAll("ok\n");
}

fn doMemDump(writer: anytype, session: *const engine_session.Session, name: []const u8, start_opt: ?u64, count_opt: ?u64) !void {
    const mem = (try resolveMem(writer, session, name)) orelse return;
    const total = wordCount(mem);
    const start = start_opt orelse 0;
    if (start >= total) {
        try writeErrFmt(writer, .addr, "{s} 0x{x}", .{ name, start });
        return;
    }
    // A typo'd start is an error above; only the count is clipped.
    const count = @min(count_opt orelse (total - start), total - start);
    try writer.print("cells {d}\n", .{count});
    var addr = start;
    while (addr < start + count) : (addr += 1) {
        try protocol.writeHex(writer, addr);
        try writer.writeByte(' ');
        try writeCell(writer, session, mem, addr);
        try writer.writeByte('\n');
    }
}

fn doClear(writer: anytype, session: *const engine_session.Session, name: []const u8) !void {
    const mem = (try resolveMem(writer, session, name)) orelse return;
    const node = session.nodeById(mem.component_id).?;
    session.circuit.memoryClear(node) catch {
        try writeErr(writer, .proto, "clear failed");
        return;
    };
    try writer.writeAll("ok\n");
}

/// Resolve a `set`/`eval` target to a driveable input and validate its value.
/// Returns the state to drive, or writes the appropriate `err` and returns null.
fn resolveDrive(
    writer: anytype,
    session: *const engine_session.Session,
    a: protocol.Assign,
) !?struct { node: *engine.Component, state: engine.BitVecState } {
    const pin = session.findInput(a.pin) orelse {
        const code: protocol.ErrorCode = if (session.findOutput(a.pin) != null) .notin else .nopin;
        try writeErr(writer, code, a.pin);
        return null;
    };
    const full = widthMask(pin.width);
    const mask = a.mask orelse full;
    if ((a.value & ~full) != 0 or (mask & ~full) != 0) {
        try writeErr(writer, .width, a.pin);
        return null;
    }
    return .{
        .node = session.nodeById(pin.component_id).?,
        .state = .{ .value = a.value, .defined = mask, .width = pin.width },
    };
}

fn doSet(writer: anytype, session: *const engine_session.Session, a: protocol.Assign) !void {
    const drive = (try resolveDrive(writer, session, a)) orelse return;
    session.circuit.propagateEvent(drive.node, drive.state) catch {
        try writeErr(writer, .proto, "drive failed");
        return;
    };
    try writer.writeAll("ok\n");
}

fn doGet(writer: anytype, session: *const engine_session.Session, name: []const u8) !void {
    const pin = session.findOutput(name) orelse session.findInput(name) orelse {
        try writeErr(writer, .nopin, name);
        return;
    };
    const r = readPin(session, pin);
    try writer.writeAll("ok ");
    try protocol.writeHex(writer, r.value);
    try writer.writeByte(' ');
    try protocol.writeHex(writer, r.defined);
    try writer.writeByte('\n');
}

fn doDump(writer: anytype, session: *const engine_session.Session, which: protocol.Which) !void {
    const want_in = which == .in or which == .all;
    const want_out = which == .out or which == .all;
    var n: usize = 0;
    if (want_in) n += session.inputs.len;
    if (want_out) n += session.outputs.len;
    try writer.print("vals {d}\n", .{n});
    if (want_in) for (session.inputs) |pin| try writeVal(writer, session, pin);
    if (want_out) for (session.outputs) |pin| try writeVal(writer, session, pin);
}

fn writeVal(writer: anytype, session: *const engine_session.Session, pin: engine_session.PinRef) !void {
    const r = readPin(session, pin);
    try writer.print("{s} ", .{pin.name});
    try protocol.writeHex(writer, r.value);
    try writer.writeByte(' ');
    try protocol.writeHex(writer, r.defined);
    try writer.writeByte('\n');
}

fn doEval(writer: anytype, session: *const engine_session.Session, e: anytype) !void {
    // Validate everything before mutating state, so a malformed eval is inert.
    for (e.assigns) |a| {
        if ((try resolveDrive(writer, session, a)) == null) return;
    }
    for (e.queries) |qname| {
        if (session.findOutput(qname) == null and session.findInput(qname) == null) {
            try writeErr(writer, .nopin, qname);
            return;
        }
    }
    for (e.assigns) |a| {
        const drive = (try resolveDrive(writer, session, a)).?;
        session.circuit.propagateEvent(drive.node, drive.state) catch {
            try writeErr(writer, .proto, "drive failed");
            return;
        };
    }
    try writer.writeAll("ok");
    for (e.queries) |qname| {
        const pin = session.findOutput(qname) orelse session.findInput(qname).?;
        const r = readPin(session, pin);
        try writer.print(" {s}=", .{qname});
        try protocol.writeHex(writer, r.value);
        try writer.writeByte('/');
        try protocol.writeHex(writer, r.defined);
    }
    try writer.writeByte('\n');
}

// ---------- Tests ----------

const t = std.testing;
const FullComponentRecord = full_format.FullComponentRecord;
const FullConnectionRecord = full_format.FullConnectionRecord;

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

fn runScript(buf: *std.ArrayList(u8), script: []const u8) !void {
    const topology: full_format.FullTopology = .{ .components = &and_components, .connections = &and_connections };
    var fbs = std.io.fixedBufferStream(script);
    try serve(t.allocator, topology, "and.circ", &.{}, &.{}, fbs.reader(), buf.writer(t.allocator));
}

// addr (id=0, input_pin[4]) → rom code[8,4] (id=1) → out (id=2, output_pin[8])
const rom_components = [_]FullComponentRecord{
    .{ .id = 0, .kind = .input_pin, .width = 4, .name = "addr", .origin = &.{} },
    .{ .id = 1, .kind = .rom, .width = 8, .name = "code", .origin = &.{}, .aux = .{ .memory = .{ .addr_width = 4 } } },
    .{ .id = 2, .kind = .output_pin, .width = 8, .name = "out", .origin = &.{} },
};
const rom_connections = [_]FullConnectionRecord{
    .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.addr) },
    .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.in) },
};

fn runRomScript(buf: *std.ArrayList(u8), preloads: []const Preload, script: []const u8) !void {
    const topology: full_format.FullTopology = .{ .components = &rom_components, .connections = &rom_connections };
    var fbs = std.io.fixedBufferStream(script);
    try serve(t.allocator, topology, "rom.circ", &.{}, preloads, fbs.reader(), buf.writer(t.allocator));
}

test "serve: handshake unchanged with memories" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runRomScript(&buf, &.{}, "pins\nquit\n");
    try t.expect(std.mem.startsWith(u8, buf.items, "ready proto=1 pins=2 warnings=0\npin addr in 4\npin out out 8\npins 2\n"));
}

test "serve: preload is visible through the circuit and survives reset" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    const image = [_]u8{ 0x10, 0x20, 0x30, 0x40 };
    try runRomScript(&buf, &.{.{ .name = "code", .bytes = &image }}, "set addr 2\nget out\nreset\nset addr 2\nget out\nset addr 7\nget out\n");
    const out = buf.items;
    try t.expect(std.mem.startsWith(u8, out, "ready proto=1 pins=2 warnings=0\n"));
    // The preloaded word is there, still there after reset, and the tail is undefined.
    try t.expect(std.mem.indexOf(u8, out, "ok 0x30 0xff\nok\nok\nok 0x30 0xff\nok\nok 0x0 0x0\n") != null);
}

// a[4] (0), d[8] (1), we (2), clk (3) → ram data[8,4] (4) → q[8] (5)
const ram_components = [_]FullComponentRecord{
    .{ .id = 0, .kind = .input_pin, .width = 4, .name = "a", .origin = &.{} },
    .{ .id = 1, .kind = .input_pin, .width = 8, .name = "d", .origin = &.{} },
    .{ .id = 2, .kind = .input_pin, .width = 1, .name = "we", .origin = &.{} },
    .{ .id = 3, .kind = .input_pin, .width = 1, .name = "clk", .origin = &.{} },
    .{ .id = 4, .kind = .ram, .width = 8, .name = "data", .origin = &.{}, .aux = .{ .memory = .{ .addr_width = 4 } } },
    .{ .id = 5, .kind = .output_pin, .width = 8, .name = "q", .origin = &.{} },
};
const ram_connections = [_]FullConnectionRecord{
    .{ .from_id = 0, .to_id = 4, .port = @intFromEnum(full_format.PortName.addr) },
    .{ .from_id = 1, .to_id = 4, .port = @intFromEnum(full_format.PortName.din) },
    .{ .from_id = 2, .to_id = 4, .port = @intFromEnum(full_format.PortName.we) },
    .{ .from_id = 3, .to_id = 4, .port = @intFromEnum(full_format.PortName.clk) },
    .{ .from_id = 4, .to_id = 5, .port = @intFromEnum(full_format.PortName.in) },
};

// addr[2] (0) → rom wide[12,2] (1) → out[12] (2): two bytes per word, four words.
const narrow_components = [_]FullComponentRecord{
    .{ .id = 0, .kind = .input_pin, .width = 2, .name = "addr", .origin = &.{} },
    .{ .id = 1, .kind = .rom, .width = 12, .name = "wide", .origin = &.{}, .aux = .{ .memory = .{ .addr_width = 2 } } },
    .{ .id = 2, .kind = .output_pin, .width = 12, .name = "out", .origin = &.{} },
};
const narrow_connections = [_]FullConnectionRecord{
    .{ .from_id = 0, .to_id = 1, .port = @intFromEnum(full_format.PortName.addr) },
    .{ .from_id = 1, .to_id = 2, .port = @intFromEnum(full_format.PortName.in) },
};

fn runTopologyScript(buf: *std.ArrayList(u8), topology: full_format.FullTopology, preloads: []const Preload, script: []const u8) !void {
    var fbs = std.io.fixedBufferStream(script);
    try serve(t.allocator, topology, "mem.circ", &.{}, preloads, fbs.reader(), buf.writer(t.allocator));
}

const ram_topology: full_format.FullTopology = .{ .components = &ram_components, .connections = &ram_connections };
const rom_topology: full_format.FullTopology = .{ .components = &rom_components, .connections = &rom_connections };
const narrow_topology: full_format.FullTopology = .{ .components = &narrow_components, .connections = &narrow_connections };

/// Writes `data` into the test's temp dir and returns a cwd-relative,
/// whitespace-free path a protocol line can carry.
fn tmpImagePath(alloc: std.mem.Allocator, tmp: *std.testing.TmpDir, name: []const u8, data: []const u8) ![]const u8 {
    try tmp.dir.writeFile(.{ .sub_path = name, .data = data });
    return std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path, name });
}

test "serve: mems lists rom and ram" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runTopologyScript(&buf, rom_topology, &.{}, "mems\n");
    try t.expect(std.mem.indexOf(u8, buf.items, "mems 1\nmem code rom 8 4\n") != null);

    buf.clearRetainingCapacity();
    try runTopologyScript(&buf, ram_topology, &.{}, "mems\n");
    try t.expect(std.mem.indexOf(u8, buf.items, "mems 1\nmem data ram 8 4\n") != null);
}

test "serve: load then read through addr, and load refreshes the presented address" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmpImagePath(t.allocator, &tmp, "img.bin", &.{ 0x10, 0x20, 0x30, 0x40 });
    defer t.allocator.free(path);
    const script = try std.fmt.allocPrint(t.allocator, "set addr 1\nload code {s}\nget out\nset addr 7\nget out\n", .{path});
    defer t.allocator.free(script);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runTopologyScript(&buf, rom_topology, &.{}, script);
    // out follows the load with no further set; the unloaded tail reads undefined.
    try t.expect(std.mem.indexOf(u8, buf.items, "ok\nok words=4\nok 0x20 0xff\nok\nok 0x0 0x0\n") != null);
}

test "serve: peek/poke/mem/clear" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runTopologyScript(&buf, rom_topology, &.{},
        \\peek code 2
        \\poke code 2 0xab
        \\peek code 2
        \\set addr 2
        \\get out
        \\poke code 3 0 0
        \\peek code 3
        \\mem code 0 3
        \\mem code
        \\mem code 0xe
        \\mem code 0 0
        \\clear code
        \\get out
        \\
    );
    const out = buf.items;
    try t.expect(std.mem.indexOf(u8, out, "ok 0x0 0x0\nok\nok 0xab 0xff\nok\nok 0xab 0xff\nok\nok 0x0 0x0\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "cells 3\n0x0 0x0 0x0\n0x1 0x0 0x0\n0x2 0xab 0xff\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "cells 16\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "cells 2\n0xe 0x0 0x0\n0xf 0x0 0x0\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "cells 0\nok\nok 0x0 0x0\n") != null);
}

test "serve: save round-trips" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmpImagePath(t.allocator, &tmp, "saved.bin", "");
    defer t.allocator.free(path);
    const script = try std.fmt.allocPrint(t.allocator, "poke code 1 0x5a\npoke code 2 0xff 0x0f\nsave code {s}\nclear code\nload code {s}\npeek code 1\npeek code 2\n", .{ path, path });
    defer t.allocator.free(script);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runTopologyScript(&buf, rom_topology, &.{}, script);
    try t.expect(std.mem.indexOf(u8, buf.items, "ok words=16\nok\nok words=16\nok 0x5a 0xff\nok 0xf 0xff\n") != null);

    const saved = try tmp.dir.readFileAlloc(t.allocator, "saved.bin", 64);
    defer t.allocator.free(saved);
    try t.expectEqual(@as(usize, 16), saved.len);
    try t.expectEqual(@as(u8, 0x5a), saved[1]);
    try t.expectEqual(@as(u8, 0x0f), saved[2]);
    try t.expectEqual(@as(u8, 0x00), saved[3]);
}

test "serve: ram write then peek" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runTopologyScript(&buf, ram_topology, &.{}, "set a 5\nset d 0x2a\nset we 1\nset clk 0\nset clk 1\npeek data 5\nget q\n");
    try t.expect(std.mem.endsWith(u8, buf.items, "ok 0x2a 0xff\nok 0x2a 0xff\n"));
}

test "serve: reset re-applies preloads and drops poke" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    const image = [_]u8{0x11};
    try runTopologyScript(&buf, rom_topology, &.{.{ .name = "code", .bytes = &image }}, "poke code 0 0x22\nreset\npeek code 0\npoke code 9 0x33\nreset\npeek code 9\n");
    try t.expect(std.mem.indexOf(u8, buf.items, "ok\nok\nok 0x11 0xff\nok\nok\nok 0x0 0x0\n") != null);
}

test "serve: memory error replies" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const odd = try tmpImagePath(t.allocator, &tmp, "odd.bin", &.{ 1, 2, 3 });
    defer t.allocator.free(odd);
    const many = try tmpImagePath(t.allocator, &tmp, "many.bin", &([_]u8{0} ** 10));
    defer t.allocator.free(many);
    const wide = try tmpImagePath(t.allocator, &tmp, "wide.bin", &.{ 0xff, 0xff, 0, 0, 0, 0, 0, 0 });
    defer t.allocator.free(wide);
    const script = try std.fmt.allocPrint(t.allocator,
        \\peek addr 0
        \\set wide 1
        \\load wide nope.bin
        \\load wide {s}
        \\load wide {s}
        \\load wide {s}
        \\peek wide 0x4
        \\mem wide 0x4
        \\poke wide 0 0x1000
        \\poke wide 0 1 0x1000
        \\peek wide zz
        \\load wide
        \\
    , .{ odd, many, wide });
    defer t.allocator.free(script);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runTopologyScript(&buf, narrow_topology, &.{}, script);
    const out = buf.items;
    try t.expect(std.mem.indexOf(u8, out, "err E_NOMEM addr\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "err E_NOPIN wide\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "err E_IO nope.bin: FileNotFound\n") != null);
    try t.expect(std.mem.indexOf(u8, out, ": length 3 is not a multiple of 2 byte(s)\n") != null);
    try t.expect(std.mem.indexOf(u8, out, ": 5 words exceed capacity 4\n") != null);
    try t.expect(std.mem.indexOf(u8, out, ": a word has bits set beyond data width 12\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "err E_MEMFMT ") != null);
    try t.expect(std.mem.indexOf(u8, out, "err E_ADDR wide 0x4\nerr E_ADDR wide 0x4\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "err E_WIDTH wide\nerr E_WIDTH wide\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "err E_BADVAL ") != null);
    try t.expect(std.mem.endsWith(u8, out, "err E_PROTO malformed command\n"));
}

// The memory transcript in DOCS/sim-protocol.md, replayed against the rom
// topology: every command line is fed to serve() and every other line must
// come back, in order, as the loop's reply — and the doc must contain the
// block verbatim.
test "serve: doc example session" {
    const transcript =
        \\ready proto=1 pins=2 warnings=0
        \\pin addr in 4
        \\pin out out 8
        \\mems
        \\mems 1
        \\mem code rom 8 4
        \\poke code 3 0x2a
        \\ok
        \\set addr 3
        \\ok
        \\get out
        \\ok 0x2a 0xff
        \\peek code 4
        \\ok 0x0 0x0
        \\mem code 2 3
        \\cells 3
        \\0x2 0x0 0x0
        \\0x3 0x2a 0xff
        \\0x4 0x0 0x0
        \\clear code
        \\ok
        \\get out
        \\ok 0x0 0x0
        \\reset
        \\ok
        \\quit
        \\ok bye
        \\
    ;
    const commands = [_][]const u8{ "mems", "poke code 3 0x2a", "set addr 3", "get out", "peek code 4", "mem code 2 3", "clear code", "get out", "reset", "quit" };

    const doc = try std.fs.cwd().readFileAlloc(t.allocator, "DOCS/sim-protocol.md", 1024 * 1024);
    defer t.allocator.free(doc);
    try t.expect(std.mem.indexOf(u8, doc, transcript) != null);

    var script: std.ArrayList(u8) = .{};
    defer script.deinit(t.allocator);
    for (commands) |c| {
        try script.appendSlice(t.allocator, c);
        try script.append(t.allocator, '\n');
    }
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runTopologyScript(&buf, rom_topology, &.{}, script.items);

    var replies = std.mem.splitScalar(u8, buf.items, '\n');
    var lines = std.mem.splitScalar(u8, transcript, '\n');
    var next_command: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (next_command < commands.len and std.mem.eql(u8, line, commands[next_command])) {
            next_command += 1;
            continue;
        }
        try t.expectEqualStrings(line, replies.next() orelse "<end of output>");
    }
    try t.expectEqual(commands.len, next_command);
    try t.expectEqualStrings("", replies.next() orelse "<end of output>");
}

test "writeImageError reasons" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    const mem = MemRef{ .name = "code", .component_id = 1, .kind = .rom, .data_width = 12, .addr_width = 2 };
    try writeImageError(buf.writer(t.allocator), error.LengthNotWordMultiple, mem, 3);
    try buf.append(t.allocator, '|');
    try writeImageError(buf.writer(t.allocator), error.TooManyWords, mem, 10);
    try buf.append(t.allocator, '|');
    try writeImageError(buf.writer(t.allocator), error.WordExceedsWidth, mem, 8);
    try buf.append(t.allocator, '|');
    try writeImageError(buf.writer(t.allocator), error.FileTooBig, mem, 0);
    try t.expectEqualStrings(
        "length 3 is not a multiple of 2 byte(s)|5 words exceed capacity 4|a word has bits set beyond data width 12|image exceeds 16 MiB",
        buf.items,
    );
}

test "serve: handshake, set/run/get on the AND gate" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runScript(&buf, "set a 1\nset b 1\nrun\nget out\nquit\n");
    const out = buf.items;
    try t.expect(std.mem.startsWith(u8, out, "ready proto=1 pins=3 warnings=0\n"));
    try t.expect(std.mem.indexOf(u8, out, "pin a in 1\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "pin out out 1\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "ok 0x1 0x1\n") != null);
    try t.expect(std.mem.endsWith(u8, out, "ok bye\n"));
}

test "serve: AND of 1 and 0 settles low" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runScript(&buf, "set a 1\nset b 0\nget out\n");
    try t.expect(std.mem.indexOf(u8, buf.items, "ok 0x0 0x1\n") != null);
}

test "serve: eval one-shot vector" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runScript(&buf, "eval a=1 b=1 => out\n");
    try t.expect(std.mem.indexOf(u8, buf.items, "ok out=0x1/0x1\n") != null);
}

test "serve: undefined input propagates to undefined output" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    // a undefined, b high: 1 AND x = x, so out is undefined (defined mask 0).
    try runScript(&buf, "set a 0 0\nset b 1\nget out\n");
    try t.expect(std.mem.indexOf(u8, buf.items, "ok 0x0 0x0\n") != null);
}

test "serve: error replies" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runScript(&buf, "set a 2\nget nope\nset out 1\nbogus\nset a zz\n");
    const out = buf.items;
    try t.expect(std.mem.indexOf(u8, out, "err E_WIDTH a\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "err E_NOPIN nope\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "err E_NOTIN out\n") != null);
    try t.expect(std.mem.indexOf(u8, out, "err E_PROTO ") != null);
    try t.expect(std.mem.indexOf(u8, out, "err E_BADVAL ") != null);
}

test "serve: reset clears state to undefined" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(t.allocator);
    try runScript(&buf, "set a 1\nset b 1\nget out\nreset\nget out\n");
    // First get is high; after reset the AND output is undefined again.
    try t.expect(std.mem.indexOf(u8, buf.items, "ok 0x1 0x1\n") != null);
    try t.expect(std.mem.indexOf(u8, buf.items, "ok 0x0 0x0\n") != null);
}
