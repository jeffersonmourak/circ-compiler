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
        }
    }
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
