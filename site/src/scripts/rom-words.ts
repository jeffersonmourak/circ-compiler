// A ROM image, edited one word at a time.
//
// The image format is a byte stream and nothing else: word `i` is the bytes
// `[i * bpw, (i + 1) * bpw)`, little-endian. It has no way to say "this word
// is unknown", so an image is always a PREFIX of the memory — a short one
// leaves the tail undefined and can leave nothing else undefined.
//
// That single fact drives everything here. Writing word 5 of an empty rom
// cannot leave words 0 through 4 unknown, because the format cannot express
// it. They come into existence as zeros, and this module reports which ones
// so the grid can mark them as the reader's own or as the format's doing.
//
// Pure, DOM-free, and the only place that rule is written down.

import { bytesPerWord, maxWords, parseRomImage, type MemorySymbol } from '../utils/rom-image.ts';

/** Addresses that hold a zero the reader never typed. Not derivable from the
 *  image, which cannot tell a chosen zero from a filled gap, so it is carried
 *  beside it. */
export type Implied = ReadonlySet<number>;

export interface RomEdit {
  /** Canonical lowercase hex, two digits per byte, no separators. */
  text: string;
  implied: Implied;
}

export type EditResult = { ok: true; edit: RomEdit } | { ok: false; message: string };

const mask = (width: number): bigint => (1n << BigInt(width)) - 1n;

/** The words an image holds, or why it cannot be read. A word past the end of
 *  the image is not in this array: the array's length IS the image's length. */
export function wordsOf(text: string, mem: MemorySymbol): { ok: true; words: bigint[] } | { ok: false; message: string } {
  const parsed = parseRomImage(text, mem);
  if (!parsed.ok) return { ok: false, message: parsed.message };
  const bpw = bytesPerWord(mem.width);
  const words: bigint[] = [];
  for (let i = 0; i < parsed.words; i += 1) {
    let word = 0n;
    for (let b = bpw - 1; b >= 0; b -= 1) word = (word << 8n) | BigInt(parsed.bytes[i * bpw + b]);
    words.push(word & mask(mem.width));
  }
  return { ok: true, words };
}

/** Words back to canonical image text. Little-endian, `bpw` bytes each. */
export function imageOf(words: readonly bigint[], mem: MemorySymbol): string {
  const bpw = bytesPerWord(mem.width);
  const bytes = new Uint8Array(words.length * bpw);
  words.forEach((word, i) => {
    let w = word & mask(mem.width);
    for (let b = 0; b < bpw; b += 1) {
      bytes[i * bpw + b] = Number(w & 0xffn);
      w >>= 8n;
    }
  });
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** Drop trailing addresses from `implied` once the image has shrunk past them. */
function trim(implied: Implied, length: number): Set<number> {
  const out = new Set<number>();
  for (const addr of implied) if (addr < length) out.add(addr);
  return out;
}

/**
 * Write one word, or make one unknown, and report what the format forced.
 *
 * `value === null` means "make this word unknown again". At the end of the
 * image that shortens it, taking any filled gap that was only there to reach
 * the removed word with it. In the MIDDLE it cannot shorten anything, so the
 * word becomes a zero the reader did not choose and is marked implied — the
 * one honest answer when the format has no hole to offer.
 */
export function editWord(
  text: string,
  implied: Implied,
  mem: MemorySymbol,
  addr: number,
  value: bigint | null,
): EditResult {
  const capacity = maxWords(mem.addrWidth);
  if (!Number.isInteger(addr) || addr < 0 || addr >= capacity) {
    return { ok: false, message: `${addr} is not an address in ${mem.name}.` };
  }
  const read = wordsOf(text, mem);
  if (!read.ok) return { ok: false, message: `The current image cannot be read: ${read.message}` };
  const words = read.words;
  const next = new Set(implied);

  if (value === null) {
    if (addr >= words.length) return { ok: true, edit: { text: imageOf(words, mem), implied: trim(next, words.length) } };
    if (addr === words.length - 1) {
      // Shorten, then keep shortening while the new last word is only there
      // because the removed one needed reaching.
      let end = addr;
      while (end > 0 && next.has(end - 1)) end -= 1;
      const kept = words.slice(0, end);
      return { ok: true, edit: { text: imageOf(kept, mem), implied: trim(next, kept.length) } };
    }
    words[addr] = 0n;
    next.add(addr);
    return { ok: true, edit: { text: imageOf(words, mem), implied: trim(next, words.length) } };
  }

  if (value < 0n || value > mask(mem.width)) {
    return { ok: false, message: `Too large for ${mem.width} bit${mem.width === 1 ? '' : 's'}.` };
  }
  // Reaching past the end fills the gap, and every filled word is the format's
  // doing rather than the reader's.
  for (let i = words.length; i < addr; i += 1) {
    words.push(0n);
    next.add(i);
  }
  if (addr < words.length) words[addr] = value;
  else words.push(value);
  next.delete(addr);
  return { ok: true, edit: { text: imageOf(words, mem), implied: trim(next, words.length) } };
}

/** Every word an image holds, padded to the memory's capacity with nulls for
 *  the addresses it does not reach. What the grid draws when nothing is
 *  running. */
export function imageCells(
  text: string,
  mem: MemorySymbol,
): { ok: true; cells: (bigint | null)[] } | { ok: false; message: string } {
  const read = wordsOf(text, mem);
  if (!read.ok) return read;
  const cells: (bigint | null)[] = new Array(maxWords(mem.addrWidth)).fill(null);
  read.words.forEach((w, i) => { cells[i] = w; });
  return { ok: true, cells };
}

/** Hex text for a binary file the reader loaded, or why it will not fit. */
export function imageFromBytes(bytes: Uint8Array, mem: MemorySymbol): { ok: true; text: string } | { ok: false; message: string } {
  const bpw = bytesPerWord(mem.width);
  const capacity = maxWords(mem.addrWidth) * bpw;
  if (bytes.length > capacity) {
    return {
      ok: false,
      message: `That file is ${bytes.length} bytes; ${mem.name} holds ${capacity}.`,
    };
  }
  if (bytes.length % bpw !== 0) {
    return {
      ok: false,
      message: `That file is ${bytes.length} bytes, which is not a whole number of ${bpw}-byte words.`,
    };
  }
  const text = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  // The same validator the typed path uses, so a file cannot get in through a
  // door the textarea is not allowed through.
  const check = parseRomImage(text, mem);
  if (!check.ok) return { ok: false, message: check.message };
  return { ok: true, text };
}
