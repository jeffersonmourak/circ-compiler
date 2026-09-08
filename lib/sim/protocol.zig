const std = @import("std");

/// Stable error codes the `--sim` protocol reports as `err <CODE> <message>`.
/// Versioned alongside `proto=<N>`; treat as an append-only surface.
pub const ErrorCode = enum {
    proto, // unknown or malformed command
    nopin, // no such pin
    notin, // `set` target is not a top-level input
    width, // value or mask has bits beyond the pin's width
    badval, // not a valid integer literal
    nosettle, // `run` hit the iteration cap without settling
    nomem, // no root-level memory of that name
    io, // open/read/write failure on `load`/`save`
    memfmt, // the image violates the raw-image rules
    addr, // address >= 2^A

    pub fn tag(self: ErrorCode) []const u8 {
        return switch (self) {
            .proto => "E_PROTO",
            .nopin => "E_NOPIN",
            .notin => "E_NOTIN",
            .width => "E_WIDTH",
            .badval => "E_BADVAL",
            .nosettle => "E_NOSETTLE",
            .nomem => "E_NOMEM",
            .io => "E_IO",
            .memfmt => "E_MEMFMT",
            .addr => "E_ADDR",
        };
    }
};

/// A `<mem> <addr>` pair for the single-cell verbs.
pub const MemAddr = struct {
    mem: []const u8,
    addr: u64,
};

pub const Which = enum { in, out, all };

/// A `pin=value[/mask]` assignment. `mask == null` means "fully defined",
/// resolved against the pin's width by the drive loop.
pub const Assign = struct {
    pin: []const u8,
    value: u64,
    mask: ?u64,
};

pub const Command = union(enum) {
    pins,
    set: Assign,
    get: []const u8,
    dump: Which,
    run,
    eval: struct {
        assigns: []const Assign,
        queries: []const []const u8,
    },
    reset,
    quit,
    // Memory verbs (proto=1, additive). Paths are whitespace-free tokens.
    mems,
    load: struct { mem: []const u8, path: []const u8 },
    save: struct { mem: []const u8, path: []const u8 },
    peek: MemAddr,
    poke: struct { mem: []const u8, addr: u64, value: u64, mask: ?u64 },
    mem: struct { mem: []const u8, start: ?u64, count: ?u64 },
    clear: []const u8,
};

pub const ParseError = error{
    /// Blank or comment line: the loop skips it and sends no reply.
    Empty,
    /// Unknown verb or wrong argument shape -> `err E_PROTO`.
    Malformed,
    /// A value/mask token is not a valid integer -> `err E_BADVAL`.
    BadValue,
    OutOfMemory,
};

/// Parse an unsigned integer literal. Base is inferred from the prefix:
/// `0x` hex, `0o` octal, `0b` binary, otherwise decimal (`_` separators ok).
pub fn parseValue(text: []const u8) error{BadValue}!u64 {
    return std.fmt.parseInt(u64, text, 0) catch error.BadValue;
}

/// Emit a value in the protocol's canonical form: lowercase hex, `0x`-prefixed.
pub fn writeHex(writer: anytype, value: u64) !void {
    try writer.print("0x{x}", .{value});
}

fn parseWhich(s: []const u8) ?Which {
    if (std.mem.eql(u8, s, "in")) return .in;
    if (std.mem.eql(u8, s, "out")) return .out;
    if (std.mem.eql(u8, s, "all")) return .all;
    return null;
}

