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
import { MAX_SOURCE_BYTES, STORE_KEY, buildCatalogue, defaultEnvelope } from '../src/utils/playground-store.ts';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';
import { resolve } from 'node:path';
import { Window } from 'happy-dom';
import type { SimSession } from '../src/scripts/sim-session.ts';

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

/** `drive` for a handler that keeps working after the click returns — a
 *  share that awaits an encode and a clipboard write. The globals stay
 *  installed until `fn`'s promise settles, not just until it returns. */
async function driveAsync<T>(fn: (doc: Window['document']) => Promise<T>): Promise<T> {
  if (!lastWindow) throw new Error('no window: the mounting test must run first');
  const undo = installGlobals(lastWindow);
  try {
    return await fn(lastWindow.document);
  } finally {
    undo();
  }
}

/**
 * A recording stand-in for `IntersectionObserver`, which happy-dom does not
 * implement.
 *
 * It has to be a GLOBAL before the island chunk is imported, because the
 * script wires its observer at import time — so a test cannot install it
 * afterwards and see anything.
 */
export class FakeIntersectionObserver {
  static instances: FakeIntersectionObserver[] = [];
  observed: unknown[] = [];
  unobserved: unknown[] = [];
  constructor(public readonly callback: (entries: unknown[]) => void, public readonly options?: unknown) {
    FakeIntersectionObserver.instances.push(this);
  }
  observe(el: unknown) { this.observed.push(el); }
  unobserve(el: unknown) { this.unobserved.push(el); }
  disconnect() {}
  /** Report the given elements as on screen, the way a scroll would. */
  intersect(...els: unknown[]) {
    this.callback(els.map((target) => ({ target, isIntersecting: true })));
  }
}

