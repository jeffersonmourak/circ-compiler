// The two shipped adders actually add.
//
// Their sources were rewritten from loose bits onto buses, and a rewrite of
// arithmetic is exactly the kind that stays plausible while being wrong: the
// preview still draws, the canvas still runs, every gate still passes, and one
// lane quietly drops a carry. So the committed artifacts are driven here over
// their whole input space and checked against the arithmetic they claim.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ComponentKind, decodeFullTopology } from 'circ-renderer';
import { examples } from '../src/content/examples.ts';

const WASM = resolve(import.meta.dir, '..', 'public', 'wasm');

/** Instantiate an artifact and expose its root pins by name. */
async function boot(file: string) {
  const bytes = readFileSync(resolve(WASM, file));
  const mod = await WebAssembly.compile(bytes as unknown as BufferSource);
  const { exports } = await WebAssembly.instantiate(mod, {
    env: { debugEnabled: () => 0, onDebugLog: () => {} },
  });
  const w = exports as unknown as Record<string, (...a: never[]) => never> & {
    memory: { buffer: ArrayBufferLike };
  };
  const [min] = WebAssembly.Module.customSections(mod, 'circ.topology.v0.min');
  const topo = new Uint8Array(min);
  const ptr = (w.topology_alloc as unknown as (n: number) => number)(topo.length);
  new Uint8Array(w.memory.buffer).set(topo, ptr);
  (w.init as unknown as () => void)();

  const [full] = WebAssembly.Module.customSections(mod, 'circ.topology.v0.full');
  const decoded = decodeFullTopology(new Uint8Array(full)) as unknown as {
    components: { id: number; name: string; kind: number; origin?: unknown[] }[];
  };
  const idOf = (name: string, kind: number): number => {
    const c = decoded.components.find(
      (x) => x.name === name && x.kind === kind && (x.origin?.length ?? 0) === 0,
    );
    if (!c) throw new Error(`${file} has no top-level ${kind} named ${name}`);
    return c.id;
  };
  return {
    setPin: (name: string, value: bigint, defined: bigint) =>
      (w.setPin as unknown as (i: number, v: bigint, d: bigint) => void)(
        idOf(name, ComponentKind.InputPin), value, defined,
      ),
    run: () => (w.run as unknown as () => void)(),
    read: (name: string) => ({
      value: BigInt((w.getOutputValue as unknown as (i: number) => bigint)(idOf(name, ComponentKind.OutputPin))),
      defined: BigInt((w.getOutputDefined as unknown as (i: number) => bigint)(idOf(name, ComponentKind.OutputPin))),
    }),
  };
}

/** Drive every pair of operands and report the first sum that is wrong. */
async function checkAdder(file: string, width: number) {
  const circuit = await boot(file);
  const mask = (1n << BigInt(width)) - 1n;
  const wrong: string[] = [];
  for (let a = 0; a <= Number(mask); a += 1) {
    for (let b = 0; b <= Number(mask); b += 1) {
      circuit.setPin('a', BigInt(a), mask);
      circuit.setPin('b', BigInt(b), mask);
      circuit.run();
      const s = circuit.read('s');
      const cout = circuit.read('cout');
      // Undefined anywhere means the circuit never settled, which is a
      // different failure from a wrong number and must not be read as one.
      if (s.defined !== mask || cout.defined !== 1n) {
        wrong.push(`${a}+${b}: undefined output`);
        continue;
      }
      const got = s.value + (cout.value << BigInt(width));
      if (got !== BigInt(a + b)) wrong.push(`${a}+${b} = ${got}`);
    }
  }
  return wrong;
}

describe('the shipped ripple-carry adders', () => {
  test('both take their operands as buses, not as loose bits', () => {
    // This is the shape the rewrite was for: one column per operand in the
    // truth table rather than one per bit.
    for (const slug of ['two-bit-adder', 'four-bit-adder']) {
      const source = examples.find((e) => e.slug === slug)!.source;
      expect(`${slug}: ${/^input\[\d+\] a, b$/m.test(source)}`).toBe(`${slug}: true`);
      expect(`${slug}: ${/^output\[\d+\] s\(in=\{/m.test(source)}`).toBe(`${slug}: true`);
      // …and no leftover per-bit inputs from the version this replaced.
      expect(source).not.toMatch(/^input a0/m);
    }
  });

  test('the 2-bit adder is right for all 16 pairs', async () => {
    expect(await checkAdder('two-bit-adder.wasm', 2)).toEqual([]);
  });

  test('the 4-bit adder is right for all 256 pairs', async () => {
    expect(await checkAdder('four-bit-adder.wasm', 4)).toEqual([]);
  });

  test('the carry out of the top is the one that matters', async () => {
    // The case a rewrite loses first: the sum wraps and the carry has to be
    // the thing that says so.
    const four = await boot('four-bit-adder.wasm');
    four.setPin('a', 15n, 15n);
    four.setPin('b', 1n, 15n);
    four.run();
    expect(four.read('s').value).toBe(0n);
    expect(four.read('cout').value).toBe(1n);
  });
});
