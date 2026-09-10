// The two decoders must agree: the committed libcirc.wasm emits the CIRF
// version the pinned circ-renderer reads, and the site's supported list
// names it.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { decodeFullTopology, ComponentKind } from 'circ-renderer';
import { callOp, instantiateLibcirc } from '../src/scripts/libcirc-abi.ts';
import { RENDERER_PIN_VERSION, SUPPORTED_TOPOLOGY_VERSIONS } from '../src/utils/renderer-versions.ts';
import { CircCanvas, CircRuntime, boxOutline, defaultColors, drawLabel, memoryLabel } from 'circ-renderer';
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
    // Phase 2: the typed memory API. Every memory read and write on the site
    // goes through these now, and nothing reaches through `raw` any more.
    for (const method of ['memories', 'memInfo', 'readMemWord', 'writeMemWord', 'loadMemImage', 'storeMemImage', 'clearMem']) {
      expect(`${method}: ${typeof (CircRuntime.prototype as unknown as Record<string, unknown>)[method]}`).toBe(`${method}: function`);
    }
    expect(Object.getOwnPropertyDescriptor(CircRuntime.prototype, 'hasMemory')?.get).toBeDefined();
    // Phase 3: the ring is the canvas's, and the default skins' pieces are
    // exported so the site's own rom/ram/slice/concat skins can be built.
    expect(typeof defaultColors.highlight).toBe('string');
    for (const fn of [boxOutline, drawLabel, memoryLabel]) expect(typeof fn).toBe('function');
    // Phase 4: a theme flip is a redraw, not a rebuild.
    for (const method of ['setTheme', 'setCell', 'setPadding', 'setValueFormat', 'redraw']) {
      expect(`${method}: ${typeof (CircCanvas.prototype as unknown as Record<string, unknown>)[method]}`).toBe(`${method}: function`);
    }
  });

  test('a theme flip changes a live canvas in place, on both pages', () => {
    // A rebuilt canvas is a new instance with empty state: the reader's pins,
    // typed values and loaded memories are gone, and the site used to replay
    // what it could. Neither page may go back to destroying on a theme change.
    const gallery = readFileSync(resolve(import.meta.dir, '..', 'src', 'components', 'LiveCanvas.astro'), 'utf8');
    const playground = readFileSync(resolve(import.meta.dir, '..', 'src', 'components', 'Playground.astro'), 'utf8');
    for (const [name, source] of [['LiveCanvas', gallery], ['Playground', playground]] as const) {
      expect(`${name}: ${/setTheme\(pickTheme\(\)/.test(source)}`).toBe(`${name}: true`);
      expect(`${name}: ${/rebuildAll|rebuildSim/.test(source)}`).toBe(`${name}: false`);
    }
    // The only renderCircuit on each page is the first mount.
    expect([...gallery.matchAll(/renderCircuit\(/g)]).toHaveLength(2); // import + call
    expect([...playground.matchAll(/await renderCircuit\(/g)]).toHaveLength(1);
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
