// ROM images: what a reader types, and what the compiler and the runtime will
// accept.
//
// The wire format is a headerless raw image of little-endian words, ceil(W/8)
// bytes per word — the same bytes the CLI reads from a file, so an assembler's
// output pastes in unchanged. The validator mirrors the compiler's own, in the
// same order, so the page refuses exactly what the library would refuse and
// says so before a request is spent.
//
// Every failure is a value. A malformed image is a thing a reader typed, not a
// bug, and it must never reach a throw.
import type { AnalyzeSymbol } from '../scripts/circ-diagnostics.ts';

/** Topology kind bytes for the two memory kinds. Inlined rather than imported:
 *  the renderer is loaded lazily, and a static import here would drag it into
 *  the playground's eager bundle. */
export const ROM_KIND = 8;
export const RAM_KIND = 9;

export interface MemorySymbol {
  name: string;
  kind: 'rom' | 'ram';
  /** W, the data width, 1..64. */
  width: number;
  /** A, the address width, 1..16. */
  addrWidth: number;
}

/** ceil(W / 8) — one word's byte count. */
export const bytesPerWord = (width: number): number => (width + 7) >> 3;

/** 2^A — how many words the address space holds. */
export const maxWords = (addrWidth: number): number => 2 ** addrWidth;

/**
 * The root file's memories, in analyze order.
 *
 * A rom or ram without an address width is dropped rather than guessed: the
 * width pair is what every bound below is computed from. The root file id
 * comes from the caller, which already resolved it — there is no second
 * root-file lookup in this codebase.
 */
export function romSymbols(
  symbols: readonly AnalyzeSymbol[],
  rootFileId: number | null,
): MemorySymbol[] {
  if (rootFileId === null) return [];
  const out: MemorySymbol[] = [];
  for (const s of symbols) {
    if (s.file_id !== rootFileId) continue;
    if (s.kind !== 'rom' && s.kind !== 'ram') continue;
    if (typeof s.addr_width !== 'number' || !s.name) continue;
    out.push({ name: s.name, kind: s.kind, width: s.width, addrWidth: s.addr_width });
  }
  return out;
}

export type RomImageError =
  | { kind: 'bad_char'; index: number; char: string }
  | { kind: 'odd_token'; token: string; index: number }
  | { kind: 'not_word_multiple'; bytes: number; bytesPerWord: number }
  | { kind: 'too_many_words'; words: number; capacity: number }
  | { kind: 'word_exceeds_width'; word: number; dataWidth: number };

export type RomImageResult =
  | { ok: true; bytes: Uint8Array; words: number; hex: string }
  | { ok: false; error: RomImageError; message: string };

export function describeRomError(e: RomImageError): string {
  switch (e.kind) {
    case 'bad_char':
      return `'${e.char}' is not a hex digit (at character ${e.index + 1}).`;
    case 'odd_token':
      return `'${e.token}' has an odd number of digits; a byte needs two.`;
    case 'not_word_multiple':
      return `${e.bytes} bytes is not a whole number of ${e.bytesPerWord}-byte words.`;
    case 'too_many_words':
      return `${e.words} words exceed this memory's capacity of ${e.capacity}.`;
    case 'word_exceeds_width':
      return `The word 0x${e.word.toString(16)} does not fit in ${e.dataWidth} bits.`;
  }
}

/** Read one little-endian word out of the image. */
function readWord(bytes: Uint8Array, index: number, bpw: number): bigint {
  let word = 0n;
  for (let k = 0; k < bpw; k += 1) word |= BigInt(bytes[index * bpw + k]) << BigInt(8 * k);
  return word;
}

const HEX = /^[0-9a-fA-F]+$/;

/**
 * Parse a reader's hex text and validate it against a memory's shape.
 *
 * The text is tolerant — whitespace, newlines, commas, `0x` prefixes and `//`
 * or `#` comments are all allowed — because it is pasted from many places. The
 * validation is not: it checks the same three things the compiler checks, in
 * the same order, so a page that accepts an image is one the library will too.
 */
