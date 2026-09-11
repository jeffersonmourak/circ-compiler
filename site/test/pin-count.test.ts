// The Data button's `N → M`: the root's pins, not its bits.
import { describe, expect, test } from 'bun:test';
import { pinCountLabel } from '../src/scripts/pin-count.ts';
import type { AnalyzeSymbol } from '../src/scripts/circ-diagnostics.ts';

const range = { start_line: 1, start_col: 1, end_line: 1, end_col: 2 } as unknown as AnalyzeSymbol['range'];
const sym = (file_id: number, name: string, kind: AnalyzeSymbol['kind'], width = 1): AnalyzeSymbol => ({ file_id, name, kind, width, range });

describe('pin count', () => {
  test('pinCountLabel counts root pins, not bits', () => {
    const symbols = [sym(0, 'a', 'input'), sym(0, 'b', 'input', 4), sym(0, 'out', 'output', 4), sym(0, 'g', 'and'), sym(1, 'x', 'input')];
    expect(pinCountLabel(symbols, 0)).toBe('2 → 1');
    expect(pinCountLabel(symbols, 1)).toBe('1 → 0');
    expect(pinCountLabel(symbols, null)).toBe('');
    expect(pinCountLabel([], 0)).toBe('0 → 0');
  });
});
