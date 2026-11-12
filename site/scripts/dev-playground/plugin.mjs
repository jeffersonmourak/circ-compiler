// The Vite plugin behind `bun run playground` (see ../dev-playground.ts).
// `astro.config.mjs` adds it only when CIRC_PLAYGROUND_ROOT is set, so
// `astro dev` and every build are untouched. It does two jobs:
//
//   1. The workspace. `/__circ/fs/projects` lists the directories under the
//      workspace root that hold `.circ` files; `/__circ/fs/apply` writes the
//      playground's edits back. A change made outside the page (an editor, a
//      `git checkout`) reloads the page.
//      The console's `load` and `save` read and write memory images there
//      too (`/__circ/fs/image`), which the site's playground refuses.
//   2. The compiler. `/wasm/libcirc.wasm` is served from `zig-out/`, not from
//      the committed copy in `public/`. A change under the compiler's sources
//      runs `zig build libcirc-wasm` and reloads the page on success.

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, watch, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';

const SKIP_DIRS = new Set(['node_modules', 'zig-out', 'zig-cache', 'dist']);
const MAX_DEPTH = 6;
const SEGMENT = /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/;
const FILE_NAME = /^[\w_.-]+\.circ$/;
export const TRASH_DIR = '.circ-trash';

/** `dir` is `.` or `/`-separated safe segments; anything else is refused. */
export function resolveDir(root, dir) {
  if (typeof dir !== 'string') return null;
  if (dir === '.') return root;
  const segments = dir.split('/');
  if (!segments.every((segment) => SEGMENT.test(segment) && segment !== '..')) return null;
  const full = resolve(root, ...segments);
  return full === root || full.startsWith(root + sep) ? full : null;
}

/** Every directory under `root` that directly holds `.circ` files. */
export function scanProjects(root) {
  const projects = [];
  const visit = (abs, depth) => {
    let entries;
    try {
      entries = readdirSync(abs, { withFileTypes: true });
    } catch {
      return;
    }
    const files = [];
    let mtimeMs = 0;
    for (const entry of entries) {
      if (entry.isFile() && FILE_NAME.test(entry.name)) {
        const path = join(abs, entry.name);
        files.push({ name: entry.name, body: readFileSync(path, 'utf8') });
        mtimeMs = Math.max(mtimeMs, statSync(path).mtimeMs);
      }
    }
    if (files.length > 0) {
      const dir = relative(root, abs).split(sep).join('/') || '.';
      projects.push({ dir, files, mtimeMs: Math.round(mtimeMs) });
    }
    if (depth >= MAX_DEPTH) return;
    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name.startsWith('.') || SKIP_DIRS.has(entry.name)) continue;
      visit(join(abs, entry.name), depth + 1);
    }
  };
  visit(root, 0);
  projects.sort((a, b) => (a.dir < b.dir ? -1 : a.dir > b.dir ? 1 : 0));
  return projects;
}

/**
 * Applies the page's writes. A `remove` moves the file into the workspace
 * trash, stamped per call, so nothing the page does unlinks a file. Returns
 * the absolute paths it wrote, with their new content (null for a removal).
 */
export function applyOps(root, ops, stamp = new Date().toISOString().replace(/[:.]/g, '-')) {
  if (!Array.isArray(ops)) throw new Error('ops must be an array');
  const touched = new Map();
  for (const op of ops) {
    const dir = resolveDir(root, op?.dir);
    if (dir === null) throw new Error(`refused directory ${JSON.stringify(op?.dir)}`);
    if (typeof op.file !== 'string' || !FILE_NAME.test(op.file)) throw new Error(`refused file ${JSON.stringify(op?.file)}`);
    const path = join(dir, op.file);
    if (op.op === 'write') {
      if (typeof op.body !== 'string') throw new Error(`write to ${op.file} has no body`);
      mkdirSync(dir, { recursive: true });
      writeFileSync(path, op.body);
      touched.set(path, op.body);
    } else if (op.op === 'remove') {
      if (!existsSync(path)) continue;
      const target = join(root, TRASH_DIR, stamp, relative(root, path));
      mkdirSync(dirname(target), { recursive: true });
      renameSync(path, target);
      touched.set(path, null);
    } else {
      throw new Error(`unknown op ${JSON.stringify(op?.op)}`);
    }
  }
  return touched;
}

/** The read cap `--sim` applies to an image (`sim_loop.IMAGE_READ_CAP`). */
export const IMAGE_READ_CAP = 16 * 1024 * 1024;

