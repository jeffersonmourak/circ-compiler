// Every `wasm:` a content entry names must be a real, committed artifact.
//
// This is the one claim the rest of the suite cannot make. The build copies
// `public/` verbatim without reading it, the bundle budget only walks emitted
// JS, and the island smoke test never clicks "Run interactively" — so a content
// entry naming an artifact that was never compiled, or one compiled locally and
// never staged, ships a button that 404s and no gate notices.
//
// It runs against the working tree rather than `dist/`, so it fails in the
// slice that introduced the reference rather than after a build.
import { describe, expect, test } from 'bun:test';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { examples } from '../src/content/examples.ts';

const SITE = resolve(import.meta.dir, '..');
const WASM_DIR = resolve(SITE, 'public', 'wasm');

/** The landing page's hero canvas, which names its artifact inline. */
const HERO = 'hero-half-adder.wasm';

/** Not content artifacts: the compiler module the playground runs, its
 *  manifest, and the tour byproducts `.gitignore` keeps out of the tree. */
const NOT_CONTENT = /^(?:libcirc\.wasm|libcirc\.manifest\.json|tour-\d+\.wasm)$/;

/** Files git actually tracks under public/wasm. An artifact that exists only
 *  on this machine is the failure this whole file is about. */
function trackedArtifacts(): Set<string> {
  const out = execFileSync('git', ['ls-files', '--', 'public/wasm'], { cwd: SITE, encoding: 'utf8' });
  return new Set(
    out
      .split('\n')
      .filter(Boolean)
      .map((p) => p.slice(p.lastIndexOf('/') + 1)),
  );
}

const declared = [...examples.flatMap((e) => (e.wasm ? [e.wasm] : [])), HERO];

describe('content artifacts', () => {
  test('every example declares one, named after its slug', () => {
    for (const e of examples) {
      expect(e.wasm).toBe(`${e.slug}.wasm`);
    }
    // No two entries may point at the same artifact — a copy-pasted `wasm:`
    // would otherwise draw the wrong circuit under the right title.
    expect(new Set(declared).size).toBe(declared.length);
  });

  test('every declared artifact exists and is a WebAssembly module', () => {
    for (const name of declared) {
      const path = resolve(WASM_DIR, name);
      expect(existsSync(path) ? name : `${name} (missing)`).toBe(name);
      const head = readFileSync(path).subarray(0, 8);
      // \0asm, version 1 — a truncated or failed compile fails here.
      expect(Array.from(head)).toEqual([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]);
    }
  });

  test('every declared artifact is committed, not just built locally', () => {
    const tracked = trackedArtifacts();
    for (const name of declared) {
      expect(tracked.has(name) ? name : `${name} (untracked)`).toBe(name);
    }
  });

  test('every repoPath names a fixture the shipped source matches byte for byte', () => {
    // The gallery prints this path as "Source:". If the fixture is edited and
    // the copy here is not, that link sends a reader to different code than the
    // card shows — a quiet lie no build step can see.
    const repoRoot = resolve(SITE, '..');
    for (const e of examples) {
      if (!e.repoPath) continue;
      const path = resolve(repoRoot, e.repoPath);
      expect(existsSync(path) ? e.repoPath : `${e.repoPath} (missing)`).toBe(e.repoPath);
      expect(readFileSync(path, 'utf8').trim()).toBe(e.source.trim());
    }
  });

  test('no committed artifact is orphaned', () => {
    // The reverse direction: removing an example must remove its artifact, or
    // the repo accumulates dead binaries nothing can reach.
    const orphans = [...trackedArtifacts()].filter((n) => !NOT_CONTENT.test(n) && !declared.includes(n));
    expect(orphans).toEqual([]);
  });
});
