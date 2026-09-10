// Themes for the embedded circ-renderer Canvas. Direct port of the blog's
// (jeffersonmourak.github.io) circ-runtime theme, with a derived light-mode
// color palette so the canvas works under both site themes. The skin
// functions, helpers, and sprite-loading logic match the blog 1:1; only
// the color tables differ between modes.
//
// Background: the canvas is rendered TRANSPARENT (clearRect, not fillRect)
// so it inherits the parent .lc element's background (var(--pane-bg)).
// `colors.background` is still set to the matching pane-bg value because
// the vector-fallback skins use it as the gate body fill — keeping the
// same hue makes vector gates blend with the canvas, leaving only the
// outline visible (the same look the blog uses).
//
// Sprites are loaded once and used in both light and dark modes. Light
// mode rebuilds via the onAssetsReady hook in LiveCanvas just like dark.
//
// Active theme is selected at click-load time via pickTheme() reading the
// data-theme attribute on <html>. Toggling the site theme later hands the
// other palette to the live canvas through `setTheme` (LiveCanvas.astro and
// Playground.astro both do); nothing is rebuilt.
//
// Typed through JSDoc so the components that pass a theme to `renderCircuit`
// get the renderer's own `CircView` back, with this palette's keys, and need
// no cast. `PaletteKey` is exported for them.

import { ComponentKind, memoryLabel, traceWire, wireColorKey, wireStyleOf } from 'circ-renderer';
import { loadAssets } from './circ-assets.mjs';

/* ───── async sprite loading ───────────────────────────────────────── */

let sprites = null;
const readyCallbacks = [];

export const blogAssetsReady = loadAssets().then((lib) => {
  sprites = lib;
  for (const cb of readyCallbacks) cb();
});

export function onAssetsReady(cb) {
  if (sprites) {
    cb();
    return () => {};
  }
  readyCallbacks.push(cb);
  return () => {
    const i = readyCallbacks.indexOf(cb);
    if (i >= 0) readyCallbacks.splice(i, 1);
  };
}

/* ───── color palettes ─────────────────────────────────────────────── */

// Dark palette — the blog's color choices, with `background` set to
// global.css's --pane-bg dark (#0c0517) since the canvas is now
// transparent and the vector-fallback skins fill gate bodies with this
// value to blend with the parent pane.
const colorsDark = {
  background: '#0c0517',
  grid: '#1c0f2a',
  stroke: '#ffffff',
  fillIdle: '#1c0f2a',
  fillActive: 'hsl(134 61% 41% / 1)',
  fillUndefined: '#241636',
  wireIdle: '#dee2e6',
  wireActive: 'hsl(134 61% 41% / 1)',
  wireUndefined: '#3a2752',
  // A defined multi-bit wire: the badge above it says the number, so the
  // wire itself does not need to be green or grey.
  wireBus: '#d0bfff',
  label: '#ffffff',
  labelMuted: '#aaa',
  // Used for labels drawn ON a component's surface (centered on the gate
  // sprite, inside pin/output circles). Stays white in both themes so it
  // reads against the dark sprite interior + saturated circle fills,
  // independent of the page bg.
  labelOnComponent: '#ffffff',
  macro: '#bea7ff',
  inputOn: '#fd7e14',
  inputOff: 'hsl(134 61% 41%)',
  inputBorderOn: '#634e0d',
  inputBorderOff: '#165a26',
  inputHover: '#ffc107',
  outputOn: '#0b99ff',
  outputOff: '#bee3ff',
  outputBorderOn: '#0059b9',
  outputBorderOff: '#24b4ff',
  portOn: '#fd7e14',
  portOff: '#634e0d',
};

// Light palette — same semantic mapping (orange=HIGH, green=LOW, blue=
// output, yellow=hover) but with hues darkened so they clear AA contrast
// on the lavender pane-bg (#f4eefb). Uses the same PNG sprites as dark
// mode; the canvas is transparent so sprite pixels composite onto the
// pane's lavender bg instead of a black canvas paint.
/** @typedef {keyof typeof colorsDark} PaletteKey */

