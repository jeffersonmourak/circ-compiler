/**
 * Port of the official site's custom circ-renderer theme —
 * circ-compiler/site/src/utils/circ-theme.mjs (itself a 1:1 port of the
 * blog's circ-runtime theme). Colors, geometry and skin logic verbatim;
 * only the call signature is adapted to renderScene's.
 *
 * Sprites are the base64 PNGs from site/src/utils/circ-assets.mjs.
 */
import { loadAssets } from "./site/src/utils/circ-assets.mjs";

let sprites = null;
export const spritesReady = loadAssets().then((lib) => { sprites = lib; return lib; });

/* ───── palettes (verbatim) ─────────────────────────────────────────── */
export const siteDark = {
  background: "#0c0517",
  grid: "#1c0f2a",
  stroke: "#ffffff",
  fillIdle: "#1c0f2a",
  fillActive: "hsl(134 61% 41% / 1)",
  fillUndefined: "#241636",
  wireIdle: "#dee2e6",
  wireActive: "hsl(134 61% 41% / 1)",
  wireUndefined: "#3a2752",
  label: "#ffffff",
  labelMuted: "#aaa",
  labelOnComponent: "#ffffff",
  macro: "#bea7ff",
  inputOn: "#fd7e14",
  inputOff: "hsl(134 61% 41%)",
  inputBorderOn: "#634e0d",
  inputBorderOff: "#165a26",
  inputHover: "#ffc107",
  outputOn: "#0b99ff",
  outputOff: "#bee3ff",
  outputBorderOn: "#0059b9",
  outputBorderOff: "#24b4ff",
  portOn: "#fd7e14",
  portOff: "#634e0d",
};

export const siteLight = {
  background: "#f4eefb",
  grid: "#d4c8e8",
  stroke: "#443856",
  fillIdle: "#f4eefb",
  fillActive: "hsl(134 61% 32% / 1)",
  fillUndefined: "#c8b8dc",
  wireIdle: "#5d3a96",
  wireActive: "hsl(134 61% 32% / 1)",
  wireUndefined: "#a89cc0",
  label: "#443856",
  labelMuted: "#8a7e9a",
  labelOnComponent: "#ffffff",
  macro: "#6e49ab",
  inputOn: "#d65f0a",
  inputOff: "hsl(134 61% 32%)",
  inputBorderOn: "#8a4408",
  inputBorderOff: "#0f4419",
  inputHover: "#b8860b",
  outputOn: "#0066cc",
  outputOff: "#7fc3ff",
  outputBorderOn: "#003d7a",
  outputBorderOff: "#0066cc",
  portOn: "#d65f0a",
  portOff: "#8a4408",
};

export const siteFont = '600 11px ui-monospace, "JetBrains Mono", monospace';

/* ───── helpers (verbatim) ──────────────────────────────────────────── */
function drawTailLine(ctx, gateEdge, portEnd, y, signal, t) {
  ctx.strokeStyle = signal === 1 ? t.wireActive : signal === 0 ? t.wireIdle : t.wireUndefined;
  ctx.lineWidth = 4;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(gateEdge, y);
  ctx.lineTo(portEnd, y);
  ctx.stroke();
}

function drawTailDot(ctx, cell, gateEdge, y, signal, t) {
  ctx.fillStyle = signal === 1 ? t.portOn : t.portOff;
  ctx.beginPath();
  ctx.arc(gateEdge, y, cell * 0.28, 0, Math.PI * 2);
  ctx.fill();
}

function drawNameBelow(ctx, cell, name, bx, by, bw, bh, color, yOffset = 0) {
  if (!name) return;
  ctx.fillStyle = color;
  ctx.font = `500 ${Math.round(cell * 0.65)}px ui-monospace, "JetBrains Mono", monospace`;
  ctx.textAlign = "center";
  ctx.textBaseline = "top";
  ctx.fillText(name, bx + bw / 2, by + bh + (cell + yOffset) * 0.05);
}

const nameFitsInside = (c) => c.name.length >= 3 || c.width >= 7;

function drawPinCircle(ctx, cell, bx, by, bw, bh, fill, stroke, label, font, labelColor) {
  const cx = bx + bw / 2, cy = by + bh / 2;
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
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(label, cx, cy);
}

function spriteRect(x, y, w, h) {
  const size = Math.min(w, h);
  const cx = x + w / 2, cy = y + h / 2;
  return { left: cx - size / 2, right: cx + size / 2, size, cx, cy };
}

function drawSprite(ctx, img, x, y, w, h) {
  const rect = spriteRect(x, y, w, h);
  ctx.save();
  ctx.translate(rect.cx, rect.cy);
  ctx.rotate(Math.PI / 2);
  ctx.drawImage(img, -rect.size / 2, -rect.size / 2, rect.size, rect.size);
  ctx.restore();
}

function spriteForSubcircuit(type) {
  if (!sprites) return undefined;
  switch (String(type).toLowerCase()) {
    case "and": return sprites.AND;
    case "nand": return sprites.NAND;
    case "or": return sprites.OR;
    case "xor": return sprites.XOR;
    case "not": return sprites.NOT;
    default: return undefined;
  }
}

