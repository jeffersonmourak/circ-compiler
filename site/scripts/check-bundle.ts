// `bun run bundle`: the per-page JavaScript budget gate, run after
// `bun --bun run build`. Walks every `dist/**/*.html`, seeds each page's
// eager module graph from its `<script type="module" src>` and
// `<link rel="modulepreload" href>` tags, follows the built chunks' static
// imports transitively, sums raw and gzip bytes, prints one row per route,
// compares against the committed `bundle-budget.json` and exits 1 over budget.
//
// gzip is summed PER FILE, not over a concatenation: each chunk is a separate
// HTTP response, so per-file gzip is what the network actually transfers.
// Chunks reachable only through `import()` are reported (with their own
// bytes) and never gated; `<script>` blocks without `src` are reported as one
// byte count per page and never gated.
//
// Astro renders pages itself and emits no `modulepreload` tags for a static
// build, so the chunk scanner below is the walker's only way past the entry
// script. That makes non-vacuity a hard condition: if `/playground` reaches
// no chunk beyond its seeds the scanner is not matching the emitted syntax,
// and a budget measured over seeds alone is not a budget.
import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, normalize, relative, resolve, sep } from 'node:path';

export interface Ceiling {
  /** Sum of raw bytes across the page's eager module graph. Omit to gate gzip only. */
  raw?: number;
  /** Sum of per-file `Bun.gzipSync(bytes, { level: 9 }).length`. Always present. */
  gzip: number;
}

export interface Measurement {
  files: number;
  raw: number;
  gzip: number;
}

export interface BundleBudget {
  /** Envelope version; bump only alongside a reader change in this script. */
  version: 1;
  $comment?: string;
  /** Applies to any route without a `routes` entry. */
  default: Ceiling;
  /** Per-route overrides, keyed by the route derived from the dist path. */
  routes: Record<string, Ceiling>;
  /** Measured once and committed. Informational: never gates, never auto-updated. */
  baseline: Record<string, Measurement>;
}

/** One page as the walker sees it. */
export interface PageGraph {
  /** `index.html` → `/`, `tour/index.html` → `/tour`. */
  route: string;
  /** dist-relative paths of every eagerly-loaded module, in discovery order. */
  files: string[];
  raw: number;
  gzip: number;
  /** Chunks reachable only through `import()`; reported, never gated. */
  lazy: { file: string; raw: number; gzip: number }[];
  /** Bytes of `<script>` blocks with no `src`. Reported, never gated. */
  inlineBytes: number;
  /** Specifiers that escaped `dist/` or did not exist. */
  warnings: string[];
}

// A static, namespace or side-effect import, minified or not. Astro's client
// build is esbuild-minified, so `import{a as b}from"./x.js"` and
// `import*as n from"./x.js"` have no space after `import` and must still
// match. `import(` and `import.meta` cannot match: neither `(` nor `.` starts
// a binding, and neither is a quote.
const STATIC_IMPORT =
  /(?:^|[;}\n])\s*import\s*(?:(?:[\w$]+\s*,\s*)?(?:\*\s*as\s+[\w$]+|\{[^}]*\}|[\w$]+)\s*from\s*)?["']([^"']+)["']/g;
const REEXPORT = /(?:^|[;}\n])\s*export\s*(?:\*|\{[^}]*\})\s*from\s*["']([^"']+)["']/g;
const DYNAMIC = /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g;

