// Decision 1 (`DOCS/PLANS_PROMPT.md`): six hand-picked CodeMirror packages,
// exact-pinned, no `codemirror` meta-package and no autocomplete/search. A
// caret would let a minor bump land an API change under a phase plan whose
// every CodeMirror name was verified against these exact versions.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const siteDir = resolve(import.meta.dir, '..');
const pkg = JSON.parse(readFileSync(resolve(siteDir, 'package.json'), 'utf8')) as {
  dependencies?: Record<string, string>;
  devDependencies?: Record<string, string>;
};
const lock = readFileSync(resolve(siteDir, 'bun.lock'), 'utf8');

const PINNED = [
  '@codemirror/state',
  '@codemirror/view',
  '@codemirror/language',
  '@codemirror/commands',
  '@codemirror/lint',
  '@lezer/highlight',
] as const;

/** The packages decision 1 rules out by name. */
const FORBIDDEN = ['codemirror', '@codemirror/autocomplete', '@codemirror/search'] as const;

describe('codemirror pin', () => {
  test('codemirror packages are pinned exactly', () => {
    // A bare x.y.z: no `^`, no `~`, no range, no tag, no git specifier.
    const bare = /^\d+\.\d+\.\d+$/;
    // Filtering rather than asserting in a loop so a failure names the package.
    expect(PINNED.filter((name) => !bare.test(pkg.dependencies?.[name] ?? ''))).toEqual([]);
    // `bun.lock`'s packages map resolves each one at that same version.
    expect(
      PINNED.filter((name) => !lock.includes(`"${name}": ["${name}@${pkg.dependencies![name]}"`)),
    ).toEqual([]);
  });

  test('no meta-package, autocomplete or search is installed', () => {
    for (const name of FORBIDDEN) {
      expect(pkg.dependencies ?? {}).not.toContainKey(name);
      expect(pkg.devDependencies ?? {}).not.toContainKey(name);
    }
  });
});
