// The console's pure parts, over plain values.
import { describe, expect, test } from 'bun:test';
import { HistoryRing, LOAD_REFUSAL, MemoryTabFiles, SAVE_REFUSAL, Transcript, helpLines, promptEcho } from '../src/scripts/console.ts';
import { parseLine } from '../src/scripts/sim-protocol.ts';

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