/* ───── skins (verbatim geometry) ───────────────────────────────────── */
export const siteSkins = {
  input_pin: ({ ctx, t, cell, font, c, outSig, hovered }) => {
    const x = c.x * cell, y = c.y * cell, w = c.width * cell, h = c.height * cell;
    const isOn = outSig === 1;
    const r = Math.min(w, h) / 2 - cell * 0.05;
    const cx = x + w / 2;
    const tailEdge = cx + r + cell * 0.45;
    const portY = c.outPort.y * cell + cell / 2;
    const portX = c.outPort.x * cell + cell / 2;
    drawTailLine(ctx, tailEdge, portX, portY, outSig, t);
    let fill = isOn ? t.inputOn : t.inputOff;
    let stroke = isOn ? t.inputBorderOn : t.inputBorderOff;
    if (hovered) { fill = t.inputHover; stroke = t.inputHover; }
    const inside = nameFitsInside(c) ? c.name : isOn ? "1" : "0";
    drawPinCircle(ctx, cell, x, y, w, h, fill, stroke, inside,
      font ?? `600 ${Math.round(cell * 0.8)}px ui-monospace, monospace`, t.labelOnComponent);
    if (!nameFitsInside(c)) drawNameBelow(ctx, cell, c.name, x, y, w, h, t.labelMuted);
    drawTailDot(ctx, cell, tailEdge, portY, outSig, t);
  },

  output_pin: ({ ctx, t, cell, font, c, inSigs }) => {
    const x = c.x * cell, y = c.y * cell, w = c.width * cell, h = c.height * cell;
    const sig = inSigs[0] ?? 2;
    const isOn = sig === 1;
    const r = Math.min(w, h) / 2 - cell * 0.05;
    const cx = x + w / 2;
    const tailEdge = cx - r - cell * 0.45;
    const slot = c.inPorts[0];
    let dotY = 0;
    if (slot) {
      dotY = slot.coord.y * cell + cell / 2;
      drawTailLine(ctx, tailEdge, slot.coord.x * cell + cell / 2, dotY, sig, t);
    }
    const inside = nameFitsInside(c) ? c.name : isOn ? "1" : "0";
    drawPinCircle(ctx, cell, x, y, w, h,
      isOn ? t.outputOn : t.outputOff,
      isOn ? t.outputBorderOn : t.outputBorderOff,
      inside, font ?? `600 ${Math.round(cell * 0.7)}px ui-monospace, monospace`, t.labelOnComponent);
    if (!nameFitsInside(c)) drawNameBelow(ctx, cell, c.name, x, y, w, h, t.labelMuted);
    if (slot) drawTailDot(ctx, cell, tailEdge, dotY, sig, t);
  },

  led: ({ ctx, t, cell, c, inSigs }) => {
    const cx = (c.x + c.width / 2) * cell, cy = (c.y + c.height / 2) * cell;
    const r = Math.min(c.width, c.height) * cell * 0.4;
    const sig = inSigs[0] ?? 2;
    const isOn = sig === 1;
    const tailEdge = cx - r - cell * 0.45;
    const slot = c.inPorts[0];
    let dotY = 0;
    if (slot) {
      dotY = slot.coord.y * cell + cell / 2;
      drawTailLine(ctx, tailEdge, slot.coord.x * cell + cell / 2, dotY, sig, t);
    }
    ctx.fillStyle = isOn ? t.outputOn : t.outputOff;
    ctx.strokeStyle = isOn ? t.outputBorderOn : t.outputBorderOff;
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
    drawNameBelow(ctx, cell, c.name, c.x * cell, c.y * cell, c.width * cell, c.height * cell, t.labelMuted);
    if (slot) drawTailDot(ctx, cell, tailEdge, dotY, sig, t);
  },

  not_gate: ({ ctx, t, cell, c, inSigs, outSig }) => {
    const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
    const usingSprite = !!sprites?.NOT;
    const rect = spriteRect(x0, y0, w, h);
    const gap = cell * 0.45;
    const leftEdge = (usingSprite ? rect.left : x0 + w * 0.1) - gap;
    const rightEdge = (usingSprite ? rect.right : x0 + w * 0.95) + gap;
    const inSlot = c.inPorts[0];
    const inSig = inSigs[0] ?? 2;
    const inDotY = inSlot ? inSlot.coord.y * cell + cell / 2 : 0;
    if (inSlot) drawTailLine(ctx, leftEdge, inSlot.coord.x * cell + cell / 2, inDotY, inSig, t);
    const outDotY = c.outPort.y * cell + cell / 2;
    drawTailLine(ctx, rightEdge, c.outPort.x * cell + cell / 2, outDotY, outSig, t);
    if (usingSprite) {
      drawSprite(ctx, sprites.NOT, x0, y0, w, h);
    } else {
      ctx.strokeStyle = t.stroke;
      ctx.fillStyle = t.background;
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
    if (inSlot) drawTailDot(ctx, cell, leftEdge, inDotY, inSig, t);
    drawTailDot(ctx, cell, rightEdge, outDotY, outSig, t);
    drawNameBelow(ctx, cell, c.name, x0, y0, w, h, t.labelMuted, -cell * 15);
  },

  and_gate: ({ ctx, t, cell, c, inSigs, outSig }) => {
    const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
    const usingSprite = !!sprites?.AND;
    const gap = cell * 0.45;
    const leftEdge = x0 + w * 0.1 - gap;
    const rightEdge = x0 + w * 0.92 + gap;
    const inDotYs = [];
    for (let i = 0; i < c.inPorts.length; i++) {
      const slot = c.inPorts[i];
      const sig = inSigs[i] ?? 2;
      const portY = slot.coord.y * cell + cell / 2;
      inDotYs.push(portY);
      drawTailLine(ctx, leftEdge, slot.coord.x * cell + cell / 2, portY, sig, t);
    }
    const outDotY = c.outPort.y * cell + cell / 2;
    drawTailLine(ctx, rightEdge, c.outPort.x * cell + cell / 2, outDotY, outSig, t);
    if (usingSprite) {
      drawSprite(ctx, sprites.AND, x0, y0, w, h);
    } else {
      ctx.strokeStyle = t.stroke;
      ctx.fillStyle = t.background;
      ctx.lineWidth = Math.max(1, cell * 0.1);
      const left = x0 + cell * 0.15, top = y0 + cell * 0.15;
      const bot = y0 + h - cell * 0.15, flat = x0 + w * 0.5, right = x0 + w - cell * 0.15;
      ctx.beginPath();
      ctx.moveTo(left, top);
      ctx.lineTo(flat, top);
      ctx.bezierCurveTo(right, top, right, bot, flat, bot);
      ctx.lineTo(left, bot);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
    }
    for (let i = 0; i < c.inPorts.length; i++) {
      drawTailDot(ctx, cell, leftEdge, inDotYs[i], inSigs[i] ?? 2, t);
    }
    drawTailDot(ctx, cell, rightEdge, outDotY, outSig, t);
    if (c.name) {
      ctx.fillStyle = t.labelOnComponent;
      ctx.font = `600 ${Math.round(cell * 0.7)}px ui-monospace, "JetBrains Mono", monospace`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(c.name, x0 + w / 2, y0 + h / 2);
    }
  },

  subcircuit: ({ ctx, t, cell, c, inSigs, outSig }) => {
    const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
    const subcircuit = c.subcircuit ?? "";
    const sprite = spriteForSubcircuit(subcircuit);
    const usingSprite = !!sprite;
    const gap = cell * 0.45;
    const rect = spriteRect(x0, y0, w, h);
    const leftEdge = (usingSprite ? rect.left : x0 + w * 0.08) - gap;
    const rightEdge = (usingSprite ? rect.right : x0 + w * 0.92) + gap;
    const inDotYs = [];
    for (let i = 0; i < c.inPorts.length; i++) {
      const slot = c.inPorts[i];
      const sig = inSigs[i] ?? 2;
      const portY = slot.coord.y * cell + cell / 2;
      inDotYs.push(portY);
      drawTailLine(ctx, leftEdge, slot.coord.x * cell + cell / 2, portY, sig, t);
    }
    const outDotY = c.outPort.y * cell + cell / 2;
    drawTailLine(ctx, rightEdge, c.outPort.x * cell + cell / 2, outDotY, outSig, t);
    if (usingSprite) {
      drawSprite(ctx, sprite, x0, y0, w, h);
    } else {
      ctx.strokeStyle = t.macro;
      ctx.fillStyle = t.fillIdle;
      ctx.lineWidth = Math.max(2, cell * 0.12);
      ctx.beginPath();
      ctx.roundRect(x0 + cell * 0.08, y0 + cell * 0.08, w - cell * 0.16, h - cell * 0.16, cell * 0.25);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = t.label;
      ctx.font = `600 ${Math.round(cell * 0.75)}px ui-monospace, "JetBrains Mono", monospace`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(subcircuit, x0 + w / 2, y0 + h / 2);
    }
    for (let i = 0; i < c.inPorts.length; i++) {
      drawTailDot(ctx, cell, leftEdge, inDotYs[i], inSigs[i] ?? 2, t);
    }
    drawTailDot(ctx, cell, rightEdge, outDotY, outSig, t);
    drawNameBelow(ctx, cell, c.name, x0, y0, w, h, t.labelMuted);
  },
};

/**
 * The site's `wire` override: flat 4px strokes, no in-box stubs, and
 * tri-state only — it never consults wireStyleOf, so bus nets lose the
 * bus color entirely.
 */
export function drawWireSite(ctx, t, cell, wire, signal) {
  ctx.strokeStyle = signal === 1 ? t.wireActive : signal === 0 ? t.wireIdle : t.wireUndefined;
  ctx.lineWidth = 4;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  const arcRadius = cell * 0.4;
  for (const seg of wire.segments) {
    const startX = seg.from.x * cell + cell / 2, startY = seg.from.y * cell + cell / 2;
    const endX = seg.to.x * cell + cell / 2, endY = seg.to.y * cell + cell / 2;
    if (seg.from.y !== seg.to.y) {
      ctx.beginPath();
      ctx.moveTo(startX, startY);
      ctx.lineTo(endX, endY);
      ctx.stroke();
      continue;
    }
    const [segLo, segHi] = [startX, endX].sort((a, b) => a - b);
    const jumps = (wire.crossings ?? [])
      .filter((c) => c.y === seg.from.y && c.x * cell + cell / 2 >= segLo && c.x * cell + cell / 2 <= segHi)
      .map((c) => c.x * cell + cell / 2)
      .sort((a, b) => a - b);
    ctx.beginPath();
    let cursor = segLo;
    for (const jx of jumps) {
      ctx.moveTo(cursor, startY);
      ctx.lineTo(jx - arcRadius, startY);
      ctx.arc(jx, startY, arcRadius, Math.PI, 0, false);
      cursor = jx + arcRadius;
    }
    ctx.moveTo(cursor, startY);
    ctx.lineTo(segHi, startY);
    ctx.stroke();
  }
}


/* ═══ PROPOSED: an upgrade of the SITE theme ════════════════════════
 * Keeps the site's identity — orange HIGH, green LOW, blue outputs,
 * circular pins, tails with terminal dots, its gate sprites, and the
 * lavender / deep-purple panes. Fixes the eight gaps: buses get a real
 * treatment, slice + concat get site skins, strokes scale with cell,
 * idle stops out-shouting active, sprites respond to signal, light mode
 * gets light sprites, hover keeps state readable, and shape carries the
 * signal alongside color.
 */

export const nextSiteDark = {
  background: '#0c0517',
  surface: '#160b26',
  grid: '#1c0f2a',
  stroke: '#e8ddff',
  fillIdle: '#160b26',
  fillActive: 'hsl(134 61% 52%)',
  fillUndefined: '#241636',
  wireIdle: '#4c3a6b',
  wireActive: 'hsl(134 61% 52%)',
  wireUndefined: '#33244d',
  wireBus: '#bea7ff',
  busLabel: '#0c0517',
  label: '#f0e9ff',
  labelMuted: '#8f7fb0',
  labelOnComponent: '#0c0517',
  macro: '#bea7ff',
  inputOn: '#fd7e14',
  inputOff: 'hsl(134 38% 34%)',
  inputBorderOn: '#ffab5e',
  inputBorderOff: 'hsl(134 40% 46%)',
  inputHover: '#ffc107',
  outputOn: '#0b99ff',
  outputOff: '#2c4a6b',
  outputBorderOn: '#7cc8ff',
  outputBorderOff: '#4a6e93',
  portOn: '#fd7e14',
  portOff: '#5a4a70',
  spriteInk: '#e8ddff',
};

export const nextSiteLight = {
  background: '#f4eefb',
  surface: '#ffffff',
  grid: '#d4c8e8',
  stroke: '#3a2f4a',
  fillIdle: '#ffffff',
  fillActive: 'hsl(134 61% 32%)',
  fillUndefined: '#ded3ec',
  wireIdle: '#a394bd',
  wireActive: 'hsl(134 61% 32%)',
  wireUndefined: '#c9bedb',
  wireBus: '#6e49ab',
  busLabel: '#ffffff',
  label: '#2e2440',
  labelMuted: '#7d6f92',
  labelOnComponent: '#ffffff',
  macro: '#6e49ab',
  inputOn: '#d65f0a',
  inputOff: 'hsl(134 40% 34%)',
  inputBorderOn: '#a04708',
  inputBorderOff: 'hsl(134 45% 26%)',
  inputHover: '#b8860b',
  outputOn: '#0066cc',
  outputOff: '#9dc8f0',
  outputBorderOn: '#00478f',
  outputBorderOff: '#5c9fd6',
  portOn: '#d65f0a',
  portOff: '#8a4408',
  spriteInk: '#8672b5',
};

/** Hex for a multi-bit value, matching the library's badge format. */
function nsHex(v) {
  if (!v) return '?';
  const mask = v.width >= 32 ? 0xffffffff : ((1 << v.width) - 1) >>> 0;
  if (((v.defined & mask) >>> 0) !== mask) return '?';
  return '0x' + ((v.value & mask) >>> 0).toString(16).toUpperCase().padStart(Math.ceil(v.width / 4), '0');
}

const nsFont = (cell, w = 600) =>
  `${w} ${Math.max(9, Math.round(cell * 0.6))}px ui-monospace, "JetBrains Mono", monospace`;

/** Stroke weight now scales with the cell instead of sitting at 4px. */
const nsWire = (cell) => Math.max(2, cell * 0.2);

/** Recolor a sprite by compositing a flat fill inside its own alpha. */
const tintCache = new WeakMap();
function tintedSprite(img, color, alpha) {
  let perImg = tintCache.get(img);
  if (!perImg) { perImg = new Map(); tintCache.set(img, perImg); }
  const key = `${color}|${alpha}`;
  const hit = perImg.get(key);
  if (hit) return hit;
  const c = document.createElement('canvas');
  c.width = img.width;
  c.height = img.height;
  const g = c.getContext('2d');
  g.drawImage(img, 0, 0);
  g.globalCompositeOperation = 'source-atop';
  g.globalAlpha = alpha;
  g.fillStyle = color;
  g.fillRect(0, 0, c.width, c.height);
  perImg.set(key, c);
  return c;
}

/**
 * Halo for sprite art: the tinted sprite blurred ONCE at cache-build time
 * on an oversized canvas, so per-frame it is a single drawImage. Padding
 * is 18% of the sprite on every side; `nsSprite` maps it back with the
 * same ratio.
 */
const haloCache = new WeakMap();
const HALO_PAD = 0.14;
function haloSprite(img, color) {
  let perImg = haloCache.get(img);
  if (!perImg) { perImg = new Map(); haloCache.set(img, perImg); }
  const hit = perImg.get(color);
  if (hit) return hit;
  const pad = Math.round(img.width * HALO_PAD);
  const c = document.createElement('canvas');
  c.width = img.width + pad * 2;
  c.height = img.height + pad * 2;
  const g = c.getContext('2d');
  g.shadowColor = color;
  g.shadowBlur = pad * 0.8;
  g.drawImage(tintedSprite(img, color, 1), pad, pad);
  g.drawImage(tintedSprite(img, color, 1), pad, pad);
  // Remove the crisp core so only the soft field remains underneath.
  g.shadowBlur = 0;
  g.globalCompositeOperation = 'destination-out';
  const shrink = Math.max(1, Math.round(img.width * 0.012));
  g.drawImage(tintedSprite(img, color, 1), pad + shrink, pad + shrink, img.width - shrink * 2, img.height - shrink * 2);
  perImg.set(color, c);
  return c;
}

/**
 * Halo for vector shapes. Same recipe as the sprite halo, done per shape
 * on a small offscreen canvas: blur the shape once, knock its own core
 * out so only the soft field around the silhouette remains, then draw
 * the result underneath the crisp shape. Cached by shape signature so
 * per-frame cost is one drawImage. `pathFn(g)` must trace the shape
 * with beginPath/…/closePath into `g`, in the box's local coordinates.
 */
const vecHaloCache = new Map();
function nsVecHalo(ctx, key, x, y, w, h, color, spread, pathFn) {
  const dpr = 2;
  const cacheKey = `${key}|${Math.round(w)}x${Math.round(h)}|${color}|${Math.round(spread)}`;
  let c = vecHaloCache.get(cacheKey);
  if (!c) {
    c = document.createElement('canvas');
    c.width = Math.ceil((w + spread * 2) * dpr);
    c.height = Math.ceil((h + spread * 2) * dpr);
    const g = c.getContext('2d');
    g.scale(dpr, dpr);
    g.translate(spread, spread);
    g.shadowColor = color;
    g.shadowBlur = spread * 0.9;
    g.fillStyle = color;
    g.strokeStyle = color;
    // pathFn may paint itself (stroke shapes); fill() on an empty path is a no-op.
    pathFn(g); g.fill();
    pathFn(g); g.fill();
    g.shadowBlur = 0;
    g.globalCompositeOperation = 'destination-out';
    g.save();
    g.translate(w / 2, h / 2);
    g.scale(1 - 1.2 / Math.max(w, h), 1 - 1.2 / Math.max(w, h));
    g.translate(-w / 2, -h / 2);
    pathFn(g); g.fill();
    g.restore();
    vecHaloCache.set(cacheKey, c);
  }
  ctx.save();
  ctx.globalAlpha = 0.55;
  ctx.drawImage(c, x - spread, y - spread, w + spread * 2, h + spread * 2);
  ctx.restore();
}

/** Legacy glow entry used by pins/LED/wires: soft under-paint of the same path. */
function nsGlow(ctx, color, spread, fn) {
  // Pins, LEDs and wires are circles/strokes — an oversize translucent
  // pass under them reads as a halo without disturbing the silhouette.
  ctx.save();
  ctx.globalAlpha = 0.22;
  ctx.strokeStyle = color;
  ctx.fillStyle = color;
  ctx.lineWidth = (ctx.lineWidth || 1) + spread;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  const prevFill = ctx.fill.bind(ctx), prevStroke = ctx.stroke.bind(ctx);
  ctx.fill = function (...a) { prevFill(...a); prevStroke(); };
  fn();
  ctx.fill = prevFill;
  ctx.stroke = prevStroke;
  ctx.restore();
  fn();
}

/** Sprite that answers to signal: tinted to ink, warmed + haloed when HIGH. */
function nsSprite(ctx, img, x, y, w, h, sig, t, cell) {
  nsSpriteRect(ctx, img, spriteRect(x, y, w, h), sig, t, cell);
}
function nsSpriteRect(ctx, img, rect, sig, t, cell) {
  const ink = sig === 1 ? t.inputOn : sig === 2 ? t.labelMuted : t.spriteInk;
  const alpha = sig === 1 ? 0.92 : sig === 2 ? 0.5 : 0.94;
  const art = tintedSprite(img, ink, alpha);
  ctx.save();
  const scx = rect.left + rect.size / 2, scy = (rect.top ?? rect.cy - rect.size / 2) + rect.size / 2;
  ctx.translate(scx, scy);
  ctx.rotate(Math.PI / 2);
  if (sig === 1) {
    const halo = haloSprite(img, t.inputOn);
    const hs = rect.size * (1 + HALO_PAD * 2);
    ctx.globalAlpha = 0.55;
    ctx.drawImage(halo, -hs / 2, -hs / 2, hs, hs);
    ctx.globalAlpha = 1;
  }
  ctx.drawImage(art, -rect.size / 2, -rect.size / 2, rect.size, rect.size);
  ctx.restore();
}

function nsTail(ctx, cell, from, to, y, sig, t, bus) {
  ctx.strokeStyle = bus ? t.wireBus : sig === 1 ? t.wireActive : sig === 0 ? t.wireIdle : t.wireUndefined;
  ctx.lineWidth = nsWire(cell) * (bus ? 1.5 : 1);
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(from, y);
  ctx.lineTo(to, y);
  ctx.stroke();
}

function nsDot(ctx, cell, x, y, sig, t) {
  ctx.fillStyle = sig === 1 ? t.portOn : t.portOff;
  ctx.beginPath();
  ctx.arc(x, y, cell * 0.24, 0, Math.PI * 2);
  ctx.fill();
}

function nsName(ctx, cell, name, bx, by, bw, bh, color) {
  if (!name) return;
  ctx.fillStyle = color;
  ctx.font = nsFont(cell, 500);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  ctx.fillText(name, bx + bw / 2, by + bh + cell * 0.16);
}

/**
 * Pin circle where SHAPE carries the state as well as color: HIGH is a
 * solid disc, LOW is a ring with a small core, undefined is dashed.
 */
function nsPinCircle(ctx, cell, bx, by, bw, bh, on, undef_, fill, border, t, label) {
  const cx = bx + bw / 2, cy = by + bh / 2;
  const r = Math.min(bw, bh) / 2 - cell * 0.08;
  const lw = Math.max(2, cell * 0.14);
  if (undef_) {
    ctx.setLineDash([cell * 0.28, cell * 0.24]);
    ctx.strokeStyle = t.labelMuted;
    ctx.lineWidth = lw;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
    return { cx, cy, r };
  }
  if (on) {
    nsGlow(ctx, fill, cell * 0.7, () => {
      ctx.fillStyle = fill;
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.fill();
    });
    ctx.strokeStyle = border;
    ctx.lineWidth = lw;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
  } else {
    ctx.fillStyle = t.surface;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = border;
    ctx.lineWidth = lw * 1.2;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
  }
  if (label) {
    ctx.fillStyle = on ? t.labelOnComponent : t.label;
    ctx.font = nsFont(cell, 700);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(label, cx, cy + cell * 0.03);
  }
  return { cx, cy, r };
}

/**
 * Value chip above the pin. Solid when HIGH or carrying a bus, outlined
 * when LOW, dashed when undefined — the same fill-vs-outline cue the
 * circle uses, so the pair reads as one unit.
 */
function nsValuePill(ctx, t, cell, cx, bottomY, text, mode, fill, ink) {
  ctx.save();
  ctx.font = nsFont(cell, 700);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  // `bottomY` is the lowest the chip may reach — callers pass the outer
  // edge of whatever the pin draws (circle stroke, hover ring), so the
  // chip never lands on it. Needs ROW_GUTTER 2.
  const h = cell * 0.92;
  const w = ctx.measureText(text).width + cell * 0.7;
  const y = bottomY - h;
  ctx.beginPath();
  ctx.roundRect(cx - w / 2, y, w, h, h / 2);
  if (mode === 'solid') {
    ctx.fillStyle = fill;
    ctx.fill();
  } else {
    ctx.fillStyle = t.surface;
    ctx.fill();
    ctx.strokeStyle = mode === 'dashed' ? t.labelMuted : fill;
    ctx.lineWidth = Math.max(1.5, cell * 0.1);
    if (mode === 'dashed') ctx.setLineDash([cell * 0.26, cell * 0.22]);
    ctx.stroke();
    ctx.setLineDash([]);
  }
  ctx.fillStyle = ink;
  ctx.fillText(text, cx, y + h / 2 + cell * 0.03);
  ctx.restore();
}

/** Hover keeps the state visible — a ring outside the pin, not a fill swap. */
function nsHoverRing(ctx, cell, cx, cy, r, t) {
  ctx.strokeStyle = t.inputHover;
  ctx.lineWidth = Math.max(2, cell * 0.13);
  ctx.beginPath();
  ctx.arc(cx, cy, r + cell * 0.38, 0, Math.PI * 2);
  ctx.stroke();
}

/* ── slice + concat: assets that show the operation ────────────────
 * A labelled box tells you a slice exists; it doesn't tell you which
 * bits it takes. These two draw the bit-field itself: SLICE is a ruler
 * of the incoming word with the tapped range picked out, CONCAT is the
 * assembled word with a lane per operand in order.
 */

/** Shared shell: inset rounded rect in the bus color. */
function nsShell(ctx, t, cell, c) {
  const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
  const inset = cell * 0.35;
  const bx = x0 + inset, bw = w - inset * 2;
  ctx.fillStyle = t.surface;
  ctx.strokeStyle = t.wireBus;
  ctx.lineWidth = Math.max(1.75, cell * 0.1);
  ctx.beginPath();
  ctx.roundRect(bx, y0, bw, h, cell * 0.16);
  ctx.fill();
  ctx.stroke();
  return { x0, y0, w, h, bx, bw, inset };
}

/**
 * SLICE — a ruler of the incoming word, MSB left, with the tapped range
 * filled and the discarded bits left hollow. The [lo:hi] label sits
 * under the ruler so the notation and the picture agree.
 */
function nsSliceAsset(ctx, t, cell, c, inSigs, outSig) {
  const { y0, h, bx, bw } = nsShell(ctx, t, cell, c);
  const sl = c.slice ?? { lo: 0, hi: 1 };
  const inWidth = Math.max(c.inValues?.[0]?.width ?? 0, sl.hi, 1);
  const padX = cell * 0.32;
  const gap = Math.max(1, cell * 0.05);
  const rulerW = bw - padX * 2;
  const tickW = (rulerW - gap * (inWidth - 1)) / inWidth;
  const rulerH = h * 0.32;
  const ry = y0 + h * 0.2;
  for (let i = 0; i < inWidth; i++) {
    const bit = inWidth - 1 - i;              // MSB first, so it reads like hex
    const taken = bit >= sl.lo && bit < sl.hi;
    const tx = bx + padX + i * (tickW + gap);
    ctx.beginPath();
    ctx.roundRect(tx, ry, tickW, rulerH, Math.min(tickW / 2, cell * 0.07));
    if (taken) {
      ctx.fillStyle = t.wireBus;
      ctx.globalAlpha = outSig === 2 ? 0.4 : outSig === 0 ? 0.7 : 1;
      ctx.fill();
      ctx.globalAlpha = 1;
    } else {
      // Discarded bits still have to read as bit positions, so they get
      // a muted ink rather than a near-surface fill.
      ctx.fillStyle = t.labelMuted;
      ctx.globalAlpha = 0.38;
      ctx.fill();
      ctx.globalAlpha = 1;
    }
  }
  ctx.fillStyle = t.label;
  ctx.font = nsFont(cell, 700);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(
    sl.hi - sl.lo <= 1 ? `[${sl.lo}]` : `[${sl.lo}:${sl.hi}]`,
    bx + bw / 2, y0 + h * 0.74
  );
}

/**
 * CONCAT — the assembled word as a stack of bands on the output side,
 * one per operand, with a numbered lane running in from each port so the
 * bit order is readable rather than implied.
 */
function nsConcatAsset(ctx, t, cell, c, inSigs, outSig) {
  const { y0, h, bx, bw } = nsShell(ctx, t, cell, c);
  const n = Math.max(1, c.inPorts.length);
  const barW = cell * 0.5;
  const barX = bx + bw - cell * 0.42 - barW;
  const barY = y0 + cell * 0.35;
  const barH = h - cell * 0.7;
  const gap = Math.max(1, cell * 0.06);
  const segH = (barH - gap * (n - 1)) / n;
  const laneX = bx + cell * 1.25;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  for (let i = 0; i < n; i++) {
    const segY = barY + i * (segH + gap);
    const segMid = segY + segH / 2;
    const port = c.inPorts[i];
    const py = port ? port.coord.y * cell + cell / 2 : segMid;
    ctx.strokeStyle = t.wireBus;
    ctx.globalAlpha = Math.max(0.45, 1 - i * 0.2);
    ctx.lineWidth = Math.max(1.5, cell * 0.11);
    ctx.beginPath();
    ctx.moveTo(bx + cell * 0.78, py);
    ctx.lineTo(laneX, py);
    ctx.arcTo(barX - cell * 0.22, py, barX, segMid, cell * 0.3);
    ctx.lineTo(barX, segMid);
    ctx.stroke();
    ctx.fillStyle = t.wireBus;
    ctx.beginPath();
    ctx.roundRect(barX, segY, barW, segH, cell * 0.07);
    ctx.fill();
    ctx.globalAlpha = 1;
    // Operand index sits on the lane's own baseline, left of where the
    // lane starts, so every index including 0 clears the shell border.
    ctx.fillStyle = t.labelMuted;
    ctx.font = nsFont(cell, 600);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(String(i), bx + cell * 0.42, py);
  }
}

export const nextSiteSkins = {
  input_pin: ({ ctx, t, cell, c, outSig, hovered }) => {
    const x = c.x * cell, y = c.y * cell, w = c.width * cell, h = c.height * cell;
    const on = outSig === 1;
    const bus = (c.bitWidth ?? 1) > 1;
    const r = Math.min(w, h) / 2 - cell * 0.08;
    const tailEdge = x + w / 2 + r + cell * 0.4;
    const portY = c.outPort.y * cell + cell / 2;
    nsTail(ctx, cell, tailEdge, c.outPort.x * cell + cell / 2, portY, outSig, t, bus);
    // Value rides in a chip above; the name sits in the circle. Same
    // arrangement whether the pin is one bit or sixty-four. The chip is
    // seated clear of the hover ring's outer edge, and the ring is drawn
    // last so nothing paints over it.
    const cx = x + w / 2, cy = y + h / 2;
    nsValuePill(
      ctx, t, cell, cx, cy - r - cell * 0.5,
      bus ? nsHex(c.value) : outSig === 2 ? '?' : on ? '1' : '0',
      bus || on ? 'solid' : outSig === 2 ? 'dashed' : 'outline',
      bus ? t.wireBus : on ? t.inputOn : t.inputBorderOff,
      bus ? t.busLabel : on ? t.labelOnComponent : t.label
    );
    const geo = nsPinCircle(
      ctx, cell, x, y, w, h, on, outSig === 2,
      on ? t.inputOn : t.inputOff,
      on ? t.inputBorderOn : t.inputBorderOff,
      t, c.name
    );
    if (hovered) nsHoverRing(ctx, cell, geo.cx, geo.cy, geo.r, t);
    nsDot(ctx, cell, tailEdge, portY, outSig, t);
  },

  output_pin: ({ ctx, t, cell, c, inSigs }) => {
    const x = c.x * cell, y = c.y * cell, w = c.width * cell, h = c.height * cell;
    const sig = inSigs[0] ?? 2;
    const on = sig === 1;
    const bus = (c.bitWidth ?? 1) > 1;
    const r = Math.min(w, h) / 2 - cell * 0.08;
    const tailEdge = x + w / 2 - r - cell * 0.4;
    const slot = c.inPorts[0];
    let dotY = 0;
    if (slot) {
      dotY = slot.coord.y * cell + cell / 2;
      nsTail(ctx, cell, tailEdge, slot.coord.x * cell + cell / 2, dotY, sig, t, bus);
    }
    nsPinCircle(ctx, cell, x, y, w, h, on, sig === 2,
      on ? t.outputOn : t.outputOff,
      on ? t.outputBorderOn : t.outputBorderOff,
      t, c.name);
    nsValuePill(
      ctx, t, cell, x + w / 2, y + h / 2 - r - cell * 0.5,
      bus ? nsHex(c.value) : sig === 2 ? '?' : on ? '1' : '0',
      bus || on ? 'solid' : sig === 2 ? 'dashed' : 'outline',
      bus ? t.wireBus : on ? t.outputOn : t.outputBorderOff,
      bus ? t.busLabel : on ? t.labelOnComponent : t.label
    );
    if (slot) nsDot(ctx, cell, tailEdge, dotY, sig, t);
  },

  led: ({ ctx, t, cell, c, inSigs }) => {
    const cx = (c.x + c.width / 2) * cell, cy = (c.y + c.height / 2) * cell;
    const r = Math.min(c.width, c.height) * cell * 0.4;
    const sig = inSigs[0] ?? 2;
    const on = sig === 1;
    const tailEdge = cx - r - cell * 0.4;
    const slot = c.inPorts[0];
    let dotY = 0;
    if (slot) {
      dotY = slot.coord.y * cell + cell / 2;
      nsTail(ctx, cell, tailEdge, slot.coord.x * cell + cell / 2, dotY, sig, t, false);
    }
    const lw = Math.max(2, cell * 0.16);
    if (on) {
      nsGlow(ctx, t.outputOn, cell * 1.3, () => {
        ctx.fillStyle = t.outputOn;
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, Math.PI * 2);
        ctx.fill();
      });
      ctx.strokeStyle = t.outputBorderOn;
      ctx.lineWidth = lw;
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.stroke();
      ctx.globalAlpha = 0.5;
      ctx.fillStyle = t.background;
      ctx.beginPath();
      ctx.arc(cx - r * 0.3, cy - r * 0.32, r * 0.24, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    } else {
      ctx.fillStyle = t.surface;
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = sig === 2 ? t.labelMuted : t.outputBorderOff;
      ctx.lineWidth = lw;
      if (sig === 2) ctx.setLineDash([cell * 0.28, cell * 0.24]);
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = t.outputOff;
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.3, 0, Math.PI * 2);
      ctx.fill();
    }
    nsName(ctx, cell, c.name, c.x * cell, c.y * cell, c.width * cell, c.height * cell, t.labelMuted);
    if (slot) nsDot(ctx, cell, tailEdge, dotY, sig, t);
  },

  // Every negated gate is base silhouette + the one standard bubble, so
  // NOT and NAND stop relying on the bubble baked into their own PNG —
  // that is what made the spacing differ from NOR and XNOR.
  // [exclusive][gate][negate] — three containers, every gate a combination.
  buffer:    (a) => nsGate(a.ctx, a.t, a.cell, a.c, a.inSigs, a.outSig, { vector: 'triangle' }),
  not_gate:  (a) => nsGate(a.ctx, a.t, a.cell, a.c, a.inSigs, a.outSig, { vector: 'triangle', negate: true }),
  and_gate:  (a) => nsGate(a.ctx, a.t, a.cell, a.c, a.inSigs, a.outSig, { sprite: 'AND', qualifier: '&' }),
  nand_gate: (a) => nsGate(a.ctx, a.t, a.cell, a.c, a.inSigs, a.outSig, { sprite: 'AND', negate: true, qualifier: '&' }),
  or_gate:   (a) => nsGate(a.ctx, a.t, a.cell, a.c, a.inSigs, a.outSig, { sprite: 'OR', qualifier: '\u22651', qx: 0.44, qy: 0.18 }),
  nor_gate:  (a) => nsGate(a.ctx, a.t, a.cell, a.c, a.inSigs, a.outSig, { sprite: 'OR', negate: true, qualifier: '\u22651', qx: 0.44, qy: 0.18 }),
  xor_gate:  (a) => nsGate(a.ctx, a.t, a.cell, a.c, a.inSigs, a.outSig, { sprite: 'OR', exclusive: true, qualifier: '=1', qx: 0.44, qy: 0.18 }),
  xnor_gate: (a) => nsGate(a.ctx, a.t, a.cell, a.c, a.inSigs, a.outSig, { sprite: 'OR', exclusive: true, negate: true, qualifier: '=1', qx: 0.44, qy: 0.18 }),

  slice: ({ ctx, t, cell, c, inSigs, outSig }) =>
    nsBitPart(ctx, t, cell, c, inSigs, outSig, nsSliceAsset),

  concat: ({ ctx, t, cell, c, inSigs, outSig }) =>
    nsBitPart(ctx, t, cell, c, inSigs, outSig, nsConcatAsset),

  subcircuit: (a) => {
    const kind = String(a.c.subcircuit ?? '').toLowerCase();
    // Builtin macros ARE gates: reuse the exact gate recipe so a macro
    // reads as the primitive it wraps, then label the instance below.
    const recipe = {
      and:  { sprite: 'AND', qualifier: '&' },
      nand: { sprite: 'AND', negate: true, qualifier: '&' },
      or:   { sprite: 'OR', qualifier: '\u22651', qx: 0.44, qy: 0.18 },
      nor:  { sprite: 'OR', negate: true, qualifier: '\u22651', qx: 0.44, qy: 0.18 },
      xor:  { sprite: 'OR', exclusive: true, qualifier: '=1', qx: 0.44, qy: 0.18 },
      xnor: { sprite: 'OR', exclusive: true, negate: true, qualifier: '=1', qx: 0.44, qy: 0.18 },
      not:  { vector: 'triangle', negate: true },
    }[kind];
    if (recipe) {
      // The macro box is wider than a primitive's (max(8, label+2) vs 5).
      // Lay the gate out on a virtual 5-wide box centred in the macro box
      // so the symbol, slots and bubble match the primitive exactly; the
      // tails simply run longer to reach the real ports.
      const c = a.c;
      const vx = c.x + (c.width - 5) / 2;
      const virt = { ...c, x: vx, width: 5 };
      return nsGate(a.ctx, a.t, a.cell, virt, a.inSigs, a.outSig, { ...recipe, portsFrom: c });
    }
    nsUserSubcircuit(a.ctx, a.t, a.cell, a.c, a.inSigs, a.outSig);
  },
};

