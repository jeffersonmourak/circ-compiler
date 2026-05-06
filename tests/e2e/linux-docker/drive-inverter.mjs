/**
 * Mirrors DOCS/getting-started.md § "4. Drive the compiled `.wasm` from Node".
 * The compiled WASM contains a `circ.topology` custom section; the host loads
 * it into linear memory via `topology_alloc(len)` before calling `init()`.
 */
import fs from "node:fs";

const wasmPath = process.argv[2];
if (!wasmPath) {
  console.error("usage: node drive-inverter.mjs <circuit.wasm>");
  process.exit(2);
}

const bytes = fs.readFileSync(wasmPath);
const mod = await WebAssembly.compile(bytes);
const { exports: w } = await WebAssembly.instantiate(mod, {
  env: {
    print: () => {},
    printFmt: () => {},
    flushBuffer: () => {},
    _log: () => {},
    _log_flush: () => {},
    _log_set_name: () => {},
    debugEnabled: () => 0,
    onDebugLog: () => {},
  },
});

// Host protocol: copy the circ.topology custom section into WASM linear memory
// before calling init().
const [topoSection] = WebAssembly.Module.customSections(mod, "circ.topology");
if (!topoSection) {
  console.error("missing circ.topology custom section");
  process.exit(1);
}
const topoBytes = new Uint8Array(topoSection);
const ptr = w.topology_alloc(topoBytes.length);
new Uint8Array(w.memory.buffer).set(topoBytes, ptr);

w.init();

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
