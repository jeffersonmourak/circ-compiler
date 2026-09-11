// The site's skins: every drawing function the canvas calls, and the theme
// pieces (`skins`, `wire`, `background`, `portMarker`, `highlight`, `font`)
// that hand them to circ-renderer. No colours here — they come in on
// `theme.colors` from `circ-palette.mjs` — and nothing runs at import: the
// sprites and any offscreen canvas are reached through the `Assets` object
// `makeSkins` is given, so `bun test` can drive every skin with a stub and a
// recording context, which the old one-file theme could not (it decoded PNGs
// at module scope, and `new Image()` does not exist under bun).
//
// The functions are the ones the one-file theme had, moved. The only edit is
// that a sprite is looked up through `sprite(name)` instead of a module
// variable the loader assigned.

import { ComponentKind, memoryLabel, traceWire, wireColorKey, wireStyleOf } from 'circ-renderer';

/**
 * What the skins need from the page: the decoded sprites (null until they
 * are), their painted bounds, and a place to render offscreen.
 *
 * `bounds` is the page's because measuring needs `getImageData`, which a
 * test's recording context cannot answer; tinting and halos need only a
 * canvas to draw into, so they are built here from `offscreen`.
 * @typedef {{ l: number, r: number, t: number, b: number, apex: number }} Bounds
 * @typedef {{
 *   sprite(name: string): CanvasImageSource | null,
 *   bounds(name: string): Bounds | null,
 *   offscreen(width: number, height: number): HTMLCanvasElement,
 * }} Assets
 */

/** @type {Assets | null} */
let assets = null;

/** The decoded sprite of that name, or null before the site's PNGs resolve. */
const sprite = (name) => assets?.sprite(name) ?? null;

/**
 * Bind the page's assets and return the theme pieces. Called once by
 * `circ-theme.mjs`; a test calls it with a stub. The pieces are the same
 * objects on every call — binding is the only state, and every cache keyed
 * on a sprite name empties with it, since the names now mean other bytes.
 * @param {Assets} a
 */
export function makeSkins(a) {
  assets = a;
  tintCache.clear();
  haloCache.clear();
  boundsCache.clear();
  vecHaloCache.clear();
  return sharedRenderers;
}

/* ───── sprite art: tint, halo, bounds ─────────────────────────────── */

/**
 * The gate PNGs are dark-interior art drawn the same in both palettes. They
 * are never drawn raw now: a sprite is tinted inside its own alpha to the
 * palette's ink (LOW), the HIGH orange, or the muted label colour
 * (undefined), and a HIGH sprite gets a blurred copy of itself underneath.
 * Every one of those is rendered once per (sprite, colour) into an offscreen
 * canvas and kept, so a frame is one `drawImage` per gate; `shadowBlur` runs
 * only when a halo is first built.
 *
 * Caches key on the sprite NAME the site passes, never on `img.src`.
 */
const HALO_PAD = 0.14;
const tintCache = new Map();
const haloCache = new Map();
const boundsCache = new Map();
const vecHaloCache = new Map();

/** Recolour a sprite by compositing a flat fill inside its own alpha. */
function tintedSprite(name, colour, alpha) {
  const key = `${name}|${colour}|${alpha}`;
  const hit = tintCache.get(key);
  if (hit) return hit;
  const img = sprite(name);
  if (!img) return null;
  const c = assets.offscreen(img.width, img.height);
  const g = c.getContext('2d');
  g.drawImage(img, 0, 0);
  g.globalCompositeOperation = 'source-atop';
  g.globalAlpha = alpha;
  g.fillStyle = colour;
  g.fillRect(0, 0, c.width, c.height);
  tintCache.set(key, c);
  return c;
}

/**
 * Halo for sprite art: the tinted sprite blurred ONCE at build time on an
 * oversized canvas, its crisp core knocked out so only the soft field around
 * the silhouette remains. Padded by `HALO_PAD` of the sprite on every side;
 * `nsSpriteRect` maps it back with the same ratio.
 */
function haloSprite(name, colour) {
  const key = `${name}|${colour}`;
  const hit = haloCache.get(key);
  if (hit) return hit;
  const img = sprite(name);
  const art = tintedSprite(name, colour, 1);
  if (!img || !art) return null;
  const pad = Math.round(img.width * HALO_PAD);
  const c = assets.offscreen(img.width + pad * 2, img.height + pad * 2);
  const g = c.getContext('2d');
  g.shadowColor = colour;
  g.shadowBlur = pad * 0.8;
  g.drawImage(art, pad, pad);
  g.drawImage(art, pad, pad);
  g.shadowBlur = 0;
  g.globalCompositeOperation = 'destination-out';
  const shrink = Math.max(1, Math.round(img.width * 0.012));
  g.drawImage(art, pad + shrink, pad + shrink, img.width - shrink * 2, img.height - shrink * 2);
  haloCache.set(key, c);
  return c;
}

/**
 * Painted bounds of a sprite as fractions of its square, in the rotation
 * the canvas draws it. The PNGs carry transparent padding, so the art is
 * smaller than the square; sizing must use these, not the square, for the
 * lobes to land on the port rows. Measured by the page once per name.
 */
const TRIANGLE_BOUNDS = { l: 0.2, r: 0.84, t: 0.2, b: 0.8, apex: 0.2 };
function spriteBounds(name) {
  const hit = boundsCache.get(name);
  if (hit) return hit;
  const b = assets?.bounds(name) ?? null;
  if (b) boundsCache.set(name, b);
  return b ?? TRIANGLE_BOUNDS;
}

