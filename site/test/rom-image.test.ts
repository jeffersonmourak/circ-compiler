// A ROM image is bytes a reader pastes in, so the page must accept exactly
// what the library accepts and refuse the rest by hand — with a reason, before
// a request is spent. The refusals are checked against the compiler's own
// order: whole words, then capacity, then each word's width.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  bytesPerWord,
  describeRomError,
  maxWords,
  parseRomImage,
  romSymbols,
  applyRomImages,
  preloadsFor,
  romPlan,
  type MemoryRuntime,
  type MemorySymbol,
} from '../src/utils/rom-image.ts';
import { callOp, instantiateLibcirc, type LibcircExports } from '../src/scripts/libcirc-abi.ts';
import { requestFor, splitFiles } from '../src/utils/split-files.ts';
import { optionsFor } from '../src/scripts/settings-drawer.ts';
import { defaultSettings } from '../src/utils/playground-store.ts';
import type { Analysis, AnalyzeSymbol } from '../src/scripts/circ-diagnostics.ts';

const rom = (over: Partial<MemorySymbol> = {}): MemorySymbol => ({
  name: 'code',
  kind: 'rom',
  width: 8,
  addrWidth: 4,
  ...over,
});

describe('word geometry', () => {
  test('bytesPerWord and maxWords match the compiler', () => {
    expect(bytesPerWord(1)).toBe(1);
    expect(bytesPerWord(8)).toBe(1);
    expect(bytesPerWord(9)).toBe(2);
    expect(bytesPerWord(16)).toBe(2);
    expect(bytesPerWord(64)).toBe(8);
    expect(maxWords(1)).toBe(2);
    expect(maxWords(4)).toBe(16);
    expect(maxWords(16)).toBe(65536);
  });
});

describe('romSymbols', () => {
  const symbols = [
    { file_id: 0, name: 'code', kind: 'rom', width: 8, addr_width: 4, range: {} },
    { file_id: 0, name: 'data', kind: 'ram', width: 16, addr_width: 8, range: {} },
    { file_id: 0, name: 'a', kind: 'input', width: 1, range: {} },
    { file_id: 1, name: 'elsewhere', kind: 'rom', width: 8, addr_width: 4, range: {} },
    { file_id: 0, name: 'broken', kind: 'rom', width: 8, range: {} },
  ] as unknown as AnalyzeSymbol[];

  test('keeps the root file\'s memories, in order', () => {
    const out = romSymbols(symbols, 0);
    expect(out.map((m) => m.name)).toEqual(['code', 'data']);
    expect(out[0]).toEqual({ name: 'code', kind: 'rom', width: 8, addrWidth: 4 });
    expect(out[1].kind).toBe('ram');
  });

  test('drops a memory with no address width rather than guessing one', () => {
    // Every bound below is computed from the width pair.
    expect(romSymbols(symbols, 0).some((m) => m.name === 'broken')).toBe(false);
  });

  test('a sibling file and a null root yield nothing', () => {
    expect(romSymbols(symbols, 0).some((m) => m.name === 'elsewhere')).toBe(false);
    expect(romSymbols(symbols, null)).toEqual([]);
  });
});

describe('parseRomImage — what a reader may type', () => {
  test('plain hex', () => {
    const r = parseRomImage('00ff10', rom());
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(Array.from(r.bytes)).toEqual([0, 255, 16]);
    expect(r.words).toBe(3);
    expect(r.hex).toBe('00ff10');
  });

  test('whitespace, newlines, commas, 0x prefixes and comments', () => {
    const text = `
      // the first four opcodes
      0x00, 0xff
      10 20   # trailing note
    `;
    const r = parseRomImage(text, rom());
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.hex).toBe('00ff1020');
  });

  test('an empty image is legal and clears nothing', () => {
    const r = parseRomImage('   \n  ', rom());
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.words).toBe(0);
      expect(r.hex).toBe('');
    }
  });

  test('the canonical hex is lowercase and even-length', () => {
    const r = parseRomImage('0A0B', rom());
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.hex).toBe('0a0b');
  });
});

