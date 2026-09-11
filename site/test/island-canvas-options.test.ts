// The two canvas islands lay out and pad for the value chip.
//
// The chip above a pin reaches 1.34 cells over its box (pill height 0.92,
// seated 0.5 above a circle of radius 1.42 in a 3-row box). At the
// renderer's default row gutter of one it lands on the box above; at the
// default padding of 16px at cell 14 a top-row pin's chip is clipped by
// three pixels. Both islands must ask for two rows and 1.5 cells, and this
// is what keeps them asking.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const src = (rel: string) => readFileSync(resolve(import.meta.dir, '..', 'src', 'components', rel), 'utf8');

describe('island canvas options', () => {
  test('both islands lay out with a row gutter of two', () => {
    for (const [name, text] of [['LiveCanvas', src('LiveCanvas.astro')], ['Playground', src('Playground.astro')]] as const) {
      expect(`${name}: ${/layoutOptions:\s*\{\s*rowGutter:\s*2\s*\}/.test(text)}`).toBe(`${name}: true`);
    }
  });

  test('both islands pad the canvas by 1.5 cells', () => {
    const gallery = src('LiveCanvas.astro');
    // The prop default, and the script's fallback when the attribute is absent.
    expect(gallery).toMatch(/padding = Math\.ceil\(cell \* 1\.5\)/);
    expect(gallery).toMatch(/circPadding \?\? String\(Math\.ceil\(cell \* 1\.5\)\)/);
    const playground = src('Playground.astro');
    expect(playground).toMatch(/padding:\s*Math\.ceil\(14 \* 1\.5\)/);
    expect(playground).not.toMatch(/padding:\s*16\b/);
  });
});
