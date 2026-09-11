// What every site skin draws, pinned as an op log.
//
// Each registered skin is run over a fixed component at three cell sizes, the
// three signals, one and eight bits, with and without sprites, into the
// recording context of `canvas-record.ts`; the calls it made are compared to
// `fixtures/skins/<kind>.json`. `UPDATE_GOLDENS=1 bun test` rewrites the
// goldens; diff them like any other. The wire and highlight hooks are pinned
// the same way.
//
// Two properties hold for every log whatever the golden says: `save` and
// `restore` balance, because a skin that leaves state behind corrupts what
// is drawn after it, and nothing throws.
import { describe, expect, test } from 'bun:test';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ComponentKind, widthMask } from 'circ-renderer/topology';
import type { BitValue } from 'circ-renderer/topology';
import type { CircTheme, PlacedComponent, RoutedWire } from 'circ-renderer';
import { colorsDark, type PaletteKey } from '../src/utils/circ-palette.mjs';
import { makeSkins } from '../src/utils/circ-skins.mjs';
import { recordingContext, stubAssets, type Op } from './canvas-record.ts';

const GOLDENS = resolve(import.meta.dir, 'fixtures', 'skins');
const UPDATE = process.env.UPDATE_GOLDENS === '1';

const CELLS = [10, 14, 24];
const SIGNALS = [0, 1, 2] as const;
const WIDTHS = [1, 8];

type Signal = 0 | 1 | 2;

function valueOf(sig: Signal, width: number): BitValue {
  const mask = widthMask(width);
  if (sig === 2) return { value: 0n, defined: 0n, width };
  return { value: sig === 1 ? (width > 1 ? 0xa5n & mask : 1n) : 0n, defined: mask, width };
}

const X = 2;
const Y = 2;
const port = (name: string, dy: number) => ({ portName: name, coord: { x: X - 1, y: Y + dy } });
const prim = (kind: ComponentKind) => ({ tag: 'primitive' as const, kind });

/** One fixed component per kind the site registers a skin for. */
function component(kind: string, bitWidth: number): PlacedComponent {
  const base = { id: 7, origin: [], x: X, y: Y, bitWidth };
  switch (kind) {
    case 'input_pin':
      return { ...base, kind: prim(ComponentKind.InputPin), name: 'a', width: 5, height: 3, inPorts: [], outPort: { x: X + 5, y: Y + 1 } };
    case 'output_pin':
      return { ...base, kind: prim(ComponentKind.OutputPin), name: 'q', width: 5, height: 3, inPorts: [port('in', 1)], outPort: { x: X + 5, y: Y + 1 } };
    case 'led':
      return { ...base, kind: prim(ComponentKind.Led), name: 'l', width: 5, height: 3, inPorts: [port('in', 1)], outPort: { x: X + 5, y: Y + 1 } };
    case 'not_gate':
      return { ...base, kind: prim(ComponentKind.NotGate), name: 'n', width: 5, height: 3, inPorts: [port('in', 1)], outPort: { x: X + 5, y: Y + 1 } };
    case 'and_gate':
      return { ...base, kind: prim(ComponentKind.AndGate), name: 'g', width: 5, height: 5, inPorts: [port('a', 1), port('b', 3)], outPort: { x: X + 5, y: Y + 2 } };
    case 'slice':
      return { ...base, kind: prim(ComponentKind.Slice), name: '', width: 5, height: 3, inPorts: [port('in', 1)], outPort: { x: X + 5, y: Y + 1 }, slice: { lo: 0, hi: 4 } };
    case 'concat':
      return { ...base, kind: prim(ComponentKind.Concat), name: '', width: 5, height: 5, inPorts: [port('op0', 1), port('op1', 3)], outPort: { x: X + 5, y: Y + 2 } };
    case 'rom':
      return { ...base, kind: prim(ComponentKind.Rom), name: 'code', width: 17, height: 3, inPorts: [port('addr', 1)], outPort: { x: X + 17, y: Y + 1 }, memory: { addrWidth: 4 } };
    case 'ram':
      return { ...base, kind: prim(ComponentKind.Ram), name: 'data', width: 17, height: 9, inPorts: [port('addr', 1), port('din', 3), port('we', 5), port('clk', 7)], outPort: { x: X + 17, y: Y + 4 }, memory: { addrWidth: 4 } };
    case 'subcircuit_builtin':
      return { ...base, kind: { tag: 'subcircuit', subcircuit: 'xor' }, name: 's', width: 9, height: 5, inPorts: [port('a', 1), port('b', 3)], outPort: { x: X + 9, y: Y + 2 } };
    case 'subcircuit_user':
      return { ...base, kind: { tag: 'subcircuit', subcircuit: 'adder' }, name: 'u', width: 11, height: 5, inPorts: [port('a', 1), port('b', 3)], outPort: { x: X + 11, y: Y + 2 } };
  }
  throw new Error(`no fixture component for ${kind}`);
}

const KINDS = [
  'input_pin', 'output_pin', 'led', 'not_gate', 'and_gate', 'slice', 'concat', 'rom', 'ram',
  'subcircuit_builtin', 'subcircuit_user',
];

type Theme = CircTheme<PaletteKey>;