const SCRIPT_SRC = /<script\b[^>]*\btype\s*=\s*["']module["'][^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>/g;
const SCRIPT_SRC_REV = /<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*\btype\s*=\s*["']module["'][^>]*>/g;
const MODULEPRELOAD = /<link\b[^>]*\brel\s*=\s*["']modulepreload["'][^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>/g;
const MODULEPRELOAD_REV = /<link\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*\brel\s*=\s*["']modulepreload["'][^>]*>/g;
const INLINE_SCRIPT = /<script\b(?![^>]*\bsrc\s*=)[^>]*>([\s\S]*?)<\/script>/g;

function all(re: RegExp, text: string): string[] {
  const out: string[] = [];
  re.lastIndex = 0;
  for (let m = re.exec(text); m; m = re.exec(text)) out.push(m[1]);
  return out;
}

/** `/base/` with exactly one trailing slash, the way Base.astro normalises it. */
export function normalizeBase(base: string | undefined): string {
  const b = (base ?? '/').replace(/\/?$/, '/');
  return b.startsWith('/') ? b : `/${b}`;
}

/** Map a `src`/`href` to a dist-relative path, stripping the base path. */
export function distPathOf(url: string, base: string): string | null {
  if (/^[a-z]+:/i.test(url) || url.startsWith('//')) return null; // external
  let p = url.split(/[?#]/)[0];
  if (p.startsWith(base)) p = p.slice(base.length);
  else if (p.startsWith('/')) p = p.slice(1);
  return p;
}

export function routeOf(htmlRel: string): string {
  const posix = htmlRel.split(sep).join('/');
  if (posix === 'index.html') return '/';
  return '/' + posix.replace(/\/index\.html$/, '').replace(/\.html$/, '');
}

interface Sized { raw: number; gzip: number }

export function walkPage(distDir: string, htmlRel: string, base: string): PageGraph {
  const html = readFileSync(join(distDir, htmlRel), 'utf8');
  const seeds = [
    ...all(SCRIPT_SRC, html),
    ...all(SCRIPT_SRC_REV, html),
    ...all(MODULEPRELOAD, html),
    ...all(MODULEPRELOAD_REV, html),
  ]
    .map((u) => distPathOf(u, base))
    .filter((p): p is string => p !== null);

  const files: string[] = [];
  const seen = new Set<string>();
  const lazySeen = new Set<string>();
  const lazy: PageGraph['lazy'] = [];
  const warnings: string[] = [];
  const sizes = new Map<string, Sized>();

  const sizeOf = (rel: string): Sized => {
    let s = sizes.get(rel);
    if (!s) {
      const bytes = readFileSync(join(distDir, rel));
      s = { raw: bytes.length, gzip: Bun.gzipSync(bytes, { level: 9 }).length };
      sizes.set(rel, s);
    }
    return s;
  };

  const resolveSpec = (fromRel: string, spec: string): string | null => {
    const abs = spec.startsWith('/')
      ? resolve(distDir, spec.slice(1))
      : resolve(distDir, dirname(fromRel), spec);
    const rel = relative(distDir, abs);
    if (rel.startsWith('..') || rel === '') {
      warnings.push(`${fromRel}: '${spec}' escapes dist/`);
      return null;
    }
    if (!existsSync(abs) || !statSync(abs).isFile()) {
      warnings.push(`${fromRel}: '${spec}' does not exist`);
      return null;
    }
    return normalize(rel);
  };

  const queue: string[] = [];
  for (const seed of seeds) {
    const abs = join(distDir, seed);
    if (!existsSync(abs)) {
      warnings.push(`seed '${seed}' does not exist`);
      continue;
    }
    queue.push(normalize(seed));
  }
  while (queue.length) {
    const rel = queue.shift()!;
    if (seen.has(rel)) continue;
    seen.add(rel);
    files.push(rel);
    const text = readFileSync(join(distDir, rel), 'utf8');
    for (const spec of [...all(STATIC_IMPORT, text), ...all(REEXPORT, text)]) {
      const target = resolveSpec(rel, spec);
      if (target && !seen.has(target)) queue.push(target);
    }
    for (const spec of all(DYNAMIC, text)) {
      const target = resolveSpec(rel, spec);
      if (target && !lazySeen.has(target)) {
        lazySeen.add(target);
        lazy.push({ file: target, ...sizeOf(target) });
      }
    }
  }

  let raw = 0;
  let gzip = 0;
  for (const f of files) {
    const s = sizeOf(f);
    raw += s.raw;
    gzip += s.gzip;
  }
  const inlineBytes = all(INLINE_SCRIPT, html).reduce((n, body) => n + Buffer.byteLength(body, 'utf8'), 0);
  return { route: routeOf(htmlRel), files, raw, gzip, lazy, inlineBytes, warnings };
}

export function ceilingFor(budget: BundleBudget, route: string): Ceiling {
  return budget.routes[route] ?? budget.default;
}

export function overBudget(page: PageGraph, ceiling: Ceiling): string[] {
  const out: string[] = [];
  if (page.gzip > ceiling.gzip) out.push(`gzip ${page.gzip} > ${ceiling.gzip}`);
  if (ceiling.raw !== undefined && page.raw > ceiling.raw) out.push(`raw ${page.raw} > ${ceiling.raw}`);
  return out;
}

const kb = (n: number) => (n / 1024).toFixed(1).padStart(7) + ' KB';

function main(): number {
  const siteDir = resolve(import.meta.dir, '..');
  const distDir = resolve(siteDir, 'dist');
  const budgetPath = resolve(siteDir, 'bundle-budget.json');
  if (!existsSync(distDir)) {
    console.error(`no dist/ at ${distDir}; run \`bun --bun run build\` first`);
    return 1;
  }
  const budget = JSON.parse(readFileSync(budgetPath, 'utf8')) as BundleBudget;
  if (budget.version !== 1) {
    console.error(`bundle-budget.json version ${String(budget.version)} is not 1`);
    return 1;
  }
  const base = normalizeBase(process.env.BASE_PATH);

  const htmls = [...new Bun.Glob('**/*.html').scanSync({ cwd: distDir })].sort();
  const pages = htmls.map((h) => walkPage(distDir, h, base));

  const failures: string[] = [];
  console.log('route                          files      raw         gzip     ceiling(gzip)  status');
  for (const page of pages) {
    const ceiling = ceilingFor(budget, page.route);
    const over = overBudget(page, ceiling);
    const status = over.length ? `OVER (${over.join(', ')})` : 'ok';
    if (over.length) failures.push(`${page.route}: ${over.join(', ')}`);
    console.log(
      `${page.route.padEnd(30)} ${String(page.files.length).padStart(5)} ${kb(page.raw)} ${kb(page.gzip)}   ${kb(ceiling.gzip)}  ${status}`,
    );
  }

  const lazyRows = new Map<string, Sized>();
  for (const page of pages) for (const l of page.lazy) lazyRows.set(l.file, l);
  if (lazyRows.size) {
    console.log('\nlazy chunks (import() only; informational, not gated):');
    for (const [file, s] of [...lazyRows].sort()) console.log(`  ${file.padEnd(60)} ${kb(s.raw)} ${kb(s.gzip)}`);
  }
  const inlineTotal = pages.reduce((n, p) => n + p.inlineBytes, 0);
  console.log(`\ninline <script> bytes across all pages (informational, not gated): ${inlineTotal}`);

  for (const page of pages) for (const w of page.warnings) console.warn(`warning: ${page.route}: ${w}`);

  // Non-vacuity: the walker must get past the seeds on /playground.
  const playground = pages.find((p) => p.route === '/playground');
  if (!playground) {
    failures.push('/playground was not built');
  } else {
    const html = readFileSync(join(distDir, 'playground', 'index.html'), 'utf8');
    const seeds = new Set(
      [...all(SCRIPT_SRC, html), ...all(SCRIPT_SRC_REV, html), ...all(MODULEPRELOAD, html), ...all(MODULEPRELOAD_REV, html)]
        .map((u) => distPathOf(u, base))
        .filter((p): p is string => p !== null)
        .map((p) => normalize(p)),
    );
    const beyond = playground.files.filter((f) => !seeds.has(f));
    if (beyond.length === 0) {
      failures.push(
        '/playground: the walker reached no chunk beyond its seeds — the chunk scanner is not matching the emitted module syntax',
      );
    }
  }

  if (failures.length) {
    console.error('\nbundle budget FAILED:');
    for (const f of failures) console.error(`  ${f}`);
    return 1;
  }
  console.log('\nbundle budget ok');
  return 0;
}

if (import.meta.main) process.exit(main());
