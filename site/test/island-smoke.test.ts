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
import { afterEach, describe, expect, test } from 'bun:test';
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
/** The playground's window, kept so a later test can drive its DOM: the island
 *  module is imported once per process and cannot be mounted twice. */
let lastWindow: Window | null = null;

/**
 * Re-point the globals at an already-built window, run `fn`, put them back.
 *
 * A test that only reads the document does not need this, but one that DRIVES
 * it does: the island allocates through the global `document`, and `afterEach`
 * has already restored that by the time a later test runs. Without this, a
 * click handler that calls `document.createElement` throws inside the event
 * dispatch, where nothing surfaces it — the assertion just sees a DOM that
 * did not change, which reads as a product bug rather than a harness one.
 */
function drive<T>(fn: (doc: Window['document']) => T): T {
  if (!lastWindow) throw new Error('no window: the mounting test must run first');
  const undo = installGlobals(lastWindow);
  try {
    return fn(lastWindow.document);
  } finally {
    undo();
  }
}

function installGlobals(window: Window): () => void {
  const g = globalThis as Record<string, unknown>;
  const saved: [string, unknown][] = [];
  const keys = [
    'document', 'window', 'location', 'history', 'navigator', 'matchMedia',
    'requestAnimationFrame', 'ResizeObserver', 'MutationObserver', 'HTMLElement',
    'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'HTMLAnchorElement',
    'HTMLButtonElement', 'Node', 'Element', 'Event', 'CustomEvent', 'localStorage',
    'getComputedStyle', 'DOMException', 'CSS',
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

  return () => {
    for (const [k, v] of saved) {
      if (v === undefined) delete g[k];
      else g[k] = v;
    }
  };
}

function installDom(html: string) {
  const window = new Window({ url: 'http://localhost/playground' });
  // The chunk is imported by hand below, so the page's own <script src> tags
  // are stripped rather than fetched over a network that is not there.
  window.document.write(html.replace(/<script\b[^>]*\bsrc=[^>]*><\/script>/g, ''));
  restore = installGlobals(window);
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

  if (page === 'playground') lastWindow = window;
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

    // The workspace is a tree, and the server-rendered fallback list is gone.
    const catalogue = buildCatalogue(examples, tour);
    expect(doc.querySelector('.pg-tree')?.getAttribute('role')).toBe('tree');
    expect(doc.querySelector('.pg-ws-fallback')).toBeNull();

    // One row per group, plus the projects of whichever groups are open. Every
    // group is shut on a fresh envelope except "Yours" and the one holding the
    // project that loaded, so this is far fewer rows than the flat list was.
    const groupRows = Array.from(
      doc.querySelectorAll('.pg-tree-group .pg-tree-label'),
      (n) => (n as { textContent: string }).textContent,
    );
    expect(groupRows).toEqual([...CATALOGUE_GROUPS.filter((g) => catalogue.some((c) => c.group === g)), 'Yours']);
    expect(doc.querySelectorAll('.pg-tree-project').length).toBeLessThan(catalogue.length);

    // The default pick is open, revealed inside its group, and showing files.
    const openProject = doc.querySelector('.pg-tree-project[aria-current="true"]')!;
    expect(openProject).not.toBeNull();
    expect(openProject.getAttribute('aria-expanded')).toBe('true');
    const files = doc.querySelectorAll('.pg-tree-file');
    expect(files.length).toBeGreaterThanOrEqual(1);
    // …with exactly one of them marked as the file the editor is showing.
    expect(doc.querySelectorAll('.pg-tree-file[aria-current="true"]')).toHaveLength(1);

    // The editor's own file strip is gone: the tree is the only place files
    // live, which is the whole point of the move.
    expect(doc.querySelector('.pg-files')).toBeNull();
    expect(doc.querySelectorAll('.pg-filetab')).toHaveLength(0);

    // A roving tabindex, so the whole tree is one tab stop rather than 22.
    const stops = Array.from(doc.querySelectorAll('.pg-tree-row')).filter(
      (r) => (r as unknown as { tabIndex: number }).tabIndex === 0,
    );
    expect(stops).toHaveLength(1);
    // The editor panel is labelled by the current file row, not by a tab.
    const labelledBy = doc.querySelector('.pg-editor-wrap')?.getAttribute('aria-labelledby') ?? '';
    expect(labelledBy).not.toBe('');
    expect(doc.querySelector(`#${labelledBy}`)?.classList.contains('pg-tree-file')).toBe(true);

    // The dock: two panels under the editor, diagnostics open and selected.
    const dock = doc.querySelector('.pg-dock') as unknown as { dataset: Record<string, string> } | null;
    expect(dock).not.toBeNull();
    // Shut on a fresh envelope: the tree carries the error badge now, so the
    // dock is for reading the messages rather than for noticing them.
    expect(dock!.dataset.open).toBe('false');
    const dockTabs = Array.from(
      doc.querySelectorAll('.pg-dock-tabs [role=tab]'),
      (b) => (b as unknown as { dataset: Record<string, string> }).dataset.dock,
    );
    expect(dockTabs).toEqual(['diagnostics', 'settings']);
    expect(doc.querySelector('.pg-dock-tab[data-dock="diagnostics"]')?.getAttribute('aria-selected')).toBe('true');
    expect(doc.querySelector('[data-dock-panel="settings"]')?.hasAttribute('hidden')).toBe(true);

    // Both moved OUT of the output pane. A duplicate left behind would give
    // the settings two sets of live controls bound to one store.
    const output = doc.querySelector('.pg-output')!;
    expect(output.querySelectorAll('.pg-diag')).toHaveLength(0);
    expect(output.querySelectorAll('[data-setting]')).toHaveLength(0);
    expect(doc.querySelectorAll('.pg-diag')).toHaveLength(1);
    const editorPane = doc.querySelector('.pg-editor')!;
    expect(editorPane.querySelectorAll('[data-setting]').length).toBeGreaterThan(0);
    expect(editorPane.querySelector('.pg-dock')).not.toBeNull();

    // The output strip is the three compiled views, diagnostics gone.
    const outTabs = Array.from(
      doc.querySelectorAll('.pg-tabs [role=tab]'),
      (b) => (b as unknown as { dataset: Record<string, string> }).dataset.tab,
    );
    expect(outTabs).toEqual(['preview', 'truth', 'simulate']);
    expect(doc.querySelector('.pg-tabs [data-tab="preview"]')?.getAttribute('aria-selected')).toBe('true');

    // The tooltip exists and is empty — no analysis lands in this harness, so
    // the truth tab is not blocked and must say nothing.
    const tip = doc.querySelector('#pg-tab-tip-truth')!;
    expect(tip.getAttribute('role')).toBe('tooltip');
    expect(tip.textContent).toBe('');
    expect(doc.querySelector('.pg-tabs [data-tab="truth"]')?.getAttribute('aria-disabled')).toBe('false');

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

  test('the dock collapses and reopens, and remembers which panel', () => drive((doc) => {
    // The playground module is imported once per process, so this reuses the
    // document the test above left behind rather than mounting a second one.
    const dock = doc.querySelector('.pg-dock') as unknown as { dataset: Record<string, string> };
    const toggle = doc.querySelector('.pg-dock-toggle') as unknown as { click(): void; textContent: string };
    const diagTab = doc.querySelector('.pg-dock-tab[data-dock="diagnostics"]') as unknown as { click(): void };
    const setTab = doc.querySelector('.pg-dock-tab[data-dock="settings"]') as unknown as { click(): void };
    const body = doc.querySelector('.pg-dock-body')!;

    expect(dock.dataset.open).toBe('false');
    toggle.click();
    expect(dock.dataset.open).toBe('true');
    expect(toggle.textContent).toBe('Hide');
    toggle.click();
    expect(dock.dataset.open).toBe('false');
    expect(toggle.textContent).toBe('Show');
    toggle.click();

    // Switching panel keeps the dock open and moves the selection with it.
    setTab.click();
    expect(dock.dataset.open).toBe('true');
    expect(doc.querySelector('[data-dock-panel="settings"]')?.hasAttribute('hidden')).toBe(false);
    expect(doc.querySelector('[data-dock-panel="diagnostics"]')?.hasAttribute('hidden')).toBe(true);

    // Clicking the panel already showing is the collapse gesture.
    setTab.click();
    expect(dock.dataset.open).toBe('false');
    // …and clicking the OTHER panel while collapsed reopens on that one.
    diagTab.click();
    expect(dock.dataset.open).toBe('true');
    expect(doc.querySelector('[data-dock-panel="diagnostics"]')?.hasAttribute('hidden')).toBe(false);
    expect(body).not.toBeNull();
  }));

  test('a group collapses and reopens, taking its projects with it', () => drive((doc) => {
    const rows = () => Array.from(doc.querySelectorAll('.pg-tree-row'));
    const openGroup = doc.querySelector('.pg-tree-group[aria-expanded="true"]') as unknown as
      { click(): void; getAttribute(n: string): string | null };
    const before = rows().length;

    openGroup.click();
    const shut = rows().length;
    // Shutting a group removes its projects — and the open project's files
    // with them — rather than leaving hidden rows the arrow keys could reach.
    expect(shut).toBeLessThan(before);
    expect(doc.querySelector('.pg-tree-group[aria-expanded="true"]')).not.toBe(openGroup);

    openGroup.click();
    expect(rows().length).toBe(before);
    expect(openGroup.getAttribute('aria-expanded')).toBe('true');

    // Still exactly one tab stop after two redraws.
    const stops = rows().filter((r) => (r as unknown as { tabIndex: number }).tabIndex === 0);
    expect(stops).toHaveLength(1);
  }));

  test('files are added, switched and deleted from the tree', () => drive((doc) => {
    // Everything here used to live on the strip above the editor. This is the
    // proof that moving it did not quietly drop half of it.
    const fileRows = () => Array.from(doc.querySelectorAll('.pg-tree-file'));
    const labelOf = (r: unknown): string =>
      (r as { querySelector(s: string): { textContent: string } | null })
        .querySelector('.pg-tree-label')?.textContent ?? '';
    const click = (el: unknown) => (el as { click(): void }).click();

    expect(fileRows()).toHaveLength(1);
    const firstName = labelOf(fileRows()[0]);

    // The ＋ on the open project row is the add-file control the strip had.
    const add = doc.querySelector('.pg-tree-project[aria-current="true"] .pg-tree-add');
    expect(add).not.toBeNull();
    click(add);
    expect(fileRows()).toHaveLength(2);

    // The last file is the root, and only it carries the chip.
    const roots = fileRows().filter((r) => (r as unknown as Element).querySelector('.pg-tree-root'));
    expect(roots).toHaveLength(1);
    expect(labelOf(roots[0])).toBe(labelOf(fileRows()[1]));
    // Adding a file selects it, and exactly one row is ever current.
    expect(doc.querySelectorAll('.pg-tree-file[aria-current="true"]')).toHaveLength(1);

    // A new file is inserted BEFORE the root, so the root stays last and the
    // original file is still the one the compiler starts from.
    expect(labelOf(fileRows()[1])).toBe(firstName);
    // Switching files by clicking a row.
    click(fileRows()[1]);
    expect(labelOf(doc.querySelector('.pg-tree-file[aria-current="true"]'))).toBe(firstName);

    // Delete is two presses, as it was on the strip: the first only arms.
    const del = (doc.querySelector('.pg-tree-file .pg-tree-action') as unknown as { click(): void });
    click(del);
    expect(fileRows()).toHaveLength(2);
    expect(doc.querySelector('.pg-tree-file[data-confirm="true"]')).not.toBeNull();
    click(doc.querySelector('.pg-tree-file[data-confirm="true"] .pg-tree-action'));
    expect(fileRows()).toHaveLength(1);

    // …and the last remaining file refuses to go, so a project always has one.
    click(doc.querySelector('.pg-tree-file .pg-tree-action'));
    click(doc.querySelector('.pg-tree-file .pg-tree-action'));
    expect(fileRows()).toHaveLength(1);
  }));

  test('every app-shell container hands its height to exactly one child', () => drive((doc) => {
    // The bug this exists for, twice over: a container declared a fixed set of
    // grid rows, and then the page turned out to have a different number of
    // children than tracks — `main` after its header was deleted, and `.pg`
    // whose banner is hidden in the normal case. Both times the pane that was
    // supposed to fill the viewport quietly landed in an `auto` track and
    // started sizing to its own content, with no error and every gate green.
    //
    // So the invariant is checked against the DOM as it actually renders, not
    // against the CSS alone: a fixed track count must match the children that
    // are really there, and anything else must be a flex column whose
    // height-taking child says so.
    const css = readFileSync(resolve(SITE, 'src', 'styles', 'global.css'), 'utf8');
    const declarationsOf = (selector: string): string => {
      const at = css.indexOf(selector);
      expect(at === -1 ? `${selector} (no such rule)` : selector).toBe(selector);
      const body = css.slice(at + selector.length);
      return body.slice(0, body.indexOf('}')).replace(/\/\*[\s\S]*?\*\//g, '');
    };
    /** `auto minmax(0, 1fr) auto` is three tracks, not five words. */
    const trackCount = (value: string): number =>
      value.replace(/[a-z-]+\([^)]*\)/gi, 'X').trim().split(/\s+/).filter(Boolean).length;
    /** A `<script>` and a `[hidden]` element generate no box, so neither is a
     *  grid item. This is exactly what both bugs turned on. */
    const rendered = (el: unknown): boolean => {
      const e = el as { tagName: string; hasAttribute(n: string): boolean };
      return e.tagName !== 'SCRIPT' && e.tagName !== 'STYLE' && !e.hasAttribute('hidden');
    };

    const chain: [string, string][] = [
      ['main', '.pg'],
      ['.pg', '.pg-panes'],
    ];

    for (const [selector, fills] of chain) {
      const el = doc.querySelector(selector)!;
      expect(el).not.toBeNull();
      const kids = Array.from(el.children).filter(rendered);
      const block = declarationsOf(`[data-layout='app'] ${selector} {`);

      // A container that hands height down must be allowed to shrink first.
      expect(block).toContain('min-height: 0');

      const rows = block.match(/grid-template-rows:([^;]+);/);
      if (rows) {
        // Allowed, but only while the tracks and the real children agree.
        expect(trackCount(rows[1])).toBe(kids.length);
      } else {
        expect(block).toContain('display: flex');
        expect(block).toContain('flex-direction: column');
        // …and the child that takes the leftover has to claim it.
        expect(declarationsOf(`[data-layout='app'] ${fills} {`)).toContain('flex: 1');
        expect(doc.querySelector(fills)?.parentElement).toBe(el);
      }
    }

    // The editor's own chain is flex all the way down to CodeMirror, which
    // sizes to its content unless something gives it a height.
    expect(declarationsOf("[data-layout='app'] .pg-editor .pg-cm .cm-editor {")).toContain('height: 100%');
    expect(declarationsOf("[data-layout='app'] .pg-editor .pg-cm .cm-scroller {")).toContain('overflow: auto');
  }));

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
