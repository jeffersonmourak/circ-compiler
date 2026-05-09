#!/usr/bin/env bun
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const SRC_DIR = resolve(here, '..', '..', 'DOCS');
const PAGES_DIR = resolve(here, '..', 'src', 'pages');

// Mirror astro.config.mjs so cross-doc links land on the right path in
// both dev (BASE_PATH unset → '/') and CI builds (BASE_PATH=/circ-compiler).
const base = (process.env.BASE_PATH ?? '/').replace(/\/?$/, '/');

type Doc = { src: string; dst: string; title: string; description: string };

const docs: Doc[] = [
  {
    src: 'language.md',
    dst: 'reference.md',
    title: 'Language Reference',
    description: 'The full reference for the circ digital-logic language.',
  },
  {
    src: 'getting-started.md',
    dst: 'reference/getting-started.md',
    title: 'Getting Started',
    description: 'Install the compiler, write your first circuit, and drive it from Node.',
  },
  {
    src: 'circuit-format.md',
    dst: 'reference/circuit-format.md',
    title: 'Circuit File Format',
    description: 'The .circ language: declarations, ports, components, and built-ins.',
  },
  {
    src: 'wasm-api.md',
    dst: 'reference/wasm-api.md',
    title: 'WASM Runtime API',
    description: 'The export and import contract for every compiled .wasm artifact.',
  },
  {
    src: 'preview.md',
    dst: 'reference/preview.md',
    title: 'ASCII Preview',
    description: 'Render circuits as deterministic ASCII schematics with --preview.',
  },
];

// Filename → site URL, used to rewrite intra-doc markdown links so they
// keep working after the move into pages/.
const linkMap = new Map<string, string>();
for (const d of docs) {
  const slug = d.dst.replace(/\.md$/, '');
  linkMap.set(d.src, `${base}${slug}`);
}

function syncDoc(d: Doc) {
  const srcPath = resolve(SRC_DIR, d.src);
  const dstPath = resolve(PAGES_DIR, d.dst);
  let body = readFileSync(srcPath, 'utf8');

  // DocsLayout renders the title from frontmatter; strip the source H1.
  body = body.replace(/^# .+\n+/, '');

  body = body.replace(/\]\(([^)\s]+\.md)(#[^)]*)?\)/g, (m, file, anchor = '') => {
    const target = linkMap.get(file);
    return target ? `](${target}${anchor})` : m;
  });

  // pages/reference.md → ../layouts; pages/reference/foo.md → ../../layouts.
  const depth = (d.dst.match(/\//g) ?? []).length;
  const layoutPath = `${'../'.repeat(depth + 1)}layouts/DocsLayout.astro`;

  const frontmatter = [
    '---',
    `layout: ${layoutPath}`,
    `title: ${JSON.stringify(d.title)}`,
    `description: ${JSON.stringify(d.description)}`,
    '---',
    '',
    '',
  ].join('\n');

  mkdirSync(dirname(dstPath), { recursive: true });
  writeFileSync(dstPath, frontmatter + body);
  console.log(`synced ${srcPath} -> ${dstPath}`);
}

for (const d of docs) syncDoc(d);
