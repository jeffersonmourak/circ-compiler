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
