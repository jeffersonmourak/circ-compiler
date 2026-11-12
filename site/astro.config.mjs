import { defineConfig } from 'astro/config';
import { circLang } from './src/utils/circ-lang.mjs';
import { shikiThemes } from './src/utils/shiki-themes.mjs';
import { devPlayground } from './scripts/dev-playground/plugin.mjs';

const base = process.env.BASE_PATH ?? '/';
const site = process.env.SITE_URL;
// Set only by `bun run playground` (scripts/dev-playground.ts): the playground
// then keeps its projects in this directory and runs a freshly built compiler.
const playgroundRoot = process.env.CIRC_PLAYGROUND_ROOT;
const repoRoot = process.env.CIRC_REPO_ROOT;

export default defineConfig({
  base,
  site,
  output: 'static',
  trailingSlash: 'ignore',
  // The gallery lived at /examples until it was renamed. The repository is
  // public, so that path may already be linked or indexed; a static build
  // emits a meta-refresh page here rather than a 404. Keep it.
  redirects: {
    '/examples': '/gallery',
    // The tour page is gone; its seven circuits live on in the playground's
    // workspace, which is where a reader arriving from an old link wants to
    // end up.
    '/tour': '/playground',
  },
  markdown: {
    shikiConfig: {
      themes: shikiThemes,
      defaultColor: false,
      langs: [circLang],
      wrap: false,
    },
  },
  // Allow ngrok-style hostnames through the dev-server's Host-header check so
  // the tunnel can reach the running site. The leading dot matches any
  // subdomain (Vite accepts suffix patterns this way). No effect on the
  // production build — these are dev-only.
  vite: {
    plugins: playgroundRoot && repoRoot ? [devPlayground({ workspace: playgroundRoot, repoRoot })] : [],
    server: {
      allowedHosts: ['.ngrok-free.app', '.ngrok.app', '.ngrok.io'],
    },
  },
});
