#!/usr/bin/env bash
# Host: Zig + Docker required (Zig only on the host, not in the container).
# Builds circ-compile as a Linux/x86_64 ELF, stages it + tests as a Docker
# build context, builds a Zig-free runtime image, and runs the e2e tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${ROOT}"

if ! command -v docker >/dev/null 2>&1; then
  echo "e2e: docker not found — install Docker and retry" >&2
  exit 1
fi

if ! command -v zig >/dev/null 2>&1; then
  echo "e2e: zig not found on host — Zig 0.15.x required (host only)" >&2
  exit 1
fi

# 1. Compile the binary for Linux BEFORE starting Docker.
echo "==> Host: zig build Linux circ-compile release"
zig build -Doptimize=ReleaseFast "-Dtarget=x86_64-linux-gnu" circ-compile

if [[ ! -x zig-out/bin/circ-compile ]]; then
  echo "e2e: expected executable zig-out/bin/circ-compile" >&2
  exit 1
fi

# 2. Stage the binary + tests into a Docker build context.
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

cp zig-out/bin/circ-compile                       "${STAGE}/circ-compile"
cp tests/fixtures/circuits/inverter.circ          "${STAGE}/inverter.circ"
cp "${SCRIPT_DIR}/drive-inverter.mjs"             "${STAGE}/drive-inverter.mjs"
cp "${SCRIPT_DIR}/container-e2e.sh"               "${STAGE}/container-e2e.sh"
cp "${SCRIPT_DIR}/Dockerfile"                     "${STAGE}/Dockerfile"

DOCKER_PLATFORM_ARGS=()
if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
  DOCKER_PLATFORM_ARGS=(--platform linux/amd64)
fi

echo "==> Docker: build Zig-free runtime image"
docker build "${DOCKER_PLATFORM_ARGS[@]}" \
  -t circ-compiler:e2e-linux \
  "${STAGE}"

# 4. Run the tests (container script asserts step 3: no zig at runtime).
echo "==> Docker: run e2e tests"
docker run "${DOCKER_PLATFORM_ARGS[@]}" --rm \
  circ-compiler:e2e-linux

echo "==> Linux Docker E2E passed"
