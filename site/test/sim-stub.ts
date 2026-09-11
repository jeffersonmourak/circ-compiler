// A runtime the session can drive without a wasm module: values in a map, a
// `run` that evaluates whatever the test wires in, memories as arrays, and a
// log of every call so a test can prove what the session did — and did not —
// ask the runtime for.

import { ComponentKind, widthMask, type BitValue } from 'circ-renderer/topology';
import type { RuntimeLike, TopologyLike } from '../src/scripts/sim-session.ts';

export interface StubComponent {
  id: number;
  kind: ComponentKind;
  name: string;
  width: number;
  origin?: unknown[];
  memory?: { addrWidth: number };
}

export interface StubRuntime extends RuntimeLike {
  /** Every method call, in order: `set:0`, `run`, `read:3`, … */
  calls: string[];
  values: Map<number, BitValue>;
  cells: Map<number, { value: bigint; defined: bigint }[]>;
  destroyed: boolean;
}

const undef = (width: number): BitValue => ({ value: 0n, defined: 0n, width });

/**
 * A runtime over `components`. `evaluate` runs on every `run()` and may set
 * output values from input values, the way a circuit would.
 */
export function stubRuntime(
  components: readonly StubComponent[],
  evaluate: (values: Map<number, BitValue>, cells: StubRuntime['cells']) => void = () => {},
): StubRuntime {
  const topology: TopologyLike = {
    components: components.map((c) => ({ ...c, origin: c.origin ?? [] })),
  };
  const values = new Map<number, BitValue>();
  const cells = new Map<number, { value: bigint; defined: bigint }[]>();
  for (const c of components) {
    values.set(c.id, undef(c.width));
    if (c.memory) cells.set(c.id, Array.from({ length: 2 ** c.memory.addrWidth }, () => ({ value: 0n, defined: 0n })));
  }
  const calls: string[] = [];
  const mems = () =>
    components
      .filter((c) => c.memory && (c.origin ?? []).length === 0)
      .map((c) => ({
        id: c.id,
        name: c.name,
        info: { kind: c.kind === ComponentKind.Rom ? ('rom' as const) : ('ram' as const), width: c.width, addrWidth: c.memory!.addrWidth },
      }));
  const rt: StubRuntime = {
    topology,
    calls,
    values,
    cells,
    destroyed: false,
    setValue(id, value, defined) {
      calls.push(`set:${id}`);
      const width = values.get(id)?.width ?? 1;
      const mask = widthMask(width);
      values.set(id, { value: value & defined & mask, defined: defined & mask, width });
    },
    run() {
      calls.push('run');
      evaluate(values, cells);
    },
    readValue(id) {
      calls.push(`read:${id}`);
      return values.get(id) ?? undef(1);
    },
    get hasMemory() {
      return cells.size > 0;
    },
    memories: mems,
    readMemWord(id, addr) {
      calls.push(`peek:${id}:${addr}`);
      const c = cells.get(id)![addr];
      const width = components.find((k) => k.id === id)!.width;
      return { value: c.value, defined: c.defined, width };
    },
    writeMemWord(id, addr, value, defined) {
      calls.push(`poke:${id}:${addr}`);
      const row = cells.get(id);
      if (!row || addr >= row.length) return -7;
      row[addr] = { value: value & defined, defined };
      return 0;
    },
    loadMemImage(id, bytes) {
      calls.push(`load:${id}`);
      const c = components.find((k) => k.id === id)!;
      const bpw = (c.width + 7) >> 3;
      if (bytes.length % bpw !== 0) return -2;
      const row = cells.get(id)!;
      const words = bytes.length / bpw;
      if (words > row.length) return -4;
      const mask = widthMask(c.width);
      for (let i = 0; i < row.length; i++) {
        if (i < words) {
          let w = 0n;
          for (let k = 0; k < bpw; k++) w |= BigInt(bytes[i * bpw + k]) << BigInt(8 * k);
          if (w >> BigInt(c.width) !== 0n) return -3;
          row[i] = { value: w & mask, defined: mask };
        } else {
          row[i] = { value: 0n, defined: 0n };
        }
      }
      return 0;
    },
    storeMemImage(id) {
      calls.push(`store:${id}`);
      const c = components.find((k) => k.id === id)!;
      const bpw = (c.width + 7) >> 3;
      const row = cells.get(id)!;
      const out = new Uint8Array(row.length * bpw);
      row.forEach((cell, i) => {
        const w = cell.value & cell.defined;
        for (let k = 0; k < bpw; k++) out[i * bpw + k] = Number((w >> BigInt(8 * k)) & 0xffn);
      });
      return out;
    },
    clearMem(id) {
      calls.push(`clear:${id}`);
      const row = cells.get(id)!;
      for (let i = 0; i < row.length; i++) row[i] = { value: 0n, defined: 0n };
      return 0;
    },
    destroy() {
      calls.push('destroy');
      rt.destroyed = true;
    },
  };
  return rt;
}

/** `input a`, `input b`, `and g(a, b)`, `output out(g)`: the `and_gate.circ` fixture's shape. */
export const AND_GATE: StubComponent[] = [
  { id: 0, kind: ComponentKind.InputPin, name: 'a', width: 1 },
  { id: 1, kind: ComponentKind.InputPin, name: 'b', width: 1 },
  { id: 2, kind: ComponentKind.AndGate, name: 'g', width: 1 },
  { id: 3, kind: ComponentKind.OutputPin, name: 'out', width: 1 },
];

/** The AND's semantics, for the stub's `run`: defined only when both inputs are. */
export function evaluateAnd(values: Map<number, BitValue>): void {
  const a = values.get(0)!;
  const b = values.get(1)!;
  const defined = a.defined & b.defined & 1n;
  const value = a.value & b.value & defined;
  values.set(2, { value, defined, width: 1 });
  values.set(3, { value, defined, width: 1 });
}

/** `input[4] pc`, `rom code[8,4]`, `ram data[8,2]`, `output[8] q`, plus a nested rom the session must skip. */
export const MEMORIES: StubComponent[] = [
  { id: 0, kind: ComponentKind.InputPin, name: 'pc', width: 4 },
  { id: 1, kind: ComponentKind.Rom, name: 'code', width: 8, memory: { addrWidth: 4 } },
  { id: 2, kind: ComponentKind.Ram, name: 'data', width: 8, memory: { addrWidth: 2 } },
  { id: 3, kind: ComponentKind.OutputPin, name: 'q', width: 8 },
  { id: 4, kind: ComponentKind.Rom, name: 'inner', width: 8, memory: { addrWidth: 2 }, origin: [{ alias: 'm', subcircuit: 'wrap', targetFile: 1 }] },
  { id: 5, kind: ComponentKind.InputPin, name: 'hidden', width: 1, origin: [{ alias: 'm', subcircuit: 'wrap', targetFile: 1 }] },
];

/** A rom whose `q` follows `code[pc]`, for the memory tests. */
export function evaluateRom(values: Map<number, BitValue>, cells: StubRuntime['cells']): void {
  const pc = values.get(0)!;
  const rom = cells.get(1)!;
  if ((pc.defined & 0xfn) !== 0xfn) {
    values.set(3, { value: 0n, defined: 0n, width: 8 });
    return;
  }
  const cell = rom[Number(pc.value & 0xfn)];
  values.set(3, { value: cell.value, defined: cell.defined, width: 8 });
}
