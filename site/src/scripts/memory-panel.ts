// Reading and writing one memory's cells, as data.
//
// A `rom` or `ram` holds its contents as runtime state rather than in the
// artifact, so everything a reader sees here is read back from a running
// circuit one word at a time. This module is the part of that with no runtime
// in it: how a word is written down, which words are on screen, and what a
// typed word means. `bun test` drives all of it.
//
// Definedness is the thing to get right. A cell carries `(value, defined)` as
// two bit vectors, and the honest rendering of a half-known word is neither
// its value nor a blank — it is the bits that are known and a mark where the
// others are. Every formatter below preserves that distinction.

import { maxWords } from '../utils/rom-image.ts';

export type ValueFormat = 'binary' | 'hex' | 'decimal';

/** One cell, exactly as the two getters return it. */
export interface Cell {
  value: bigint;
  defined: bigint;
}

/** All-ones for `width` bits. Widths run 1..64, so bigint is required. */
export const maskFor = (width: number): bigint => (1n << BigInt(width)) - 1n;

/** What a cell with no known bits is written as, everywhere. */
export const UNKNOWN = '?';

/**
 * One word as the reader sees it.
 *
 * Fully undefined is `?`. Fully defined follows the chosen format. A
 * PARTIALLY defined word ignores the chosen format and is written in binary
 * with `x` for each unknown bit: there is no honest hex digit for four bits of
 * which two are unknown, and rounding one out would state something the
 * simulation never said.
 */
export function formatWord(cell: Cell, width: number, format: ValueFormat): string {
  const mask = maskFor(width);
  const defined = cell.defined & mask;
  // The runtime canonicalises to `value & defined`; do it again rather than
  // trust it, so a stray bit above the mask cannot reach the screen.
  const value = cell.value & defined;

  if (defined === 0n) return UNKNOWN;
  if (defined !== mask) {
    let out = '';
    for (let bit = width - 1; bit >= 0; bit -= 1) {
      const at = 1n << BigInt(bit);
      out += (defined & at) === 0n ? 'x' : (value & at) === 0n ? '0' : '1';
    }
    return out;
  }

  switch (format) {
    case 'binary':
      return value.toString(2).padStart(width, '0');
    case 'hex':
      return value.toString(16).padStart(Math.ceil(width / 4), '0');
    case 'decimal':
      return value.toString(10);
  }
}

/** How wide a cell can get, so the table can reserve a column width without
 *  measuring text. Partial words are binary, which is the widest case. */
export function cellWidth(width: number, format: ValueFormat): number {
  const full = format === 'hex' ? Math.ceil(width / 4) : format === 'decimal' ? `${maskFor(width)}`.length : width;
  // A partially defined word always renders as `width` characters.
  return Math.max(full, width);
}

// ---------------------------------------------------------------------------
// Which words are on screen.
// ---------------------------------------------------------------------------

export interface AddressWindow {
  start: number;
  count: number;
}

/**
 * A window inside `0..total`, clamped so it can never run past either end.
 *
 * A memory may declare 16 address bits — 65,536 words — and reading every one
 * of them across the wasm boundary on each repaint would stall the page. Only
 * what is visible is ever read, which is what makes this module's job paging
 * rather than dumping.
 */
export function clampWindow(start: number, count: number, total: number): AddressWindow {
  const size = Math.max(1, Math.min(count, total));
  if (total <= 0) return { start: 0, count: 0 };
  const first = Math.max(0, Math.min(Math.floor(start), total - size));
  return { start: first, count: size };
}

/** The window of `count` words that contains `addr`, aligned to a page
 *  boundary so paging back and forth is stable rather than drifting. */
export function pageContaining(addr: number, count: number, total: number): AddressWindow {
  const size = Math.max(1, count);
  const page = Math.floor(Math.max(0, addr) / size) * size;
  return clampWindow(page, size, total);
}

export function pageCount(count: number, total: number): number {
  const size = Math.max(1, count);
  return Math.max(1, Math.ceil(total / size));
}

export interface DumpCell {
  addr: number;
  text: string;
  /** False when no bit of the word is known — the table dims those. */
  known: boolean;
}

