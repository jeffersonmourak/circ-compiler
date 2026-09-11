// The session, over a stub runtime: the root pins it finds, the drives it
// refuses before touching the runtime, the settles and notifications it owes
// after each one, and the reset that hands every face a fresh runtime.
import { describe, expect, test } from 'bun:test';
import { widthMask } from 'circ-renderer/topology';
import { SimSession, collectMems, collectPins, type SessionEvent } from '../src/scripts/sim-session.ts';
import { AND_GATE, MEMORIES, evaluateAnd, evaluateRom, stubRuntime, type StubRuntime } from './sim-stub.ts';

const bytes = new Uint8Array([0]);

async function andSession() {
  const made: StubRuntime[] = [];
  const session = await SimSession.build({
    bytes,
    load: async () => {
      const rt = stubRuntime(AND_GATE, evaluateAnd);
      made.push(rt);
      return rt;
    },
  });
  const events: SessionEvent[] = [];
  session.subscribe((e) => events.push(e));
  return { session, rt: made[0], made, events };
}

describe('collecting the root pins and memories', () => {
  test('pins are the root pins, inputs then outputs, in declaration order', () => {
    const pins = collectPins(stubRuntime(MEMORIES).topology);
    expect(pins.map((p) => `${p.kind}:${p.name}:${p.width}`)).toEqual(['in:pc:4', 'out:q:8']);
    // The nested `hidden` input, one origin frame deep, is not addressable.
    expect(pins.some((p) => p.name === 'hidden')).toBe(false);
    const and = collectPins(stubRuntime(AND_GATE).topology);
    expect(and.map((p) => p.name)).toEqual(['a', 'b', 'out']);
  });

  test('memories are the root memories, in declaration order, with their shape', () => {
    const mems = collectMems(stubRuntime(MEMORIES).topology);
    expect(mems).toEqual([
      { name: 'code', id: 1, kind: 'rom', width: 8, addrWidth: 4 },
      { name: 'data', id: 2, kind: 'ram', width: 8, addrWidth: 2 },
    ]);
  });
});

