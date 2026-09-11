// A source-text guard over the site's skins and palettes.
//
// The property being guarded is easy to lose and invisible until someone
// points at a gate: the ring around a hovered or highlighted component is
// drawn by the canvas through one theme hook, for every kind, and no skin
// draws its own — or a kind gets two rings, or none. What the skins draw is
// pinned by `circ-skins.test.ts`; this file guards how they are put together.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const utils = resolve(import.meta.dir, '..', 'src', 'utils');
const source = readFileSync(resolve(utils, 'circ-skins.mjs'), 'utf8');
const palette = readFileSync(resolve(utils, 'circ-palette.mjs'), 'utf8');

/** The body of a top-level `const <name> = (…) => {…}` function. */
function skinBody(name: string): string {
  const start = source.indexOf(`const ${name} = (`);
  expect(start).toBeGreaterThan(-1);
  const end = source.indexOf('\n};\n', start);
  expect(end).toBeGreaterThan(start);
  return source.slice(start, end);
}

/** The skins the site registers, from the object literal itself. */
function registeredSkins(): string[] {
  const start = source.indexOf('export const skins = {');
  const end = source.indexOf('};', start);
  const block = source.slice(start, end);
  return [...block.matchAll(/:\s*(draw[A-Za-z]+)/g)].map((m) => m[1]);
}

describe('circ-theme hover', () => {
  test('the site registers a skin for every kind the canvas can draw', () => {
    // Slice, concat, rom and ram used to fall through to the package's
    // defaults and render in a foreign visual language beside the sprites.
    expect([...new Set(registeredSkins())].sort()).toEqual(
      [
        'drawAnd', 'drawConcat', 'drawInputPin', 'drawLed', 'drawMemory',
        'drawNot', 'drawOutputPin', 'drawSlice', 'drawSubcircuit',
      ].sort(),
    );
    expect(source).toContain('[ComponentKind.Rom]: drawMemory');
    expect(source).toContain('[ComponentKind.Ram]: drawMemory');
  });

  test('the ring is drawn once, by the canvas, through the highlight hook', () => {
    // The theme hands the canvas its ring; no skin draws its own. Before
    // this, five skins each drew a ring and four kinds drew none, and a
    // reader pointing at a rom in the editor saw nothing light up.
    expect(source).toMatch(/highlight:\s*\(\{[^}]*\}\)\s*=>\s*drawHoverRing\(/);
    for (const name of registeredSkins()) {
      expect(`${name}: ${skinBody(name).includes('drawHoverRing(')}`).toBe(`${name}: false`);
    }
    // Exactly one caller of the helper in the whole file: the hook.
    expect([...source.matchAll(/drawHoverRing\(ctx/g)]).toHaveLength(1);
  });

  test('a skin may still react to hovered on its own, and the input pin does', () => {
    // The ring is uniform; a pin changing its own fill is an extra the canvas
    // leaves open. Both paths stay, which is what kept this skin unchanged.
    const body = skinBody('drawInputPin');
    expect(body).toMatch(/if \(hovered\)/);
    expect(body).toContain('theme.colors.inputHover');
  });

  test('the ring helper uses the hover colour and restores the context', () => {
    const helper = skinBody('drawHoverRing');
    expect(helper).toContain('theme.colors.inputHover');
    // A skin that leaves stroke state behind corrupts everything drawn after.
    expect(helper).toContain('ctx.save()');
    expect(helper).toContain('ctx.restore()');
  });

  test('both palettes define the hover colour the ring reads', () => {
    // One per theme; the guard is that neither is missing.
    expect([...palette.matchAll(/inputHover:/g)]).toHaveLength(2);
  });

  test('a memory is labelled by the renderer, so the canvas and the preview agree', () => {
    // `rom code[8,4]` comes from one function in one place.
    expect(source).toMatch(/^import \{[^}]*\bmemoryLabel\b[^}]*\} from 'circ-renderer';$/m);
    expect(skinBody('drawMemory')).toContain('memoryLabel(');
  });
});
