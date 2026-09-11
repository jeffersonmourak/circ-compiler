/**
 * Scene builders: one card per extracted asset, plus the demo circuit.
 * Footprints and port coordinates follow src/layout/sizing.ts + place.ts.
 */
import { pinSize, sliceSize, concatSize, macroSize, undef, val } from "./circ-skins.js";

const LEAD = 2; // cells of lead wire on each side of a card

export function makeComponent(kind, opts = {}) {
  const { name = "", x = LEAD, y = 0, slice, subcircuit, operands = 2, macroInputs = 2, bitWidth = 1 } = opts;
  let size, inPorts = [], outPort = null;
  const P = (n, ox, oy) => ({ portName: n, coord: { x: Math.max(0, x - 1), y: y + oy } });
  switch (kind) {
    case "input_pin":
      size = pinSize(name.length);
      outPort = { x: x + size.width, y: y + 1 };
      break;
    case "output_pin":
      size = pinSize(name.length);
      inPorts = [P("in", 0, 1)];
      break;
    case "not_gate":
      size = { width: 5, height: 3 };
      inPorts = [P("in", 0, 1)];
      outPort = { x: x + 5, y: y + 1 };
      break;
    case "and_gate":
    case "nand_gate":
    case "or_gate":
    case "nor_gate":
    case "xor_gate":
    case "xnor_gate":
      size = { width: 5, height: 5 };
      inPorts = [P("a", 0, 1), P("b", 0, 3)];
      outPort = { x: x + 5, y: y + 2 };
      break;
    case "rom": {
      // PR #79 place.zig: memorySize(label, 1) → max(5, label+4) × 3; addr at y+1, out at y+1
      const lbl = `rom ${name}[${opts.dataWidth ?? 8},${opts.addrWidth ?? 4}]`;
      size = { width: Math.max(5, lbl.length + 4), height: 3 };
      inPorts = [P("addr", 0, 1)];
      outPort = { x: x + size.width, y: y + 1 };
      break;
    }
    case "ram": {
      // memorySize(label, 4) → max(5, label+4) × 9; addr/din/we/clk at y+1/3/5/7, out at y+4
      const lbl = `ram ${name}[${opts.dataWidth ?? 8},${opts.addrWidth ?? 4}]`;
      size = { width: Math.max(5, lbl.length + 4), height: 9 };
      inPorts = [P("addr", 0, 1), P("din", 0, 3), P("we", 0, 5), P("clk", 0, 7)];
      outPort = { x: x + size.width, y: y + 4 };
      break;
    }
    case "buffer":
      size = { width: 5, height: 3 };
      inPorts = [P("in", 0, 1)];
      outPort = { x: x + 5, y: y + 1 };
      break;
    case "led":
      size = { width: 5, height: 3 };
      inPorts = [P("in", 0, 1)];
      break;
    case "slice":
      size = sliceSize(slice.lo, slice.hi);
      inPorts = [P("in", 0, 1)];
      outPort = { x: x + size.width, y: y + 1 };
      break;
    case "concat":
      size = concatSize(operands);
      inPorts = Array.from({ length: operands }, (_, i) => P(`op${i}`, 0, 1 + 2 * i));
      outPort = { x: x + size.width, y: y + Math.floor(size.height / 2) };
      break;
    case "subcircuit":
      size = macroSize(subcircuit.length + name.length + 3, macroInputs);
      inPorts = Array.from({ length: macroInputs }, (_, i) => P(["a", "in", "b"][i] ?? `p${i}`, 0, 1 + 2 * i));
      outPort = { x: x + size.width, y: y + Math.floor(size.height / 2) };
      break;
    default:
      size = { width: 5, height: 3 };
  }
  return {
    id: opts.id ?? 0, kind, name, subcircuit, slice, bitWidth,
    dataWidth: opts.dataWidth, addrWidth: opts.addrWidth, mem: opts.mem,
    x, y, width: size.width, height: size.height, inPorts, outPort,
  };
}

const h = (x1, x2, y) => ({ from: { x: x1, y }, to: { x: x2, y } });
const v = (x, y1, y2) => ({ from: { x, y: y1 }, to: { x, y: y2 } });

