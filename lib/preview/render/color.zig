const std = @import("std");
const builtin = @import("builtin");

/// User-selectable color mode for `circ-compile preview` output.
pub const ColorMode = enum {
    auto,
    always,
    never,
};

/// Per-component-kind color tag. Resolved to ANSI escape sequences at write-out time.
pub const ColorTag = enum(u8) {
    none = 0,
    input_pin,
    not_gate,
    and_gate,
    led,
    macro,
    wire,
    crossing,
};

/// ANSI escape constants. Kept minimal for slice 1; Phase 3 slice 2's Canvas
/// will pick the right escape per ColorTag at write-out time.
pub const ANSI_RESET: []const u8 = "\x1b[0m";

pub fn ansiFor(tag: ColorTag) []const u8 {
    return switch (tag) {
        .none => "",
        .input_pin => "\x1b[32m", // green
        .not_gate => "\x1b[36m", // cyan
        .and_gate => "\x1b[36m", // cyan
        .led => "\x1b[33m", // yellow
        .macro => "\x1b[35m", // magenta
        .wire => "\x1b[2m", // dim
        .crossing => "\x1b[1m", // bold
    };
}

/// Pure resolution function: given the user's selected mode, an optional stdout
/// file handle, and an optional `NO_COLOR` env-var value, decide whether to emit
/// ANSI color. Caller is responsible for resolving env and TTY detection at the
/// CLI boundary.
///
/// Resolution table:
///   `mode=always` → true regardless of env/TTY (explicit user opt-in beats `NO_COLOR`).
///   `mode=never`  → false always.
///   `mode=auto`   → true iff (stdout_handle is a real handle, treated as TTY) AND no NO_COLOR.
///
/// `stdout_handle == null` is treated as "not a TTY" so tests get deterministic
/// uncolored output without mocking syscalls.
pub fn shouldColor(
    mode: ColorMode,
    stdout_handle: ?std.fs.File.Handle,
    no_color_value: ?[]const u8,
) bool {
    return switch (mode) {
        .always => true,
        .never => false,
        .auto => blk: {
            // No TTY exists on a freestanding target (the wasm library).
            if (comptime builtin.os.tag == .freestanding) break :blk false;
            if (no_color_value != null) break :blk false;
            const handle = stdout_handle orelse break :blk false;
            break :blk std.posix.isatty(handle);
        },
    };
}

// ---------- Tests ----------

test "color_resolution_always_overrides_no_color" {
    // `--color=always` must beat NO_COLOR per the locked precedence rule.
    try std.testing.expect(shouldColor(.always, null, "1"));
    try std.testing.expect(shouldColor(.always, null, ""));
    try std.testing.expect(shouldColor(.always, null, null));
}

test "color_resolution_never_always_off" {
    try std.testing.expect(!shouldColor(.never, null, null));
    try std.testing.expect(!shouldColor(.never, null, "1"));
}

test "color_resolution_auto_no_tty" {
    // Null handle is treated as "not a TTY" — auto resolves to false.
    try std.testing.expect(!shouldColor(.auto, null, null));
}

test "color_resolution_auto_no_color_env" {
    // NO_COLOR set (any value, including empty per no-color.org) suppresses auto.
    try std.testing.expect(!shouldColor(.auto, null, ""));
    try std.testing.expect(!shouldColor(.auto, null, "1"));
}

test "color: ANSI constants present" {
    try std.testing.expect(ANSI_RESET.len > 0);
    try std.testing.expect(ansiFor(.input_pin).len > 0);
    try std.testing.expect(ansiFor(.none).len == 0);
}
