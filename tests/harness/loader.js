import fs from "node:fs";

async function main() {
  const wasmPath = process.argv[2];
  const scriptBase64 = process.argv[3];

  if (!wasmPath || !scriptBase64) {
    process.stderr.write("usage: node loader.js <wasm_path> <script_base64>\n");
    process.exit(2);
  }

  const script = Buffer.from(scriptBase64, "base64").toString("utf8");
  const bytes = fs.readFileSync(wasmPath);
  const module = await WebAssembly.instantiate(bytes, {
    env: {
      debugEnabled: () => 0,
      onDebugLog: () => {},
    },
  });
  const wasm = module.instance.exports;

  if (typeof wasm.init === "function") wasm.init();
  try {
    const runScript = new Function("wasm", script);
    runScript(wasm);
  } finally {
    if (typeof wasm.deinit === "function") wasm.deinit();
  }
}

main().catch((err) => {
  process.stderr.write(String(err && err.stack ? err.stack : err));
  process.stderr.write("\n");
  process.exit(1);
});