/** One asset in isolation with lead wires so its ports and stubs are visible. */
export function cardScene(kind, opts = {}) {
  const { signal = 0, hovered = false, bitWidth = 1, value = null, bottom = 0 } = opts;
  const badge = bitWidth > 1;
  const y = opts.top ?? (badge ? 2 : 0);
  const c = makeComponent(kind, { ...opts, y, bitWidth });
  c.hovered = hovered;
  c.anatomy = !!opts.anatomy;
  c.value = value ?? (signal === 2 ? undef(bitWidth) : val(signal === 1 ? (bitWidth > 1 ? 0xa5 : 1) : 0, bitWidth));
  c.inValues = opts.inValues ?? c.inPorts.map(() => c.value);
  const wires = [];
  for (const p of c.inPorts) {
    wires.push({
      srcId: -1, dstId: c.id, dstPort: p.portName,
      segments: [h(0, p.coord.x, p.coord.y)], crossings: [], value: c.value,
    });
  }
  if (c.outPort) {
    wires.push({
      srcId: c.id, dstId: -1, dstPort: null,
      segments: [h(c.outPort.x, c.outPort.x + LEAD - 1, c.outPort.y)], crossings: [], value: c.value,
    });
  }
  return {
    components: [c], wires,
    gridW: LEAD + c.width + LEAD, gridH: c.height + y + bottom,
  };
}

/** Bare wire / marker specimens — the chrome canvas.ts draws itself. */
export function markScene(which, opts = {}) {
  const value = opts.value ?? val(1, 1);
  const base = { components: [], wires: [], gridW: 9, gridH: 3, transparent: false };
  if (which === "wire") {
    base.wires = [{ srcId: -1, dstId: -1, segments: [h(0, 8, 1)], crossings: [], value }];
  } else if (which === "corner") {
    base.wires = [{ srcId: -1, dstId: -1, segments: [h(0, 4, 0), v(4, 0, 2), h(4, 8, 2)], crossings: [], value }];
    base.gridH = 3;
  } else if (which === "crossing") {
    base.wires = [
      { srcId: -1, dstId: -1, segments: [v(4, 0, 2)], crossings: [], value: val(0, 1) },
      { srcId: -1, dstId: -1, segments: [h(0, 8, 1)], crossings: [{ x: 4, y: 1 }], value },
    ];
  } else if (which === "fanout") {
    // Three wires off one source. Only the branch cell collects three
    // segment touches, so exactly one dot is stamped — the junction.
    base.gridH = 5;
    base.wires = [
      { srcId: 7, dstId: -1, segments: [v(5, 2, 0), h(5, 8, 0)], crossings: [], value },
      { srcId: 7, dstId: -1, segments: [v(5, 2, 4), h(5, 8, 4)], crossings: [], value },
      { srcId: 7, dstId: -1, segments: [h(0, 8, 2)], crossings: [], value },
    ];
  }
  return base;
}

/**
 * Demo circuit. Column/row geometry follows place.ts:
 * COL_GUTTER = 5, ROW_GUTTER = 1, port coords one cell outside the box.
 *
 *   a ──┐                            data[8] ──▶ [0:4] ──▶ lo
 *   b ──┴─▶ AND ──▶ NOT ──▶ LED
 */
