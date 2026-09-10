/**
 * Container-side check for libcirc.wasm: compile the inverter entirely in
 * memory through circ_compile, then drive the resulting artifact with the
 * topology host protocol exactly like drive-inverter.mjs does for the CLI's
 * output. Prints the same two lines and exits non-zero on a wrong answer.
 */
import fs from "node:fs";

const [libPath, circPath] = process.argv.slice(2);
if (!libPath || !circPath) {
  console.error("usage: node drive-libcirc.mjs <libcirc.wasm> <circuit.circ>");
  process.exit(2);
}

const lib = await WebAssembly.instantiate(fs.readFileSync(libPath), {
  env: { debugEnabled: () => 0, onDebugLog: () => {} },
});
const L = lib.instance.exports;
const result = () => Buffer.from(new Uint8Array(L.memory.buffer, L.circ_result_ptr(), L.circ_result_len()));

const req = Buffer.from(
  JSON.stringify({ root: "/p/main.circ", files: { "/p/main.circ": fs.readFileSync(circPath, "utf8") } }),
  "utf8",
);
const ptr = L.circ_alloc(req.length);
new Uint8Array(L.memory.buffer).set(req, ptr);
const status = L.circ_compile(ptr, req.length);
L.circ_free(ptr, req.length);
if (status !== 0) {
  console.error(`circ_compile status ${status}: ${result().toString()}`);
  process.exit(1);
}
const artifact = result();

const mod = await WebAssembly.compile(artifact);
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
const [topoSection] = WebAssembly.Module.customSections(mod, "circ.topology.v0.min");
if (!topoSection) {
  console.error("missing circ.topology.v0.min custom section");
  process.exit(1);
}
const topoBytes = new Uint8Array(topoSection);
const tp = w.topology_alloc(topoBytes.length);
new Uint8Array(w.memory.buffer).set(topoBytes, tp);
w.init();

const readScalar = (id) => (w.getOutputDefined(id) === 0n ? 2 : w.getOutputValue(id) === 0n ? 0 : 1);
w.setPin(0, 0n, 1n);
w.run();
const hi0 = readScalar(1);
w.setPin(0, 1n, 1n);
w.run();
const hi1 = readScalar(1);

console.log("a=0 -> NOT a =", hi0);
console.log("a=1 -> NOT a =", hi1);
if (hi0 !== 1 || hi1 !== 0) {
  console.error(`unexpected NOT outputs: wanted 1 then 0, got ${hi0} then ${hi1}`);
  process.exit(1);
}