/** @type {Record<PaletteKey, string>} */
const colorsLight = {
  background: '#f4eefb',
  grid: '#d4c8e8',
  stroke: '#443856',
  fillIdle: '#f4eefb',
  fillActive: 'hsl(134 61% 32% / 1)',
  fillUndefined: '#c8b8dc',
  wireIdle: '#5d3a96',
  wireActive: 'hsl(134 61% 32% / 1)',
  wireUndefined: '#a89cc0',
  wireBus: '#5f3dc4',
  label: '#443856',
  labelMuted: '#8a7e9a',
  // White on the component surface — see colorsDark.labelOnComponent.
  // The PNG sprites have dark interiors in both modes, so this stays
  // white even when the page is light.
  labelOnComponent: '#ffffff',
  macro: '#6e49ab',
  inputOn: '#d65f0a',
  inputOff: 'hsl(134 61% 32%)',
  inputBorderOn: '#8a4408',
  inputBorderOff: '#0f4419',
  inputHover: '#b8860b',
  outputOn: '#0066cc',
  outputOff: '#7fc3ff',
  outputBorderOn: '#003d7a',
  outputBorderOff: '#0066cc',
  portOn: '#d65f0a',
  portOff: '#8a4408',
};

/* ───── helpers ────────────────────────────────────────────────────── */

/**
 * Stroke a horizontal "tail" between the gate's actual visual edge and
 * the wire's endpoint cell-center. Drawn BEFORE the gate symbol so the
 * symbol covers the tail's gate-edge end cleanly.
 */
function drawTailLine(ctx, gateEdge, portEnd, y, signal, theme) {
  ctx.strokeStyle =
    signal === 1
      ? theme.colors.wireActive
      : signal === 0
        ? theme.colors.wireIdle
        : theme.colors.wireUndefined;
  ctx.lineWidth = 4;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(gateEdge, y);
  ctx.lineTo(portEnd, y);
  ctx.stroke();
}

/**
 * Stamp the orange terminal dot at the tail's gate-edge end. Drawn
 * AFTER the gate symbol so the dot always sits on top of the gate.
 */
function drawTailDot(ctx, cell, gateEdge, y, signal, theme) {
  ctx.fillStyle = signal === 1 ? theme.colors.portOn : theme.colors.portOff;
  ctx.beginPath();
  ctx.arc(gateEdge, y, cell * 0.28, 0, Math.PI * 2);
  ctx.fill();
}

/**
 * Draw the component's name as a small label hovering just below its
 * bounding box. Used by NOT, AND, and the small input/output pins.
 */
function drawNameBelow(ctx, cell, name, bx, by, bw, bh, color, yOffset = 0) {
  if (!name) return;
  ctx.fillStyle = color;
  ctx.font = `500 ${Math.round(cell * 0.65)}px ui-monospace, "JetBrains Mono", monospace`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  ctx.fillText(name, bx + bw / 2, by + bh + (cell + yOffset) * 0.05);
}

/**
 * Pins narrower than ~7 cells (≤2-char names) put the name BELOW the
 * circle; wider boxes can fit the name inside, replacing the 0/1.
 */
function nameFitsInside(component) {
  return component.name.length >= 3 || component.width >= 7;
}

/** Filled circle inscribed in the box, with a 0/1 label inside. */
function drawPinCircle(ctx, cell, bx, by, bw, bh, fill, stroke, label, font, labelColor) {
  const cx = bx + bw / 2;
  const cy = by + bh / 2;
  const r = Math.min(bw, bh) / 2 - cell * 0.05;
  ctx.fillStyle = fill;
  ctx.strokeStyle = stroke;
  ctx.lineWidth = Math.max(3, cell * 0.16);
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();

  ctx.fillStyle = labelColor;
  ctx.font = font;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(label, cx, cy);
}

/**
 * Compute where a square sprite would land inside a box of (w × h),
 * preserving aspect ratio (size = min(w, h), centered). Used by skins
 * to anchor tails at the sprite's actual silhouette rather than at the
 * box border.
 */