export function demoScene({ a = 1, b = 0, data = 0xa5, gutter = 1 } = {}) {
  const andOut = a === 1 && b === 1 ? 1 : 0;
  const notOut = andOut === 1 ? 0 : 1;

  // T leaves room above row 0 for value chips / bus badges. `gutter` is
  // place.ts's ROW_GUTTER — the proposal asks for 2 so a chip sitting in
  // the gutter can't reach the box above it.
  const T = 2;
  const g = gutter;
  const yA = T;
  const yB = T + 3 + g;
  const yBus = yB + 5 + g;
  const pinA = makeComponent("input_pin", { id: 1, name: "a", x: 0, y: yA });
  const pinB = makeComponent("input_pin", { id: 2, name: "b", x: 0, y: yB });
  const pinD = makeComponent("input_pin", { id: 3, name: "data", x: 0, y: yBus, bitWidth: 8 });
  const and = makeComponent("and_gate", { id: 4, x: 13, y: T });
  const not = makeComponent("not_gate", { id: 5, x: 25, y: T + 1 });
  const led = makeComponent("led", { id: 6, x: 36, y: T + 1 });
  const sl = makeComponent("slice", { id: 7, x: 13, y: yBus, slice: { lo: 0, hi: 4 }, bitWidth: 4 });
  const out = makeComponent("output_pin", { id: 8, name: "lo", x: 25, y: yBus, bitWidth: 4 });

  pinA.value = val(a, 1);
  pinB.value = val(b, 1);
  pinD.value = val(data, 8);
  and.value = val(andOut, 1);
  not.value = val(notOut, 1);
  sl.value = val(data & 0x0f, 4);
  led.inValues = [not.value];
  out.value = sl.value;
  out.inValues = [sl.value];
  and.inValues = [pinA.value, pinB.value];
  not.inValues = [and.value];
  sl.inValues = [pinD.value];

  const wires = [
    { srcId: 1, dstId: 4, dstPort: "a", segments: [h(8, 12, yA + 1)], crossings: [], value: pinA.value },
    {
      srcId: 2, dstId: 4, dstPort: "b",
      segments: [h(8, 10, yB + 1), v(10, yB + 1, T + 3), h(10, 12, T + 3)], crossings: [], value: pinB.value,
    },
    { srcId: 4, dstId: 5, dstPort: "in", segments: [h(18, 24, T + 2)], crossings: [], value: and.value },
    { srcId: 5, dstId: 6, dstPort: "in", segments: [h(30, 35, T + 2)], crossings: [], value: not.value },
    { srcId: 3, dstId: 7, dstPort: "in", segments: [h(8, 12, yBus + 1)], crossings: [], value: pinD.value },
    { srcId: 7, dstId: 8, dstPort: "in", segments: [h(20, 24, yBus + 1)], crossings: [], value: sl.value },
  ];

  return {
    components: [pinA, pinB, pinD, and, not, led, sl, out],
    wires, gridW: 42, gridH: yBus + 4,
  };
}

/**
 * The grammar-true demo used by the playground proposals:
 *   input a, b · and g(a=a, b=b) · not n(in=g.out) · output out(in=n.out)
 */
export function nandScene({ a = 1, b = 0, gutter = 2 } = {}) {
  const andOut = a === 1 && b === 1 ? 1 : 0;
  const notOut = andOut === 1 ? 0 : 1;
  const T = 2, g = gutter;
  const yA = T, yB = T + 3 + g;
  const pinA = makeComponent("input_pin", { id: 1, name: "a", x: 0, y: yA });
  const pinB = makeComponent("input_pin", { id: 2, name: "b", x: 0, y: yB });
  const and = makeComponent("and_gate", { id: 3, name: "g", x: 13, y: T });
  const not = makeComponent("not_gate", { id: 4, name: "n", x: 25, y: T + 1 });
  const out = makeComponent("output_pin", { id: 5, name: "out", x: 36, y: T + 1 });
  pinA.value = val(a, 1); pinB.value = val(b, 1);
  and.value = val(andOut, 1); not.value = val(notOut, 1); out.value = not.value;
  and.inValues = [pinA.value, pinB.value]; not.inValues = [and.value]; out.inValues = [not.value];
  const wires = [
    { srcId: 1, dstId: 3, dstPort: "a", segments: [h(8, 12, yA + 1)], crossings: [], value: pinA.value },
    { srcId: 2, dstId: 3, dstPort: "b", segments: [h(8, 10, yB + 1), v(10, yB + 1, T + 3), h(10, 12, T + 3)], crossings: [], value: pinB.value },
    { srcId: 3, dstId: 4, dstPort: "in", segments: [h(18, 24, T + 2)], crossings: [], value: and.value },
    { srcId: 4, dstId: 5, dstPort: "in", segments: [h(30, 35, T + 2)], crossings: [], value: not.value },
  ];
  return { components: [pinA, pinB, and, not, out], wires, gridW: 42, gridH: yB + 4 };
}

/**
 * A wider program for the bench proposals — a 2-bit ripple adder written
 * with slices, primitive gates and a concat, so buses, fan-out and
 * multiple outputs all appear:
 *
 *   input a[2], b[2]
 *   slice a0(in=a, lo=0, hi=1)  slice a1(in=a, lo=1, hi=2)
 *   slice b0(in=b, lo=0, hi=1)  slice b1(in=b, lo=1, hi=2)
 *   xor s0(a=a0.out, b=b0.out)  and c1(a=a0.out, b=b0.out)
 *   xor p1(a=a1.out, b=b1.out)  and g1(a=a1.out, b=b1.out)
 *   xor s1(a=p1.out, b=c1.out)  and h1(a=p1.out, b=c1.out)
 *   or  c2(a=g1.out, b=h1.out)
 *   concat sum(a=s1.out, b=s0.out)
 *   output sum(in=sum.out), cout(in=c2.out)
 */
