/**
 * Exact port of circ-renderer's drawing code (src/render/skins.ts,
 * src/render/canvas.ts, src/utils/theme.ts, src/layout/sizing.ts,
 * src/layout/place.ts) plus a proposed "next" skin set.
 *
 * `current` reproduces today's output pixel for pixel. Do not tune it.
 */

/* ── theme.ts: defaultColors ────────────────────────────────────────── */
import { siteSkins, siteLight, siteDark, siteFont, drawWireSite, spritesReady,
  nextSiteSkins, nextSiteLight, nextSiteDark, drawWireNextSite } from "./circ-site-theme.js";
export { siteLight, siteDark, siteFont, spritesReady, nextSiteLight, nextSiteDark };

export const defaultColors = {
  background: "#f8f9fa",
  grid: "#e9ecef",
  stroke: "#212529",
  fillIdle: "#ffffff",
  fillActive: "#28a745",
  fillUndefined: "#adb5bd",
  wireIdle: "#495057",
  wireActive: "#28a745",
  wireUndefined: "#ced4da",
  wireBus: "#1971c2",
  busLabel: "#1971c2",
  label: "#212529",
  labelMuted: "#868e96",
  macro: "#6f42c1",
};

/** README's dark override — note it spreads defaultColors, so bus stays #1971c2. */
export const darkColors = {
  ...defaultColors,
  background: "#0f172a",
  stroke: "#94a3b8",
  fillIdle: "#1e293b",
  fillActive: "#22d3ee",
  fillUndefined: "#334155",
  wireIdle: "#475569",
  wireActive: "#22d3ee",
  wireUndefined: "#334155",
  label: "#e2e8f0",
  labelMuted: "#64748b",
  macro: "#a78bfa",
  grid: "#1e293b",
};

/** baseTheme.font */
export const baseFont = '500 8px "JetBrains Mono", ui-monospace, monospace';

/* ── proposed palettes (evolution of the same hues) ─────────────────── */
export const nextLight = {
  ...defaultColors,
  background: "#f7f8f9",
  surface: "#ffffff",
  stroke: "#3f464e",
  fillIdle: "#ffffff",
  fillActive: "#1a9c47",
  fillUndefined: "#e4e7ea",
  wireIdle: "#8b939c",
  wireActive: "#1a9c47",
  wireUndefined: "#cdd2d7",
  wireBus: "#1971c2",
  busLabel: "#ffffff",
  label: "#1b1f24",
  labelMuted: "#7b848d",
  macro: "#6f42c1",
  hover: "#1971c2",
};
export const nextDark = {
  ...nextLight,
  background: "#0f172a",
  surface: "#182236",
  stroke: "#7c8ba4",
  fillIdle: "#182236",
  fillActive: "#22d3ee",
  fillUndefined: "#243147",
  wireIdle: "#4a5a75",
  wireActive: "#22d3ee",
  wireUndefined: "#2c3a52",
  wireBus: "#5aa2f0",
  busLabel: "#0f172a",
  label: "#e2e8f0",
  labelMuted: "#7d8ba0",
  macro: "#a78bfa",
  hover: "#7dd3fc",
};

/* ── topology.ts: signal helpers ────────────────────────────────────── */
export const undef = (width = 1) => ({ value: 0, defined: 0, width });
export const val = (value, width = 1) => ({ value, defined: (1 << width) - 1 >>> 0, width });
const widthMask = (w) => (w >= 32 ? 0xffffffff : ((1 << w) - 1) >>> 0);
export const signalOf = (v) => {
  const m = widthMask(v.width);
  if ((v.defined & m) >>> 0 !== m) return 2;
  return ((v.value & m) >>> 0) === 0 ? 0 : 1;
};
const styleForSignal = (s) => (s === 1 ? "active" : s === 0 ? "idle" : "undefined");
const wireStyleOf = (v) => {
  if (v.width <= 1) return styleForSignal(signalOf(v));
  const m = widthMask(v.width);
  if (((v.defined & m) >>> 0) !== m) return "undefined";
  return "bus";
};
const wireColorKey = (s) =>
  s === "active" ? "wireActive" : s === "idle" ? "wireIdle" : s === "bus" ? "wireBus" : "wireUndefined";
