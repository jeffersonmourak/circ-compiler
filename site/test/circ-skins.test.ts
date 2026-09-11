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
import { gateGeometry, makeSkins, spriteArt } from '../src/utils/circ-skins.mjs';
import { STUB_BOUNDS, recordingContext, stubAssets, type Op } from './canvas-record.ts';

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

describe('sprite art', () => {
  test('a tint, a halo and the bounds are each built once per name and colour', () => {
    const assets = stubAssets(true);
    makeSkins(assets);
    const ink = colorsDark.spriteInk;
    const a = spriteArt.tinted('AND', ink, 0.94);
    const b = spriteArt.tinted('AND', ink, 0.94);
    expect(a).toBe(b);
    expect(assets.calls.offscreen).toBe(1);
    // Another colour or alpha is another tint.
    spriteArt.tinted('AND', colorsDark.inputOn, 0.92);
    expect(assets.calls.offscreen).toBe(2);
    // A halo builds its own canvas over a tint at alpha 1.
    const h1 = spriteArt.halo('AND', colorsDark.inputOn);
    const h2 = spriteArt.halo('AND', colorsDark.inputOn);
    expect(h1).toBe(h2);
    expect(assets.calls.offscreen).toBe(4); // + tint at alpha 1, + the halo
    // Bounds are asked of the page once per name.
    expect(spriteArt.bounds('AND')).toEqual(STUB_BOUNDS);
    spriteArt.bounds('AND');
    expect(assets.calls.bounds).toBe(1);
    // The halo is padded by 0.14 of the sprite on every side.
    const halo = assets.offscreens[assets.offscreens.length - 1];
    expect([halo.width, halo.height]).toEqual([128, 128]);
    // The blur runs at build time, on the offscreen canvas, never on the page.
    expect(halo.recording.ops.some((op) => op[0] === 'set' && op[1] === 'shadowBlur')).toBe(true);
  });

  test('before the sprites decode nothing is built, and nothing is cached as missing', () => {
    const cold = stubAssets(false);
    makeSkins(cold);
    expect(spriteArt.tinted('AND', colorsDark.spriteInk, 0.94)).toBeNull();
    expect(spriteArt.halo('AND', colorsDark.inputOn)).toBeNull();
    expect(spriteArt.bounds('AND')).toEqual({ l: 0.2, r: 0.84, t: 0.2, b: 0.8, apex: 0.2 });
    expect(cold.calls.offscreen).toBe(0);
    // Rebinding to decoded sprites — the sprite-ready retheme — starts clean.
    const warm = stubAssets(true);
    makeSkins(warm);
    expect(spriteArt.tinted('AND', colorsDark.spriteInk, 0.94)).not.toBeNull();
    expect(spriteArt.bounds('AND')).toEqual(STUB_BOUNDS);
    expect(warm.calls.offscreen).toBe(1);
  });

  test('the sprite module still exports what the page decodes', () => {
    const assets = readFileSync(resolve(import.meta.dir, '..', 'src', 'utils', 'circ-assets.mjs'), 'utf8');
    const exported = [...assets.matchAll(/^export const (\w+)/gm)].map((m) => m[1]).sort();
    expect(exported).toEqual(['AND', 'NAND', 'NOT', 'OR', 'XOR']);
  });
});