function spriteRect(x, y, w, h) {
  const size = Math.min(w, h);
  const cx = x + w / 2;
  const cy = y + h / 2;
  return { left: cx - size / 2, right: cx + size / 2, size, cx, cy };
}

/**
 * Draw a sprite into the component box, preserving aspect ratio. The
 * blog's PNGs are drawn with the gate pointing UP, so we rotate 90°
 * clockwise to match the layout's left-to-right flow.
 */
function drawSprite(ctx, img, x, y, w, h) {
  const rect = spriteRect(x, y, w, h);
  ctx.save();
  ctx.translate(rect.cx, rect.cy);
  ctx.rotate(Math.PI / 2);
  ctx.drawImage(img, -rect.size / 2, -rect.size / 2, rect.size, rect.size);
  ctx.restore();
}

/**
 * Per-subcircuit-type sprite map. Builtin macros (and/nand/or/xor/not)
 * render with their primitive sprite so the macro reads as a familiar
 * gate; everything else falls back to a labeled box.
 */
function spriteForSubcircuit(type) {
  if (!sprites) return undefined;
  switch (type.toLowerCase()) {
    case 'and':  return sprites.AND;
    case 'nand': return sprites.NAND;
    case 'or':   return sprites.OR;
    case 'xor':  return sprites.XOR;
    case 'not':  return sprites.NOT;
    default:     return undefined;
  }
}

/**
 * A ring around a component's box, drawn when the pointer is over it or when
 * the host highlighted it — the canvas feeds both through the same `hovered`
 * flag, so one branch covers an editor cursor and a mouse alike.
 *
 * A ring rather than a fill: every skin below already uses fill and stroke to
 * say what the component IS and what it is DOING, and a highlight must not
 * overwrite either.
 */
const drawHoverRing = (ctx, cell, component, theme) => {
  const pad = cell * 0.18;
  const x = component.x * cell - pad;
  const y = component.y * cell - pad;
  const w = component.width * cell + pad * 2;
  const h = component.height * cell + pad * 2;
  const r = Math.min(cell * 0.4, w / 2, h / 2);
  ctx.save();
  ctx.strokeStyle = theme.colors.inputHover;
  ctx.lineWidth = Math.max(1, cell * 0.09);
  ctx.beginPath();
  if (typeof ctx.roundRect === 'function') ctx.roundRect(x, y, w, h, r);
  else ctx.rect(x, y, w, h);
  ctx.stroke();
  ctx.restore();
};

/* ───── skins ──────────────────────────────────────────────────────── */

const drawInputPin = ({ ctx, cell, component, outputSignal, hovered, theme }) => {
  const x = component.x * cell;
  const y = component.y * cell;
  const w = component.width * cell;
  const h = component.height * cell;
  const isOn = outputSignal === 1;

  const r = Math.min(w, h) / 2 - cell * 0.05;
  const cx = x + w / 2;
  const tailEdge = cx + r + cell * 0.45;
  const portY = component.outPort.y * cell + cell / 2;
  const portX = component.outPort.x * cell + cell / 2;
  drawTailLine(ctx, tailEdge, portX, portY, outputSignal, theme);

  let fill = isOn ? theme.colors.inputOn : theme.colors.inputOff;
  let stroke = isOn ? theme.colors.inputBorderOn : theme.colors.inputBorderOff;
  if (hovered) {
    fill = theme.colors.inputHover;
    stroke = theme.colors.inputHover;
  }
  const inside = nameFitsInside(component) ? component.name : isOn ? '1' : '0';
  drawPinCircle(
    ctx, cell, x, y, w, h,
    fill, stroke,
    inside,
    theme.font ?? `600 ${Math.round(cell * 0.8)}px ui-monospace, monospace`,
    theme.colors.labelOnComponent
  );
  if (!nameFitsInside(component)) {
    drawNameBelow(ctx, cell, component.name, x, y, w, h, theme.colors.labelMuted);
  }

  drawTailDot(ctx, cell, tailEdge, portY, outputSignal, theme);
};

