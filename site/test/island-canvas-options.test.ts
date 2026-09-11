// The two canvas islands lay out and pad for the value chip.
//
// The chip above a pin reaches 1.42 cells over its box, stroke included
// (pill height 0.92, seated 0.5 above a circle of radius 1.42 in a 3-row
// box). At the renderer's default row gutter of one it lands on the box
// above; at 1.5 cells of padding a top-row pin's chip fit to the pixel and
// the reader saw it cut. Both islands must ask for two rows and two cells,
// and this is what keeps them asking.
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

  test('both islands pad the canvas by two cells', () => {
    const gallery = src('LiveCanvas.astro');
    // The prop default, and the script's fallback when the attribute is absent.
    expect(gallery).toMatch(/padding = Math\.ceil\(cell \* 2\)/);
    expect(gallery).toMatch(/circPadding \?\? String\(Math\.ceil\(cell \* 2\)\)/);
    const playground = src('Playground.astro');
    expect(playground).toMatch(/padding:\s*Math\.ceil\(14 \* 2\)/);
    expect(playground).not.toMatch(/padding:\s*16\b/);
  });
});