/// Parse one request line. `alloc` is only used for `eval`'s variable-length
/// operand lists; every returned slice (and the pin-name slices inside it)
/// borrows from `raw`, so callers must finish using the command before the
/// next line overwrites the buffer.
pub fn parseLine(alloc: std.mem.Allocator, raw: []const u8) ParseError!Command {
    const line = std.mem.trim(u8, raw, " \t\r\n");
    if (line.len == 0 or line[0] == '#') return error.Empty;

    var it = std.mem.tokenizeAny(u8, line, " \t");
    const verb = it.next() orelse return error.Empty;

    if (std.mem.eql(u8, verb, "pins")) return .pins;
    if (std.mem.eql(u8, verb, "run")) return .run;
    if (std.mem.eql(u8, verb, "reset")) return .reset;
    if (std.mem.eql(u8, verb, "quit")) return .quit;

    if (std.mem.eql(u8, verb, "mems")) {
        if (it.next() != null) return error.Malformed;
        return .mems;
    }

    if (std.mem.eql(u8, verb, "load") or std.mem.eql(u8, verb, "save")) {
        const mem = it.next() orelse return error.Malformed;
        const path = it.next() orelse return error.Malformed;
        if (it.next() != null) return error.Malformed;
        if (verb[0] == 'l') return .{ .load = .{ .mem = mem, .path = path } };
        return .{ .save = .{ .mem = mem, .path = path } };
    }

    if (std.mem.eql(u8, verb, "peek")) {
        const mem = it.next() orelse return error.Malformed;
        const addr_str = it.next() orelse return error.Malformed;
        if (it.next() != null) return error.Malformed;
        return .{ .peek = .{ .mem = mem, .addr = try parseValue(addr_str) } };
    }

    if (std.mem.eql(u8, verb, "poke")) {
        const mem = it.next() orelse return error.Malformed;
        const addr_str = it.next() orelse return error.Malformed;
        const value_str = it.next() orelse return error.Malformed;
        const addr = try parseValue(addr_str);
        const value = try parseValue(value_str);
        var mask: ?u64 = null;
        if (it.next()) |mask_str| {
            mask = try parseValue(mask_str);
            if (it.next() != null) return error.Malformed;
        }
        return .{ .poke = .{ .mem = mem, .addr = addr, .value = value, .mask = mask } };
    }

    if (std.mem.eql(u8, verb, "mem")) {
        const mem = it.next() orelse return error.Malformed;
        var start: ?u64 = null;
        var count: ?u64 = null;
        if (it.next()) |start_str| {
            start = try parseValue(start_str);
            if (it.next()) |count_str| {
                count = try parseValue(count_str);
                if (it.next() != null) return error.Malformed;
            }
        }
        return .{ .mem = .{ .mem = mem, .start = start, .count = count } };
    }

    if (std.mem.eql(u8, verb, "clear")) {
        const mem = it.next() orelse return error.Malformed;
        if (it.next() != null) return error.Malformed;
        return .{ .clear = mem };
    }

    if (std.mem.eql(u8, verb, "get")) {
        const pin = it.next() orelse return error.Malformed;
        if (it.next() != null) return error.Malformed;
        return .{ .get = pin };
    }

    if (std.mem.eql(u8, verb, "dump")) {
        const which_str = it.next() orelse return error.Malformed;
        if (it.next() != null) return error.Malformed;
        return .{ .dump = parseWhich(which_str) orelse return error.Malformed };
    }

    if (std.mem.eql(u8, verb, "set")) {
        const pin = it.next() orelse return error.Malformed;
        const value_str = it.next() orelse return error.Malformed;
        const value = try parseValue(value_str);
        var mask: ?u64 = null;
        if (it.next()) |mask_str| {
            mask = try parseValue(mask_str);
            if (it.next() != null) return error.Malformed;
        }
        return .{ .set = .{ .pin = pin, .value = value, .mask = mask } };
    }

    if (std.mem.eql(u8, verb, "eval")) {
        var assigns: std.ArrayList(Assign) = .{};
        errdefer assigns.deinit(alloc);
        var queries: std.ArrayList([]const u8) = .{};
        errdefer queries.deinit(alloc);
        var saw_arrow = false;
        while (it.next()) |tok| {
            if (std.mem.eql(u8, tok, "=>")) {
                if (saw_arrow) return error.Malformed;
                saw_arrow = true;
                continue;
            }
            if (saw_arrow) {
                try queries.append(alloc, tok);
                continue;
            }
            const eq = std.mem.indexOfScalar(u8, tok, '=') orelse return error.Malformed;
            if (eq == 0) return error.Malformed;
            const pin = tok[0..eq];
            const rhs = tok[eq + 1 ..];
            if (rhs.len == 0) return error.Malformed;
            if (std.mem.indexOfScalar(u8, rhs, '/')) |slash| {
                try assigns.append(alloc, .{
                    .pin = pin,
                    .value = try parseValue(rhs[0..slash]),
                    .mask = try parseValue(rhs[slash + 1 ..]),
                });
            } else {
                try assigns.append(alloc, .{ .pin = pin, .value = try parseValue(rhs), .mask = null });
            }
        }
        if (!saw_arrow) return error.Malformed;
        return .{ .eval = .{
            .assigns = try assigns.toOwnedSlice(alloc),
            .queries = try queries.toOwnedSlice(alloc),
        } };
    }

    return error.Malformed;
}

// ---------- Tests ----------

const t = std.testing;

test "parseValue across radixes" {
    try t.expectEqual(@as(u64, 3), try parseValue("3"));
    try t.expectEqual(@as(u64, 31), try parseValue("0x1f"));
    try t.expectEqual(@as(u64, 5), try parseValue("0b101"));
    try t.expectEqual(@as(u64, 15), try parseValue("0o17"));
    try t.expectError(error.BadValue, parseValue("abc"));
    try t.expectError(error.BadValue, parseValue(""));
    try t.expectError(error.BadValue, parseValue("-1"));
}

test "parseLine simple commands" {
    try t.expect(try parseLine(t.allocator, "pins") == .pins);
    try t.expect(try parseLine(t.allocator, "run") == .run);
    try t.expect(try parseLine(t.allocator, "reset") == .reset);
    try t.expect(try parseLine(t.allocator, "quit") == .quit);
    try t.expectError(error.Empty, parseLine(t.allocator, ""));
    try t.expectError(error.Empty, parseLine(t.allocator, "  # a comment"));
    try t.expectError(error.Malformed, parseLine(t.allocator, "bogus"));
}

