#!/usr/bin/env bun
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { docs, DOCS_DIR, PUBLIC_DIR } from './lib/site-config.ts';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';
import { aliases, documentKeys, removed, sectionOverrides } from '../src/content/agent-reference.ts';
import { requestFor, splitFiles } from '../src/utils/split-files.ts';
import { callOp, instantiateLibcirc } from '../src/scripts/libcirc-abi.ts';
import type { CompilerIdentity, CorpusRecord, ExampleMemory, ExampleRecord, IndexedRecord, KnowledgeIndex, KnowledgeManifest, TextRecord } from '../src/scripts/knowledge-contract.ts';

const root = resolve(PUBLIC_DIR, '..', '..');
const out = resolve(PUBLIC_DIR, 'agent-reference');
const assets = resolve(out, 'assets');
const digest = (value: string | Uint8Array) => createHash('sha256').update(value).digest('hex');
const json = (value: unknown) => `${JSON.stringify(value)}\n`;
const wordTokens = (value: string) => (value.normalize('NFKC').toLowerCase().match(/[\p{L}\p{N}_]+/gu) ?? []).flatMap((token) => token.includes('_') ? [token, ...token.split('_')] : [token]);
const terms = (value: string) => Object.fromEntries(Object.entries(wordTokens(value).reduce<Record<string, number>>((out, token) => (out[token] = (out[token] ?? 0) + 1, out), {})).sort(([a], [b]) => a.localeCompare(b)));
const slug = (heading: string) => heading.replace(/^\d+(?:\.\d+)*\.?\s*/, '').replace(/[`*_]/g, '').replace(/\([^)]*\)/g, '').trim().toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '-').replace(/(^-|-$)/g, '');
const fileHash = (path: string) => digest(readFileSync(path));

function route(doc: string): { htmlPath: string; markdownPath: string } {
  const d = docs.find((item) => item.src === `${doc}.md`); if (!d) throw new Error(`Unknown reference document: ${doc}`);
  return { htmlPath: `/${d.dst.replace(/\.md$/, '')}`, markdownPath: `/${d.dst}` };
}
function citation(sourcePath: string, hash: string, startLine: number | null, endLine: number | null, htmlPath: string | null, markdownPath: string | null, heading: string | null) { return { sourcePath, sourceHash: hash, startLine, endLine, htmlPath, markdownPath, heading }; }
function textRecord(id: string, title: string, text: string, sourcePath: string, sourceHash: string, startLine: number | null, endLine: number | null, htmlPath: string | null, markdownPath: string | null, heading: string | null, parentId: string | null = null, relatedIds: string[] = [], format: TextRecord['format'] = 'markdown'): TextRecord {
  return { id, kind: 'reference', title, parentId, relatedIds, citation: citation(sourcePath, sourceHash, startLine, endLine, htmlPath, markdownPath, heading), format, text, textSha256: digest(text) };
}
function documentRecords(key: string): TextRecord[] {
  const sourcePath = `DOCS/${key}.md`; const path = resolve(DOCS_DIR, `${key}.md`); const body = readFileSync(path, 'utf8'); const lines = body.split('\n'); const hash = digest(body); const urls = route(key);
  const headings = lines.map((line, index) => ({ line, index, match: /^(#{2,6})\s+(.+?)\s*$/.exec(line) })).filter((item): item is { line: string; index: number; match: RegExpExecArray } => Boolean(item.match));
  const introEnd = headings[0]?.index ?? lines.length; const records: TextRecord[] = [];
  if (lines.slice(1, introEnd).join('\n').trim()) records.push(textRecord(`ref:${key}:overview`, key === 'language' ? 'Language overview' : docs.find((d) => d.src === `${key}.md`)!.title, lines.slice(1, introEnd).join('\n').trimEnd(), sourcePath, hash, 2, introEnd, urls.htmlPath, urls.markdownPath, null));
  for (let i = 0; i < headings.length; i++) {
    const current = headings[i]; const depth = current.match[1].length; let end = lines.length;
    for (let n = i + 1; n < headings.length; n++) if (headings[n].match[1].length <= depth) { end = headings[n].index; break; }
    const title = current.match[2]; const semanticId = sectionOverrides[`${key}:${title}`] ?? slug(title); const id = `ref:${key}:${semanticId}`;
    records.push(textRecord(id, title.replace(/^\d+(?:\.\d+)*\.?\s*/, ''), lines.slice(current.index, end).join('\n').trimEnd(), sourcePath, hash, current.index + 1, end, urls.htmlPath, urls.markdownPath, slug(title), null));
  }
  return records;
}
function diagnosticRecords(): TextRecord[] {
  const sourcePath = resolve(root, 'lib/validator/codes.zig'); const source = readFileSync(sourcePath, 'utf8'); const found = [...source.matchAll(/\.code\s*=\s*\.([EW]\d{3}),\s*\.default_message\s*=\s*"([^"]+)"/g)];
  if (!found.length) throw new Error('Could not read validator diagnostic registry.');
  const circuit = readFileSync(resolve(DOCS_DIR, 'circuit-format.md'), 'utf8'); const hash = digest(circuit); const urls = route('circuit-format');
  return found.map((match) => {
    const code = match[1]; const documented = new RegExp(`\\| ${code} \\| ([^\\n]+)`).exec(circuit)?.[1]?.trim() ?? match[2];
    const related = code === 'E014' ? ['ref:language:validation-rules', 'ref:language:multi-bit-wires'] : code === 'E017' ? ['ref:language:memories-declaration-shape', 'ref:language:memories-rom-ram'] : [];
    const text = `# ${code}: ${match[2]}\n\n${documented}`;
    return { ...textRecord(`diagnostic:${code}`, `${code}: ${match[2]}`, text, 'DOCS/circuit-format.md', hash, 149, 175, urls.htmlPath, urls.markdownPath, 'diagnostic-codes', null, related), kind: 'diagnostic' as const };
  });
}
function memoryFor(source: string, files: { name: string }[], values: Record<string, string> | undefined): ExampleMemory[] {
  if (!values) return []; const entry = files.at(-1)?.name ?? 'main.circ';
  return Object.entries(values).map(([name, hex]) => {
    const declaration = new RegExp(`\\b(rom|ram)\\s+${name}\\[(\\d+),\\s*(\\d+)\\]`).exec(source);
    if (!declaration) throw new Error(`Memory ${name} does not have a root declaration.`);
    const [, kind, width, addrWidth] = declaration; const wordBytes = Math.ceil(Number(width) / 8); const capacity = 2 ** Number(addrWidth);
    if (!/^[0-9a-fA-F]*$/.test(hex) || hex.length % 2 || hex.length % (wordBytes * 2) || hex.length > capacity * wordBytes * 2) throw new Error(`Invalid memory image for ${name}.`);
    return { file: entry, name, kind: kind as 'rom' | 'ram', width: Number(width), addrWidth: Number(addrWidth), encoding: 'hex-bytes-little-endian', hex: hex.toLowerCase(), initialization: 'load-before-driving-inputs' };
  });
}
async function compiler(): Promise<CompilerIdentity> {
  const manifest = JSON.parse(readFileSync(resolve(PUBLIC_DIR, 'wasm/libcirc.manifest.json'), 'utf8')) as Record<string, unknown>; const wasm = readFileSync(resolve(PUBLIC_DIR, 'wasm/libcirc.wasm'));
  const instance = await instantiateLibcirc(wasm); const version = JSON.parse(new TextDecoder().decode(callOp(instance, 'analyze', { root: '/x/main.circ', files: { '/x/main.circ': '' } }).bytes));
  if (typeof version !== 'object') throw new Error('libcirc did not initialize.');
  return { version: String(manifest.version), revision: String(manifest.revision), grammarSha256: String(manifest.grammar_sha256), parserRuntimeSha256: String(manifest.parser_runtime_sha256), topologyVersion: Number(manifest.topology_version), fullVersion: Number(manifest.full_version), wasmSha256: digest(wasm) };
}
async function exampleRecords(): Promise<ExampleRecord[]> {
  const wasm = await instantiateLibcirc(readFileSync(resolve(PUBLIC_DIR, 'wasm/libcirc.wasm'))); const all = [
    ...examples.map((example) => ({ id: `example:${example.slug}`, playgroundId: `example:${example.slug}`, title: example.title, description: example.lede, level: example.level, source: example.source, memory: example.memory, sourcePath: 'site/src/content/examples.ts' })),
    ...tour.map((step) => ({ id: `tour-example:${step.slug}`, playgroundId: `tour:${tour.indexOf(step)}`, title: step.title, description: step.prose, level: null, source: step.source, memory: undefined, sourcePath: 'site/src/content/tour.ts' })),
  ];
  return all.map((item) => {
    const files = splitFiles(item.source).map(({ name, body }) => ({ name, body })); const result = callOp(wasm, 'compile', requestFor(files));
    if (result.status !== 0) throw new Error(`${item.id} does not compile against committed libcirc.wasm: ${new TextDecoder().decode(result.bytes).slice(0, 500)}`);
    const memory = memoryFor(item.source, files, item.memory); const projectSha256 = digest(json({ files, entryFile: files.at(-1)?.name, memory })); const sourceHash = digest(item.source);
    return { id: item.id, kind: 'example', title: item.title, parentId: null, relatedIds: [], citation: citation(item.sourcePath, sourceHash, null, null, item.id.startsWith('example:') ? '/gallery' : null, item.id.startsWith('example:') ? '/gallery.md' : '/reference/tour-examples.md', item.id.startsWith('example:') ? item.id.slice(8) : item.id.slice(13)), playgroundId: item.playgroundId, level: item.level, description: item.description, entryFile: files.at(-1)!.name, files, memory, projectSha256, validation: { compile: 'passed', warnings: [], memoryShapes: 'passed', behavior: 'not_checked', scenarioIds: [] } };
  });
}
function indexed(record: CorpusRecord, shardKey: string): IndexedRecord | null {
  if (record.kind !== 'reference' && record.kind !== 'diagnostic' && record.kind !== 'example') return null;
  const content = record.kind === 'example' ? `${record.description}\n${record.files.map((file) => file.body).join('\n')}` : record.text;
  return { id: record.id, kind: record.kind, title: record.title, parentId: record.parentId, relatedIds: record.relatedIds, citation: record.citation, shardKey, headingPath: [record.title], tags: [], excerpt: content.replace(/\s+/g, ' ').slice(0, 477).replace(/\s+\S*$/, '').trimEnd() + (content.length > 480 ? '...' : ''), directContentLength: content.length, terms: { title: terms(record.title), headings: terms(record.title), tags: {}, prose: terms(record.kind === 'example' ? record.description : record.text), code: terms(record.kind === 'example' ? record.files.map((file) => file.body).join('\n') : '') } };
}
function asset(value: unknown): { path: string; sha256: string; bytes: number; contents: string } { const contents = json(value); const sha256 = digest(contents); return { path: `/agent-reference/assets/${sha256}.json`, sha256, bytes: Buffer.byteLength(contents), contents }; }
function gitRevision(): string | null { try { return execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(); } catch { return null; } }