function formatBus(v) {
  const m = widthMask(v.width);
  if (((v.defined & m) >>> 0) !== m) return "?";
  return "0x" + ((v.value & m) >>> 0).toString(16).toUpperCase().padStart(Math.ceil(v.width / 4), "0");
}

/* ── sizing.ts ──────────────────────────────────────────────────────── */
export const pinSize = (nameLen) => ({ width: Math.max(5, nameLen + 4), height: 3 });
export const sliceSize = (lo, hi) => ({
  width: Math.max(5, (hi - lo <= 1 ? `[${lo}]` : `[${lo}:${hi}]`).length + 2),
  height: 3,
});
export const concatSize = (n) => ({ width: 5, height: n <= 1 ? 3 : 2 * Math.max(1, n) + 1 });
export const macroSize = (labelWidth, inputCount) => ({
  width: Math.max(8, labelWidth + 2),
  height: inputCount <= 1 ? 3 : 2 * inputCount + 1,
});

/* ── skins.ts (verbatim geometry) ───────────────────────────────────── */
const fillFor = (t, sig) =>
  t[styleForSignal(sig) === "active" ? "fillActive" : styleForSignal(sig) === "idle" ? "fillIdle" : "fillUndefined"];

function boxOutline(ctx, t, cell, x, y, w, h, sig) {
  ctx.fillStyle = fillFor(t, sig);
  ctx.strokeStyle = t.stroke;
  ctx.lineWidth = Math.max(1, cell * 0.12);
  const px = x * cell, py = y * cell, pw = w * cell, ph = h * cell;
  const r = Math.min(cell * 0.4, pw / 2, ph / 2);
  ctx.beginPath();
  ctx.roundRect(px + ctx.lineWidth / 2, py + ctx.lineWidth / 2, pw - ctx.lineWidth, ph - ctx.lineWidth, r);
  ctx.fill();
  ctx.stroke();
}

function drawLabel(ctx, t, cell, font, text, cx, cy, colorKey = "label") {
  ctx.fillStyle = t[colorKey];
  ctx.font = font ?? `${Math.round(cell * 1.1)}px ui-monospace, monospace`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(text, cx, cy);
}

const cx_ = (c, cell) => (c.x + c.width / 2) * cell;
const cy_ = (c, cell) => (c.y + c.height / 2) * cell;