/**
 * User subcircuit chip: macro-purple shell, tinted header band with the
 * subcircuit name, instance name in the body. Same inset/tail/dot rule
 * as the gates so it sits on the wire like a primitive.
 */
function nsUserSubcircuit(ctx, t, cell, c, inSigs, outSig) {
  const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
  const inset = NS_INSET * cell;
  const gap = cell * 0.4;
  const leftEdge = x0 + inset - gap, rightEdge = x0 + w - inset + gap;
  const inDotYs = [];
  for (let i = 0; i < c.inPorts.length; i++) {
    const slot = c.inPorts[i];
    const portY = slot.coord.y * cell + cell / 2;
    inDotYs.push(portY);
    nsTail(ctx, cell, leftEdge, slot.coord.x * cell + cell / 2, portY, inSigs[i] ?? 2, t, (c.inValues?.[i]?.width ?? 1) > 1);
  }
  const outDotY = c.outPort.y * cell + cell / 2;
  nsTail(ctx, cell, rightEdge, c.outPort.x * cell + cell / 2, outDotY, outSig, t, (c.bitWidth ?? 1) > 1);

  const bx = x0 + inset, bw = w - inset * 2, r = cell * 0.18;
  const head = cell * 1.0;
  ctx.fillStyle = t.surface;
  ctx.strokeStyle = t.macro;
  ctx.lineWidth = Math.max(1.75, cell * 0.1);
  ctx.beginPath();
  ctx.roundRect(bx, y0, bw, h, r);
  ctx.fill();
  ctx.stroke();
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(bx, y0, bw, h, r);
  ctx.clip();
  ctx.fillStyle = t.macro;
  ctx.globalAlpha = 0.18;
  ctx.fillRect(bx, y0, bw, head);
  ctx.globalAlpha = 1;
  ctx.restore();
  ctx.strokeStyle = t.macro;
  ctx.globalAlpha = 0.5;
  ctx.beginPath();
  ctx.moveTo(bx, y0 + head);
  ctx.lineTo(bx + bw, y0 + head);
  ctx.stroke();
  ctx.globalAlpha = 1;
  ctx.fillStyle = t.macro;
  ctx.font = nsFont(cell, 700);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(String(c.subcircuit ?? '').toUpperCase(), bx + bw / 2, y0 + head / 2 + cell * 0.02);
  ctx.fillStyle = t.label;
  ctx.font = nsFont(cell, 500);
  ctx.fillText(c.name ?? '', bx + bw / 2, y0 + head + (h - head) / 2);

  for (let i = 0; i < c.inPorts.length; i++) nsDot(ctx, cell, leftEdge, inDotYs[i], inSigs[i] ?? 2, t);
  nsDot(ctx, cell, rightEdge, outDotY, outSig, t);
}

