import { defineConfig } from 'astro/config';
import { circLang } from './src/utils/circ-lang.mjs';
import { shikiThemes } from './src/utils/shiki-themes.mjs';

const base = process.env.BASE_PATH ?? '/';
const site = process.env.SITE_URL;

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
    server: {
      allowedHosts: ['.ngrok-free.app', '.ngrok.app', '.ngrok.io'],
    },
  },
});
