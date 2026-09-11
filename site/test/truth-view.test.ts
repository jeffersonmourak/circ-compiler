// The Truth view's module: the compiler's JSON parsed and spelled, the live
// row found, the chip's words, the compiler's markdown and CSV shapes, a row
// driven through a stub session, and the over-cap enumeration on a scratch.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { callOp, instantiateLibcirc, type LibcircExports } from '../src/scripts/libcirc-abi.ts';
import { SimSession } from '../src/scripts/sim-session.ts';
import {
  cellText,
  chipText,
  columnOf,
  driveRow,
  liveRowIndex,
  parseTruthTable,
  rowsForPins,
  toCsv,
  toMarkdown,
  unknownInputs,
} from '../src/scripts/truth-view.ts';
import { requestFor, splitFiles } from '../src/utils/split-files.ts';
import { AND_GATE, evaluateAnd, MEMORIES, evaluateRom, stubRuntime, type StubRuntime } from './sim-stub.ts';

const skip = process.env.SKIP_LIBCIRC_TEST === '1';
const REPO = resolve(import.meta.dir, '..', '..');
const wasmPath = resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.wasm');
let cached: Promise<LibcircExports> | null = null;
const lib = () => (cached ??= instantiateLibcirc(readFileSync(wasmPath)));
const text = (bytes: Uint8Array) => new TextDecoder().decode(bytes);

async function andSession(): Promise<{ session: SimSession; rt: StubRuntime }> {
  let rt!: StubRuntime;
  const session = await SimSession.build({
    bytes: new Uint8Array([1]),
    load: async () => (rt = stubRuntime(AND_GATE, evaluateAnd)),
  });
  return { session, rt };
}

const AND_JSON = '{"inputs":["a","b"],"outputs":["out"],"rows":[{"in":[0,0],"out":[0]},{"in":[1,0],"out":[0]},{"in":[0,1],"out":[0]},{"in":[1,1],"out":[1]}]}';

