// The console's pure parts, over plain values.
import { describe, expect, test } from 'bun:test';
import { HistoryRing, LOAD_REFUSAL, MemoryTabFiles, SAVE_REFUSAL, Transcript, commandFor, helpLines, promptEcho } from '../src/scripts/console.ts';
import { parseLine } from '../src/scripts/sim-protocol.ts';
import type { SessionEvent } from '../src/scripts/sim-session.ts';

describe('history is a ring of a hundred lines', () => {
  test('up walks back and stays on the oldest; down returns to the empty prompt', () => {
    const h = new HistoryRing();
    expect(h.up()).toBeNull();
    expect(h.down()).toBeNull();
    h.push('set a 1');
    h.push('get out');
    expect(h.up()).toBe('get out');
    expect(h.up()).toBe('set a 1');
    expect(h.up()).toBe('set a 1');
    expect(h.down()).toBe('get out');
    expect(h.down()).toBe('');
    expect(h.down()).toBeNull();
  });

  test('a submit resets the cursor, blank lines are not kept, and a repeat is kept once', () => {
    const h = new HistoryRing();
    h.push('a');
    h.push('b');
    h.up();
    h.up();
    h.push('c');
    expect(h.up()).toBe('c');
    h.push('');
    expect(h.size).toBe(3);
    h.push('c');
    expect(h.size).toBe(3);
    h.reset();
    expect(h.up()).toBe('c');
  });

  test('the cap drops the oldest', () => {
    const h = new HistoryRing(3);
    for (const l of ['1', '2', '3', '4']) h.push(l);
    expect(h.size).toBe(3);
    expect(h.up()).toBe('4');
    expect(h.up()).toBe('3');
    expect(h.up()).toBe('2');
    expect(h.up()).toBe('2');
  });
});

describe('the transcript keeps its newest lines', () => {
  test('append, cap, clear, last', () => {
    const t = new Transcript(4);
    expect(t.text).toBe('');
    expect(t.last).toBeNull();
    t.append(['a', 'b']);
    t.append([]);
    expect(t.text).toBe('a\nb');
    t.append(['c', 'd', 'e']);
    expect(t.text).toBe('b\nc\nd\ne');
    expect(t.length).toBe(4);
    expect(t.last).toBe('e');
    t.clear();
    expect(t.text).toBe('');
    expect(t.length).toBe(0);
  });
});

describe("the page's file source points at the Memory tab", () => {
  test('both ways, with the two messages', () => {
    const files = new MemoryTabFiles();
    expect(files.read('x.bin')).toEqual({ ok: false, error: LOAD_REFUSAL });
    expect(files.write('x.bin', new Uint8Array(1))).toEqual({ ok: false, error: SAVE_REFUSAL });
  });
});

describe('the echo and the help', () => {
  test('an echo cannot read as a reply', () => {
    expect(promptEcho('set a 1')).toBe('> set a 1');
    expect(parseLine(promptEcho('set a 1')).ok).toBe(false);
  });

  test('help is comment lines the protocol ignores, one per verb', () => {
    const lines = helpLines();
    for (const line of lines) {
      expect(line.startsWith('# ')).toBe(true);
      expect(parseLine(line)).toEqual({ ok: false, reason: 'empty' });
    }
    const verbs = lines.slice(1).map((l) => l.slice(2).trim().split(' ')[0]);
    expect(verbs).toEqual(['pins', 'set', 'get', 'dump', 'eval', 'run', 'reset', 'quit', 'mems', 'peek', 'poke', 'mem', 'clear', 'load', 'save', 'help']);
  });
});

describe('commandFor spells the protocol line and its reply', () => {
  const session = {
    pins: [
      { name: 'a', id: 0, width: 4, kind: 'in' as const },
      { name: 'clk', id: 1, width: 1, kind: 'in' as const },
      { name: 'q', id: 2, width: 8, kind: 'out' as const },
    ],
    mems: [{ name: 'data', id: 3, kind: 'ram' as const, width: 8, addrWidth: 4 }],
  };
  const drive = (assigns: { name: string; value: bigint; defined: bigint }[]): SessionEvent => ({
    kind: 'drive',
    names: assigns.map((a) => a.name),
    assigns,
  });

  test('a drive is one set per pin, with a mask only when the pin is not wholly known', () => {
    expect(commandFor(drive([{ name: 'a', value: 0xan, defined: 0xfn }]), session)).toEqual(['> set a 0xa', 'ok']);
    expect(commandFor(drive([{ name: 'clk', value: 1n, defined: 1n }, { name: 'a', value: 3n, defined: 0xfn }]), session)).toEqual([
      '> set clk 0x1',
      'ok',
      '> set a 0x3',
      'ok',
    ]);
    expect(commandFor(drive([{ name: 'a', value: 0x5n, defined: 0x3n }]), session)).toEqual(['> set a 0x1 0x3', 'ok']);
    expect(commandFor(drive([{ name: 'a', value: 0n, defined: 0n }]), session)).toEqual(['> set a 0x0 0x0', 'ok']);
    // Canonical: a value bit under an unknown mask bit is not written.
    expect(commandFor(drive([{ name: 'a', value: 0xfn, defined: 0xcn }]), session)).toEqual(['> set a 0xc 0xc', 'ok']);
    // A name the session does not know keeps its mask rather than guessing a width.
    expect(commandFor(drive([{ name: 'zz', value: 1n, defined: 1n }]), session)).toEqual(['> set zz 0x1 0x1', 'ok']);
    // Every line is the grammar's, so the echo parses once its mark is stripped.
    for (const line of commandFor(drive([{ name: 'a', value: 0x5n, defined: 0x3n }]), session)) {
      if (line.startsWith('> ')) expect(parseLine(line.slice(2)).ok).toBe(true);
    }
  });

  test('memory events are a poke, a clear or a comment about an image', () => {
    expect(commandFor({ kind: 'memory', name: 'data', op: 'poke', addr: 2n, value: 0x5an, defined: 0xffn }, session)).toEqual(['> poke data 0x2 0x5a', 'ok']);
    expect(commandFor({ kind: 'memory', name: 'data', op: 'poke', addr: 15n, value: 0n, defined: 0n }, session)).toEqual(['> poke data 0xf 0x0 0x0', 'ok']);
    expect(commandFor({ kind: 'memory', name: 'data', op: 'clear' }, session)).toEqual(['> clear data', 'ok']);
    expect(commandFor({ kind: 'memory', name: 'code', op: 'load', words: 4 }, session)).toEqual(['# code: image from the Memory tab, 4 words']);
    expect(commandFor({ kind: 'memory', name: 'code', op: 'load', words: 1 }, session)).toEqual(['# code: image from the Memory tab, 1 word']);
  });

  test('a rebuild is a reset; an end is nothing', () => {
    expect(commandFor({ kind: 'rebuilt' }, session)).toEqual(['> reset', 'ok']);
    expect(commandFor({ kind: 'destroyed' }, session)).toEqual([]);
  });
});
