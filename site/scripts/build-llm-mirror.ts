#!/usr/bin/env bun
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { execSync } from 'node:child_process';
import { docs, DOCS_DIR, PUBLIC_DIR, SITE_URL, type Doc } from './lib/site-config.ts';
import { tour } from '../src/content/tour.ts';
import { examples } from '../src/content/examples.ts';

const REPO_ROOT = resolve(PUBLIC_DIR, '..', '..');
const GITHUB_REPO = process.env.GITHUB_REPO ?? 'https://github.com/jeffersonmourak/circ-compiler';
const GITHUB_PUBLIC = (process.env.GITHUB_PUBLIC ?? 'true').toLowerCase() !== 'false';

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

// Source of truth for the hero snippet on the landing page lives in
// `src/pages/index.astro`. Mirror it here so the markdown twin shows the same
// circuit. If you change one, change the other — there's no shared source
// today (the JSX page interleaves prose with `<LiveCanvas>`, which doesn't
// translate to markdown).
const HERO_SOURCE = `// half_adder.circ
import xor "<builtin>/xor.circ"
input a, b
xor s(a=a, b=b)
and c(a=a, b=b)
output sum(in=s.out)
output carry(in=c.out)
`;

const HERO_PREVIEW = `╭───╮     ╭───╮         ╭───────╮
│ a ├○─●─▶┤   │ ╭──────▶┤ carry │
╰───╯  │  │AND├○╯       ╰───────╯
      ╭┼─▶┤   │
      ││  ╰───╯
      ││
╭───╮ ││  ╭───────╮     ╭─────╮
│ b ├○●╰─▶┤       │ ╭──▶┤ sum │
╰───╯ │   │[xor:s]├○╯   ╰─────╯
      ╰──▶┤       │
          ╰───────╯`;

function emitLandingTwin(): void {
  const lines = [
    header(
      'circ',
      'A small language for building and simulating logic circuits, made for people learning how computers work.',
    ).trimEnd(),
    '',
    '## Hero example: half-adder',
    '',
    'Two inputs, an XOR macro for the sum, an AND for the carry.',
    '',
    '### Source',
    '',
    '```circ',
    HERO_SOURCE.trimEnd(),
    '```',
    '',
    '### `circ-compile --preview`',
    '',
    '```',
    HERO_PREVIEW,
    '```',
    '',
    `Download \`circ-compile\` for Linux, macOS, or Windows: ${SITE_URL}/download.md`,
    '',
    '## What it is',
    '',
    '`circ` is a declarative language. Programs are flat lists of declarations: name an input pin, instantiate a gate, wire its ports to signals from other components. The primitives are `and`, `not`, `led`, and `wire`; macros for `or`, `nand`, `nor`, `xor`, and `xnor` expand to those primitives at compile time. Larger circuits live in their own `.circ` file and get pulled in with `import`.',
    '',
    "## What it isn't",
    '',
    '`circ` is a v0. There are no multi-bit buses, no clocked registers, no analog signals, no tri-state lines. A `wire` is a single-bit pass-through, not a let-binding for a vector. The language deliberately stops at the same boundary as the early Nand2Tetris hardware chapters.',
    '',
    '## Where it runs',
    '',
    '`circ-compile` produces a self-contained WebAssembly module: drive its input pins from JavaScript, read its outputs back, run it from Node or a browser. There is also a `--preview` flag that prints an ASCII schematic to your terminal — handy for sanity-checking the wiring before you simulate.',
    '',
    "If you've enjoyed Nand2Tetris or building NANDs from scratch in Petzold's *Code*, this is a language for doing more of that.",
    '',
  ];

  writeTwin('index.md', lines.join('\n'), 'src/pages/index.astro (hand-mirrored)');
}

type Platform = {
  os: string;
  arch: string;
  label: string;
  ext: 'tar.gz' | 'zip';
  minOs: string;
};

// Mirror of `src/pages/download.astro`. Same source of truth caveat as the
// landing page applies.
const PLATFORMS: Platform[] = [
  { os: 'Linux', arch: 'x86_64', label: 'linux-x86_64', ext: 'tar.gz', minOs: 'Kernel 3.2+' },
  { os: 'macOS', arch: 'aarch64 (Apple Silicon)', label: 'macos-aarch64', ext: 'tar.gz', minOs: '11 (Big Sur)' },
  { os: 'Windows', arch: 'x86_64', label: 'windows-x86_64', ext: 'zip', minOs: '10' },
];

function readVersion(): string {
  return readFileSync(resolve(REPO_ROOT, 'VERSION'), 'utf8').trim();
}

function emitDownloadTwin(): void {
  const version = readVersion();
  const repoName = GITHUB_REPO.split('/').pop() ?? 'circ-compiler';

  const tableHeader = '| OS | Architecture | File | Min OS |';
  const tableSep = '| --- | --- | --- | --- |';
  const tableRows = PLATFORMS.map((p) => {
    const file = `circ-compile-${version}-${p.label}.${p.ext}`;
    const downloadUrl = `${SITE_URL}/downloads/${file}`;
    return `| ${p.os} | ${p.arch} | [\`${file}\`](${downloadUrl}) | ${p.minOs} |`;
  });

  const lines = [
    header(
      'Download',
      'Pre-built `circ-compile` binaries for Linux, macOS, and Windows. Alpha software — expect breaking changes between builds.',
    ).trimEnd(),
    '',
    `Latest build: \`${version}\`.`,
    '',
    '## Alpha warning',
    '',
    "`circ-compile` is under active development. Expect rough edges, cryptic error messages, and breaking changes between builds. Don't use it for anything you care about preserving. Reports of what doesn't work are welcome — but for now, assume nothing here is stable.",
    '',
    '## Pre-built binaries',
    '',
    `Prefer to build from source? See [getting started](${SITE_URL}/reference/getting-started.md).`,
    '',
    tableHeader,
    tableSep,
    ...tableRows,
    '',
  ];

  if (GITHUB_PUBLIC) {
    lines.push(
      '## Build from source',
      '',
      'For Intel Macs, ARM Linux, ARM Windows, or any platform not listed above, build directly with [Zig 0.15.x](https://ziglang.org/):',
      '',
      '```sh',
      `git clone ${GITHUB_REPO}`,
      `cd ${repoName}`,
      'zig build circ-compile -Doptimize=ReleaseFast',
      './zig-out/bin/circ-compile --help',
      '```',
      '',
      `The full walkthrough — including writing your first \`.circ\` file and driving the compiled WASM from Node — lives in [getting started](${SITE_URL}/reference/getting-started.md).`,
      '',
    );
  }

  writeTwin('download.md', lines.join('\n'), 'src/pages/download.astro (hand-mirrored)');
}

