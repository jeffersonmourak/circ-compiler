// Build-free guards on the app layout. Two things can go wrong silently here
// and neither shows up in a build: another page opting into `layout="app"` and
// losing its article column, or an app-layout rule reaching `.lc-mount`, which
// is shared with LiveCanvas.astro on / and /examples.
import { describe, expect, test } from 'bun:test';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const SITE = resolve(import.meta.dir, '..');
const read = (...parts: string[]) => readFileSync(resolve(SITE, ...parts), 'utf8');

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else out.push(full);
  }
  return out;
}

/** CSS with `/* … *\/` comments removed, so a selector mentioned in prose does
 *  not count as a rule. */
function stripComments(css: string): string {
  return css.replace(/\/\*[\s\S]*?\*\//g, '');
}

/** Every selector text in the stylesheet: whatever precedes each `{`. */
function selectorsOf(css: string): string[] {
  const out: string[] = [];
  const body = stripComments(css);
  const re = /([^{}]+)\{/g;
  for (let m = re.exec(body); m; m = re.exec(body)) {
    const selector = m[1].trim();
    // Skip at-rule preludes (@media, @font-face, …) and empty matches.
    if (!selector || selector.startsWith('@')) continue;
    out.push(selector.replace(/\s+/g, ' '));
  }
  return out;
}

describe('app layout', () => {
  const base = read('src', 'layouts', 'Base.astro');
  const css = read('src', 'styles', 'global.css');

  test('Base declares the layout prop and defaults it to the default layout', () => {
    expect(base).toMatch(/layout\?:\s*'default'\s*\|\s*'app'/);
    expect(base).toMatch(/layout\s*=\s*'default',/);
    // `data-layout` is stamped only for 'app', so every other page's <body> is
    // byte-identical to what it was before the prop existed.
    expect(base).toMatch(/data-layout=\{layout === 'app' \? 'app' : undefined\}/);
  });

  test('only the playground opts in', () => {
    const pages = walk(resolve(SITE, 'src', 'pages')).filter((f) => /\.(astro|md)$/.test(f));
    const optIn = pages.filter((f) => readFileSync(f, 'utf8').includes('layout="app"'));
    expect(optIn.map((f) => f.split('/').pop())).toEqual(['playground.astro']);
  });

  test('nothing restyles .lc-mount', () => {
    // The frozen set. `.lc-mount` is LiveCanvas.astro's mount too, so a rule
    // added for the workbench would silently restyle / and /examples.
    const frozen = [
      '.lc-mount',
      '.lc-mount canvas',
      '.lc-launch[hidden], .lc-mount[hidden], .lc-error[hidden]',
    ];
    const mentioning = selectorsOf(css).filter((s) => s.includes('.lc-mount'));
    expect([...new Set(mentioning)].sort()).toEqual([...new Set(frozen)].sort());
    // And no app-layout rule reaches it, whatever else changes.
    for (const selector of mentioning) expect(selector).not.toContain('data-layout');
  });

  test('the app layout is always scoped to the attribute', () => {
    const appRules = selectorsOf(css).filter((s) => s.includes("data-layout='app'"));
    expect(appRules.length).toBeGreaterThan(5);
    // Scoping is what keeps /tour and /examples — and Phase 7's LiveEditor —
    // out of every rule in the block.
    for (const selector of appRules) {
      expect(selector.startsWith("[data-layout='app']")).toBe(true);
    }
  });

  test('the app shell hands its height down to the workbench', () => {
    const css = read('src', 'styles', 'global.css');
    // Comments are stripped first: this rule's own comment explains the trap by
    // naming `grid-template-rows`, and an assertion that reads prose as if it
    // were a declaration is the same trap one level up.
    const declarations = (from: string) => {
      const body = css.slice(css.indexOf(from) + from.length);
      return body.slice(0, body.indexOf('}')).replace(/\/\*[\s\S]*?\*\//g, '');
    };
    // The chain that carries viewport height down to the editor. Each link
    // must be able to shrink, and the next one must claim the leftover.
    //
    // Both containers used to declare a fixed `grid-template-rows`, and both
    // broke when the page turned out to have a different number of children
    // than tracks. `island-smoke` checks tracks against the rendered DOM,
    // which is the real invariant; this is the build-free half of it, and it
    // runs in every slice rather than only after `bun --bun run build`.
    for (const [container, fills] of [['main', '.pg'], ['.pg', '.pg-panes']] as const) {
      expect(declarations(`[data-layout='app'] ${container} {`)).toContain('min-height: 0');
      const child = declarations(`[data-layout='app'] ${fills} {`);
      expect(child).toContain('flex: 1');
      expect(child).toContain('min-height: 0');
    }
  });

  test('the viewport lock has a 100vh fallback before 100dvh', () => {
    const block = stripComments(css).slice(stripComments(css).indexOf("[data-layout='app'] {"));
    const vh = block.indexOf('height: 100vh');
    const dvh = block.indexOf('height: 100dvh');
    expect(vh).toBeGreaterThanOrEqual(0);
    expect(dvh).toBeGreaterThan(vh);
  });

  test('--danger is defined in both token blocks', () => {
    const light = css.slice(css.indexOf(':root {'), css.indexOf('[data-theme="dark"] {'));
    const dark = css.slice(css.indexOf('[data-theme="dark"] {'));
    expect(light).toContain('--danger:');
    expect(dark).toContain('--danger:');
  });
});
