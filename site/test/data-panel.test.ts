import { describe, expect, test } from 'bun:test';
import { defaultPos, clampPanel, positionFromDrag, crossedThreshold } from '../src/scripts/data-panel.ts';

describe('Data panel geometry', () => {
  const region = { width: 900, height: 600 };
  const card = { width: 312, height: 400 };
  test('anchors below the toolbar, sixteen pixels from the right', () => {
    expect(defaultPos(region)).toEqual({ x: 572, y: 52 });
  });
  test('clamps each edge, and pins an oversized card to the origin', () => {
    const pos = { x: 100, y: 80 };
    expect(clampPanel(pos, card, region)).toEqual(pos);
    expect(clampPanel({ x: 700, y: 500 }, card, region)).toEqual({ x: 588, y: 200 });
    expect(clampPanel({ x: -40, y: -10 }, card, region)).toEqual({ x: 0, y: 0 });
    expect(clampPanel(pos, card, { width: 200, height: 300 })).toEqual({ x: 0, y: 0 });
    expect(pos).toEqual({ x: 100, y: 80 });
  });
  test('a resize borrows space without changing the saved intent', () => {
    const pos = { x: 500, y: 100 };
    expect(clampPanel(pos, card, { width: 400, height: 450 })).toEqual({ x: 88, y: 50 });
    expect(clampPanel(pos, card, region)).toEqual(pos);
  });
  test('a drag adds its delta only after the four-pixel threshold', () => {
    expect(positionFromDrag({ x: 100, y: 100 }, { x: 10, y: 10 }, { x: 25, y: 5 })).toEqual({ x: 115, y: 95 });
    expect(crossedThreshold({ x: 0, y: 0 }, { x: 3, y: 3 })).toBe(false);
    expect(crossedThreshold({ x: 0, y: 0 }, { x: 4, y: 0 })).toBe(true);
    expect(crossedThreshold({ x: 0, y: 0 }, { x: 0, y: -4 })).toBe(true);
  });
});
