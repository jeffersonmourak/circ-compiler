import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export type Doc = {
  /** Filename inside `../../DOCS/`, relative path. */
  src: string;
  /** Output path under `src/pages/` (drives the HTML route). */
  dst: string;
  /** Human title; rendered as the page H1 in both HTML and the `.md` twin. */
  title: string;
  /** One-sentence description; rendered as the lede + the twin's blockquote. */
  description: string;
};

export const docs: Doc[] = [
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

/**
 * Canonical production URL of the site, without trailing slash.
 *
 * Used by `build-llm-mirror.ts` to emit absolute links inside the `.md` twins
 * so a consumer that fetches one twin can follow the rest of the docs.
 */
export const SITE_URL = (process.env.SITE_URL ?? 'https://circ-lang.org').replace(/\/+$/, '');

/**
 * Astro `base` mirror — same logic as `astro.config.mjs`. Normalised to end in
 * `/` so callers can string-concatenate without thinking about it.
 */
export const BASE_PATH = (process.env.BASE_PATH ?? '/').replace(/\/?$/, '/');

const here = dirname(fileURLToPath(import.meta.url));

/** Absolute path to the canonical `DOCS/` directory inside the repo. */
export const DOCS_DIR = resolve(here, '..', '..', '..', 'DOCS');

/** Absolute path to `site/src/pages/`. */
export const PAGES_DIR = resolve(here, '..', '..', 'src', 'pages');

/** Absolute path to `site/public/` (deploys verbatim under the site root). */
export const PUBLIC_DIR = resolve(here, '..', '..', 'public');