function installGlobals(window: Window): () => void {
  const g = globalThis as Record<string, unknown>;
  const saved: [string, unknown][] = [];
  saved.push(['IntersectionObserver', g.IntersectionObserver]);
  g.IntersectionObserver = FakeIntersectionObserver;
  const keys = [
    'document', 'window', 'location', 'history', 'navigator', 'matchMedia',
    'requestAnimationFrame', 'ResizeObserver', 'MutationObserver', 'HTMLElement',
    'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'HTMLAnchorElement',
    'HTMLButtonElement', 'Node', 'Element', 'Event', 'CustomEvent', 'KeyboardEvent',
    'MouseEvent', 'InputEvent', 'FocusEvent', 'localStorage',
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
async function runIsland(page: string, chunkPrefix: string, seed?: Record<string, unknown>) {
  const html = readFileSync(resolve(DIST, page, 'index.html'), 'utf8');
  const window = installDom(html);
  // An envelope the island finds at boot, the way a returning reader's
  // browser holds one. Written before the chunk runs, since the store is
  // read once, in `init`.
  if (seed) (window as unknown as { localStorage: Storage }).localStorage.setItem(STORE_KEY, JSON.stringify(seed));
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
    // Restored onto the Live view, as a reader who left the page there comes
    // back to it. This is the boot path that once reached the simulator's
    // record before it was declared ("Cannot access 'sim' before
    // initialization"), and it aborted the rest of the boot with it.
    const { doc, errors } = await runIsland('playground', 'Playground.astro', { ...defaultEnvelope(), activeId: buildCatalogue(examples, tour)[0].id, view: 'live', dataOpen: true });
    expect(errors).toEqual([]);
    expect(doc.querySelector('.pg-data-card')?.hasAttribute('hidden')).toBe(false);
    (doc.querySelector('.pg-data-close') as unknown as HTMLElement).click();
    expect(doc.querySelector('.pg-view-tab[data-view="live"]')?.getAttribute('aria-selected')).toBe('true');
    expect(doc.querySelector('[data-view-panel="live"]')?.hasAttribute('hidden')).toBe(false);
    // Back to the default view for the rest of the walk.
    (doc.querySelector('.pg-view-tab[data-view="schematic"]') as unknown as { click(): void }).click();


    // The editor took over from the fallback.
    expect(doc.querySelectorAll('.cm-editor')).toHaveLength(1);
    expect(doc.querySelector('#pg-editor')?.hasAttribute('hidden')).toBe(false);
    expect(doc.querySelector('#pg-source')).toBeNull();
    expect(doc.querySelector('.cm-content')?.textContent?.length ?? 0).toBeGreaterThan(0);

    // The workspace is a tree, and the server-rendered fallback list is gone.
    const catalogue = buildCatalogue(examples, tour);
    expect(doc.querySelector('.pg-switch-tree')?.getAttribute('role')).toBe('tree');
    expect(doc.querySelector('.pg-switch-fallback')).toBeNull();

    // One row per group, plus the projects of whichever groups are open. Every
    // group is shut on a fresh envelope except "Yours" and the one holding the
    // project that loaded, so this is far fewer rows than the flat list was.
    const groupRows = Array.from(
      doc.querySelectorAll('.pg-switch-group .pg-switch-label'),
      (n) => (n as { textContent: string }).textContent,
    );
    expect(groupRows).toEqual(['Tour', 'Examples', 'Mine']);
    expect(doc.querySelectorAll('.pg-switch-project').length).toBe(catalogue.length);

    // The default pick is open, revealed inside its group, and showing files.
    const openProject = doc.querySelector('.pg-switch-project[aria-current="true"]')!;
    expect(openProject).not.toBeNull();
    expect(openProject.getAttribute('aria-expanded')).toBe('true');
    const files = doc.querySelectorAll('.pg-switch-file');
    expect(files.length).toBeGreaterThanOrEqual(1);
    // …with exactly one of them marked as the file the editor is showing.
    expect(doc.querySelectorAll('.pg-switch-file[aria-current="true"]')).toHaveLength(1);

    // The file strip over the editor lists the same files as the tree, in
    // order, with the open one selected; it is a switch, so it carries no
    // rename or delete of its own.
    const strip = Array.from(doc.querySelectorAll('.pg-files .pg-file'), (b) => (b as { textContent: string }).textContent);
    const treeFiles = Array.from(files, (r) => (r.querySelector('.pg-switch-label') as { textContent: string } | null)?.textContent ?? '');
    expect(strip).toEqual(treeFiles);
    expect(doc.querySelectorAll('.pg-files .pg-file[aria-selected="true"]')).toHaveLength(1);
    expect(doc.querySelectorAll('.pg-files .pg-switch-action')).toHaveLength(0);
    expect(doc.querySelector('.pg-files .pg-file-add')?.textContent).toBe('+ file');

    // A roving tabindex, so the whole tree is one tab stop rather than 22.
    const stops = Array.from(doc.querySelectorAll('.pg-switch-row')).filter(
      (r) => (r as unknown as { tabIndex: number }).tabIndex === 0,
    );
    expect(stops).toHaveLength(1);
    // The editor panel is labelled by the strip's current tab.
    const labelledBy = doc.querySelector('.pg-editor-wrap')?.getAttribute('aria-labelledby') ?? '';
    expect(labelledBy).not.toBe('');
    expect(doc.querySelector(`#${labelledBy}`)?.classList.contains('pg-file')).toBe(true);
    expect(doc.querySelector(`#${labelledBy}`)?.getAttribute('aria-selected')).toBe('true');

    // The footer under the editor: a bar with the counts and the stats, a
    // gear, and a body shut on a fresh envelope — the bar already says how
    // many, so opening it is for reading the messages. The dock is gone.
    expect(doc.querySelector('.pg-dock')).toBeNull();
    const footer = doc.querySelector('.pg-footer') as unknown as { dataset: Record<string, string> } | null;
    expect(footer).not.toBeNull();
    expect(footer!.dataset.open).toBe('false');
    expect(footer!.dataset.tab).toBe('diagnostics');
    expect(doc.querySelector('.pg-footer-counts-text')?.textContent).toBe('0 errors · 0 warnings');
    expect(doc.querySelector('.pg-footer-counts')?.getAttribute('data-severity')).toBe('none');
    // No analysis lands in this harness, so the stats are the lines alone.
    expect(doc.querySelector('.pg-footer-stats')?.textContent).toMatch(/^\d+ lines?$/);
    expect(doc.querySelector('.pg-footer-gear')?.getAttribute('aria-label')).toBe('Settings');
    expect(doc.querySelector('.pg-footer-body')?.hasAttribute('hidden')).toBe(true);
    expect(doc.querySelector('[data-footer-panel="settings"]')?.hasAttribute('hidden')).toBe(true);

    // The drawer is the frame's third row: the session's console and the
    // memory panel, folded to one line until asked for. It left the output
    // pane, so the canvas region never shares its height with it.
    const drawer = doc.querySelector('.pg-drawer')!;
    expect(doc.querySelector('.pg-output .pg-drawer')).toBeNull();
    expect(doc.querySelector('.pg-term .pg-drawer')).not.toBeNull();
    expect((doc.querySelector('.pg-term') as unknown as { dataset: Record<string, string> }).dataset.open).toBe('false');
    expect(drawer.hasAttribute('hidden')).toBe(false);
    expect(doc.querySelector('.pg-term-line .pg-term-title')?.textContent).toMatch(/^circ-compile \S+\.circ --sim$/);
    expect(doc.querySelector('.pg-term-line .pg-term-cmd')?.textContent).toBe('');
    expect(doc.querySelector('.pg-term-line .pg-term-reply')?.textContent).toBe('Compile a circuit first.');
    expect(doc.querySelector('.pg-term-mem')?.getAttribute('aria-disabled')).toBe('true');
    expect(doc.querySelector('.pg-drawer-splitter')?.getAttribute('aria-orientation')).toBe('horizontal');
    expect(doc.querySelector('.pg-drawer-tabs')).toBeNull();
    expect(doc.querySelector('.pg-console-tab')?.textContent).toBe('Console');
    expect(doc.querySelector('.pg-console-caret')).not.toBeNull();
    // The memory tab exists in the markup but is hidden: the default pick
    // declares no rom or ram, and a permanently empty tab is a worse answer
    // than no tab. Its panel ships hidden with it.
    expect(drawer.hasAttribute('data-mem')).toBe(false);
    expect(doc.querySelector('.pg-drawer-mem')?.hasAttribute('hidden')).toBe(true);
    expect(doc.querySelector('.pg-mem')?.textContent).toBe('');
    expect(doc.querySelector('.pg-footer .pg-mem')).toBeNull();
    // The console: a scrollback and a prompt, shut until a session exists,
    // with the same sentence Simulate shows for why.
    expect(doc.querySelector('.pg-drawer .pg-console-log')).not.toBeNull();
    // An editor's terminal: a bar naming the command it runs, with its actions.
    expect(doc.querySelector('.pg-console-title')?.textContent).toMatch(/^circ-compile \S+\.circ --sim$/);
    const consoleButtons = Array.from(
      doc.querySelectorAll('.pg-console-head .pg-console-btn'),
      (b) => (b as unknown as { dataset: Record<string, string> }).dataset.console,
    );
    expect(consoleButtons).toEqual(['clear', 'script', 'log']);
    const prompt = doc.querySelector('.pg-console-in') as unknown as { disabled: boolean } | null;
    expect(prompt?.disabled).toBe(true);
    expect(doc.querySelector('.pg-console-note')?.hasAttribute('hidden')).toBe(false);
    expect(doc.querySelector('.pg-console-note')?.textContent).toBe('Compile a circuit first.');
    expect(doc.querySelector('.pg-console-log')?.textContent).toBe('');
    // The rom image boxes left Settings for it, and left nothing behind.
    expect(doc.querySelector('[data-footer-panel="settings"] .pg-rom-group')).toBeNull();
    expect(doc.querySelector('[data-footer-panel="settings"] .pg-rom-box')).toBeNull();

    // Both moved OUT of the output pane. A duplicate left behind would give
    // the settings two sets of live controls bound to one store.
    const output = doc.querySelector('.pg-output')!;
    expect(output.querySelectorAll('.pg-diag')).toHaveLength(0);
    // The Schematic's two toggles are the only settings in the region, on the
    // same attribute the footer's form binds, so one binding paints both.
    expect(Array.from(output.querySelectorAll('.pg-view-tools [data-setting]'), (e) => e.getAttribute('data-setting'))).toEqual(['expandMacros', 'expandDisplay']);
    expect(doc.querySelectorAll('.pg-diag')).toHaveLength(1);
    const editorPane = doc.querySelector('.pg-editor')!;
    expect(editorPane.querySelectorAll('[data-setting]').length).toBeGreaterThan(0);
    expect(editorPane.querySelector('.pg-footer')).not.toBeNull();
    expect(doc.querySelectorAll('.pg-footer [data-setting]').length).toBeGreaterThan(0);

    // The canvas region's furniture: the view switch with its three views,
    // the Data button carrying the card, the hint and zoom lines. The output
    // strip and its tooltip are gone.
    const views = Array.from(
      doc.querySelectorAll('.pg-view-switch [role=tab]'),
      (b) => (b as unknown as { dataset: Record<string, string> }).dataset.view,
    );
    expect(views).toEqual(['schematic', 'live', 'truth']);
    expect(doc.querySelector('.pg-view-tab[data-view="schematic"]')?.getAttribute('aria-selected')).toBe('true');
    expect(doc.querySelector('.pg-tabs')).toBeNull();
    expect(doc.querySelector('#pg-tab-tip-truth')).toBeNull();
    expect(doc.querySelector('.pg-panel')).toBeNull();
    // No analysis lands in this harness, so the truth view is not blocked and
    // the note beside the switch says nothing.
    expect(doc.querySelector('.pg-view-tab[data-view="truth"]')?.getAttribute('aria-disabled')).toBe('false');
    // No analysis, no rows: the chip says only the cap.
    expect(doc.querySelector('.pg-truth-chip')?.textContent).toBe('cap 12');
    expect(doc.querySelector('.pg-truth-card .pg-table')).not.toBeNull();
    // The region wears the view, and the Schematic's size line starts empty.
    expect((doc.querySelector('.pg-output') as unknown as { dataset: Record<string, string> }).dataset.view).toBe('schematic');
    expect(doc.querySelector('.pg-size')?.textContent).toBe('0 × 0 chars');
    expect(doc.querySelector('.pg-view-tools[data-for="schematic"] [data-copy="preview"]')).not.toBeNull();
    expect(doc.querySelector('.pg-data-btn')?.getAttribute('aria-expanded')).toBe('false');
    expect(doc.querySelector('.pg-data-card')?.getAttribute('role')).toBe('dialog');
    expect(doc.querySelector('.pg-data-card')?.getAttribute('aria-label')).toBe('Data');
    expect(doc.querySelector('.pg-data-card')?.hasAttribute('hidden')).toBe(true);
    expect(doc.querySelector('.pg-data-card .pg-data')).not.toBeNull();
    expect(doc.querySelector('.pg-data-card .pg-data-reset')).not.toBeNull();
    expect(doc.querySelector('.pg-hint')).not.toBeNull();
    expect(doc.querySelector('.pg-zoom .pg-zoom-pct')?.textContent).toBe('100%');
    expect(doc.querySelector('.pg-zoom .pg-zoom-fit')?.getAttribute('aria-disabled')).toBe('true');
    expect(doc.querySelector('.pg-sim-mount')?.classList.contains('lc-mount')).toBe(false);

    // The bench's chrome: no site nav or footer; a nav with the wordmark, the
    // breadcrumb naming the open project, the status cluster, the two
    // actions and the theme toggle; a status line with the identity, the
    // footer's signature and the promise. The status bar is gone.
    expect(doc.querySelector('.site-nav')).toBeNull();
    expect(doc.querySelector('.site-footer')).toBeNull();
    expect(doc.querySelector('.pg-statusbar')).toBeNull();
    expect(doc.querySelector('.pg-nav .pg-brand')?.getAttribute('href')).not.toBeNull();
    const defaultPick = catalogue[0];
    expect(doc.querySelector('.pg-crumb-group')?.textContent).toBe('Examples /');
    expect(doc.querySelector('.pg-crumb-name')?.textContent).toBe(defaultPick.label);
    // The cluster moved with its state: the harness has no worker, so the
    // word is whatever the pipeline says, never blank.
    expect(doc.querySelector('.pg-nav .pg-dot')?.getAttribute('data-state')).not.toBeNull();
    expect(doc.querySelector('.pg-nav .pg-status-label')?.textContent).not.toBe('');
    expect(doc.querySelector('.pg-nav .pg-download')).not.toBeNull();
    expect(doc.querySelector('.pg-nav .pg-share')).not.toBeNull();
    expect(doc.querySelector('.pg-nav .theme-toggle')).not.toBeNull();
    expect(doc.querySelector('.pg-statusline .pg-status-identity')).not.toBeNull();
    expect(doc.querySelector('.pg-statusline .signature .heart')).not.toBeNull();
    expect(doc.querySelector('.pg-statusline .pg-promise')?.textContent).toBe('runs in your browser · nothing leaves the page');
    expect(doc.querySelector('.pg-statusline .pg-status[role="status"]')).not.toBeNull();
    // The banner lives inside the source pane, not among the frame's rows.
    expect(doc.querySelector('.pg-editor > .pg-banner')).not.toBeNull();

    // The workbench furniture, and the body grid in order: the tree's card
    // first (hidden, and positioned out of the grid), then source, hairline,
    // canvas.
    expect(doc.querySelector('.pg-splitter')).not.toBeNull();
    expect(doc.querySelector('.pg-settings')).not.toBeNull();
    // happy-dom's Element is structurally its own; `className` is all this needs.
    const regions = Array.from(
      doc.querySelector('.pg-body')?.children ?? [],
      (c) => (c as { className: string }).className,
    );
    expect(regions).toEqual(['pg-editor', 'pg-splitter', 'pg-output']);
    expect(doc.querySelector('.pg-switch')?.hasAttribute('hidden')).toBe(true);
    expect(doc.querySelector('.pg-ws')).toBeNull();
    // The source column is the splitter, in pixels, at the design's default.
    expect((doc.querySelector('.pg-body') as unknown as { style: { getPropertyValue(n: string): string } }).style.getPropertyValue('--pg-source-w')).toBe('480px');
  });

  test('the strip switches files and adds one', () => drive((doc) => {
    const tabs = () => Array.from(doc.querySelectorAll('.pg-files .pg-file'), (b) => (b as { textContent: string }).textContent);
    const selected = () => (doc.querySelector('.pg-files .pg-file[aria-selected="true"]') as { textContent: string } | null)?.textContent;
    const before = tabs();
    // `+ file` adds a file before the root (the last file is the root) and
    // selects it; the tree shows the same file.
    (doc.querySelector('.pg-file-add') as unknown as { click(): void }).click();
    const after = tabs();
    expect(after).toHaveLength(before.length + 1);
    expect(after[after.length - 1]).toBe(before[before.length - 1]);
    expect(selected()).toBe(after[after.length - 2]);
    expect((doc.querySelector('.pg-switch-file[aria-current="true"] .pg-switch-label') as { textContent: string } | null)?.textContent).toBe(selected() ?? '');
    // Only the selected tab is a tab stop, and a click on another switches.
    const stops = Array.from(doc.querySelectorAll('.pg-files .pg-file')).filter((b) => (b as unknown as { tabIndex: number }).tabIndex === 0);
    expect(stops).toHaveLength(1);
    (doc.querySelectorAll('.pg-files .pg-file')[after.length - 1] as unknown as { click(): void }).click();
    expect(selected()).toBe(after[after.length - 1]);
    expect(doc.querySelector('.pg-editor-wrap')?.getAttribute('aria-labelledby')).toBe(`pg-file-${after.length - 1}`);
    // Leave the project as it was found: the tree's delete, armed then made.
    const deleteOn = () => doc.querySelector('.pg-switch-file .pg-switch-action[aria-label^="Delete"]') as unknown as { click(): void };
    deleteOn().click();
    deleteOn().click();
    expect(tabs()).toEqual(before);
  }));

  test('the view switch shows one view, and the Data button opens the card', () => drive((doc) => {
    const view = (name: string) => doc.querySelector(`.pg-view-tab[data-view="${name}"]`) as unknown as { click(): void; getAttribute(n: string): string | null; tabIndex: number };
    const panel = (name: string) => doc.querySelector(`[data-view-panel="${name}"]`)!;
    const region = doc.querySelector('.pg-output') as unknown as { dataset: Record<string, string> };
    const press = (el: unknown, key: string) =>
      (el as { dispatchEvent(e: unknown): void }).dispatchEvent(
        new (globalThis as unknown as { KeyboardEvent: new (t: string, o: unknown) => unknown })
          .KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }),
      );

    view('live').click();
    expect(view('live').getAttribute('aria-selected')).toBe('true');
    expect(region.dataset.view).toBe('live');
    expect(panel('live').hasAttribute('hidden')).toBe(false);
    expect(panel('schematic').hasAttribute('hidden')).toBe(true);
    expect(panel('truth').hasAttribute('hidden')).toBe(true);
    expect(doc.querySelector('.pg-hint')?.textContent).toBe('click a pin to toggle · hover a part to find it in the source');
    // Live exposes the terminal row.
    expect(doc.querySelector('.pg-term')?.hasAttribute('hidden')).toBe(false);
    expect(doc.querySelector('.pg-drawer')?.hasAttribute('hidden')).toBe(false);
    // One tab stop, and the arrows move it.
    const stops = Array.from(doc.querySelectorAll('.pg-view-switch [role=tab]')).filter((b) => (b as unknown as { tabIndex: number }).tabIndex === 0);
    expect(stops).toHaveLength(1);
    press(view('live'), 'ArrowRight');
    expect(view('truth').getAttribute('aria-selected')).toBe('true');
    press(view('truth'), 'Home');
    expect(view('schematic').getAttribute('aria-selected')).toBe('true');
    expect(doc.querySelector('.pg-hint')?.textContent).toBe('');
    expect(doc.querySelector('.pg-term')?.hasAttribute('hidden')).toBe(true);

    // The Data button toggles the card over whichever view, and the region
    // says so for the view's inset.
    const data = doc.querySelector('.pg-data-btn') as unknown as { click(): void; getAttribute(n: string): string | null };
    data.click();
    expect(data.getAttribute('aria-expanded')).toBe('true');
    expect(doc.querySelector('.pg-data-card')?.hasAttribute('hidden')).toBe(false);
    expect(region.dataset.dataOpen).toBe('true');
    expect(view('schematic').getAttribute('aria-selected')).toBe('true');
    data.click();
    expect(data.getAttribute('aria-expanded')).toBe('false');
    expect(doc.querySelector('.pg-data-card')?.hasAttribute('hidden')).toBe(true);
    expect(region.dataset.dataOpen).toBe('false');
  }));

  test('the Data card edits a real session, shares its build and rebinds after a new artifact', async () => driveAsync(async (doc) => {
    const island = (doc.querySelector('.pg') as unknown as { __playground: {
      hooks: { onArtifact(bytes: Uint8Array | null, reason: string): void };
      getSession(): Promise<SimSession | null>; showData(): Promise<void>;
    } }).__playground;
    const bytes = new Uint8Array(readFileSync(resolve(SITE, 'public/wasm/four-bit-adder.wasm')));
    const click = (selector: string) => (doc.querySelector(selector) as unknown as HTMLElement).click();
    const press = (target: HTMLElement, key: string) => target.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
    const card = doc.querySelector('.pg-data-card') as unknown as HTMLElement;
    const field = () => doc.querySelector('.pg-data-row[data-name="a"] .pg-data-in') as unknown as HTMLInputElement;
    const select = doc.querySelector('#pg-set-values') as unknown as HTMLSelectElement;
    const originalBase = select.value;
    try {
      island.hooks.onArtifact(bytes, 'compiled');
      const [session, other] = await Promise.all([island.getSession(), island.getSession()]);
      expect(session).not.toBeNull();
      expect(session === other).toBe(true);
      click('.pg-data-btn');
      await island.showData();
      expect(doc.querySelectorAll('.pg-data-section')).toHaveLength(2);
      expect(doc.querySelectorAll('.pg-data-row')).toHaveLength(4);
      expect(doc.querySelector('.pg-data table')).toBeNull();
      expect(doc.querySelector('.pg-data-summary')?.textContent).toBe('2 in · 2 out');
      click('.pg-data-base input[value="hex"]');
      expect(select.value).toBe('hex');
      field().value = '0x3';
      press(field(), 'Enter');
      expect(session!.get('a')).toMatchObject({ ok: true, value: { value: 3n } });
      expect(doc.querySelector('.pg-console-log')?.textContent).toContain('set a 0x3');
      expect(doc.querySelector('.pg-data-row[data-kind="out"] .pg-data-out')?.textContent).toBe('0x3');
      select.value = 'decimal';
      select.dispatchEvent(new Event('change', { bubbles: true }));
      expect((doc.querySelector('.pg-data-base input[value="decimal"]') as unknown as HTMLInputElement).checked).toBe(true);
      expect(field().value).toBe('3');
      field().value = '99';
      press(field(), 'Enter');
      expect(field().getAttribute('aria-invalid')).toBe('true');
      press(field(), 'Escape');
      expect(field().value).toBe('3');
      expect(card.hidden).toBe(false);
      press(field(), 'Escape');
      expect(card.hidden).toBe(true);
      expect(doc.activeElement === doc.querySelector('.pg-data-btn')).toBe(true);
      // Same shape, new artifact: controls must drive the new session.
      island.hooks.onArtifact(new Uint8Array(bytes), 'compiled');
      const next = await island.getSession();
      expect(next === session).toBe(false);
      click('.pg-data-btn');
      await island.showData();
      field().value = '5';
      field().dispatchEvent(new Event('blur'));
      expect(next!.get('a')).toMatchObject({ ok: true, value: { value: 5n } });
      click('.pg-data-reset');
      for (let i = 0; i < 100 && (doc.querySelector('.pg-data-reset') as unknown as HTMLButtonElement).disabled; i++) await new Promise((r) => setTimeout(r, 1));
      expect(next!.get('a')).toMatchObject({ ok: true, value: { defined: 0n } });
      expect(doc.querySelector('.pg-console-log')?.textContent).toContain('reset');
      // A scalar artifact exercises the round knob, including unknown.
      island.hooks.onArtifact(new Uint8Array(readFileSync(resolve(SITE, 'public/wasm/half-adder.wasm'))), 'compiled');
      await island.showData();
      const knob = doc.querySelector('.pg-data-toggle') as unknown as HTMLButtonElement;
      expect(knob.textContent).toBe('0');
      knob.click();
      expect(knob.textContent).toBe('1');
      expect(knob.getAttribute('aria-pressed')).toBe('true');
      expect(doc.querySelector('.pg-console-log')?.textContent).toContain('set a 0x1');
    } finally {
      if (!card.hidden) click('.pg-data-close');
      island.hooks.onArtifact(null, 'files-changed');
      select.value = originalBase;
      select.dispatchEvent(new Event('change', { bubbles: true }));
    }
  }));

  test('the Data grip commits only deliberate moves and restores each project position', async () => driveAsync(async (doc) => {
    const island = (doc.querySelector('.pg') as unknown as { __playground: {
      placeDataPanel(): void; dataPanelState(): { open: boolean; positions: Record<string, { x: number; y: number }> };
    } }).__playground;
    const card = doc.querySelector('.pg-data-card') as unknown as HTMLElement;
    const region = doc.querySelector('.pg-output') as unknown as HTMLElement;
    const grip = doc.querySelector('.pg-data-grip') as unknown as HTMLButtonElement;
    const originalCardRect = card.getBoundingClientRect;
    const originalRegionRect = region.getBoundingClientRect;
    let size = { width: 900, height: 600 };
    region.getBoundingClientRect = () => ({ ...size, x: 0, y: 0 }) as DOMRect;
    card.getBoundingClientRect = () => ({ width: 312, height: 260, x: 0, y: 0 }) as DOMRect;
    const Pointer = lastWindow!.PointerEvent;
    const pointer = (type: string, x: number, y: number, pointerId = 1) => grip.dispatchEvent(new Pointer(type, { clientX: x, clientY: y, pointerId, button: 0, isPrimary: true, bubbles: true }) as unknown as Event);
    const click = (selector: string) => (doc.querySelector(selector) as unknown as HTMLElement).click();
    const position = () => ({ x: Number.parseFloat(card.style.left), y: Number.parseFloat(card.style.top) });
    const id = doc.querySelector('.pg-switch-project[aria-current="true"]')!.getAttribute('data-pick')!;
    const saved = () => island.dataPanelState().positions[id];
    const drag = (x: number, y: number) => { pointer('pointerdown', 0, 0); pointer('pointermove', x, y); };
    try {
      click('.pg-data-btn');
      expect(position()).toEqual({ x: 572, y: 52 });
      drag(3, 3);
      pointer('pointerup', 3, 3);
      expect(saved()).toBeUndefined();
      expect(position()).toEqual({ x: 572, y: 52 });
      pointer('pointerdown', 0, 0);
      pointer('pointermove', -100, 80, 2);
      expect(position()).toEqual({ x: 572, y: 52 });
      pointer('pointermove', -100, 80);
      pointer('pointerup', -100, 80);
      expect(saved()).toEqual({ x: 472, y: 132 });
      drag(-50, 50);
      grip.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
      expect(card.hidden).toBe(false);
      expect(position()).toEqual(saved());
      for (const event of ['pointercancel', 'lostpointercapture']) {
        drag(-50, 50); pointer(event, -50, 50);
        expect(position()).toEqual(saved());
      }
      drag(5000, 5000); pointer('pointerup', 5000, 5000);
      expect(saved()).toEqual({ x: 588, y: 340 });
      size = { width: 400, height: 300 }; island.placeDataPanel();
      expect(position()).toEqual({ x: 88, y: 40 });
      expect(saved()).toEqual({ x: 588, y: 340 });
      size = { width: 900, height: 600 }; island.placeDataPanel();
      expect(position()).toEqual(saved());
      grip.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }));
      grip.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', shiftKey: true, bubbles: true }));
      expect(saved()).toEqual({ x: 580, y: 308 });
      drag(-100, -100);
      click('.pg-crumb'); click('.pg-switch-project[data-pick="example:half-adder"]');
      expect(card.hidden).toBe(true);
      expect(island.dataPanelState().open).toBe(false);
      expect(saved()).toEqual({ x: 580, y: 308 });
      click('.pg-data-btn');
      expect(position()).toEqual({ x: 572, y: 52 });
      click('.pg-crumb'); click(`.pg-switch-project[data-pick="${id}"]`);
      expect(card.hidden).toBe(true);
      click('.pg-data-btn');
      expect(position()).toEqual(saved());
      await new Promise((r) => setTimeout(r, 550));
      expect(JSON.parse(lastWindow!.localStorage.getItem(STORE_KEY)!).dataPanel[id]).toEqual(saved());
    } finally {
      if (!card.hidden) click('.pg-data-close');
      card.getBoundingClientRect = originalCardRect;
      region.getBoundingClientRect = originalRegionRect;
    }
  }));

  test('the truth table renders as a card of rows that drive', async () => {
    type Island = { renderTruth(json: string): Promise<void> };
    // Through the async driver: the view's module is a dynamic import, and
    // the chunk's preload helper reads `document`, which only the driver has
    // installed.
    await driveAsync(async (doc) => {
      const island = (doc.querySelector('.pg') as unknown as { __playground: Island }).__playground;
      await island.renderTruth('{"inputs":["a","b[2]"],"outputs":["out"],"rows":[{"in":[0,0],"out":[0]},{"in":[1,3],"out":[1]},{"in":[0,1],"out":[null]}]}');
      const heads = Array.from(doc.querySelectorAll('.pg-truth-card th'), (th) => (th as { textContent: string }).textContent);
      expect(heads).toEqual(['a', 'b[2]', 'out']);
      expect(doc.querySelector('.pg-truth-card th[data-symbol-name="b"]')).not.toBeNull();
      expect(doc.querySelector('.pg-truth-card th.pg-truth-first-out')?.textContent).toBe('out');
      const rows = Array.from(doc.querySelectorAll('.pg-truth-card tr[data-row]'));
      expect(rows).toHaveLength(3);
      const cells = (r: unknown) => Array.from((r as { children: ArrayLike<{ textContent: string; className: string }> }).children);
      // A bit is its digit; a bus is spelled in the reader's base (binary by default); unknown is a question.
      expect(cells(rows[1]).map((c) => c.textContent)).toEqual(['1', '0b11', '1']);
      expect(cells(rows[1]).map((c) => c.className)).toEqual(['pg-truth-high', 'pg-truth-high', 'pg-truth-high pg-truth-first-out']);
      expect(cells(rows[2]).map((c) => c.textContent)).toEqual(['0', '0b01', '?']);
      expect(cells(rows[2])[2].className).toContain('pg-truth-unknown');
      // The chip counts the rows now.
      expect(doc.querySelector('.pg-truth-chip')?.textContent).toBe('3 rows · cap 12');
      // No session in this harness: a row click is refused in the status
      // line, and nothing throws.
      (rows[1] as unknown as { click(): void }).click();
      await new Promise((r) => setTimeout(r, 50));
      expect(doc.querySelector('.pg-status')?.textContent).toBe('Compile a circuit first.');
      expect(doc.querySelector('.pg-truth-card tr[aria-current="true"]')).toBeNull();
    });
  });

  test('the breadcrumb opens the switcher without reflow and gives focus back', () => drive((doc) => {
    const press = (el: unknown, key: string) =>
      (el as { dispatchEvent(e: unknown): void }).dispatchEvent(
        new (globalThis as unknown as { KeyboardEvent: new (t: string, o: unknown) => unknown })
          .KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }),
      );
    const body = doc.querySelector('.pg-body') as unknown as { style: { getPropertyValue(n: string): string } };
    const crumb = doc.querySelector('.pg-crumb') as unknown as { click(): void; getAttribute(n: string): string | null };
    const before = body.style.getPropertyValue('--pg-source-w');
    const editor = doc.querySelector('.pg-editor') as unknown as HTMLElement;
    const width = editor.offsetWidth;
    crumb.click();
    expect(crumb.getAttribute('aria-expanded')).toBe('true');
    expect(doc.querySelector('.pg-switch')?.hasAttribute('hidden')).toBe(false);
    expect(doc.querySelector('.pg-scrim')?.hasAttribute('hidden')).toBe(false);
    expect(doc.activeElement === doc.querySelector('.pg-switch-query')).toBe(true);
    expect(doc.querySelector('.pg-crumb-chevron')?.textContent).toBe('▴');
    // Opening the card moves nothing on the bench.
    expect(body.style.getPropertyValue('--pg-source-w')).toBe(before);
    expect(editor.offsetWidth).toBe(width);
    press(doc.querySelector('.pg-switch-query'), 'Escape');
    expect(crumb.getAttribute('aria-expanded')).toBe('false');
    expect(doc.querySelector('.pg-switch')?.hasAttribute('hidden')).toBe(true);
    expect(doc.querySelector('.pg-scrim')?.hasAttribute('hidden')).toBe(true);
    expect((doc as unknown as { activeElement: unknown }).activeElement).toBe(crumb);
    expect(body.style.getPropertyValue('--pg-source-w')).toBe(before);
    expect(editor.offsetWidth).toBe(width);
  }));

  test('both search shortcuts work from the editor and yield to a text field', () => drive((doc) => {
    const content = doc.querySelector('.cm-content') as unknown as HTMLElement;
    const field = doc.querySelector('.pg-switch-query') as unknown as HTMLInputElement;
    const popup = doc.querySelector('.pg-switch') as unknown as HTMLElement;
    for (const modifier of ['metaKey', 'ctrlKey']) {
      content.focus();
      const key = new KeyboardEvent('keydown', { key: 'k', [modifier]: true, bubbles: true, cancelable: true });
      content.dispatchEvent(key);
      expect(key.defaultPrevented).toBe(true);
      expect(popup.hidden).toBe(false);
      expect(doc.activeElement === doc.querySelector('.pg-switch-query')).toBe(true);
      (doc.querySelector('.pg-scrim') as unknown as HTMLElement).click();
      expect(popup.hidden).toBe(true);
    }
    const other = doc.querySelector('.pg-console-in') as unknown as HTMLInputElement;
    const key = new KeyboardEvent('keydown', { key: 'k', ctrlKey: true, bubbles: true, cancelable: true });
    other.dispatchEvent(key);
    expect(key.defaultPrevented).toBe(false);
    expect(popup.hidden).toBe(true);
    expect(field.value).toBe('');
  }));

  test('Enter selects a sole search match; arrows walk several matches', () => drive((doc) => {
    const click = (selector: string) => (doc.querySelector(selector) as unknown as HTMLElement).click();
    const previous = doc.querySelector('.pg-switch-project[aria-current="true"]')!.getAttribute('data-pick')!;
    const field = doc.querySelector('.pg-switch-query') as unknown as HTMLInputElement;
    const popup = doc.querySelector('.pg-switch') as unknown as HTMLElement;
    const press = (target: unknown, key: string) => (target as HTMLElement).dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
    const search = (value: string) => { field.value = value; field.dispatchEvent(new Event('input', { bubbles: true })); };
    click('.pg-crumb');
    search('ripple');
    press(field, 'Enter');
    expect(popup.hidden).toBe(false);
    expect(doc.activeElement?.getAttribute('data-node')).toBe('examples');
    press(doc.activeElement, 'ArrowLeft');
    expect(doc.querySelectorAll('.pg-switch-project')).toHaveLength(0);
    expect(doc.activeElement?.getAttribute('aria-expanded')).toBe('false');
    press(doc.activeElement, 'ArrowRight');
    press(doc.activeElement, 'ArrowRight');
    expect(doc.activeElement?.getAttribute('data-pick')).toBe('example:two-bit-adder');
    press(doc.activeElement, 'Enter');
    expect(popup.hidden).toBe(true);
    expect(doc.querySelector('.pg-crumb-name')?.textContent).toBe('2-bit ripple-carry adder');
    click('.pg-crumb');
    search('4-bit ripple');
    press(field, 'Enter');
    expect(popup.hidden).toBe(true);
    expect(doc.querySelector('.pg-crumb-name')?.textContent).toBe('4-bit ripple-carry adder');
    click('.pg-crumb');
    click(`.pg-switch-project[data-pick="${previous}"]`);
    expect(popup.hidden).toBe(true);
  }));

  test('the footer opens on the counts and on the gear, and remembers which', () => drive((doc) => {
    // The playground module is imported once per process, so this reuses the
    // document the test above left behind rather than mounting a second one.
    const press = (el: unknown, key: string) =>
      (el as { dispatchEvent(e: unknown): void }).dispatchEvent(
        new (globalThis as unknown as { KeyboardEvent: new (t: string, o: unknown) => unknown })
          .KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }),
      );
    const footer = doc.querySelector('.pg-footer') as unknown as { dataset: Record<string, string> };
    const counts = doc.querySelector('.pg-footer-counts') as unknown as { click(): void; getAttribute(n: string): string | null };
    const gear = doc.querySelector('.pg-footer-gear') as unknown as { click(): void; getAttribute(n: string): string | null };
    const body = doc.querySelector('.pg-footer-body')!;
    const panel = (name: string) => doc.querySelector(`[data-footer-panel="${name}"]`)!;

    expect(footer.dataset.open).toBe('false');
    // The counts open the list, and close it again.
    counts.click();
    expect(footer.dataset.open).toBe('true');
    expect(footer.dataset.tab).toBe('diagnostics');
    expect(body.hasAttribute('hidden')).toBe(false);
    expect(counts.getAttribute('aria-expanded')).toBe('true');
    expect(panel('diagnostics').hasAttribute('hidden')).toBe(false);
    expect(panel('settings').hasAttribute('hidden')).toBe(true);
    counts.click();
    expect(footer.dataset.open).toBe('false');
    expect(counts.getAttribute('aria-expanded')).toBe('false');

    // The gear opens the settings; the counts, while open, switch the panel.
    gear.click();
    expect(footer.dataset.open).toBe('true');
    expect(footer.dataset.tab).toBe('settings');
    expect(gear.getAttribute('aria-expanded')).toBe('true');
    expect(panel('settings').hasAttribute('hidden')).toBe(false);
    expect(panel('settings').querySelectorAll('[data-setting]').length).toBeGreaterThan(0);
    counts.click();
    expect(footer.dataset.open).toBe('true');
    expect(footer.dataset.tab).toBe('diagnostics');
    expect(gear.getAttribute('aria-expanded')).toBe('false');
    // The gear on its own panel is the close gesture.
    gear.click();
    gear.click();
    expect(footer.dataset.open).toBe('false');
    expect(footer.dataset.tab).toBe('settings');

    // Escape in the body closes it and hands focus back to the opener.
    gear.click();
    press(panel('settings').querySelector('[data-setting]'), 'Escape');
    expect(footer.dataset.open).toBe('false');
    expect((doc as unknown as { activeElement: unknown }).activeElement).toBe(gear);
  }));

  test('diagnostics render as grid rows', () => drive((doc) => {
    type Island = { state: { mapped: unknown[] }; renderDiagnostics(): void };
    const island = (doc.querySelector('.pg') as unknown as { __playground: Island }).__playground;
    const row = (over: Record<string, unknown>) => ({
      from: 0, to: 5, severity: 'error', code: 'E001', message: 'unknown component', fileName: 'main.circ',
      line: 2, column: 3, docLine: 1, tab: 0, ...over,
    });
    island.state.mapped = [
      row({}),
      row({ severity: 'warning', code: 'W002', message: 'unused wire', line: 4, column: 1 }),
      // The compiler blamed a builtin file: no buffer, no jump.
      row({ severity: 'warning', code: 'W003', fileName: '<builtin>/xor.circ', from: null, to: null, tab: null, docLine: null }),
    ];
    island.renderDiagnostics();
    expect(doc.querySelector('.pg-footer-counts-text')?.textContent).toBe('1 error · 2 warnings');
    expect(doc.querySelector('.pg-footer-counts')?.getAttribute('data-severity')).toBe('error');
    const rows = Array.from(doc.querySelectorAll('.pg-diag .pg-diag-row'));
    expect(rows).toHaveLength(3);
    const cells = (r: unknown) => Array.from((r as { children: ArrayLike<{ className: string; textContent: string; tagName: string }> }).children);
    expect(cells(rows[0]).map((c) => c.className)).toEqual(['pg-diag-glyph', 'pg-diag-pos', 'pg-diag-code', 'pg-diag-msg']);
    expect(cells(rows[0]).map((c) => c.textContent)).toEqual(['▲', 'main.circ:2:3', 'E001', 'unknown component']);
    expect(cells(rows[0])[1].tagName).toBe('BUTTON');
    expect((rows[0] as unknown as { dataset: Record<string, string> }).dataset.severity).toBe('error');
    // A placeless row shows its position as text, not as a button.
    expect(cells(rows[2])[1].tagName).toBe('SPAN');
    expect(cells(rows[2])[1].textContent).toMatch(/^<builtin>\/xor\.circ:/);
    // Back to nothing, and the bar follows.
    island.state.mapped = [];
    island.renderDiagnostics();
    expect(doc.querySelector('.pg-diag-none')?.textContent).toBe('No diagnostics.');
    expect(doc.querySelector('.pg-footer-counts')?.getAttribute('data-severity')).toBe('none');
  }));

  test('the console\'s Clear on an empty log is harmless, and Copy says what went', async () => {
    drive((doc) => {
      const click = (sel: string) => (doc.querySelector(sel) as unknown as { click(): void }).click();
      click('.pg-console-btn[data-console="clear"]');
      expect(doc.querySelector('.pg-console-log')?.textContent).toBe('');
      click('.pg-console-btn[data-console="script"]');
    });
    // The clipboard answers in a microtask (or is absent, which is a sentence too).
    await new Promise((r) => setTimeout(r, 0));
    drive((doc) => {
      expect(doc.querySelector('.pg-status')?.textContent).toMatch(/^Clipboard unavailable|^Copied 0 command lines\./);
    });
  });

  test('the terminal row hides in Schematic and restores its drawer in Live and Truth', () => drive((doc) => {
    type Island = { consoleAppend(lines: readonly string[]): void };
    const island = (doc.querySelector('.pg') as unknown as { __playground: Island }).__playground;
    const term = doc.querySelector('.pg-term') as unknown as HTMLElement;
    const frame = doc.querySelector('.pg') as unknown as { style: { getPropertyValue(n: string): string } };
    const drawer = doc.querySelector('.pg-drawer') as unknown as { dataset: Record<string, string> };
    const separator = doc.querySelector('.pg-drawer-splitter')!;
    const open = (name: string) => doc.querySelector(`.pg-term-open[data-term="${name}"]`) as unknown as { click(): void };
    const toggle = doc.querySelector('.pg-drawer-close') as unknown as { click(): void };
    (doc.querySelector('.pg-drawer-close') as unknown as HTMLElement).click();

    // Whatever the view, the row is there and shut.
    const view = (name: string) => doc.querySelector(`.pg-view-tab[data-view="${name}"]`) as unknown as { click(): void };
    view('live').click();
    expect(term.hidden).toBe(false);
    expect(term.dataset.open).toBe('false');
    view('schematic').click();
    expect(term.hidden).toBe(true);
    expect(term.hasAttribute('inert')).toBe(true);
    expect(frame.style.getPropertyValue('--pg-term-h')).toBe('0px');
    open('console').click();
    expect(term.dataset.open).toBe('false');
    view('truth').click();
    expect(term.hidden).toBe(false);
    expect(term.hasAttribute('inert')).toBe(false);

    // The line reads the transcript: the last echo and the first reply.
    island.consoleAppend(['> set a 1', 'ok']);
    expect(doc.querySelector('.pg-term-cmd')?.textContent).toBe('set a 1');
    expect(doc.querySelector('.pg-term-reply')?.textContent).toBe('ok');
    island.consoleAppend(['> get out']);
    expect(doc.querySelector('.pg-term-cmd')?.textContent).toBe('get out');
    expect(doc.querySelector('.pg-term-reply')?.textContent).toBe('');

    // Console opens the drawer on the console; the row grows on the frame.
    open('console').click();
    expect(term.dataset.open).toBe('true');
    expect(drawer.dataset.open).toBe('true');
    expect(frame.style.getPropertyValue('--pg-term-h')).toBe('var(--pg-drawer-h, 320px)');
    expect(separator.hasAttribute('hidden')).toBe(false);
    (doc.querySelector('.pg-drawer-close') as unknown as HTMLElement).focus();
    view('schematic').click();
    expect(term.hidden).toBe(true);
    expect(drawer.dataset.open).toBe('true');
    expect(separator.hasAttribute('hidden')).toBe(true);
    expect(frame.style.getPropertyValue('--pg-term-h')).toBe('0px');
    expect(doc.activeElement === doc.querySelector('.pg-view-tab[data-view="schematic"]')).toBe(true);
    view('truth').click();
    expect(term.hidden).toBe(false);
    expect(drawer.dataset.open).toBe('true');
    expect(frame.style.getPropertyValue('--pg-term-h')).toBe('var(--pg-drawer-h, 320px)');
    view('live').click();
    expect(term.hidden).toBe(false);
    expect(drawer.dataset.open).toBe('true');
    // The drawer bar's toggle closes it, and the frame's row goes back.
    toggle.click();
    expect(term.dataset.open).toBe('false');
    expect(frame.style.getPropertyValue('--pg-term-h')).toBe('');
    // The selected tab is the reopen gesture, as on the dock.
    open('console').click();
    expect(term.dataset.open).toBe('true');
    open('console').click();
    expect(term.dataset.open).toBe('false');
    // Memory is inert until the circuit declares one.
    open('memory').click();
    expect(term.dataset.open).toBe('false');
    view('schematic').click();
  }));

  test('the drawer grows on focus, saves its height and closes only after clearing the prompt', async () => driveAsync(async (doc) => {
    const island = (doc.querySelector('.pg') as unknown as { __playground: {
      hooks: { onArtifact(bytes: Uint8Array | null, reason: string): void }; getSession(): Promise<SimSession | null>;
    } }).__playground;
    const drawer = doc.querySelector('.pg-drawer') as unknown as HTMLElement;
    const input = doc.querySelector('.pg-console-in') as unknown as HTMLInputElement;
    const separator = doc.querySelector('.pg-drawer-splitter') as unknown as HTMLElement;
    const close = doc.querySelector('.pg-drawer-close') as unknown as HTMLButtonElement;
    const press = (el: HTMLElement, key: string) => el.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
    try {
      (doc.querySelector('.pg-view-tab[data-view="truth"]') as unknown as HTMLElement).click();
      island.hooks.onArtifact(new Uint8Array(readFileSync(resolve(SITE, 'public/wasm/half-adder.wasm'))), 'compiled');
      await island.getSession();
      (doc.querySelector('.pg-term-line') as unknown as HTMLElement).focus();
      expect(drawer.dataset.open).toBe('true');
      expect(separator.hidden).toBe(false);
      expect(doc.activeElement === doc.querySelector('.pg-console-in')).toBe(true);
      press(separator, 'ArrowUp');
      window.dispatchEvent(new Event('pagehide'));
      expect(JSON.parse(localStorage.getItem(STORE_KEY)!).drawerHeight).toBe(336);
      input.value = 'set a 1';
      (doc.querySelector('.pg-console-form') as unknown as HTMLElement).dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
      await new Promise((r) => setTimeout(r, 0));
      press(input, 'ArrowUp');
      expect(input.value).toBe('set a 1');
      press(input, 'Escape');
      expect(input.value).toBe('');
      expect(drawer.dataset.open).toBe('true');
      press(input, 'ArrowDown');
      expect(input.value).toBe('');
      press(input, 'Escape');
      expect(drawer.dataset.open).toBe('false');
      expect(separator.hidden).toBe(true);
      input.focus();
      expect(drawer.dataset.open).toBe('true');
      close.click();
      expect(drawer.dataset.open).toBe('false');
    } finally {
      close.click();
      island.hooks.onArtifact(null, 'files-changed');
      (doc.querySelector('.pg-view-tab[data-view="schematic"]') as unknown as HTMLElement).click();
    }
  }));

  test('search finds a project in a collapsed group and restores the tree', () => drive((doc) => {
    (doc.querySelector('.pg-crumb') as unknown as HTMLElement).click();
    const group = () => doc.querySelector('.pg-switch-group[data-node="examples"]') as unknown as HTMLElement;
    group().click();
    expect(group().getAttribute('aria-expanded')).toBe('false');
    const field = doc.querySelector('.pg-switch-query') as unknown as HTMLInputElement;
    const search = (value: string) => {
      field.value = value;
      field.dispatchEvent(new Event('input', { bubbles: true }));
    };
    search('  4-BIT RIPPLE ');
    expect(doc.querySelectorAll('.pg-switch-project')).toHaveLength(1);
    expect(doc.querySelector('.pg-switch-project')?.getAttribute('data-pick')).toBe('example:four-bit-adder');
    field.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
    expect(doc.activeElement?.getAttribute('data-node')).toBe('examples');
    search('does not exist');
    expect(doc.querySelectorAll('.pg-switch-row')).toHaveLength(0);
    expect(doc.querySelector('.pg-switch-empty')?.textContent).toBe('No circuits found.');
    search('');
    expect(group().getAttribute('aria-expanded')).toBe('false');
    group().click();
    (doc.querySelector('.pg-crumb') as unknown as HTMLElement).click();
  }));

  test('a group collapses and reopens, taking its projects with it', () => drive((doc) => {
    (doc.querySelector('.pg-crumb') as unknown as HTMLElement).click();
    const rows = () => Array.from(doc.querySelectorAll('.pg-switch-row'));
    const openGroup = doc.querySelector('.pg-switch-group[aria-expanded="true"]') as unknown as
      { click(): void; getAttribute(n: string): string | null };
    const before = rows().length;

    openGroup.click();
    const shut = rows().length;
    // Shutting a group removes its projects — and the open project's files
    // with them — rather than leaving hidden rows the arrow keys could reach.
    expect(shut).toBeLessThan(before);
    expect(doc.querySelector('.pg-switch-group[aria-expanded="true"]')).not.toBe(openGroup);

    openGroup.click();
    expect(rows().length).toBe(before);
    expect(openGroup.getAttribute('aria-expanded')).toBe('true');

    // Still exactly one tab stop after two redraws.
    const stops = rows().filter((r) => (r as unknown as { tabIndex: number }).tabIndex === 0);
    expect(stops).toHaveLength(1);
    (doc.querySelector('.pg-crumb') as unknown as HTMLElement).click();
  }));

  test('files are added, switched and deleted from the tree', () => drive((doc) => {
    // Everything here used to live on the strip above the editor. This is the
    // proof that moving it did not quietly drop half of it.
    (doc.querySelector('.pg-crumb') as unknown as HTMLElement).click();
    const fileRows = () => Array.from(doc.querySelectorAll('.pg-switch-file'));
    const labelOf = (r: unknown): string =>
      (r as { querySelector(s: string): { textContent: string } | null })
        .querySelector('.pg-switch-label')?.textContent ?? '';
    const click = (el: unknown) => (el as { click(): void }).click();

    expect(fileRows()).toHaveLength(1);
    const firstName = labelOf(fileRows()[0]);

    // The ＋ on the open project row is the add-file control the strip had.
    const add = doc.querySelector('.pg-switch-project[aria-current="true"] .pg-switch-add');
    expect(add).not.toBeNull();
    click(add);
    expect(fileRows()).toHaveLength(2);

    // The last file is the root, and only it carries the chip.
    const roots = fileRows().filter((r) => (r as unknown as Element).querySelector('.pg-switch-root'));
    expect(roots).toHaveLength(1);
    expect(labelOf(roots[0])).toBe(labelOf(fileRows()[1]));
    // Adding a file selects it, and exactly one row is ever current.
    expect(doc.querySelectorAll('.pg-switch-file[aria-current="true"]')).toHaveLength(1);

    // A new file is inserted BEFORE the root, so the root stays last and the
    // original file is still the one the compiler starts from.
    expect(labelOf(fileRows()[1])).toBe(firstName);
    // Switching files by clicking a row.
    click(fileRows()[1]);
    expect(labelOf(doc.querySelector('.pg-switch-file[aria-current="true"]'))).toBe(firstName);
    expect(doc.querySelector('.pg-switch')?.hasAttribute('hidden')).toBe(true);
    click(doc.querySelector('.pg-crumb'));

    // Delete is two presses, as it was on the strip: the first only arms. The
    // button is named rather than taken by position — a file row carries a
    // rename control too, and "the first action" is not a stable thing to mean.
    const deleteOn = (sel: string) => doc.querySelector(`${sel} .pg-switch-action[aria-label^="Delete"]`);
    click(deleteOn('.pg-switch-file'));
    expect(fileRows()).toHaveLength(2);
    expect(doc.querySelector('.pg-switch-file[data-confirm="true"]')).not.toBeNull();
    click(deleteOn('.pg-switch-file[data-confirm="true"]'));
    expect(fileRows()).toHaveLength(1);

    // …and the last remaining file refuses to go, so a project always has one.
    click(deleteOn('.pg-switch-file'));
    click(deleteOn('.pg-switch-file'));
    click(doc.querySelector('.pg-crumb'));
    expect(fileRows()).toHaveLength(1);
  }));

  test('a file is renamed from the tree, and a bad name is refused', () => drive((doc) => {
    (doc.querySelector('.pg-crumb') as unknown as HTMLElement).click();
    const fileRows = () => Array.from(doc.querySelectorAll('.pg-switch-file'));
    const labelOf = (r: unknown): string =>
      (r as { querySelector(s: string): { textContent: string } | null })
        .querySelector('.pg-switch-label')?.textContent ?? '';
    const click = (el: unknown) => (el as { click(): void }).click();
    const press = (el: unknown, key: string) =>
      (el as { dispatchEvent(e: unknown): void }).dispatchEvent(
        new (globalThis as unknown as { KeyboardEvent: new (t: string, o: unknown) => unknown })
          .KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }),
      );

    const before = labelOf(fileRows()[0]);
    const renameBtn = doc.querySelector('.pg-switch-file .pg-switch-action[aria-label^="Rename"]');
    expect(renameBtn).not.toBeNull();

    // The label is swapped for an input carrying the current name.
    click(renameBtn);
    let input = doc.querySelector('.pg-switch-file .pg-switch-input') as unknown as
      { value: string; getAttribute(n: string): string | null; blur(): void };
    expect(input).not.toBeNull();
    expect(input.value).toBe(before);

    // A name the marker format cannot represent is refused in place: the input
    // stays, and the reason lands in the tree's error line.
    input.value = 'not a file name!';
    press(doc.querySelector('.pg-switch-file .pg-switch-input'), 'Enter');
    expect(doc.querySelector('.pg-switch-file .pg-switch-input')).not.toBeNull();
    expect(doc.querySelector('.pg-switch-error')?.textContent ?? '').not.toBe('');
    expect(labelOf(fileRows()[0])).toBe('');

    // Escape reverts, leaving the original name and clearing the complaint.
    press(doc.querySelector('.pg-switch-file .pg-switch-input'), 'Escape');
    expect(doc.querySelector('.pg-switch-file .pg-switch-input')).toBeNull();
    expect(labelOf(fileRows()[0])).toBe(before);
    expect(doc.querySelector('.pg-switch-error')?.textContent ?? '').toBe('');

    // A legal name commits, and the row shows it.
    click(doc.querySelector('.pg-switch-file .pg-switch-action[aria-label^="Rename"]'));
    input = doc.querySelector('.pg-switch-file .pg-switch-input') as never;
    input.value = 'renamed.circ';
    press(doc.querySelector('.pg-switch-file .pg-switch-input'), 'Enter');
    expect(doc.querySelector('.pg-switch-file .pg-switch-input')).toBeNull();
    expect(labelOf(fileRows()[0])).toBe('renamed.circ');

    // F2 opens the same editor, so the keyboard path did not go away.
    press(fileRows()[0], 'F2');
    expect(doc.querySelector('.pg-switch-file .pg-switch-input')).not.toBeNull();
    press(doc.querySelector('.pg-switch-file .pg-switch-input'), 'Escape');
    click(doc.querySelector('.pg-crumb'));
    expect(labelOf(fileRows()[0])).toBe('renamed.circ');
  }));

  test('scratch row actions remain keyboard-reachable through rename, duplicate and delete', () => drive((doc) => {
    const click = (selector: string) => (doc.querySelector(selector) as unknown as HTMLElement).click();
    const current = () => doc.querySelector('.pg-switch-project[aria-current="true"]') as unknown as HTMLElement;
    const press = (target: HTMLElement, key: string) => {
      const event = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
      target.dispatchEvent(event);
      return event;
    };
    click('.pg-crumb');
    const previous = current().dataset.pick!;
    click('.pg-switch-new');
    if (doc.querySelector('.pg-switch')!.hasAttribute('hidden')) click('.pg-crumb');
    const id = current().dataset.pick!;
    expect(id.startsWith('scratch:')).toBe(true);
    const name = current().querySelector('.pg-switch-label')!.textContent!;
    current().focus();
    expect(current().querySelector<HTMLButtonElement>('.pg-switch-action')!.tabIndex).toBe(0);
    press(current(), 'F2');
    const rename = doc.querySelector('.pg-switch-input') as unknown as HTMLInputElement;
    const shortcut = new KeyboardEvent('keydown', { key: 'k', ctrlKey: true, bubbles: true, cancelable: true });
    rename.dispatchEvent(shortcut);
    expect(shortcut.defaultPrevented).toBe(false);
    expect(doc.activeElement === doc.querySelector('.pg-switch-input')).toBe(true);
    rename.value = 'Keyboard project';
    press(rename, 'Enter');
    expect(doc.querySelector('.pg-crumb-name')?.textContent).toBe('Keyboard project');
    const duplicate = current().querySelector<HTMLButtonElement>('[aria-label^="Duplicate"]')!;
    duplicate.focus();
    expect(press(duplicate, 'Enter').defaultPrevented).toBe(false);
    duplicate.click();
    const duplicateId = current().dataset.pick!;
    expect(duplicateId).not.toBe(id);
    expect(current().querySelector('.pg-switch-label')?.textContent).toBe('Keyboard project 2');
    current().querySelector<HTMLButtonElement>('[aria-label^="Delete"]')!.click();
    expect(current().querySelector('[data-confirm="true"]')).not.toBeNull();
    current().querySelector<HTMLButtonElement>('[aria-label^="Delete"]')!.click();
    expect(doc.querySelector(`.pg-switch-project[data-pick="${duplicateId}"]`)).toBeNull();
    click(`.pg-switch-project[data-pick="${id}"]`);
    click('.pg-crumb');
    press(current(), 'F2');
    const restoreName = doc.querySelector('.pg-switch-input') as unknown as HTMLInputElement;
    restoreName.value = name;
    press(restoreName, 'Enter');
    current().querySelector<HTMLButtonElement>('[aria-label^="Delete"]')!.click();
    current().querySelector<HTMLButtonElement>('[aria-label^="Delete"]')!.click();
    click(`.pg-switch-project[data-pick="${previous}"]`);
    if (!doc.querySelector('.pg-switch')!.hasAttribute('hidden')) click('.pg-crumb');
  }));

  test('Import .circ keeps the source, numbers duplicate names and refuses failed reads', async () => driveAsync(async (doc) => {
    const DiskFile = lastWindow!.File;
    const popup = doc.querySelector('.pg-switch') as unknown as HTMLElement;
    const picker = doc.querySelector('.pg-switch-picker') as unknown as HTMLInputElement;
    const button = doc.querySelector('.pg-switch-import') as unknown as HTMLButtonElement;
    const click = (selector: string) => (doc.querySelector(selector) as unknown as HTMLElement).click();
    const open = () => { if (popup.hidden) click('.pg-crumb'); };
    const activeId = () => doc.querySelector('.pg-switch-project[aria-current="true"]')!.getAttribute('data-pick')!;
    const previous = activeId();
    const added: string[] = [];
    const source = '// blink from disk\ninput a\noutput out(in=a)\n';
    const pick = (file: unknown) => {
      open();
      Object.defineProperty(picker, 'files', { configurable: true, value: file ? [file] : [] });
      picker.dispatchEvent(new Event('change', { bubbles: true }));
    };
    const settled = async () => {
      for (let i = 0; i < 100 && picker.disabled; i++) await new Promise((r) => setTimeout(r, 1));
      expect(picker.disabled).toBe(false);
      expect(button.disabled).toBe(false);
      expect(picker.value).toBe('');
    };
    expect(picker.accept).toBe('.circ');
    expect(picker.multiple).toBe(false);
    for (const name of ['blink', 'blink 2']) {
      pick(new DiskFile([source], 'blink.circ'));
      expect(button.disabled).toBe(true);
      await settled();
      added.push(activeId());
      expect(activeId().startsWith('scratch:')).toBe(true);
      expect(doc.querySelector('.pg-crumb-group')?.textContent).toBe('Mine /');
      expect(doc.querySelector('.pg-crumb-name')?.textContent).toBe(name);
      expect(popup.hidden).toBe(true);
      expect(doc.querySelector('.pg-status')?.textContent).toBe('Imported blink.circ.');
      const island = (doc.querySelector('.pg') as unknown as { __playground: { state: { tabs: { files: { body: string }[] } } } }).__playground;
      expect(island.state.tabs.files[0].body).toBe(source);
    }
    const beforeRefusal = activeId();
    pick(new DiskFile(['é'.repeat(MAX_SOURCE_BYTES / 2) + 'x'], 'big.circ'));
    await settled();
    expect(activeId()).toBe(beforeRefusal);
    expect(doc.querySelector('.pg-status')?.textContent).toBe('Could not import big: each circuit must fit in 32 KiB.');
    const unreadable = new DiskFile([], 'lost.circ');
    Object.defineProperty(unreadable, 'text', { value: async () => { throw new Error('read failed'); } });
    pick(unreadable);
    await settled();
    expect(doc.querySelector('.pg-status')?.textContent).toBe('Could not read lost.circ.');
    expect(activeId()).toBe(beforeRefusal);
    pick(null);
    expect(picker.disabled).toBe(false);
    let release!: (value: string) => void;
    const slow = new DiskFile([], 'slow.circ');
    Object.defineProperty(slow, 'text', { value: () => new Promise<string>((resolve) => { release = resolve; }) });
    pick(slow);
    pick(new DiskFile([source], 'ignored.circ'));
    release(source);
    await settled();
    added.push(activeId());
    expect(doc.querySelector('.pg-crumb-name')?.textContent).toBe('slow');
    await new Promise((r) => setTimeout(r, 550));
    const saved = JSON.parse(lastWindow!.localStorage.getItem(STORE_KEY)!);
    expect(saved.scratch.filter((p: { id: string }) => added.includes(p.id)).map((p: { source: string }) => p.source)).toEqual([source, source, source]);
    expect(saved.scratch.some((p: { name: string }) => ['big', 'lost', 'ignored'].includes(p.name))).toBe(false);
    open();
    for (const id of added) {
      const selector = `.pg-switch-project[data-pick="${id}"] .pg-switch-action[aria-label^="Delete"]`;
      click(selector); click(selector);
    }
    click(`.pg-switch-project[data-pick="${previous}"]`);
    if (!popup.hidden) click('.pg-crumb');
  }));

  test('the memory grid refuses a bad word without closing, and Load image opens', () => drive((doc) => {
    (doc.querySelector('.pg-view-tab[data-view="truth"]') as unknown as HTMLElement).click();
    // The panel exists only once an analysis reports a memory, and no headless
    // harness can run the worker that produces one — so the island's own seam
    // is handed a minimal analysis declaring `rom code[8, 4]`.
    const island = (doc.querySelector('.pg') as unknown as {
      __playground: { state: Record<string, unknown>; renderMemory(): void };
    }).__playground;
    const files = (island.state.tabs as { files: { name: string }[] }).files;
    const rootName = files[files.length - 1].name;
    island.state.analysis = {
      files: [{ file_id: 0, path: `/playground/${rootName}` }],
      diagnostics: [],
      symbols: [{ file_id: 0, kind: 'rom', name: 'code', width: 8, addr_width: 4, range: {} }],
      references: [],
    };
    island.renderMemory();

    (doc.querySelector('.pg-term-mem') as unknown as HTMLElement).click();

    const click = (el: unknown) => (el as { click(): void }).click();
    const press = (el: unknown, key: string) =>
      (el as { dispatchEvent(e: unknown): void }).dispatchEvent(
        new (globalThis as unknown as { KeyboardEvent: new (t: string, o: unknown) => unknown })
          .KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }),
      );
    const fire = (el: unknown, type: string) =>
      (el as { dispatchEvent(e: unknown): void }).dispatchEvent(
        new (globalThis as unknown as { Event: new (t: string, o: unknown) => unknown })
          .Event(type, { bubbles: true }),
      );
    const cells = () => Array.from(doc.querySelectorAll('.pg-mem-cell'));
    const errorLine = () => doc.querySelector('.pg-mem-error')?.textContent ?? '';

    // The tab is no longer hidden, and the grid is the memory's exact size.
    expect(doc.querySelector('.pg-drawer')?.hasAttribute('data-mem')).toBe(true);
    expect(doc.querySelector('.pg-drawer-mem')?.hasAttribute('hidden')).toBe(false);
    expect(cells()).toHaveLength(16);
    expect(Array.from(doc.querySelectorAll('.pg-mem-table thead th'), (h) => h.textContent)).toEqual(['addr', '+0', '+1', '+2', '+3', '+4', '+5', '+6', '+7']);
    expect(Array.from(doc.querySelectorAll('.pg-mem-table tbody .pg-mem-addr'), (h) => h.textContent)).toEqual(['0', '8']);
    // Nothing runs in this harness, so the image can be edited but not saved.
    expect((doc.querySelector('.pg-mem-save') as unknown as { disabled: boolean }).disabled).toBe(true);
    expect(cells().every((c) => (c as unknown as { textContent: string }).textContent === '?')).toBe(true);

    // Open a cell.
    const cell = cells()[0] as unknown as { dispatchEvent(e: unknown): void };
    fire(cell, 'dblclick');
    expect(doc.querySelector('.pg-mem-cell[data-editing="true"]')).not.toBeNull();
    const input = () => doc.querySelector('.pg-mem-input') as unknown as
      { value: string; maxLength: number; getAttribute(n: string): string | null } | null;
    expect(input()).not.toBeNull();

    // Characters that cannot begin any legal word never land.
    const box = input()!;
    box.value = 'zqg!';
    fire(doc.querySelector('.pg-mem-input'), 'input');
    expect(input()!.value).toBe('');

    // The shipped default value format is binary, so nine binary digits is the
    // overflow case for an eight-bit word. A word too wide is refused IN
    // PLACE: the editor stays open holding what was typed, and the reason
    // appears under the grid rather than in the status bar at the page foot.
    box.value = '100000000';
    press(doc.querySelector('.pg-mem-input'), 'Enter');
    expect(input()).not.toBeNull();
    expect(input()!.value).toBe('100000000');
    expect(input()!.getAttribute('aria-invalid')).toBe('true');
    expect(errorLine()).toContain('255');

    // Typing again is the reader answering the complaint, so it clears.
    box.value = '11111111';
    fire(doc.querySelector('.pg-mem-input'), 'input');
    expect(input()!.getAttribute('aria-invalid')).toBe('false');
    expect(errorLine()).toBe('');

    // …and a legal word commits and closes.
    press(doc.querySelector('.pg-mem-input'), 'Enter');
    expect(doc.querySelector('.pg-mem-input')).toBeNull();
    expect((cells()[0] as unknown as { textContent: string }).textContent).toBe('11111111');

    // "Load image" actually opens the hex box and the file picker. It did
    // nothing before: a checkbox is an INPUT, and the panel's own guard against
    // redrawing a field being typed into swallowed the redraw.
    expect(doc.querySelector('.pg-mem-hex')).toBeNull();
    const toggle = doc.querySelector('.pg-mem-load') as unknown as HTMLButtonElement;
    expect(toggle.textContent).toBe('Load image…');
    expect(doc.querySelector('.pg-mem-shape')?.textContent).toBe('rom[8,4] · 16 words');
    expect(Array.from(doc.querySelectorAll('.pg-mem-tools [data-mem]'), (b) => b.getAttribute('data-mem'))).toEqual(['refresh', 'clear', 'load', 'save']);
    // Focused and clicked, not just `checked = true`: a real click focuses the
    // box, and the focus is the whole bug. Setting the property from outside
    // leaves the document focused elsewhere and the defect cannot reproduce.
    toggle.focus();
    toggle.click();
    expect(doc.querySelector('.pg-mem-load')?.getAttribute('aria-expanded')).toBe('true');
    expect(doc.querySelector('.pg-mem-hex')).not.toBeNull();
    expect(doc.querySelector('.pg-rom-box')).not.toBeNull();
    expect(doc.querySelector('.pg-mem-file')?.getAttribute('type')).toBe('file');
    // The hex reflects the word just written through the grid.
    expect((doc.querySelector('.pg-rom-box') as unknown as { value: string }).value).toBe('ff');

    // Unticking closes it again.
    (doc.querySelector('.pg-mem-load') as unknown as HTMLButtonElement).focus();
    (doc.querySelector('.pg-mem-load') as unknown as HTMLButtonElement).click();
    expect(doc.querySelector('.pg-mem-hex')).toBeNull();
    (doc.querySelector('.pg-mem-base input[value="hex"]') as unknown as HTMLInputElement).click();
    expect(cells()[0].textContent).toBe('ff');
    expect((doc.querySelector('#pg-set-values') as unknown as HTMLSelectElement).value).toBe('hex');
    expect((doc.querySelector('.pg-data-base input[value="hex"]') as unknown as HTMLInputElement).checked).toBe(true);
    const select = doc.querySelector('#pg-set-values') as unknown as HTMLSelectElement;
    select.value = 'binary'; select.dispatchEvent(new Event('change', { bubbles: true }));
    expect(cells()[0].textContent).toBe('11111111');
    (doc.querySelector('.pg-drawer-close') as unknown as HTMLElement).click();
    (doc.querySelector('.pg-view-tab[data-view="schematic"]') as unknown as HTMLElement).click();
  }));

  test('Download follows the artifact, and saves it under the project\'s name', async () => {
    // No harness can run the worker that builds an artifact, so the island's
    // state is handed one directly and its refresh seam is called, the way
    // the compile reply does.
    type Island = {
      state: { artifact: unknown; stale: boolean };
      refreshActions(): void;
      setStale(stale: boolean): void;
    };
    const saved: { name: string; href: string }[] = [];
    const island = drive((doc) => {
      const button = doc.querySelector('.pg-download') as unknown as { disabled: boolean; title: string };
      expect(button.disabled).toBe(true);
      expect(button.title).toBe('Compile a circuit first');
      expect(doc.querySelector('.pg-download .pg-action-label')?.textContent).toBe('Download');
      expect(doc.querySelector('.pg-download .pg-action-meta')?.textContent).toBe('');
      // The anchor the click creates is caught here, before happy-dom tries
      // to navigate to a blob: URL.
      doc.addEventListener('click', (e) => {
        const t = (e as { target: { tagName?: string; download?: string; href?: string } }).target;
        if (t.tagName === 'A' && t.download) {
          saved.push({ name: t.download, href: t.href ?? '' });
          (e as { preventDefault(): void }).preventDefault();
        }
      }, true);
      return (doc.querySelector('.pg') as unknown as { __playground: Island }).__playground;
    });

    island.state.artifact = { bytes: new Uint8Array([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0]), hash: 7, size: 8 };
    island.state.stale = false;
    island.refreshActions();
    drive((doc) => {
      const button = doc.querySelector('.pg-download') as unknown as { disabled: boolean; title: string; click(): void; hasAttribute(n: string): boolean };
      expect(button.disabled).toBe(false);
      expect(button.title).toMatch(/^Download [a-z0-9-]+\.wasm \(8 B\)$/);
      // The button says what it would save, and how big it is.
      expect(doc.querySelector('.pg-download .pg-action-label')?.textContent).toMatch(/^[a-z0-9-]+\.wasm$/);
      expect(doc.querySelector('.pg-download .pg-action-meta')?.textContent).toBe('8 B');
      expect(button.hasAttribute('data-stale')).toBe(false);
      button.click();
      expect(saved).toHaveLength(1);
      expect(saved[0].name).toMatch(/^[a-z0-9-]+\.wasm$/);
      expect(saved[0].href.startsWith('blob:')).toBe(true);
      expect(doc.querySelector('.pg-status')?.textContent).toMatch(/^Saved [a-z0-9-]+\.wasm \(8 B\)\.$/);
      expect(doc.querySelector('.pg-download')?.getAttribute('data-state')).toBe('done');
      // The anchor was a means, not a leftover.
      expect(doc.querySelector('.pg-nav a[download]')).toBeNull();
    });

    // A build the source has moved past is still offered, and says so. This
    // goes through the island's own setStale, the path the compile reply
    // takes, so a refresh dropped from it fails here.
    island.setStale(true);
    drive((doc) => {
      const button = doc.querySelector('.pg-download') as unknown as { disabled: boolean; title: string; hasAttribute(n: string): boolean };
      expect(button.disabled).toBe(false);
      expect(button.hasAttribute('data-stale')).toBe(true);
      expect(button.title).toContain('the source has changed');
    });

    // And no build is no button.
    island.state.artifact = null;
    island.setStale(false);
    drive((doc) => {
      expect((doc.querySelector('.pg-download') as unknown as { disabled: boolean }).disabled).toBe(true);
    });
  });

  test('Share copies a link and says so on the button and in the status line', async () => {
    const written: string[] = [];
    await driveAsync(async (doc) => {
      // happy-dom's clipboard is a stub; record what the island hands it.
      const nav = globalThis.navigator as unknown as { clipboard?: { writeText(t: string): Promise<void> } };
      Object.defineProperty(nav, 'clipboard', {
        configurable: true,
        value: { writeText: async (t: string) => { written.push(t); } },
      });
      (doc.querySelector('.pg-share') as unknown as { click(): void }).click();
      // The handler is async — an encode through a CompressionStream and the
      // clipboard write — so the globals have to outlive the click.
      await new Promise((r) => setTimeout(r, 100));
      expect(written).toHaveLength(1);
      expect(written[0]).toMatch(/#src0?=[A-Za-z0-9_-]+$/);
      expect(doc.querySelector('.pg-status')?.textContent).toMatch(/^Link copied \(\d+ characters\)\.$/);
      expect(doc.querySelector('.pg-share')?.getAttribute('data-state')).toBe('done');
      expect(doc.querySelector('.pg-share .pg-action-label')?.textContent).toBe('Copied');
      expect((doc.querySelector('.pg-share') as unknown as { disabled: boolean }).disabled).toBe(false);
    });
  });

  test('every canvas that asks to auto-run is watched, and nothing else is', async () => {
    FakeIntersectionObserver.instances.length = 0;
    const { doc, errors } = await runIsland('gallery', 'LiveCanvas.astro');
    expect(errors).toEqual([]);

    // One observer for the page, watching every opted-in card and nothing else.
    expect(FakeIntersectionObserver.instances).toHaveLength(1);
    const watcher = FakeIntersectionObserver.instances[0];
    const cards = Array.from(doc.querySelectorAll('.lc[data-circ-autorun]'));
    expect(cards.length).toBeGreaterThan(1);
    // Compared by artifact name rather than by node. A failed `toEqual` on
    // happy-dom elements makes bun serialise fourteen DOM trees to build its
    // diff, and the run never finishes — a test whose failure mode is a hang
    // is worse than no test.
    const nameOf = (el: unknown) =>
      (el as { getAttribute(n: string): string | null }).getAttribute('data-circ-wasm');
    expect(watcher.observed.map(nameOf)).toEqual(cards.map(nameOf));
    // Started before the card is actually on screen, so a steady scroll meets
    // a running circuit rather than a spinner.
    expect((watcher.options as { rootMargin: string }).rootMargin).toContain('200px');

    // A card reported on screen is let go at once: this is a one-shot, not a
    // visibility toggle, because tearing a circuit down on scroll would throw
    // away whatever the reader had clocked into it.
    //
    // The target is a bare element rather than a card. `mount` returns before
    // it imports anything when the container holds no launch button, and
    // letting it get as far as the real renderer hangs this harness — there is
    // no network here, and the import never settles.
    const stub = doc.createElement('div');
    stub.setAttribute('data-circ-wasm', 'stub.wasm');
    watcher.intersect(stub);
    expect(watcher.unobserved.map(nameOf)).toEqual(['stub.wasm']);

    // The landing page renders the same component and opts its hero in too, so
    // the flag is a per-canvas decision rather than a page-shaped one. What
    // the observer must never do is watch a canvas that did NOT ask.
    const landing = readFileSync(resolve(DIST, 'index.html'), 'utf8');
    expect(landing).toContain('class="lc"');
    expect(landing).toContain('data-circ-autorun');
    const optedOut = Array.from(doc.querySelectorAll('.lc:not([data-circ-autorun])'));
    expect(watcher.observed).toHaveLength(cards.length);
    for (const el of optedOut) expect(watcher.observed).not.toContain(el);
  });

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
      ['.pg', '.pg-body'],
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
        const hiddenTerminal = selector === '.pg' && doc.querySelector('.pg-term')?.hasAttribute('hidden');
        if (hiddenTerminal) {
          // Schematic intentionally leaves row 3 at zero, with the status
          // footer explicitly anchored after it rather than auto-placed in it.
          expect((el as unknown as HTMLElement).style.getPropertyValue('--pg-term-h')).toBe('0px');
          expect(declarationsOf("[data-layout='app'] .pg-statusline {")).toContain('grid-row: 4');
        }
        expect(trackCount(rows[1])).toBe(kids.length + (hiddenTerminal ? 1 : 0));
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
});
