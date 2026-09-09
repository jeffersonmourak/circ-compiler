#!/usr/bin/env bun
//
// One-shot regenerator. Walks every example, every tour step, and the
// landing-page hero; for each, writes its `.circ` source into a temp dir,
// runs `circ-compile` twice (once for `-o foo.wasm`, once for
// `--preview --color=never`), and prints a JSON map of results.
//
// Outputs:
//   site/public/wasm/*.wasm           — interactive simulator artifacts
//   site/scripts/.compiled.json       — { slug: { wasm, preview } }
//
// The .compiled.json is consumed by neither the build nor the runtime; it's
// a reference dump you read so you can paste real previews into examples.ts,
// tour.ts, and index.astro. (We don't auto-rewrite the TS files because doing
// so safely requires AST manipulation that isn't worth the complexity for a
// one-shot script.)
//
// Multi-file sources (tour step 6, full-adder importing half-adder) are
// recognised by `// <name>.circ` line markers. The LAST file in a multi-file
// source is treated as the root and passed to the compiler; sibling files
// land alongside it for `import` resolution.

import {
  mkdirSync,
  writeFileSync,
  rmSync,
  existsSync,
} from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';
import { splitFiles, rootOf } from '../src/utils/split-files.ts';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..');
const tmpRoot = '/tmp/circ-content-build';
const wasmOut = resolve(here, '..', 'public', 'wasm');
const compiler = resolve(repoRoot, 'zig-out', 'bin', 'circ-compile');
const outJson = resolve(here, '.compiled.json');

if (!existsSync(compiler)) {
  console.error(`circ-compile not found at ${compiler}`);
  console.error(`run \`zig build circ-compile\` from the repo root first`);
  process.exit(1);
}

rmSync(tmpRoot, { recursive: true, force: true });
mkdirSync(tmpRoot, { recursive: true });
mkdirSync(wasmOut, { recursive: true });

type Compiled = { wasm: string; preview: string };
const results: Record<string, Compiled | { error: string }> = {};

function compile(slug: string, source: string): Compiled | { error: string } {
  const dir = `${tmpRoot}/${slug}`;
  mkdirSync(dir, { recursive: true });
  const files = splitFiles(source);
  for (const f of files) writeFileSync(`${dir}/${f.name}`, f.body);
  const rootName = rootOf(files).name;
  const root = `${dir}/${rootName}`;

  const wasmName = `${slug}.wasm`;
  const wasmPath = `${wasmOut}/${wasmName}`;

  const cR = spawnSync(compiler, [root, '-o', wasmPath], {
    encoding: 'utf-8',
  });
  if (cR.status !== 0) {
    return { error: `compile failed: ${cR.stderr || cR.stdout}`.trim() };
  }

  const pR = spawnSync(compiler, [root, '--preview', '--color=never'], {
    encoding: 'utf-8',
  });
  if (pR.status !== 0) {
    return { error: `preview failed: ${pR.stderr || pR.stdout}`.trim() };
  }

  return { wasm: wasmName, preview: pR.stdout.replace(/\n+$/, '') };
}

console.log('compiling examples …');
for (const ex of examples) {
  const r = compile(ex.slug, ex.source);
  results[`example:${ex.slug}`] = r;
  console.log(`  ${'error' in r ? '✗' : '✓'} example:${ex.slug}`);
  if ('error' in r) console.log(`      ${r.error.split('\n')[0]}`);
}

console.log('compiling tour steps …');
tour.forEach((step, i) => {
  const slug = `tour-${i + 1}`;
  const r = compile(slug, step.source);
  results[`tour:${i + 1}`] = r;
  console.log(`  ${'error' in r ? '✗' : '✓'} tour:${i + 1} (${step.title})`);
  if ('error' in r) console.log(`      ${r.error.split('\n')[0]}`);
});

console.log('compiling landing hero …');
const heroSource = `import xor "<builtin>/xor.circ"
input a, b
xor s(a=a, b=b)
and c(a=a, b=b)
output sum(in=s.out)
output carry(in=c.out)
`;
const heroR = compile('hero-half-adder', heroSource);
results['hero'] = heroR;
console.log(`  ${'error' in heroR ? '✗' : '✓'} hero`);
if ('error' in heroR) console.log(`      ${heroR.error.split('\n')[0]}`);

writeFileSync(outJson, JSON.stringify(results, null, 2));
console.log(`\nwrote ${outJson}`);
