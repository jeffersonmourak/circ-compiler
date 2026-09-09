// A source-text guard, not an import: `circ-theme.mjs` calls `loadAssets()` at
// module scope and that needs `new Image()`, which `bun test` does not have.
//
// The property being guarded is easy to lose and invisible until someone
// points at a gate: every skin the site registers must react to `hovered`, or
// a host highlight draws nothing for that component kind.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const source = readFileSync(resolve(import.meta.dir, '..', 'src', 'utils', 'circ-theme.mjs'), 'utf8');

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
  const start = source.indexOf('const skins = {');
  const end = source.indexOf('};', start);
  const block = source.slice(start, end);
  return [...block.matchAll(/:\s*(draw[A-Za-z]+)/g)].map((m) => m[1]);
}

describe('circ-theme hover', () => {
  test('the site registers the six skins this guard covers', () => {
    expect(registeredSkins().sort()).toEqual(
      ['drawAnd', 'drawInputPin', 'drawLed', 'drawNot', 'drawOutputPin', 'drawSubcircuit'].sort(),
    );
  });

  test('every registered skin reacts to hovered', () => {
    for (const name of registeredSkins()) {
      const body = skinBody(name);
      // Destructured from the skin context…
      expect(body).toMatch(/\(\{[^}]*\bhovered\b[^}]*\}\)/);
      // …and actually branched on.
      expect(body).toMatch(/if \(hovered\)/);
      // …using the theme's own hover colour, not a literal.
      expect(body + source).toContain('theme.colors.inputHover');
    }
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
    expect([...source.matchAll(/inputHover:/g)]).toHaveLength(2);
  });

  test('rom and ram are the known gap', () => {
    // TOPOLOGY_KIND_OF maps them and a cursor on one reaches setHighlight, but
    // the site registers no Rom/Ram skin, so the package's own drawMemory runs
    // and it never reads `hovered`. Pinned so it is a decision, not a surprise.
    expect(registeredSkins()).not.toContain('drawRom');
    expect(registeredSkins()).not.toContain('drawMemory');
    expect(source).not.toContain('ComponentKind.Rom');
  });
});
