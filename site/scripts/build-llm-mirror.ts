#!/usr/bin/env bun
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { docs, DOCS_DIR, PUBLIC_DIR, SITE_URL, type Doc } from './lib/site-config.ts';

// Cross-doc links are rewritten to absolute `.md` URLs so an LLM that fetches
// a single twin can walk the rest of the docs without guessing URLs.
const mdLinkMap = new Map<string, string>();
for (const d of docs) {
  const slug = d.dst.replace(/\.md$/, '');
  mdLinkMap.set(d.src, `${SITE_URL}/${slug}.md`);
}

function banner(): string {
  return [
    '> **Documentation index**',
    '>',
    `> Fetch the complete documentation index at: ${SITE_URL}/llms.txt`,
    '> Use this file to discover all available pages before exploring further.',
    '',
    '',
  ].join('\n');
}

function rewriteLinks(body: string): string {
  return body.replace(/\]\(([^)\s]+\.md)(#[^)]*)?\)/g, (m, file, anchor = '') => {
    const target = mdLinkMap.get(file);
    return target ? `](${target}${anchor})` : m;
  });
}

function emitTwin(d: Doc) {
  const srcPath = resolve(DOCS_DIR, d.src);
  const dstPath = resolve(PUBLIC_DIR, d.dst);

  let body = readFileSync(srcPath, 'utf8');

  // Strip the source H1 — we re-emit a canonical H1 from the title field so
  // every twin has predictable framing, regardless of whatever heading the
  // upstream `DOCS/*.md` happens to use.
  body = body.replace(/^# .+\n+/, '');
  body = rewriteLinks(body);

  const header = [
    banner(),
    `# ${d.title}`,
    '',
    `> ${d.description}`,
    '',
    '',
  ].join('\n');

  mkdirSync(dirname(dstPath), { recursive: true });
  writeFileSync(dstPath, header + body);
  console.log(`twin   ${srcPath} -> ${dstPath}`);
}

for (const d of docs) emitTwin(d);
