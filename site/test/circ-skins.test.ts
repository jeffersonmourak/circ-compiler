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
import { colorsDark, colorsLight, type PaletteKey } from '../src/utils/circ-palette.mjs';
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

describe('circ-palette', () => {
  test('both palettes define the same keys, and none of them is grid', () => {
    // The handoff's 28 keys: the site's 24 plus surface, spriteInk, wireBus
    // and busLabel, minus grid, which canvas.ts never read.
    const dark = Object.keys(colorsDark).sort();
    const light = Object.keys(colorsLight).sort();
    expect(light).toEqual(dark);
    expect(dark).toHaveLength(27);
    expect(dark).not.toContain('grid');
    for (const key of ['surface', 'spriteInk', 'wireBus', 'busLabel', 'labelOnComponent', 'inputHover']) {
      expect(dark).toContain(key);
    }
    for (const palette of [colorsDark, colorsLight]) {
      for (const [key, value] of Object.entries(palette)) {
        expect(`${key}: ${typeof value}`).toBe(`${key}: string`);
        expect(`${key}: ${/^(#[0-9a-f]{6}|hsl\([^)]*\))$/.test(value)}`).toBe(`${key}: true`);
      }
    }
  });

  test('idle wires are quieter than active ones in dark mode', () => {
    // The gap the handoff named: dark wireIdle was #dee2e6, the brightest
    // thing on the pane. Luminance of idle must sit below active.
    const lum = (hex: string) => {
      const n = parseInt(hex.slice(1), 16);
      return ((n >> 16) & 255) * 0.2126 + ((n >> 8) & 255) * 0.7152 + (n & 255) * 0.0722;
    };
    expect(lum(colorsDark.wireIdle)).toBeLessThan(lum(colorsDark.label));
    expect(colorsDark.wireIdle).toBe('#4c3a6b');
  });
});

describe('circ-skins', () => {
  const store = new Map<string, Record<string, Op[]>>();
  const skinsSource = readFileSync(resolve(import.meta.dir, '..', 'src', 'utils', 'circ-skins.mjs'), 'utf8');
  const paletteValues = new Set([...Object.values(colorsDark), ...Object.values(colorsLight)]);

  test('no skin sets a literal stroke width', () => {
    // The gap the handoff named: a 4px wire at every cell size. Every width
    // is a function of the cell now; a bare number is a regression.
    expect(skinsSource.match(/lineWidth\s*=\s*\d/g) ?? []).toEqual([]);
  });

  test('every colour a skin sets comes from the palette', () => {
    // A hex literal in a skin is a colour the theme flip cannot reach.
    for (const loaded of [false, true]) {
      const theme = themeWith(loaded);
      for (const kind of KINDS) for (const sig of SIGNALS) for (const width of WIDTHS) {
        const c = component(kind, width);
        const { ctx, ops } = recordingContext(14);
        const value = valueOf(sig, width);
        skinFor(theme, c)({
          ctx, theme, cell: 14, component: c,
          inputSignals: c.inPorts.map(() => sig), outputSignal: sig,
          inputValues: c.inPorts.map(() => value), outputValue: value, hovered: false,
        });
        for (const op of ops) {
          if (op[0] !== 'set' || (op[1] !== 'fillStyle' && op[1] !== 'strokeStyle')) continue;
          expect(`${kind}: ${String(op[2])}`).toMatch(new RegExp(`^${kind}: (${[...paletteValues].map((v) => v.replace(/[()]/g, '\\$&')).join('|')})$`));
        }
      }
    }
  });

  test('a bus tail is heavier and in the bus colour', () => {
    // An and gate fed by two 8-bit buses draws its input tails in wireBus at
    // 1.5× the wire weight; its 1-bit output tail stays in the signal colour.
    const theme = themeWith(true);
    const c = { ...component('and_gate', 1), bitWidth: 1 };
    const { ctx, ops } = recordingContext(20);
    const bus = valueOf(1, 8);
    skinFor(theme, c)({
      ctx, theme, cell: 20, component: c,
      inputSignals: [1, 1], outputSignal: 1,
      inputValues: [bus, bus], outputValue: valueOf(1, 1), hovered: false,
    });
    const strokes = ops.filter((op) => op[0] === 'set' && op[1] === 'strokeStyle').map((op) => op[2]);
    expect(strokes.slice(0, 3)).toEqual([colorsDark.wireBus, colorsDark.wireBus, colorsDark.wireActive]);
    const widths = ops.filter((op) => op[0] === 'set' && op[1] === 'lineWidth').map((op) => op[2]);
    expect(widths.slice(0, 3)).toEqual([6, 6, 4]);
  });

  test('the NOT gate names itself below its box, like every other part', () => {
    // Before: yOffset = -cell * 15 put the name 0.7 cells above the bottom
    // edge, inside the sprite.
    const theme = themeWith(true);
    const c = component('not_gate', 1);
    const { ctx, ops } = recordingContext(10);
    skinFor(theme, c)({
      ctx, theme, cell: 10, component: c,
      inputSignals: [0], outputSignal: 1, inputValues: [valueOf(0, 1)], outputValue: valueOf(1, 1), hovered: false,
    });
    const name = ops.find((op) => op[0] === 'fillText' && op[1] === 'n')!;
    expect(name).toBeDefined();
    // Below the box: y0 + h + 0.16 cell = 20 + 30 + 1.6.
    expect(name[3]).toBe(51.6);
  });

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