const currentSkins = {
  input_pin: ({ ctx, t, cell, font, c, outSig }) => {
    boxOutline(ctx, t, cell, c.x, c.y, c.width, c.height, outSig);
    drawLabel(ctx, t, cell, font, c.name || "pin", cx_(c, cell), cy_(c, cell));
  },
  output_pin: ({ ctx, t, cell, font, c, inSigs }) => {
    const sig = inSigs[0] ?? 2;
    boxOutline(ctx, t, cell, c.x, c.y, c.width, c.height, sig);
    drawLabel(ctx, t, cell, font, c.name || "out", cx_(c, cell), cy_(c, cell));
  },
  not_gate: ({ ctx, t, cell, c, outSig }) => {
    const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
    ctx.fillStyle = fillFor(t, outSig);
    ctx.strokeStyle = t.stroke;
    ctx.lineWidth = Math.max(1, cell * 0.12);
    ctx.beginPath();
    const triRight = x0 + w * 0.78;
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
  },
  and_gate: ({ ctx, t, cell, c, outSig }) => {
    const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
    ctx.fillStyle = fillFor(t, outSig);
    ctx.strokeStyle = t.stroke;
    ctx.lineWidth = Math.max(1, cell * 0.12);
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
  },
  led: ({ ctx, t, cell, c, inSigs }) => {
    const sig = inSigs[0] ?? 2;
    const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
    const cx = x0 + w / 2, cy = y0 + h / 2, r = Math.min(w, h) * 0.4;
    ctx.fillStyle = fillFor(t, sig);
    ctx.strokeStyle = t.stroke;
    ctx.lineWidth = Math.max(1, cell * 0.14);
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    if (sig === 1) {
      ctx.strokeStyle = t.fillActive;
      ctx.globalAlpha = 0.5;
      ctx.lineWidth = Math.max(1, cell * 0.3);
      ctx.beginPath();
      ctx.arc(cx, cy, r * 1.4, 0, Math.PI * 2);
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
  },
  slice: ({ ctx, t, cell, font, c, outSig }) => {
    boxOutline(ctx, t, cell, c.x, c.y, c.width, c.height, outSig);
    const { lo, hi } = c.slice ?? { lo: 0, hi: 1 };
    drawLabel(ctx, t, cell, font, hi - lo <= 1 ? `[${lo}]` : `[${lo}:${hi}]`, cx_(c, cell), cy_(c, cell));
  },
  concat: ({ ctx, t, cell, font, c, outSig }) => {
    boxOutline(ctx, t, cell, c.x, c.y, c.width, c.height, outSig);
    drawLabel(ctx, t, cell, font, "{\u00b7}", cx_(c, cell), cy_(c, cell));
  },
  subcircuit: ({ ctx, t, cell, font, c }) => {
    const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
    ctx.fillStyle = fillFor(t, 2);
    ctx.strokeStyle = t.macro;
    ctx.lineWidth = Math.max(1, cell * 0.12);
    ctx.beginPath();
    ctx.roundRect(x0 + ctx.lineWidth / 2, y0 + ctx.lineWidth / 2, w - ctx.lineWidth, h - ctx.lineWidth, cell * 0.25);
    ctx.fill();
    ctx.stroke();
    drawLabel(ctx, t, cell, font, `${c.subcircuit}:${c.name}`, x0 + w / 2, y0 + h / 2);
  },
};

/* ── proposed skins ─────────────────────────────────────────────────── */
const nextFont = (cell, weight = 500) =>
  `${weight} ${Math.max(9, Math.round(cell * 0.6))}px "JetBrains Mono", ui-monospace, monospace`;

function glow(ctx, color, blur, fn) {
  ctx.save();
  ctx.shadowColor = color;
  ctx.shadowBlur = blur;
  fn();
  ctx.restore();
}

/** Shared body: constant silhouette, signal only on the border + glow. */
function nextBody(ctx, t, cell, path, sig, opts = {}) {
  const lw = Math.max(1.25, cell * 0.085);
  ctx.lineJoin = "round";
  ctx.fillStyle = opts.fill ?? t.surface;
  path();
  ctx.fill();
  if (sig === 1) {
    glow(ctx, t.fillActive, cell * 0.55, () => {
      ctx.strokeStyle = t.fillActive;
      ctx.lineWidth = lw;
      path();
      ctx.stroke();
    });
    ctx.strokeStyle = t.fillActive;
  } else if (sig === 2) {
    ctx.setLineDash([cell * 0.22, cell * 0.22]);
    ctx.strokeStyle = t.labelMuted;
  } else {
    ctx.strokeStyle = opts.stroke ?? t.stroke;
  }
  ctx.lineWidth = lw;
  path();
  ctx.stroke();
  ctx.setLineDash([]);
}

function hoverRing(ctx, t, cell, x, y, w, h, r) {
  ctx.strokeStyle = t.hover;
  ctx.lineWidth = Math.max(1.5, cell * 0.1);
  ctx.globalAlpha = 0.9;
  ctx.beginPath();
  ctx.roundRect(x - cell * 0.3, y - cell * 0.3, w + cell * 0.6, h + cell * 0.6, r + cell * 0.3);
  ctx.stroke();
  ctx.globalAlpha = 1;
}

const nextSkins = {
  input_pin: ({ ctx, t, cell, c, outSig, hovered }) => {
    const x = c.x * cell, y = c.y * cell, w = c.width * cell, h = c.height * cell;
    const r = h / 2;
    const path = () => { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); };
    if (hovered) hoverRing(ctx, t, cell, x, y, w, h, r);
    nextBody(ctx, t, cell, path, outSig);
    // state dot at the left, the clickable affordance
    ctx.beginPath();
    ctx.arc(x + h * 0.42, y + h / 2, cell * 0.26, 0, Math.PI * 2);
    ctx.fillStyle = outSig === 1 ? t.fillActive : outSig === 0 ? t.wireIdle : t.fillUndefined;
    ctx.fill();
    ctx.fillStyle = t.label;
    ctx.font = nextFont(cell, 600);
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText(c.name || "pin", x + h * 0.42 + cell * 0.55, y + h / 2 + cell * 0.03);
  },
  output_pin: ({ ctx, t, cell, c, inSigs }) => {
    const sig = inSigs[0] ?? 2;
    const x = c.x * cell, y = c.y * cell, w = c.width * cell, h = c.height * cell;
    const path = () => { ctx.beginPath(); ctx.roundRect(x, y, w, h, cell * 0.18); };
    nextBody(ctx, t, cell, path, sig);
    ctx.fillStyle = t.label;
    ctx.font = nextFont(cell, 600);
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(c.name || "out", x + w / 2, y + h / 2 + cell * 0.03);
  },
  not_gate: ({ ctx, t, cell, c, outSig }) => {
    const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
    const tip = x0 + w * 0.74;
    const bubbleR = cell * 0.3;
    const path = () => {
      ctx.beginPath();
      ctx.moveTo(x0 + cell * 0.1, y0 + h * 0.1);
      ctx.lineTo(tip, y0 + h / 2);
      ctx.lineTo(x0 + cell * 0.1, y0 + h * 0.9);
      ctx.closePath();
    };
    nextBody(ctx, t, cell, path, outSig);
    const bubble = () => { ctx.beginPath(); ctx.arc(tip + bubbleR + cell * 0.12, y0 + h / 2, bubbleR, 0, Math.PI * 2); };
    nextBody(ctx, t, cell, bubble, outSig);
  },
  and_gate: ({ ctx, t, cell, c, outSig }) => {
    const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
    const left = x0 + cell * 0.1, top = y0 + cell * 0.35, bot = y0 + h - cell * 0.35;
    const flat = x0 + w * 0.42, right = x0 + w - cell * 0.1;
    const path = () => {
      ctx.beginPath();
      ctx.moveTo(left, top);
      ctx.lineTo(flat, top);
      ctx.bezierCurveTo(right, top, right, bot, flat, bot);
      ctx.lineTo(left, bot);
      ctx.closePath();
    };
    nextBody(ctx, t, cell, path, outSig);
    ctx.fillStyle = t.labelMuted;
    ctx.font = nextFont(cell, 600);
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.fillText("&", left + cell * 0.35, top + cell * 0.22);
  },
  led: ({ ctx, t, cell, c, inSigs }) => {
    const sig = inSigs[0] ?? 2;
    const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
    const cx = x0 + w / 2, cy = y0 + h / 2, r = Math.min(w, h) * 0.42;
    const path = () => { ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); };
    nextBody(ctx, t, cell, path, sig, { fill: sig === 1 ? t.fillActive : t.surface });
    if (sig === 1) {
      glow(ctx, t.fillActive, cell * 1.1, () => {
        ctx.fillStyle = t.fillActive;
        ctx.beginPath();
        ctx.arc(cx, cy, r * 0.98, 0, Math.PI * 2);
        ctx.fill();
      });
      ctx.fillStyle = t.background;
      ctx.globalAlpha = 0.55;
      ctx.beginPath();
      ctx.arc(cx - r * 0.28, cy - r * 0.3, r * 0.26, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    } else {
      ctx.fillStyle = sig === 0 ? t.wireIdle : t.fillUndefined;
      ctx.globalAlpha = 0.35;
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.42, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    }
  },
  slice: ({ ctx, t, cell, c, outSig }) => {
    iecBox(ctx, t, cell, c, outSig, c.slice ? (c.slice.hi - c.slice.lo <= 1 ? `[${c.slice.lo}]` : `[${c.slice.lo}:${c.slice.hi}]`) : "[0:1]", "SLICE");
  },
  concat: ({ ctx, t, cell, c, outSig }) => {
    iecBox(ctx, t, cell, c, outSig, "{\u00b7}", "CONCAT");
  },
  subcircuit: ({ ctx, t, cell, c }) => {
    const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
    const path = () => { ctx.beginPath(); ctx.roundRect(x0, y0, w, h, cell * 0.14); };
    nextBody(ctx, t, cell, path, 0, { stroke: t.macro });
    ctx.save();
    ctx.beginPath();
    ctx.roundRect(x0, y0, w, h, cell * 0.14);
    ctx.clip();
    ctx.fillStyle = t.macro;
    ctx.globalAlpha = 0.12;
    ctx.fillRect(x0, y0, w, cell * 0.9);
    ctx.globalAlpha = 1;
    ctx.restore();
    ctx.fillStyle = t.macro;
    ctx.font = nextFont(cell, 700);
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText(c.subcircuit.toUpperCase(), x0 + cell * 0.4, y0 + cell * 0.46);
    ctx.fillStyle = t.label;
    ctx.font = nextFont(cell, 500);
    ctx.textAlign = "center";
    ctx.fillText(c.name, x0 + w / 2, y0 + cell * 0.9 + (h - cell * 0.9) / 2);
  },
};