describe('driving pins', () => {
  test('set drives a root input and settles, and reads come back defined', async () => {
    const { session, rt, events } = await andSession();
    expect(session.set('a', 1n)).toEqual({ ok: true });
    expect(session.set('b', 1n)).toEqual({ ok: true });
    expect(rt.calls).toEqual(['set:0', 'run', 'set:1', 'run']);
    const out = session.get('out');
    expect(out.ok && out.value).toEqual({ value: 1n, defined: 1n, width: 1 });
    // An input reads back as what it was driven to, as `get <input>` does.
    const a = session.get('a');
    expect(a.ok && a.value).toEqual({ value: 1n, defined: 1n, width: 1 });
    expect(events).toEqual([{ kind: 'drive', names: ['a'] }, { kind: 'drive', names: ['b'] }]);
  });

  test('set refuses what --sim refuses, before touching the runtime', async () => {
    const { session, rt } = await andSession();
    expect(session.set('nope', 1n)).toEqual({ ok: false, code: 'E_NOPIN', arg: 'nope' });
    expect(session.set('out', 1n)).toEqual({ ok: false, code: 'E_NOTIN', arg: 'out' });
    expect(session.set('a', 2n)).toEqual({ ok: false, code: 'E_WIDTH', arg: 'a' });
    expect(session.set('a', 0n, 2n)).toEqual({ ok: false, code: 'E_WIDTH', arg: 'a' });
    expect(rt.calls).toEqual([]);
  });

  test('an omitted mask is the full mask, and a given one is per bit', async () => {
    const { session, rt } = await andSession();
    session.set('a', 1n);
    expect(rt.values.get(0)).toEqual({ value: 1n, defined: 1n, width: 1 });
    session.set('a', 0n, 0n);
    expect(rt.values.get(0)).toEqual({ value: 0n, defined: 0n, width: 1 });
    const out = session.get('out');
    expect(out.ok && out.value.defined).toBe(0n);
  });

  test('get on an unknown name is E_NOPIN, and dump lists what was asked for', async () => {
    const { session } = await andSession();
    expect(session.get('zz')).toEqual({ ok: false, code: 'E_NOPIN', arg: 'zz' });
    expect(session.dump('in').map((v) => v.pin.name)).toEqual(['a', 'b']);
    expect(session.dump('out').map((v) => v.pin.name)).toEqual(['out']);
    expect(session.dump('all').map((v) => v.pin.name)).toEqual(['a', 'b', 'out']);
  });

  test('eval validates everything before driving anything', async () => {
    const { session, rt, events } = await andSession();
    const bad = session.eval([{ pin: 'a', value: 1n }, { pin: 'b', value: 1n }], ['out', 'zz']);
    expect(bad).toEqual({ ok: false, code: 'E_NOPIN', arg: 'zz' });
    const wide = session.eval([{ pin: 'a', value: 1n }, { pin: 'b', value: 3n }], ['out']);
    expect(wide).toEqual({ ok: false, code: 'E_WIDTH', arg: 'b' });
    expect(rt.calls).toEqual([]);
    expect(events).toEqual([]);
    const good = session.eval([{ pin: 'a', value: 1n }, { pin: 'b', value: 0n, defined: 1n }], ['out', 'a']);
    expect(good.ok && good.values.map((v) => `${v.pin.name}=${v.value.value}/${v.value.defined}`)).toEqual(['out=0/1', 'a=1/1']);
    // Each assignment settles on its own, as `--sim` does.
    expect(rt.calls.filter((c) => c === 'run')).toHaveLength(2);
    expect(events).toEqual([{ kind: 'drive', names: ['a', 'b'] }]);
  });

  test('a listener that throws does not silence the others', async () => {
    const { session } = await andSession();
    const seen: string[] = [];
    session.subscribe(() => { throw new Error('boom'); });
    session.subscribe((e) => seen.push(e.kind));
    session.set('a', 1n);
    expect(seen).toEqual(['drive']);
  });

  test('a face that drove the runtime itself can tell the others', async () => {
    const { session, events } = await andSession();
    session.notifyExternal(['a']);
    expect(events).toEqual([{ kind: 'drive', names: ['a'] }]);
  });
});

