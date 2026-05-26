#!/bin/sh
# circ-compile installer.
#
#   curl -fsSL https://circ-lang.org/install.sh | sh
#
# Downloads a prebuilt circ-compile binary from https://circ-lang.org/downloads
# and installs it. Written in POSIX sh so it runs the same under sh, dash, or
# bash when piped to a shell.
#
# Environment overrides:
#   CIRC_VERSION       version to install (default: the latest released VERSION)
#   CIRC_INSTALL_DIR   install directory (default: $HOME/.local/bin)

set -eu

DOWNLOADS="https://circ-lang.org/downloads"
REPO="https://github.com/jeffersonmourak/circ-compiler"
INSTALL_DIR="${CIRC_INSTALL_DIR:-$HOME/.local/bin}"

say() { printf 'circ-install: %s\n' "$*"; }
die() { printf 'circ-install: error: %s\n' "$*" >&2; exit 1; }

# Pick a downloader.
if command -v curl >/dev/null 2>&1; then
  fetch()    { curl -fsSL "$1"; }
  download() { curl -fsSL -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch()    { wget -qO- "$1"; }
  download() { wget -qO "$2" "$1"; }
else
  die "curl or wget is required"
fi

# Map the platform to a release label (matches tools/build-dist.sh).
os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Linux)
    case "$arch" in
      x86_64 | amd64) label="linux-x86_64" ;;
      *) die "no prebuilt binary for Linux/$arch; build from source: $REPO" ;;
    esac
    ;;
  Darwin)
    case "$arch" in
      arm64 | aarch64) label="macos-aarch64" ;;
      *) die "no prebuilt binary for macOS/$arch (Apple Silicon only); build from source: $REPO" ;;
    esac
    ;;
  *) die "unsupported OS '$os'; build from source: $REPO" ;;
esac

# Resolve the version: explicit override, otherwise the published "latest"
# pointer (written next to the archives by tools/build-dist.sh, so it always
# matches what is actually downloadable).
version="${CIRC_VERSION:-}"
if [ -z "$version" ]; then
  version="$(fetch "$DOWNLOADS/latest" 2>/dev/null | tr -d '[:space:]')" || true
fi
[ -n "$version" ] || die "could not determine the latest version; set CIRC_VERSION=x.y.z"

pkg="circ-compile-$version-$label"
url="$DOWNLOADS/$pkg.tar.gz"
say "installing circ-compile $version ($label)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

download "$url" "$tmp/pkg.tar.gz" || die "download failed: $url"
tar -xzf "$tmp/pkg.tar.gz" -C "$tmp" || die "could not extract $pkg.tar.gz"
[ -f "$tmp/$pkg/circ-compile" ] || die "archive did not contain circ-compile"

mkdir -p "$INSTALL_DIR"
cp "$tmp/$pkg/circ-compile" "$INSTALL_DIR/circ-compile"
chmod 0755 "$INSTALL_DIR/circ-compile"

# macOS: clear the quarantine flag so Gatekeeper does not block the binary.
if [ "$os" = "Darwin" ] && command -v xattr >/dev/null 2>&1; then
  xattr -d com.apple.quarantine "$INSTALL_DIR/circ-compile" >/dev/null 2>&1 || true
fi

say "installed to $INSTALL_DIR/circ-compile"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) say "ready: run 'circ-compile --help'" ;;
  *) say "add it to PATH:  export PATH=\"$INSTALL_DIR:\$PATH\"   (then run 'circ-compile --help')" ;;
esac
