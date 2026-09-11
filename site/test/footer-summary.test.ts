// The diagnostics footer's two strings, from the island's own state.
import { describe, expect, test } from 'bun:test';
import { lineCount, summarize, summaryLabels } from '../src/scripts/footer-summary.ts';
import type { Analysis } from '../src/scripts/circ-diagnostics.ts';

const range = { start: { line: 1, column: 1 }, end: { line: 1, column: 2 } } as unknown as Analysis['symbols'][number]['range'];
const sym = (file_id: number, name: string, kind: Analysis['symbols'][number]['kind']) =>
  ({ file_id, name, kind, width: 1, range });
const analysis = (symbols: Analysis['symbols'], files = [{ file_id: 0, path: '/playground/main.circ' }]): Analysis =>
  ({ files, diagnostics: [], symbols, references: [] });
const files = [{ name: 'main.circ', body: 'input a\nnot n(in=a)\noutput out(in=n.out)\n' }];

describe('footer-summary', () => {
  test('lines count a trailing newline once', () => {
    expect(lineCount('')).toBe(1);
    expect(lineCount('a')).toBe(1);
    expect(lineCount('a\nb')).toBe(2);
    expect(lineCount('a\nb\n')).toBe(2);
    expect(summarize([{ name: 'a', body: 'x\n' }, { name: 'b', body: 'y\nz' }], null, []).lines).toBe(3);
  });

  test('counts and words', () => {
    const e = { severity: 'error' as const };
    const w = { severity: 'warning' as const };
    expect(summaryLabels(summarize(files, null, [w]))[0]).toBe('0 errors · 1 warning');
    expect(summaryLabels(summarize(files, null, [e]))[0]).toBe('1 error · 0 warnings');
    expect(summaryLabels(summarize(files, null, [e, e, w, w, w]))[0]).toBe('2 errors · 3 warnings');
  });

  test('before an analysis', () => {
    const s = summarize(files, null, []);
    expect(s.components).toBeNull();
    expect(s.extra).toBeNull();
    expect(summaryLabels(s)[1]).toBe('3 lines');
  });

  test('the third slot', () => {
    // A plain circuit counts its pins, and components are everything else.
    const plain = summarize(files, analysis([sym(0, 'a', 'input'), sym(0, 'n', 'not'), sym(0, 'out', 'output')]), []);
    expect(plain.components).toBe(1);
    expect(plain.extra).toEqual({ count: 2, noun: 'pin' });
    expect(summaryLabels(plain)[1]).toBe('3 lines · 1 component · 2 pins');
    // Chips outrank pins.
    const chips = summarize(files, analysis([sym(0, 'a', 'input'), sym(0, 'h1', 'instance'), sym(0, 'h2', 'instance'), sym(0, 'g', 'and')]), []);
    expect(chips.extra).toEqual({ count: 2, noun: 'chip' });
    expect(summaryLabels(chips)[1]).toBe('3 lines · 3 components · 2 chips');
    // A memory outranks both, and pluralises its own way.
    const mem = summarize(files, analysis([sym(0, 'code', 'rom'), sym(0, 'h', 'instance'), sym(0, 'a', 'input')]), []);
    expect(mem.extra).toEqual({ count: 1, noun: 'memory' });
    expect(summaryLabels(mem)[1]).toBe('3 lines · 2 components · 1 memory');
    expect(summaryLabels(summarize(files, analysis([sym(0, 'r', 'rom'), sym(0, 'm', 'ram')]), []))[1]).toBe('3 lines · 2 components · 2 memories');
  });

  test('a builtin file never counts', () => {
    const a = analysis(
      [sym(0, 'a', 'input'), sym(1, 'x', 'instance'), sym(1, 'y', 'rom')],
      [{ file_id: 0, path: '/playground/main.circ' }, { file_id: 1, path: '<builtin>/xor.circ' }],
    );
    const s = summarize(files, a, []);
    expect(s.components).toBe(0);
    expect(s.extra).toEqual({ count: 1, noun: 'pin' });
  });
});
