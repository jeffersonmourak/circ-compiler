// The zoom line's words, and the renderer's bounds they are asked about.
import { describe, expect, test } from 'bun:test';
import { DEFAULT_ZOOM } from 'circ-renderer';
import { formatZoom, zoomLine } from '../src/scripts/zoom-label.ts';

describe('zoom label', () => {
  test('formatZoom rounds to a whole percent', () => {
    expect(formatZoom(1)).toBe('100%');
    expect(formatZoom(0.25)).toBe('25%');
    expect(formatZoom(8)).toBe('800%');
    expect(formatZoom(1.004)).toBe('100%');
    expect(formatZoom(1.006)).toBe('101%');
    expect(formatZoom(0.333)).toBe('33%');
    // Nothing a canvas reports, but nothing a label should choke on either.
    expect(formatZoom(Number.NaN)).toBe('100%');
    expect(formatZoom(0)).toBe('100%');
  });

  test("formatZoom's bounds are the renderer's", () => {
    expect(formatZoom(DEFAULT_ZOOM.min)).toBe('25%');
    expect(formatZoom(DEFAULT_ZOOM.max)).toBe('800%');
  });

  test("zoomLine spells the design's line", () => {
    expect(zoomLine(1, 14)).toBe('cell 14 · 100% · fit');
    expect(zoomLine(2.5, 14)).toBe('cell 14 · 250% · fit');
  });
});
