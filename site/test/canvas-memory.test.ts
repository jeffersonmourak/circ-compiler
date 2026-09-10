// Loading a gallery card's memory images into its own compiled artifact.
//
// A card has no compiler and no analysis, so the shape every image is checked
// against is read back out of the `.wasm` through `getMemInfo`. These tests
// drive the committed artifacts rather than a stand-in: the claim is that the
// bytes shipped in `examples.ts` are ones the runtime accepts, and only the
// runtime can settle that.
import { describe, expect, test } from 'bun:test';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadMemoryImages, memoriesOf, readMemoryAttr } from '../src/scripts/canvas-memory.ts';
import { examples } from '../src/content/examples.ts';

const WASM = resolve(import.meta.dir, '..', 'public', 'wasm');

/** Instantiate an artifact and build the topology view the renderer would
 *  hand the canvas — component id, kind and name, which is all the join needs. */
async function boot(file: string) {
  const bytes = readFileSync(resolve(WASM, file));
  const mod = await WebAssembly.compile(bytes as unknown as BufferSource);
  const { exports } = await WebAssembly.instantiate(mod, {
    env: { debugEnabled: () => 0, onDebugLog: () => {} },
  });
  const host = exports as unknown as Record<string, unknown> & { memory: { buffer: ArrayBufferLike } };
  const [section] = WebAssembly.Module.customSections(mod, 'circ.topology.v0.min');
  const topo = new Uint8Array(section);
  const ptr = (host.topology_alloc as (n: number) => number)(topo.length);
  new Uint8Array(host.memory.buffer).set(topo, ptr);
  (host.init as () => void)();

  // The renderer decodes the full section; everything here needs is the id,
  // the kind byte and the name, which `getMemInfo` can confirm one by one.
  const components: { id: number; kind: number; name: string; origin: never[] }[] = [];
  for (let id = 0; id < 256; id += 1) {
    const info = (host.getMemInfo as (i: number) => number)(id);
    if (info < 0) continue;
    components.push({ id, kind: (info >> 16) & 0xff, name: nameOf(file), origin: [] });
  }
  const read = (id: number, addr: number) => ({
    value: BigInt((host.getMemValue as (i: number, a: number) => bigint)(id, addr)),
    defined: BigInt((host.getMemDefined as (i: number, a: number) => bigint)(id, addr)),
  });
  return { host, topology: { components }, read };
}

/** The declared name each shipped artifact uses for its single memory. */
function nameOf(file: string): string {
  const slug = file.replace(/\.wasm$/, '');
  const entry = examples.find((e) => e.wasm === file);
  const names = Object.keys(entry?.memory ?? {});
  if (names.length !== 1) throw new Error(`${slug} does not declare exactly one memory image`);
  return names[0];
}

const withMemory = examples.filter((e) => e.memory && Object.keys(e.memory).length > 0);

describe('the shipped images', () => {
  test('exactly the two memory examples carry one', () => {
    expect(withMemory.map((e) => e.slug).sort()).toEqual(['ram-write-read', 'rom-lookup']);
    // A card with no memory must not carry images for one it does not have.
    for (const e of examples) {
      if (e.memory) expect(e.wasm).toBeTruthy();
    }
  });

  test('every image is hex bytes and nothing else', () => {
    for (const e of withMemory) {
      for (const [name, hex] of Object.entries(e.memory!)) {
        expect(`${e.slug}/${name}: ${/^[0-9a-f]*$/.test(hex)}`).toBe(`${e.slug}/${name}: true`);
        expect(hex.length % 2).toBe(0);
      }
    }
  });
});

describe('memoriesOf', () => {
  test('reads the shape from the artifact, not from anything beside it', async () => {
    const { host, topology } = await boot('rom-lookup.wasm');
    const found = memoriesOf(topology, host);
    expect([...found.keys()]).toEqual(['code']);
    expect(found.get('code')!.mem).toEqual({ name: 'code', kind: 'rom', width: 8, addrWidth: 4 });
  });

  test('a ram is reported as a ram', async () => {
    const { host, topology } = await boot('ram-write-read.wasm');
    expect(memoriesOf(topology, host).get('data')!.mem.kind).toBe('ram');
  });

  test('a host with no memory support yields nothing rather than throwing', () => {
    expect(memoriesOf({ components: [{ id: 0, kind: 8, name: 'x', origin: [] }] }, {}).size).toBe(0);
  });

  test('a box from inside a macro is not addressable and is skipped', async () => {
    const { host, topology } = await boot('rom-lookup.wasm');
    const nested = {
      components: topology.components.map((c) => ({ ...c, origin: ['macro'] })),
    };
    expect(memoriesOf(nested, host).size).toBe(0);
  });
});

