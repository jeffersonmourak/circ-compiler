//! Headerless raw memory image codec.
//!
//! An image is the words of a memory laid out consecutively, each word in
//! `bytesPerWord(W)` little-endian bytes with every bit at or above W clear.
//! There is no magic, header, or length prefix: the declared `[W, A]` is
//! the schema. Definedness is not representable on disk — `encode` writes
//! `value & defined` (undefined bits become 0) and `decode` marks every
//! loaded word fully defined; cells beyond the image are left undefined.
const std = @import("std");

pub const MemoryImageError = error{
    LengthNotWordMultiple,
    WordExceedsWidth,
    TooManyWords,
};

/// `(1 << W) - 1` without shifting a u64 by 64.
fn wordMask(data_width: u8) u64 {
    std.debug.assert(data_width >= 1 and data_width <= 64);
    if (data_width == 64) return std.math.maxInt(u64);
    return (@as(u64, 1) << @intCast(data_width)) - 1;
}

pub fn bytesPerWord(data_width: u8) usize {
    std.debug.assert(data_width >= 1 and data_width <= 64);
    return (@as(usize, data_width) + 7) / 8;
}

/// Size of a full image: one word per cell.
pub fn maxImageSize(data_width: u8, addr_width: u8) usize {
    return bytesPerWord(data_width) << @intCast(addr_width);
}

fn readWord(bytes: []const u8, index: usize, bpw: usize) u64 {
    var word: u64 = 0;
    for (bytes[index * bpw ..][0..bpw], 0..) |byte, k| {
        word |= @as(u64, byte) << @intCast(8 * k);
    }
    return word;
}

fn writeWord(buf: []u8, index: usize, bpw: usize, word: u64) void {
    for (buf[index * bpw ..][0..bpw], 0..) |*byte, k| {
        byte.* = @truncate(word >> @intCast(8 * k));
    }
}

/// Pure check; returns the word count. Checks, in order: the length is a
/// whole number of words, the word count fits the address space, and no
/// word has bits set at or above the data width. Touches no plane.
pub fn validate(bytes: []const u8, data_width: u8, addr_width: u8) MemoryImageError!usize {
    const bpw = bytesPerWord(data_width);
    if (bytes.len % bpw != 0) return error.LengthNotWordMultiple;
    const words = bytes.len / bpw;
    if (words > (@as(usize, 1) << @intCast(addr_width))) return error.TooManyWords;
    const mask = wordMask(data_width);
    var i: usize = 0;
    while (i < words) : (i += 1) {
        if (readWord(bytes, i, bpw) & ~mask != 0) return error.WordExceedsWidth;
    }
    return words;
}

/// Validate, then replace every cell: words `0..n` become the image's
/// values, fully defined; cells `n..` become undefined. A rejected image
/// leaves both planes untouched. Returns `n`.
pub fn decode(
    bytes: []const u8,
    data_width: u8,
    addr_width: u8,
    values: []u64,
    defined: []u64,
) MemoryImageError!usize {
    const cells = @as(usize, 1) << @intCast(addr_width);
    std.debug.assert(values.len == cells and defined.len == cells);
    const words = try validate(bytes, data_width, addr_width);
    const bpw = bytesPerWord(data_width);
    const mask = wordMask(data_width);
    for (values[0..words], defined[0..words], 0..) |*value, *def, i| {
        value.* = readWord(bytes, i, bpw);
        def.* = mask;
    }
    @memset(values[words..], 0);
    @memset(defined[words..], 0);
    return words;
}

/// Writes every cell as `value & defined`, little-endian, into `buf`.
/// Returns the bytes written (`values.len * bytesPerWord(W)`).
pub fn encode(values: []const u64, defined: []const u64, data_width: u8, buf: []u8) usize {
    std.debug.assert(values.len == defined.len);
    const bpw = bytesPerWord(data_width);
    std.debug.assert(buf.len >= values.len * bpw);
    for (values, defined, 0..) |value, def, i| {
        writeWord(buf, i, bpw, value & def);
    }
    return values.len * bpw;
}

// ---------- Tests ----------

test "memimage: bytesPerWord and maxImageSize" {
    try std.testing.expectEqual(@as(usize, 1), bytesPerWord(1));
    try std.testing.expectEqual(@as(usize, 1), bytesPerWord(8));
    try std.testing.expectEqual(@as(usize, 2), bytesPerWord(9));
    try std.testing.expectEqual(@as(usize, 8), bytesPerWord(64));
    try std.testing.expectEqual(@as(usize, 16), maxImageSize(8, 4));
    try std.testing.expectEqual(@as(usize, 8 << 16), maxImageSize(64, 16));
}

