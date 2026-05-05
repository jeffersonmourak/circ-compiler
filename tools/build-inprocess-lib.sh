#!/usr/bin/env bash
# Build libinprocess.a (FFI + vendored Zig compiler) and copy to prebuilt/libinprocess.a.
# Extra args are forwarded to `zig build inprocess-lib` (e.g. -Doptimize=ReleaseFast).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
OUT_PREFIX="${TMPDIR:-/tmp}/circ-inprocess-lib-out.$$"
cleanup() { rm -rf "${OUT_PREFIX}"; }
trap cleanup EXIT
mkdir -p prebuilt
zig build inprocess-lib -p "${OUT_PREFIX}" "$@"
cp "${OUT_PREFIX}/lib/libinprocess.a" prebuilt/libinprocess.a
echo "Wrote prebuilt/libinprocess.a (run: zig build circ-compile -Dcirc-prebuilt-inprocess=true)"
