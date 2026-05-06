const std = @import("std");

const WASM_MAGIC = "\x00asm";
const WASM_VERSION = "\x01\x00\x00\x00";
const SECTION_ID_CUSTOM: u8 = 0x00;
const SECTION_NAME = "circ.topology.v0.min";
const SECTION_NAME_LEN: u8 = SECTION_NAME.len; // 20, fits in 1 LEB128 byte
const TOPOLOGY_MIN_LEN: usize = 9; // magic(4) + version(1) + comp_count(4)

/// Encodes `value` as an unsigned LEB128 integer into `buf`.
/// Returns the number of bytes written (1–5).
fn writeLeb128(buf: *[5]u8, value: u32) u3 {
    var v = value;
    var i: u3 = 0;
    while (true) {
        const byte: u8 = @intCast(v & 0x7F);
        v >>= 7;
        if (v != 0) {
            buf[i] = byte | 0x80;
        } else {
            buf[i] = byte;
            return i + 1;
        }
        i += 1;
    }
}

/// Appends a `circ.topology.v0.min` custom section to `runtime_wasm` and returns
/// the combined bytes as a newly allocated slice owned by the caller.
///
/// Errors:
///   `error.InvalidRuntimeMagic` — `runtime_wasm` does not begin with the WASM magic + version
///   `error.TopologyTooShort`    — `topology_payload` is shorter than the minimum valid header (9 bytes)
pub fn combine(
    allocator: std.mem.Allocator,
    runtime_wasm: []const u8,
    topology_payload: []const u8,
) ![]u8 {
    if (runtime_wasm.len < 8 or
        !std.mem.eql(u8, runtime_wasm[0..4], WASM_MAGIC) or
        !std.mem.eql(u8, runtime_wasm[4..8], WASM_VERSION))
    {
        return error.InvalidRuntimeMagic;
    }
    if (topology_payload.len < TOPOLOGY_MIN_LEN) return error.TopologyTooShort;

    // section_body = name_len_byte(1) + name(20) + payload
    const section_body_len: u32 = 1 + SECTION_NAME_LEN + @as(u32, @intCast(topology_payload.len));
    var leb_buf: [5]u8 = undefined;
    const leb_len = writeLeb128(&leb_buf, section_body_len);

    const total = runtime_wasm.len + 1 + leb_len + 1 + SECTION_NAME_LEN + topology_payload.len;
    const out = try allocator.alloc(u8, total);

    var pos: usize = 0;
    @memcpy(out[pos..][0..runtime_wasm.len], runtime_wasm);
    pos += runtime_wasm.len;

    out[pos] = SECTION_ID_CUSTOM;
    pos += 1;

    @memcpy(out[pos..][0..leb_len], leb_buf[0..leb_len]);
    pos += leb_len;

    out[pos] = SECTION_NAME_LEN;
    pos += 1;

    @memcpy(out[pos..][0..SECTION_NAME_LEN], SECTION_NAME);
    pos += SECTION_NAME_LEN;

    @memcpy(out[pos..][0..topology_payload.len], topology_payload);

    return out;
}

// --- Tests ---

const testing = std.testing;

test "section_writer: leb128 single byte" {
    var buf: [5]u8 = undefined;
    try testing.expectEqual(@as(u3, 1), writeLeb128(&buf, 0));
    try testing.expectEqual(@as(u8, 0x00), buf[0]);
    try testing.expectEqual(@as(u3, 1), writeLeb128(&buf, 1));
    try testing.expectEqual(@as(u8, 0x01), buf[0]);
    try testing.expectEqual(@as(u3, 1), writeLeb128(&buf, 127));
    try testing.expectEqual(@as(u8, 0x7F), buf[0]);
}

test "section_writer: leb128 multi byte" {
    var buf: [5]u8 = undefined;
    // 128 = 0x80, 0x01
    try testing.expectEqual(@as(u3, 2), writeLeb128(&buf, 128));
    try testing.expectEqualSlices(u8, &.{ 0x80, 0x01 }, buf[0..2]);
    // 16383 = 0xFF, 0x7F
    try testing.expectEqual(@as(u3, 2), writeLeb128(&buf, 16383));
    try testing.expectEqualSlices(u8, &.{ 0xFF, 0x7F }, buf[0..2]);
}

test "section_writer: rejects invalid runtime magic" {
    const bad_runtime = "not_wasm_at_all_here";
    const dummy_payload = "circ" ++ "\x00" ++ "\x00\x00\x00\x00"; // 9 bytes
    try testing.expectError(
        error.InvalidRuntimeMagic,
        combine(testing.allocator, bad_runtime, dummy_payload),
    );
}

test "section_writer: rejects short topology" {
    // A real WASM header for runtime_wasm
    const fake_runtime = WASM_MAGIC ++ WASM_VERSION ++ "some_function_section_bytes";
    const short_payload = "tooshort"; // 8 bytes, below minimum 9
    try testing.expectError(
        error.TopologyTooShort,
        combine(testing.allocator, fake_runtime, short_payload),
    );
}

test "section_writer: runtime bytes are preserved verbatim" {
    const fake_runtime = WASM_MAGIC ++ WASM_VERSION ++ "extra_runtime_bytes_here";
    // 9-byte minimum payload: magic(4) + version(1) + comp_count(4)
    const payload = "circ" ++ "\x00" ++ "\x00\x00\x00\x00";
    const result = try combine(testing.allocator, fake_runtime, payload);
    defer testing.allocator.free(result);
    try testing.expectEqualSlices(u8, fake_runtime, result[0..fake_runtime.len]);
}

test "section_writer: custom section bytes are correct" {
    const fake_runtime = WASM_MAGIC ++ WASM_VERSION;
    // 4-byte payload + 8 padding to hit the 9-byte minimum
    const payload = "circ" ++ "\x00" ++ "\x00\x00\x00\x00";
    const result = try combine(testing.allocator, fake_runtime, payload);
    defer testing.allocator.free(result);

    const section_start = fake_runtime.len;
    // section id
    try testing.expectEqual(@as(u8, 0x00), result[section_start]);
    // section_body_len = 1 + 20 + 9 = 30, fits in single LEB128 byte
    try testing.expectEqual(@as(u8, 30), result[section_start + 1]);
    // name length byte
    try testing.expectEqual(@as(u8, 20), result[section_start + 2]);
    // name
    try testing.expectEqualSlices(u8, SECTION_NAME, result[section_start + 3 ..][0..20]);
    // payload
    try testing.expectEqualSlices(u8, payload, result[section_start + 23 ..]);
}