export function parseRomImage(text: string, mem: MemorySymbol): RomImageResult {
  const stripped = text
    .replace(/\/\/[^\n]*/g, ' ')
    .replace(/#[^\n]*/g, ' ')
    .replace(/,/g, ' ');

  const bytes: number[] = [];
  const tokenRe = /\S+/g;
  for (let m = tokenRe.exec(stripped); m; m = tokenRe.exec(stripped)) {
    let token = m[0];
    if (token.startsWith('0x') || token.startsWith('0X')) token = token.slice(2);
    if (token === '') continue;
    if (!HEX.test(token)) {
      const badIndex = [...token].findIndex((c) => !HEX.test(c));
      return {
        ok: false,
        error: { kind: 'bad_char', index: m.index + badIndex, char: token[badIndex] },
        message: describeRomError({ kind: 'bad_char', index: m.index + badIndex, char: token[badIndex] }),
      };
    }
    if (token.length % 2 !== 0) {
      const error: RomImageError = { kind: 'odd_token', token, index: m.index };
      return { ok: false, error, message: describeRomError(error) };
    }
    for (let i = 0; i < token.length; i += 2) bytes.push(Number.parseInt(token.slice(i, i + 2), 16));
  }

  const bpw = bytesPerWord(mem.width);
  // The compiler's order: whole words, then capacity, then the width of each.
  if (bytes.length % bpw !== 0) {
    const error: RomImageError = { kind: 'not_word_multiple', bytes: bytes.length, bytesPerWord: bpw };
    return { ok: false, error, message: describeRomError(error) };
  }
  const words = bytes.length / bpw;
  const capacity = maxWords(mem.addrWidth);
  if (words > capacity) {
    const error: RomImageError = { kind: 'too_many_words', words, capacity };
    return { ok: false, error, message: describeRomError(error) };
  }
  const out = new Uint8Array(bytes);
  const mask = mem.width >= 64 ? (1n << 64n) - 1n : (1n << BigInt(mem.width)) - 1n;
  for (let i = 0; i < words; i += 1) {
    const word = readWord(out, i, bpw);
    if ((word & ~mask) !== 0n) {
      const error: RomImageError = {
        kind: 'word_exceeds_width',
        word: Number(word),
        dataWidth: mem.width,
      };
      return { ok: false, error, message: describeRomError(error) };
    }
  }

  const hex = Array.from(out, (b) => b.toString(16).padStart(2, '0')).join('');
  return { ok: true, bytes: out, words, hex };
}

// ---------------------------------------------------------------------------
// Getting an image into a running circuit.
// ---------------------------------------------------------------------------

/** name → the reader's raw text, exactly as typed. */
export type RomImageMap = ReadonlyMap<string, string>;

export interface RomWrite {
  name: string;
  /** Null clears the memory: an empty image is a legal instruction, not a
   *  missing one. */
  bytes: Uint8Array | null;
}

export interface RomPlan {
  writes: RomWrite[];
  /** name → message, for images that no longer validate. */
  errors: Map<string, string>;
}

/**
 * What to write, re-derived from the CURRENT declarations.
 *
 * The reader's text is re-parsed rather than cached as bytes, so changing
 * `rom code[8, 4]` to `rom code[16, 4]` re-validates the same text against the
 * new shape instead of writing stale bytes into a memory that has changed
 * underneath it. A name that is no longer a declared rom is skipped, and its
 * text is kept by the caller — restoring the declaration restores the image.
 */
export function romPlan(images: RomImageMap, roms: readonly MemorySymbol[]): RomPlan {
  const writes: RomWrite[] = [];
  const errors = new Map<string, string>();
  for (const mem of roms) {
    if (mem.kind !== 'rom') continue; // a ram is driven by the circuit, not by us
    const text = images.get(mem.name);
    if (text === undefined) continue;
    const parsed = parseRomImage(text, mem);
    if (!parsed.ok) {
      errors.set(mem.name, parsed.message);
      continue;
    }
    writes.push({ name: mem.name, bytes: parsed.words === 0 ? null : parsed.bytes });
  }
  return { writes, errors };
}

/** name → canonical hex, for the request's preloads. Roms only. */
export function preloadsFor(images: RomImageMap, roms: readonly MemorySymbol[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const { name, bytes } of romPlan(images, roms).writes) {
    out[name] = bytes === null ? '' : Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  }
  return out;
}

/**
 * The slice of circ-renderer's `CircRuntime` a memory needs.
 *
 * Structural rather than imported, so this module pulls no renderer code
 * into the playground's eager bundle and a test can hand it a fake. The
 * renderer owns the eight raw exports, the packed shape word and the
 * staging-buffer dance; nothing here reaches past these three calls.
 */
export interface MemoryRuntime {
  memories(): readonly {
    id: number;
    name: string;
    info: { kind: 'rom' | 'ram'; width: number; addrWidth: number };
  }[];
  /** `0` on success; the runtime's own code otherwise. */
  loadMemImage(id: number, bytes: Uint8Array): number;
  clearMem(id: number): number;
}

export interface ApplyResult {
  applied: string[];
  errors: Map<string, string>;
}

/**
 * Write every planned image into a running circuit.
 *
 * The join is by declared name, against what the RUNTIME says it has: a name
 * the runtime does not confirm, or one whose shape differs from what the
 * analysis validated the image against, is refused — the artifact and the
 * analysis have drifted apart, and writing to the wrong memory is worse than
 * not writing at all.
 */
export function applyRomImages(
  runtime: MemoryRuntime,
  plan: RomPlan,
  roms: readonly MemorySymbol[],
): ApplyResult {
  const applied: string[] = [];
  const errors = new Map(plan.errors);
  const found = new Map(runtime.memories().map((m) => [m.name, m]));

  for (const write of plan.writes) {
    const target = found.get(write.name);
    if (!target) {
      errors.set(write.name, `${write.name} is not in the compiled circuit.`);
      continue;
    }
    const mem = roms.find((m) => m.name === write.name);
    if (!mem || target.info.width !== mem.width || target.info.addrWidth !== mem.addrWidth) {
      errors.set(write.name, `${write.name} does not match the compiled circuit; not loaded.`);
      continue;
    }
    const rc = write.bytes === null ? runtime.clearMem(target.id) : runtime.loadMemImage(target.id, write.bytes);
    if (rc !== 0) {
      errors.set(write.name, `${write.name} was refused by the runtime (code ${rc}).`);
      continue;
    }
    applied.push(write.name);
  }
  return { applied, errors };
}

