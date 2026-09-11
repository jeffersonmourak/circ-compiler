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