/**
 * The sprite art producers, exported for the test that counts their cache
 * hits; the skins reach them by name.
 */
export const spriteArt = { tinted: tintedSprite, halo: haloSprite, bounds: spriteBounds };

/**
 * Halo for a vector shape: the same recipe as the sprite halo, per shape, on
 * a small offscreen canvas — blur the shape once, knock its core out, keep
 * the soft field — cached by shape signature so a frame is one `drawImage`.
 * `pathFn(g)` traces the shape into `g` in the box's local coordinates.
 */
function nsVecHalo(ctx, key, x, y, w, h, colour, spread, pathFn) {
  const dpr = 2;
  const cacheKey = `${key}|${Math.round(w)}x${Math.round(h)}|${colour}|${Math.round(spread)}`;
  let c = vecHaloCache.get(cacheKey);
  if (!c) {
    c = assets.offscreen(Math.ceil((w + spread * 2) * dpr), Math.ceil((h + spread * 2) * dpr));
    const g = c.getContext('2d');
    g.scale(dpr, dpr);
    g.translate(spread, spread);
    g.shadowColor = colour;
    g.shadowBlur = spread * 0.9;
    g.fillStyle = colour;
    g.strokeStyle = colour;
    pathFn(g);
    g.fill();
    pathFn(g);
    g.fill();
    g.shadowBlur = 0;
    g.globalCompositeOperation = 'destination-out';
    g.save();
    g.translate(w / 2, h / 2);
    g.scale(1 - 1.2 / Math.max(w, h), 1 - 1.2 / Math.max(w, h));
    g.translate(-w / 2, -h / 2);
    pathFn(g);
    g.fill();
    g.restore();
    vecHaloCache.set(cacheKey, c);
  }
  ctx.save();
  ctx.globalAlpha = 0.55;
  ctx.drawImage(c, x - spread, y - spread, w + spread * 2, h + spread * 2);
  ctx.restore();
}

/* ───── helpers ────────────────────────────────────────────────────── */

/** Font for a label: `w` weight, sized by the cell, never under 9px. */
const nsFont = (cell, w = 600) =>
  `${w} ${Math.max(9, Math.round(cell * 0.6))}px ui-monospace, "JetBrains Mono", monospace`;

/** Stroke weight of a wire, in proportion to the cell: 4px at cell 20. */
const nsWire = (cell) => Math.max(2, cell * 0.2);

/** The palette colour for what a wire carries: a bus, or one tri-state bit. */
const wireColour = (t, sig, bus) =>
  bus ? t.wireBus : sig === 1 ? t.wireActive : sig === 0 ? t.wireIdle : t.wireUndefined;

/**
 * Stroke a horizontal "tail" between the part's visual edge and the wire's
 * endpoint cell-centre, in the wire's own colour and weight (a bus is 1.5×).
 * Drawn BEFORE the symbol so the symbol covers the tail's inner end cleanly.
 */
function nsTail(ctx, cell, from, to, y, sig, t, bus) {
  ctx.strokeStyle = wireColour(t, sig, bus);
  ctx.lineWidth = nsWire(cell) * (bus ? 1.5 : 1);
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(from, y);
  ctx.lineTo(to, y);
  ctx.stroke();
}

/**
 * Stamp the terminal dot at the tail's inner end. Drawn AFTER the symbol so
 * the dot always sits on top of it.
 */
function nsDot(ctx, cell, x, y, sig, t) {
  ctx.fillStyle = sig === 1 ? t.portOn : t.portOff;
  ctx.beginPath();
  ctx.arc(x, y, cell * 0.24, 0, Math.PI * 2);
  ctx.fill();
}

/** The part's name, just below its box. */
function nsName(ctx, cell, name, bx, by, bw, bh, color) {
  if (!name) return;
  ctx.fillStyle = color;
  ctx.font = nsFont(cell, 500);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  ctx.fillText(name, bx + bw / 2, by + bh + cell * 0.16);
}

/**
 * A soft halo under a lit shape: the same disc, one spread wider, at low
 * alpha. Drawn as one explicit fill inside save/restore, so the op log sees
 * every context change put back.
 */