/** IEC-style rectangular part: square corners, qualifier strip, mono label. */
function iecBox(ctx, t, cell, c, sig, label, qualifier) {
  const x0 = c.x * cell, y0 = c.y * cell, w = c.width * cell, h = c.height * cell;
  const path = () => { ctx.beginPath(); ctx.roundRect(x0, y0, w, h, cell * 0.1); };
  nextBody(ctx, t, cell, path, sig, { stroke: t.wireBus });
  ctx.fillStyle = t.wireBus;
  ctx.fillRect(x0, y0, Math.max(2, cell * 0.14), h);
  ctx.fillStyle = t.label;
  ctx.font = nextFont(cell, 600);
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(label, x0 + w / 2 + cell * 0.1, y0 + h / 2 + cell * 0.03);
  if (qualifier && h > cell * 3.2) {
    ctx.fillStyle = t.labelMuted;
    ctx.font = nextFont(cell, 500);
    ctx.textAlign = "left";
    ctx.fillText(qualifier, x0 + cell * 0.45, y0 + cell * 0.55);
  }
}

export const skinSets = { current: currentSkins, next: nextSkins, site: siteSkins, "site-next": nextSiteSkins };

/* ── canvas.ts pipeline ─────────────────────────────────────────────── */
function drawWireCurrent(ctx, t, cell, wire, value, byId) {
  const style = wireStyleOf(value);
  ctx.strokeStyle = t[wireColorKey(style)];
  ctx.lineWidth = Math.max(1, cell * (style === "bus" ? 0.28 : 0.18));
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  const src = byId.get(wire.srcId);
  if (src && src.outPort) {
    const sy = src.outPort.y * cell + cell / 2;
    ctx.beginPath();
    ctx.moveTo((src.x + src.width - 0.5) * cell, sy);
    ctx.lineTo(src.outPort.x * cell + cell / 2, sy);
    ctx.stroke();
  }
  const dst = byId.get(wire.dstId);
  if (dst) {
    const slot = dst.inPorts.find((p) => p.portName === wire.dstPort);
    if (slot) {
      const dy = slot.coord.y * cell + cell / 2;
      ctx.beginPath();
      ctx.moveTo(slot.coord.x * cell + cell / 2, dy);
      ctx.lineTo((dst.x + 0.5) * cell, dy);
      ctx.stroke();
    }
  }
  for (const seg of wire.segments) {
    const sx = seg.from.x * cell + cell / 2, sy = seg.from.y * cell + cell / 2;
    const ex = seg.to.x * cell + cell / 2, ey = seg.to.y * cell + cell / 2;
    if (seg.from.y !== seg.to.y) {
      ctx.beginPath();
      ctx.moveTo(sx, sy);
      ctx.lineTo(ex, ey);
      ctx.stroke();
      continue;
    }
    const lo = Math.min(sx, ex), hi = Math.max(sx, ex);
    const jumps = (wire.crossings ?? [])
      .filter((c) => c.y === seg.from.y && c.x * cell + cell / 2 >= lo && c.x * cell + cell / 2 <= hi)
      .map((c) => c.x * cell + cell / 2)
      .sort((a, b) => a - b);
    ctx.beginPath();
    let cursor = lo;
    const arcR = cell * 0.4;
    for (const jx of jumps) {
      ctx.moveTo(cursor, sy);
      ctx.lineTo(jx - arcR, sy);
      ctx.arc(jx, sy, arcR, Math.PI, 0, false);
      cursor = jx + arcR;
    }
    ctx.moveTo(cursor, sy);
    ctx.lineTo(hi, sy);
    ctx.stroke();
  }
}

