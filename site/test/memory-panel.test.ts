// A memory's contents are the one thing in the playground that the artifact
// does not carry: they are runtime state, read back a word at a time. These
// tests are mostly about DEFINEDNESS — a half-known word must not be written
// down as if it were known, and must not be written down as if it were blank.
import { describe, expect, test } from 'bun:test';
import {
  UNKNOWN,
  cellWidth,
  clampWindow,
  dumpRows,
  formatAddress,
  formatWord,
  maskFor,
  pageContaining,
  pageCount,
  parseAddress,
  parseWord,
  type Cell,
} from '../src/scripts/memory-panel.ts';

const cell = (value: bigint, defined: bigint): Cell => ({ value, defined });
const full = (value: bigint, width: number): Cell => cell(value, maskFor(width));

describe('formatWord', () => {
  test('a fully defined word follows the chosen format', () => {
    expect(formatWord(full(0xa5n, 8), 8, 'hex')).toBe('a5');
    expect(formatWord(full(0xa5n, 8), 8, 'binary')).toBe('10100101');
    expect(formatWord(full(0xa5n, 8), 8, 'decimal')).toBe('165');
  });

  test('hex and binary are padded to the declared width, decimal is not', () => {
    expect(formatWord(full(1n, 8), 8, 'hex')).toBe('01');
    expect(formatWord(full(1n, 8), 8, 'binary')).toBe('00000001');
    expect(formatWord(full(1n, 8), 8, 'decimal')).toBe('1');
    // A width that is not a multiple of four still gets whole hex digits.
    expect(formatWord(full(3n, 5), 5, 'hex')).toBe('03');
    expect(formatWord(full(3n, 5), 5, 'binary')).toBe('00011');
  });

  test('a word with no known bits is ?, whatever its value bits say', () => {
    for (const format of ['binary', 'hex', 'decimal'] as const) {
      expect(formatWord(cell(0n, 0n), 8, format)).toBe(UNKNOWN);
      // Value bits under a zero defined mask are meaningless and must not leak.
      expect(formatWord(cell(0xffn, 0n), 8, format)).toBe(UNKNOWN);
    }
  });

  test('a partially defined word is binary with x, whatever the format', () => {
    // There is no honest hex digit for four bits of which two are unknown.
    const half = cell(0b1010_0000n, 0b1111_0000n);
    for (const format of ['binary', 'hex', 'decimal'] as const) {
      expect(formatWord(half, 8, format)).toBe('1010xxxx');
    }
    expect(formatWord(cell(0b1n, 0b1n), 4, 'hex')).toBe('xxx1');
  });

  test('bits above the declared width never reach the screen', () => {
    // A stray high bit is masked off rather than widening the word.
    expect(formatWord(cell(0xff00n | 0x5n, maskFor(4)), 4, 'hex')).toBe('5');
    expect(formatWord(cell(0xfn, 0xffffn), 4, 'binary')).toBe('1111');
  });

  test('the full 64-bit width round-trips', () => {
    const w = 64;
    const all = maskFor(w);
    expect(all).toBe(18446744073709551615n);
    expect(formatWord(full(all, w), w, 'decimal')).toBe('18446744073709551615');
    expect(formatWord(full(all, w), w, 'hex')).toBe('ffffffffffffffff');
    expect(formatWord(full(all, w), w, 'binary')).toBe('1'.repeat(64));
  });

  test('a one-bit memory reads as a bit', () => {
    expect(formatWord(full(1n, 1), 1, 'binary')).toBe('1');
    expect(formatWord(full(0n, 1), 1, 'hex')).toBe('0');
    expect(formatWord(cell(0n, 0n), 1, 'binary')).toBe(UNKNOWN);
  });
});

describe('cellWidth', () => {
  test('reserves room for the widest rendering, which is the partial one', () => {
    // Hex of an 8-bit word is 2 characters, but `1010xxxx` is 8.
    expect(cellWidth(8, 'hex')).toBe(8);
    expect(cellWidth(8, 'binary')).toBe(8);
    expect(cellWidth(16, 'decimal')).toBe(16);
  });
});

