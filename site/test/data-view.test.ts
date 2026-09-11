// The Data tab's rows and edits, over the session on a stub runtime: the
// rows follow the pins in the reader's base, an edit parses the site's way
// and drives, a refusal drives nothing and says why, a one-bit input toggles.
import { describe, expect, test } from 'bun:test';
import { ComponentKind, type BitValue } from 'circ-renderer/topology';
import { SimSession } from '../src/scripts/sim-session.ts';
import { describeError, editRow, rowsFor, toggleRow } from '../src/scripts/data-view.ts';
import { AND_GATE, evaluateAnd, stubRuntime, type StubRuntime } from './sim-stub.ts';

const bytes = new Uint8Array([0]);

/** `input[4] a`, `output[4] o(a)`: a bus that passes through. */
const BUS = [
  { id: 0, kind: ComponentKind.InputPin, name: 'a', width: 4 },
  { id: 1, kind: ComponentKind.OutputPin, name: 'o', width: 4 },
];
const passThrough = (values: Map<number, BitValue>) => {
  values.set(1, { ...values.get(0)!, width: 4 });
};

async function bus() {
  let rt!: StubRuntime;
  const session = await SimSession.build({ bytes, load: async () => (rt = stubRuntime(BUS, passThrough)) });
  return { session, rt };
}
async function and() {
  let rt!: StubRuntime;
  const session = await SimSession.build({ bytes, load: async () => (rt = stubRuntime(AND_GATE, evaluateAnd)) });
  return { session, rt };
}

describe('rows', () => {
  test('rows follow the pins, inputs then outputs, unknown before any drive', async () => {
    const { session } = await and();
    expect(rowsFor(session, 'hex')).toEqual([
      { name: 'a', kind: 'in', width: 1, text: '?', signal: 2 },
      { name: 'b', kind: 'in', width: 1, text: '?', signal: 2 },
      { name: 'out', kind: 'out', width: 1, text: '?', signal: 2 },
    ]);
  });

  test("a value is spelled in the reader's base, and a half-known one bit by bit", async () => {
    const { session } = await bus();
    session.set('a', 0xan);
    expect(rowsFor(session, 'hex').map((r) => r.text)).toEqual(['0xA', '0xA']);
    expect(rowsFor(session, 'binary').map((r) => r.text)).toEqual(['0b1010', '0b1010']);
    expect(rowsFor(session, 'decimal').map((r) => r.text)).toEqual(['10', '10']);
    session.set('a', 0b1010n, 0b1100n);
    // The renderer writes a partly known value bit by bit with x for each
    // unknown bit, whatever the base, and without a prefix: there is no honest
    // hex digit for four bits of which two are unknown.
    expect(rowsFor(session, 'hex')[0].text).toBe('10xx');
  });
});

describe('edits', () => {
  test("an edit parses the site's way and drives the session", async () => {
    const { session, rt } = await bus();
    expect(editRow(session, 'a', '0xA', 'binary')).toEqual({ ok: true });
    expect(rt.values.get(0)).toEqual({ value: 0xan, defined: 0xfn, width: 4 });
    expect(editRow(session, 'a', '1010', 'binary')).toEqual({ ok: true });
    expect(rt.values.get(0)!.value).toBe(0b1010n);
    expect(editRow(session, 'a', '12', 'decimal')).toEqual({ ok: true });
    expect(rt.values.get(0)!.value).toBe(12n);
    // A typed value is fully known; ? and nothing make the pin wholly unknown.
    // The renderer's parser does not take x bits back in (the bus dialog has
    // never offered a per-bit entry), so a half-known spelling is refused.
    const partial = editRow(session, 'a', '10xx', 'binary');
    expect(partial.ok).toBe(false);
    expect(editRow(session, 'a', '?', 'hex')).toEqual({ ok: true });
    expect(rt.values.get(0)!.defined).toBe(0n);
    expect(editRow(session, 'a', '', 'hex')).toEqual({ ok: true });
  });

  test('a refused edit drives nothing and says why', async () => {
    const { session, rt } = await bus();
    const wide = editRow(session, 'a', '0x1F', 'hex');
    expect(wide.ok).toBe(false);
    expect(!wide.ok && wide.message.length).toBeGreaterThan(0);
    const junk = editRow(session, 'a', 'zz', 'decimal');
    expect(junk.ok).toBe(false);
    expect(editRow(session, 'o', '1', 'hex')).toEqual({ ok: false, message: 'o is an output; only inputs can be driven.' });
    expect(editRow(session, 'nope', '1', 'hex')).toEqual({ ok: false, message: 'There is no pin named nope.' });
    expect(rt.calls).toEqual([]);
  });

  test('a one-bit input toggles unknown → 1 → 0 → 1, and a bus does not', async () => {
    const { session } = await and();
    expect(toggleRow(session, 'a')).toEqual({ ok: true });
    expect(rowsFor(session, 'hex')[0]).toMatchObject({ text: '0x1', signal: 1 });
    expect(toggleRow(session, 'a')).toEqual({ ok: true });
    expect(rowsFor(session, 'hex')[0]).toMatchObject({ text: '0x0', signal: 0 });
    expect(toggleRow(session, 'a')).toEqual({ ok: true });
    expect(rowsFor(session, 'hex')[0].signal).toBe(1);
    expect(toggleRow(session, 'out')).toEqual({ ok: false, message: 'out is an output; only inputs can be driven.' });
    const { session: wide } = await bus();
    expect(toggleRow(wide, 'a')).toEqual({ ok: false, message: 'a is 4 bits wide; type its value instead.' });
  });

  test('every protocol code has a sentence', () => {
    for (const code of ['E_PROTO', 'E_NOPIN', 'E_NOTIN', 'E_WIDTH', 'E_BADVAL', 'E_NOSETTLE', 'E_NOMEM', 'E_IO', 'E_MEMFMT', 'E_ADDR'] as const) {
      expect(describeError(code, 'x').length).toBeGreaterThan(0);
      expect(describeError(code, 'x').endsWith('.')).toBe(true);
    }
  });
});
