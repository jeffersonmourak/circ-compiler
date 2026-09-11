// The site's two canvas palettes, one per `data-theme`. Colours only: the
// drawing that reads them is in `circ-skins.mjs`, the wiring that hands both
// to the renderer in `circ-theme.mjs`. Kept apart so a test can import the
// keys without pulling sprite loading (which needs `new Image()`) along.

// Dark palette — the blog's color choices, with `background` set to
// global.css's --pane-bg dark (#0c0517) since the canvas is now
// transparent and the vector-fallback skins fill gate bodies with this
// value to blend with the parent pane.
export const colorsDark = {
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
export const colorsLight = {
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

/** Which palette the page's `data-theme` asks for. */
export const pickPalette = () =>
  document.documentElement.dataset.theme === 'dark' ? colorsDark : colorsLight;