describe('gate anatomy', () => {
  const cell = 14;
  const box = component('and_gate', 1); // 5×5 at (2,2), ports a at y+1, b at y+3
  const or = { ...STUB_BOUNDS };
  const RECIPES = {
    and: {}, nand: { negate: true },
    or: {}, nor: { negate: true }, xor: { exclusive: true }, xnor: { exclusive: true, negate: true },
  } as const;

  test('the three containers are inset and never touch', () => {
    const L = gateGeometry(cell, box, or, {});
    const x0 = box.x * cell, w = box.width * cell;
    expect(L.innerL).toBeCloseTo(x0 + 0.4 * cell, 9);
    expect(L.innerR).toBeCloseTo(x0 + w - 0.4 * cell, 9);
    expect(L.exclusive.right - L.exclusive.left).toBeCloseTo(0.55 * cell, 9);
    expect(L.negate.right - L.negate.left).toBeCloseTo(0.55 * cell, 9);
    expect(L.gate.left).toBe(L.exclusive.right);
    expect(L.gate.right).toBe(L.negate.left);
  });

  test('the symbol is sized by the port spread and the gate slot, whichever binds', () => {
    const L = gateGeometry(cell, box, or, {});
    const paintedH = or.b - or.t, paintedW = or.r - or.l;
    // Two inputs two cells apart: four cells of painted height.
    const expected = Math.min((4 * cell) / paintedH, L.rect.gateW / paintedW);
    expect(L.rect.size).toBe(expected);
    // The painted art is centred on the span, so its lobes sit on the port rows.
    const artMid = (L.rect.artL + L.rect.artR) / 2;
    expect(Math.abs(artMid - L.rect.cx)).toBeLessThan(1e-9);
  });

  test('a negated pair, and an exclusive pair, share one symbol size', () => {
    for (const [a, b] of [['and', 'nand'], ['or', 'nor'], ['xor', 'xnor']] as const) {
      const sa = gateGeometry(cell, box, or, RECIPES[a]).rect.size;
      const sb = gateGeometry(cell, box, or, RECIPES[b]).rect.size;
      expect(`${a}/${b}: ${sa === sb}`).toBe(`${a}/${b}: true`);
    }
  });

  test('an unused slot lends its width: the symbol recentres, never resizes', () => {
    const plain = gateGeometry(cell, box, or, {});
    const negated = gateGeometry(cell, box, or, { negate: true });
    expect(negated.rect.size).toBe(plain.rect.size);
    expect(negated.rect.cx).toBeLessThan(plain.rect.cx);
    const excl = gateGeometry(cell, box, or, { exclusive: true });
    expect(excl.rect.cx).toBeGreaterThan(plain.rect.cx);
  });

  test('the negate bubble is tangent to the measured tip, clamped inside its slot', () => {
    const L = gateGeometry(cell, box, or, { negate: true });
    const r = Math.min(0.24 * cell, (L.negate.right - L.negate.left) / 2 - 0.03 * cell);
    const tangent = L.rect.artR + 0.14 * cell + r;
    const bx = Math.min(L.negate.right - r, Math.max(L.negate.left + r, tangent));
    expect(bx - r).toBeGreaterThanOrEqual(L.negate.left);
    expect(bx + r).toBeLessThanOrEqual(L.negate.right);
    // The symbol keeps its size when a slot is used, so with a wide OR the art
    // ends a little inside the gate slot and the bubble sits at the slot's
    // left edge, the nearest it can be to the tip.
    expect(L.rect.artR).toBeLessThan(L.negate.left);
    expect(bx).toBe(L.negate.left + r);
    expect(tangent).toBeLessThan(bx);
  });

  test("the exclusive curve nests in the OR's back, apex just left of the back's own", () => {
    const L = gateGeometry(cell, box, or, { exclusive: true });
    const lw = Math.max(2, cell * 0.2);
    // The back apex is inside the art's box: the lobe tips are its left edge.
    expect(L.rect.apexX).toBeGreaterThan(L.rect.artL);
    expect(L.rect.depth).toBeCloseTo((or.apex - or.l) * L.rect.size, 9);
    const xTip = L.rect.apexX - 0.14 * cell - lw / 2;
    expect(xTip).toBeLessThan(L.rect.apexX);
    const xEnd = Math.max(L.exclusive.left + lw / 2, xTip - L.rect.depth);
    expect(xEnd).toBeLessThan(xTip);
    expect(xEnd - lw / 2).toBeGreaterThanOrEqual(L.exclusive.left);
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

  test('an AND is the tinted sprite, haloed when HIGH, and a D-shape before the sprites decode', () => {
    const run = (loaded: boolean, sig: Signal) => {
      const theme = themeWith(loaded);
      const c = component('and_gate', 1);
      const { ctx, ops } = recordingContext(14);
      const v = valueOf(sig, 1);
      skinFor(theme, c)({
        ctx, theme, cell: 14, component: c, inputSignals: [sig, sig], outputSignal: sig,
        inputValues: [v, v], outputValue: v, hovered: false,
      });
      return ops;
    };
    const images = (ops: Op[]) => ops.filter((op) => op[0] === 'drawImage').map((op) => op[1]);
    // HIGH: the halo (padded canvas) under the tinted art, after the three tails.
    const high = run(true, 1);
    expect(images(high)).toEqual(['canvas:128x128', 'canvas:100x100']);
    expect(high.filter((op) => op[0] === 'stroke').length).toBeGreaterThanOrEqual(3);
    expect(high.findIndex((op) => op[0] === 'drawImage')).toBeGreaterThan(high.findIndex((op) => op[0] === 'stroke'));
    // Rotated a quarter turn before the art is drawn, and the qualifier on top.
    expect(high.some((op) => op[0] === 'rotate' && op[1] === 1.571)).toBe(true);
    expect(high.some((op) => op[0] === 'fillText' && op[1] === '&')).toBe(true);
    // LOW: the art alone, in the palette's ink.
    const low = run(true, 0);
    expect(images(low)).toEqual(['canvas:100x100']);
    // Before the sprites decode: a vector D-shape, no image.
    const cold = run(false, 1);
    expect(images(cold)).toEqual([]);
    expect(cold.some((op) => op[0] === 'bezierCurveTo')).toBe(true);
  });

  test('a NOT is the triangle plus the one standard bubble, no PNG', () => {
    const theme = themeWith(true);
    const c = component('not_gate', 1);
    const { ctx, ops } = recordingContext(14);
    skinFor(theme, c)({
      ctx, theme, cell: 14, component: c, inputSignals: [0], outputSignal: 1,
      inputValues: [valueOf(0, 1)], outputValue: valueOf(1, 1), hovered: false,
    });
    expect(ops.some((op) => op[0] === 'drawImage' && String(op[1]).startsWith('sprite:'))).toBe(false);
    const names = ops.map((op) => op[0]);
    // The triangle: move, two lines, close, fill.
    const tri = names.indexOf('closePath');
    expect(names.slice(tri - 3, tri + 2)).toEqual(['moveTo', 'lineTo', 'lineTo', 'closePath', 'fill']);
    // One bubble at r = 0.24 cell inside the negate slot (the terminal dots
    // share that radius but sit outside the box's inset).
    const x0 = c.x * 14, innerR = x0 + c.width * 14 - 0.4 * 14;
    const bubbles = ops.filter((op) => op[0] === 'arc' && op[3] === 3.36 && Number(op[1]) >= innerR - 0.55 * 14 && Number(op[1]) <= innerR);
    expect(bubbles).toHaveLength(1);
    // HIGH: the triangle's halo came from an offscreen canvas.
    expect(ops.some((op) => op[0] === 'drawImage' && String(op[1]).startsWith('canvas:'))).toBe(true);
  });

  test('a builtin macro draws through the recipe on a virtual box, tails to the real ports', () => {
    const theme = themeWith(true);
    const names = ['and', 'nand', 'or', 'nor', 'xor', 'xnor', 'not'];
    for (const name of names) {
      const base = component('subcircuit_builtin', 1);
      const two = name !== 'not';
      const c: PlacedComponent = {
        ...base,
        kind: { tag: 'subcircuit', subcircuit: name },
        height: two ? 5 : 3,
        inPorts: two ? base.inPorts : [{ portName: 'in', coord: { x: X - 1, y: Y + 1 } }],
        outPort: { x: X + base.width, y: Y + (two ? 2 : 1) },
      };
      const { ctx, ops } = recordingContext(10);
      const sig = 1;
      skinFor(theme, c)({
        ctx, theme, cell: 10, component: c, inputSignals: c.inPorts.map(() => sig), outputSignal: sig,
        inputValues: c.inPorts.map(() => valueOf(sig, 1)), outputValue: valueOf(sig, 1), hovered: false,
      });
      // The virtual 5-wide box centred in the 9-wide macro box: x = 2 + 2 = 4.
      const vx = (c.x + (c.width - 5) / 2) * 10;
      const innerL = vx + 4, innerR = vx + 50 - 4;
      // Tails: from each real port's centre to the virtual box's inset edge.
      const lines = ops.filter((op) => op[0] === 'lineTo');
      const moves = ops.filter((op) => op[0] === 'moveTo');
      for (const p of c.inPorts) {
        const py = p.coord.y * 10 + 5;
        expect(`${name} in: ${moves.some((m) => m[1] === innerL - 4 && m[2] === py)}`).toBe(`${name} in: true`);
        expect(`${name} in: ${lines.some((l) => l[1] === p.coord.x * 10 + 5 && l[2] === py)}`).toBe(`${name} in: true`);
      }
      const oy = c.outPort.y * 10 + 5;
      expect(`${name} out: ${moves.some((m) => m[1] === innerR + 4 && m[2] === oy)}`).toBe(`${name} out: true`);
      expect(`${name} out: ${lines.some((l) => l[1] === c.outPort.x * 10 + 5 && l[2] === oy)}`).toBe(`${name} out: true`);
      // The symbol: tinted sprite art for the six (a 100×100 canvas), the
      // triangle for not, whose only image is its halo; a bubble for the negated four.
      const art = ops.filter((op) => op[0] === 'drawImage' && op[1] === 'canvas:100x100').length;
      expect(`${name}: ${art}`).toBe(`${name}: ${name === 'not' ? 0 : 1}`);
      const negated = ['nand', 'nor', 'xnor', 'not'].includes(name);
      const bubbles = ops.filter((op) => op[0] === 'arc' && op[3] === 2.4 && Number(op[1]) >= innerR - 5.5 && Number(op[1]) <= innerR);
      expect(`${name}: ${bubbles.length}`).toBe(`${name}: ${negated ? 1 : 0}`);
      const exclusive = ['xor', 'xnor'].includes(name);
      expect(`${name}: ${ops.some((op) => op[0] === 'quadraticCurveTo')}`).toBe(`${name}: ${exclusive}`);
      // The instance name below the real box.
      const label = ops.find((op) => op[0] === 'fillText' && op[1] === 's')!;
      expect(label[2]).toBe((c.x + c.width / 2) * 10);
    }
  });

  test('a user subcircuit still takes the labelled box', () => {
    const theme = themeWith(true);
    const c = component('subcircuit_user', 1);
    const { ctx, ops } = recordingContext(10);
    skinFor(theme, c)({
      ctx, theme, cell: 10, component: c, inputSignals: [0, 0], outputSignal: 0,
      inputValues: [valueOf(0, 1), valueOf(0, 1)], outputValue: valueOf(0, 1), hovered: false,
    });
    expect(ops.some((op) => op[0] === 'roundRect')).toBe(true);
    expect(ops.some((op) => op[0] === 'drawImage')).toBe(false);
    expect(ops.some((op) => op[0] === 'fillText' && op[1] === 'adder')).toBe(true);
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

  test('the wire hook rounds corners, keeps them across a crossing, and strokes a bus heavier', () => {
    const theme = themeWith(true);
    const seg = (x0: number, y0: number, x1: number, y1: number) => ({ from: { x: x0, y: y0 }, to: { x: x1, y: y1 } });
    const draw = (segments: RoutedWire['segments'], crossings: RoutedWire['crossings'], sig: Signal, width: number, cell = 20) => {
      const wire: RoutedWire = { srcId: 1, srcPort: 3, dstId: 2, dstPort: 0, realSrcId: 1, segments, crossings };
      const { ctx, ops } = recordingContext(cell);
      theme.wire!({ ctx, theme, cell, wire, signal: sig, value: valueOf(sig, width), conflictTier: 0 });
      return ops;
    };
    const count = (ops: Op[], name: string) => ops.filter((op) => op[0] === name).length;
    const corner = [seg(0, 0, 4, 0), seg(4, 0, 4, 2), seg(4, 2, 8, 2)];

    // Idle, one bit: one pass, one subpath, a rounded corner at each bend.
    const idle = draw(corner, [], 0, 1);
    expect(count(idle, 'stroke')).toBe(1);
    expect(count(idle, 'moveTo')).toBe(1);
    expect(count(idle, 'arcTo')).toBe(2);
    expect(idle.find((op) => op[0] === 'set' && op[1] === 'strokeStyle')![2]).toBe(colorsDark.wireIdle);
    expect(idle.find((op) => op[0] === 'set' && op[1] === 'lineWidth')![2]).toBe(4);

    // A crossing on the first run is one hop, and the corners stay.
    const crossed = draw(corner, [{ x: 2, y: 0 }], 0, 1);
    expect(count(crossed, 'arc')).toBe(1);
    expect(count(crossed, 'arcTo')).toBe(2);
    expect(count(crossed, 'moveTo')).toBe(1);

    // Active, one bit: the glow pass first, translucent and wider, then the colour.
    const active = draw(corner, [], 1, 1);
    expect(count(active, 'stroke')).toBe(2);
    const alphas = active.filter((op) => op[0] === 'set' && op[1] === 'globalAlpha').map((op) => op[2]);
    expect(alphas).toEqual([0.22]);
    const widths = active.filter((op) => op[0] === 'set' && op[1] === 'lineWidth').map((op) => op[2]);
    expect(widths).toEqual([14, 4]);
    expect(count(active, 'save')).toBe(count(active, 'restore'));

    // A bus: 1.5× in wireBus, no glow, and the bit-count slash with its number.
    const bus = draw([seg(0, 1, 8, 1)], [], 1, 8);
    expect(count(bus, 'stroke')).toBe(2); // the wire and the slash
    expect(bus.find((op) => op[0] === 'set' && op[1] === 'strokeStyle')![2]).toBe(colorsDark.wireBus);
    expect(bus.find((op) => op[0] === 'set' && op[1] === 'lineWidth')![2]).toBe(6);
    expect(bus.some((op) => op[0] === 'fillText' && op[1] === '8')).toBe(true);
    expect(count(bus, 'globalAlpha')).toBe(0);

    // A bus with an unknown bit is undefined, not a bus: no slash.
    const half = draw([seg(0, 1, 8, 1)], [], 2, 8);
    expect(half.find((op) => op[0] === 'set' && op[1] === 'strokeStyle')![2]).toBe(colorsDark.wireUndefined);
    expect(half.some((op) => op[0] === 'fillText')).toBe(false);
  });

  test('fan-out: a ring in the wire colour with the centre knocked out to alpha', () => {
    const theme = themeWith(true);
    for (const cell of CELLS) for (const sig of SIGNALS) for (const width of WIDTHS) {
      const value = valueOf(sig, width);
      const { ctx, ops } = recordingContext(cell);
      theme.fanOutMarker!({ ctx, theme, cell, x: 3, y: 2, value, signal: sig });
      expect(balanced(ops)).toBe(true);
      checkGolden('fanout', `sig${sig}.w${width}.c${cell}`, ops, store);
      const names = ops.map((op) => op[0]);
      const fills = ops.filter((op) => op[0] === 'arc').map((op) => op[3]);
      const r3 = (n: number) => Math.round(n * 1000) / 1000;
      expect(fills).toEqual([r3(cell * 0.3), r3(cell * 0.13)]);
      expect(names.indexOf('save')).toBeLessThan(names.indexOf('arc'));
      // The knock-out comes after the disc and before the restore, and the
      // op log ends with the composite mode put back.
      const knock = ops.findIndex((op) => op[0] === 'set' && op[1] === 'globalCompositeOperation');
      expect(ops[knock][2]).toBe('destination-out');
      expect(knock).toBeGreaterThan(names.indexOf('fill'));
      expect(names[names.length - 1]).toBe('restore');
      const colour = ops.find((op) => op[0] === 'set' && op[1] === 'fillStyle')![2];
      const expected = sig === 2 ? colorsDark.wireUndefined : width > 1 ? colorsDark.wireBus : sig === 1 ? colorsDark.wireActive : colorsDark.wireIdle;
      expect(colour).toBe(expected);
    }
    flush(store);
  });

  test("a pin's shape says its state, and its name owns the centre", () => {
    const theme = themeWith(true);
    const run = (kind: 'input_pin' | 'output_pin', sig: Signal, cell = 10) => {
      const c = component(kind, 1);
      const { ctx, ops } = recordingContext(cell);
      const v = valueOf(sig, 1);
      skinFor(theme, c)({
        ctx, theme, cell, component: c,
        inputSignals: c.inPorts.map(() => sig), outputSignal: sig,
        inputValues: c.inPorts.map(() => v), outputValue: v, hovered: false,
      });
      return ops;
    };
    const sets = (ops: Op[], prop: string) => ops.filter((op) => op[0] === 'set' && op[1] === prop).map((op) => op[2]);
    // Box 5×3 at cell 10 from (2,2): centre (45, 35), r = 15 − 0.8.
    const cx = 45, cy = 35, r = 14.2;
    for (const kind of ['input_pin', 'output_pin'] as const) {
      const onFill = kind === 'input_pin' ? colorsDark.inputOn : colorsDark.outputOn;
      const offBorder = kind === 'input_pin' ? colorsDark.inputBorderOff : colorsDark.outputBorderOff;

      // HIGH: a halo one spread wider, then a filled disc, then the border.
      const high = run(kind, 1);
      const arcs = high.filter((op) => op[0] === 'arc');
      expect(arcs.some((op) => op[1] === cx && op[2] === cy && op[3] === r + 3.5)).toBe(true);
      expect(sets(high, 'globalAlpha')).toEqual([0.22]);
      expect(sets(high, 'fillStyle')).toContain(onFill);
      // The name, not the value, sits in the centre, in the on-component ink.
      const name = high.find((op) => op[0] === 'fillText' && op[1] === (kind === 'input_pin' ? 'a' : 'q'))!;
      expect([name[2], name[3]]).toEqual([cx, cy + 0.3]);
      expect(high.some((op) => op[0] === 'fillText' && op[1] === '1')).toBe(true);

      // LOW: a hollow ring — surface fill, border at 1.2× the line weight.
      const low = run(kind, 0);
      expect(sets(low, 'strokeStyle')[0]).toBe(colorsDark.wireIdle); // the tail
      expect(sets(low, 'fillStyle')).toContain(colorsDark.surface);
      expect(sets(low, 'strokeStyle')).toContain(offBorder);
      expect(sets(low, 'lineWidth')).toContain(2.4);
      expect(low.some((op) => op[0] === 'fillText' && op[1] === '0')).toBe(true);
      expect(sets(low, 'globalAlpha')).toEqual([]);

      // Undefined: a dashed outline in labelMuted, dash cleared after.
      const und = run(kind, 2);
      const dashes = und.filter((op) => op[0] === 'setLineDash').map((op) => op[1]);
      // The circle's dash and the pill's dash, each cleared after; an input
      // pin draws its pill first and an output pin its circle first.
      expect([...dashes].sort()).toEqual(['[2.6,2.2]', '[2.8,2.4]', '[]', '[]']);
      expect(dashes[1]).toBe('[]');
      expect(dashes[3]).toBe('[]');
      expect(sets(und, 'strokeStyle')).toContain(colorsDark.labelMuted);
      expect(und.some((op) => op[0] === 'fillText' && op[1] === '?')).toBe(true);
    }
  });

  test('the single-bit pill sits above the circle, clear of the ring', () => {
    const theme = themeWith(true);
    for (const cell of CELLS) {
      const c = component('input_pin', 1);
      const { ctx, ops } = recordingContext(cell);
      skinFor(theme, c)({
        ctx, theme, cell, component: c, inputSignals: [], outputSignal: 1,
        inputValues: [], outputValue: valueOf(1, 1), hovered: false,
      });
      const pill = ops.find((op) => op[0] === 'roundRect')!;
      expect(pill).toBeDefined();
      const r3 = (n: number) => Math.round(n * 1000) / 1000;
      const cy = (Y + 1.5) * cell;
      const r = 1.5 * cell - 0.08 * cell;
      const h = 0.92 * cell;
      // Height 0.92 cell; bottom edge at cy − r − 0.5 cell.
      expect(pill[4]).toBe(r3(h));
      expect(r3(Number(pill[2]) + Number(pill[4]))).toBe(r3(cy - r - 0.5 * cell));
      // The ring of decision 9 sits at r + 0.38 cell; the pill's bottom is
      // 0.5 cell above the circle, so 0.12 cell clears it.
      expect(cy - r - 0.5 * cell).toBeLessThan(cy - (r + 0.38 * cell));
    }
  });

  test('a bus pin draws no pill of its own', () => {
    // At width > 1 the canvas calls busValue with the text in the reader's
    // base; a pill drawn here would ignore that base.
    const theme = themeWith(true);
    for (const kind of ['input_pin', 'output_pin'] as const) {
      const c = component(kind, 8);
      const { ctx, ops } = recordingContext(14);
      const v = valueOf(1, 8);
      skinFor(theme, c)({
        ctx, theme, cell: 14, component: c, inputSignals: c.inPorts.map(() => 1), outputSignal: 1,
        inputValues: c.inPorts.map(() => v), outputValue: v, hovered: false,
      });
      expect(ops.some((op) => op[0] === 'roundRect')).toBe(false);
    }
  });

  test('an LED lit is a disc under a halo, unlit a hollow ring, unknown a dashed one', () => {
    const theme = themeWith(true);
    const run = (sig: Signal, cell = 10) => {
      const c = component('led', 1);
      const { ctx, ops } = recordingContext(cell);
      const v = valueOf(sig, 1);
      skinFor(theme, c)({
        ctx, theme, cell, component: c, inputSignals: [sig], outputSignal: sig,
        inputValues: [v], outputValue: v, hovered: false,
      });
      return ops;
    };
    const sets = (ops: Op[], prop: string) => ops.filter((op) => op[0] === 'set' && op[1] === prop).map((op) => op[2]);
    const r = 3 * 10 * 0.4; // min(5,3) × cell × 0.4
    const r3 = (n: number) => Math.round(n * 1000) / 1000;
    const lit = run(1);
    const litArcs = lit.filter((op) => op[0] === 'arc').map((op) => op[3]);
    // Halo (r + 0.65 cell), disc, border, glint, then the terminal dot.
    expect(litArcs).toEqual([r + 6.5, r, r, r3(r * 0.24), 2.4]);
    expect(sets(lit, 'globalAlpha')).toEqual([0.22, 0.5]);
    expect(sets(lit, 'fillStyle')).toContain(colorsDark.outputOn);
    expect(sets(lit, 'fillStyle')).toContain(colorsDark.background);

    const unlit = run(0);
    expect(sets(unlit, 'fillStyle')).toContain(colorsDark.surface);
    expect(sets(unlit, 'strokeStyle')).toContain(colorsDark.outputBorderOff);
    expect(unlit.filter((op) => op[0] === 'arc').map((op) => op[3])).toEqual([r, r, r3(r * 0.3), 2.4]);
    expect(unlit.some((op) => op[0] === 'setLineDash' && op[1] !== '[]')).toBe(false);

    const unknown = run(2);
    expect(sets(unknown, 'strokeStyle')).toContain(colorsDark.labelMuted);
    expect(unknown.filter((op) => op[0] === 'setLineDash').map((op) => op[1])).toEqual(['[2.8,2.4]', '[]']);
  });

  test('busValue: the chip for every multi-bit kind draws as the golden says, and a memory gets none', () => {
    const theme = themeWith(true);
    for (const kind of KINDS) for (const cell of CELLS) {
      const c = component(kind, 8);
      const { ctx, ops } = recordingContext(cell);
      theme.busValue!({ ctx, theme, cell, component: c, value: valueOf(1, 8), text: '0b10100101' });
      expect(balanced(ops)).toBe(true);
      checkGolden('busvalue', `${kind}.c${cell}`, ops, store);
      if (kind === 'rom' || kind === 'ram') {
        expect(ops).toEqual([]);
        continue;
      }
      // The pill carries the canvas's text verbatim, solid, in the bus colours.
      const text = ops.find((op) => op[0] === 'fillText')!;
      expect(text[1]).toBe('0b10100101');
      const fills = ops.filter((op) => op[0] === 'set' && op[1] === 'fillStyle').map((op) => op[2]);
      expect(fills).toEqual([colorsDark.wireBus, colorsDark.busLabel]);
      expect(ops.some((op) => op[0] === 'setLineDash')).toBe(false);
      // Seated above the box: a pin's above its circle, a box's above its edge.
      const pill = ops.find((op) => op[0] === 'roundRect')!;
      const r3 = (n: number) => Math.round(n * 1000) / 1000;
      const bottom = r3(Number(pill[2]) + Number(pill[4]));
      const w = c.width * cell, h = c.height * cell;
      const expected = kind === 'input_pin' || kind === 'output_pin'
        ? r3(c.y * cell + h / 2 - (Math.min(w, h) / 2 - 0.08 * cell) - 0.5 * cell)
        : r3(c.y * cell - 0.5 * cell);
      expect(bottom).toBe(expected);
    }
    flush(store);
  });

  test('highlight: a circle for a pin, a rounded box for every other kind, as the golden says', () => {
    const theme = themeWith(true);
    const r3 = (n: number) => Math.round(n * 1000) / 1000;
    for (const kind of KINDS) for (const cell of CELLS) {
      const c = component(kind, 1);
      const { ctx, ops } = recordingContext(cell);
      theme.highlight!({ ctx, theme, cell, component: c, reason: 'hover' });
      expect(balanced(ops)).toBe(true);
      checkGolden('highlight', `${kind}.c${cell}`, ops, store);
      expect(ops.find((op) => op[0] === 'set' && op[1] === 'strokeStyle')![2]).toBe(colorsDark.inputHover);
      const w = c.width * cell, h = c.height * cell;
      if (kind === 'input_pin' || kind === 'output_pin') {
        // Outside the pin's own circle by 0.38 cells, so the state stays visible.
        const arc = ops.find((op) => op[0] === 'arc')!;
        expect(arc).toBeDefined();
        expect(ops.some((op) => op[0] === 'roundRect')).toBe(false);
        expect(arc[3]).toBe(r3(Math.min(w, h) / 2 - 0.08 * cell + 0.38 * cell));
      } else {
        const box = ops.find((op) => op[0] === 'roundRect')!;
        expect(box).toBeDefined();
        expect(ops.some((op) => op[0] === 'arc')).toBe(false);
        expect(box[3]).toBe(r3(w + 0.36 * cell));
      }
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