test "parseLine set with and without mask" {
    const a = try parseLine(t.allocator, "set a 1");
    try t.expectEqualStrings("a", a.set.pin);
    try t.expectEqual(@as(u64, 1), a.set.value);
    try t.expect(a.set.mask == null);

    const b = try parseLine(t.allocator, "set bus 0x5 0xf");
    try t.expectEqualStrings("bus", b.set.pin);
    try t.expectEqual(@as(u64, 5), b.set.value);
    try t.expectEqual(@as(u64, 15), b.set.mask.?);

    try t.expectError(error.Malformed, parseLine(t.allocator, "set a"));
    try t.expectError(error.BadValue, parseLine(t.allocator, "set a zz"));
    try t.expectError(error.Malformed, parseLine(t.allocator, "set a 1 2 3"));
}

test "parseLine get and dump" {
    try t.expectEqualStrings("out", (try parseLine(t.allocator, "get out")).get);
    try t.expectError(error.Malformed, parseLine(t.allocator, "get"));
    try t.expectEqual(Which.all, (try parseLine(t.allocator, "dump all")).dump);
    try t.expectError(error.Malformed, parseLine(t.allocator, "dump sideways"));
}

test "parseLine eval" {
    const cmd = try parseLine(t.allocator, "eval a=3 b=0xf/0xf => out cout");
    defer t.allocator.free(cmd.eval.assigns);
    defer t.allocator.free(cmd.eval.queries);
    try t.expectEqual(@as(usize, 2), cmd.eval.assigns.len);
    try t.expectEqualStrings("a", cmd.eval.assigns[0].pin);
    try t.expectEqual(@as(u64, 3), cmd.eval.assigns[0].value);
    try t.expect(cmd.eval.assigns[0].mask == null);
    try t.expectEqual(@as(u64, 15), cmd.eval.assigns[1].mask.?);
    try t.expectEqual(@as(usize, 2), cmd.eval.queries.len);
    try t.expectEqualStrings("cout", cmd.eval.queries[1]);

    try t.expectError(error.Malformed, parseLine(t.allocator, "eval a=1"));
}

test "parseLine memory verbs" {
    try t.expect(try parseLine(t.allocator, "mems") == .mems);
    try t.expectError(error.Malformed, parseLine(t.allocator, "mems extra"));

    const load = try parseLine(t.allocator, "load code prog.bin");
    try t.expectEqualStrings("code", load.load.mem);
    try t.expectEqualStrings("prog.bin", load.load.path);
    try t.expectError(error.Malformed, parseLine(t.allocator, "load code"));
    try t.expectError(error.Malformed, parseLine(t.allocator, "load code a b"));
    const save = try parseLine(t.allocator, "save data out.bin");
    try t.expectEqualStrings("out.bin", save.save.path);

    const peek = try parseLine(t.allocator, "peek code 0x3");
    try t.expectEqualStrings("code", peek.peek.mem);
    try t.expectEqual(@as(u64, 3), peek.peek.addr);
    try t.expectError(error.BadValue, parseLine(t.allocator, "peek code zz"));
    try t.expectError(error.Malformed, parseLine(t.allocator, "peek code"));

    const poke = try parseLine(t.allocator, "poke code 1 0xab");
    try t.expectEqual(@as(u64, 1), poke.poke.addr);
    try t.expectEqual(@as(u64, 0xab), poke.poke.value);
    try t.expect(poke.poke.mask == null);
    const poke_mask = try parseLine(t.allocator, "poke code 1 0xab 0xf0");
    try t.expectEqual(@as(u64, 0xf0), poke_mask.poke.mask.?);
    try t.expectError(error.Malformed, parseLine(t.allocator, "poke code 1"));
    try t.expectError(error.Malformed, parseLine(t.allocator, "poke code 1 2 3 4"));

    const whole = try parseLine(t.allocator, "mem code");
    try t.expect(whole.mem.start == null and whole.mem.count == null);
    const from = try parseLine(t.allocator, "mem code 4");
    try t.expectEqual(@as(u64, 4), from.mem.start.?);
    try t.expect(from.mem.count == null);
    const range = try parseLine(t.allocator, "mem code 4 2");
    try t.expectEqual(@as(u64, 2), range.mem.count.?);
    try t.expectError(error.Malformed, parseLine(t.allocator, "mem code 1 2 3"));
    try t.expectError(error.Malformed, parseLine(t.allocator, "mem"));

    try t.expectEqualStrings("code", (try parseLine(t.allocator, "clear code")).clear);
    try t.expectError(error.Malformed, parseLine(t.allocator, "clear"));
}

test "tag() for the memory error codes" {
    try t.expectEqualStrings("E_NOMEM", ErrorCode.nomem.tag());
    try t.expectEqualStrings("E_IO", ErrorCode.io.tag());
    try t.expectEqualStrings("E_MEMFMT", ErrorCode.memfmt.tag());
    try t.expectEqualStrings("E_ADDR", ErrorCode.addr.tag());
}

test "writeHex canonical form" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeHex(fbs.writer(), 0);
    try t.expectEqualStrings("0x0", fbs.getWritten());
    fbs.reset();
    try writeHex(fbs.writer(), 31);
    try t.expectEqualStrings("0x1f", fbs.getWritten());
}
