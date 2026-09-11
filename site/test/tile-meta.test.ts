import { expect, test } from 'bun:test';
import { tileMeta, tileMetaLabel } from '../src/scripts/tile-meta.ts';
import { examples } from '../src/content/examples.ts';

test('counts pins, not bits or binding commas', () => {
  expect(tileMeta('input[2] a, b\noutput[2] s(in={a,b})\noutput cout(in=a)\nwire x(in=a)')).toEqual({ inputs: 2, outputs: 2, words: null });
});
test('reads memory address width and refuses two memories', () => {
  for (const kind of ['rom', 'ram']) expect(tileMeta(`${kind} data[8, 4](addr=pc.out)`).words).toBe(16);
  expect(() => tileMeta('rom a[8,4]()\nram b[8,4]()')).toThrow();
});
test('strips comments and refuses file markers', () => {
  expect(tileMeta('// input x\ninput a // input b')).toEqual({ inputs: 1, outputs: 0, words: null });
  expect(() => tileMeta('// half.circ\ninput a')).toThrow();
});
test('the three shipped tiles have the expected metadata', () => {
  for (const [slug, label] of [['two-bit-adder', '2 in · 2 out'], ['four-bit-adder', '2 in · 2 out'], ['rom-lookup', '1 in · 1 out · 16 words']]) {
    expect(tileMetaLabel(tileMeta(examples.find(ex => ex.slug === slug)!.source))).toBe(label);
  }
});