describe('loadMemoryImages against the real artifacts', () => {
  test('the rom card starts holding the squares', async () => {
    const entry = examples.find((e) => e.slug === 'rom-lookup')!;
    const { host, topology, read } = await boot(entry.wasm!);
    // Before: a rom holds nothing at all.
    expect(read(topology.components[0].id, 0).defined).toBe(0n);

    const result = loadMemoryImages(host, topology, entry.memory!);
    expect([...result.errors]).toEqual([]);
    expect(result.applied).toEqual(['code']);

    // n² for every one of the sixteen addresses, read back through the same
    // getters the panel uses. This is the claim the lede makes.
    const id = topology.components[0].id;
    for (let addr = 0; addr < 16; addr += 1) {
      expect(`code[${addr}] = ${read(id, addr).value}`).toBe(`code[${addr}] = ${BigInt(addr * addr)}`);
      expect(read(id, addr).defined).toBe(255n);
    }
  });

  test('the ram card starts holding its own addresses', async () => {
    const entry = examples.find((e) => e.slug === 'ram-write-read')!;
    const { host, topology, read } = await boot(entry.wasm!);
    const result = loadMemoryImages(host, topology, entry.memory!);
    // A ram is loadable exactly as a rom is; only the truth table declines to
    // preload one, and a canvas is not a truth table.
    expect(result.applied).toEqual(['data']);
    const id = topology.components[0].id;
    for (let addr = 0; addr < 16; addr += 1) {
      expect(read(id, addr).value).toBe(BigInt(0xa0 + addr));
    }
  });

  test('a name the circuit does not declare is a message, not a throw', async () => {
    const { host, topology } = await boot('rom-lookup.wasm');
    const result = loadMemoryImages(host, topology, { nope: 'ff' });
    expect(result.applied).toEqual([]);
    expect(result.errors.get('nope')).toContain('not a memory');
  });

  test('one bad image does not stop the others', async () => {
    const { host, topology, read } = await boot('rom-lookup.wasm');
    const result = loadMemoryImages(host, topology, { code: 'ff', nope: 'zz' });
    // The good one still landed: a card with one bad image shows the rest.
    expect(result.applied).toEqual(['code']);
    expect(result.errors.has('nope')).toBe(true);
    expect(read(topology.components[0].id, 0).value).toBe(255n);
  });

  test('an image too large for the memory is refused before anything is written', async () => {
    const { host, topology, read } = await boot('rom-lookup.wasm');
    const result = loadMemoryImages(host, topology, { code: '00'.repeat(17) });
    expect(result.applied).toEqual([]);
    expect(result.errors.get('code')).toBeTruthy();
    expect(read(topology.components[0].id, 0).defined).toBe(0n);
  });

  test('an empty image asks for nothing rather than clearing', async () => {
    const { host, topology, read } = await boot('rom-lookup.wasm');
    loadMemoryImages(host, topology, { code: 'ff' });
    const result = loadMemoryImages(host, topology, { code: '' });
    expect(result.applied).toEqual([]);
    expect([...result.errors]).toEqual([]);
    expect(read(topology.components[0].id, 0).value).toBe(255n);
  });

  test('no images at all touches nothing', async () => {
    const { host, topology } = await boot('rom-lookup.wasm');
    expect(loadMemoryImages(host, topology, {})).toEqual({ applied: [], errors: new Map() });
  });
});

describe('the built gallery carries what it declares', () => {
  const DIST = resolve(import.meta.dir, '..', 'dist', 'gallery', 'index.html');
  const built = existsSync(DIST) ? readFileSync(DIST, 'utf8') : null;

  test.skipIf(built === null)('one data-circ-memory per card that has images, and none anywhere else', () => {
    const attrs = [...built!.matchAll(/data-circ-memory="([^"]*)"/g)].map((m) =>
      m[1].replace(/&#34;/g, '"'),
    );
    // Forgetting the prop on the page is invisible: the card still renders and
    // the circuit still runs, it just runs on an empty memory.
    expect(attrs).toHaveLength(withMemory.length);
    expect(attrs.map((a) => JSON.parse(a))).toEqual(withMemory.map((e) => e.memory));
    // …and the attribute is absent, not empty, on every other card.
    expect(built!).not.toContain('data-circ-memory=""');
  });
});

describe('readMemoryAttr', () => {
  test('reads the attribute a card carries', () => {
    expect(readMemoryAttr('{"code":"00ff"}')).toEqual({ code: '00ff' });
  });

  test('every malformed shape is an empty map, never a throw', () => {
    for (const bad of [undefined, null, '', 'not json', '[1,2]', '"a string"', '42']) {
      expect(readMemoryAttr(bad)).toEqual({});
    }
    // A non-string value is dropped rather than coerced.
    expect(readMemoryAttr('{"a":"ff","b":7,"c":null}')).toEqual({ a: 'ff' });
  });
});
