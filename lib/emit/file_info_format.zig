const std = @import("std");

pub const NamedPin = struct {
    component_id: u32,
    name: []const u8,
};

pub const FileInfo = struct {
    schema_version: u32 = 1,
    file_id: u32,
    source_name: []const u8,
    compile_timestamp: []const u8,
    compiler_version: []const u8,
    component_count: u32,
    connection_count: u32,
    inputs: []const NamedPin,
    outputs: []const NamedPin,
};

pub const DecodedFileInfo = struct {
    schema_version: u32,
    file_id: u32,
    source_name: []const u8,
    compile_timestamp: []const u8,
    compiler_version: []const u8,
    component_count: u32,
    connection_count: u32,
    inputs: []NamedPin,
    outputs: []NamedPin,

    pub fn deinit(self: *DecodedFileInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.source_name);
        allocator.free(self.compile_timestamp);
        allocator.free(self.compiler_version);
        for (self.inputs) |pin| allocator.free(pin.name);
        allocator.free(self.inputs);
        for (self.outputs) |pin| allocator.free(pin.name);
        allocator.free(self.outputs);
    }
};

fn writeU32(writer: anytype, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try writer.writeAll(&buf);
}

fn readU32(reader: anytype) !u32 {
    var buf: [4]u8 = undefined;
    try reader.readNoEof(&buf);
    return std.mem.readInt(u32, &buf, .little);
}

fn writeString(writer: anytype, text: []const u8) !void {
    const len_u32 = std.math.cast(u32, text.len) orelse return error.StringTooLong;
    try writeU32(writer, len_u32);
    try writer.writeAll(text);
}

fn readString(allocator: std.mem.Allocator, reader: anytype) ![]u8 {
    const len = try readU32(reader);
    const out = try allocator.alloc(u8, len);
    errdefer allocator.free(out);
    try reader.readNoEof(out);
    return out;
}

pub fn encodeFileInfo(allocator: std.mem.Allocator, info: FileInfo) ![]u8 {
    var bytes: std.ArrayList(u8) = .{};
    defer bytes.deinit(allocator);
    const writer = bytes.writer(allocator);

    try writeU32(writer, info.schema_version);
    try writeU32(writer, info.file_id);
    try writeU32(writer, info.component_count);
    try writeU32(writer, info.connection_count);
    try writeString(writer, info.source_name);
    try writeString(writer, info.compile_timestamp);
    try writeString(writer, info.compiler_version);

    const input_len_u32 = std.math.cast(u32, info.inputs.len) orelse return error.TooManyPins;
    try writeU32(writer, input_len_u32);
    for (info.inputs) |pin| {
        try writeU32(writer, pin.component_id);
        try writeString(writer, pin.name);
    }

    const output_len_u32 = std.math.cast(u32, info.outputs.len) orelse return error.TooManyPins;
    try writeU32(writer, output_len_u32);
    for (info.outputs) |pin| {
        try writeU32(writer, pin.component_id);
        try writeString(writer, pin.name);
    }

    return bytes.toOwnedSlice(allocator);
}

pub fn decodeFileInfo(allocator: std.mem.Allocator, encoded: []const u8) !DecodedFileInfo {
    var stream = std.io.fixedBufferStream(encoded);
    const reader = stream.reader();

    var decoded = DecodedFileInfo{
        .schema_version = try readU32(reader),
        .file_id = try readU32(reader),
        .component_count = try readU32(reader),
        .connection_count = try readU32(reader),
        .source_name = undefined,
        .compile_timestamp = undefined,
        .compiler_version = undefined,
        .inputs = &.{},
        .outputs = &.{},
    };
    errdefer decoded.deinit(allocator);

    decoded.source_name = try readString(allocator, reader);
    decoded.compile_timestamp = try readString(allocator, reader);
    decoded.compiler_version = try readString(allocator, reader);

    const input_len = try readU32(reader);
    decoded.inputs = try allocator.alloc(NamedPin, input_len);
    for (decoded.inputs, 0..) |*pin, idx| {
        _ = idx;
        pin.component_id = try readU32(reader);
        pin.name = try readString(allocator, reader);
    }

    const output_len = try readU32(reader);
    decoded.outputs = try allocator.alloc(NamedPin, output_len);
    for (decoded.outputs, 0..) |*pin, idx| {
        _ = idx;
        pin.component_id = try readU32(reader);
        pin.name = try readString(allocator, reader);
    }

    if (stream.pos != encoded.len) return error.TrailingBytes;

    return decoded;
}
