#!/usr/bin/env bash
# Host: Zig + Docker required. Builds circ-compile as Linux/x86_64/glibc ELF, then validates
# inspect, emit-zig, wasm, and Node (see drive-inverter.mjs) inside a container.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${ROOT}"

if ! command -v docker >/dev/null 2>&1; then
  echo "e2e: docker not found — install Docker and retry" >&2
  exit 1
fi

if ! command -v zig >/dev/null 2>&1; then
  echo "e2e: zig not found on host — Zig 0.15.x required" >&2
  exit 1
fi

echo "==> Host: prebuilt libinprocess + Linux circ-compile release (fast path)"
bash tools/build-inprocess-lib.sh -Doptimize=ReleaseFast "-Dtarget=x86_64-linux-gnu"
zig build -Doptimize=ReleaseFast "-Dtarget=x86_64-linux-gnu" -Dcirc-prebuilt-inprocess=true circ-compile -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

if [[ ! -x zig-out/bin/circ-compile ]]; then
  echo "e2e: expected executable zig-out/bin/circ-compile" >&2
  exit 1
fi

DOCKER_PLATFORM_ARGS=()
# Linux x86_64 host matches the binary/arch of the Dockerfile toolchain.
if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
  DOCKER_PLATFORM_ARGS=(--platform linux/amd64)
fi

echo "==> Docker: build e2e runner image"
docker build "${DOCKER_PLATFORM_ARGS[@]}" \
  --build-arg ZIG_VERSION=0.15.1 \
  -t circ-compiler:e2e-linux \
  "${SCRIPT_DIR}"

OUT="$(mktemp -d)"
trap 'rm -rf "${OUT}"' EXIT

FIXTURE="${ROOT}/tests/fixtures/circuits/inverter.circ"
if [[ ! -f "${FIXTURE}" ]]; then
  echo "e2e: missing fixture ${FIXTURE}" >&2
  exit 1
fi

echo "==> Docker: inspect / emit-zig / wasm / node"
docker run "${DOCKER_PLATFORM_ARGS[@]}" --rm \
  -v "${ROOT}:/repo:ro" \
  -v "${ROOT}/zig-out/bin:/circ-bin:ro" \
  -v "${OUT}/:/out:rw" \
  -v "${SCRIPT_DIR}/drive-inverter.mjs:/drive-inverter.mjs:ro" \
  -v "${SCRIPT_DIR}/container-e2e.sh:/container-e2e.sh:ro" \
  -e "DEBIAN_FRONTEND=noninteractive" \
  circ-compiler:e2e-linux \
  bash /container-e2e.sh

echo "==> Linux Docker E2E passed"
