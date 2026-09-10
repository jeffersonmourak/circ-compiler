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
import { CircRuntime } from 'circ-renderer';
import { loadMemoryImages, readMemoryAttr } from '../src/scripts/canvas-memory.ts';
import { examples } from '../src/content/examples.ts';

const WASM = resolve(import.meta.dir, '..', 'public', 'wasm');

/** The artifact as the gallery card runs it: through the renderer's runtime,
 *  which is the one that confirms every memory's name and shape. */
async function boot(file: string) {
  return CircRuntime.loadFromBytes(new Uint8Array(readFileSync(resolve(WASM, file))));
}

/** The one memory a shipped artifact declares, and a reader over it. */
function only(rt: CircRuntime) {
  const [mem] = rt.memories();
  if (!mem) throw new Error('the artifact declares no memory');
  return { id: mem.id, mem, read: (addr: number) => rt.readMemWord(mem.id, addr) };
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

describe('the runtime confirms what the artifacts declare', () => {
  test('a rom and a ram, each with the shape the card was written against', async () => {
    const rom = await boot('rom-lookup.wasm');
    expect(rom.memories().map((m) => [m.name, m.info])).toEqual([
      ['code', { kind: 'rom', width: 8, addrWidth: 4 }],
    ]);
    const ram = await boot('ram-write-read.wasm');
    expect(ram.memories().map((m) => [m.name, m.info.kind])).toEqual([['data', 'ram']]);
  });
});

describe('loadMemoryImages against the real artifacts', () => {
  test('the rom card starts holding the squares', async () => {
    const entry = examples.find((e) => e.slug === 'rom-lookup')!;
    const rt = await boot(entry.wasm!);
    const { read } = only(rt);
    // Before: a rom holds nothing at all.
    expect(read(0).defined).toBe(0n);

    const result = loadMemoryImages(rt, entry.memory!);
    expect([...result.errors]).toEqual([]);
    expect(result.applied).toEqual(['code']);

    // n² for every one of the sixteen addresses, read back through the same
    // getters the panel uses. This is the claim the lede makes.
    for (let addr = 0; addr < 16; addr += 1) {
      expect(`code[${addr}] = ${read(addr).value}`).toBe(`code[${addr}] = ${BigInt(addr * addr)}`);
      expect(read(addr).defined).toBe(255n);
    }
  });

  test('the ram card starts holding its own addresses', async () => {
    const entry = examples.find((e) => e.slug === 'ram-write-read')!;
    const rt = await boot(entry.wasm!);
    const { read } = only(rt);
    const result = loadMemoryImages(rt, entry.memory!);
    // A ram is loadable exactly as a rom is; only the truth table declines to
    // preload one, and a canvas is not a truth table.
    expect(result.applied).toEqual(['data']);
    for (let addr = 0; addr < 16; addr += 1) {
      expect(read(addr).value).toBe(BigInt(0xa0 + addr));
    }
  });

  test('a name the circuit does not declare is a message, not a throw', async () => {
    const rt = await boot('rom-lookup.wasm');
    const result = loadMemoryImages(rt, { nope: 'ff' });
    expect(result.applied).toEqual([]);
    expect(result.errors.get('nope')).toContain('not a memory');
  });

  test('one bad image does not stop the others', async () => {
    const rt = await boot('rom-lookup.wasm');
    const { read } = only(rt);
    const result = loadMemoryImages(rt, { code: 'ff', nope: 'zz' });
    // The good one still landed: a card with one bad image shows the rest.
    expect(result.applied).toEqual(['code']);
    expect(result.errors.has('nope')).toBe(true);
    expect(read(0).value).toBe(255n);
  });

  test('an image too large for the memory is refused before anything is written', async () => {
    const rt = await boot('rom-lookup.wasm');
    const { read } = only(rt);
    const result = loadMemoryImages(rt, { code: '00'.repeat(17) });
    expect(result.applied).toEqual([]);
    expect(result.errors.get('code')).toBeTruthy();
    expect(read(0).defined).toBe(0n);
  });

  test('an empty image asks for nothing rather than clearing', async () => {
    const rt = await boot('rom-lookup.wasm');
    const { read } = only(rt);
    loadMemoryImages(rt, { code: 'ff' });
    const result = loadMemoryImages(rt, { code: '' });
    expect(result.applied).toEqual([]);
    expect([...result.errors]).toEqual([]);
    expect(read(0).value).toBe(255n);
  });

  test('no images at all touches nothing', async () => {
    const rt = await boot('rom-lookup.wasm');
    expect(loadMemoryImages(rt, {})).toEqual({ applied: [], errors: new Map() });
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