const drawOutputPin = ({ ctx, cell, component, inputSignals, theme, hovered }) => {
  const x = component.x * cell;
  const y = component.y * cell;
  const w = component.width * cell;
  const h = component.height * cell;
  const sig = inputSignals[0] ?? 2;
  const isOn = sig === 1;

  const r = Math.min(w, h) / 2 - cell * 0.05;
  const cx = x + w / 2;
  const tailEdge = cx - r - cell * 0.45;
  const slot = component.inPorts[0];
  let dotY = 0;
  if (slot) {
    const portX = slot.coord.x * cell + cell / 2;
    dotY = slot.coord.y * cell + cell / 2;
    drawTailLine(ctx, tailEdge, portX, dotY, sig, theme);
  }

  const inside = nameFitsInside(component) ? component.name : isOn ? '1' : '0';
  drawPinCircle(
    ctx, cell, x, y, w, h,
    isOn ? theme.colors.outputOn : theme.colors.outputOff,
    isOn ? theme.colors.outputBorderOn : theme.colors.outputBorderOff,
    inside,
    theme.font ?? `600 ${Math.round(cell * 0.7)}px ui-monospace, monospace`,
    theme.colors.labelOnComponent
  );
  if (!nameFitsInside(component)) {
    drawNameBelow(ctx, cell, component.name, x, y, w, h, theme.colors.labelMuted);
  }

  if (slot) drawTailDot(ctx, cell, tailEdge, dotY, sig, theme);

};

