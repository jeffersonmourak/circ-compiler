// Runs the REAL built playground island against the REAL built HTML in a
// headless DOM.
//
// This exists because two gates could not see island scripts at all: `bun test`
// cannot import an `.astro` file, and the build strips types without resolving
// names. An undefined identifier in the island therefore shipped green once,
// and only a browser found it. This catches that class in the suite.
//
// It needs `dist/`, so it skips when there has been no build. Run
// `bun --bun run build` first; the standing gate order already does.
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { CATALOGUE_GROUPS, buildCatalogue } from '../src/utils/playground-store.ts';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';
import { resolve } from 'node:path';
import { Window } from 'happy-dom';

const SITE = resolve(import.meta.dir, '..');
const DIST = resolve(SITE, 'dist');
const hasBuild = existsSync(resolve(DIST, 'playground', 'index.html'));

/** Errors this harness provokes by not being a browser. */
const HARNESS_ONLY = [
  /ModuleNotFound resolving .*libcirc\.worker/, // no worker outside a browser
  /Window is not defined/, // the editor's own measure pass reaches a real Window
];

let restore: (() => void) | null = null;

function installDom(html: string) {
  const window = new Window({ url: 'http://localhost/playground' });
  // The chunk is imported by hand below, so the page's own <script src> tags
  // are stripped rather than fetched over a network that is not there.
  window.document.write(html.replace(/<script\b[^>]*\bsrc=[^>]*><\/script>/g, ''));
  const g = globalThis as Record<string, unknown>;
  const saved: [string, unknown][] = [];
  const keys = [
    'document', 'window', 'location', 'history', 'navigator', 'matchMedia',
    'requestAnimationFrame', 'ResizeObserver', 'MutationObserver', 'HTMLElement',
    'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'HTMLAnchorElement',
    'HTMLButtonElement', 'Node', 'Element', 'Event', 'CustomEvent', 'localStorage',
    'getComputedStyle', 'DOMException',
  ];
  for (const k of keys) {
    const v = (window as unknown as Record<string, unknown>)[k];
    if (v === undefined) continue;
    saved.push([k, g[k]]);
    g[k] = v;
  }
  saved.push(['window', g.window]);
  g.window = window;
  saved.push(['requestIdleCallback', g.requestIdleCallback]);
  g.requestIdleCallback = (fn: () => void) => setTimeout(fn, 0);

  restore = () => {
    for (const [k, v] of saved) {
      if (v === undefined) delete g[k];
      else g[k] = v;
    }
  };
  return window;
}

afterEach(() => {
  restore?.();
  restore = null;
});

/** A module is imported once per process, so each page's island is run once
 *  and every assertion about it lives in that one test. */
async function runIsland(page: string, chunkPrefix: string) {
  const html = readFileSync(resolve(DIST, page, 'index.html'), 'utf8');
  const window = installDom(html);
  const errors: string[] = [];
  (window as unknown as { addEventListener(t: string, f: (e: { message: string }) => void): void })
    .addEventListener('error', (e) => errors.push(e.message));

  const chunk = readdirSync(resolve(DIST, '_astro')).find((f) => f.startsWith(chunkPrefix));
  if (!chunk) throw new Error(`no ${chunkPrefix} chunk in dist/_astro`);
  // The throw this guards against is the whole point: an undefined identifier
  // in an island fails right here rather than in someone's browser.
  await import(resolve(DIST, '_astro', chunk));
  await new Promise((r) => setTimeout(r, 300));

  const real = errors.filter((m) => !HARNESS_ONLY.some((re) => re.test(m)));
  return { doc: window.document, errors: real };
}

describe.skipIf(!hasBuild)('the built islands run', () => {
  test('the playground mounts its editor, tabs and workbench', async () => {
    const { doc, errors } = await runIsland('playground', 'Playground.astro');
    expect(errors).toEqual([]);

    // The editor took over from the fallback.
    expect(doc.querySelectorAll('.cm-editor')).toHaveLength(1);
    expect(doc.querySelector('#pg-editor')?.hasAttribute('hidden')).toBe(false);
    expect(doc.querySelector('#pg-source')).toBeNull();
    expect(doc.querySelector('.cm-content')?.textContent?.length ?? 0).toBeGreaterThan(0);

    // One row per catalogue item, and at least the root file tab. The count is
    // derived, so adding an example cannot leave a tier missing from the picker.
    const catalogue = buildCatalogue(examples, tour);
    expect(doc.querySelectorAll('.pg-ws-row')).toHaveLength(catalogue.length);
    // Every non-empty group renders its heading, plus "Yours" for scratch.
    const headings = Array.from(doc.querySelectorAll('.pg-ws-group'), (h) => (h as { textContent: string }).textContent);
    expect(headings).toEqual([...CATALOGUE_GROUPS.filter((g) => catalogue.some((c) => c.group === g)), 'Yours']);
    expect(doc.querySelectorAll('.pg-filetab').length).toBeGreaterThanOrEqual(1);
    expect(doc.querySelector('.pg-files')?.hasAttribute('hidden')).toBe(false);

    // The workbench furniture, and the panes grid in order.
    expect(doc.querySelector('.pg-splitter')).not.toBeNull();
    expect(doc.querySelector('.pg-statusbar')).not.toBeNull();
    expect(doc.querySelector('.pg-settings')).not.toBeNull();
    // happy-dom's Element is structurally its own; `className` is all this needs.
    const panes = Array.from(
      doc.querySelector('.pg-panes')?.children ?? [],
      (c) => (c as { className: string }).className,
    );
    expect(panes).toEqual(['pg-ws', 'pg-editor', 'pg-splitter', 'pg-output']);
  });

  test('the tour mounts one inert editor per step', async () => {
    const { doc, errors } = await runIsland('tour', 'LiveEditor.astro');
    expect(errors).toEqual([]);

    expect(doc.querySelectorAll('.le').length).toBe(7);
    // Inert until touched: no editor DOM, the source still readable.
    expect(doc.querySelectorAll('.cm-editor')).toHaveLength(0);
    expect(doc.querySelector('.le-source')?.hasAttribute('hidden')).toBe(false);
    // And the expand link works before any script has run.
    expect(doc.querySelector('.le-expand')?.getAttribute('href')).toContain('#pick=tour:1');
  });
});