describe('memories', () => {
  async function romSession(images = new Map<string, string>()) {
    const made: StubRuntime[] = [];
    const session = await SimSession.build({
      bytes,
      load: async () => {
        const rt = stubRuntime(MEMORIES, evaluateRom);
        made.push(rt);
        return rt;
      },
      roms: [
        { name: 'code', kind: 'rom', width: 8, addrWidth: 4 },
        { name: 'data', kind: 'ram', width: 8, addrWidth: 2 },
      ],
      images,
    });
    const events: SessionEvent[] = [];
    session.subscribe((e) => events.push(e));
    return { session, made, events, rt: () => made[made.length - 1] };
  }

  test('peek, poke, dump and clear map to the runtime as the protocol says', async () => {
    const { session, rt, events } = await romSession();
    expect(session.peek('nosuch', 0n)).toEqual({ ok: false, code: 'E_NOMEM', arg: 'nosuch' });
    expect(session.peek('data', 4n)).toEqual({ ok: false, code: 'E_ADDR', arg: 'data 0x4' });
    expect(session.poke('data', 0n, 0x1ffn)).toEqual({ ok: false, code: 'E_WIDTH', arg: 'data' });
    expect(rt().calls).toEqual([]);

    expect(session.poke('code', 3n, 0x2an)).toEqual({ ok: true });
    const cell = session.peek('code', 3n);
    expect(cell.ok && cell.value).toEqual({ value: 0x2an, defined: 0xffn, width: 8 });
    // A poke settles, like set: the rom's output follows.
    session.set('pc', 3n);
    const q = session.get('q');
    expect(q.ok && q.value).toEqual({ value: 0x2an, defined: 0xffn, width: 8 });

    const range = session.dumpMem('code', 2n, 3n);
    expect(range.ok && range.cells.map((c) => `${c.addr}:${c.value.value}/${c.value.defined}`)).toEqual(['2:0/0', '3:42/255', '4:0/0']);
    // start past the end is refused; count is clipped; count 0 is empty.
    expect(session.dumpMem('code', 16n)).toEqual({ ok: false, code: 'E_ADDR', arg: 'code 0x10' });
    const tail = session.dumpMem('code', 14n, 10n);
    expect(tail.ok && tail.cells.length).toBe(2);
    const none = session.dumpMem('code', 0n, 0n);
    expect(none.ok && none.cells.length).toBe(0);
    const whole = session.dumpMem('data');
    expect(whole.ok && whole.cells.length).toBe(4);

    expect(session.clear('code')).toEqual({ ok: true });
    const after = session.get('q');
    expect(after.ok && after.value.defined).toBe(0n);
    expect(events.filter((e) => e.kind === 'memory').map((e) => (e as { name: string }).name)).toEqual(['code', 'code']);
  });

  test('an image loads whole, stores back, and a ram is never preloaded', async () => {
    const { session, rt } = await romSession();
    const image = new Uint8Array([0x10, 0x20, 0x30]);
    const loaded = session.loadImage('code', image);
    expect(loaded.ok && loaded.words).toBe(3);
    const stored = session.storeImage('code');
    expect(stored.ok && Array.from(stored.bytes.slice(0, 4))).toEqual([0x10, 0x20, 0x30, 0]);
    expect(stored.ok && stored.words).toBe(16);
    expect(rt().calls).toContain('load:1');
    expect(session.loadImage('zz', image)).toEqual({ ok: false, code: 'E_NOMEM', arg: 'zz' });
  });

  test('preloads are the Memory tab images, applied at build and again at reset', async () => {
    const { session, made, events } = await romSession(new Map([['code', '2a 2b']]));
    expect(made[0].calls).toContain('load:1');
    const before = session.peek('code', 1n);
    expect(before.ok && before.value.value).toBe(0x2bn);
    // Mid-session state, then reset: a new runtime, the old destroyed, the
    // preload back, the poke gone, and the faces told to rebuild.
    session.poke('code', 5n, 0x77n);
    session.set('pc', 5n);
    await session.reset();
    expect(made).toHaveLength(2);
    expect(made[0].destroyed).toBe(true);
    expect(session.runtime).toBe(made[1]);
    const gone = session.peek('code', 5n);
    expect(gone.ok && gone.value.defined).toBe(0n);
    const kept = session.peek('code', 1n);
    expect(kept.ok && kept.value.value).toBe(0x2bn);
    const pc = session.get('pc');
    expect(pc.ok && pc.value.defined).toBe(0n);
    expect(events[events.length - 1]).toEqual({ kind: 'rebuilt' });
    // Pins and memories are the same topology, so the refs survive.
    expect(session.pins.map((p) => p.name)).toEqual(['pc', 'q']);
  });

  test('destroy ends the runtime and tells the faces once', async () => {
    const { session, rt, events } = await romSession();
    session.destroy();
    session.destroy();
    expect(rt().destroyed).toBe(true);
    expect(events.filter((e) => e.kind === 'destroyed')).toHaveLength(1);
    expect(session.isAlive).toBe(false);
  });
});

describe('widths', () => {
  test('a 64-bit pin takes a full 64-bit value and refuses a 65th bit', async () => {
    const wide = [
      { id: 0, kind: 0, name: 'w', width: 64 },
      { id: 1, kind: 5, name: 'o', width: 64 },
    ];
    const session = await SimSession.build({ bytes, load: async () => stubRuntime(wide) });
    expect(session.set('w', widthMask(64))).toEqual({ ok: true });
    expect(session.set('w', 1n << 64n)).toEqual({ ok: false, code: 'E_WIDTH', arg: 'w' });
    expect(session.set('w', 1n, 1n << 64n)).toEqual({ ok: false, code: 'E_WIDTH', arg: 'w' });
  });
});