function drawWireNext(ctx, t, cell, wire, value, byId) {
  const style = wireStyleOf(value);
  ctx.strokeStyle = t[wireColorKey(style)];
  ctx.lineWidth = Math.max(1.25, cell * (style === "bus" ? 0.2 : 0.115));
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  const run = () => {
    const src = byId.get(wire.srcId);
    if (src && src.outPort) {
      const sy = src.outPort.y * cell + cell / 2;
      ctx.beginPath();
      ctx.moveTo((src.x + src.width - 0.5) * cell, sy);
      ctx.lineTo(src.outPort.x * cell + cell / 2, sy);
      ctx.stroke();
    }
    const dst = byId.get(wire.dstId);
    if (dst) {
      const slot = dst.inPorts.find((p) => p.portName === wire.dstPort);
      if (slot) {
        const dy = slot.coord.y * cell + cell / 2;
        ctx.beginPath();
        ctx.moveTo(slot.coord.x * cell + cell / 2, dy);
        ctx.lineTo((dst.x + 0.5) * cell, dy);
        ctx.stroke();
      }
    }
    // rounded corners between consecutive segments
    const pts = [];
    for (const seg of wire.segments) {
      if (!pts.length) pts.push({ x: seg.from.x * cell + cell / 2, y: seg.from.y * cell + cell / 2 });
      pts.push({ x: seg.to.x * cell + cell / 2, y: seg.to.y * cell + cell / 2 });
    }
    if (pts.length < 2) return;
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length - 1; i++) {
      ctx.arcTo(pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, cell * 0.55);
    }
    ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y);
    ctx.stroke();
  };
  if (style === "active") glow(ctx, t.wireActive, cell * 0.45, run);
  else run();
  if (style === "bus") busTick(ctx, t, cell, wire, value);
}

