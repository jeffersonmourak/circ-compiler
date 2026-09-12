import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { documentKeys } from '../src/content/agent-reference.ts';
import { tour } from '../src/content/tour.ts';

const root = resolve(import.meta.dir, '..');
describe('agent reference inputs', () => {
  test('published documents and tour identities are explicit', () => {
    for (const key of documentKeys) expect(readFileSync(resolve(root, '..', 'DOCS', `${key}.md`), 'utf8')).toContain('#');
    expect(new Set(tour.map((step) => step.slug)).size).toBe(tour.length);
  });
  test('diagnostic registry and documented catalogue agree', () => {
    const codes = [...readFileSync(resolve(root, '..', 'lib/validator/codes.zig'), 'utf8').matchAll(/\.code = \.([EW]\d{3})/g)].map((match) => match[1]);
    const documentation = readFileSync(resolve(root, '..', 'DOCS/circuit-format.md'), 'utf8');
    for (const code of codes) expect(documentation).toContain(`| ${code} |`);
  });
});
