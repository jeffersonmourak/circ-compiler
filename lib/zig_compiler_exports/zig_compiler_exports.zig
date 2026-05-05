//! Module root for embedding the Zig compiler next to `ziglang/zig`'s `src/` tree.
//! Copied to `$ZIG_COMPILER_SRC/src/circ_zig_compiler_exports.zig` on first `zig build inprocess-lib`
//! when that file is missing (`build.zig`).

pub const Compilation = @import("Compilation.zig");
pub const Package = @import("Package.zig");
pub const Type = @import("Type.zig");
pub const Value = @import("Value.zig");
pub const link = @import("link.zig");
pub const introspect = @import("introspect.zig");
pub const target_util = @import("target.zig");
pub const dev = @import("dev.zig");
