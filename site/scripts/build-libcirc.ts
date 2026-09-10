#!/usr/bin/env bun
//
// Release-time refresh of the browser compiler. Runs `zig build libcirc-wasm`
// in the repo root, copies the module into public/wasm/, sources the
// manifest's identity fields from the binary itself (circ_version()), checks
// the grammar sha against the source tree, measures raw + gzip size, and
// fails when the module is over budget.
//
// Never part of `bun run build`: libcirc.wasm and its manifest are committed
// artifacts, refreshed by hand (`bun run libcirc`) on tagged releases so the
// deploy workflow stays bun-only.

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..');
const built = resolve(repoRoot, 'zig-out', 'lib', 'libcirc.wasm');
const outWasm = resolve(here, '..', 'public', 'wasm', 'libcirc.wasm');
const outManifest = resolve(here, '..', 'public', 'wasm', 'libcirc.manifest.json');
const grammar = resolve(repoRoot, 'lib', 'grammar', 'proto-circ.peg');

// Phase 3's budget (DOCS/libcirc-api.md): 600 KB raw, 200 KB gzip.
const BUDGET = { bytes: 614400, gzip_bytes: 204800 };

console.log('building libcirc.wasm …');
const zig = spawnSync('zig', ['build', 'libcirc-wasm'], { cwd: repoRoot, encoding: 'utf-8' });
if (zig.status !== 0) {
  console.error(zig.stderr || zig.stdout);
  console.error('zig build libcirc-wasm failed');
  process.exit(1);
}
if (!existsSync(built)) {
  console.error(`expected ${built} after zig build libcirc-wasm`);
  process.exit(1);
}
copyFileSync(built, outWasm);
const bytes = readFileSync(outWasm);

// Identity from the binary, so the manifest cannot disagree with it.
const { instance } = await WebAssembly.instantiate(bytes, {
  env: { debugEnabled: () => 0, onDebugLog: () => {} },
});
const w = instance.exports as any;
if (w.circ_version() !== 0) {
  console.error('circ_version() did not return status 0');
  process.exit(1);
}
const versionJson = Buffer.from(
  new Uint8Array(w.memory.buffer, w.circ_result_ptr(), w.circ_result_len()),
).toString('utf8');
const version = JSON.parse(versionJson) as Record<string, unknown>;

const grammarSha = createHash('sha256').update(readFileSync(grammar)).digest('hex');
if (version.grammar_sha256 !== grammarSha) {
  console.error(`grammar sha mismatch: binary ${version.grammar_sha256}, tree ${grammarSha}`);
  process.exit(1);
}

const gzipBytes = Bun.gzipSync(bytes, { level: 9 }).length;
const manifest = {
  version: version.version,
  revision: version.revision,
  topology_version: version.topology_version,
  full_version: version.full_version,
  parser: version.parser,
  parser_runtime_sha256: version.parser_runtime_sha256,
  grammar_sha256: version.grammar_sha256,
  bytes: bytes.length,
  gzip_bytes: gzipBytes,
  budget: BUDGET,
};
writeFileSync(outManifest, JSON.stringify(manifest, null, 2) + '\n');

console.log(
  `libcirc.wasm: ${bytes.length} B raw, ${gzipBytes} B gzip (budget ${BUDGET.bytes}/${BUDGET.gzip_bytes})`,
);
if (bytes.length > BUDGET.bytes || gzipBytes > BUDGET.gzip_bytes) {
  console.error(
    `libcirc.wasm is ${bytes.length} bytes (${gzipBytes} gzip), over the ${BUDGET.bytes}/${BUDGET.gzip_bytes} byte budget`,
  );
  process.exit(1);
}
console.log(`wrote ${outWasm} and ${outManifest}`);