export function adderScene({ a = 0b11, b = 0b01 } = {}) {
  const bit = (n, i) => (n >> i) & 1;
  const a0 = bit(a, 0), a1 = bit(a, 1), b0 = bit(b, 0), b1 = bit(b, 1);
  const s0 = a0 ^ b0, c1 = a0 & b0, p1 = a1 ^ b1, g1 = a1 & b1, s1 = p1 ^ c1, h1 = p1 & c1, c2 = g1 | h1;
  const C = (kind, o) => makeComponent(kind, o);
  const comps = [];
  const add = (kind, o, value, inValues) => { const c = C(kind, o); c.value = value; c.inValues = inValues; comps.push(c); return c; };
  const V = (v) => val(v, 1);
  // column 0: bus inputs
  const pinA = add("input_pin", { id: 1, name: "a", x: 0, y: 1, bitWidth: 2 }, val(a, 2), []);
  const pinB = add("input_pin", { id: 2, name: "b", x: 0, y: 13, bitWidth: 2 }, val(b, 2), []);
  // column 1: slices (5 wide, 3 tall) at x=9
  const sA1 = add("slice", { id: 3, x: 9, y: 0, slice: { lo: 1, hi: 2 } }, V(a1), [pinA.value]);
  const sA0 = add("slice", { id: 4, x: 9, y: 5, slice: { lo: 0, hi: 1 } }, V(a0), [pinA.value]);
  const sB1 = add("slice", { id: 5, x: 9, y: 11, slice: { lo: 1, hi: 2 } }, V(b1), [pinB.value]);
  const sB0 = add("slice", { id: 6, x: 9, y: 16, slice: { lo: 0, hi: 1 } }, V(b0), [pinB.value]);
  // column 2: first-stage gates at x=19 (5x5): a at y+1, b at y+3
  const gP1 = add("xor_gate", { id: 7, name: "p1", x: 19, y: 0 }, V(p1), [V(a1), V(b1)]);
  const gG1 = add("and_gate", { id: 8, name: "g1", x: 19, y: 6 }, V(g1), [V(a1), V(b1)]);
  const gS0 = add("xor_gate", { id: 9, name: "s0", x: 19, y: 12 }, V(s0), [V(a0), V(b0)]);
  const gC1 = add("and_gate", { id: 10, name: "c1", x: 19, y: 18 }, V(c1), [V(a0), V(b0)]);
  // column 3: second stage at x=30
  const gS1 = add("xor_gate", { id: 11, name: "s1", x: 30, y: 2 }, V(s1), [V(p1), V(c1)]);
  const gH1 = add("and_gate", { id: 12, name: "h1", x: 30, y: 9 }, V(h1), [V(p1), V(c1)]);
  // column 4: or + concat at x=41
  const gC2 = add("or_gate", { id: 13, name: "c2", x: 41, y: 7 }, V(c2), [V(g1), V(h1)]);
  const cat = add("concat", { id: 14, name: "sum", x: 41, y: 14, operands: 2 }, val((s1 << 1) | s0, 2), [V(s1), V(s0)]);
  // column 5: outputs at x=52
  const oCout = add("output_pin", { id: 15, name: "cout", x: 52, y: 8 }, V(c2), [V(c2)]);
  const oSum = add("output_pin", { id: 16, name: "sum", x: 52, y: 16, bitWidth: 2 }, cat.value, [cat.value]);

  const W = (srcId, dstId, dstPort, value, segments, crossings = []) => ({ srcId, dstId, dstPort, value, segments, crossings });
  const wires = [
    // a bus fans out to both a-slices
    W(1, 3, "in", pinA.value, [h(pinA.outPort.x, 6, 2), v(6, 2, 1), h(6, sA1.inPorts[0].coord.x, 1)]),
    W(1, 4, "in", pinA.value, [h(pinA.outPort.x, 6, 2), v(6, 2, 6), h(6, sA0.inPorts[0].coord.x, 6)]),
    W(2, 5, "in", pinB.value, [h(pinB.outPort.x, 6, 14), v(6, 14, 12), h(6, sB1.inPorts[0].coord.x, 12)]),
    W(2, 6, "in", pinB.value, [h(pinB.outPort.x, 6, 14), v(6, 14, 17), h(6, sB0.inPorts[0].coord.x, 17)]),
    // a1 → p1.a, g1.a ; b1 → p1.b, g1.b
    W(3, 7, "a", V(a1), [h(sA1.outPort.x, 16, 1), h(16, 18, 1)]),
    W(3, 8, "a", V(a1), [h(sA1.outPort.x, 16, 1), v(16, 1, 7), h(16, 18, 7)], [{ x: 17, y: 7 }]),
    W(5, 7, "b", V(b1), [h(sB1.outPort.x, 17, 12), v(17, 12, 3), h(17, 18, 3)], [{ x: 15, y: 12 }]),
    W(5, 8, "b", V(b1), [h(sB1.outPort.x, 17, 12), v(17, 12, 9), h(17, 18, 9)], [{ x: 15, y: 12 }]),
    // a0 → s0.a, c1.a ; b0 → s0.b, c1.b
    W(4, 9, "a", V(a0), [h(sA0.outPort.x, 15, 6), v(15, 6, 13), h(15, 18, 13)]),
    W(4, 10, "a", V(a0), [h(sA0.outPort.x, 15, 6), v(15, 6, 19), h(15, 18, 19)], [{ x: 16, y: 19 }]),
    W(6, 9, "b", V(b0), [h(sB0.outPort.x, 16, 17), v(16, 17, 15), h(16, 18, 15)]),
    W(6, 10, "b", V(b0), [h(sB0.outPort.x, 16, 17), v(16, 17, 21), h(16, 18, 21)]),
    // p1 → s1.a, h1.a
    W(7, 11, "a", V(p1), [h(gP1.outPort.x, 27, 2), v(27, 2, 3), h(27, 29, 3)]),
    W(7, 12, "a", V(p1), [h(gP1.outPort.x, 27, 2), v(27, 2, 10), h(27, 29, 10)]),
    // c1 → s1.b, h1.b
    W(10, 11, "b", V(c1), [h(gC1.outPort.x, 28, 20), v(28, 20, 5), h(28, 29, 5)]),
    W(10, 12, "b", V(c1), [h(gC1.outPort.x, 28, 20), v(28, 20, 12), h(28, 29, 12)]),
    // g1 → c2.a ; h1 → c2.b
    W(8, 13, "a", V(g1), [h(gG1.outPort.x, 38, 8), h(38, 40, 8)], [{ x: 27, y: 8 }, { x: 28, y: 8 }, { x: 37, y: 8 }]),
    W(12, 13, "b", V(h1), [h(gH1.outPort.x, 39, 11), v(39, 11, 10), h(39, 40, 10)], [{ x: 37, y: 11 }]),
    // s1 → sum.0 ; s0 → sum.1
    W(11, 14, "a", V(s1), [h(gS1.outPort.x, 37, 4), v(37, 4, 15), h(37, 40, 15)]),
    W(9, 14, "b", V(s0), [h(gS0.outPort.x, 36, 14), v(36, 14, 17), h(36, 40, 17)], [{ x: 28, y: 14 }]),
    // outputs
    W(13, 15, "in", V(c2), [h(gC2.outPort.x, oCout.inPorts[0].coord.x, 9)]),
    W(14, 16, "in", cat.value, [h(cat.outPort.x, oSum.inPorts[0].coord.x, 17)]),
  ];
  return { components: comps, wires, gridW: 60, gridH: 24 };
}

