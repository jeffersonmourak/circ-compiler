#!/usr/bin/env bun
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { docs, BASE_PATH, DOCS_DIR, PAGES_DIR, type Doc } from './lib/site-config.ts';

const base = BASE_PATH;

// Filename → site URL, used to rewrite intra-doc markdown links so they
// keep working after the move into pages/.
const linkMap = new Map<string, string>();
for (const d of docs) {
  const slug = d.dst.replace(/\.md$/, '');
  linkMap.set(d.src, `${base}${slug}`);
}

function syncDoc(d: Doc) {
  const srcPath = resolve(DOCS_DIR, d.src);
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
