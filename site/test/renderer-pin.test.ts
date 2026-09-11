// The two decoders must agree: the committed libcirc.wasm emits the CIRF
// version the pinned circ-renderer reads, and the site's supported list
// names it.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { decodeFullTopology, ComponentKind } from 'circ-renderer';
import { callOp, instantiateLibcirc } from '../src/scripts/libcirc-abi.ts';
import { RENDERER_PIN_VERSION, SUPPORTED_TOPOLOGY_VERSIONS } from '../src/utils/renderer-versions.ts';
import {
  CircCanvas,
  CircRuntime,
  boxOutline,
  defaultColors,
  defaultArcRadius,
  drawLabel,
  memoryLabel,
  traceWire,
  wirePath,
} from 'circ-renderer';
import { ComponentKind as TopologyKind } from 'circ-renderer/topology';
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
    // Phase 5: the wire tracer the site's theme strokes, and the topology-only
    // entry point the eager bundle names its kind bytes from.
    for (const fn of [traceWire, wirePath, defaultArcRadius]) expect(typeof fn).toBe('function');
    expect(TopologyKind).toBe(ComponentKind);
    const pkg = JSON.parse(
      readFileSync(resolve(import.meta.dir, '..', 'node_modules', 'circ-renderer', 'package.json'), 'utf8'),
    ) as { exports: Record<string, string> };
    expect(pkg.exports['./topology']).toBe('./src/wasm/topology.ts');
  });

  test('the value dialog the site styles is the one the installed renderer builds', () => {
    // The site's stylesheet targets the dialog by class name, which is the
    // renderer's documented surface. A rename there would leave the site's
    // rules matching nothing, and the dialog wearing the renderer's defaults.
    const canvas = readFileSync(
      resolve(import.meta.dir, '..', 'node_modules', 'circ-renderer', 'src', 'render', 'canvas.ts'),
      'utf8',
    );
    const css = readFileSync(resolve(import.meta.dir, '..', 'src', 'styles', 'global.css'), 'utf8');
    const styled = new Set([...css.matchAll(/\.circ-pin-editor(?:__[a-z]+)?/g)].map((m) => m[0].slice(1)));
    expect(styled.size).toBeGreaterThan(0);
    // The three buttons are named through one template, `circ-pin-editor__${kind}`.
    const buttons = /circ-pin-editor__\$\{kind\}/.test(canvas)
      ? ['circ-pin-editor__apply', 'circ-pin-editor__clear', 'circ-pin-editor__close']
      : [];
    const emitted = new Set([
      ...[...canvas.matchAll(/"(circ-pin-editor(?:__[a-z]+)?)"/g)].map((m) => m[1]),
      ...buttons,
    ]);
    for (const name of styled) expect(`${name}: ${emitted.has(name)}`).toBe(`${name}: true`);
    // …and the three controls the dialog promises are the ones it builds.
    for (const text of ['"Apply"', '"Clear"', '"Close"']) expect(canvas).toContain(text);
    expect(canvas).toContain('slider.type = "range"');
  });

  test('no kind byte is hand-copied and no view type is restated on the site', () => {
    // Phase 5 deleted the site's copies of the renderer's shapes. A copy that
    // comes back is a number that can drift from the enum, or a type that
    // can fall behind the class it stands in for; the renderer's own are the
    // only ones now, and this is what keeps them the only ones.
    const src = (rel: string) => readFileSync(resolve(import.meta.dir, '..', 'src', rel), 'utf8');
    const playground = src('components/Playground.astro');
    const gallery = src('components/LiveCanvas.astro');
    const sourceLink = src('scripts/source-link.ts');
    const romImage = src('utils/rom-image.ts');
    const skins = src('utils/circ-skins.mjs');
    const palette = src('utils/circ-palette.mjs');
    for (const [name, text] of [['Playground', playground], ['LiveCanvas', gallery]] as const) {
      expect(`${name}: ${/type CircView = \{/.test(text)}`).toBe(`${name}: false`);
      expect(`${name}: ${/renderCircuit\([\s\S]*?\}\)\) as unknown as/.test(text)}`).toBe(`${name}: false`);
      expect(`${name}: ${/pickTheme\(\) as any/.test(text)}`).toBe(`${name}: false`);
      expect(`${name}: ${/import type \{[^}]*\bCircView\b[^}]*\} from 'circ-renderer'/.test(text)}`).toBe(`${name}: true`);
    }
    expect(playground).not.toMatch(/INPUT_PIN = 0/);
    expect(playground).toContain("import { ComponentKind } from 'circ-renderer/topology';");
    expect(sourceLink).toContain("import { ComponentKind } from 'circ-renderer/topology';");
    expect(sourceLink).not.toMatch(/^\s+(input|rom|ram): \d+,$/m);
    expect(romImage).not.toMatch(/ROM_KIND|RAM_KIND/);
    // The theme strokes the renderer's trace and styles a bus as a bus.
    expect(skins).toContain('traceWire(ctx, wire, cell)');
    expect(skins).toContain('wireStyleOf(value)');
    expect((palette.match(/^\s+wireBus: /gm) ?? []).length).toBe(2);
    // …and no longer carries its own copy of the crossing-jump loop.
    expect(skins).not.toMatch(/wire\.crossings/);
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
    // The only renderCircuit call on each page is the first mount. Both pages
    // destructure the import (`const [{ renderCircuit }, ...]`), so the call
    // form is what is counted, not the bare name.
    for (const [name, source] of [['LiveCanvas', gallery], ['Playground', playground]] as const) {
      expect(`${name}: ${[...source.matchAll(/await renderCircuit\(/g)].length}`).toBe(`${name}: 1`);
    }
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