/** Standard bus-width notation: a slash across the wire with the bit count. */
function busTick(ctx, t, cell, wire, value) {
  const seg = wire.segments.find((s) => s.from.y === s.to.y && Math.abs(s.to.x - s.from.x) >= 2);
  if (!seg) return;
  const mx = ((seg.from.x + seg.to.x) / 2) * cell + cell / 2;
  const my = seg.from.y * cell + cell / 2;
  ctx.save();
  ctx.strokeStyle = t.wireBus;
  ctx.lineWidth = Math.max(1.25, cell * 0.1);
  ctx.beginPath();
  ctx.moveTo(mx - cell * 0.26, my + cell * 0.34);
  ctx.lineTo(mx + cell * 0.26, my - cell * 0.34);
  ctx.stroke();
  ctx.fillStyle = t.wireBus;
  ctx.font = nextFont(cell, 600);
  ctx.textAlign = "center";
  ctx.textBaseline = "bottom";
  ctx.fillText(String(value.width), mx + cell * 0.5, my - cell * 0.3);
  ctx.restore();
}

function portMarkersCurrent(ctx, t, cell, wires, byId, valueOf) {
  const stamped = new Set();
  wires.forEach((wire, i) => {
    const value = valueOf(i);
    const color = t[wireColorKey(wireStyleOf(value))];
    const src = byId.get(wire.srcId);
    if (src && src.outPort && !stamped.has(wire.srcId)) {
      const cx = src.outPort.x * cell + cell / 2, cy = src.outPort.y * cell + cell / 2;
      ctx.fillStyle = t.background;
      ctx.strokeStyle = color;
      ctx.lineWidth = Math.max(1, cell * 0.14);
      ctx.beginPath();
      ctx.arc(cx, cy, cell * 0.18, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      stamped.add(wire.srcId);
    }
    const dst = byId.get(wire.dstId);
    const slot = dst && dst.inPorts.find((p) => p.portName === wire.dstPort);
    if (!slot) return;
    const size = cell * 0.32;
    const tipX = (slot.coord.x + 1) * cell, tipY = slot.coord.y * cell + cell / 2;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(tipX, tipY);
    ctx.lineTo(tipX - size, tipY - size / 2);
    ctx.lineTo(tipX - size, tipY + size / 2);
    ctx.closePath();
    ctx.fill();
  });
}

function portMarkersNext(ctx, t, cell, wires, byId, valueOf) {
  const stamped = new Set();
  wires.forEach((wire, i) => {
    const value = valueOf(i);
    const color = t[wireColorKey(wireStyleOf(value))];
    const src = byId.get(wire.srcId);
    if (src && src.outPort && !stamped.has(wire.srcId)) {
      const cx = src.outPort.x * cell + cell / 2, cy = src.outPort.y * cell + cell / 2;
      ctx.fillStyle = t.background;
      ctx.beginPath();
      ctx.arc(cx, cy, cell * 0.24, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(cx, cy, cell * 0.15, 0, Math.PI * 2);
      ctx.fill();
      stamped.add(wire.srcId);
    }
    const dst = byId.get(wire.dstId);
    const slot = dst && dst.inPorts.find((p) => p.portName === wire.dstPort);
    if (!slot) return;
    const tipX = (slot.coord.x + 1) * cell, tipY = slot.coord.y * cell + cell / 2;
    ctx.strokeStyle = color;
    ctx.lineWidth = Math.max(1.25, cell * 0.11);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.beginPath();
    ctx.moveTo(tipX - cell * 0.3, tipY - cell * 0.2);
    ctx.lineTo(tipX - cell * 0.05, tipY);
    ctx.lineTo(tipX - cell * 0.3, tipY + cell * 0.2);
    ctx.stroke();
  });
}

function busBadges(ctx, t, cell, comps, font, style) {
  ctx.save();
  ctx.textAlign = "center";
  for (const c of comps) {
    if (!c.bitWidth || c.bitWidth <= 1) continue;
    // site-next pins print their value inside the circle.
    if (style === "site-next" && (c.kind === "input_pin" || c.kind === "output_pin")) continue;
    // Memories print the addressed word in their body.
    if (style === "site-next" && (c.kind === "rom" || c.kind === "ram")) continue;
    const v = c.value ?? undef(c.bitWidth);
    const text = formatBus({ ...v, width: c.bitWidth });
    const cx = (c.x + c.width / 2) * cell;
    if (style === "current" || style === "site") {
      ctx.font = font;
      ctx.textBaseline = "bottom";
      ctx.fillStyle = t.busLabel ?? "#1971c2";
      ctx.fillText(text, cx, c.y * cell - cell * 0.15);
    } else {
      ctx.font = nextFont(cell, 600);
      ctx.textBaseline = "middle";
      const padX = cell * 0.35;
      const w = ctx.measureText(text).width + padX * 2;
      // Same one-cell budget as the pin chips, so badges never reach
      // into the row above.
      const h = cell * 0.92;
      const y = c.y * cell - cell * 0.06 - h;
      ctx.fillStyle = t.wireBus;
      ctx.beginPath();
      ctx.roundRect(cx - w / 2, y, w, h, h / 2);
      ctx.fill();
      ctx.fillStyle = t.busLabel;
      ctx.fillText(text, cx, y + h / 2 + cell * 0.03);
    }
  }
  ctx.restore();
}

function fanOutDots(ctx, t, cell, wires, valueOf, style) {
  const bySrc = new Map();
  wires.forEach((w, i) => {
    if (!bySrc.has(w.srcId)) bySrc.set(w.srcId, []);
    bySrc.get(w.srcId).push({ w, i });
  });
  for (const group of bySrc.values()) {
    if (group.length < 2) continue;
    const counts = new Map();
    for (const { w } of group) {
      for (const seg of w.segments) {
        const dx = Math.sign(seg.to.x - seg.from.x), dy = Math.sign(seg.to.y - seg.from.y);
        const len = Math.max(Math.abs(seg.to.x - seg.from.x), Math.abs(seg.to.y - seg.from.y));
        for (let k = 0; k <= len; k++) {
          const key = `${seg.from.x + dx * k},${seg.from.y + dy * k}`;
          counts.set(key, (counts.get(key) ?? 0) + 1);
        }
      }
    }
    const v = valueOf(group[0].i);
    const wireCol = t[wireColorKey(wireStyleOf(v))] ?? "#444";
    for (const [key, n] of counts) {
      if (n < 3) continue;
      const [xs, ys] = key.split(",");
      const jx = Number(xs) * cell + cell / 2;
      const jy = Number(ys) * cell + cell / 2;
      if (style === "site-next") {
        // A junction, not a terminal: ring in the wire's own color so it
        // reads as "the signal splits here" and stays distinct from the
        // solid port dots.
        ctx.fillStyle = wireCol;
        ctx.beginPath();
        ctx.arc(jx, jy, cell * 0.3, 0, Math.PI * 2);
        ctx.fill();
        // The site canvas is transparent (clearRect), so knock the centre
        // out to alpha rather than painting a guessed background colour.
        ctx.save();
        ctx.globalCompositeOperation = "destination-out";
        ctx.beginPath();
        ctx.arc(jx, jy, cell * 0.13, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();
        continue;
      }
      ctx.fillStyle = wireCol;
      ctx.beginPath();
      ctx.arc(jx, jy, cell * (style === "current" ? 0.18 : 0.2), 0, Math.PI * 2);
      ctx.fill();
    }
  }
}

/**
 * Render a scene (one asset card or a whole circuit) into a canvas,
 * following canvas.ts draw order: bg → wires → components → fan-out
 * dots → port markers → bus badges.
 */
export function renderScene(canvas, scene) {
  const {
    cell = 16, pad = 4, gridW, gridH, theme = "light", style = "current",
    components = [], wires = [], transparent = false,
  } = scene;
  const t = style === "current"
    ? (theme === "dark" ? darkColors : defaultColors)
    : style === "site"
      ? (theme === "dark" ? siteDark : siteLight)
      : style === "site-next"
        ? (theme === "dark" ? nextSiteDark : nextSiteLight)
        : (theme === "dark" ? nextDark : nextLight);
  const font = style === "current" ? baseFont : style === "site" ? siteFont : nextFont(cell);
  const skins = skinSets[style];
  const dpr = window.devicePixelRatio || 1;
  const w = gridW * cell + pad * 2, h = gridH * cell + pad * 2;
  canvas.style.width = `${w}px`;
  canvas.style.height = `${h}px`;
  canvas.width = Math.round(w * dpr);
  canvas.height = Math.round(h * dpr);
  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, pad * dpr, pad * dpr);
  ctx.clearRect(-pad, -pad, w, h);
  if (!transparent) {
    ctx.fillStyle = t.background;
    ctx.fillRect(-pad, -pad, w, h);
  }
  const byId = new Map(components.map((c) => [c.id, c]));
  const valueOf = (i) => wires[i]?.value ?? undef(1);
  if (style === "site") {
    wires.forEach((wire, i) => drawWireSite(ctx, t, cell, wire, signalOf(valueOf(i))));
  } else if (style === "site-next") {
    wires.forEach((wire, i) => drawWireNextSite(ctx, t, cell, wire, signalOf(valueOf(i)), valueOf(i)));
  } else {
    const drawWire = style === "current" ? drawWireCurrent : drawWireNext;
    wires.forEach((wire, i) => drawWire(ctx, t, cell, wire, valueOf(i), byId));
  }
  for (const c of components) {
    // The site theme defines no slice/concat skin, so pickSkin falls back
    // to the library defaults — reproduced here.
    const skin = skins[c.kind] ?? (style === "site" ? currentSkins[c.kind] : null);
    if (!skin) continue;
    skin({
      ctx, t, cell, font, c,
      outSig: signalOf(c.value ?? undef(c.bitWidth ?? 1)),
      inSigs: (c.inValues ?? []).map(signalOf),
      hovered: !!c.hovered,
    });
  }
  fanOutDots(ctx, t, cell, wires, valueOf, style);
  // The site themes override portMarker with a no-op — each skin draws its own tail.
  if (style !== "site" && style !== "site-next") {
    (style === "current" ? portMarkersCurrent : portMarkersNext)(ctx, t, cell, wires, byId, valueOf);
  }
  busBadges(ctx, t, cell, components, font, style);
  return { ctx, colors: t };
}
