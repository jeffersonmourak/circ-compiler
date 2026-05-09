#!/usr/bin/env bun
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const SRC = resolve(here, '..', '..', 'DOCS', 'language.md');
const DST = resolve(here, '..', 'src', 'pages', 'reference.md');

const raw = readFileSync(SRC, 'utf8');

// Drop the original H1 — DocsLayout renders the title from frontmatter, so
// keeping the H1 would duplicate it.
const stripped = raw.replace(/^# .+\n+/, '');

const frontmatter = [
  '---',
  'layout: ../layouts/DocsLayout.astro',
  'title: Language Reference',
  'description: The full reference for the circ digital-logic language.',
  '---',
  '',
  '',
].join('\n');

mkdirSync(dirname(DST), { recursive: true });
writeFileSync(DST, frontmatter + stripped);
console.log(`synced ${SRC} -> ${DST}`);