/** input addr[4] · rom lut[8,4](addr=addr) · output q(in=lut.out) — for the drawer proposals. */
export function romScene({ addr = 0x3, word = 0x5a } = {}) {
  const pin = makeComponent("input_pin", { id: 1, name: "addr", x: 0, y: 1, bitWidth: 4 });
  const rom = makeComponent("rom", { id: 2, name: "lut", x: 12, y: 1, dataWidth: 8, addrWidth: 4, mem: { addr, word } });
  const out = makeComponent("output_pin", { id: 3, name: "q", x: rom.x + rom.width + 5, y: 1, bitWidth: 8 });
  pin.value = val(addr, 4); rom.value = val(word, 8); out.value = rom.value;
  rom.inValues = [pin.value]; out.inValues = [rom.value];
  const wires = [
    { srcId: 1, dstId: 2, dstPort: "addr", segments: [h(pin.outPort.x, rom.inPorts[0].coord.x, 2)], crossings: [], value: pin.value },
    { srcId: 2, dstId: 3, dstPort: "in", segments: [h(rom.outPort.x, out.inPorts[0].coord.x, 2)], crossings: [], value: rom.value },
  ];
  return { components: [pin, rom, out], wires, gridW: out.x + out.width + 1, gridH: 5 };
}

/**
 * The Hack ALU (Nand2Tetris project 2), as circ would write it from the
 * project's own chips: two Mux16/Not16 preprocessing paths, Add16/And16,
 * a function mux, an output negate, and the zr/ng flags.
 *
 *   input x[16], y[16], zx, nx, zy, ny, f, no
 *   output out[16], zr, ng
 *
 * Eight inputs on the rail is the point of this scene.
 */
