const std = @import("std");
const full_format = @import("full_format");

const FullTopology = full_format.FullTopology;
const FullComponentRecord = full_format.FullComponentRecord;
const FullConnectionRecord = full_format.FullConnectionRecord;
const OriginFrame = full_format.OriginFrame;
const ComponentKind = full_format.ComponentKind;

const Cursor = struct {
    bytes: []const u8,
    pos: usize,

    fn remaining(self: Cursor) usize {
        return self.bytes.len - self.pos;
    }

    fn readU8(self: *Cursor) !u8 {
        if (self.remaining() < 1) return error.Truncated;
        const value = self.bytes[self.pos];
        self.pos += 1;
        return value;
    }

    fn readU32LE(self: *Cursor) !u32 {
        if (self.remaining() < 4) return error.Truncated;
        const value = std.mem.readInt(u32, self.bytes[self.pos..][0..4], .little);
        self.pos += 4;
        return value;
    }

    fn readBytes(self: *Cursor, n: usize) ![]const u8 {
        if (self.remaining() < n) return error.Truncated;
        const slice = self.bytes[self.pos..][0..n];
        self.pos += n;
        return slice;
    }
};

fn dupString(allocator: std.mem.Allocator, cursor: *Cursor) ![]u8 {
    const len = try cursor.readU32LE();
    const bytes = try cursor.readBytes(len);
    return allocator.dupe(u8, bytes);
}

pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !FullTopology {
    var cursor = Cursor{ .bytes = bytes, .pos = 0 };

    const magic = try cursor.readBytes(4);
    if (!std.mem.eql(u8, magic, &full_format.FULL_MAGIC)) return error.BadMagic;

    const version = try cursor.readU8();
    if (version != full_format.FULL_VERSION) return error.UnsupportedVersion;

    const num_components = try cursor.readU32LE();
    const components = try allocator.alloc(FullComponentRecord, num_components);
    var components_built: usize = 0;
    errdefer {
        for (components[0..components_built]) |comp| {
            allocator.free(comp.name);
            for (comp.origin) |frame| {
                allocator.free(frame.alias);
                allocator.free(frame.subcircuit);
            }
            allocator.free(comp.origin);
        }
        allocator.free(components);
    }

    for (components) |*comp| {
        const id = try cursor.readU32LE();
        const kind_byte = try cursor.readU8();
        const kind = std.meta.intToEnum(ComponentKind, kind_byte) catch return error.UnknownComponentKind;
        const width = try cursor.readU8();
        const name = try dupString(allocator, &cursor);
        errdefer allocator.free(name);

        const origin_len = try cursor.readU32LE();
        const origin = try allocator.alloc(OriginFrame, origin_len);
        var origin_built: usize = 0;
        errdefer {
            for (origin[0..origin_built]) |frame| {
                allocator.free(frame.alias);
                allocator.free(frame.subcircuit);
            }
            allocator.free(origin);
        }

        for (origin) |*frame| {
            const alias = try dupString(allocator, &cursor);
            errdefer allocator.free(alias);
            const subcircuit = try dupString(allocator, &cursor);
            const target_file = try cursor.readU32LE();
            frame.* = .{ .alias = alias, .subcircuit = subcircuit, .target_file = target_file };
            origin_built += 1;
        }

        comp.* = .{ .id = id, .kind = kind, .width = width, .name = name, .origin = origin };
        components_built += 1;
    }

    const num_connections = try cursor.readU32LE();
    const connections = try allocator.alloc(FullConnectionRecord, num_connections);
    errdefer allocator.free(connections);

    for (connections) |*conn| {
        const from_id = try cursor.readU32LE();
        const to_id = try cursor.readU32LE();
        const port = try cursor.readU8();
        conn.* = .{ .from_id = from_id, .to_id = to_id, .port = port };
    }

    return FullTopology{ .components = components, .connections = connections };
}

test "full_decode_rejects_bad_magic" {
    const allocator = std.testing.allocator;
    const bad = [_]u8{ 'X', 'X', 'X', 'X', 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expectError(error.BadMagic, decode(allocator, &bad));
}

test "full_decode_rejects_unknown_version" {
    const allocator = std.testing.allocator;
    const bad = [_]u8{ 'C', 'I', 'R', 'F', 0x99, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expectError(error.UnsupportedVersion, decode(allocator, &bad));
}

test "full_decode: empty payload round-trips" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{
        'C', 'I', 'R', 'F',
        0x02,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    };
    var topo = try decode(allocator, &bytes);
    defer topo.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), topo.components.len);
    try std.testing.expectEqual(@as(usize, 0), topo.connections.len);
}

test "full_decode_rejects_v01" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 'C', 'I', 'R', 'F', 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expectError(error.UnsupportedVersion, decode(allocator, &bytes));
}

test "full_decode_rejects_truncated_input" {
    const allocator = std.testing.allocator;
    const truncated = [_]u8{ 'C', 'I', 'R', 'F', 0x02 };
    try std.testing.expectError(error.Truncated, decode(allocator, &truncated));
}