/* ── memories: ROM and RAM ──────────────────────────────────────────
 * PR #79 (branch `memories`) adds rom[W,A](addr) and ram[W,A](addr,din,
 * we,clk), both drawn by --preview as a macro-colored labelled box. Here
 * they take the user-subcircuit chip — header band + body — and put the
 * *addressed word* in the body: "addr → word" for ROM, and for RAM the
 * same plus a write indicator that lights on the we·clk edge. Contents
 * are runtime configuration, so an unloaded cell reads "?" like any
 * undefined value. Footprints are the PR's.
 */
function nsMemory(ctx, t, cell, c, inSigs, outSig, mode) {
  const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
  const inset = NS_INSET * cell, gap = cell * 0.4;
  const leftEdge = x0 + inset - gap, rightEdge = x0 + w - inset + gap;
  const inDotYs = [];
  for (let i = 0; i < c.inPorts.length; i++) {
    const slot = c.inPorts[i];
    const py = slot.coord.y * cell + cell / 2;
    inDotYs.push(py);
    const busy = (c.inValues?.[i]?.width ?? 1) > 1;
    nsTail(ctx, cell, leftEdge, slot.coord.x * cell + cell / 2, py, inSigs[i] ?? 2, t, busy);
  }
  const outDotY = c.outPort.y * cell + cell / 2;
  nsTail(ctx, cell, rightEdge, c.outPort.x * cell + cell / 2, outDotY, outSig, t, (c.bitWidth ?? 1) > 1);

  const bx = x0 + inset, bw = w - inset * 2, r = cell * 0.18, head = cell;
  ctx.fillStyle = t.surface;
  ctx.strokeStyle = t.macro;
  ctx.lineWidth = Math.max(1.75, cell * 0.1);
  ctx.beginPath(); ctx.roundRect(bx, y0, bw, h, r); ctx.fill(); ctx.stroke();
  ctx.save();
  ctx.beginPath(); ctx.roundRect(bx, y0, bw, h, r); ctx.clip();
  ctx.fillStyle = t.macro; ctx.globalAlpha = 0.18; ctx.fillRect(bx, y0, bw, head); ctx.globalAlpha = 1;
  ctx.restore();
  ctx.strokeStyle = t.macro; ctx.globalAlpha = 0.5;
  ctx.beginPath(); ctx.moveTo(bx, y0 + head); ctx.lineTo(bx + bw, y0 + head); ctx.stroke();
  ctx.globalAlpha = 1;

  // Header: MODE left, W×2^A shape right — the declaration, not the instance.
  const W = c.dataWidth ?? 8, A = c.addrWidth ?? 4;
  ctx.font = nsFont(cell, 700); ctx.textBaseline = 'middle';
  ctx.fillStyle = t.macro; ctx.textAlign = 'left';
  ctx.fillText(mode.toUpperCase(), bx + cell * 0.45, y0 + head / 2 + cell * 0.02);
  ctx.font = nsFont(cell, 500); ctx.textAlign = 'right';
  ctx.fillText(`${W}\u00d7${1 << A}`, bx + bw - cell * 0.45, y0 + head / 2 + cell * 0.02);

  // Port labels inside the left edge, on each port row (RAM has four).
  if (c.inPorts.length > 1) {
    ctx.font = nsFont(cell, 500); ctx.textAlign = 'left'; ctx.fillStyle = t.labelMuted;
    for (let i = 0; i < c.inPorts.length; i++) ctx.fillText(c.inPorts[i].portName, bx + cell * 0.4, inDotYs[i]);
  }

  // Body: the addressed word. addr → word, in the bus colour when defined.
  const m = c.mem ?? {};
  const addrText = m.addr == null ? '?' : '0x' + m.addr.toString(16).toUpperCase().padStart(Math.ceil(A / 4), '0');
  const wordText = m.word == null ? '?' : '0x' + m.word.toString(16).toUpperCase().padStart(Math.ceil(W / 4), '0');
  const bodyY = y0 + head + (h - head) / 2;
  const nameY = c.inPorts.length > 1 ? bodyY + cell * 1.1 : null;
  const cx = bx + bw / 2 + (c.inPorts.length > 1 ? cell * 0.9 : 0);
  ctx.textAlign = 'center';
  ctx.font = nsFont(cell, 700);
  const seg = [
    { t: addrText, col: m.addr == null ? t.labelMuted : t.label },
    { t: ' \u2192 ', col: t.labelMuted },
    { t: wordText, col: m.word == null ? t.labelMuted : t.wireBus },
  ];
  const total = seg.reduce((a, s) => a + ctx.measureText(s.t).width, 0);
  let px = cx - total / 2;
  ctx.textAlign = 'left';
  for (const sg of seg) { ctx.fillStyle = sg.col; ctx.fillText(sg.t, px, nameY ? bodyY - cell * 0.5 : bodyY); px += ctx.measureText(sg.t).width; }
  // Instance name: RAM has room under the word; ROM puts it below the box.
  if (nameY) {
    ctx.textAlign = 'center'; ctx.fillStyle = t.label; ctx.font = nsFont(cell, 500);
    ctx.fillText(c.name ?? '', cx, nameY - cell * 0.5);
  } else {
    nsName(ctx, cell, c.name, x0, y0, w, h, t.labelMuted);
  }

  // RAM write indicator: a small pen-dot that lights orange on the we·clk edge.
  if (mode === 'ram') {
    const wr = !!m.writing;
    // Plain lit dot, labelled "wr" beside it so its meaning survives greyscale.
    const ir = cell * 0.2;
    const ix = bx + bw - cell * 0.55 - ir, iy = y0 + h - cell * 0.5;
    if (wr) nsVecHalo(ctx, 'wr', ix - ir, iy - ir, ir * 2, ir * 2, t.inputOn, cell * 0.6,
      (g) => { g.beginPath(); g.arc(ir, ir, ir, 0, Math.PI * 2); g.closePath(); });
    ctx.fillStyle = wr ? t.inputOn : t.surface;
    ctx.strokeStyle = wr ? t.inputOn : t.labelMuted;
    ctx.lineWidth = Math.max(1.5, cell * 0.1);
    ctx.beginPath(); ctx.arc(ix, iy, ir, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
    ctx.fillStyle = wr ? t.inputOn : t.labelMuted;
    ctx.font = nsFont(cell, 600); ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
    ctx.fillText('wr', ix - ir - cell * 0.3, iy + cell * 0.02);
  }

  for (let i = 0; i < c.inPorts.length; i++) nsDot(ctx, cell, leftEdge, inDotYs[i], inSigs[i] ?? 2, t);
  nsDot(ctx, cell, rightEdge, outDotY, outSig, t);
}

nextSiteSkins.rom = (a) => nsMemory(a.ctx, a.t, a.cell, a.c, a.inSigs, a.outSig, 'rom');
nextSiteSkins.ram = (a) => nsMemory(a.ctx, a.t, a.cell, a.c, a.inSigs, a.outSig, 'ram');

/* ── proposed gate set ─────────────────────────────────────────────
 * The library ships two gates; the site's sprite map adds three more as
 * builtin subcircuits (nand, or, xor). Missing outright: NOR, XNOR and
 * BUFFER. Rather than draw new art, the derived gates compose the way
 * ANSI itself derives them — the base sprite plus an inversion bubble.
 * Only BUFFER needs a vector, and it is the NOT triangle without its
 * bubble.
 */

/* ── gate anatomy: three containers ─────────────────────────────────
 *
 *   port [space] [ exclusive ][   gate   ][ negate ] [space] port
 *
 * Every gate is authored from the same three slots inside its box. The
 * slots are always reserved — an AND leaves exclusive and negate empty —
 * so the gate symbol is the same size and sits at the same x for the
 * whole family, and the box, ports and tails never move. Containers
 * never touch: each has its own inset.
 */
const NS_INSET = 0.4;   // box edge → first container, in cells
const NS_SLOT = 0.55;   // exclusive / negate container width, in cells
const NS_BUBBLE_R = 0.24;

function nsGateLayout(cell, c) {
  const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
  const cy = y0 + h / 2;
  const innerL = x0 + NS_INSET * cell, innerR = x0 + w - NS_INSET * cell;
  const slot = NS_SLOT * cell;
  const exclusive = { left: innerL, right: innerL + slot, top: y0, bottom: y0 + h };
  const negate = { left: innerR - slot, right: innerR, top: y0, bottom: y0 + h };
  const gate = { left: exclusive.right, right: negate.left, top: y0, bottom: y0 + h };
  // The symbol is sized to the box HEIGHT, not the gate slot, so its input
  // lobes land on the a/b port rows (y+1, y+3 in a 5-tall box). It stays
  // centred on the gate slot; the height of the two-input sprites equals
  // their width, so a 5-cell box gives a 5-cell symbol that the 0.7-cell
  // side slots overlap into. The slot assets are drawn on top and sit in
  // the sprite's concave/convex ends, which is exactly where ANSI puts them.
  // The symbol is sized by its PAINTED extent, not its PNG square: the art
  // must span the port rows (a at y+1, b at y+3 → 2 cells apart, plus one
  // half-cell lobe beyond each) so the inputs meet the lobes, and it must
  // fit the gate slot horizontally so the side assets stay clear of it.
  const gcx = (gate.left + gate.right) / 2;
  const rect = { left: gcx, right: gcx, size: 0, cx: gcx, cy, gateW: gate.right - gate.left, boxH: h };
  return { x0, y0, w, h, cy, innerL, innerR, exclusive, gate, negate, rect };
}

/** Finish the rect once the sprite (or vector) painted bounds are known. */
function nsFitSymbol(rect, bounds, cell, nInputs, availW) {
  const paintedH = bounds.b - bounds.t;
  // Size comes from the port spread ONLY — the painted lobes must span the
  // port rows plus one cell each side. It never depends on which side
  // slots are occupied, so AND and NAND, OR and NOR, XOR and XNOR share
  // one symbol size. Two-input gates: ports 2 cells apart → 4 cells tall.
  const targetH = Math.min(rect.boxH, (nInputs > 1 ? 2 * (nInputs - 1) + 2 : 2) * cell);
  // …and by the FIXED gate-slot width — the same number for every gate in
  // the family, occupied side slots or not. Whichever binds, wins, so the
  // symbol is identical across AND/NAND, OR/NOR, XOR/XNOR.
  const paintedW = bounds.r - bounds.l;
  const size = Math.min(targetH / paintedH, rect.gateW / paintedW);
  // Centre the PAINTED art on the gate slot, not the PNG square.
  const cxArt = (bounds.l + bounds.r) / 2, cyArt = (bounds.t + bounds.b) / 2;
  rect.size = size;
  rect.left = rect.cx - cxArt * size;
  rect.right = rect.left + size;
  rect.top = rect.cy - cyArt * size;
  rect.artL = rect.left + bounds.l * size;
  rect.artR = rect.left + bounds.r * size;
  rect.apexX = rect.left + (bounds.apex ?? bounds.l) * size;
  rect.depth = rect.apexX - rect.artL;
  return rect;
}

/**
 * Painted bounds of a sprite as fractions of its square, measured in the
 * rotation the stage draws it. The PNGs carry transparent padding, so
 * the art is smaller than the square — sizing must use these, not the
 * square, for the symbol to line up with anything.
 */
const boundsCache = new Map();
function spriteBounds(img, key) {
  const hit = boundsCache.get(key);
  if (hit) return hit;
  const N = 128;
  const c = document.createElement('canvas');
  c.width = N; c.height = N;
  const g = c.getContext('2d');
  g.translate(N / 2, N / 2);
  g.rotate(Math.PI / 2);
  g.drawImage(img, -N / 2, -N / 2, N, N);
  const d = g.getImageData(0, 0, N, N).data;
  let l = N, r = -1, tp = N, bt = -1;
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    if (d[(y * N + x) * 4 + 3] > 16) { if (x < l) l = x; if (x > r) r = x; if (y < tp) tp = y; if (y > bt) bt = y; }
  }
  // Back apex: how far in the concave input edge reaches on the centre row.
  let apex = l;
  const mid = Math.floor(N / 2);
  for (let x = 0; x < N; x++) if (d[(mid * N + x) * 4 + 3] > 16) { apex = x; break; }
  const b = r < 0 ? { l: 0.1, r: 0.9, t: 0.1, b: 0.9, apex: 0.1 }
    : { l: l / N, r: (r + 1) / N, t: tp / N, b: (bt + 1) / N, apex: apex / N };
  boundsCache.set(key, b);
  return b;
}