const compilerIdentity = await compiler();
const refs = documentKeys.flatMap(documentRecords); const diagnostics = diagnosticRecords(); const examplesOut = await exampleRecords();
const duplicateReferenceIds = refs.map((record) => record.id).filter((id, index, ids) => ids.indexOf(id) !== index);
if (duplicateReferenceIds.length) throw new Error(`Duplicate reference semantic IDs require an explicit override: ${[...new Set(duplicateReferenceIds)].join(', ')}`);
const shards = new Map<string, CorpusRecord[]>();
for (const record of [...refs, ...diagnostics]) { const key = record.id.startsWith('diagnostic:') ? 'circuit-format' : record.id.split(':')[1]; (shards.get(key) ?? shards.set(key, []).get(key)!).push(record); }
for (const example of examplesOut) {
  const key = example.id; const resources: TextRecord[] = [
    ...example.files.map((file) => ({ ...textRecord(`${example.id}/file/${encodeURIComponent(file.name)}`, file.name, file.body, example.citation.sourcePath, example.citation.sourceHash, null, null, null, null, null, example.id, [], 'circ'), kind: 'example_file' as const })),
    ...example.memory.map((memory) => ({ ...textRecord(`${example.id}/memory/${encodeURIComponent(memory.file)}/${encodeURIComponent(memory.name)}`, `${memory.name} initialization`, memory.hex, example.citation.sourcePath, example.citation.sourceHash, null, null, null, null, null, example.id, [], 'hex'), kind: 'memory_image' as const })),
  ];
  shards.set(key, [example, ...resources]);
}
const shardAssets = Object.fromEntries([...shards.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([key, records]) => [key, asset({ schemaVersion: 1, corpusId: '', records })]));
const sourceSetSha256 = digest(json({ refs: documentKeys.map((key) => [key, fileHash(resolve(DOCS_DIR, `${key}.md`))]), examples: digest(readFileSync(resolve(root, 'site/src/content/examples.ts'))), tour: digest(readFileSync(resolve(root, 'site/src/content/tour.ts'))), identityMetadata: digest(readFileSync(resolve(root, 'site/src/content/agent-reference.ts'))), compiler: compilerIdentity, aliases, removed }));
const corpusId = digest(json({ sourceSetSha256, compilerIdentity, schemaVersion: 1, searchVersion: 1 }));
for (const value of Object.values(shardAssets)) { const parsed = JSON.parse(value.contents); parsed.corpusId = corpusId; const replacement = asset(parsed); Object.assign(value, replacement); }
const indexRecords = [...shards.entries()].flatMap(([key, records]) => records.map((record) => indexed(record, key)).filter((record): record is IndexedRecord => Boolean(record))).sort((a, b) => a.id.localeCompare(b.id));
const resources: KnowledgeIndex['resources'] = Object.fromEntries([...shards.entries()].flatMap(([key, records]) => records
  .filter((record): record is TextRecord => record.kind === 'example_file' || record.kind === 'memory_image')
  .map((record) => [record.id, { shardKey: key, kind: record.kind as 'example_file' | 'memory_image' }])));
