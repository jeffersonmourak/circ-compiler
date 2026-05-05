//! Module root for the zig-compiler vendored module.
//! Lives inside src/ so that relative @import paths resolve against src/.

pub const Compilation = @import("Compilation.zig");
pub const Package = @import("Package.zig");
pub const Type = @import("Type.zig");
pub const Value = @import("Value.zig");
pub const link = @import("link.zig");
pub const introspect = @import("introspect.zig");
pub const target_util = @import("target.zig");
pub const dev = @import("dev.zig");
