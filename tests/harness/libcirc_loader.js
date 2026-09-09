// node tests/harness/libcirc_loader.js <libcirc.wasm> <script_base64>
//
// Instantiates libcirc.wasm with the two engine log stubs and runs the
// script with a `circ` helper that owns the alloc/copy/call/read protocol.
// The same helper, verbatim, is what a browser worker implements.
import fs from "node:fs";
import zlib from "node:zlib";

async function main() {
  const wasmPath = process.argv[2];
  const scriptBase64 = process.argv[3];
  if (!wasmPath || !scriptBase64) {
    process.stderr.write("usage: node libcirc_loader.js <libcirc.wasm> <script_base64>\n");
    process.exit(2);
  }

  const script = Buffer.from(scriptBase64, "base64").toString("utf8");
  const bytes = fs.readFileSync(wasmPath);
  const mod = await WebAssembly.compile(bytes);
  const instance = await WebAssembly.instantiate(mod, {
    env: {
      debugEnabled: () => 0,
      onDebugLog: () => {},
    },
  });
  const wasm = instance.exports;

  const circ = {
    bytes,
    exports: () => WebAssembly.Module.exports(mod).map((e) => e.name).sort(),
    imports: () => WebAssembly.Module.imports(mod).map((i) => `${i.module}.${i.name}`).sort(),
    memoryBytes: () => wasm.memory.buffer.byteLength,
    gzipSize: () => zlib.gzipSync(bytes, { level: 9 }).length,
    // Copy out: the buffer is only valid until the next circ_* call, and
    // memory.buffer detaches on every grow, so re-read it for each copy.
    result() {
      const ptr = wasm.circ_result_ptr();
      const len = wasm.circ_result_len();
      return Buffer.from(new Uint8Array(wasm.memory.buffer, ptr, len));
    },
    version() {
      const status = wasm.circ_version();
      return { status, bytes: this.result() };
    },
    reset: () => wasm.circ_reset(),
    // op ∈ analyze | compile | preview | truth_table; request is an object
    // (JSON-encoded here) or a raw string sent as-is.
    call(op, request) {
      const req = Buffer.from(typeof request === "string" ? request : JSON.stringify(request), "utf8");
      const ptr = wasm.circ_alloc(req.length);
      if (ptr === 0) throw new Error("circ_alloc failed");
      if (req.length > 0) new Uint8Array(wasm.memory.buffer).set(req, ptr);
      const status = wasm["circ_" + op](ptr, req.length);
      wasm.circ_free(ptr, req.length);
      return { status, bytes: this.result() };
    },
    // Test protocol: one line per result the Zig side compares.
    emit(name, status, bytes) {
      process.stdout.write(`RESULT ${name} ${status} ${Buffer.from(bytes).toString("base64")}\n`);
    },
  };

  // Scripts may `await` (they instantiate the artifacts they compile).
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  const runScript = new AsyncFunction("circ", "wasm", "mod", "WebAssembly", script);
  await runScript(circ, wasm, mod, WebAssembly);
}

main().catch((err) => {
  process.stderr.write(String(err && err.stack ? err.stack : err));
  process.stderr.write("\n");
  process.exit(1);
});
