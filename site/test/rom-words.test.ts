// Editing a ROM image one word at a time.
//
// Every test here is really about one fact: the image format is a byte stream
// with no way to say "unknown", so an image is a PREFIX. Writing word 5 of an
// empty rom cannot leave words 0 through 4 unknown, and this module is where
// what happens instead is decided and written down.
import { describe, expect, test } from 'bun:test';
import {
  editWord,
  imageCells,
  imageFromBytes,
  imageOf,
  wordsOf,
} from '../src/scripts/rom-words.ts';
import type { MemorySymbol } from '../src/utils/rom-image.ts';

/** The shape both shipped memory examples declare. */
const mem = (over: Partial<MemorySymbol> = {}): MemorySymbol => ({
  name: 'code',
  kind: 'rom',
  width: 8,
  addrWidth: 4,
  ...over,
});

/** Apply a sequence of edits, failing loudly on the first refusal. */
function apply(mem_: MemorySymbol, steps: [number, bigint | null][], from = '') {
  let text = from;
  let implied: ReadonlySet<number> = new Set();
  for (const [addr, value] of steps) {
    const r = editWord(text, implied, mem_, addr, value);
    expect(r.ok ? 'ok' : `refused: ${!r.ok && r.message}`).toBe('ok');
    if (!r.ok) throw new Error(r.message);
    text = r.edit.text;
    implied = r.edit.implied;
  }
  return { text, implied: [...implied].sort((a, b) => a - b) };
}

describe('wordsOf and imageOf', () => {
  test('round-trip a one-byte-per-word image', () => {
    const r = wordsOf('deadbeef', mem());
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.words).toEqual([0xden, 0xadn, 0xben, 0xefn]);
    expect(imageOf(r.words, mem())).toBe('deadbeef');
  });

  test('a wider word is little-endian across its bytes', () => {
    // 12 bits is two bytes per word, low byte first, top four bits zero.
    const m = mem({ width: 12, addrWidth: 4 });
    expect(imageOf([0x123n], m)).toBe('2301');
    const back = wordsOf('2301', m);
    expect(back.ok && back.words).toEqual([0x123n]);
  });

  test('the array length is the image length, not the capacity', () => {
    const r = wordsOf('0102', mem());
    // Two words written into a sixteen-word memory.
    expect(r.ok && r.words.length).toBe(2);
  });

  test('an unreadable image is a message rather than a throw', () => {
    const r = wordsOf('zz', mem());
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.message.length).toBeGreaterThan(0);
  });

  test('the full 64-bit word survives the round trip', () => {
    const m = mem({ width: 64, addrWidth: 1 });
    const all = (1n << 64n) - 1n;
    expect(imageOf([all], m)).toBe('ffffffffffffffff');
    expect(wordsOf('ffffffffffffffff', m)).toEqual({ ok: true, words: [all] });
  });
});

describe('editWord — writing', () => {
  test('writing into an empty image starts it at that word', () => {
    expect(apply(mem(), [[0, 0xa5n]])).toEqual({ text: 'a5', implied: [] });
  });

  test('writing past the end fills the gap, and says which words it filled', () => {
    // This is the prefix rule. Words 0 through 4 cannot stay unknown, so they
    // become zeros — and they are the format's doing, not the reader's.
    const r = apply(mem(), [[5, 0x7fn]]);
    expect(r.text).toBe('00000000007f');
    expect(r.implied).toEqual([0, 1, 2, 3, 4]);
  });

  test('filling an implied word by hand stops it being implied', () => {
    const r = apply(mem(), [[3, 0x11n], [1, 0x22n]]);
    expect(r.text).toBe('00220011');
    // 0 and 2 are still the format's; 1 is now the reader's.
    expect(r.implied).toEqual([0, 2]);
  });

  test('overwriting a word inside the image changes nothing else', () => {
    const r = apply(mem(), [[0, 1n], [1, 2n], [2, 3n], [1, 0xffn]]);
    expect(r.text).toBe('01ff03');
    expect(r.implied).toEqual([]);
  });

  test('a word too wide for the memory is refused', () => {
    const r = editWord('', new Set(), mem(), 0, 0x100n);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.message).toContain('8 bits');
  });

  test('an address outside the memory is refused', () => {
    for (const addr of [-1, 16, 1.5]) {
      const r = editWord('', new Set(), mem(), addr, 1n);
      expect(r.ok).toBe(false);
    }
    expect(editWord('', new Set(), mem(), 15, 1n).ok).toBe(true);
  });

  test('an image that cannot be read refuses the edit rather than discarding it', () => {
    const r = editWord('zz', new Set(), mem(), 0, 1n);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.message).toContain('cannot be read');
  });
});