/** Rightmost opaque column of a sprite, as a fraction of its square (rotated as drawn). */
const extentCache = new Map();
function spriteRightExtent(img, key) {
  const hit = extentCache.get(key);
  if (hit !== undefined) return hit;
  const N = 96;
  const c = document.createElement('canvas');
  c.width = N; c.height = N;
  const g = c.getContext('2d');
  g.translate(N / 2, N / 2);
  g.rotate(Math.PI / 2);
  g.drawImage(img, -N / 2, -N / 2, N, N);
  const data = g.getImageData(0, 0, N, N).data;
  const mid = Math.floor(N / 2);
  let maxX = 0;
  for (let y = mid - 2; y <= mid + 2; y++) {
    for (let x = N - 1; x >= 0; x--) {
      if (data[(y * N + x) * 4 + 3] > 16) { if (x > maxX) maxX = x; break; }
    }
  }
  const frac = maxX > 0 ? (maxX + 1) / N : 0.9;
  extentCache.set(key, frac);
  return frac;
}

/** Negate container: one bubble, centred in its slot. Same for every negated gate. */
function nsNegate(ctx, cell, slot, cy, sig, t, symbolRight) {
  const r = Math.min(NS_BUBBLE_R * cell, (slot.right - slot.left) / 2 - cell * 0.03);
  // Tangent to where the symbol actually ends, clamped inside the slot.
  const bx = Math.min(slot.right - r, Math.max(slot.left + r, (symbolRight ?? slot.left) + cell * 0.14 + r));
  const ink = sig === 1 ? t.inputOn : sig === 2 ? t.labelMuted : t.spriteInk;
  if (sig === 1) {
    nsVecHalo(ctx, 'bubble', bx - r, cy - r, r * 2, r * 2, t.inputOn, cell * 0.55,
      (g) => { g.beginPath(); g.arc(r, r, r, 0, Math.PI * 2); g.closePath(); });
  }
  ctx.fillStyle = ink;
  ctx.globalAlpha = sig === 1 ? 0.92 : sig === 2 ? 0.5 : 0.94;
  ctx.beginPath();
  ctx.arc(bx, cy, r, 0, Math.PI * 2);
  ctx.fill();
  ctx.globalAlpha = 1;
}

