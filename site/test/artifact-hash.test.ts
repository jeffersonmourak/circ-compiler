// Every consumer of an artifact must hash it the same way, or the canvas is
// rebuilt on every keystroke and the reader's toggled pins go with it.
import { describe, expect, test } from 'bun:test';
import { fnv1a } from '../src/utils/artifact-hash.ts';

describe('fnv1a', () => {
  test('matches the reference vectors', () => {
    const of = (s: string) => fnv1a(new TextEncoder().encode(s));
    expect(of('')).toBe(0x811c9dc5);
    expect(of('a')).toBe(0xe40c292c);
    expect(of('foobar')).toBe(0xbf9cf968);
  });

  test('is unsigned and stable', () => {
    const bytes = new Uint8Array([255, 254, 253, 0, 1]);
    const h = fnv1a(bytes);
    expect(h).toBeGreaterThanOrEqual(0);
    expect(h).toBe(fnv1a(bytes));
    expect(Number.isInteger(h)).toBe(true);
  });

  test('one changed byte changes the hash', () => {
    const a = new Uint8Array([1, 2, 3, 4]);
    const b = new Uint8Array([1, 2, 3, 5]);
    expect(fnv1a(a)).not.toBe(fnv1a(b));
  });
});