describe('truth view', () => {
  test('parseTruthTable reads numbers and hex strings into bigints', () => {
    const t = parseTruthTable('{"inputs":["a[4]"],"outputs":["o[4]","p"],"rows":[{"in":[10],"out":["A",null]}]}');
    expect(t.inputs).toEqual([{ name: 'a', width: 4 }]);
    expect(t.outputs).toEqual([{ name: 'o', width: 4 }, { name: 'p', width: 1 }]);
    expect(t.rows[0].in).toEqual([10n]);
    expect(t.rows[0].out).toEqual([10n, null]);
    expect(columnOf('a[4]')).toEqual({ name: 'a', width: 4 });
    expect(columnOf('a')).toEqual({ name: 'a', width: 1 });
  });

  test("cellText spells in the reader's base", () => {
    expect(cellText(10n, 4, 'binary')).toBe('0b1010');
    expect(cellText(10n, 4, 'hex')).toBe('0xA');
    expect(cellText(10n, 4, 'decimal')).toBe('10');
    // A bit is a bit in any base, and an unknown cell is a question.
    expect(cellText(1n, 1, 'binary')).toBe('1');
    expect(cellText(0n, 1, 'hex')).toBe('0');
    expect(cellText(null, 4, 'hex')).toBe('?');
  });

  test("liveRowIndex matches the compiler's row order", () => {
    const t = parseTruthTable(AND_JSON);
    const pin = (name: string, value: bigint, defined = 1n) => ({ name, value: { value, defined, width: 1 } });
    // The first pin varies fastest: `a=1, b=0` is the second row.
    expect(liveRowIndex(t, [pin('a', 1n), pin('b', 0n)])).toBe(1);
    expect(liveRowIndex(t, [pin('a', 1n), pin('b', 1n)])).toBe(3);
    // An unknown pin selects nothing, and so does a pin the table lacks.
    expect(liveRowIndex(t, [pin('a', 1n), pin('b', 0n, 0n)])).toBe(-1);
    expect(liveRowIndex(t, [pin('a', 1n)])).toBe(-1);
  });

  test('liveRowIndex on a bus', () => {
    const t = parseTruthTable('{"inputs":["a[4]"],"outputs":["o"],"rows":[{"in":[5],"out":[0]},{"in":[6],"out":[1]}]}');
    expect(liveRowIndex(t, [{ name: 'a', value: { value: 0b0110n, defined: 0b1111n, width: 4 } }])).toBe(1);
    expect(liveRowIndex(t, [{ name: 'a', value: { value: 0b0110n, defined: 0b0111n, width: 4 } }])).toBe(-1);
  });

  test('chipText composes the parts', () => {
    expect(chipText({ bits: 3, rows: 8, cap: 12, blocked: null, filtered: false })).toBe('3 input bits · 8 rows · cap 12');
    expect(chipText({ bits: 1, rows: 1, cap: 12, blocked: null, filtered: false })).toBe('1 input bit · 1 row · cap 12');
    expect(chipText({ bits: null, rows: null, cap: 12, blocked: null, filtered: false })).toBe('cap 12');
    expect(chipText({ bits: 20, rows: 4, cap: 12, blocked: null, filtered: true })).toBe('20 input bits · 4 rows · cap 12 · filtered to the current pins');
    expect(chipText({ bits: 20, rows: null, cap: 4, blocked: null, filtered: false, unknownBits: 9 })).toBe('20 input bits · cap 4 · over the cap: 9 unknown bits');
    const blocked = 'One error to fix first — E001 unknown component. A truth table needs a circuit that compiles.';
    expect(chipText({ bits: 2, rows: null, cap: 12, blocked, filtered: false })).toBe('2 input bits · cap 12 · One error to fix first — E001 unknown component');
    const cap = 'This circuit has 20 input bits; the playground enumerates up to 12 (4096 rows). Raise the cap in settings, or use circ-compile --truth-table.';
    expect(chipText({ bits: 20, rows: null, cap: 12, blocked: cap, filtered: false })).toBe('20 input bits · cap 12 · This circuit has 20 input bits');
  });

  test("toMarkdown and toCsv match the compiler's shape", () => {
    const md = readFileSync(resolve(REPO, 'tests', 'fixtures', 'truth_table', 'and_4bit_truth.binary.md.golden'), 'utf8');
    const csv = readFileSync(resolve(REPO, 'tests', 'fixtures', 'truth_table', 'and_4bit_truth.hex.csv.golden'), 'utf8');
    const json = readFileSync(resolve(REPO, 'tests', 'fixtures', 'truth_table', 'and_4bit_truth.hex.json.golden'), 'utf8');
    const t = parseTruthTable(json);
    expect(toMarkdown(t, 'binary')).toBe(md);
    expect(toCsv(t, 'hex')).toBe(csv);
    // The header line and the rule, on the hex markdown golden.
    const hexMd = readFileSync(resolve(REPO, 'tests', 'fixtures', 'truth_table', 'and_4bit_truth.hex.md.golden'), 'utf8');
    expect(toMarkdown(t, 'hex')).toBe(hexMd);
  });

  test('a row click drives every input column through the session', async () => {
    const { session, rt } = await andSession();
    const t = parseTruthTable(AND_JSON);
    rt.calls.length = 0;
    expect(driveRow(session, t, 3)).toEqual({ ok: true });
    expect(rt.calls).toEqual(['set:0', 'run', 'set:1', 'run']);
    const out = session.get('out');
    expect(out.ok && out.value.value).toBe(1n);
    // A row that names no such pin is a refusal, not a throw.
    const bad = parseTruthTable('{"inputs":["zz"],"outputs":["out"],"rows":[{"in":[1],"out":[1]}]}');
    expect(driveRow(session, bad, 0)).toMatchObject({ ok: false, code: 'E_NOPIN' });
    expect(driveRow(session, t, 9)).toMatchObject({ ok: false });
  });

  test('unknownInputs lists the pins with an undefined bit', async () => {
    const { session } = await andSession();
    expect(unknownInputs(session).map((p) => p.name)).toEqual(['a', 'b']);
    session.set('a', 0n, 1n);
    expect(unknownInputs(session).map((p) => p.name)).toEqual(['b']);
  });

  test('rowsForPins enumerates only the unknown bits', async () => {
    const { session: live } = await andSession();
    const { session: scratch, rt } = await andSession();
    live.set('a', 1n, 1n);
    const r = rowsForPins(scratch, live, 12);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.unknownBits).toBe(1);
    expect(r.table.inputs).toEqual([{ name: 'a', width: 1 }, { name: 'b', width: 1 }]);
    expect(r.table.rows.map((row) => [...row.in, ...row.out])).toEqual([[1n, 0n, 0n], [1n, 1n, 1n]]);
    expect(rt.calls.filter((c) => c.startsWith('set:'))).toEqual(['set:0', 'set:1', 'set:1']);
  });

  test('rowsForPins refuses over the cap and on a ram', async () => {
    const { session: live } = await andSession();
    const { session: scratch } = await andSession();
    expect(rowsForPins(scratch, live, 1)).toEqual({ ok: false, reason: 'over-cap', unknownBits: 2 });
    const stateful = await SimSession.build({ bytes: new Uint8Array([1]), load: async () => stubRuntime(MEMORIES, evaluateRom) });
    const liveMem = await SimSession.build({ bytes: new Uint8Array([1]), load: async () => stubRuntime(MEMORIES, evaluateRom) });
    expect(rowsForPins(stateful, liveMem, 12)).toEqual({ ok: false, reason: 'stateful', unknownBits: 4 });
  });

  test('the scratch never writes the live session', async () => {
    const { session: live, rt: liveRt } = await andSession();
    const { session: scratch, rt: scratchRt } = await andSession();
    live.set('b', 1n, 1n);
    liveRt.calls.length = 0;
    const r = rowsForPins(scratch, live, 12);
    expect(r.ok).toBe(true);
    expect(liveRt.calls.some((c) => c.startsWith('set:'))).toBe(false);
    expect(scratchRt.calls.some((c) => c.startsWith('set:'))).toBe(true);
    if (r.ok) expect(r.table.rows.map((row) => [...row.in, ...row.out])).toEqual([[0n, 1n, 0n], [1n, 1n, 1n]]);
  });

  test.skipIf(skip)("toMarkdown of the parsed json equals the compiler's markdown", async () => {
    const w = await lib();
    for (const name of ['and_gate.circ', 'and_2bit.circ']) {
      const source = readFileSync(resolve(REPO, 'tests', 'fixtures', 'circuits', name), 'utf8');
      for (const value_format of ['binary', 'hex', 'decimal'] as const) {
        const ask = (format: string) => {
          const out = callOp(w, 'truth_table', requestFor(splitFiles(source), { format, value_format, truth_table_cap: 12 }));
          expect(out.status).toBe(0);
          return text(out.bytes);
        };
        const t = parseTruthTable(ask('json'));
        expect(toMarkdown(t, value_format)).toBe(ask('markdown'));
        expect(toCsv(t, value_format)).toBe(ask('csv'));
      }
    }
  });
});