/**
 * Exclusive container: the second back-curve that turns OR into XOR.
 * Drawn as the XOR sprite's own curve — the same concave arc the OR
 * silhouette has on its input side, echoed one slot to the left. It is
 * a stroked arc with round caps, sized to the gate symbol, and kept a
 * clear gap from the gate container so the two never touch.
 */
function nsExclusive(ctx, cell, slot, rect, sig, t) {
  const lw = Math.max(2, cell * 0.2);
  const gapToGate = cell * 0.14;
  const half = rect.size * 0.30;                 // matches the OR art's painted half-height
  const top = rect.cy - half, bot = rect.cy + half;
  // The OR back bows INTO the body; its apex sits about 0.2·size in from
  // the left edge. Mirror that depth here so the two curves are parallel.
  // Everything — caps included — must stay inside the slot.
  // The OR back's apex is ~0.2·size in from the sprite's left edge; the
  // sprite may overlap this slot, so measure from the sprite, not the slot.
  // Apex just left of the OR back's own apex (which is ~0.16·size in from
  // the painted left edge), by the gap plus the stroke's half width.
  const xTip = (rect.apexX ?? rect.left) - gapToGate - lw / 2;
  const xEnd = Math.max(slot.left + lw / 2, xTip - (rect.depth ?? rect.size * 0.16));  // curve ends (leftmost)
  const depth = xTip - xEnd;
  const path = (g, ox, oy) => {
    g.beginPath();
    g.moveTo(xEnd - ox, top - oy);
    g.quadraticCurveTo(xTip + depth - ox, rect.cy - oy, xEnd - ox, bot - oy);
  };
  const ink = sig === 1 ? t.inputOn : sig === 2 ? t.labelMuted : t.spriteInk;
  if (sig === 1) {
    nsVecHalo(ctx, 'excl', xEnd - lw, top - lw, depth + lw * 2 + depth * 0.3, bot - top + lw * 2, t.inputOn, cell * 0.6,
      (g) => { path(g, xEnd - lw, top - lw); g.lineWidth = lw; g.lineCap = 'round'; g.stroke(); g.beginPath(); });
  }
  ctx.save();
  ctx.strokeStyle = ink;
  ctx.globalAlpha = sig === 1 ? 0.92 : sig === 2 ? 0.5 : 0.94;
  ctx.lineWidth = lw;
  ctx.lineCap = 'round';
  path(ctx, 0, 0);
  ctx.stroke();
  ctx.restore();
}

