#!/usr/bin/env bun
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { docs, DOCS_DIR, PUBLIC_DIR, SITE_URL, type Doc } from './lib/site-config.ts';
import { tour } from '../src/content/tour.ts';
import { examples } from '../src/content/examples.ts';

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

function header(title: string, description: string): string {
  return [
    banner(),
    `# ${title}`,
    '',
    `> ${description}`,
    '',
    '',
  ].join('\n');
}

const fence = (lang: string, body: string): string =>
  `\`\`\`${lang}\n${body.replace(/\n$/, '')}\n\`\`\``;

function writeTwin(relPath: string, contents: string, label: string): void {
  const dstPath = resolve(PUBLIC_DIR, relPath);
  mkdirSync(dirname(dstPath), { recursive: true });
  writeFileSync(dstPath, contents);
  console.log(`twin   ${label} -> ${dstPath}`);
}

function emitDocTwin(d: Doc): void {
  const srcPath = resolve(DOCS_DIR, d.src);
  let body = readFileSync(srcPath, 'utf8');

  // Strip the source H1 — we re-emit a canonical H1 from the title field so
  // every twin has predictable framing, regardless of whatever heading the
  // upstream `DOCS/*.md` happens to use.
  body = body.replace(/^# .+\n+/, '');
  body = rewriteLinks(body);

  writeTwin(d.dst, header(d.title, d.description) + body, srcPath);
}

function renderTourStep(step: (typeof tour)[number], index: number): string {
  return `## Step ${index + 1}. ${step.title}

${step.prose}

### Source

${fence('circ', step.source)}

### \`circ-compile --preview\`

${fence('', step.preview)}`;
}

function emitTourTwin(): void {
  const intro = header(
    'A short tour',
    "A progressive walkthrough of `circ`. Each step adds one new idea on top of the previous one. By the end you'll have read enough to feel at home in the language reference.",
  ).trimEnd();
  const steps = tour.map(renderTourStep).join('\n\n');
  const footer = `Done. The [language reference](${SITE_URL}/reference.md) covers the full surface — every keyword, every diagnostic code, the rules the validator enforces. The [examples gallery](${SITE_URL}/examples.md) has more circuits to read through.`;

  writeTwin('tour.md', `${intro}\n\n\n${steps}\n\n${footer}\n`, 'src/content/tour.ts');
}

function renderExample(ex: (typeof examples)[number]): string {
  const repoNote = ex.repoPath ? `\n\nSource file in the repo: \`${ex.repoPath}\`.` : '';
  return `## ${ex.title}

${ex.lede}

### Source

${fence('circ', ex.source)}

### \`circ-compile --preview\`

${fence('', ex.preview)}${repoNote}`;
}

function emitExamplesTwin(): void {
  const intro = header(
    'Examples',
    'A gallery of `circ` circuits — primitives, multi-bit arithmetic, and stateful latches. Each entry shows the source and its `--preview` output.',
  ).trimEnd();
  const body = examples.map(renderExample).join('\n\n');

  writeTwin('examples.md', `${intro}\n\n\n${body}\n`, 'src/content/examples.ts');
}

for (const d of docs) emitDocTwin(d);
emitTourTwin();
emitExamplesTwin();