describe('parseRomImage — refusals, in the compiler\'s own order', () => {
  test('a non-hex character', () => {
    const r = parseRomImage('00 zz', rom());
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.error.kind).toBe('bad_char');
    expect(r.message).toContain('not a hex digit');
  });

  test('an odd token, because a byte needs two digits', () => {
    const r = parseRomImage('0 ff', rom());
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('odd_token');
  });

  test('a length that is not a whole number of words', () => {
    // W=16 means two bytes per word; three bytes is one and a half.
    const r = parseRomImage('00ff10', rom({ width: 16 }));
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe('not_word_multiple');
      expect(r.message).toContain('3 bytes');
    }
  });

  test('more words than the address space holds', () => {
    // A=1 holds two words; three is one too many.
    const r = parseRomImage('000102', rom({ addrWidth: 1 }));
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe('too_many_words');
      expect(r.message).toContain('capacity of 2');
    }
    // Exactly full is fine.
    expect(parseRomImage('0001', rom({ addrWidth: 1 })).ok).toBe(true);
  });

  test('a word with bits set above the data width', () => {
    // W=4 in a one-byte word: 0x1f has bit 4 set.
    const r = parseRomImage('1f', rom({ width: 4 }));
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe('word_exceeds_width');
      expect(r.message).toContain('4 bits');
    }
    expect(parseRomImage('0f', rom({ width: 4 })).ok).toBe(true);
  });

  test('the order is words, then capacity, then width', () => {
    // Both too long AND over-wide: the length check must win, because it is
    // what the compiler reports first.
    const r = parseRomImage('ffffff', rom({ width: 16, addrWidth: 1 }));
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('not_word_multiple');
  });

  test('every error kind has a message', () => {
    const kinds = [
      { kind: 'bad_char', index: 0, char: 'z' },
      { kind: 'odd_token', token: '0', index: 0 },
      { kind: 'not_word_multiple', bytes: 3, bytesPerWord: 2 },
      { kind: 'too_many_words', words: 3, capacity: 2 },
      { kind: 'word_exceeds_width', word: 31, dataWidth: 4 },
    ] as const;
    for (const e of kinds) expect(describeRomError(e).length).toBeGreaterThan(10);
  });

  test('a 64-bit word is accepted rather than overflowing', () => {
    // The mask has to be computed in bigint, or W=64 wraps to 0.
    const r = parseRomImage('ffffffffffffffff', rom({ width: 64, addrWidth: 1 }));
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.words).toBe(1);
  });
});

const skip = process.env.SKIP_LIBCIRC_TEST === '1';
let cached: Promise<LibcircExports> | null = null;
const lib = () =>
  (cached ??= instantiateLibcirc(
    readFileSync(resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.wasm')),
  ));

describe.skipIf(skip)('against the committed module', () => {
  // The shipped fixture's own shape: width goes on the keyword, not the name.
  const source = 'input[4] pc\nrom code[8, 4](addr = pc.out)\noutput[8] out(in = code.out)\n';

  test('the page and the library agree on which memories exist', async () => {
    const w = await lib();
    const files = splitFiles(source);
    const an = callOp(w, 'analyze', requestFor(files));
    expect(an.status).toBe(0);
    const analysis = JSON.parse(new TextDecoder().decode(an.bytes)) as Analysis;
    const rootId = analysis.files.find((f) => f.path.endsWith('main.circ'))!.file_id;

    const mems = romSymbols(analysis.symbols, rootId);
    expect(mems).toHaveLength(1);
    expect(mems[0]).toEqual({ name: 'code', kind: 'rom', width: 8, addrWidth: 4 });
  });

  test('an image the page accepts is one the library accepts', async () => {
    const w = await lib();
    const files = splitFiles(source);
    const mem = rom();
    const parsed = parseRomImage('01 02 03 04', mem);
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) return;

    const options = optionsFor('truth_table', defaultSettings(), { code: parsed.hex });
    const out = callOp(w, 'truth_table', requestFor(files, options));
    // Status 0 is the whole claim: the bytes the page produced were loaded.
    expect(out.status).toBe(0);
    const table = JSON.parse(new TextDecoder().decode(out.bytes));
    expect(table.rows.length).toBe(16);
  });

  test('an image the page refuses would also have been refused', async () => {
    const w = await lib();
    const files = splitFiles(source);
    // 17 words into a 16-word memory.
    const tooMany = '00'.repeat(17);
    expect(parseRomImage(tooMany, rom()).ok).toBe(false);

    const out = callOp(w, 'truth_table', requestFor(files, optionsFor('truth_table', defaultSettings(), { code: tooMany })));
    // Status 3 is a refusal, and its text names the same problem.
    expect(out.status).toBe(3);
    expect(new TextDecoder().decode(out.bytes)).toContain('capacity');
  });

  test('a name that is not a declared memory is refused by the library', async () => {
    const w = await lib();
    const files = splitFiles(source);
    const out = callOp(w, 'truth_table', requestFor(files, optionsFor('truth_table', defaultSettings(), { nope: 'ff' })));
    expect(out.status).toBe(3);
    expect(new TextDecoder().decode(out.bytes)).toContain('nope');
  });
});

