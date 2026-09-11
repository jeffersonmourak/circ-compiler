import { describe, expect, test } from 'bun:test';
import { pinLine, pinLineParts, rootPins, type PinRecord } from '../src/scripts/pin-line.ts';

const bit = (name: string, kind: PinRecord['kind'], value: bigint, defined = 1n): PinRecord => ({
  name,
  kind,
  value: { value, defined, width: 1 },
});

describe('rootPins', () => {
  test('keeps the root pins, inputs then outputs, in declaration order', () => {
    const topology = {
      components: [
        { id: 7, kind: 50, name: 'sum', origin: [] },
        { id: 8, kind: 40, name: 'nested', origin: [{}] },
        { id: 9, kind: 99, name: 'gate', origin: [] },
        { id: 10, kind: 40, name: 'a', origin: [] },
      ],
    };
    const pins = rootPins(
      topology,
      (id) => ({ value: BigInt(id), defined: 1n, width: 1 }),
      { input: 40, output: 50 },
    );
    expect(pins).toEqual([
      { name: 'a', kind: 'in', value: { value: 10n, defined: 1n, width: 1 } },
      { name: 'sum', kind: 'out', value: { value: 7n, defined: 1n, width: 1 } },
    ]);
  });
});

describe('pinLine', () => {
  test('spells a bit as its digit and a bus in the base', () => {
    const bits = [bit('a', 'in', 1n), bit('b', 'in', 0n), bit('sum', 'out', 1n), bit('carry', 'out', 0n)];
    expect(pinLine(bits, 'hex')).toBe('a = 1 · b = 0 → sum = 1 · carry = 0');

    const bus: PinRecord[] = [{ name: 'word', kind: 'out', value: { value: 6n, defined: 15n, width: 4 } }];
    expect(pinLine(bus, 'hex')).toBe('word = 0x6');
    expect(pinLine(bus, 'binary')).toBe('word = 0b0110');
    expect(pinLine(bus, 'decimal')).toBe('word = 6');
  });

  test('an undefined bit is a question mark', () => {
    const pins = [
      bit('a', 'in', 1n),
      { name: 'word', kind: 'out' as const, value: { value: 5n, defined: 5n, width: 4 } },
    ];
    expect(pinLine(pins, 'hex')).toBe('a = 1 → word = ?');
  });

  test('no outputs drops the arrow, no pins is empty', () => {
    expect(pinLine([bit('a', 'in', 0n), bit('b', 'in', 0n)])).toBe('a = 0 · b = 0');
    expect(pinLine([bit('sum', 'out', 0n)])).toBe('sum = 0');
    expect(pinLine([])).toBe('');
  });

  test('pinLineParts marks every name', () => {
    const pins = [bit('a', 'in', 1n), bit('sum', 'out', 1n)];
    const parts = pinLineParts(pins);
    expect(parts.map((part) => part.text).join('')).toBe(pinLine(pins));
    expect(parts.filter((part) => part.name)).toEqual([
      { text: 'a', name: true },
      { text: 'sum', name: true },
    ]);
  });
});