/**
 * Where a `load` or `save` path lands: resolved against the project's
 * directory, as the CLI resolves against its cwd. `..` may climb, but never
 * out of the workspace, and never into a dotted directory or the trash.
 */
export function resolveImage(root, dir, path) {
  const base = resolveDir(root, dir);
  if (base === null || typeof path !== 'string' || path === '' || path.includes('\0')) return null;
  const full = resolve(base, path);
  if (!full.startsWith(root + sep)) return null;
  const segments = relative(root, full).split(sep);
  if (segments.some((segment) => segment.startsWith('.'))) return null;
  return full;
}

/** Errors are spelled as Zig's `@errorName` spells them, as `--sim` prints. */
export function readImage(root, dir, path) {
  const full = resolveImage(root, dir, path);
  if (full === null) return { ok: false, error: 'AccessDenied' };
  let stat;
  try {
    stat = statSync(full);
  } catch {
    return { ok: false, error: 'FileNotFound' };
  }
  if (stat.isDirectory()) return { ok: false, error: 'IsDir' };
  if (stat.size > IMAGE_READ_CAP) return { ok: false, error: 'FileTooBig' };
  return { ok: true, base64: readFileSync(full).toString('base64') };
}

/** An image the save replaces goes to the trash first, like a removed file. */
export function writeImage(root, dir, path, base64, stamp = new Date().toISOString().replace(/[:.]/g, '-')) {
  const full = resolveImage(root, dir, path);
  if (full === null || typeof base64 !== 'string') return { ok: false, error: 'AccessDenied' };
  try {
    if (existsSync(full)) {
      if (statSync(full).isDirectory()) return { ok: false, error: 'IsDir' };
      const target = join(root, TRASH_DIR, stamp, relative(root, full));
      mkdirSync(dirname(target), { recursive: true });
      renameSync(full, target);
    }
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, Buffer.from(base64, 'base64'));
    return { ok: true, path: full };
  } catch (err) {
    return { ok: false, error: err?.code === 'EACCES' ? 'AccessDenied' : 'Unexpected' };
  }
}

/**
 * These routes write files, so only this page may call them. A request from
 * another site carries that site's Origin; a write must also be JSON, which
 * no cross-site form or `no-cors` fetch can send.
 */
export function allowed(req) {
  const origin = req.headers.origin;
  if (origin) {
    let host;
    try {
      host = new URL(origin).host;
    } catch {
      return false;
    }
    if (host !== req.headers.host) return false;
  }
  if (req.method === 'POST' && !String(req.headers['content-type'] ?? '').startsWith('application/json')) return false;
  return true;
}

function readBody(req) {
  return new Promise((done, fail) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => done(Buffer.concat(chunks).toString('utf8')));
    req.on('error', fail);
  });
}

function debounce(fn, ms) {
  let timer = null;
  return () => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = null;
      fn();
    }, ms);
  };
}

/**
 * @param {{ workspace: string, repoRoot: string }} options absolute paths
 */