/** The dark theme over the stub assets, typed as the renderer sees it. */
function themeWith(loaded: boolean): Theme {
  return { colors: colorsDark, ...(makeSkins(stubAssets(loaded)) as unknown as Omit<Theme, 'colors'>) };
}

function skinFor(theme: Theme, c: PlacedComponent) {
  const skins = theme.skins as Record<string | number, unknown>;
  const key = c.kind.tag === 'primitive' ? c.kind.kind : 'subcircuit';
  const skin = skins[key];
  if (typeof skin !== 'function') throw new Error(`no skin registered for ${String(key)}`);
  return skin as (args: unknown) => void;
}

/** Compare a log to its golden entry, or write it under UPDATE_GOLDENS. */
function checkGolden(file: string, key: string, ops: Op[], store: Map<string, Record<string, Op[]>>) {
  const path = resolve(GOLDENS, `${file}.json`);
  if (!store.has(file)) {
    store.set(file, existsSync(path) ? (JSON.parse(readFileSync(path, 'utf8')) as Record<string, Op[]>) : {});
  }
  const golden = store.get(file)!;
  if (UPDATE) {
    golden[key] = ops;
    return;
  }
  expect(golden[key], `${file}.json has no entry ${key}; run UPDATE_GOLDENS=1 bun test`).toBeDefined();
  expect(ops).toEqual(golden[key]);
}

function flush(store: Map<string, Record<string, Op[]>>) {
  if (!UPDATE) return;
  mkdirSync(GOLDENS, { recursive: true });
  for (const [file, golden] of store) {
    const sorted = Object.fromEntries(Object.keys(golden).sort().map((k) => [k, golden[k]]));
    writeFileSync(resolve(GOLDENS, `${file}.json`), JSON.stringify(sorted, null, 1) + '\n');
  }
}

const balanced = (ops: Op[]) => {
  const count = (name: string) => ops.filter((op) => op[0] === name).length;
  return count('save') === count('restore');
};

describe('circ-skins', () => {
  const store = new Map<string, Record<string, Op[]>>();

  for (const kind of KINDS) {
    test(`${kind}: every combination draws as its golden says`, () => {
      for (const loaded of [false, true]) {
        const theme = themeWith(loaded);
        for (const cell of CELLS) for (const sig of SIGNALS) for (const width of WIDTHS) {
          const c = component(kind, width);
          const { ctx, ops } = recordingContext(cell);
          const value = valueOf(sig, width);
          skinFor(theme, c)({
            ctx, theme, cell, component: c,
            inputSignals: c.inPorts.map(() => sig),
            outputSignal: sig,
            inputValues: c.inPorts.map(() => value),
            outputValue: value,
            hovered: false,
          });
          expect(balanced(ops)).toBe(true);
          checkGolden(kind, `${loaded ? 'sprites' : 'vector'}.sig${sig}.w${width}.c${cell}`, ops, store);
        }
      }
      flush(store);
    });
  }

  test('wire: straight, cornered and crossed wires draw as the golden says', () => {
    const theme = themeWith(true);
    const seg = (x0: number, y0: number, x1: number, y1: number) => ({ from: { x: x0, y: y0 }, to: { x: x1, y: y1 } });
    const shapes: Record<string, Pick<RoutedWire, 'segments' | 'crossings'>> = {
      straight: { segments: [seg(0, 1, 8, 1)], crossings: [] },
      corner: { segments: [seg(0, 0, 4, 0), seg(4, 0, 4, 2), seg(4, 2, 8, 2)], crossings: [] },
      crossed: { segments: [seg(0, 0, 4, 0), seg(4, 0, 4, 2), seg(4, 2, 8, 2)], crossings: [{ x: 2, y: 0 }] },
    };
    for (const [name, shape] of Object.entries(shapes)) {
      for (const cell of CELLS) for (const sig of SIGNALS) for (const width of WIDTHS) {
        const wire: RoutedWire = { srcId: 1, srcPort: 3, dstId: 2, dstPort: 0, realSrcId: 1, ...shape };
        const value = valueOf(sig, width);
        const { ctx, ops } = recordingContext(cell);
        theme.wire!({ ctx, theme, cell, wire, signal: sig, value, conflictTier: 0 });
        expect(balanced(ops)).toBe(true);
        checkGolden('wire', `${name}.sig${sig}.w${width}.c${cell}`, ops, store);
      }
    }
    flush(store);
  });

  test('highlight: the ring for every kind draws as the golden says', () => {
    const theme = themeWith(true);
    for (const kind of KINDS) for (const cell of CELLS) {
      const c = component(kind, 1);
      const { ctx, ops } = recordingContext(cell);
      theme.highlight!({ ctx, theme, cell, component: c, reason: 'hover' });
      expect(balanced(ops)).toBe(true);
      checkGolden('highlight', `${kind}.c${cell}`, ops, store);
    }
    flush(store);
  });

  test('background clears rather than fills, so the pane shows through', () => {
    const theme = themeWith(true);
    const { ctx, ops } = recordingContext(14);
    theme.background!({ ctx, theme, cell: 14, width: 10, height: 4 });
    expect(ops.map((op) => op[0])).toEqual(['clearRect']);
    expect(ops.some((op) => op[0] === 'fillRect')).toBe(false);
  });
});