function gitSha(): string {
  try {
    return execSync('git rev-parse HEAD', { cwd: REPO_ROOT, encoding: 'utf8' }).trim();
  } catch {
    return 'unknown';
  }
}

function emitLlmsTxt(): void {
  const lines = [
    '# circ',
    '',
    '> A small declarative language for digital logic circuits. Programs are flat lists of declarations: name an input pin, instantiate a gate, wire its ports to signals from other components. The compiler (`circ-compile`) produces a self-contained WebAssembly module simulating the circuit, plus optional ASCII schematics and truth tables.',
    '',
    'Important notes:',
    '',
    '- `circ` is a v0 — single-bit signals only, no clocked registers, no multi-bit buses.',
    '- Primitives are `and`, `not`, `led`, and `wire`; macros for `or`, `nand`, `nor`, `xor`, and `xnor` expand to those primitives at compile time.',
    '- Sub-circuits live in their own `.circ` files and are pulled in with `import`.',
    '',
    '## Docs',
    '',
    `- [Landing page](${SITE_URL}/index.md): What \`circ\` is, what it isn't, where it runs.`,
    `- [Tour](${SITE_URL}/tour.md): Seven progressive examples from a single NOT gate to a full-adder built from two half-adders.`,
    `- [Playground](${SITE_URL}/playground): Compile, diagnose, preview, tabulate, and simulate \`.circ\` in the browser — interactive, no \`.md\` twin.`,
    `- [Language reference](${SITE_URL}/reference.md): Every keyword, every diagnostic code, the rules the validator enforces.`,
    ...docs
      .filter((d) => d.dst !== 'reference.md')
      .map((d) => `- [${d.title}](${SITE_URL}/${d.dst}): ${d.description}`),
    `- [Download](${SITE_URL}/download.md): Pre-built \`circ-compile\` binaries for Linux, macOS, and Windows.`,
    '',
    '## Examples',
    '',
    `- [Examples gallery](${SITE_URL}/examples.md): Curated \`.circ\` programs with their \`--preview\` output.`,
    '',
    '## Optional',
    '',
    `- [Architecture](${GITHUB_REPO}/blob/main/DOCS/architecture.md): Compiler pipeline and layering, useful when contributing.`,
    `- [Design decisions](${GITHUB_REPO}/blob/main/DOCS/decisions/index.md): Rationale for the major language and runtime choices.`,
    `- [Source repository](${GITHUB_REPO}): Issues, pull requests, and the canonical \`DOCS/\` directory.`,
    '',
  ];

  writeTwin('llms.txt', lines.join('\n'), 'llmstxt.org index (generated)');
}

function stripDiscoveryBanner(body: string): string {
  // The per-page discovery banner is helpful when each twin is fetched
  // individually, but in a bundled `llms-full.txt` it repeats and wastes
  // tokens. Drop it (the leading `> **Documentation index** ...` block + the
  // blank lines that follow).
  return body.replace(/^> \*\*Documentation index\*\*[\s\S]*?\n\n\n/, '');
}

function emitLlmsFullTxt(): void {
  const sections: Array<{ path: string; label: string }> = [
    { path: 'index.md', label: 'Landing page' },
    { path: 'tour.md', label: 'Tour' },
    { path: 'reference.md', label: 'Language reference' },
    { path: 'reference/getting-started.md', label: 'Getting started' },
    { path: 'reference/circuit-format.md', label: 'Circuit file format' },
    { path: 'reference/wasm-api.md', label: 'WASM runtime API' },
    { path: 'reference/preview.md', label: 'ASCII preview' },
    { path: 'examples.md', label: 'Examples gallery' },
    { path: 'download.md', label: 'Download' },
  ];

  const out: string[] = [
    '# circ — full documentation bundle',
    '',
    `> Concatenation of every public \`.md\` twin on ${SITE_URL}.`,
    `> Built from commit \`${gitSha()}\` by \`scripts/build-llm-mirror.ts\`.`,
    `> Canonical source: ${GITHUB_REPO}.`,
    '',
  ];

  for (const s of sections) {
    const body = readFileSync(resolve(PUBLIC_DIR, s.path), 'utf8');
    out.push('---');
    out.push('');
    out.push(`<!-- source: ${SITE_URL}/${s.path} (${s.label}) -->`);
    out.push('');
    out.push(stripDiscoveryBanner(body).trimEnd());
    out.push('');
  }

  writeTwin('llms-full.txt', out.join('\n'), 'full bundle (generated)');
}

for (const d of docs) emitDocTwin(d);
emitTourTwin();
emitExamplesTwin();
emitLandingTwin();
emitDownloadTwin();
emitLlmsTxt();
emitLlmsFullTxt();
