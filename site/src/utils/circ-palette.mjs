// The site's two canvas palettes, one per `data-theme`. Colours only: the
// drawing that reads them is in `circ-skins.mjs`, the wiring that hands both
// to the renderer in `circ-theme.mjs`. Kept apart so a test can import the
// keys without pulling sprite loading (which needs `new Image()`) along.
//
// These are the design handoff's `nextSiteDark` / `nextSiteLight`
// (`DOCS/archive/design/canvas-theme/circ-site-theme.js`), taken verbatim. The language is the
// site's: orange is HIGH, green is LOW, blue is output, purple is macro,
// yellow is hover. Four keys are new against the palette the site shipped
// before — `surface` (the fill inside hollow pins, chips and shells),
// `spriteInk` (what LOW gate art is tinted to), and `wireBus` / `busLabel`,
// which the renderer always expected and the site never defined, so a bus
// badge fell back to the library's `#1971c2`. Two semantics moved: dark-mode
// `labelOnComponent` is the pane's ink rather than white, because the pin
// fill it sits on is now the bright HIGH orange (white on `#fd7e14` is
// 2.9:1, dark ink 7.6:1); and dark-mode `wireIdle` is dimmed so the wires
// carrying a signal are the brightest thing on the pane, not the idle ones.
// `grid` is gone: nothing ever read it.
//
// `background` is still the pane colour (`--pane-bg` in global.css) because
// the canvas is transparent and a few marks knock through to it.

export const colorsDark = {
  background: '#0c0517',
  surface: '#160b26',
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


/** @typedef {keyof typeof colorsDark} PaletteKey */

/** @type {Record<PaletteKey, string>} */
export const colorsLight = {
  background: '#f4eefb',
  surface: '#ffffff',
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


/** Which palette the page's `data-theme` asks for. */
export const pickPalette = () =>
  document.documentElement.dataset.theme === 'dark' ? colorsDark : colorsLight;
