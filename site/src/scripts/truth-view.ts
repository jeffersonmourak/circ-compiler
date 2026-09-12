// The Truth view, as a pure module: the compiler's JSON parsed, every cell
// spelled the renderer's way, the row that matches the session's pins, the
// chip's words, the compiler's markdown and CSV shapes for rows the compiler
// never saw, a row driven through the session, and the over-cap enumeration
// on a scratch session (decision 10).
//
// Reaches the renderer's index for the value helpers, so the island imports
// this module dynamically beside `data-view.ts`; it must not enter the eager
// graph.
import { formatPinValue, widthMask, type BitValue, type ValueFormat } from 'circ-renderer';
import type { SessionLike } from './data-view.ts';
import type { SimResult } from './sim-session.ts';

/** A column as the compiler names it: `name` or `name[W]`. */
export interface Column {
  name: string;
  width: number;
}
/** One cell: fully defined as a bigint, else null. The compiler's JSON emits
 *  `null` for any undefined bit (lib/truth_table/json.zig). */
export type Cell = bigint | null;
export interface TruthRows {
  inputs: Column[];
  outputs: Column[];
  rows: { in: Cell[]; out: Cell[] }[];
}

export function columnOf(header: string): Column {
  const m = header.match(/^(.*)\[(\d+)\]$/);
  return m ? { name: m[1], width: Number(m[2]) } : { name: header, width: 1 };
}

const cellOf = (v: unknown): Cell => {
  if (v === null || v === undefined) return null;
  // Under `value_format: hex` the compiler writes uppercase hex strings with
  // no prefix; under binary and decimal it writes numbers.
  if (typeof v === 'string') return BigInt(`0x${v}`);
  if (typeof v === 'number') return BigInt(v);
  return null;
};

/** The compiler's `{inputs, outputs, rows: [{in, out}]}`, cells as bigints. */
export function parseTruthTable(text: string): TruthRows {
  const raw = JSON.parse(text) as { inputs: string[]; outputs: string[]; rows: { in: unknown[]; out: unknown[] }[] };
  return {
    inputs: raw.inputs.map(columnOf),
    outputs: raw.outputs.map(columnOf),
    rows: raw.rows.map((r) => ({ in: r.in.map(cellOf), out: r.out.map(cellOf) })),
  };
}

/** The renderer's spelling in the reader's base, so the table and the Data
 *  panel never disagree; a one-bit column is its digit in any base, and an
 *  unknown cell is `?`. */
export function cellText(cell: Cell, width: number, format: ValueFormat): string {
  if (cell === null) return '?';
  if (width <= 1) return cell.toString();
  return formatPinValue({ value: cell, defined: widthMask(width), width }, format);
}

const fullyDefined = (v: BitValue): boolean => (v.defined & widthMask(v.width)) === widthMask(v.width);

/** The row whose input cells equal the session's input pins, by name; -1 when
 *  any input pin is not fully defined, a column names no pin, or no row
 *  matches. */
export function liveRowIndex(table: TruthRows, pins: readonly { name: string; value: BitValue }[]): number {
  const want: bigint[] = [];
  for (const col of table.inputs) {
    const pin = pins.find((p) => p.name === col.name);
    if (!pin || !fullyDefined(pin.value)) return -1;
    want.push(pin.value.value & widthMask(col.width));
  }
  return table.rows.findIndex((r) => r.in.every((c, i) => c !== null && c === want[i]));
}

export { chipText, type ChipInput } from './truth-chip.ts';

// ---------------------------------------------------------------------------
// The compiler's own shapes (lib/truth_table/markdown.zig, csv.zig), for rows
// the compiler never produced. Byte-equal to its output for the rows it did.
// ---------------------------------------------------------------------------

const headerName = (c: Column): string => (c.width <= 1 ? c.name : `${c.name}[${c.width}]`);

/** A cell as the compiler writes it: bits, uppercase hex digits, or decimal,
 *  with no prefix; `?` when unknown. */
export function compilerCell(cell: Cell, width: number, format: ValueFormat): string {
  if (cell === null) return '?';
  if (width === 0) return '?';
  switch (format) {
    case 'binary':
      return cell.toString(2).padStart(width, '0');
    case 'hex':
      return cell.toString(16).toUpperCase().padStart(Math.ceil(width / 4), '0');
    case 'decimal':
      return cell.toString(10);
  }
}

const cellWidthFor = (width: number, format: ValueFormat): number => {
  if (width === 0) return 1;
  switch (format) {
    case 'binary':
      return width;
    case 'hex':
      return Math.ceil(width / 4);
    case 'decimal':
      return widthMask(width).toString(10).length;
  }
};

const columnWidth = (c: Column, format: ValueFormat): number =>
  Math.max(Math.max(headerName(c).length, 1), cellWidthFor(c.width, format));

export function toMarkdown(table: TruthRows, format: ValueFormat): string {
  const cols = [...table.inputs, ...table.outputs];
  const widths = cols.map((c) => columnWidth(c, format));
  const pad = (s: string, w: number) => ` ${s}${' '.repeat(Math.max(0, w - s.length))} `;
  let out = '|' + cols.map((c, i) => pad(headerName(c), widths[i])).join('|') + '|\n';
  out += '|' + widths.map((w) => '-'.repeat(w + 2)).join('|') + '|\n';
  for (const r of table.rows) {
    const cells = [...r.in, ...r.out];
    out += '|' + cells.map((cell, i) => pad(compilerCell(cell, cols[i].width, format), widths[i])).join('|') + '|\n';
  }
  return out;
}