export function devPlayground({ workspace, repoRoot }) {
  const built = join(repoRoot, 'zig-out', 'lib', 'libcirc.wasm');
  const log = (message) => console.log(`\x1b[36m[playground]\x1b[0m ${message}`);

  return {
    name: 'circ-dev-playground',
    apply: 'serve',
    configureServer(server) {
      // ---- the workspace ----
      // What the page last read or wrote, by absolute path. A watch event
      // that matches it is the page's own write and reloads nothing.
      const known = new Map();
      const remember = () => {
        known.clear();
        const projects = scanProjects(workspace);
        for (const project of projects) {
          const dir = resolveDir(workspace, project.dir) ?? workspace;
          for (const file of project.files) known.set(join(dir, file.name), file.body);
        }
        return projects;
      };

      const reloadForDisk = debounce(() => {
        log('workspace changed on disk; reloading the page');
        server.ws.send({ type: 'custom', event: 'circ:disk-changed' });
      }, 150);

      mkdirSync(workspace, { recursive: true });
      const workspaceWatcher = watch(workspace, { recursive: true }, (_event, name) => {
        if (!name || !name.endsWith('.circ') || name.split(sep).includes(TRASH_DIR)) return;
        const path = join(workspace, name);
        let body = null;
        try {
          body = readFileSync(path, 'utf8');
        } catch {
          body = null;
        }
        const before = known.has(path) ? known.get(path) : null;
        if (before === body) return;
        known.set(path, body);
        reloadForDisk();
      });

      // ---- the compiler ----
      let building = false;
      let again = false;
      const build = (reason) => {
        if (building) {
          again = true;
          return;
        }
        building = true;
        const started = Date.now();
        log(`zig build libcirc-wasm (${reason})`);
        const zig = spawn('zig', ['build', 'libcirc-wasm'], { cwd: repoRoot });
        let output = '';
        zig.stdout.on('data', (chunk) => (output += chunk));
        zig.stderr.on('data', (chunk) => (output += chunk));
        zig.on('error', (err) => {
          building = false;
          log(`could not run zig: ${err.message}`);
        });
        zig.on('close', (code) => {
          building = false;
          if (code === 0) {
            log(`libcirc.wasm rebuilt in ${((Date.now() - started) / 1000).toFixed(1)}s; reloading the page`);
            server.ws.send({ type: 'full-reload' });
          } else {
            console.error(output);
            log('build failed; the page keeps the last good libcirc.wasm');
            server.ws.send({
              type: 'error',
              err: { message: 'zig build libcirc-wasm failed', stack: output, plugin: 'circ-dev-playground' },
            });
          }
          if (again) {
            again = false;
            build('sources changed during the build');
          }
        });
      };

      const rebuild = debounce(() => build('sources changed'), 300);
      const sourceWatchers = ['lib', 'templates', 'build', 'cmd']
        .map((name) => join(repoRoot, name))
        .filter((path) => existsSync(path))
        .map((path) =>
          watch(path, { recursive: true }, (_event, name) => {
            if (name && /\.(zig|circ|peg|zon)$/.test(name)) rebuild();
          }),
        );
      const buildFileWatcher = watch(repoRoot, (_event, name) => {
        if (name === 'build.zig' || name === 'build.zig.zon' || name === 'VERSION') rebuild();
      });
      build('startup');

      server.httpServer?.once('close', () => {
        workspaceWatcher.close();
        buildFileWatcher.close();
        for (const watcher of sourceWatchers) watcher.close();
      });

      // ---- routes ----
      server.middlewares.use(async (req, res, next) => {
        const [path, query = ''] = (req.url ?? '').split('?');
        if (path.startsWith('/__circ/fs/') && !allowed(req)) {
          res.statusCode = 403;
          res.end('refused: not this page');
          return;
        }
        try {
          if (path.endsWith('/wasm/libcirc.wasm') && existsSync(built)) {
            res.setHeader('content-type', 'application/wasm');
            res.setHeader('cache-control', 'no-store');
            res.end(readFileSync(built));
            return;
          }
          if (path === '/__circ/fs/projects' && req.method === 'GET') {
            res.setHeader('content-type', 'application/json');
            res.setHeader('cache-control', 'no-store');
            res.end(JSON.stringify({ root: workspace, projects: remember() }));
            return;
          }
          if (path === '/__circ/fs/apply' && req.method === 'POST') {
            const { ops } = JSON.parse(await readBody(req));
            // Record the content first: the watcher fires as soon as it lands.
            for (const op of Array.isArray(ops) ? ops : []) {
              const dir = resolveDir(workspace, op?.dir);
              if (dir !== null && typeof op.file === 'string') {
                known.set(join(dir, op.file), op.op === 'write' ? op.body : null);
              }
            }
            const touched = applyOps(workspace, ops);
            for (const [file, body] of touched) {
              log(`${body === null ? 'trashed' : 'wrote  '} ${relative(workspace, file)}`);
            }
            res.setHeader('content-type', 'application/json');
            res.end(JSON.stringify({ ok: true, files: touched.size }));
            return;
          }
          if (path === '/__circ/fs/image' && req.method === 'GET') {
            const params = new URLSearchParams(query);
            const result = readImage(workspace, params.get('dir'), params.get('path'));
            res.setHeader('content-type', 'application/json');
            res.setHeader('cache-control', 'no-store');
            res.end(JSON.stringify(result));
            return;
          }
          if (path === '/__circ/fs/image' && req.method === 'POST') {
            const { dir, path: imagePath, base64 } = JSON.parse(await readBody(req));
            const result = writeImage(workspace, dir, imagePath, base64);
            if (result.ok) log(`saved   ${relative(workspace, result.path)}`);
            res.setHeader('content-type', 'application/json');
            res.end(JSON.stringify({ ok: result.ok, error: result.error }));
            return;
          }
        } catch (err) {
          res.statusCode = 400;
          res.end(String(err?.message ?? err));
          return;
        }
        next();
      });
    },
  };
}