describe('windows', () => {
  test('a window never runs past either end', () => {
    expect(clampWindow(0, 16, 256)).toEqual({ start: 0, count: 16 });
    expect(clampWindow(250, 16, 256)).toEqual({ start: 240, count: 16 });
    expect(clampWindow(-5, 16, 256)).toEqual({ start: 0, count: 16 });
    // A memory smaller than one page shows all of it.
    expect(clampWindow(0, 64, 8)).toEqual({ start: 0, count: 8 });
    expect(clampWindow(4, 64, 8)).toEqual({ start: 0, count: 8 });
  });

  test('an empty memory is a window of nothing rather than a throw', () => {
    expect(clampWindow(0, 16, 0)).toEqual({ start: 0, count: 0 });
  });

  test('paging is aligned, so going back and forth does not drift', () => {
    expect(pageContaining(0, 16, 256)).toEqual({ start: 0, count: 16 });
    expect(pageContaining(5, 16, 256)).toEqual({ start: 0, count: 16 });
    expect(pageContaining(16, 16, 256)).toEqual({ start: 16, count: 16 });
    expect(pageContaining(31, 16, 256)).toEqual({ start: 16, count: 16 });
    // The last page is clamped, not aligned past the end.
    expect(pageContaining(255, 16, 250)).toEqual({ start: 234, count: 16 });
  });

  test('pageCount covers every word, including a ragged last page', () => {
    expect(pageCount(16, 256)).toBe(16);
    expect(pageCount(16, 257)).toBe(17);
    expect(pageCount(16, 0)).toBe(1);
  });
});

describe('dumpRows', () => {
  test('reads each visible address exactly once, and nothing else', () => {
    const seen: number[] = [];
    const read = (addr: number): Cell => {
      seen.push(addr);
      return full(BigInt(addr), 8);
    };
    const rows = dumpRows(read, { start: 16, count: 8 }, 4, 8, 'hex');
    expect(seen).toEqual([16, 17, 18, 19, 20, 21, 22, 23]);
    // This is the whole reason for paging: a 2^16-word memory must not be
    // read in full to repaint eight visible cells.
    expect(new Set(seen).size).toBe(seen.length);
    expect(rows.map((r) => r.base)).toEqual([16, 20]);
    expect(rows[0].cells.map((c) => c.text)).toEqual(['10', '11', '12', '13']);
  });

  test('a ragged final row is short rather than padded past the window', () => {
    const rows = dumpRows(() => full(0n, 8), { start: 0, count: 6 }, 4, 8, 'hex');
    expect(rows.map((r) => r.cells.length)).toEqual([4, 2]);
    expect(rows.at(-1)!.cells.at(-1)!.addr).toBe(5);
  });

  test('known is false only when no bit of the word is known', () => {
    const cells = [cell(0n, 0n), cell(0n, maskFor(8)), cell(0b1n, 0b1n)];
    const rows = dumpRows((a) => cells[a], { start: 0, count: 3 }, 3, 8, 'hex');
    expect(rows[0].cells.map((c) => c.known)).toEqual([false, true, true]);
    // A zero that is KNOWN to be zero is not the same as an unknown word.
    expect(rows[0].cells.map((c) => c.text)).toEqual([UNKNOWN, '00', 'xxxxxxx1']);
  });

  test('an empty window produces no rows', () => {
    expect(dumpRows(() => full(0n, 8), { start: 0, count: 0 }, 4, 8, 'hex')).toEqual([]);
  });
});

describe('formatAddress', () => {
  test('always hex, padded to the address width', () => {
    expect(formatAddress(0, 4)).toBe('0');
    expect(formatAddress(255, 8)).toBe('ff');
    expect(formatAddress(1, 16)).toBe('0001');
  });
});

describe('parseWord', () => {
  test('reads the chosen format by default', () => {
    expect(parseWord('ff', 8, 'hex')).toEqual({ ok: true, value: 255n, defined: 255n });
    expect(parseWord('1010', 8, 'binary')).toEqual({ ok: true, value: 10n, defined: 255n });
    expect(parseWord('42', 8, 'decimal')).toEqual({ ok: true, value: 42n, defined: 255n });
  });

  test('an explicit prefix overrides the chosen format', () => {
    // A reader who typed 0x meant hex, whatever the drop-down says.
    expect(parseWord('0x1f', 8, 'decimal')).toEqual({ ok: true, value: 31n, defined: 255n });
    expect(parseWord('0b101', 8, 'hex')).toEqual({ ok: true, value: 5n, defined: 255n });
  });

  test('? and empty make the word unknown again, which is the only way back', () => {
    for (const text of ['?', '', '  ']) {
      expect(parseWord(text, 8, 'hex')).toEqual({ ok: true, value: 0n, defined: 0n });
    }
    // …and that is NOT the same as writing a zero.
    expect(parseWord('0', 8, 'hex')).toEqual({ ok: true, value: 0n, defined: 255n });
  });

  test('a word too large for the declared width is refused with the limit', () => {
    const r = parseWord('100', 8, 'hex');
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.message).toContain('255');
    expect(parseWord('ff', 8, 'hex').ok).toBe(true);
    // The singular reads properly on a one-bit memory.
    const one = parseWord('2', 1, 'decimal');
    expect(one.ok).toBe(false);
    if (!one.ok) expect(one.message).toContain('1 bit;');
  });

  test('garbage is a message, never a throw and never a silent zero', () => {
    for (const bad of ['zz', '0xg', '0b12', '1.5', '-1', '#']) {
      const r = parseWord(bad, 8, 'hex');
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.message.length).toBeGreaterThan(0);
    }
  });

  test('underscores are allowed as digit grouping', () => {
    expect(parseWord('1010_1010', 8, 'binary')).toEqual({ ok: true, value: 170n, defined: 255n });
  });

  test('the full 64-bit range parses', () => {
    const r = parseWord('ffffffffffffffff', 64, 'hex');
    expect(r).toEqual({ ok: true, value: 18446744073709551615n, defined: 18446744073709551615n });
    expect(parseWord('10000000000000000', 64, 'hex').ok).toBe(false);
  });
});