const drawLed = ({ ctx, cell, component, inputSignals, theme, hovered }) => {
  const cx = (component.x + component.width / 2) * cell;
  const cy = (component.y + component.height / 2) * cell;
  const r = Math.min(component.width, component.height) * cell * 0.4;
  const sig = inputSignals[0] ?? 2;
  const isOn = sig === 1;

  const tailEdge = cx - r - cell * 0.45;
  const slot = component.inPorts[0];
  let dotY = 0;
  if (slot) {
    const portX = slot.coord.x * cell + cell / 2;
    dotY = slot.coord.y * cell + cell / 2;
    drawTailLine(ctx, tailEdge, portX, dotY, sig, theme);
  }

  ctx.fillStyle = isOn ? theme.colors.outputOn : theme.colors.outputOff;
  ctx.strokeStyle = isOn ? theme.colors.outputBorderOn : theme.colors.outputBorderOff;
  ctx.lineWidth = Math.max(2, cell * 0.28);
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();

  if (isOn) {
    ctx.globalAlpha = 0.4;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 1.45, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  drawNameBelow(
    ctx, cell, component.name,
    component.x * cell, component.y * cell,
    component.width * cell, component.height * cell,
    theme.colors.labelMuted
  );

  if (slot) drawTailDot(ctx, cell, tailEdge, dotY, sig, theme);

};

const drawNot = ({ ctx, cell, component, inputSignals, outputSignal, theme, hovered }) => {
  const x0 = component.x * cell;
  const y0 = component.y * cell;
  const w = component.width * cell;
  const h = component.height * cell;

  const usingSprite = !!sprites?.NOT;
  const rect = spriteRect(x0, y0, w, h);
  const gap = cell * 0.45;
  const leftEdge = (usingSprite ? rect.left : x0 + w * 0.1) - gap;
  const rightEdge = (usingSprite ? rect.right : x0 + w * 0.95) + gap;

  const inSlot = component.inPorts[0];
  const inSig = inputSignals[0] ?? 2;
  const inDotY = inSlot ? inSlot.coord.y * cell + cell / 2 : 0;
  if (inSlot) {
    const portX = inSlot.coord.x * cell + cell / 2;
    drawTailLine(ctx, leftEdge, portX, inDotY, inSig, theme);
  }
  const outDotY = component.outPort.y * cell + cell / 2;
  drawTailLine(
    ctx, rightEdge,
    component.outPort.x * cell + cell / 2,
    outDotY, outputSignal, theme
  );

  if (usingSprite) {
    drawSprite(ctx, sprites.NOT, x0, y0, w, h);
  } else {
    ctx.strokeStyle = theme.colors.stroke;
    ctx.fillStyle = theme.colors.background;
    ctx.lineWidth = Math.max(1, cell * 0.1);
    const triRight = x0 + w * 0.78;
    ctx.beginPath();
    ctx.moveTo(x0 + cell * 0.2, y0 + h * 0.18);
    ctx.lineTo(x0 + cell * 0.2, y0 + h * 0.82);
    ctx.lineTo(triRight, y0 + h / 2);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    const bubbleR = Math.min(cell * 0.3, h * 0.18);
    ctx.beginPath();
    ctx.arc(triRight + bubbleR + cell * 0.05, y0 + h / 2, bubbleR, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
  }

  if (inSlot) drawTailDot(ctx, cell, leftEdge, inDotY, inSig, theme);
  drawTailDot(ctx, cell, rightEdge, outDotY, outputSignal, theme);

  drawNameBelow(ctx, cell, component.name, x0, y0, w, h, theme.colors.labelMuted, -cell * 15);

};

const drawAnd = ({ ctx, cell, component, inputSignals, outputSignal, theme, hovered }) => {
  const x0 = component.x * cell;
  const y0 = component.y * cell;
  const w = component.width * cell;
  const h = component.height * cell;

  const usingSprite = !!sprites?.AND;
  const gap = cell * 0.45;
  const leftEdge = x0 + w * 0.1 - gap;
  const rightEdge = x0 + w * 0.92 + gap;

  const inDotYs = [];
  for (let i = 0; i < component.inPorts.length; i++) {
    const slot = component.inPorts[i];
    const sig = inputSignals[i] ?? 2;
    const portX = slot.coord.x * cell + cell / 2;
    const portY = slot.coord.y * cell + cell / 2;
    inDotYs.push(portY);
    drawTailLine(ctx, leftEdge, portX, portY, sig, theme);
  }
  const outDotY = component.outPort.y * cell + cell / 2;
  drawTailLine(
    ctx, rightEdge,
    component.outPort.x * cell + cell / 2,
    outDotY, outputSignal, theme
  );

  if (usingSprite) {
    drawSprite(ctx, sprites.AND, x0, y0, w, h);
  } else {
    ctx.strokeStyle = theme.colors.stroke;
    ctx.fillStyle = theme.colors.background;
    ctx.lineWidth = Math.max(1, cell * 0.1);
    const left = x0 + cell * 0.15;
    const top = y0 + cell * 0.15;
    const bot = y0 + h - cell * 0.15;
    const flat = x0 + w * 0.5;
    const right = x0 + w - cell * 0.15;
    ctx.beginPath();
    ctx.moveTo(left, top);
    ctx.lineTo(flat, top);
    ctx.bezierCurveTo(right, top, right, bot, flat, bot);
    ctx.lineTo(left, bot);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
  }

  for (let i = 0; i < component.inPorts.length; i++) {
    drawTailDot(ctx, cell, leftEdge, inDotYs[i], inputSignals[i] ?? 2, theme);
  }
  drawTailDot(ctx, cell, rightEdge, outDotY, outputSignal, theme);

  if (component.name) {
    ctx.fillStyle = theme.colors.labelOnComponent;
    ctx.font = `600 ${Math.round(cell * 0.7)}px ui-monospace, "JetBrains Mono", monospace`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(component.name, x0 + w / 2, y0 + h / 2);
  }

};

const drawSubcircuit = ({ ctx, cell, component, inputSignals, outputSignal, theme, hovered }) => {
  const x0 = component.x * cell;
  const y0 = component.y * cell;
  const w = component.width * cell;
  const h = component.height * cell;
  const subcircuit = component.kind.tag === 'subcircuit'
    ? component.kind.subcircuit
    : '';
  const sprite = spriteForSubcircuit(subcircuit);
  const usingSprite = !!sprite;

  const gap = cell * 0.45;
  const rect = spriteRect(x0, y0, w, h);
  const leftEdge = (usingSprite ? rect.left : x0 + w * 0.08) - gap;
  const rightEdge = (usingSprite ? rect.right : x0 + w * 0.92) + gap;

  const inDotYs = [];
  for (let i = 0; i < component.inPorts.length; i++) {
    const slot = component.inPorts[i];
    const sig = inputSignals[i] ?? 2;
    const portX = slot.coord.x * cell + cell / 2;
    const portY = slot.coord.y * cell + cell / 2;
    inDotYs.push(portY);
    drawTailLine(ctx, leftEdge, portX, portY, sig, theme);
  }
  const outDotY = component.outPort.y * cell + cell / 2;
  drawTailLine(
    ctx, rightEdge,
    component.outPort.x * cell + cell / 2,
    outDotY, outputSignal, theme
  );

  if (usingSprite) {
    drawSprite(ctx, sprite, x0, y0, w, h);
  } else {
    ctx.strokeStyle = theme.colors.macro;
    ctx.fillStyle = theme.colors.fillIdle;
    ctx.lineWidth = Math.max(2, cell * 0.12);
    const r = cell * 0.25;
    const bw = w - cell * 0.16, bh = h - cell * 0.16;
    ctx.beginPath();
    ctx.roundRect(x0 + cell * 0.08, y0 + cell * 0.08, bw, bh, r);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = theme.colors.label;
    ctx.font = `600 ${Math.round(cell * 0.75)}px ui-monospace, "JetBrains Mono", monospace`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(subcircuit, x0 + w / 2, y0 + h / 2);
  }

  for (let i = 0; i < component.inPorts.length; i++) {
    drawTailDot(ctx, cell, leftEdge, inDotYs[i], inputSignals[i] ?? 2, theme);
  }
  drawTailDot(ctx, cell, rightEdge, outDotY, outputSignal, theme);

  drawNameBelow(ctx, cell, component.name, x0, y0, w, h, theme.colors.labelMuted);

};

/**
 * A bit-shape or memory box: the same rounded box the collapsed macro draws,
 * with the site's tails and a name below. These four kinds used to fall
 * through to the package's default skins and render in a foreign visual
 * language beside the sprite-drawn gates.
 */
const drawBox = ({ ctx, cell, component, inputSignals, outputSignal, theme }, label, borderColor) => {
  const x0 = component.x * cell;
  const y0 = component.y * cell;
  const w = component.width * cell;
  const h = component.height * cell;
  const gap = cell * 0.45;
  const leftEdge = x0 + w * 0.08 - gap;
  const rightEdge = x0 + w * 0.92 + gap;

  const inDotYs = [];
  for (let i = 0; i < component.inPorts.length; i++) {
    const slot = component.inPorts[i];
    const sig = inputSignals[i] ?? 2;
    const portY = slot.coord.y * cell + cell / 2;
    inDotYs.push(portY);
    drawTailLine(ctx, leftEdge, slot.coord.x * cell + cell / 2, portY, sig, theme);
  }
  const outDotY = component.outPort.y * cell + cell / 2;
  drawTailLine(ctx, rightEdge, component.outPort.x * cell + cell / 2, outDotY, outputSignal, theme);

  ctx.strokeStyle = borderColor;
  ctx.fillStyle = theme.colors.fillIdle;
  ctx.lineWidth = Math.max(2, cell * 0.12);
  const r = cell * 0.25;
  ctx.beginPath();
  ctx.roundRect(x0 + cell * 0.08, y0 + cell * 0.08, w - cell * 0.16, h - cell * 0.16, r);
  ctx.fill();
  ctx.stroke();
  ctx.fillStyle = theme.colors.label;
  ctx.font = `600 ${Math.round(cell * 0.75)}px ui-monospace, "JetBrains Mono", monospace`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(label, x0 + w / 2, y0 + h / 2);

  for (let i = 0; i < component.inPorts.length; i++) {
    drawTailDot(ctx, cell, leftEdge, inDotYs[i], inputSignals[i] ?? 2, theme);
  }
  drawTailDot(ctx, cell, rightEdge, outDotY, outputSignal, theme);
};

/** `[i]` or `[lo:hi]`, the way the compiler's own preview writes a slice. */
const drawSlice = (args) => {
  const { lo, hi } = args.component.slice ?? { lo: 0, hi: 1 };
  drawBox(args, hi - lo <= 1 ? `[${lo}]` : `[${lo}:${hi}]`, args.theme.colors.stroke);
};

const drawConcat = (args) => {
  drawBox(args, '{·}', args.theme.colors.stroke);
};

/** `rom code[8,4]` — the label text comes from the renderer, so the canvas
 *  and the preview cannot spell a memory two ways. Named below like a macro. */
const drawMemory = (args) => {
  const { component, ctx, cell, theme } = args;
  const kind = component.kind.tag === 'primitive' ? component.kind.kind : ComponentKind.Rom;
  const label = memoryLabel(kind, component.name, component.bitWidth, component.memory?.addrWidth ?? 0);
  drawBox(args, label, theme.colors.macro);
  const x0 = component.x * cell, y0 = component.y * cell;
  drawNameBelow(ctx, cell, component.name, x0, y0, component.width * cell, component.height * cell, theme.colors.labelMuted);
};

/* ───── theme objects ──────────────────────────────────────────────── */

/**
 * 4px round-cap segments — matches the line style the blog used in its
 * `wires` override. Differs from the default in lineWidth (smaller +
 * uniform regardless of cell size) and skips the in-box stubs (the
 * port dots already anchor wires to gates). Horizontal segments arc
 * over recorded crossings so wires of different signals read as
 * separate strands rather than fusing at intersections.
 */
/**
 * A wire in the palette's colour for what it carries. A bus with a defined
 * value is a bus, whatever its bits: the badge above it says the number. The
 * route — every segment, arcing over its crossings — is traced by the
 * renderer's own `traceWire`, the same function its default painter uses, so
 * the site cannot draw a jump anywhere the renderer would not.
 */
function wireRenderer({ ctx, cell, wire, value, theme }) {
  const style = wireStyleOf(value);
  ctx.strokeStyle = theme.colors[wireColorKey(style)];
  // A touch heavier for a bus, so it reads as more than one bit.
  ctx.lineWidth = style === 'bus' ? 6 : 4;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.beginPath();
  traceWire(ctx, wire, cell);
  ctx.stroke();
}

const skins = {
  [ComponentKind.InputPin]: drawInputPin,
  [ComponentKind.OutputPin]: drawOutputPin,
  [ComponentKind.Led]: drawLed,
  [ComponentKind.NotGate]: drawNot,
  [ComponentKind.AndGate]: drawAnd,
  [ComponentKind.Slice]: drawSlice,
  [ComponentKind.Concat]: drawConcat,
  [ComponentKind.Rom]: drawMemory,
  [ComponentKind.Ram]: drawMemory,
  subcircuit: drawSubcircuit,
};

const sharedRenderers = {
  font: '600 11px ui-monospace, "JetBrains Mono", monospace',
  skins,
  // Transparent — the parent .lc element's --pane-bg shows through, so
  // the canvas always matches its block parent without us tracking the
  // pane color in two places. clearRect (not fillRect) is required: it
  // resets pixels to alpha 0 so each frame starts fresh and the parent
  // bg composites underneath the gate sprites + wire strokes.
  background: ({ ctx, cell, width, height }) => {
    ctx.clearRect(-4, -4, width * cell + 8, height * cell + 8);
  },
  wire: wireRenderer,
  // No port markers — each skin draws its own tail.
  portMarker: () => {},
  // The ring around a hovered or host-highlighted component, drawn by the
  // canvas after every skin. One hook, every kind — including the four above
  // that used to fall through to defaults that never read `hovered`.
  highlight: ({ ctx, cell, component, theme }) => drawHoverRing(ctx, cell, component, theme),
};

/** @type {import('circ-renderer').CircTheme<PaletteKey>} */
export const blogTheme = {
  colors: colorsDark,
  ...sharedRenderers,
};

/** @type {import('circ-renderer').CircTheme<PaletteKey>} */
export const blogThemeLight = {
  colors: colorsLight,
  ...sharedRenderers,
};

/** @returns {import('circ-renderer').CircTheme<PaletteKey>} */
export const pickTheme = () =>
  document.documentElement.dataset.theme === 'dark' ? blogTheme : blogThemeLight;
