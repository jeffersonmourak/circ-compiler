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
// data-theme attribute on <html>. Toggling the site theme later requires
// destroying and re-creating the canvas (handled in LiveCanvas.astro).

import { ComponentKind } from 'circ-renderer';
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

const drawOutputPin = ({ ctx, cell, component, inputSignals, theme }) => {
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

const drawLed = ({ ctx, cell, component, inputSignals, theme }) => {
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

const drawNot = ({ ctx, cell, component, inputSignals, outputSignal, theme }) => {
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

const drawAnd = ({ ctx, cell, component, inputSignals, outputSignal, theme }) => {
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

const drawSubcircuit = ({ ctx, cell, component, inputSignals, outputSignal, theme }) => {
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

/* ───── theme objects ──────────────────────────────────────────────── */

/**
 * 4px round-cap segments — matches the line style the blog used in its
 * `wires` override. Differs from the default in lineWidth (smaller +
 * uniform regardless of cell size) and skips the in-box stubs (the
 * port dots already anchor wires to gates). Horizontal segments arc
 * over recorded crossings so wires of different signals read as
 * separate strands rather than fusing at intersections.
 */
function wireRenderer({ ctx, cell, wire, signal, theme }) {
  ctx.strokeStyle =
    signal === 1
      ? theme.colors.wireActive
      : signal === 0
        ? theme.colors.wireIdle
        : theme.colors.wireUndefined;
  ctx.lineWidth = 4;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  const arcRadius = cell * 0.4;
  for (const seg of wire.segments) {
    const horiz = seg.from.y === seg.to.y;
    const startX = seg.from.x * cell + cell / 2;
    const startY = seg.from.y * cell + cell / 2;
    const endX = seg.to.x * cell + cell / 2;
    const endY = seg.to.y * cell + cell / 2;
    if (!horiz) {
      ctx.beginPath();
      ctx.moveTo(startX, startY);
      ctx.lineTo(endX, endY);
      ctx.stroke();
      continue;
    }
    const [segLo, segHi] = [startX, endX].sort((a, b) => a - b);
    const y = startY;
    const jumps = wire.crossings
      .filter((c) => c.y === seg.from.y && c.x * cell + cell / 2 >= segLo && c.x * cell + cell / 2 <= segHi)
      .map((c) => c.x * cell + cell / 2)
      .sort((a, b) => a - b);
    ctx.beginPath();
    let cursor = segLo;
    for (const jx of jumps) {
      ctx.moveTo(cursor, y);
      ctx.lineTo(jx - arcRadius, y);
      ctx.arc(jx, y, arcRadius, Math.PI, 0, false);
      cursor = jx + arcRadius;
    }
    ctx.moveTo(cursor, y);
    ctx.lineTo(segHi, y);
    ctx.stroke();
  }
}

const skins = {
  [ComponentKind.InputPin]: drawInputPin,
  [ComponentKind.OutputPin]: drawOutputPin,
  [ComponentKind.Led]: drawLed,
  [ComponentKind.NotGate]: drawNot,
  [ComponentKind.AndGate]: drawAnd,
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
};

export const blogTheme = {
  colors: colorsDark,
  ...sharedRenderers,
};

export const blogThemeLight = {
  colors: colorsLight,
  ...sharedRenderers,
};

export const pickTheme = () =>
  document.documentElement.dataset.theme === 'dark' ? blogTheme : blogThemeLight;