export function toCsv(table: TruthRows, format: ValueFormat): string {
  const cols = [...table.inputs, ...table.outputs];
  let out = cols.map(headerName).join(',') + '\n';
  for (const r of table.rows) {
    const cells = [...r.in, ...r.out];
    out += cells.map((cell, i) => compilerCell(cell, cols[i].width, format)).join(',') + '\n';
  }
  return out;
}

// ---------------------------------------------------------------------------
// Driving, and the over-cap path.
// ---------------------------------------------------------------------------

/** Drive every input column of a row through the session (decision 11): one
 *  `set` per column, in column order, so each reaches the canvas, the Data
 *  panel and the console the way a typed `set` does. The first refusal ends
 *  it and comes back; an unknown cell is skipped. */
export function driveRow(session: SessionLike, table: TruthRows, row: number): SimResult {
  const r = table.rows[row];
  if (!r) return { ok: false, code: 'E_NOPIN', arg: String(row) };
  for (let i = 0; i < table.inputs.length; i++) {
    const cell = r.in[i];
    if (cell === null) continue;
    const col = table.inputs[i];
    const res = session.set(col.name, cell, widthMask(col.width));
    if (!res.ok) return res;
  }
  return { ok: true };
}

/** The input pins with any undefined bit, in declaration order. */
export function unknownInputs(session: SessionLike): { name: string; width: number }[] {
  const out: { name: string; width: number }[] = [];
  for (const pin of session.pins) {
    if (pin.kind !== 'in') continue;
    const r = session.get(pin.name);
    if (!r.ok || !fullyDefined(r.value)) out.push({ name: pin.name, width: pin.width });
  }
  return out;
}

export type ScratchOutcome =
  | { ok: true; table: TruthRows; filtered: true; unknownBits: number }
  | { ok: false; reason: 'over-cap' | 'stateful'; unknownBits: number };

export type FixedInputs = readonly { name: string; width: number; value: BitValue }[];

/**
 * Decision 10: the table over the cap. Every known input pin of `live` is
 * held at its value on `scratch`; the unknown pins' bits are enumerated,
 * `2^k` assignments with the first unknown pin varying fastest (the
 * compiler's order, lib/truth_table/json.zig); the outputs are read after
 * each. `live` is only ever read. Refused when the unknown bits exceed the
 * cap, or when the circuit holds a `ram` (as the compiler refuses it: a
 * truth table of a stateful circuit is not one).
 */
export function rowsForPins(
  scratch: SessionLike & { mems: readonly { kind: 'rom' | 'ram' }[]; hasRam?: boolean },
  live: SessionLike,
  cap: number,
  fixedInputs?: FixedInputs,
): ScratchOutcome {
  const inputs = live.pins.filter((p) => p.kind === 'in');
  const outputs = live.pins.filter((p) => p.kind === 'out');
  const fixed = new Map(fixedInputs?.map((pin) => [pin.name, pin]) ?? []);
  const unknown = fixedInputs
    ? inputs.filter((pin) => !fullyDefined(fixed.get(pin.name)?.value ?? { value: 0n, defined: 0n, width: pin.width }))
    : unknownInputs(live);
  const unknownBits = unknown.reduce((n, p) => n + p.width, 0);
  if (unknownBits > cap) return { ok: false, reason: 'over-cap', unknownBits };
  if (scratch.hasRam || scratch.mems.some((m) => m.kind === 'ram')) return { ok: false, reason: 'stateful', unknownBits };

  const unknownNames = new Set(unknown.map((p) => p.name));
  const known = new Map<string, bigint>();
  for (const pin of inputs) {
    if (unknownNames.has(pin.name)) continue;
    const captured = fixed.get(pin.name)?.value;
    const r = captured ? { ok: true as const, value: captured } : live.get(pin.name);
    const value = r.ok ? r.value.value & widthMask(pin.width) : 0n;
    known.set(pin.name, value);
    scratch.set(pin.name, value, widthMask(pin.width));
  }

  const rows: TruthRows['rows'] = [];
  const total = 1n << BigInt(unknownBits);
  for (let i = 0n; i < total; i++) {
    let shift = 0n;
    const assigned = new Map<string, bigint>();
    for (const pin of unknown) {
      const value = (i >> shift) & widthMask(pin.width);
      assigned.set(pin.name, value);
      scratch.set(pin.name, value, widthMask(pin.width));
      shift += BigInt(pin.width);
    }
    const row = {
      in: inputs.map((p) => (unknownNames.has(p.name) ? assigned.get(p.name)! : known.get(p.name)!)),
      out: outputs.map((p) => {
        const r = scratch.get(p.name);
        return r.ok && fullyDefined(r.value) ? r.value.value & widthMask(p.width) : null;
      }),
    };
    rows.push(row);
  }
  return {
    ok: true,
    filtered: true,
    unknownBits,
    table: {
      inputs: inputs.map((p) => ({ name: p.name, width: p.width })),
      outputs: outputs.map((p) => ({ name: p.name, width: p.width })),
      rows,
    },
  };
}
