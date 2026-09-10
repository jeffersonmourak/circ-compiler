// The two decoders must agree: the committed libcirc.wasm emits the CIRF
// version the pinned circ-renderer reads, and the site's supported list
// names it.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { decodeFullTopology, ComponentKind } from 'circ-renderer';
import { callOp, instantiateLibcirc } from '../src/scripts/libcirc-abi.ts';
import { RENDERER_PIN_VERSION, SUPPORTED_TOPOLOGY_VERSIONS } from '../src/utils/renderer-versions.ts';
import { CircCanvas } from 'circ-renderer';
import { examples } from '../src/content/examples.ts';

const skip = process.env.SKIP_LIBCIRC_TEST === '1';
const wasmPath = resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.wasm');
const manifest = JSON.parse(readFileSync(resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.manifest.json'), 'utf8'));

describe('renderer pin', () => {
  test('the supported list names the manifest version', () => {
    expect(SUPPORTED_TOPOLOGY_VERSIONS).toContain(manifest.full_version);
  });

  test('the installed package is the version the site pins', () => {
    // A `bun add` that rewrote package.json but not the install — or the
    // reverse — is invisible in a diff and fatal at runtime.
    const pkg = JSON.parse(
      readFileSync(resolve(import.meta.dir, '..', 'node_modules', 'circ-renderer', 'package.json'), 'utf8'),
    );
    expect(pkg.version).toBe(RENDERER_PIN_VERSION);
  });

  test('the lockfile and package.json name the same specifier', () => {
    const root = resolve(import.meta.dir, '..');
    const specifier = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'))
      .dependencies['circ-renderer'];
    expect(specifier).toMatch(/^github:jeffersonmourak\/circ-renderer#[0-9a-f]{7,40}$/);
    expect(readFileSync(resolve(root, 'bun.lock'), 'utf8')).toContain(specifier);
  });

  test('the host hooks this site depends on are present', () => {
    // Each phase of the renderer sync adds to this list, and this is the
    // guard: a renderer pinned one phase behind would leave the island
    // silently calling nothing rather than failing here.
    expect(typeof CircCanvas.prototype.setHighlight).toBe('function');
    expect(typeof CircCanvas.prototype.getLayout).toBe('function');
    expect(typeof CircCanvas.prototype.setInputSignal).toBe('function');
    // Phase 1: a bus pin takes a value. The replay goes through setInputValue,
    // and the whole point of the phase is lost if it is not there.
    expect(typeof CircCanvas.prototype.setInputValue).toBe('function');
    expect(typeof CircCanvas.prototype.getInputValue).toBe('function');
    expect(typeof CircCanvas.prototype.boxOf).toBe('function');
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