test "memimage: round-trip" {
    const src_values = [_]u64{ 0x000, 0x001, 0x7ff, 0x800, 0xabc, 0xfff, 0x123, 0x0f0 };
    const src_defined = [_]u64{0xfff} ** 8;
    var buf: [16]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 16), encode(&src_values, &src_defined, 12, &buf));

    var values: [8]u64 = undefined;
    var defined: [8]u64 = undefined;
    try std.testing.expectEqual(@as(usize, 8), try decode(&buf, 12, 3, &values, &defined));
    try std.testing.expectEqualSlices(u64, &src_values, &values);
    try std.testing.expectEqualSlices(u64, &src_defined, &defined);

    const wide = [_]u64{0xDEADBEEF_CAFEBABE};
    const wide_defined = [_]u64{std.math.maxInt(u64)};
    var wide_buf: [16]u8 = undefined;
    _ = encode(&wide, &wide_defined, 64, wide_buf[0..8]);
    var wide_values: [2]u64 = undefined;
    var wide_def: [2]u64 = undefined;
    try std.testing.expectEqual(@as(usize, 1), try decode(wide_buf[0..8], 64, 1, &wide_values, &wide_def));
    try std.testing.expectEqual(@as(u64, 0xDEADBEEF_CAFEBABE), wide_values[0]);
    try std.testing.expectEqual(@as(u64, 0), wide_def[1]);
}

test "memimage: W=64 has no padding bits" {
    const image = [_]u8{0xff} ** 16;
    var values: [2]u64 = undefined;
    var defined: [2]u64 = undefined;
    try std.testing.expectEqual(@as(usize, 2), try decode(&image, 64, 1, &values, &defined));
    for (values, defined) |v, d| {
        try std.testing.expectEqual(std.math.maxInt(u64), v);
        try std.testing.expectEqual(std.math.maxInt(u64), d);
    }
}

test "memimage: short image leaves tail undefined" {
    const image = [_]u8{ 0x11, 0x22, 0x33 };
    var values = [_]u64{0xaa} ** 8;
    var defined = [_]u64{0xff} ** 8;
    try std.testing.expectEqual(@as(usize, 3), try decode(&image, 8, 3, &values, &defined));
    try std.testing.expectEqualSlices(u64, &.{ 0x11, 0x22, 0x33, 0, 0, 0, 0, 0 }, &values);
    try std.testing.expectEqualSlices(u64, &.{ 0xff, 0xff, 0xff, 0, 0, 0, 0, 0 }, &defined);

    var values2 = [_]u64{0xaa} ** 8;
    var defined2 = [_]u64{0xff} ** 8;
    try std.testing.expectEqual(@as(usize, 0), try decode(&.{}, 8, 3, &values2, &defined2));
    try std.testing.expectEqualSlices(u64, &([_]u64{0} ** 8), &values2);
    try std.testing.expectEqualSlices(u64, &([_]u64{0} ** 8), &defined2);
}

test "memimage: LengthNotWordMultiple leaves planes untouched" {
    const image = [_]u8{ 0x01, 0x02, 0x03 };
    var values = [_]u64{0xaa} ** 4;
    var defined = [_]u64{0xff} ** 4;
    try std.testing.expectError(error.LengthNotWordMultiple, decode(&image, 12, 2, &values, &defined));
    try std.testing.expectEqualSlices(u64, &([_]u64{0xaa} ** 4), &values);
    try std.testing.expectEqualSlices(u64, &([_]u64{0xff} ** 4), &defined);
}

test "memimage: WordExceedsWidth" {
    var values = [_]u64{0xaa} ** 4;
    var defined = [_]u64{0xff} ** 4;
    // W=12: bit 12 set in the second byte.
    try std.testing.expectError(error.WordExceedsWidth, decode(&.{ 0x00, 0x10 }, 12, 2, &values, &defined));
    try std.testing.expectEqualSlices(u64, &([_]u64{0xaa} ** 4), &values);
    // W=8: every byte value is a legal word.
    try std.testing.expectEqual(@as(usize, 2), try validate(&.{ 0xff, 0x80 }, 8, 2));
    // W=1: only bit 0 may be set.
    try std.testing.expectError(error.WordExceedsWidth, validate(&.{0x02}, 1, 2));
    try std.testing.expectEqual(@as(usize, 1), try validate(&.{0x01}, 1, 2));
}

test "memimage: TooManyWords" {
    try std.testing.expectError(error.TooManyWords, validate(&([_]u8{0} ** 5), 8, 2));
    try std.testing.expectEqual(@as(usize, 4), try validate(&([_]u8{0} ** 4), 8, 2));
}

test "memimage: encode writes value & defined" {
    var buf: [2]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2), encode(&.{ 0xff, 0x5a }, &.{ 0x0f, 0xff }, 8, &buf));
    try std.testing.expectEqual(@as(u8, 0x0f), buf[0]);
    try std.testing.expectEqual(@as(u8, 0x5a), buf[1]);
}
