// Themes for the embedded circ-renderer Canvas. Direct port of the blog's
// (jeffersonmourak.github.io) circ-runtime theme, with a derived light-mode
// color palette so the canvas works under both site themes. This file is the
// entry the islands import: it decodes the sprites, binds them to the skins
// in `circ-skins.mjs`, and pairs those with the palettes in
// `circ-palette.mjs`. The three are apart so the drawing can run under
// `bun test`, which has no `Image`.
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

import { colorsDark, colorsLight } from './circ-palette.mjs';
import { makeSkins } from './circ-skins.mjs';
import { loadAssets } from './circ-assets.mjs';

/** @typedef {import('./circ-palette.mjs').PaletteKey} PaletteKey */

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

/* ───── the page's assets, as the skins see them ───────────────────── */

/** @type {import('./circ-skins.mjs').Assets} */
const pageAssets = {
  // Live: null until `loadAssets` resolves, the decoded image after, so a
  // canvas that mounted early draws the vector fallback and the sprite-ready
  // retheme picks the PNG up — the same timing the one-file theme had.
  sprite: (name) => sprites?.[name] ?? null,
  offscreen: (width, height) => {
    const c = document.createElement('canvas');
    c.width = width;
    c.height = height;
    return c;
  },
  // Painted bounds of a sprite, as fractions of its square in the rotation
  // the skins draw it (the PNGs point up; the canvas turns them a quarter
  // clockwise). One 128×128 getImageData per name, on the decoded image,
  // never on a tinted copy: a tint must not move the bounds. The data-URI
  // images are same-origin, so the read does not taint.
  bounds: (name) => {
    const img = sprites?.[name];
    if (!img) return null;
    const N = 128;
    const c = document.createElement('canvas');
    c.width = N;
    c.height = N;
    const g = c.getContext('2d');
    g.translate(N / 2, N / 2);
    g.rotate(Math.PI / 2);
    g.drawImage(img, -N / 2, -N / 2, N, N);
    const d = g.getImageData(0, 0, N, N).data;
    let l = N, r = -1, top = N, bottom = -1;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        if (d[(y * N + x) * 4 + 3] > 16) {
          if (x < l) l = x;
          if (x > r) r = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    if (r < 0) return null;
    // Back apex: how far in the concave input edge reaches on the centre row.
    let apex = l;
    const mid = Math.floor(N / 2);
    for (let x = 0; x < N; x++) {
      if (d[(mid * N + x) * 4 + 3] > 16) { apex = x; break; }
    }
    return { l: l / N, r: (r + 1) / N, t: top / N, b: (bottom + 1) / N, apex: apex / N };
  },
};

const sharedRenderers = makeSkins(pageAssets);

/* ───── theme objects ──────────────────────────────────────────────── */

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
