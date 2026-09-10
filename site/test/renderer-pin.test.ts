// The two decoders must agree: the committed libcirc.wasm emits the CIRF
// version the pinned circ-renderer reads, and the site's supported list
// names it.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { decodeFullTopology, ComponentKind } from 'circ-renderer';
import { callOp, instantiateLibcirc } from '../src/scripts/libcirc-abi.ts';
import { SUPPORTED_TOPOLOGY_VERSIONS } from '../src/utils/renderer-versions.ts';
import { examples } from '../src/content/examples.ts';

const skip = process.env.SKIP_LIBCIRC_TEST === '1';
const wasmPath = resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.wasm');
const manifest = JSON.parse(readFileSync(resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.manifest.json'), 'utf8'));

describe('renderer pin', () => {
  test('the supported list names the manifest version', () => {
    expect(SUPPORTED_TOPOLOGY_VERSIONS).toContain(manifest.full_version);
  });

  test.skipIf(skip)('the pinned renderer decodes what libcirc.wasm emits', async () => {
    const w = await instantiateLibcirc(readFileSync(wasmPath));
    const out = callOp(w, 'compile', { root: '/playground/main.circ', files: { '/playground/main.circ': examples[0].source } });
    expect(out.status).toBe(0);
    const mod = await WebAssembly.compile(out.bytes);
    const full = new Uint8Array(WebAssembly.Module.customSections(mod, 'circ.topology.v0.full')[0]);
    expect(full[4]).toBe(manifest.full_version);
    const topo = decodeFullTopology(full);
    const kinds = topo.components.map((c) => c.kind);
    expect(kinds).toContain(ComponentKind.InputPin);
    expect(kinds).toContain(ComponentKind.NotGate);
    expect(kinds).toContain(ComponentKind.OutputPin);
  });
});
