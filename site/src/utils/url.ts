// Path helper that respects Astro's configured `base` (e.g. `/circ-compiler/`
// when deployed to a GitHub Pages project subpath). Use this for every internal
// link so the site works both at the root and under a subpath without changes.
const base = import.meta.env.BASE_URL.replace(/\/$/, '');

export const url = (path: string): string => {
  const clean = path.startsWith('/') ? path : `/${path}`;
  return `${base}${clean}`;
};

export const GITHUB_REPO = 'https://github.com/jeffersonmourak/circ-compiler';
export const RENDERER_REPO = 'https://github.com/jeffersonmourak/circ-renderer';

// Flip to `true` when the circ-compiler repo goes public. While `false`,
// nav + footer render a muted "GitHub (soon)" tag instead of a live link,
// and per-example "Source: …" lines are suppressed (the file paths they
// point at aren't reachable yet).
export const GITHUB_PUBLIC = true;
