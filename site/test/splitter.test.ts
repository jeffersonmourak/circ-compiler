// The splitter's arithmetic. The DOM half is pointer capture and attribute
// writes, which no headless runner can exercise; everything a wrong number
// could break is here.
import { describe, expect, test } from 'bun:test';
import {
  ariaValues,
  clampRatio,
  effectiveBounds,
  ratioFromPointer,
  stepRatio,
  type SplitterBounds,
} from '../src/scripts/splitter.ts';

const opts = { minPanePx: 240, minRatio: 0.2, maxRatio: 0.8 };
const wide: SplitterBounds = { min: 0.2, max: 0.8 };

describe('splitter', () => {
  test('clampRatio holds the bounds and is idempotent', () => {
    expect(clampRatio(0.5, wide)).toBe(0.5);
    expect(clampRatio(0, wide)).toBe(0.2);
    expect(clampRatio(1, wide)).toBe(0.8);
    expect(clampRatio(clampRatio(9, wide), wide)).toBe(0.8);
    // A NaN ratio must not propagate into a CSS custom property.
    expect(clampRatio(Number.NaN, wide)).toBe(0.2);
  });

  test('effectiveBounds tightens by the pane minimum', () => {
    // 1200px: 240/1200 = 0.2, exactly the configured minimum, so nothing moves.
    expect(effectiveBounds(1200, opts)).toEqual({ min: 0.2, max: 0.8 });
    // 800px: 240/800 = 0.3, which is tighter than the configured 0.2.
    expect(effectiveBounds(800, opts)).toEqual({ min: 0.3, max: 0.7 });
  });

  test('a container too narrow for two minimums collapses to the midpoint', () => {
    // Below 2 × minPanePx there is no legal position at all.
    expect(effectiveBounds(400, opts)).toEqual({ min: 0.5, max: 0.5 });
    expect(effectiveBounds(479, opts)).toEqual({ min: 0.5, max: 0.5 });
    expect(effectiveBounds(480, opts)).toEqual({ min: 0.5, max: 0.5 });
    // …and the bounds never invert.
    for (const size of [0, 1, 100, 481, 600, 1000, 4000]) {
      const b = effectiveBounds(size, opts);
      expect(b.max).toBeGreaterThanOrEqual(b.min);
    }
  });

  test('effectiveBounds falls back to the configured range for a zero size', () => {
    // Before first layout the container measures 0; the configured range is a
    // better guess than a collapsed one.
    expect(effectiveBounds(0, opts)).toEqual({ min: 0.2, max: 0.8 });
    expect(effectiveBounds(Number.NaN, opts)).toEqual({ min: 0.2, max: 0.8 });
  });

  test('ratioFromPointer maps the container and clamps outside it', () => {
    expect(ratioFromPointer(100, 800, 500)).toBe(0.5);
    expect(ratioFromPointer(100, 800, 100)).toBe(0);
    expect(ratioFromPointer(100, 800, 900)).toBe(1);
    // Outside the rect, either side.
    expect(ratioFromPointer(100, 800, -50)).toBe(0);
    expect(ratioFromPointer(100, 800, 5000)).toBe(1);
    // A zero-width container yields the midpoint, never NaN.
    expect(ratioFromPointer(0, 0, 42)).toBe(0.5);
  });

  test('the keyboard contract, vertical', () => {
    const o = { orientation: 'vertical' as const, step: 0.02, coarseStep: 0.1, bounds: wide };
    expect(stepRatio(0.5, { key: 'ArrowLeft' }, o)).toBeCloseTo(0.48, 10);
    expect(stepRatio(0.5, { key: 'ArrowRight' }, o)).toBeCloseTo(0.52, 10);
    expect(stepRatio(0.5, { key: 'ArrowLeft', shiftKey: true }, o)).toBeCloseTo(0.4, 10);
    expect(stepRatio(0.5, { key: 'ArrowRight', shiftKey: true }, o)).toBeCloseTo(0.6, 10);
    expect(stepRatio(0.5, { key: 'Home' }, o)).toBe(0.2);
    expect(stepRatio(0.5, { key: 'End' }, o)).toBe(0.8);
    // The wrong axis is deliberately not ours, so the page still scrolls.
    expect(stepRatio(0.5, { key: 'ArrowUp' }, o)).toBeNull();
    expect(stepRatio(0.5, { key: 'ArrowDown' }, o)).toBeNull();
    for (const key of ['Enter', ' ', 'Escape', 'Tab', 'a', 'PageUp']) {
      expect(stepRatio(0.5, { key }, o)).toBeNull();
    }
  });

  test('the keyboard contract, horizontal', () => {
    const o = { orientation: 'horizontal' as const, step: 0.02, coarseStep: 0.1, bounds: wide };
    expect(stepRatio(0.5, { key: 'ArrowUp' }, o)).toBeCloseTo(0.48, 10);
    expect(stepRatio(0.5, { key: 'ArrowDown' }, o)).toBeCloseTo(0.52, 10);
    expect(stepRatio(0.5, { key: 'ArrowUp', shiftKey: true }, o)).toBeCloseTo(0.4, 10);
    expect(stepRatio(0.5, { key: 'ArrowLeft' }, o)).toBeNull();
    expect(stepRatio(0.5, { key: 'ArrowRight' }, o)).toBeNull();
    expect(stepRatio(0.5, { key: 'Home' }, o)).toBe(0.2);
  });

  test('every keyboard result lands inside the bounds', () => {
    const o = { orientation: 'vertical' as const, step: 0.02, coarseStep: 0.1, bounds: wide };
    for (const start of [0.2, 0.21, 0.5, 0.79, 0.8]) {
      for (const key of ['ArrowLeft', 'ArrowRight', 'Home', 'End']) {
        for (const shiftKey of [false, true]) {
          const next = stepRatio(start, { key, shiftKey }, o);
          expect(next).not.toBeNull();
          expect(next!).toBeGreaterThanOrEqual(wide.min);
          expect(next!).toBeLessThanOrEqual(wide.max);
        }
      }
    }
  });

  test('ariaValues reports integer percents and names both panes', () => {
    expect(ariaValues(0.5, wide, ['editor', 'output'])).toEqual({
      now: 50,
      min: 20,
      max: 80,
      text: 'editor 50%, output 50%',
    });
    expect(ariaValues(0.333, wide, ['editor', 'output']).now).toBe(33);
    expect(ariaValues(0.333, wide, ['editor', 'output']).text).toBe('editor 33%, output 67%');
    // A collapsed range still reports a coherent triple.
    expect(ariaValues(0.5, { min: 0.5, max: 0.5 }, ['a', 'b'])).toEqual({
      now: 50,
      min: 50,
      max: 50,
      text: 'a 50%, b 50%',
    });
  });
});
