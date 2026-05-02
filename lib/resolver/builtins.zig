//! Embedded built-in `.circ` macro sources (Phase 8).
//! Sources live in `builtin_circ/` beside this file so `@embedFile` stays within the module path.
const std = @import("std");

pub const Name = enum {
    or_gate,
    nand,
    nor,
    xor,
    xnor,

    pub fn slice(self: Name) []const u8 {
        return switch (self) {
            .or_gate => "or",
            .nand => "nand",
            .nor => "nor",
            .xor => "xor",
            .xnor => "xnor",
        };
    }

    pub fn fileName(self: Name) []const u8 {
        return switch (self) {
            .or_gate => "or.circ",
            .nand => "nand.circ",
            .nor => "nor.circ",
            .xor => "xor.circ",
            .xnor => "xnor.circ",
        };
    }
};

pub const Entry = struct {
    name: Name,
    source: []const u8,
};

pub const table: []const Entry = &.{
    .{ .name = .or_gate, .source = @embedFile("builtin_circ/or.circ") },
    .{ .name = .nand, .source = @embedFile("builtin_circ/nand.circ") },
    .{ .name = .nor, .source = @embedFile("builtin_circ/nor.circ") },
    .{ .name = .xor, .source = @embedFile("builtin_circ/xor.circ") },
    .{ .name = .xnor, .source = @embedFile("builtin_circ/xnor.circ") },
};

pub fn sourceForName(name: []const u8) ?[]const u8 {
    for (table) |entry| {
        if (std.mem.eql(u8, entry.name.slice(), name)) return entry.source;
    }
    return null;
}

pub fn sourceForPathSuffix(suffix: []const u8) ?[]const u8 {
    for (table) |entry| {
        if (std.mem.eql(u8, entry.name.fileName(), suffix)) return entry.source;
    }
    return null;
}
