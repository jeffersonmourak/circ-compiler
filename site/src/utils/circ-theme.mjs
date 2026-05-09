// Themes for the embedded circ-renderer Canvas. Two palettes — one matched
// to the site's light mode, one to its dark mode — sharing the same shape
// expected by `renderCircuit({ theme })`. The active theme is selected at
// click-load time from the `data-theme` attribute on <html> so the canvas
// blends with the rest of the page; toggling the site theme later requires
// destroying and re-creating the canvas (handled in LiveCanvas.astro).
//
// The colors here are deliberately the SAME tokens as src/styles/global.css
// so the two stay visually coherent. If you change one, change the other.

import { defaultColors } from 'circ-renderer';

const fontFamily = '500 9px ui-monospace, SFMono-Regular, "JetBrains Mono", Menlo, Monaco, Consolas, monospace';

export const siteThemeLight = {
  colors: {
    ...defaultColors,
    background: '#fafaf6',     // pane-bg
    grid: '#e6e2d9',           // border
    stroke: '#1a1816',         // fg
    fillIdle: '#f5f1e8',       // code-bg
    fillActive: '#b85c1c',     // accent (warm orange)
    fillUndefined: '#c8c2b6',  // border-ish, slightly darker
    wireIdle: '#6b665f',       // muted
    wireActive: '#b85c1c',     // accent
    wireUndefined: '#cdc7bc',  // dim
    label: '#1a1816',          // fg
    labelMuted: '#6b665f',     // muted
    macro: '#d97a3a',          // accent-soft
  },
  font: fontFamily,
};

export const siteThemeDark = {
  colors: {
    ...defaultColors,
    background: '#1a1813',     // pane-bg dark
    grid: '#2a2822',           // border dark
    stroke: '#e8e4d8',         // fg dark
    fillIdle: '#1d1b15',       // code-bg dark
    fillActive: '#d97a3a',     // accent dark
    fillUndefined: '#3a3830',  // mid
    wireIdle: '#908a7c',       // muted dark
    wireActive: '#d97a3a',     // accent dark
    wireUndefined: '#3a3830',  // dim
    label: '#e8e4d8',          // fg dark
    labelMuted: '#908a7c',     // muted dark
    macro: '#e89860',          // accent-soft dark
  },
  font: fontFamily,
};

export const pickTheme = () =>
  document.documentElement.dataset.theme === 'dark' ? siteThemeDark : siteThemeLight;
