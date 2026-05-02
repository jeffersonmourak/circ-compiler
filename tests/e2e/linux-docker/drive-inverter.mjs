/**
 * Mirrors DOCS/getting-started.md § "4. Drive the compiled `.wasm` from Node".
 * Expects inverter semantics (one input pin id 0, output driver component id 1).
 */
import fs from "node:fs";

const wasmPath = process.argv[2];
if (!wasmPath) {
  console.error("usage: node drive-inverter.mjs <circuit.wasm>");
  process.exit(2);
}

const bytes = fs.readFileSync(wasmPath);
const { instance } = await WebAssembly.instantiate(bytes, {
  env: {
    debugEnabled: () => 0,
    onDebugLog: () => {},
  },
});
const w = instance.exports;

w.init();
try {
  w.setPin(0, 0);
  w.run();
  const hi0 = w.getOutputState(1);
  w.setPin(0, 1);
  w.run();
  const hi1 = w.getOutputState(1);

  console.log("a=0 -> NOT a =", hi0);
  console.log("a=1 -> NOT a =", hi1);

  if (hi0 !== 1 || hi1 !== 0) {
    console.error(`unexpected NOT outputs: wanted 1 then 0, got ${hi0} then ${hi1}`);
    process.exit(1);
  }
} finally {
  w.deinit();
}
