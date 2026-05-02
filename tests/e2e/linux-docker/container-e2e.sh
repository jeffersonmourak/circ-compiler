#!/usr/bin/env bash
# Runs inside the e2e Docker image after volumes are mounted:
# - /circ-bin/circ-compile  (Linux x86_64 host-built ELF)
# - /repo                     (checkout, read-only)
# - /out                      (writable temp)
# - /drive-inverter.mjs       (Node harness)
set -euxo pipefail

export PATH="/circ-bin:${PATH}"

test -x /circ-bin/circ-compile
command -v circ-compile >/dev/null

fixture="/repo/tests/fixtures/circuits/inverter.circ"
test -f "${fixture}"

echo "--- inspect ---"
inspect_out="$(circ-compile "${fixture}" --inspect)"
echo "${inspect_out}" | grep -Fq "=== Parse Tree ==="
echo "${inspect_out}" | grep -Fq "Input a"
echo "${inspect_out}" | grep -Fq "Output out"

echo "--- emit zig ---"
circ-compile "${fixture}" --emit-zig -o /out/emitted.zig
test -s /out/emitted.zig
line_count="$(wc -l < /out/emitted.zig | tr -d ' ')"
test "${line_count}" -ge 30

echo "--- wasm ---"
circ-compile "${fixture}" -o /out/inverter.wasm
test -s /out/inverter.wasm
node -e 'const fs=require("fs"); const m=Buffer.from([0,0x61,0x73,0x6d]); const b=fs.readFileSync("/out/inverter.wasm"); if (!b.slice(0,4).equals(m)) { console.error("missing wasm magic"); process.exit(1); }'

echo "--- node drive ---"
node /drive-inverter.mjs /out/inverter.wasm
