#!/usr/bin/env bun
//
// `bun run playground [dir] [--no-open] [astro dev flags]`: the playground as
// a compiler development tool.
//
//   * Its "Yours" projects are the directories under `dir` that hold `.circ`
//     files, and every edit is written back to those files.
//   * Its compiler is `zig-out/lib/libcirc.wasm`, built from the working tree
//     at startup and again whenever the compiler's sources change.
//
// `dir` is resolved against the directory the command was run from and
// defaults to `tests/fixtures/projects`. The plugin that does the work is
// `scripts/dev-playground/plugin.mjs`; this file only sets it up and starts
// `astro dev`. Never part of a build.

import { spawnSync, spawn, type ChildProcess } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const siteRoot = resolve(here, '..');
const repoRoot = resolve(siteRoot, '..');

const args = process.argv.slice(2);
const dirArg = args.length > 0 && !args[0].startsWith('-') ? args.shift()! : null;
// The page opens in the browser unless `--no-open` says otherwise.
const noOpen = args.indexOf('--no-open');
if (noOpen >= 0) args.splice(noOpen, 1);
// `tools/playground` runs this from site/, so it passes the caller's cwd on.
const callerCwd = process.env.CIRC_PLAYGROUND_CWD ?? process.env.INIT_CWD ?? process.cwd();
const workspace = dirArg ? resolve(callerCwd, dirArg) : resolve(repoRoot, 'tests', 'fixtures', 'projects');

if (existsSync(workspace) && !statSync(workspace).isDirectory()) {
  console.error(`${workspace} is a file; pass the directory that holds it.`);
  process.exit(2);
}

// The same generated pages `bun run dev` prepares; the playground reads the
// agent-reference manifest at render time.
for (const script of ['sync', 'llm-mirror', 'agent-reference']) {
  const step = spawnSync('bun', ['run', script], { cwd: siteRoot, stdio: 'inherit' });
  if (step.status !== 0) process.exit(step.status ?? 1);
}

console.log(`\nplayground workspace: ${workspace}\ncompiler sources:     ${repoRoot}\n`);

// Astro's ambient types widen `process.env`, hence the cast.
const env = { ...process.env, CIRC_PLAYGROUND_ROOT: workspace, CIRC_REPO_ROOT: repoRoot } as unknown as NodeJS.ProcessEnv;
const astro: ChildProcess = spawn('bunx', ['astro', 'dev', ...(noOpen >= 0 ? [] : ['--open', '/playground']), ...args], {
  cwd: siteRoot,
  stdio: 'inherit',
  env,
});
for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => astro.kill(signal));
}
astro.on('close', (code) => process.exit(code ?? 0));