const indexAsset = asset({ schemaVersion: 1, corpusId, records: indexRecords, aliases, removed, resources } satisfies KnowledgeIndex);
const manifest = { schemaVersion: 1, corpusId, sourceSetSha256, repositoryRevision: gitRevision(), compiler: compilerIdentity, searchVersion: 1, index: { path: indexAsset.path, sha256: indexAsset.sha256, bytes: indexAsset.bytes }, shards: Object.fromEntries(Object.entries(shardAssets).map(([key, value]) => [key, { path: value.path, sha256: value.sha256, bytes: value.bytes }])), counts: { reference: refs.length, diagnostic: diagnostics.length, example: examplesOut.length } } satisfies KnowledgeManifest;
const manifestAsset = asset(manifest); const pointer = { schemaVersion: 1, corpusId, manifest: { path: manifestAsset.path, sha256: manifestAsset.sha256, bytes: manifestAsset.bytes }, owned: [manifestAsset.path, indexAsset.path, ...Object.values(shardAssets).map((item) => item.path)].sort() };
mkdirSync(assets, { recursive: true });
const prior = existsSync(resolve(out, 'manifest.json')) ? JSON.parse(readFileSync(resolve(out, 'manifest.json'), 'utf8')) as { owned?: string[] } : null;
for (const item of [manifestAsset, indexAsset, ...Object.values(shardAssets)]) writeFileSync(resolve(PUBLIC_DIR, item.path.slice(1)), item.contents);
writeFileSync(resolve(out, 'manifest.json'), json(pointer));
for (const path of prior?.owned ?? []) if (typeof path === 'string' && path.startsWith('/agent-reference/assets/') && !pointer.owned.includes(path)) rmSync(resolve(PUBLIC_DIR, path.slice(1)), { force: true });
console.log(`agent-reference ${corpusId} (${refs.length} references, ${diagnostics.length} diagnostics, ${examplesOut.length} examples; compiler ${compilerIdentity.version})`);
