// A download's file name comes from the project's label, and a label is text
// the reader typed: it has to come out as something every file system takes.
import { describe, expect, test } from 'bun:test';
import { artifactFileName } from '../src/utils/artifact-name.ts';

describe('artifactFileName', () => {
  test('a label becomes a lower-case dashed stem with the extension', () => {
    expect(artifactFileName('Half adder')).toBe('half-adder.wasm');
    expect(artifactFileName('4-bit ripple-carry adder')).toBe('4-bit-ripple-carry-adder.wasm');
    expect(artifactFileName('Brave Otter')).toBe('brave-otter.wasm');
  });

  test('punctuation, slashes and spaces collapse to single dashes and never lead or trail', () => {
    expect(artifactFileName('  a/b\\c: d?  ')).toBe('a-b-c-d.wasm');
    expect(artifactFileName('--x--')).toBe('x.wasm');
    expect(artifactFileName('rom: lookup (v2)')).toBe('rom-lookup-v2.wasm');
  });

  test('accents are folded rather than dropped', () => {
    expect(artifactFileName('Décodeur à 3 bits')).toBe('decodeur-a-3-bits.wasm');
  });

  test('nothing usable falls back to circuit, and a very long label is cut', () => {
    expect(artifactFileName('')).toBe('circuit.wasm');
    expect(artifactFileName('???')).toBe('circuit.wasm');
    expect(artifactFileName('🙂')).toBe('circuit.wasm');
    const long = artifactFileName('a'.repeat(200));
    expect(long.length).toBeLessThanOrEqual(64 + '.wasm'.length);
    expect(long.endsWith('.wasm')).toBe(true);
  });

  test('the extension is the caller\'s', () => {
    expect(artifactFileName('Half adder', '.circ')).toBe('half-adder.circ');
  });
});
