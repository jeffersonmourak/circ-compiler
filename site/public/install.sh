#!/bin/sh
# circ-compile installer.
#
#   curl -fsSL https://circ-lang.org/install.sh | sh
#
# Downloads a prebuilt circ-compile binary from the project's GitHub Releases
# (published automatically for each version tag by the CLI release workflow)
# and installs it. Written in POSIX sh so it runs the same under sh, dash, or
# bash when piped to a shell.
#
# Environment overrides:
#   CIRC_VERSION       version/tag to install, e.g. 0.0.2 or v0.0.2
#                      (default: the latest published release)
#   CIRC_INSTALL_DIR   install directory (default: $HOME/.local/bin)

set -eu

REPO="https://github.com/jeffersonmourak/circ-compiler"
RELEASES="$REPO/releases"
INSTALL_DIR="${CIRC_INSTALL_DIR:-$HOME/.local/bin}"

say() { printf 'circ-install: %s\n' "$*"; }
die() { printf 'circ-install: error: %s\n' "$*" >&2; exit 1; }

# Pick a downloader, and define latest_tag() to match. "Latest" is resolved by
# following GitHub's /releases/latest redirect to /releases/tag/<tag> and taking
# the final path segment -- no API token and no rate-limited API call.
if command -v curl >/dev/null 2>&1; then
  download()   { curl -fsSL -o "$2" "$1"; }
  latest_tag() {
    eff="$(curl -fsSL -o /dev/null -w '%{url_effective}' "$RELEASES/latest")" || return 1
    [ -n "$eff" ] || return 1
    basename "$eff"
  }
elif command -v wget >/dev/null 2>&1; then
  download()   { wget -qO "$2" "$1"; }
  latest_tag() {
    loc="$(wget -S --max-redirect=0 "$RELEASES/latest" 2>&1 \
      | sed -n 's/^[[:space:]]*[Ll]ocation:[[:space:]]*//p' | tr -d '\r' | head -n1)"
    [ -n "$loc" ] || return 1
    basename "$loc"
  }
else
  die "curl or wget is required"
fi

# Map the platform to a release asset label (matches the artifact suffixes the
# CLI release workflow attaches to each GitHub Release).
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

# Resolve the tag: explicit override (accept 0.0.2 or v0.0.2), else the latest
# published release.
tag="${CIRC_VERSION:-}"
if [ -n "$tag" ]; then
  case "$tag" in v*) ;; *) tag="v$tag" ;; esac
else
  tag="$(latest_tag 2>/dev/null || true)"
fi
[ -n "$tag" ] || die "could not determine the latest release; set CIRC_VERSION=x.y.z"

asset="circ-compile-$tag-$label"
url="$RELEASES/download/$tag/$asset"
say "installing circ-compile $tag ($label)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

download "$url" "$tmp/circ-compile" || die "download failed: $url"
[ -s "$tmp/circ-compile" ] || die "downloaded an empty file from $url"

mkdir -p "$INSTALL_DIR"
cp "$tmp/circ-compile" "$INSTALL_DIR/circ-compile"
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
