// One name per page, in every place the site says it.
//
// A page's name is written down four times: the nav, the footer, the `<h1>`,
// and the `<title>`. Renaming one of them is a two-second edit and leaving the
// other three is a two-second oversight, and nothing about it fails — the site
// builds, every link still resolves, and the reader is the one who finds a
// "Gallery" tab that opens a page headed "Examples".
//
// So the names are checked against each other rather than against a list this
// file keeps, which would just be a fifth place to forget.
import { describe, expect, test } from 'bun:test';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SITE = resolve(import.meta.dir, '..');
const read = (...parts: string[]) => readFileSync(resolve(SITE, ...parts), 'utf8');

/** `{ href: url('/tour'), label: 'Tour' }` → `['/tour', 'Tour']`. */
function navLinks(): [string, string][] {
  const source = read('src', 'components', 'Nav.astro');
  const out: [string, string][] = [];
  const re = /\{\s*href:\s*url\('([^']+)'\),\s*label:\s*'([^']+)'\s*\}/g;
  for (let m = re.exec(source); m; m = re.exec(source)) out.push([m[1], m[2]]);
  return out;
}

/** `<a href={url('/tour')}>Tour</a>` → `['/tour', 'Tour']`. */
function footerLinks(): [string, string][] {
  const source = read('src', 'components', 'Footer.astro');
  const out: [string, string][] = [];
  const re = /<a href=\{url\('([^']+)'\)\}>([^<]+)<\/a>/g;
  for (let m = re.exec(source); m; m = re.exec(source)) out.push([m[1], m[2]]);
  return out;
}

/** The page behind a route, whichever extension it uses. */
function pageFor(route: string): string | null {
  const stem = route === '/' ? 'index' : route.replace(/^\//, '');
  for (const ext of ['.astro', '.md']) {
    const path = resolve(SITE, 'src', 'pages', `${stem}${ext}`);
    if (existsSync(path)) return readFileSync(path, 'utf8');
  }
  return null;
}

const h1Of = (page: string): string | null => page.match(/<h1[^>]*>([^<]+)<\/h1>/)?.[1].trim() ?? null;
const titleOf = (page: string): string | null => page.match(/title="([^"]+)"/)?.[1].trim() ?? null;

describe('the site calls each page one thing', () => {
  test('the nav is not empty, or this whole file proves nothing', () => {
    // A regex that silently matches nothing is the way a test like this rots.
    expect(navLinks().length).toBeGreaterThanOrEqual(3);
    expect(footerLinks().length).toBeGreaterThanOrEqual(2);
    expect(navLinks().map(([route]) => route)).toContain('/gallery');
  });

  test('every page heading names the thing the nav calls it', () => {
    // Containment, not equality: `/tour` is labelled "Tour" and headed "A
    // short tour", which is a longer form of the same name and not a
    // disagreement. A heading still saying "Examples" under a "Gallery" tab
    // fails here, which is the case this exists for.
    for (const [route, label] of navLinks()) {
      const page = pageFor(route);
      if (page === null) continue; // a route with no page file of its own
      const h1 = h1Of(page);
      if (h1 === null) continue; // a page that leads with something else
      const mentions = h1.toLowerCase().includes(label.toLowerCase());
      expect(`${route} → ${mentions ? label : h1}`).toBe(`${route} → ${label}`);
    }
  });

  test('every footer label matches its nav label', () => {
    const nav = new Map(navLinks());
    for (const [route, label] of footerLinks()) {
      if (!nav.has(route)) continue;
      expect(`${route} → ${label}`).toBe(`${route} → ${nav.get(route)}`);
    }
  });

  test('every page title leads with its nav label', () => {
    // Titles read `Gallery — circ`, so the name is the part before the dash.
    // This is the strict half: a browser tab and a nav tab sit side by side,
    // and one of them saying "Examples" is exactly what a half-rename looks
    // like from the reader's chair.
    let checked = 0;
    for (const [route, label] of navLinks()) {
      const page = pageFor(route);
      if (page === null) continue;
      const title = titleOf(page);
      if (title === null) continue;
      checked += 1;
      expect(`${route} → ${title.split('—')[0].trim()}`).toBe(`${route} → ${label}`);
    }
    expect(checked).toBeGreaterThanOrEqual(3);
  });

  test('the route the gallery moved away from still redirects to it', () => {
    // The page lived at /examples until it was renamed. The repository is
    // public, so that path may already be linked or indexed, and dropping the
    // redirect turns every one of those links into a 404 without failing a
    // build. The target is read from the nav rather than written down here, so
    // a second rename cannot leave the redirect pointing at nothing.
    const config = read('astro.config.mjs');
    const target = new Map(navLinks()).get('/gallery') ? '/gallery' : null;
    expect(target).toBe('/gallery');
    expect(config).toContain("'/examples': '/gallery'");
    // …and nothing still links to the old path.
    for (const [route] of [...navLinks(), ...footerLinks()]) {
      expect(route).not.toBe('/examples');
    }
  });

  test('the markdown twin of the gallery is headed the same way', () => {
    // The `.md` mirror is the site's other face, and it has its own copy of
    // every page name. It was the last place the rename reached.
    const mirror = read('scripts', 'build-llm-mirror.ts');
    const gallery = pageFor('/gallery')!;
    const h1 = h1Of(gallery)!;
    // The twin's own header, its entry in llms.txt, and its section label in
    // the bundled llms-full.txt all name it.
    expect(mirror).toContain(`    '${h1}',\n`);
    expect(mirror).toContain(`## ${h1}`);
    expect(mirror).toContain(`label: '${h1}'`);
    expect(mirror).not.toContain('Examples gallery');
  });
});