function nsHalo(ctx, colour, cx, cy, r, spread) {
  ctx.save();
  ctx.globalAlpha = 0.22;
  ctx.fillStyle = colour;
  ctx.beginPath();
  ctx.arc(cx, cy, r + spread / 2, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

/**
 * Pin circle where SHAPE carries the state as well as colour: HIGH is a
 * solid disc under a halo, LOW is a hollow ring, undefined is dashed. The
 * name owns the centre, so greyscale docs and colourblind readers still get
 * the state from the silhouette. Returns the geometry for the ring and pill.
 */
function nsPinCircle(ctx, cell, bx, by, bw, bh, on, undef_, fill, border, t, label) {
  const cx = bx + bw / 2;
  const cy = by + bh / 2;
  const r = Math.min(bw, bh) / 2 - cell * 0.08;
  const lw = Math.max(2, cell * 0.14);
  if (undef_) {
    ctx.save();
    ctx.setLineDash([cell * 0.28, cell * 0.24]);
    ctx.strokeStyle = t.labelMuted;
    ctx.lineWidth = lw;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.restore();
  } else if (on) {
    nsHalo(ctx, fill, cx, cy, r, cell * 0.7);
    ctx.fillStyle = fill;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fill();
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
 * Value chip above a pin or a box. Solid when HIGH or carrying a bus,
 * outlined when LOW, dashed when undefined — the same fill-versus-outline
 * cue the circle uses, so the pair reads as one unit. `bottomY` is the
 * lowest the chip may reach; callers pass the outer edge of whatever sits
 * below it (a circle's stroke, a hover ring), so the chip never lands on
 * it. It reaches 1.34 cells above a 3-row pin box: the islands lay out
 * with a row gutter of 2 for it.
 */
function nsValuePill(ctx, t, cell, cx, bottomY, text, mode, fill, ink) {
  ctx.save();
  ctx.font = nsFont(cell, 700);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
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

/** The radius of a pin's circle in its box, as `nsPinCircle` draws it. */
const pinRadius = (cell, w, h) => Math.min(w, h) / 2 - cell * 0.08;

/**
 * The mark on a hovered or host-highlighted component, drawn by the canvas
 * after every skin — the pointer and an editor cursor come through the same
 * hook. A pin gets a circle outside its own, so the state it shows stays
 * visible under the mark; every other kind gets a ring around its box.
 *
 * A ring rather than a fill: every skin already uses fill and stroke to say
 * what the component IS and what it is DOING, and a highlight must not
 * overwrite either.
 */
function nsHoverRing(ctx, cell, cx, cy, r, t) {
  ctx.strokeStyle = t.inputHover;
  ctx.lineWidth = Math.max(2, cell * 0.13);
  ctx.beginPath();
  ctx.arc(cx, cy, r + cell * 0.38, 0, Math.PI * 2);
  ctx.stroke();
}

const drawHighlight = ({ ctx, cell, component, theme }) => {
  const t = theme.colors;
  const kind = component.kind.tag === 'primitive' ? component.kind.kind : null;
  const w = component.width * cell;
  const h = component.height * cell;
  ctx.save();
  if (kind === ComponentKind.InputPin || kind === ComponentKind.OutputPin) {
    nsHoverRing(ctx, cell, component.x * cell + w / 2, component.y * cell + h / 2, pinRadius(cell, w, h), t);
  } else {
    const pad = cell * 0.18;
    const x = component.x * cell - pad;
    const y = component.y * cell - pad;
    const r = Math.min(cell * 0.4, (w + pad * 2) / 2, (h + pad * 2) / 2);
    ctx.strokeStyle = t.inputHover;
    ctx.lineWidth = Math.max(1, cell * 0.09);
    ctx.beginPath();
    if (typeof ctx.roundRect === 'function') ctx.roundRect(x, y, w + pad * 2, h + pad * 2, r);
    else ctx.rect(x, y, w + pad * 2, h + pad * 2);
    ctx.stroke();
  }
  ctx.restore();
};

/* ───── gate anatomy: three containers ─────────────────────────────
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
  // The symbol is sized by its PAINTED extent, not its PNG square: the art
  // must span the port rows (a at y+1, b at y+3 → 2 cells apart, plus one
  // half-cell lobe beyond each) so the inputs meet the lobes, and it must
  // fit the gate slot horizontally so the side assets stay clear of it.
  const gcx = (gate.left + gate.right) / 2;
  const rect = {
    left: gcx, right: gcx, top: cy, size: 0, cx: gcx, cy,
    gateW: gate.right - gate.left, boxH: h,
    // Filled by nsFitSymbol once the painted bounds are known.
    artL: gcx, artR: gcx, apexX: gcx, depth: 0,
  };
  return { x0, y0, w, h, cy, innerL, innerR, exclusive, gate, negate, rect };
}

/** Finish the rect once the sprite (or vector) painted bounds are known. */
function nsFitSymbol(rect, bounds, cell, nInputs) {
  const paintedH = bounds.b - bounds.t;
  // Size comes from the port spread ONLY — the painted lobes must span the
  // port rows plus one cell each side. It never depends on which side
  // slots are occupied, so AND and NAND, OR and NOR, XOR and XNOR share
  // one symbol size. Two-input gates: ports 2 cells apart → 4 cells tall.
  const targetH = Math.min(rect.boxH, (nInputs > 1 ? 2 * (nInputs - 1) + 2 : 2) * cell);
  // …and by the FIXED gate-slot width — the same number for every gate in
  // the family, occupied side slots or not. Whichever binds, wins.
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
 * The geometry a gate is drawn on: the three containers and the fitted
 * symbol rect, for the given bounds and recipe. Exported for the tests
 * that check the anatomy without drawing; `nsGate` computes the same.
 */
export function gateGeometry(cell, c, bounds, opts, nInputs = c.inPorts.length) {
  const L = nsGateLayout(cell, c);
  // Unused side slots lend their width to the symbol; used ones keep it.
  // The exclusive curve nests INSIDE the OR's concave back, so it needs
  // only the part of its slot the back does not already vacate.
  const spanL = opts.exclusive ? L.exclusive.left + cell * 0.36 : L.exclusive.left;
  const spanR = opts.negate ? L.gate.right - cell * 0.1 : L.negate.right;
  L.rect.cx = (spanL + spanR) / 2;
  nsFitSymbol(L.rect, bounds, cell, nInputs);
  return L;
}

/** The ink a symbol takes for a signal, and its alpha. */
const symbolInk = (t, sig) => (sig === 1 ? t.inputOn : sig === 2 ? t.labelMuted : t.spriteInk);
const symbolAlpha = (sig) => (sig === 1 ? 0.92 : sig === 2 ? 0.5 : 0.94);

/**
 * Sprite that answers to signal: tinted to ink, warmed and haloed when
 * HIGH. The PNGs point up; the canvas turns them a quarter clockwise to
 * match the layout's left-to-right flow — `bounds` are measured in that
 * rotation.
 */
function nsSpriteRect(ctx, name, rect, sig, t) {
  const art = tintedSprite(name, symbolInk(t, sig), symbolAlpha(sig));
  if (!art) return;
  ctx.save();
  ctx.translate(rect.left + rect.size / 2, rect.top + rect.size / 2);
  ctx.rotate(Math.PI / 2);
  if (sig === 1) {
    const halo = haloSprite(name, t.inputOn);
    if (halo) {
      const hs = rect.size * (1 + HALO_PAD * 2);
      ctx.globalAlpha = 0.55;
      ctx.drawImage(halo, -hs / 2, -hs / 2, hs, hs);
      ctx.globalAlpha = 1;
    }
  }
  ctx.drawImage(art, -rect.size / 2, -rect.size / 2, rect.size, rect.size);
  ctx.restore();
}

/** Negate container: one bubble, tangent to where the symbol actually ends, clamped inside its slot. */
function nsNegate(ctx, cell, slot, cy, sig, t, symbolRight) {
  const r = Math.min(NS_BUBBLE_R * cell, (slot.right - slot.left) / 2 - cell * 0.03);
  const bx = Math.min(slot.right - r, Math.max(slot.left + r, (symbolRight ?? slot.left) + cell * 0.14 + r));
  if (sig === 1) {
    nsVecHalo(ctx, 'bubble', bx - r, cy - r, r * 2, r * 2, t.inputOn, cell * 0.55,
      (g) => { g.beginPath(); g.arc(r, r, r, 0, Math.PI * 2); g.closePath(); });
  }
  ctx.save();
  ctx.fillStyle = symbolInk(t, sig);
  ctx.globalAlpha = symbolAlpha(sig);
  ctx.beginPath();
  ctx.arc(bx, cy, r, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

/**
 * Exclusive container: the second back-curve that turns OR into XOR — the
 * same concave arc the OR silhouette has on its input side, echoed one
 * slot to the left, a stroked curve with round caps sized to the symbol
 * and kept a clear gap from it. Its apex sits just left of the OR back's
 * own apex, by the gap plus the stroke's half width, so the two curves
 * are parallel.
 */
function nsExclusive(ctx, cell, slot, rect, sig, t) {
  const lw = Math.max(2, cell * 0.2);
  const gapToGate = cell * 0.14;
  const half = rect.size * 0.30;
  const top = rect.cy - half, bot = rect.cy + half;
  const xTip = (rect.apexX ?? rect.left) - gapToGate - lw / 2;
  const xEnd = Math.max(slot.left + lw / 2, xTip - (rect.depth ?? rect.size * 0.16));
  const depth = xTip - xEnd;
  const path = (g, ox, oy) => {
    g.beginPath();
    g.moveTo(xEnd - ox, top - oy);
    g.quadraticCurveTo(xTip + depth - ox, rect.cy - oy, xEnd - ox, bot - oy);
  };
  if (sig === 1) {
    nsVecHalo(ctx, 'excl', xEnd - lw, top - lw, depth + lw * 2 + depth * 0.3, bot - top + lw * 2, t.inputOn, cell * 0.6,
      (g) => { path(g, xEnd - lw, top - lw); g.lineWidth = lw; g.lineCap = 'round'; g.stroke(); g.beginPath(); });
  }
  ctx.save();
  ctx.strokeStyle = symbolInk(t, sig);
  ctx.globalAlpha = symbolAlpha(sig);
  ctx.lineWidth = lw;
  ctx.lineCap = 'round';
  path(ctx, 0, 0);
  ctx.stroke();
  ctx.restore();
}

/** NOT's triangle: the one symbol that is a vector, since a bubble cannot be subtracted from a PNG. */
function nsTriangle(ctx, t, cell, rect, sig) {
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
    nsVecHalo(ctx, 'tri', x0, y0, x1 - x0, y1 - y0, t.inputOn, cell * 0.7, (g) => tri(g, x0, y0));
  }
  ctx.save();
  ctx.fillStyle = symbolInk(t, sig);
  ctx.globalAlpha = symbolAlpha(sig);
  tri(ctx, 0, 0);
  ctx.fill();
  ctx.restore();
}

/**
 * Vector stand-ins for the two sprites, drawn inside the triangle's painted
 * bounds so the layout does not move, for the moment before the PNGs
 * decode. The sprite-ready retheme replaces them.
 */
function nsVectorGate(ctx, t, cell, rect, sig, shape) {
  const l = rect.left + rect.size * 0.2, r = rect.left + rect.size * 0.84;
  const top = rect.cy - rect.size * 0.3, bot = rect.cy + rect.size * 0.3;
  const mid = (l + r) / 2;
  ctx.save();
  ctx.fillStyle = symbolInk(t, sig);
  ctx.globalAlpha = symbolAlpha(sig);
  ctx.beginPath();
  if (shape === 'OR') {
    ctx.moveTo(l, top);
    ctx.quadraticCurveTo(mid, top, r, rect.cy);
    ctx.quadraticCurveTo(mid, bot, l, bot);
    ctx.quadraticCurveTo(l + rect.size * 0.16, rect.cy, l, top);
  } else {
    ctx.moveTo(l, top);
    ctx.lineTo(mid, top);
    ctx.bezierCurveTo(r, top, r, bot, mid, bot);
    ctx.lineTo(l, bot);
  }
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}

/* ───── skins ──────────────────────────────────────────────────────── */

const drawInputPin = ({ ctx, cell, component, outputSignal, theme }) => {
  const t = theme.colors;
  const x = component.x * cell;
  const y = component.y * cell;
  const w = component.width * cell;
  const h = component.height * cell;
  const on = outputSignal === 1;
  const undef_ = outputSignal === 2;
  const bus = (component.bitWidth ?? 1) > 1;

  const r = pinRadius(cell, w, h);
  const cx = x + w / 2;
  const cy = y + h / 2;
  const tailEdge = cx + r + cell * 0.4;
  const portY = component.outPort.y * cell + cell / 2;
  nsTail(ctx, cell, tailEdge, component.outPort.x * cell + cell / 2, portY, outputSignal, t, bus);

  // The value rides in a chip above and the name sits in the circle, the
  // same arrangement at one bit or sixty-four. A bus's chip is the canvas's
  // to draw, through the busValue hook, in the reader's chosen base.
  if (!bus) {
    nsValuePill(
      ctx, t, cell, cx, cy - r - cell * 0.5,
      undef_ ? '?' : on ? '1' : '0',
      on ? 'solid' : undef_ ? 'dashed' : 'outline',
      on ? t.inputOn : t.inputBorderOff,
      on ? t.labelOnComponent : t.label
    );
  }
  // Hover is the canvas's ring, drawn after this through the highlight hook;
  // the fill stays what the state says, so the value about to be toggled is
  // never hidden under the mark.
  nsPinCircle(
    ctx, cell, x, y, w, h, on, undef_,
    on ? t.inputOn : t.inputOff,
    on ? t.inputBorderOn : t.inputBorderOff,
    t, component.name
  );
  nsDot(ctx, cell, tailEdge, portY, outputSignal, t);
};

const drawOutputPin = ({ ctx, cell, component, inputSignals, inputValues, theme }) => {
  const t = theme.colors;
  const x = component.x * cell;
  const y = component.y * cell;
  const w = component.width * cell;
  const h = component.height * cell;
  const sig = inputSignals[0] ?? 2;
  const on = sig === 1;
  const undef_ = sig === 2;
  const bus = (component.bitWidth ?? 1) > 1;

  const r = pinRadius(cell, w, h);
  const cx = x + w / 2;
  const cy = y + h / 2;
  const tailEdge = cx - r - cell * 0.4;
  const slot = component.inPorts[0];
  let dotY = 0;
  if (slot) {
    dotY = slot.coord.y * cell + cell / 2;
    nsTail(ctx, cell, tailEdge, slot.coord.x * cell + cell / 2, dotY, sig, t, (inputValues[0]?.width ?? 1) > 1);
  }
  nsPinCircle(
    ctx, cell, x, y, w, h, on, undef_,
    on ? t.outputOn : t.outputOff,
    on ? t.outputBorderOn : t.outputBorderOff,
    t, component.name
  );
  if (!bus) {
    nsValuePill(
      ctx, t, cell, cx, cy - r - cell * 0.5,
      undef_ ? '?' : on ? '1' : '0',
      on ? 'solid' : undef_ ? 'dashed' : 'outline',
      on ? t.outputOn : t.outputBorderOff,
      on ? t.labelOnComponent : t.label
    );
  }
  if (slot) nsDot(ctx, cell, tailEdge, dotY, sig, t);
};

const drawLed = ({ ctx, cell, component, inputSignals, inputValues, theme }) => {
  const t = theme.colors;
  const cx = (component.x + component.width / 2) * cell;
  const cy = (component.y + component.height / 2) * cell;
  const r = Math.min(component.width, component.height) * cell * 0.4;
  const sig = inputSignals[0] ?? 2;
  const on = sig === 1;

  const tailEdge = cx - r - cell * 0.4;
  const slot = component.inPorts[0];
  let dotY = 0;
  if (slot) {
    dotY = slot.coord.y * cell + cell / 2;
    nsTail(ctx, cell, tailEdge, slot.coord.x * cell + cell / 2, dotY, sig, t, (inputValues[0]?.width ?? 1) > 1);
  }

  const lw = Math.max(2, cell * 0.16);
  if (on) {
    // Lit: a halo under a solid disc, and a glint of the pane's colour high
    // on the left, so the LED reads as a light and not a filled dot.
    nsHalo(ctx, t.outputOn, cx, cy, r, cell * 1.3);
    ctx.fillStyle = t.outputOn;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = t.outputBorderOn;
    ctx.lineWidth = lw;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.save();
    ctx.globalAlpha = 0.5;
    ctx.fillStyle = t.background;
    ctx.beginPath();
    ctx.arc(cx - r * 0.3, cy - r * 0.32, r * 0.24, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  } else {
    // Unlit: a hollow ring on the surface with a small core; undefined is
    // the same ring dashed and muted.
    ctx.fillStyle = t.surface;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.save();
    ctx.strokeStyle = sig === 2 ? t.labelMuted : t.outputBorderOff;
    ctx.lineWidth = lw;
    if (sig === 2) ctx.setLineDash([cell * 0.28, cell * 0.24]);
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.restore();
    ctx.fillStyle = t.outputOff;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.3, 0, Math.PI * 2);
    ctx.fill();
  }

  nsName(
    ctx, cell, component.name,
    component.x * cell, component.y * cell,
    component.width * cell, component.height * cell,
    t.labelMuted
  );

  if (slot) nsDot(ctx, cell, tailEdge, dotY, sig, t);
};

/** Recipe per gate; the keys are the lowercase subcircuit names `collapse.ts` reports. */
const RECIPES = {
  and:  { sprite: 'AND', qualifier: '&' },
  nand: { sprite: 'AND', negate: true, qualifier: '&' },
  or:   { sprite: 'OR', qualifier: '\u22651', qx: 0.44, qy: 0.18 },
  nor:  { sprite: 'OR', negate: true, qualifier: '\u22651', qx: 0.44, qy: 0.18 },
  xor:  { sprite: 'OR', exclusive: true, qualifier: '=1', qx: 0.44, qy: 0.18 },
  xnor: { sprite: 'OR', exclusive: true, negate: true, qualifier: '=1', qx: 0.44, qy: 0.18 },
  not:  { vector: 'triangle', negate: true },
};

/**
 * One body for every gate: tails, then the containers, then dots and the
 * name. `opts.portsFrom` lets a builtin macro draw on a virtual box while
 * its tails run to the real ports.
 */
function nsGate({ ctx, cell, component: c, inputSignals: inSigs, inputValues, outputSignal: outSig, theme }, opts) {
  const t = theme.colors;
  const ports = opts.portsFrom ?? c;
  const hasSprite = !!(opts.sprite && sprite(opts.sprite));
  const bounds = hasSprite ? spriteBounds(opts.sprite) : TRIANGLE_BOUNDS;
  const L = gateGeometry(cell, c, bounds, opts, ports.inPorts.length);
  const { x0, y0, w, h, cy, innerL, innerR, rect } = L;
  const gap = cell * 0.4;
  const leftEdge = innerL - gap;
  const rightEdge = innerR + gap;

  const inDotYs = [];
  for (let i = 0; i < ports.inPorts.length; i++) {
    const slot = ports.inPorts[i];
    const portY = slot.coord.y * cell + cell / 2;
    inDotYs.push(portY);
    nsTail(ctx, cell, leftEdge, slot.coord.x * cell + cell / 2, portY, inSigs[i] ?? 2, t, (inputValues[i]?.width ?? 1) > 1);
  }
  const outDotY = ports.outPort.y * cell + cell / 2;
  nsTail(ctx, cell, rightEdge, ports.outPort.x * cell + cell / 2, outDotY, outSig, t, (ports.bitWidth ?? 1) > 1);

  if (opts.exclusive) nsExclusive(ctx, cell, L.exclusive, rect, outSig, t);
  if (hasSprite) nsSpriteRect(ctx, opts.sprite, rect, outSig, t);
  else if (opts.vector === 'triangle') nsTriangle(ctx, t, cell, rect, outSig);
  else nsVectorGate(ctx, t, cell, rect, outSig, opts.sprite);
  if (opts.negate) nsNegate(ctx, cell, L.negate, cy, outSig, t, rect.artR);

  if (opts.qualifier) {
    ctx.save();
    ctx.fillStyle = t.labelOnComponent;
    ctx.font = nsFont(cell, 700);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(opts.qualifier, rect.left + rect.size * (opts.qx ?? 0.31), rect.cy - rect.size * (opts.qy ?? 0.21));
    ctx.restore();
  }
  for (let i = 0; i < ports.inPorts.length; i++) nsDot(ctx, cell, leftEdge, inDotYs[i], inSigs[i] ?? 2, t);
  nsDot(ctx, cell, rightEdge, outDotY, outSig, t);
  nsName(ctx, cell, c.name, x0, y0, w, h, t.labelMuted);
}

const drawNot = (args) => {
  nsGate(args, RECIPES.not);
};

const drawAnd = (args) => {
  nsGate(args, RECIPES.and);
};

/**
 * A subcircuit has two faces. A builtin macro (and, nand, or, nor, xor,
 * xnor, not) IS a gate: it takes the gate recipe on a virtual 5-wide box
 * centred in the macro box, so the symbol, slots and bubble match the
 * primitive exactly, and the tails run longer to reach the real ports.
 * Anything else is the labelled box, until Phase 4 gives it a chip.
 */
const drawSubcircuit = (args) => {
  const { ctx, cell, component, inputSignals, inputValues, outputSignal, theme } = args;
  const subcircuit = component.kind.tag === 'subcircuit' ? component.kind.subcircuit : '';
  const recipe = RECIPES[subcircuit.toLowerCase()];
  if (recipe) {
    const virt = { ...component, x: component.x + (component.width - 5) / 2, width: 5 };
    nsGate({ ...args, component: virt }, { ...recipe, portsFrom: component });
    return;
  }

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
    const portX = slot.coord.x * cell + cell / 2;
    const portY = slot.coord.y * cell + cell / 2;
    inDotYs.push(portY);
    nsTail(ctx, cell, leftEdge, portX, portY, sig, theme.colors, (inputValues[i]?.width ?? 1) > 1);
  }
  const outDotY = component.outPort.y * cell + cell / 2;
  nsTail(ctx, cell, rightEdge, component.outPort.x * cell + cell / 2, outDotY, outputSignal, theme.colors, (component.bitWidth ?? 1) > 1);

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

  for (let i = 0; i < component.inPorts.length; i++) {
    nsDot(ctx, cell, leftEdge, inDotYs[i], inputSignals[i] ?? 2, theme.colors);
  }
  nsDot(ctx, cell, rightEdge, outDotY, outputSignal, theme.colors);

  nsName(ctx, cell, component.name, x0, y0, w, h, theme.colors.labelMuted);
};

/**
 * A bit-shape or memory box: the same rounded box the collapsed macro draws,
 * with the site's tails and a name below. These four kinds used to fall
 * through to the package's default skins and render in a foreign visual
 * language beside the sprite-drawn gates.
 */
const drawBox = ({ ctx, cell, component, inputSignals, inputValues, outputSignal, theme }, label, borderColor) => {
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
    nsTail(ctx, cell, leftEdge, slot.coord.x * cell + cell / 2, portY, sig, theme.colors, (inputValues[i]?.width ?? 1) > 1);
  }
  const outDotY = component.outPort.y * cell + cell / 2;
  nsTail(ctx, cell, rightEdge, component.outPort.x * cell + cell / 2, outDotY, outputSignal, theme.colors, (component.bitWidth ?? 1) > 1);

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
    nsDot(ctx, cell, leftEdge, inDotYs[i], inputSignals[i] ?? 2, theme.colors);
  }
  nsDot(ctx, cell, rightEdge, outDotY, outputSignal, theme.colors);
};

/** `[i]` or `[lo:hi]`, the way the compiler's own preview writes a slice. */
/* ───── bit parts: slice and concat ────────────────────────────────
 * A labelled box tells you a slice exists; it does not tell you which bits
 * it takes. These draw the bit field itself: a slice is a ruler of the
 * incoming word with the tapped range picked out, a concat is the
 * assembled word with a lane per operand in order.
 */

/** Shared shell: inset rounded rect in the bus colour on the surface. */
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

/** Bits a slice's ruler will show one by one; wider words get a range bar. */
const RULER_MAX_BITS = 16;

/**
 * SLICE — a ruler of the incoming word, MSB left so it reads like the hex
 * chip above it, the tapped range filled in the bus colour and the
 * discarded bits muted. Above sixteen bits the ruler collapses to one bar
 * with the tapped span filled. The `[lo:hi]` label sits under it so the
 * notation and the picture agree.
 */
function nsSliceAsset(ctx, t, cell, c, inputValues, outSig) {
  const { y0, h, bx, bw } = nsShell(ctx, t, cell, c);
  const sl = c.slice ?? { lo: 0, hi: 1 };
  const inWidth = Math.max(inputValues[0]?.width ?? 0, sl.hi, 1);
  const padX = cell * 0.32;
  const rulerW = bw - padX * 2;
  const rulerH = h * 0.32;
  const ry = y0 + h * 0.2;
  const takenAlpha = outSig === 2 ? 0.4 : outSig === 0 ? 0.7 : 1;
  ctx.save();
  if (inWidth <= RULER_MAX_BITS) {
    const gap = Math.max(1, cell * 0.05);
    const tickW = (rulerW - gap * (inWidth - 1)) / inWidth;
    for (let i = 0; i < inWidth; i++) {
      const bit = inWidth - 1 - i;
      const taken = bit >= sl.lo && bit < sl.hi;
      const tx = bx + padX + i * (tickW + gap);
      ctx.beginPath();
      ctx.roundRect(tx, ry, tickW, rulerH, Math.min(tickW / 2, cell * 0.07));
      ctx.fillStyle = taken ? t.wireBus : t.labelMuted;
      ctx.globalAlpha = taken ? takenAlpha : 0.38;
      ctx.fill();
    }
  } else {
    // The whole word as one muted bar, the tapped span filled over it. MSB
    // left: bit `hi − 1` is `inWidth − hi` bits in from the left edge.
    ctx.beginPath();
    ctx.roundRect(bx + padX, ry, rulerW, rulerH, cell * 0.07);
    ctx.fillStyle = t.labelMuted;
    ctx.globalAlpha = 0.38;
    ctx.fill();
    const sx = bx + padX + rulerW * ((inWidth - sl.hi) / inWidth);
    const sw = rulerW * ((sl.hi - sl.lo) / inWidth);
    ctx.beginPath();
    ctx.roundRect(sx, ry, sw, rulerH, cell * 0.07);
    ctx.fillStyle = t.wireBus;
    ctx.globalAlpha = takenAlpha;
    ctx.fill();
  }
  ctx.restore();
  ctx.fillStyle = t.label;
  ctx.font = nsFont(cell, 700);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(sl.hi - sl.lo <= 1 ? `[${sl.lo}]` : `[${sl.lo}:${sl.hi}]`, bx + bw / 2, y0 + h * 0.74);
}

/** Tails, dots and bus leads around a bit-field asset. */
function nsBitPart({ ctx, cell, component: c, inputSignals: inSigs, inputValues, outputSignal: outSig, theme }, body) {
  const t = theme.colors;
  const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell;
  const inset = cell * 0.35;
  const gap = cell * 0.4;
  const leftEdge = x0 + inset - gap;
  const rightEdge = x0 + w - inset + gap;
  const inDotYs = [];
  for (let i = 0; i < c.inPorts.length; i++) {
    const slot = c.inPorts[i];
    const portY = slot.coord.y * cell + cell / 2;
    inDotYs.push(portY);
    nsTail(ctx, cell, leftEdge, slot.coord.x * cell + cell / 2, portY, inSigs[i] ?? 2, t, (inputValues[i]?.width ?? 1) > 1);
  }
  const outDotY = c.outPort.y * cell + cell / 2;
  nsTail(ctx, cell, rightEdge, c.outPort.x * cell + cell / 2, outDotY, outSig, t, (c.bitWidth ?? 1) > 1);
  body(ctx, t, cell, c, inputValues, outSig);
  for (let i = 0; i < c.inPorts.length; i++) nsDot(ctx, cell, leftEdge, inDotYs[i], inSigs[i] ?? 2, t);
  nsDot(ctx, cell, rightEdge, outDotY, outSig, t);
  void y0;
}

const drawSlice = (args) => {
  nsBitPart(args, nsSliceAsset);
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
  nsName(ctx, cell, component.name, x0, y0, component.width * cell, component.height * cell, theme.colors.labelMuted);
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
 * A wire in the palette's colour for what it carries, at a weight that
 * follows the cell. A bus with a defined value is a bus, whatever its bits,
 * drawn 1.5× heavy with the bit-count slash; an active single bit gets a
 * soft glow under its colour. The route — every segment, corners rounded,
 * hops over its crossings — is traced by the renderer's own `traceWire`,
 * the same function its default painter uses, so the site cannot draw a
 * jump or a corner anywhere the renderer would not.
 */
function drawWire({ ctx, cell, wire, signal, value, theme }) {
  const t = theme.colors;
  const style = wireStyleOf(value);
  const bus = style === 'bus';
  const width = nsWire(cell) * (bus ? 1.5 : 1);
  const trace = () => {
    ctx.beginPath();
    traceWire(ctx, wire, cell, { arcRadius: cell * 0.4, cornerRadius: cell * 0.6 });
  };
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  if (signal === 1 && !bus) {
    // The glow: the same path, wider and translucent, under the colour. Two
    // explicit strokes rather than a patched `stroke`, so nothing on the
    // context is touched that `restore` does not put back.
    ctx.save();
    ctx.globalAlpha = 0.22;
    ctx.strokeStyle = t.wireActive;
    ctx.lineWidth = width + cell * 0.5;
    trace();
    ctx.stroke();
    ctx.restore();
  }
  ctx.strokeStyle = t[wireColorKey(style)];
  ctx.lineWidth = width;
  trace();
  ctx.stroke();
  if (bus) nsBusTick(ctx, t, cell, wire, value);
}

/**
 * The bit-count slash on a bus — the standard notation the site lacked — on
 * the first horizontal run two cells or longer, with the width beside it.
 */
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

/**
 * A fan-out junction: a ring in the wire's own colour, so a split reads as
 * "the signal branches here" and stays distinct from the solid terminal dots
 * at either end. The canvas is transparent, so the centre is knocked out to
 * alpha with `destination-out` rather than painted in a guessed background.
 */
function drawFanOut({ ctx, cell, x, y, value, theme }) {
  const cx = x * cell + cell / 2;
  const cy = y * cell + cell / 2;
  ctx.save();
  ctx.fillStyle = theme.colors[wireColorKey(wireStyleOf(value))];
  ctx.beginPath();
  ctx.arc(cx, cy, cell * 0.3, 0, Math.PI * 2);
  ctx.fill();
  ctx.globalCompositeOperation = 'destination-out';
  ctx.beginPath();
  ctx.arc(cx, cy, cell * 0.13, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

/**
 * The value chip for every multi-bit component: the pill, solid, in the bus
 * colour, carrying the text the canvas spelled in the reader's chosen base.
 * A pin's chip sits above its circle where the single-bit skin puts one;
 * any other box's sits above its top edge. A memory gets none: its word is
 * in its body.
 */
function drawBusValue({ ctx, cell, component, text, theme }) {
  const t = theme.colors;
  const kind = component.kind.tag === 'primitive' ? component.kind.kind : null;
  if (kind === ComponentKind.Rom || kind === ComponentKind.Ram) return;
  const w = component.width * cell;
  const h = component.height * cell;
  const cx = component.x * cell + w / 2;
  const isPin = kind === ComponentKind.InputPin || kind === ComponentKind.OutputPin;
  const bottom = isPin
    ? component.y * cell + h / 2 - pinRadius(cell, w, h) - cell * 0.5
    : component.y * cell - cell * 0.5;
  nsValuePill(ctx, t, cell, cx, bottom, text, 'solid', t.wireBus, t.busLabel);
}

export const skins = {
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

/**
 * Everything a theme is, except its colours. Spread into each palette's theme
 * object by `circ-theme.mjs`.
 */
export const sharedRenderers = {
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
  wire: drawWire,
  // No port markers — each skin draws its own tail.
  portMarker: () => {},
  // A junction is the one mark the canvas used to stamp itself, a dot in the
  // wire's colour on a wire of that colour. The ring says something.
  fanOutMarker: drawFanOut,
  // The bus badge, as a chip in the palette rather than the library's blue
  // text; the text is the canvas's, so the reader's base setting is honoured.
  busValue: drawBusValue,
  // The ring around a hovered or host-highlighted component, drawn by the
  // canvas after every skin. One hook, every kind — including the four above
  // that used to fall through to defaults that never read `hovered`.
  highlight: drawHighlight,
};
