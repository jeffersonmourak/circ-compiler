#!/usr/bin/env bash
# Builds circ-compile for Linux, macOS, and Windows, packages each archive
# with LICENSE + README, and copies the archives to site/public/downloads/
# so the static site serves them at /downloads/<file>. Run any time you
# want to refresh the binaries the download page links to.
#
# Usage:   tools/build-dist.sh
# Needs:   zig (0.15.x), tar, zip
#
# Cross-compilation is handled entirely by Zig's bundled libc — no
# platform-specific toolchains required on the host.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOADS="$ROOT/site/public/downloads"
VERSION="$(cat "$ROOT/VERSION")"
STAGE="$(mktemp -d -t circ-dist.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$DOWNLOADS"

build_one() {
  local triple="$1" bin_name="$2" label="$3"
  echo "==> circ-compile-${VERSION}-${label}  (${triple})"

  local out="$STAGE/build-$label"
  zig build circ-compile \
    -Dtarget="$triple" \
    -Doptimize=ReleaseFast \
    --prefix "$out" >/dev/null

  local pkg_name="circ-compile-$VERSION-$label"
  local pkg_dir="$STAGE/pkg/$pkg_name"
  mkdir -p "$pkg_dir"
  cp "$out/bin/$bin_name" "$pkg_dir/"
  cp "$ROOT/LICENSE"      "$pkg_dir/"
  cp "$ROOT/README.md"    "$pkg_dir/"

  local archive
  case "$label" in
    windows-*)
      archive="$DOWNLOADS/$pkg_name.zip"
      rm -f "$archive"
      (cd "$STAGE/pkg" && zip -qr "$archive" "$pkg_name")
      ;;
    *)
      archive="$DOWNLOADS/$pkg_name.tar.gz"
      rm -f "$archive"
      (cd "$STAGE/pkg" && tar -czf "$archive" "$pkg_name")
      ;;
  esac
  printf "    -> %s (%s)\n" "$archive" "$(du -h "$archive" | cut -f1)"
}

build_one x86_64-linux-musl   circ-compile      linux-x86_64
build_one aarch64-macos       circ-compile      macos-aarch64
build_one x86_64-windows-gnu  circ-compile.exe  windows-x86_64

# Plain-text "latest" pointer the install script (site/public/install.sh)
# reads to resolve the current version, kept in lockstep with the archives.
printf '%s\n' "$VERSION" > "$DOWNLOADS/latest"

echo
echo "Done. Archives in $DOWNLOADS:"
ls -lh "$DOWNLOADS"
