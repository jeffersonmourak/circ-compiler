// The zoom line's words (design file, board 2a: `cell 14 · fit`, bottom right
// of the canvas region; decision 9 adds the zoom percentage as the reset).
//
// Free of the renderer on purpose: this rides in the eager bundle, and the
// renderer stays behind its dynamic import. The bounds it is asked about are
// asserted against the renderer's `DEFAULT_ZOOM` in the test, not here.

/** `100%` at 1, rounded to the nearest whole percent. */
export function formatZoom(scale: number): string {
  if (!Number.isFinite(scale) || scale <= 0) return '100%';
  return `${Math.round(scale * 100)}%`;
}

/** The whole line, for a reader of the spec; the island writes the three
 *  pieces into their own spans (the percentage and `fit` are buttons). */
export function zoomLine(scale: number, cell: number): string {
  return `cell ${cell} · ${formatZoom(scale)} · fit`;
}
