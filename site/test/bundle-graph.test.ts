// Build-free companion to `bun run bundle`: nothing reachable from the base
// layout (`Base.astro`, `Nav.astro`, `Footer.astro`) may import CodeMirror.
// Runs in every slice, before any `dist/` exists, so an editor leaking into
// the base bundle of `/`, `/reference/*` or `/download` fails here first.
//
// The walk parses `.astro` frontmatter and every `<script>` block (PostHog's
// script imports `../utils/sillyname`), follows relative specifiers through
// `.ts` / `.mjs` / `.js` / `.astro` / `/index.ts`, skips `.css`, and collects
// bare specifiers (`astro:content`, `@codemirror/view`, …) without resolving
// them — those are what the assertion is about.
import { describe, expect, test } from 'bun:test';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';

const SITE = resolve(import.meta.dir, '..');

/** Roots per decision 14(b). Site-relative paths. */
export const ROOTS = ['src/layouts/Base.astro', 'src/components/Nav.astro', 'src/components/Footer.astro'];

export const FORBIDDEN = /^(?:@codemirror\/|@lezer\/|codemirror$)/;

export interface SourceGraph {
  /** Site-relative paths of every source file reached. */
  visited: Set<string>;
  /** Bare (non-relative) specifiers seen anywhere in the graph, e.g. 'astro:content'. */
  bare: Set<string>;
  /** Relative specifiers that could not be resolved (reported, not failed). */
  unresolved: string[];
}

const STATIC_IMPORT =
  /(?:^|[;}\n])\s*import\s*(?:(?:[\w$]+\s*,\s*)?(?:\*\s*as\s+[\w$]+|\{[^}]*\}|[\w$]+)\s*from\s*)?["']([^"']+)["']/g;
const TYPE_IMPORT = /(?:^|[;}\n])\s*import\s+type\s+(?:\*\s*as\s+[\w$]+|\{[^}]*\}|[\w$]+)\s*from\s*["']([^"']+)["']/g;
const REEXPORT = /(?:^|[;}\n])\s*export\s*(?:type\s*)?(?:\*|\{[^}]*\})\s*from\s*["']([^"']+)["']/g;
const DYNAMIC = /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g;
const FRONTMATTER = /^---\r?\n([\s\S]*?)\r?\n---/;
const SCRIPT_BLOCK = /<script\b[^>]*>([\s\S]*?)<\/script>/g;

function all(re: RegExp, text: string): string[] {
  const out: string[] = [];
  re.lastIndex = 0;
  for (let m = re.exec(text); m; m = re.exec(text)) out.push(m[1]);
  return out;
}

/** The JS/TS regions of a file: the whole file, or an .astro file's fence and script blocks. */
export function codeRegions(path: string, text: string): string[] {
  if (!path.endsWith('.astro')) return [text];
  const regions: string[] = [];
  const fm = FRONTMATTER.exec(text);
  if (fm) regions.push(fm[1]);
  regions.push(...all(SCRIPT_BLOCK, text));
  return regions;
}

export function specifiersOf(path: string, text: string): string[] {
  const specs: string[] = [];
  for (const region of codeRegions(path, text)) {
    specs.push(...all(STATIC_IMPORT, region), ...all(TYPE_IMPORT, region), ...all(REEXPORT, region), ...all(DYNAMIC, region));
  }
  return specs;
}

const CANDIDATES = ['', '.ts', '.mjs', '.js', '.astro', '/index.ts'];

function resolveRelative(fromAbs: string, spec: string): string | null {
  const base = resolve(dirname(fromAbs), spec);
  for (const suffix of CANDIDATES) {
    const candidate = base + suffix;
    if (existsSync(candidate) && statSync(candidate).isFile()) return candidate;
  }
  return null;
}

export function walkSources(roots: string[], siteDir = SITE): SourceGraph {
  const visited = new Set<string>();
  const bare = new Set<string>();
  const unresolved: string[] = [];
  const queue = roots.map((r) => resolve(siteDir, r));
  while (queue.length) {
    const abs = queue.shift()!;
    const rel = relative(siteDir, abs);
    if (visited.has(rel)) continue;
    visited.add(rel);
    const text = readFileSync(abs, 'utf8');
    for (const spec of specifiersOf(rel, text)) {
      const isRelative = spec.startsWith('./') || spec.startsWith('../') || spec.startsWith('/');
      if (!isRelative) {
        bare.add(spec);
        continue;
      }
      if (spec.endsWith('.css')) continue;
      const target = spec.startsWith('/') ? resolve(siteDir, spec.slice(1)) : resolveRelative(abs, spec);
      if (!target) {
        unresolved.push(`${rel}: ${spec}`);
        continue;
      }
      queue.push(target);
    }
  }
  return { visited, bare, unresolved };
}

describe('bundle graph', () => {
  const graph = walkSources(ROOTS);

  test('nothing in the base layout imports CodeMirror', () => {
    const leaks = [...graph.bare].filter((s) => FORBIDDEN.test(s));
    expect(leaks).toEqual([]);
  });

  test('the walk is non-vacuous', () => {
    expect(graph.visited.size).toBeGreaterThanOrEqual(6);
    expect(graph.visited.has('src/utils/url.ts')).toBe(true); // frontmatter parsed
    expect(graph.visited.has('src/utils/sillyname.ts')).toBe(true); // an .astro <script> block parsed
    expect(graph.unresolved).toEqual([]);
  });

  test('the scanner sees every import form the walk relies on', () => {
    const sample = [
      `---`,
      `import Nav from '../components/Nav.astro';`,
      `import { url } from "../utils/url.ts";`,
      `import '../styles/global.css';`,
      `import type { Foo } from './types';`,
      `export * from './re';`,
      `---`,
      `<script>`,
      `  import { generateSillyName } from '../utils/sillyname';`,
      `  const m = await import('../utils/lazy.ts');`,
      `</script>`,
      `<script is:inline>window.x = 1;</script>`,
    ].join('\n');
    expect(specifiersOf('x.astro', sample).sort()).toEqual(
      ['../components/Nav.astro', '../styles/global.css', '../utils/lazy.ts', '../utils/sillyname', '../utils/url.ts', './re', './types'].sort(),
    );
  });
});
