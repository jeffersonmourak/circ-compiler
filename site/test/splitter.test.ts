// The splitter's arithmetic. The DOM half is pointer capture and attribute
// writes, which no headless runner can exercise; everything a wrong number
// could break is here.
import { describe, expect, test } from 'bun:test';
import { Window } from 'happy-dom';
import {
  ariaValues,
  clampPx,
  clampRatio,
  createSplitter,
  effectiveBounds,
  pxBounds,
  pxFromPointer,
  ratioFromPointer,
  stepPx,
  stepRatio,
  type SplitterBounds,
} from '../src/scripts/splitter.ts';

const opts = { minPanePx: 240, minRatio: 0.2, maxRatio: 0.8 };
const wide: SplitterBounds = { min: 0.2, max: 0.8 };

describe('splitter', () => {
  test('each pane can have its own minimum', () => {
    expect(effectiveBounds(600, { minPanePx: [200, 160], minRatio: 0, maxRatio: 1 })).toEqual({ min: 200 / 600, max: 1 - 160 / 600 });
    expect(effectiveBounds(300, { minPanePx: [200, 160], minRatio: 0, maxRatio: 1 })).toEqual({ min: 0.5, max: 0.5 });
  });
  test('the lower pane grows when the divider moves up, and resize never commits', () => {
    const window = new Window();
    const container = window.document.createElement('div') as unknown as HTMLElement;
    const separator = window.document.createElement('div') as unknown as HTMLElement;
    let size = 800;
    const commits: number[] = [];
    const handle = createSplitter({ container, separator, property: '--height', unit: 'px', pane: 'second', orientation: 'horizontal', minPx: 160, maxReservePx: 200, initial: 320, measure: () => ({ start: 100, size }), labels: ['bench', 'drawer'], onCommit: (v) => commits.push(v) });
    expect(container.style.getPropertyValue('--height')).toBe('320px');
    expect(separator.getAttribute('aria-valuetext')).toBe('drawer 40%, bench 60%');
    size = 400; handle.refresh();
    expect(container.style.getPropertyValue('--height')).toBe('200px');
    expect(handle.intent).toBe(320);
    expect(commits).toEqual([]);
    size = 800; handle.refresh();
    separator.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'ArrowUp' }) as unknown as Event);
    expect(handle.intent).toBe(336);
    expect(commits).toEqual([336]);
    expect(pxFromPointer(100, 580, 800, 'second')).toBe(320);
    expect(pxFromPointer(100, 1000, 800, 'second')).toBe(0);
    handle.destroy();
  });
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

  // The pixel unit: the bench's source column.
  const pxOpts = { minPx: 320, maxReservePx: 480 };

  test('clampPx holds the bounds and rounds to whole pixels', () => {
    const b: SplitterBounds = { min: 320, max: 960 };
    expect(clampPx(100, b)).toBe(320);
    expect(clampPx(2000, b)).toBe(960);
    expect(clampPx(480.4, b)).toBe(480);
    // A NaN width must not reach a CSS custom property.
    expect(clampPx(Number.NaN, b)).toBe(320);
  });

  test('pixel bounds reserve the far pane', () => {
    // 1440 wide: the source may grow until 480px is left for the canvas.
    expect(pxBounds(1440, pxOpts)).toEqual({ min: 320, max: 960 });
    // Too narrow for both minimums: the range collapses to the source's, so
    // the canvas is what gives, and the bounds never invert.
    expect(pxBounds(700, pxOpts)).toEqual({ min: 320, max: 320 });
    expect(pxBounds(800, pxOpts)).toEqual({ min: 320, max: 320 });
    expect(pxBounds(801, pxOpts)).toEqual({ min: 320, max: 321 });
    // Nothing laid out yet: the intent stands, until the observer sees a size.
    expect(pxBounds(0, pxOpts)).toEqual({ min: 320, max: Number.POSITIVE_INFINITY });
    expect(pxBounds(Number.NaN, pxOpts)).toEqual({ min: 320, max: Number.POSITIVE_INFINITY });
    expect(clampPx(480, pxBounds(0, pxOpts))).toBe(480);
  });

  test('pxFromPointer is the distance from the near edge, never negative', () => {
    expect(pxFromPointer(100, 580)).toBe(480);
    expect(pxFromPointer(100, 40)).toBe(0);
    expect(pxFromPointer(100, Number.NaN)).toBe(0);
  });

  test('the keyboard contract, pixels', () => {
    const o = { orientation: 'vertical' as const, stepPx: 16, coarseStepPx: 64, bounds: { min: 320, max: 960 } };
    expect(stepPx(480, { key: 'ArrowRight' }, o)).toBe(496);
    expect(stepPx(480, { key: 'ArrowRight', shiftKey: true }, o)).toBe(544);
    expect(stepPx(480, { key: 'ArrowLeft' }, o)).toBe(464);
    expect(stepPx(330, { key: 'ArrowLeft', shiftKey: true }, o)).toBe(320);
    expect(stepPx(480, { key: 'Home' }, o)).toBe(320);
    expect(stepPx(480, { key: 'End' }, o)).toBe(960);
    // The wrong axis keeps its browser meaning.
    expect(stepPx(480, { key: 'ArrowUp' }, o)).toBeNull();
    expect(stepPx(480, { key: 'a' }, o)).toBeNull();
  });
});