/** Debug overlay: outline the three containers so the anatomy is visible. */
function nsAnatomy(ctx, cell, L, t) {
  ctx.save();
  ctx.setLineDash([cell * 0.18, cell * 0.14]);
  ctx.lineWidth = 1;
  const box = (r, col) => {
    ctx.strokeStyle = col;
    ctx.strokeRect(r.left + 0.5, r.top + 0.5, r.right - r.left - 1, r.bottom - r.top - 1);
  };
  box(L.exclusive, t.wireBus);
  box(L.gate, t.labelMuted);
  box(L.negate, t.inputOn);
  ctx.restore();
}

/** One body for every gate: tails, then the containers, then dots. */
function nsGate(ctx, t, cell, c, inSigs, outSig, opts) {
  const L = nsGateLayout(cell, c);
  const { x0, y0, w, h, cy, innerL, innerR, rect } = L;
  const img = opts.sprite ? sprites?.[opts.sprite] : null;
  const gap = cell * 0.4;
  const leftEdge = innerL - gap, rightEdge = innerR + gap;
  const ports = opts.portsFrom ?? c;
  const inDotYs = [];
  for (let i = 0; i < ports.inPorts.length; i++) {
    const slot = ports.inPorts[i];
    const portY = slot.coord.y * cell + cell / 2;
    inDotYs.push(portY);
    nsTail(ctx, cell, leftEdge, slot.coord.x * cell + cell / 2, portY, inSigs[i] ?? 2, t, false);
  }
  const outDotY = ports.outPort.y * cell + cell / 2;
  nsTail(ctx, cell, rightEdge, ports.outPort.x * cell + cell / 2, outDotY, outSig, t, false);

  // Triangle paints from 0.2 to 0.84 of its square horizontally, ±0.3 vertically.
  const bounds = img ? spriteBounds(img, opts.sprite) : { l: 0.2, r: 0.84, t: 0.2, b: 0.8 };
  // Unused side slots lend their width to the symbol; used ones keep it.
  // The exclusive curve nests INSIDE the OR's concave back, so it needs
  // only the part of its slot the back doesn't already vacate.
  // Curve stroke sits at the slot's left edge; the OR's painted left edge
  // may come no closer than its own back depth + gap + stroke from there.
  const spanL = opts.exclusive ? L.exclusive.left + cell * 0.36 : L.exclusive.left;
  const spanR = opts.negate ? L.gate.right - cell * 0.1 : L.negate.right;
  rect.cx = (spanL + spanR) / 2;
  nsFitSymbol(rect, bounds, cell, c.inPorts.length);
  if (c.anatomy) nsAnatomy(ctx, cell, L, t);
  if (opts.exclusive) nsExclusive(ctx, cell, L.exclusive, rect, outSig, t);
  if (img) nsSpriteRect(ctx, img, rect, outSig, t, cell);
  else if (opts.vector === 'triangle') nsTriangle(ctx, t, cell, rect, outSig);
  if (opts.negate) nsNegate(ctx, cell, L.negate, cy, outSig, t, rect.artR);

  if (opts.qualifier) {
    ctx.fillStyle = t.labelOnComponent;
    ctx.font = nsFont(cell, 700);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(
      opts.qualifier,
      rect.left + rect.size * (opts.qx ?? 0.31),
      rect.cy - rect.size * (opts.qy ?? 0.21)
    );
  }
  for (let i = 0; i < ports.inPorts.length; i++) nsDot(ctx, cell, leftEdge, inDotYs[i], inSigs[i] ?? 2, t);
  nsDot(ctx, cell, rightEdge, outDotY, outSig, t);
  nsName(ctx, cell, c.name, x0, y0, w, h, t.labelMuted);
}