export function aluScene({ x = 0x0007, y = 0x0003, zx = 0, nx = 0, zy = 0, ny = 0, f = 1, no = 0 } = {}) {
  const M = 0xffff;
  let xa = zx ? 0 : x; if (nx) xa = ~xa & M;
  let ya = zy ? 0 : y; if (ny) ya = ~ya & M;
  const add = (xa + ya) & M, and = xa & ya;
  const fo = f ? add : and;
  const out = no ? (~fo & M) : fo;
  const zr = out === 0 ? 1 : 0, ng = (out >> 15) & 1;

  const comps = [];
  const add1 = (kind, o, value, inValues) => { const c = makeComponent(kind, o); c.value = value; c.inValues = inValues; comps.push(c); return c; };
  const B = (v) => val(v & M, 16), V = (v) => val(v, 1);
  const sub = (id, name, subcircuit, x0, y0, n, value, inValues) => add1("subcircuit", { id, name, subcircuit, x: x0, y: y0, macroInputs: n }, value, inValues);

  // inputs — buses first, then the six control bits, each on its own row band
  const pX  = add1("input_pin", { id: 1, name: "x",  x: 0, y: 1,  bitWidth: 16 }, B(x), []);
  const pZx = add1("input_pin", { id: 2, name: "zx", x: 0, y: 6 }, V(zx), []);
  const pNx = add1("input_pin", { id: 3, name: "nx", x: 0, y: 11 }, V(nx), []);
  const pY  = add1("input_pin", { id: 4, name: "y",  x: 0, y: 18, bitWidth: 16 }, B(y), []);
  const pZy = add1("input_pin", { id: 5, name: "zy", x: 0, y: 23 }, V(zy), []);
  const pNy = add1("input_pin", { id: 6, name: "ny", x: 0, y: 28 }, V(ny), []);
  const pF  = add1("input_pin", { id: 7, name: "f",  x: 0, y: 35 }, V(f), []);
  const pNo = add1("input_pin", { id: 8, name: "no", x: 0, y: 40 }, V(no), []);

  // Columns: subcircuit boxes are 12–15 cells wide (label + 2), so give
  // every column 15 and route each trunk two cells before the next column.
  const X = [12, 27, 42, 57, 72, 87, 102, 117, 133, 141];
  const T = (i) => X[i] - 2;
  // x path: Mux16(x, 0, zx) → Not16 → Mux16(·, ¬·, nx)
  const zxm = sub(10, "zxm", "Mux16", X[0], 1, 3, B(zx ? 0 : x), [B(x), B(0), V(zx)]);
  const nxn = sub(11, "nxn", "Not16", X[1], 1, 1, B(~(zx ? 0 : x)), [zxm.value]);
  const nxm = sub(12, "nxm", "Mux16", X[2], 1, 3, B(xa), [zxm.value, nxn.value, V(nx)]);
  // y path
  const zym = sub(13, "zym", "Mux16", X[0], 18, 3, B(zy ? 0 : y), [B(y), B(0), V(zy)]);
  const nyn = sub(14, "nyn", "Not16", X[1], 18, 1, B(~(zy ? 0 : y)), [zym.value]);
  const nym = sub(15, "nym", "Mux16", X[2], 18, 3, B(ya), [zym.value, nyn.value, V(ny)]);
  // function
  const a16 = sub(16, "sum", "Add16", X[3], 6, 2, B(add), [B(xa), B(ya)]);
  const n16 = sub(17, "both", "And16", X[3], 13, 2, B(and), [B(xa), B(ya)]);
  const fm  = sub(18, "fm", "Mux16", X[4], 8, 3, B(fo), [B(and), B(add), V(f)]);
  // negate
  const non = sub(19, "non", "Not16", X[5], 8, 1, B(~fo), [B(fo)]);
  const nom = sub(20, "nom", "Mux16", X[6], 8, 3, B(out), [B(fo), B(~fo), V(no)]);
  // flags
  const orw = sub(21, "any", "Or16Way", X[7], 16, 1, V(zr ? 0 : 1), [B(out)]);
  const zrn = add1("not_gate", { id: 22, name: "zr", x: X[8], y: 16 }, V(zr), [V(zr ? 0 : 1)]);
  const msb = add1("slice", { id: 23, x: X[7], y: 22, slice: { lo: 15, hi: 16 } }, V(ng), [B(out)]);
  // outputs
  const oOut = add1("output_pin", { id: 24, name: "out", x: X[9], y: 9,  bitWidth: 16 }, B(out), [B(out)]);
  const oZr  = add1("output_pin", { id: 25, name: "zr",  x: X[9], y: 16 }, V(zr), [V(zr)]);
  const oNg  = add1("output_pin", { id: 26, name: "ng",  x: X[9], y: 22 }, V(ng), [V(ng)]);

  const W = (srcId, dstId, dstPort, value, segments, crossings = []) => ({ srcId, dstId, dstPort, value, segments, crossings });
  const P = (c, i) => c.inPorts[i].coord, O = (c) => c.outPort;
  // out → trunk → port, as an L or a Z
  const route = (src, dst, i, tx) => { const o = O(src), p = P(dst, i); return o.y === p.y ? [h(o.x, p.x, o.y)] : [h(o.x, tx, o.y), v(tx, o.y, p.y), h(tx, p.x, p.y)]; };
  const wires = [
    // x path
    W(1, 10, "a", B(x), route(pX, zxm, 0, 9)),
    W(2, 10, "sel", V(zx), route(pZx, zxm, 2, 9)),
    W(10, 11, "in", zxm.value, route(zxm, nxn, 0, T(1))),
    W(10, 12, "a", zxm.value, route(zxm, nxm, 0, T(1))),
    W(11, 12, "b", nxn.value, route(nxn, nxm, 1, T(2))),
    W(3, 12, "sel", V(nx), route(pNx, nxm, 2, T(2) - 1)),
    // y path
    W(4, 13, "a", B(y), route(pY, zym, 0, 9)),
    W(5, 13, "sel", V(zy), route(pZy, zym, 2, 9)),
    W(13, 14, "in", zym.value, route(zym, nyn, 0, T(1))),
    W(13, 15, "a", zym.value, route(zym, nym, 0, T(1))),
    W(14, 15, "b", nyn.value, route(nyn, nym, 1, T(2))),
    W(6, 15, "sel", V(ny), route(pNy, nym, 2, T(2) - 1)),
    // function stage
    W(12, 16, "a", B(xa), route(nxm, a16, 0, T(3))),
    W(12, 17, "a", B(xa), route(nxm, n16, 0, T(3))),
    W(15, 16, "b", B(ya), route(nym, a16, 1, T(3) - 1)),
    W(15, 17, "b", B(ya), route(nym, n16, 1, T(3) - 1)),
    W(17, 18, "a", B(and), route(n16, fm, 0, T(4))),
    W(16, 18, "b", B(add), route(a16, fm, 1, T(4) - 1)),
    W(7, 18, "sel", V(f), route(pF, fm, 2, T(4) - 2)),
    // negate
    W(18, 19, "in", B(fo), route(fm, non, 0, T(5))),
    W(18, 20, "a", B(fo), route(fm, nom, 0, T(5))),
    W(19, 20, "b", B(~fo), route(non, nom, 1, T(6))),
    W(8, 20, "sel", V(no), route(pNo, nom, 2, T(6) - 1)),
    // outputs + flags
    W(20, 24, "in", B(out), route(nom, oOut, 0, T(7))),
    W(20, 21, "in", B(out), route(nom, orw, 0, T(7))),
    W(20, 23, "in", B(out), route(nom, msb, 0, T(7))),
    W(21, 22, "in", V(zr ? 0 : 1), route(orw, zrn, 0, T(8))),
    W(22, 25, "in", V(zr), route(zrn, oZr, 0, T(9))),
    W(23, 26, "in", V(ng), route(msb, oNg, 0, T(9))),
  ];
  return { components: comps, wires, gridW: oOut.x + oOut.width + 1, gridH: 45, values: { out, zr, ng } };
}
