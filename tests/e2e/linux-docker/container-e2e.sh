#!/usr/bin/env bash
# Runs inside the e2e Docker image. Everything the container needs is
# baked in by the Dockerfile — no volume mounts.
set -euxo pipefail

# 3. Confirm no Zig in the runtime image. The whole point of the new
# compile pipeline is that end users do not need Zig installed.
if command -v zig >/dev/null 2>&1; then
  echo "e2e: zig is present in the runtime image — pipeline must be Zig-free" >&2
  zig version >&2 || true
  exit 1
fi
echo "OK: no zig binary in the runtime image"

test -x /usr/local/bin/circ-compile
test -f /test/inverter.circ

mkdir -p /out

echo "--- inspect ---"
inspect_out="$(circ-compile /test/inverter.circ --inspect)"
echo "${inspect_out}" | grep -Fq "=== Parse Tree ==="
echo "${inspect_out}" | grep -Fq "Input a"
echo "${inspect_out}" | grep -Fq "Output out"

echo "--- emit zig ---"
circ-compile /test/inverter.circ --emit-zig -o /out/emitted.zig
test -s /out/emitted.zig
line_count="$(wc -l < /out/emitted.zig | tr -d ' ')"
test "${line_count}" -ge 30

echo "--- wasm ---"
circ-compile /test/inverter.circ -o /out/inverter.wasm
test -s /out/inverter.wasm
node -e 'const fs=require("fs"); const m=Buffer.from([0,0x61,0x73,0x6d]); const b=fs.readFileSync("/out/inverter.wasm"); if (!b.slice(0,4).equals(m)) { console.error("missing wasm magic"); process.exit(1); }'
node -e 'const fs=require("fs"); const b=fs.readFileSync("/out/inverter.wasm"); if (!WebAssembly.validate(b)) { console.error("WebAssembly.validate() failed"); process.exit(1); }'

echo "--- node drive ---"
node /test/drive-inverter.mjs /out/inverter.wasm

echo "--- libcirc ---"
node /test/drive-libcirc.mjs /test/libcirc.wasm /test/inverter.circ

echo "==> container e2e passed"