/** BUFFER: the NOT sprite's triangle, minus the bubble. */
function nsTriangle(ctx, t, cell, rect, sig) {
  const ink = sig === 1 ? t.inputOn : sig === 2 ? t.labelMuted : t.spriteInk;
  const x0 = rect.left + rect.size * 0.2, x1 = rect.left + rect.size * 0.84;
  const y0 = rect.cy - rect.size * 0.3, y1 = rect.cy + rect.size * 0.3;
  const tri = (g, ox, oy) => {
    g.beginPath();
    g.moveTo(x0 - ox, y0 - oy);
    g.lineTo(x1 - ox, rect.cy - oy);
    g.lineTo(x0 - ox, y1 - oy);
    g.closePath();
  };
  if (sig === 1) {
    nsVecHalo(ctx, 'tri', x0, y0, x1 - x0, y1 - y0, t.inputOn, cell * 0.7,
      (g) => tri(g, x0, y0));
  }
  ctx.fillStyle = ink;
  ctx.globalAlpha = sig === 1 ? 0.92 : sig === 2 ? 0.5 : 0.94;
  tri(ctx, 0, 0);
  ctx.fill();
  ctx.globalAlpha = 1;
}

/** Tails, dots and bus leads around a bit-field asset. */
function nsBitPart(ctx, t, cell, c, inSigs, outSig, body) {
  const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
  const inset = cell * 0.35;
  const gap = cell * 0.4;
  const leftEdge = x0 + inset - gap;
  const rightEdge = x0 + w - inset + gap;
  const inDotYs = [];
  for (let i = 0; i < c.inPorts.length; i++) {
    const slot = c.inPorts[i];
    const portY = slot.coord.y * cell + cell / 2;
    inDotYs.push(portY);
    nsTail(ctx, cell, leftEdge, slot.coord.x * cell + cell / 2, portY, inSigs[i] ?? 2, t, true);
  }
  const outDotY = c.outPort.y * cell + cell / 2;
  nsTail(ctx, cell, rightEdge, c.outPort.x * cell + cell / 2, outDotY, outSig, t, (c.bitWidth ?? 1) > 1);
  body(ctx, t, cell, c, inSigs, outSig);
  for (let i = 0; i < c.inPorts.length; i++) nsDot(ctx, cell, leftEdge, inDotYs[i], inSigs[i] ?? 2, t);
  nsDot(ctx, cell, rightEdge, outDotY, outSig, t);
}

/** Wire renderer: cell-relative weight, rounded corners, a real bus branch. */
export function drawWireNextSite(ctx, t, cell, wire, signal, value) {
  const isBus = (value?.width ?? 1) > 1 && signal !== 2;
  ctx.strokeStyle = isBus
    ? t.wireBus
    : signal === 1 ? t.wireActive : signal === 0 ? t.wireIdle : t.wireUndefined;
  ctx.lineWidth = nsWire(cell) * (isBus ? 1.5 : 1);
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  const arcRadius = cell * 0.4;
  const run = () => {
    if (!wire.segments.length) return;
    // One continuous path for the whole wire: corners round via arcTo,
    // and crossing hops are spliced into the horizontal runs as we go,
    // so a wire with a crossing keeps the same corners as one without.
    const P = (p) => ({ x: p.x * cell + cell / 2, y: p.y * cell + cell / 2 });
    const pts = [P(wire.segments[0].from)];
    for (const seg of wire.segments) pts.push(P(seg.to));
    const hops = (wire.crossings ?? []).map(P);
    const cornerR = cell * 0.6;
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 0; i < pts.length - 1; i++) {
      const a = pts[i], b = pts[i + 1];
      const horiz = a.y === b.y;
      // Stop short of the corner so arcTo can round it.
      const hasNext = i < pts.length - 2;
      if (horiz) {
        const dir = Math.sign(b.x - a.x) || 1;
        const lo = Math.min(a.x, b.x), hi = Math.max(a.x, b.x);
        const row = hops
          .filter((h) => h.y === a.y && h.x > lo && h.x < hi)
          .sort((p, q) => dir > 0 ? p.x - q.x : q.x - p.x);
        for (const h of row) {
          ctx.lineTo(h.x - dir * arcRadius, a.y);
          ctx.arc(h.x, a.y, arcRadius, Math.PI, 0, dir < 0);
        }
      }
      if (hasNext) {
        const c = pts[i + 2];
        ctx.arcTo(b.x, b.y, c.x, c.y, cornerR);
      } else {
        ctx.lineTo(b.x, b.y);
      }
    }
    ctx.stroke();
  };
  if (signal === 1 && !isBus) nsGlow(ctx, t.wireActive, cell * 0.5, run);
  else run();
  if (isBus) nsBusTick(ctx, t, cell, wire, value);
}

/** Bit-count slash, the standard bus notation the site theme lacks. */
function nsBusTick(ctx, t, cell, wire, value) {
  const seg = wire.segments.find((s) => s.from.y === s.to.y && Math.abs(s.to.x - s.from.x) >= 2);
  if (!seg) return;
  const mx = ((seg.from.x + seg.to.x) / 2) * cell + cell / 2;
  const my = seg.from.y * cell + cell / 2;
  ctx.save();
  ctx.strokeStyle = t.wireBus;
  ctx.lineWidth = Math.max(1.5, cell * 0.1);
  ctx.beginPath();
  ctx.moveTo(mx - cell * 0.26, my + cell * 0.36);
  ctx.lineTo(mx + cell * 0.26, my - cell * 0.36);
  ctx.stroke();
  ctx.fillStyle = t.wireBus;
  ctx.font = nsFont(cell, 700);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'bottom';
  ctx.fillText(String(value.width), mx + cell * 0.55, my - cell * 0.32);
  ctx.restore();
}
