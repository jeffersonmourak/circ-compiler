import { describe, expect, test } from 'bun:test';
import { byteColToUtf16, caretOffset } from '../src/utils/columns.ts';

describe('columns', () => {
  test('byteColToUtf16 is identity for ASCII', () => {
    expect(byteColToUtf16('input a', 7)).toBe(7);
    expect(byteColToUtf16('input a', 1)).toBe(1);
  });

  test('byteColToUtf16 collapses multibyte prefixes', () => {
    expect(byteColToUtf16('éé x', 5)).toBe(3); // two 2-byte chars = 4 bytes, 2 units
    expect(byteColToUtf16('😀x', 5)).toBe(3); // one 4-byte char = 2 units
    expect(byteColToUtf16('ab', 10)).toBe(3); // past the end clamps to length + 1
  });

  test('caretOffset sums UTF-16 line lengths', () => {
    expect(caretOffset('ab\ncé\nx', 2, 1)).toBe(6);
    expect(caretOffset('ab\ncé\nx', 1, 2)).toBe(4);
    expect(caretOffset('ab', 0, 9)).toBe(2);
  });
});