describe('editWord — making a word unknown', () => {
  test('at the end, the image shortens', () => {
    const r = apply(mem(), [[0, 1n], [1, 2n], [2, 3n], [2, null]]);
    expect(r.text).toBe('0102');
  });

  test('shortening takes the gap that only existed to reach it', () => {
    // Words 0..4 exist only because word 5 was written. Removing word 5 leaves
    // them with no reason to be there, so they go too.
    const first = apply(mem(), [[5, 0x7fn]]);
    expect(first.implied).toEqual([0, 1, 2, 3, 4]);
    const r = apply(mem(), [[5, 0x7fn], [5, null]]);
    expect(r.text).toBe('');
    expect(r.implied).toEqual([]);
  });

  test('shortening stops at a word the reader chose', () => {
    const r = apply(mem(), [[0, 0xaan], [5, 0x7fn], [5, null]]);
    // Word 0 was typed, so it stays; 1 through 4 were filler and go.
    expect(r.text).toBe('aa');
    expect(r.implied).toEqual([]);
  });

  test('in the middle it becomes an implied zero, since the format has no hole', () => {
    const r = apply(mem(), [[0, 1n], [1, 2n], [2, 3n], [1, null]]);
    expect(r.text).toBe('010003');
    expect(r.implied).toEqual([1]);
  });

  test('past the end it is already unknown and nothing changes', () => {
    const r = apply(mem(), [[0, 1n], [9, null]]);
    expect(r.text).toBe('01');
    expect(r.implied).toEqual([]);
  });

  test('emptying the last word of a one-word image empties the image', () => {
    const r = apply(mem(), [[0, 1n], [0, null]]);
    expect(r.text).toBe('');
  });
});

describe('imageCells', () => {
  test('pads to the memory capacity with nulls for what the image does not reach', () => {
    const r = imageCells('0102', mem());
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.cells).toHaveLength(16);
    expect(r.cells.slice(0, 3)).toEqual([1n, 2n, null]);
    // Everything past the image is unknown, which is not the same as zero.
    expect(r.cells.slice(2).every((c) => c === null)).toBe(true);
  });

  test('an empty image is all unknown', () => {
    const r = imageCells('', mem());
    expect(r.ok && r.cells.every((c) => c === null)).toBe(true);
  });

  test('a full image reaches every address', () => {
    const r = imageCells('ff'.repeat(16), mem());
    expect(r.ok && r.cells.every((c) => c === 0xffn)).toBe(true);
  });
});

describe('imageFromBytes', () => {
  test('a file that fits becomes canonical hex', () => {
    expect(imageFromBytes(new Uint8Array([0xde, 0xad]), mem())).toEqual({ ok: true, text: 'dead' });
  });

  test('a file larger than the memory is refused with both sizes', () => {
    const r = imageFromBytes(new Uint8Array(17), mem());
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.message).toContain('17');
      expect(r.message).toContain('16');
    }
  });

  test('a file that is not a whole number of words is refused', () => {
    // Three bytes into a two-byte-per-word memory.
    const r = imageFromBytes(new Uint8Array(3), mem({ width: 12 }));
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.message).toContain('2-byte words');
  });

  test('an empty file is a legal image that clears the memory', () => {
    expect(imageFromBytes(new Uint8Array(0), mem())).toEqual({ ok: true, text: '' });
  });

  test('a file goes through the same validator the textarea does', () => {
    // Bits above the declared width are refused from a file exactly as they
    // are from typed hex; a file must not have a door of its own.
    const r = imageFromBytes(new Uint8Array([0xff]), mem({ width: 4 }));
    expect(r.ok).toBe(false);
  });
});
