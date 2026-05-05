#!/usr/bin/env sh
# Convenience wrapper for `zig build inprocess-lib`.
# Requires ZIG_COMPILER_SRC or pass-through: zig build inprocess-lib -Dzig-compiler-src=...
set -eu
exec zig build inprocess-lib "$@"