describe('parseAddress', () => {
  test('hex by default, d for decimal, null on anything else', () => {
    expect(parseAddress('ff', 8)).toBe(255);
    expect(parseAddress('0x10', 8)).toBe(16);
    expect(parseAddress('d16', 8)).toBe(16);
    expect(parseAddress('', 8)).toBeNull();
    expect(parseAddress('zz', 8)).toBeNull();
  });

  test('an address past the end of the memory is refused', () => {
    // 4 address bits is 16 words: 0..f.
    expect(parseAddress('f', 4)).toBe(15);
    expect(parseAddress('10', 4)).toBeNull();
    expect(parseAddress('d15', 4)).toBe(15);
    expect(parseAddress('d16', 4)).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Against the real thing.
//
// Everything above is arithmetic over numbers a test made up. These drive the
// committed `libcirc.wasm` to decide which circuits declare a memory at all —
// which is the whole condition the dock tab appears on — and then compile one,
// instantiate it, and read its cells back through the same two getters the
// panel uses.
// ---------------------------------------------------------------------------

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { callOp, instantiateLibcirc, type LibcircExports } from '../src/scripts/libcirc-abi.ts';
import { requestFor, splitFiles } from '../src/utils/split-files.ts';
import { applyRomImages, parseRomImage, romPlan, romSymbols, type MemorySymbol } from '../src/utils/rom-image.ts';
import { examples } from '../src/content/examples.ts';
import type { Analysis } from '../src/scripts/circ-diagnostics.ts';

const skip = process.env.SKIP_LIBCIRC_TEST === '1';
let cached: Promise<LibcircExports> | null = null;
const lib = () =>
  (cached ??= instantiateLibcirc(
    readFileSync(resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.wasm')),
  ));

/** The declared memories of a source, exactly as the island computes them. */
async function memoriesOf(source: string): Promise<MemorySymbol[]> {
  const w = await lib();
  const files = splitFiles(source);
  const out = callOp(w, 'analyze', requestFor(files));
  if (out.status !== 0) return [];
  const analysis = JSON.parse(new TextDecoder().decode(out.bytes)) as Analysis;
  const root = analysis.files.find((f) => f.path.endsWith(files[files.length - 1].name));
  return romSymbols(analysis.symbols, root ? root.file_id : null);
}

/** Compile a source and instantiate the artifact, ready to drive. */
async function runCircuit(source: string) {
  const w = await lib();
  const out = callOp(w, 'compile', requestFor(splitFiles(source)));
  expect(out.status).toBe(0);
  const mod = await WebAssembly.compile(out.bytes as unknown as BufferSource);
  const { exports } = await WebAssembly.instantiate(mod, {
    env: { debugEnabled: () => 0, onDebugLog: () => {} },
  });
  const host = exports as unknown as Record<string, (...a: never[]) => never> & {
    memory: { buffer: ArrayBufferLike };
  };
  const [section] = WebAssembly.Module.customSections(mod, 'circ.topology.v0.min');
  const topo = new Uint8Array(section);
  const ptr = (host.topology_alloc as unknown as (n: number) => number)(topo.length);
  new Uint8Array(host.memory.buffer).set(topo, ptr);
  (host.init as unknown as () => void)();
  return host as unknown as Record<string, unknown> & { memory: { buffer: ArrayBufferLike } };
}

describe.skipIf(skip)('which circuits map a memory', () => {
  test('exactly the two shipped examples that declare one', async () => {
    // This is the condition the dock tab lives on, checked against the real
    // analysis rather than against a hand-built symbol list.
    const withMemory: string[] = [];
    for (const e of examples) {
      if ((await memoriesOf(e.source)).length > 0) withMemory.push(e.slug);
    }
    expect(withMemory.sort()).toEqual(['ram-write-read', 'rom-lookup']);
  });

  test('a rom and a ram are both reported, with their declared shape', async () => {
    const roms = await memoriesOf('input[4] pc\nrom code[8, 4](addr = pc.out)\noutput[8] out(in = code.out)\n');
    expect(roms).toEqual([{ name: 'code', kind: 'rom', width: 8, addrWidth: 4 }]);
    const rams = await memoriesOf(examples.find((e) => e.slug === 'ram-write-read')!.source);
    expect(rams.length).toBeGreaterThan(0);
    expect(rams.every((m) => m.kind === 'ram' || m.kind === 'rom')).toBe(true);
  });

  test('a circuit with no memory reports none, so the tab stays away', async () => {
    expect(await memoriesOf('input a\nnot n(in=a)\noutput out(in=n.out)\n')).toEqual([]);
  });
});

describe.skipIf(skip)('reading and writing a running memory', () => {
  const source = 'input[4] pc\nrom code[8, 4](addr = pc.out)\noutput[8] out(in = code.out)\n';
  const mem: MemorySymbol = { name: 'code', kind: 'rom', width: 8, addrWidth: 4 };

  /** The id join the panel does, and the two getters it reads through. */
  function bind(host: Record<string, unknown>) {
    const getInfo = host.getMemInfo as (id: number) => number;
    let id = -1;
    for (let candidate = 0; candidate < 64; candidate += 1) {
      if (getInfo(candidate) >= 0) { id = candidate; break; }
    }
    expect(id).toBeGreaterThanOrEqual(0);
    const read = (addr: number): Cell => ({
      value: BigInt((host.getMemValue as (i: number, a: number) => bigint)(id, addr)),
      defined: BigInt((host.getMemDefined as (i: number, a: number) => bigint)(id, addr)),
    });
    return { id, read };
  }

  test('an unloaded rom reads as unknown, not as zeros', async () => {
    const host = await runCircuit(source);
    const { read } = bind(host);
    const rows = dumpRows(read, { start: 0, count: 16 }, 8, mem.width, 'hex');
    const texts = rows.flatMap((r) => r.cells.map((c) => c.text));
    expect(texts).toHaveLength(16);
    // The distinction the whole formatter exists for: nothing has been written
    // here, and that is not the same as a memory full of zeros.
    expect(new Set(texts)).toEqual(new Set([UNKNOWN]));
    expect(rows.flatMap((r) => r.cells.map((c) => c.known))).not.toContain(true);
  });

  test('a loaded image reads back word for word', async () => {
    const host = await runCircuit(source);
    const { id, read } = bind(host);
    const parsed = parseRomImage('de ad be ef', mem);
    expect(parsed.ok).toBe(true);
    const result = applyRomImages(
      host as never,
      romPlan(new Map([['code', 'de ad be ef']]), [mem]),
      () => id,
      [mem],
    );
    expect([...result.errors]).toEqual([]);
    expect(result.applied).toEqual(['code']);

    const rows = dumpRows(read, { start: 0, count: 8 }, 8, mem.width, 'hex');
    expect(rows[0].cells.map((c) => c.text)).toEqual(['de', 'ad', 'be', 'ef', UNKNOWN, UNKNOWN, UNKNOWN, UNKNOWN]);
    // The same cells in another format, since the panel follows the setting.
    expect(dumpRows(read, { start: 0, count: 2 }, 2, mem.width, 'decimal')[0].cells.map((c) => c.text))
      .toEqual(['222', '173']);
  });

  test('a word the reader types is written, and ? takes it back', async () => {
    const host = await runCircuit(source);
    const { id, read } = bind(host);
    const write = host.setMemWord as (i: number, a: number, v: bigint, d: bigint) => number;

    const typed = parseWord('7f', mem.width, 'hex');
    expect(typed.ok).toBe(true);
    if (!typed.ok) return;
    expect(write(id, 3, typed.value, typed.defined)).toBe(0);
    expect(formatWord(read(3), mem.width, 'hex')).toBe('7f');
    // Its neighbours are untouched.
    expect(formatWord(read(2), mem.width, 'hex')).toBe(UNKNOWN);

    const cleared = parseWord('?', mem.width, 'hex');
    expect(cleared.ok).toBe(true);
    if (!cleared.ok) return;
    expect(write(id, 3, cleared.value, cleared.defined)).toBe(0);
    expect(formatWord(read(3), mem.width, 'hex')).toBe(UNKNOWN);
  });

  test('clear makes every word unknown again', async () => {
    const host = await runCircuit(source);
    const { id, read } = bind(host);
    applyRomImages(host as never, romPlan(new Map([['code', 'ff'.repeat(16)]]), [mem]), () => id, [mem]);
    expect(formatWord(read(0), mem.width, 'hex')).toBe('ff');
    expect((host.memClear as (i: number) => number)(id)).toBe(0);
    const rows = dumpRows(read, { start: 0, count: 16 }, 16, mem.width, 'hex');
    expect(new Set(rows[0].cells.map((c) => c.text))).toEqual(new Set([UNKNOWN]));
  });
});