describe('romPlan and preloadsFor', () => {
  const roms = [rom(), rom({ name: 'other', width: 16, addrWidth: 2 })];

  test('plans a write per valid image and reports the rest', () => {
    const plan = romPlan(new Map([['code', '0102'], ['other', 'zz']]), roms);
    expect(plan.writes.map((w) => w.name)).toEqual(['code']);
    expect(plan.errors.get('other')).toContain('hex digit');
  });

  test('an empty image is a clear, not a missing write', () => {
    const plan = romPlan(new Map([['code', '  ']]), roms);
    expect(plan.writes).toEqual([{ name: 'code', bytes: null }]);
  });

  test('a ram is never written', () => {
    const plan = romPlan(new Map([['data', '01']]), [rom({ name: 'data', kind: 'ram' })]);
    expect(plan.writes).toEqual([]);
  });

  test('the text is re-validated against the CURRENT shape', () => {
    // Three bytes is three words at W=8 and not a whole number at W=16.
    const images = new Map([['code', '010203']]);
    expect(romPlan(images, [rom({ width: 8 })]).writes).toHaveLength(1);
    const narrowed = romPlan(images, [rom({ width: 16 })]);
    expect(narrowed.writes).toHaveLength(0);
    expect(narrowed.errors.get('code')).toContain('whole number');
  });

  test('a name no longer declared is skipped, not errored', () => {
    const plan = romPlan(new Map([['gone', '01']]), roms);
    expect(plan.writes).toEqual([]);
    expect(plan.errors.size).toBe(0);
  });

  test('preloadsFor yields canonical hex per rom', () => {
    expect(preloadsFor(new Map([['code', '0x01 0x02']]), roms)).toEqual({ code: '0102' });
    expect(preloadsFor(new Map([['code', '']]), roms)).toEqual({ code: '' });
    expect(preloadsFor(new Map(), roms)).toEqual({});
  });
});

describe('applyRomImages', () => {
  /** A runtime that records what it was told to do. The renderer owns the raw
   *  exports and the staging buffer now, so the fake speaks its typed surface. */
  function fakeRuntime(over: Partial<MemoryRuntime> = {}) {
    const loads: { id: number; bytes: number[] }[] = [];
    const clears: number[] = [];
    const runtime: MemoryRuntime & { loads: typeof loads; clears: typeof clears } = {
      loads,
      clears,
      memories: () => [{ id: 7, name: 'code', info: { kind: 'rom', width: 8, addrWidth: 4 } }],
      loadMemImage: (id, bytes) => {
        loads.push({ id, bytes: Array.from(bytes) });
        return 0;
      },
      clearMem: (id) => {
        clears.push(id);
        return 0;
      },
      ...over,
    };
    return runtime;
  }

  const roms = [rom()];

  test('hands the bytes to the runtime against the id it confirmed', () => {
    const runtime = fakeRuntime();
    const plan = romPlan(new Map([['code', '01020304']]), roms);
    const result = applyRomImages(runtime, plan, roms);
    expect(result.applied).toEqual(['code']);
    expect(result.errors.size).toBe(0);
    expect(runtime.loads).toEqual([{ id: 7, bytes: [1, 2, 3, 4] }]);
  });

  test('an empty image clears rather than loading nothing', () => {
    const runtime = fakeRuntime();
    const result = applyRomImages(runtime, romPlan(new Map([['code', '']]), roms), roms);
    expect(result.applied).toEqual(['code']);
    expect(runtime.clears).toEqual([7]);
    expect(runtime.loads).toEqual([]);
  });

  test('a shape mismatch refuses rather than writing to the wrong memory', () => {
    const runtime = fakeRuntime({
      memories: () => [{ id: 7, name: 'code', info: { kind: 'rom', width: 16, addrWidth: 4 } }],
    });
    const result = applyRomImages(runtime, romPlan(new Map([['code', '0102']]), roms), roms);
    expect(result.applied).toEqual([]);
    expect(result.errors.get('code')).toContain('does not match');
    expect(runtime.loads).toEqual([]);
  });

  test('a name the runtime does not confirm is reported', () => {
    const runtime = fakeRuntime({ memories: () => [] });
    const result = applyRomImages(runtime, romPlan(new Map([['code', '01']]), roms), roms);
    expect(result.errors.get('code')).toContain('not in the compiled circuit');
  });

  test('a non-zero load code is a failure, not a silent success', () => {
    const runtime = fakeRuntime({ loadMemImage: () => 3 });
    const result = applyRomImages(runtime, romPlan(new Map([['code', '01']]), roms), roms);
    expect(result.applied).toEqual([]);
    expect(result.errors.get('code')).toContain('code 3');
  });

  test('parse errors survive into the apply result', () => {
    const runtime = fakeRuntime();
    const plan = romPlan(new Map([['code', 'zz']]), roms);
    expect(applyRomImages(runtime, plan, roms).errors.get('code')).toContain('hex digit');
    expect(runtime.loads).toEqual([]);
  });
});
