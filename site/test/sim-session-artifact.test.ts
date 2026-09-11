// The session over the real thing: an artifact compiled by the committed
// libcirc.wasm from the same fixtures `--sim`'s golden test drives, loaded
// into the renderer's CircRuntime. The stub tests prove what the session
// asks of a runtime; this proves the runtime answers as the CLI does.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { CircRuntime } from 'circ-renderer';
import { callOp, instantiateLibcirc, type LibcircExports } from '../src/scripts/libcirc-abi.ts';
import { SimSession } from '../src/scripts/sim-session.ts';

const skip = process.env.SKIP_LIBCIRC_TEST === '1';
const REPO = resolve(import.meta.dir, '..', '..');
const wasmPath = resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.wasm');

let cached: Promise<LibcircExports> | null = null;
const lib = () => (cached ??= instantiateLibcirc(readFileSync(wasmPath)));

/** Compile one fixture circuit the way the playground compiles a single file. */
async function artifact(name: string): Promise<Uint8Array> {
  const source = readFileSync(resolve(REPO, 'tests', 'fixtures', 'circuits', name), 'utf8');
  const out = callOp(await lib(), 'compile', { root: '/playground/main.circ', files: { '/playground/main.circ': source } });
  expect(out.status).toBe(0);
  return out.bytes;
}

// Floating pins after init, as `--sim` has them: the renderer's default drives
// every input low at load, which would make a first `set clk 1` an edge the
// CLI's transcript does not see.
const load = (bytes: Uint8Array) => CircRuntime.loadFromBytes(bytes, { noInitialPinDrive: true });
const hex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join(' ');

describe.skipIf(skip)('the session over a compiled artifact', () => {
  test('and_gate: the --sim transcript scenario, through CircRuntime', async () => {
    const session = await SimSession.build({ bytes: await artifact('and_gate.circ'), load });
    expect(session.pins.map((p) => `${p.name} ${p.kind} ${p.width}`)).toEqual(['a in 1', 'b in 1', 'out out 1']);
    expect(session.mems).toEqual([]);
    // Before any drive every pin is unknown, as after `init()`.
    const fresh = session.get('out');
    expect(fresh.ok && fresh.value.defined).toBe(0n);
    expect(session.set('a', 1n)).toEqual({ ok: true });
    expect(session.set('b', 1n)).toEqual({ ok: true });
    const out = session.get('out');
    expect(out.ok && out.value).toEqual({ value: 1n, defined: 1n, width: 1 });
    // An input reads back as driven.
    const a = session.get('a');
    expect(a.ok && a.value).toEqual({ value: 1n, defined: 1n, width: 1 });
    const vec = session.eval([{ pin: 'a', value: 1n }, { pin: 'b', value: 0n }], ['out']);
    expect(vec.ok && vec.values[0].value).toEqual({ value: 0n, defined: 1n, width: 1 });
    session.destroy();
  });

  test('sim_rom_pc_walk: the preload lands at build, a poke is mid-session, reset restores', async () => {
    const image = readFileSync(resolve(REPO, 'tests', 'fixtures', 'mem', 'rom_pc_walk.bin'));
    const bytes = await artifact('sim_rom_pc_walk.circ');
    const session = await SimSession.build({
      bytes,
      load,
      roms: [{ name: 'code', kind: 'rom', width: 8, addrWidth: 4 }],
      images: new Map([['code', hex(new Uint8Array(image))]]),
    });
    expect(session.mems).toEqual([{ name: 'code', id: session.mems[0].id, kind: 'rom', width: 8, addrWidth: 4 }]);
    expect(session.runtime.hasMemory).toBe(true);
    // Every word of the image is where the file put it.
    for (let addr = 0; addr < image.length; addr++) {
      const cell = session.peek('code', BigInt(addr));
      expect(cell.ok && cell.value).toEqual({ value: BigInt(image[addr]), defined: 0xffn, width: 8 });
    }
    // The rom reads asynchronously: driving pc settles instr to the cell.
    expect(session.set('pc', 3n)).toEqual({ ok: true });
    const instr = session.get('instr');
    expect(instr.ok && instr.value).toEqual({ value: BigInt(image[3]), defined: 0xffn, width: 8 });
    // A poke settles too, and is dropped by reset while the preload survives.
    expect(session.poke('code', 3n, 0x2an)).toEqual({ ok: true });
    const poked = session.get('instr');
    expect(poked.ok && poked.value.value).toBe(0x2an);
    const events: string[] = [];
    session.subscribe((e) => events.push(e.kind));
    await session.reset();
    expect(events).toEqual(['rebuilt']);
    const restored = session.peek('code', 3n);
    expect(restored.ok && restored.value.value).toBe(BigInt(image[3]));
    const pc = session.get('pc');
    expect(pc.ok && pc.value.defined).toBe(0n);
    // The whole memory stores back: the file's words, then unknown words as zero.
    const stored = session.storeImage('code');
    expect(stored.ok && stored.bytes.length).toBe(16);
    expect(stored.ok && Array.from(stored.bytes.slice(0, image.length))).toEqual(Array.from(image));
    expect(stored.ok && Array.from(stored.bytes.slice(image.length)).every((b) => b === 0)).toBe(true);
    session.destroy();
  });

  test('bootLow is the page\'s boot, and reset is the protocol\'s', async () => {
    const session = await SimSession.build({ bytes: await artifact('and_gate.circ'), load, bootLow: true });
    for (const name of ['a', 'b', 'out']) {
      const r = session.get(name);
      expect(r.ok && r.value).toEqual({ value: 0n, defined: 1n, width: 1 });
    }
    await session.reset();
    for (const name of ['a', 'b', 'out']) {
      const r = session.get(name);
      expect(r.ok && r.value.defined).toBe(0n);
    }
    session.destroy();
  });
});