export interface DumpRow {
  base: number;
  cells: DumpCell[];
}

/**
 * The visible words, in rows.
 *
 * `read` is called exactly once per visible address and never for anything
 * outside the window — the whole point of the paging above.
 */
export function dumpRows(
  read: (addr: number) => Cell,
  window: AddressWindow,
  perRow: number,
  width: number,
  format: ValueFormat,
): DumpRow[] {
  const rows: DumpRow[] = [];
  const stride = Math.max(1, perRow);
  for (let offset = 0; offset < window.count; offset += stride) {
    const base = window.start + offset;
    const cells: DumpCell[] = [];
    for (let i = 0; i < stride && offset + i < window.count; i += 1) {
      const addr = base + i;
      const cell = read(addr);
      cells.push({
        addr,
        text: formatWord(cell, width, format),
        known: (cell.defined & maskFor(width)) !== 0n,
      });
    }
    rows.push({ base, cells });
  }
  return rows;
}

/** Addresses are always shown in hex, whatever the value format: an address is
 *  a position, and a position lines up on a page boundary legibly in hex and
 *  nowhere else. */
export const formatAddress = (addr: number, addrWidth: number): string =>
  addr.toString(16).padStart(Math.max(1, Math.ceil(addrWidth / 4)), '0');

// ---------------------------------------------------------------------------
// What a typed word means.
// ---------------------------------------------------------------------------

export type ParsedWord =
  | { ok: true; value: bigint; defined: bigint }
  | { ok: false; message: string };

/**
 * Parse one word the reader typed.
 *
 * `?` and the empty string both mean "make this cell unknown again", which is
 * the only way back once a word has been written. An explicit `0x` or `0b`
 * prefix overrides the chosen format, because a reader who typed the prefix
 * meant it.
 */
export function parseWord(text: string, width: number, format: ValueFormat): ParsedWord {
  const trimmed = text.trim();
  if (trimmed === '' || trimmed === UNKNOWN) return { ok: true, value: 0n, defined: 0n };

  const lower = trimmed.toLowerCase().replace(/_/g, '');
  let body = lower;
  let radix = format === 'hex' ? 16 : format === 'binary' ? 2 : 10;
  if (lower.startsWith('0x')) {
    body = lower.slice(2);
    radix = 16;
  } else if (lower.startsWith('0b')) {
    body = lower.slice(2);
    radix = 2;
  }
  if (body === '') return { ok: false, message: 'Type a number, or ? to make the word unknown.' };

  const legal = radix === 16 ? /^[0-9a-f]+$/ : radix === 2 ? /^[01]+$/ : /^[0-9]+$/;
  if (!legal.test(body)) {
    const kind = radix === 16 ? 'hexadecimal' : radix === 2 ? 'binary' : 'decimal';
    return { ok: false, message: `Not a ${kind} number. Use 0x or 0b to give a different base.` };
  }

  let value: bigint;
  try {
    value = radix === 10 ? BigInt(body) : BigInt(`${radix === 16 ? '0x' : '0b'}${body}`);
  } catch {
    return { ok: false, message: 'Not a number this memory can hold.' };
  }
  const mask = maskFor(width);
  if (value > mask) {
    return { ok: false, message: `Too large for ${width} bit${width === 1 ? '' : 's'}; the most is ${mask}.` };
  }
  return { ok: true, value, defined: mask };
}

/** An address the reader typed, or null. Hex by default, since that is how the
 *  table writes them; `d` forces decimal for anyone who prefers it. */
export function parseAddress(text: string, addrWidth: number): number | null {
  const trimmed = text.trim().toLowerCase().replace(/_/g, '');
  if (trimmed === '') return null;
  const decimal = trimmed.startsWith('d');
  const body = decimal ? trimmed.slice(1) : trimmed.startsWith('0x') ? trimmed.slice(2) : trimmed;
  const legal = decimal ? /^[0-9]+$/ : /^[0-9a-f]+$/;
  if (!legal.test(body)) return null;
  const addr = Number.parseInt(body, decimal ? 10 : 16);
  if (!Number.isSafeInteger(addr) || addr < 0 || addr >= maxWords(addrWidth)) return null;
  return addr;
}
