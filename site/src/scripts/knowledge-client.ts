import { MAX_TOOL_RESULT_BYTES, type AgentError, type DomainResult } from './playground-contract.ts';
import type { CompilerIdentity, CorpusRecord, HelpContext, KnowledgeIndex, KnowledgeManifest, PublicRecordHeader, ResolvedCitation, TextRecord } from './knowledge-contract.ts';
import { decodeCursor, encodeCursor, search } from './knowledge-search.ts';

const encoder = new TextEncoder();
const error = (code: AgentError['code'], message: string, retryable = false): DomainResult<never> => ({ ok: false, error: { code, message, retryable } });
const sha256 = async (text: string) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(text)))].map((x) => x.toString(16).padStart(2, '0')).join('');
const safePath = (path: string) => path.startsWith('/agent-reference/assets/') && !path.includes('..') && !path.includes('//');
const jsonSize = (value: unknown) => encoder.encode(JSON.stringify(value)).byteLength;

export interface KnowledgeClientOptions { manifestUrl: string; corpusId: string; compilerIdentity: () => Partial<CompilerIdentity> | null; fetch?: typeof fetch; }
export class KnowledgeClient {
  private manifest: KnowledgeManifest | null = null;
  private index: KnowledgeIndex | null = null;
  private readonly assets = new Map<string, Promise<unknown>>();
  private disposed = false;
  constructor(private readonly options: KnowledgeClientOptions) {}
  dispose(): void { this.disposed = true; this.assets.clear(); }
  private async asset<T>(path: string, digest: string, bytes: number): Promise<T> {
    if (!safePath(path)) throw new Error('undeclared asset path');
    const prior = this.assets.get(path); if (prior) return prior as Promise<T>;
    const request = (async () => {
      const response = await (this.options.fetch ?? fetch)(path, { signal: AbortSignal.timeout(10000) });
      if (!response.ok) throw new Error(`asset request failed (${response.status})`);
      const text = await response.text();
      if (encoder.encode(text).byteLength !== bytes || await sha256(text) !== digest) throw new Error('asset digest mismatch');
      return JSON.parse(text) as T;
    })();
    this.assets.set(path, request);
    try { return await request; } catch (cause) { this.assets.delete(path); throw cause; }
  }
  private async ready(): Promise<{ manifest: KnowledgeManifest; index: KnowledgeIndex }> {
    if (this.disposed) throw new Error('disposed');
    if (!this.manifest) {
      const response = await (this.options.fetch ?? fetch)(this.options.manifestUrl, { signal: AbortSignal.timeout(10000) });
      if (!response.ok) throw new Error(`manifest request failed (${response.status})`);
      const pointer = await response.json() as { manifest: { path: string; sha256: string; bytes: number }; corpusId: string };
      if (pointer.corpusId !== this.options.corpusId || !pointer.manifest || !safePath(pointer.manifest.path)) throw new Error('invalid manifest pointer');
      this.manifest = await this.asset<KnowledgeManifest>(pointer.manifest.path, pointer.manifest.sha256, pointer.manifest.bytes);
      if (this.manifest.schemaVersion !== 1 || this.manifest.corpusId !== pointer.corpusId || this.manifest.corpusId !== this.options.corpusId) throw new Error('inconsistent corpus');
    }
    if (!this.index) {
      const m = this.manifest;
      this.index = await this.asset<KnowledgeIndex>(m.index.path, m.index.sha256, m.index.bytes);
      if (this.index.schemaVersion !== 1 || this.index.corpusId !== m.corpusId) throw new Error('inconsistent index');
    }
    return { manifest: this.manifest, index: this.index };
  }
  private context(manifest: KnowledgeManifest): HelpContext {
    const active = this.options.compilerIdentity();
    const fields: (keyof CompilerIdentity)[] = ['version', 'revision', 'grammarSha256', 'parserRuntimeSha256', 'topologyVersion', 'fullVersion'];
    const comparison = !active ? 'not_initialized' : fields.every((key) => active[key] === undefined || active[key] === manifest.compiler[key]) ? 'match' : 'mismatch';
    return { corpusId: manifest.corpusId, compiler: manifest.compiler, activeCompilerComparison: comparison };
  }
  private citation(citation: TextRecord['citation']): ResolvedCitation {
    const assetRoot = new URL('../', new URL(this.options.manifestUrl, document.baseURI));
    const resolve = (path: string | null) => path ? new URL(path.replace(/^\//, ''), assetRoot).toString() : null;
    return { ...citation, htmlUrl: citation.htmlPath ? `${resolve(citation.htmlPath)}${citation.heading ? `#${citation.heading}` : ''}` : null, markdownUrl: citation.markdownPath ? `${resolve(citation.markdownPath)}${citation.heading ? `#${citation.heading}` : ''}` : null };
  }
  private header(record: CorpusRecord): PublicRecordHeader {
    return { id: record.id, kind: record.kind, title: record.title, parentId: record.parentId, relatedIds: record.relatedIds, citation: this.citation(record.citation) };
  }
  private async record(id: string): Promise<CorpusRecord | null> {
    const { manifest, index } = await this.ready();
    let canonical = id; const seen = new Set<string>();
    while (index.aliases[canonical]) { if (seen.has(canonical)) throw new Error('alias cycle'); seen.add(canonical); canonical = index.aliases[canonical]; }
    if (index.removed[canonical]) return null;
    const indexed = index.records.find((record) => record.id === canonical);
    const resource = index.resources[canonical]; const shardKey = indexed?.shardKey ?? resource?.shardKey;
    if (!shardKey || !manifest.shards[shardKey]) return null;
    const shard = await this.asset<{ schemaVersion: 1; corpusId: string; records: CorpusRecord[] }>(manifest.shards[shardKey].path, manifest.shards[shardKey].sha256, manifest.shards[shardKey].bytes);
    if (shard.schemaVersion !== 1 || shard.corpusId !== manifest.corpusId) throw new Error('inconsistent shard');
    return shard.records.find((record) => record.id === canonical) ?? null;
  }
  async search(input: { query: string; kind?: 'reference' | 'diagnostic' | 'example'; limit?: number; cursor?: string; expectedCorpusId?: string }): Promise<DomainResult<unknown>> {
    try {
      if (input.expectedCorpusId && input.expectedCorpusId !== this.options.corpusId) return error('HELP_CORPUS_CHANGED', 'The requested corpus is not installed on this page.');
      if (typeof input.query !== 'string' || !input.query.trim() || input.query.length > 512) return error('INVALID_ARGUMENT', 'query must be a nonempty string up to 512 code units.');
      if (input.limit !== undefined && (!Number.isInteger(input.limit) || input.limit < 1 || input.limit > 10)) return error('INVALID_RANGE', 'limit must be an integer from 1 through 10.');
      const { manifest, index } = await this.ready(); let offset = 0;
      if (input.cursor) { const cursor = decodeCursor(input.cursor); if (!cursor || cursor[0] !== manifest.corpusId || cursor[1] !== input.query.normalize('NFKC').toLowerCase() || cursor[2] !== (input.kind ?? null)) return error('HELP_CORPUS_CHANGED', 'The cursor belongs to another corpus or query.'); offset = cursor[3]; }
      const records = search(index, input.query, input.kind); const limit = input.limit ?? 5; const matches: unknown[] = [];
      for (const record of records.slice(offset, offset + limit)) {
        const candidate = { id: record.id, kind: record.kind, title: record.title, excerpt: record.excerpt, citation: this.citation(record.citation), relatedIds: record.relatedIds };
        if (jsonSize({ context: this.context(manifest), query: input.query, matches: [...matches, candidate] }) > MAX_TOOL_RESULT_BYTES) break;
        matches.push(candidate);
      }
      const end = offset + matches.length;
      return { ok: true, value: { context: this.context(manifest), query: input.query, matches, totalMatches: records.length, nextCursor: end < records.length ? encodeCursor(manifest.corpusId, input.query, input.kind, end) : null } };
    } catch (cause) { return error(this.disposed ? 'PAGE_DISPOSED' : 'HELP_UNAVAILABLE', cause instanceof Error ? cause.message : 'Reference assets are unavailable.', !this.disposed); }
  }
  async read(input: { id: string; offset?: number; maxCodeUnits?: number; expectedCorpusId?: string }): Promise<DomainResult<unknown>> {
    try {
      if (input.expectedCorpusId && input.expectedCorpusId !== this.options.corpusId) return error('HELP_CORPUS_CHANGED', 'The requested corpus is not installed on this page.');
      const offset = input.offset ?? 0; const budget = input.maxCodeUnits ?? 4096;
      if (!Number.isInteger(offset) || offset < 0 || !Number.isInteger(budget) || budget < 2 || budget > 4096) return error('INVALID_RANGE', 'offset and maxCodeUnits are outside their allowed range.');
      if (offset && !input.expectedCorpusId) return error('INVALID_ARGUMENT', 'expectedCorpusId is required when offset is nonzero.');
      const record = await this.record(input.id); if (!record) return error('HELP_NOT_FOUND', 'The requested reference record was not found.');
      if (record.kind === 'example') return error('INVALID_ARGUMENT', 'Use action: example to retrieve a complete example project.');
      const text = record.text; if (offset > text.length || (offset && /[\uDC00-\uDFFF]/.test(text[offset]))) return error('INVALID_RANGE', 'offset is outside the record or splits a Unicode character.');
      let end = Math.min(text.length, offset + budget); if (end < text.length && /[\uD800-\uDBFF]/.test(text[end - 1])) end--; if (record.format === 'hex') { if (offset % 2) return error('INVALID_RANGE', 'hex reads must start on a byte boundary.'); if ((end - offset) % 2) end--; }
      if (end === offset && offset < text.length) return error('RESULT_TOO_LARGE', 'The response metadata leaves no room for a complete character.');
      const { manifest } = await this.ready(); const chunk = text.slice(offset, end);
      return { ok: true, value: { context: this.context(manifest), record: this.header(record), format: record.format, textSha256: record.textSha256, offset, endOffset: end, totalCodeUnits: text.length, text: chunk, completeRecordInResponse: end === text.length && offset === 0, nextOffset: end < text.length ? end : null } };
    } catch (cause) { return error(this.disposed ? 'PAGE_DISPOSED' : 'HELP_UNAVAILABLE', cause instanceof Error ? cause.message : 'Reference assets are unavailable.', !this.disposed); }
  }
  async example(input: { id: string; expectedCorpusId?: string }): Promise<DomainResult<unknown>> {
    try {
      if (input.expectedCorpusId && input.expectedCorpusId !== this.options.corpusId) return error('HELP_CORPUS_CHANGED', 'The requested corpus is not installed on this page.');
      const record = await this.record(input.id); if (!record || record.kind !== 'example') return error('HELP_NOT_FOUND', 'The requested example was not found.');
      const { manifest } = await this.ready(); const common = { context: this.context(manifest), id: record.id, title: record.title, description: record.description, level: record.level, playgroundId: record.playgroundId, entryFile: record.entryFile, projectSha256: record.projectSha256, citation: this.citation(record.citation), relatedIds: record.relatedIds, validation: record.validation };
      const inline = { ...common, delivery: 'inline' as const, completeProjectInResponse: true, files: record.files, memory: record.memory };
      if (jsonSize({ apiVersion: 1, pageId: 'placeholder', ok: true, data: inline }) <= MAX_TOOL_RESULT_BYTES) return { ok: true, value: inline };
      const fileRefs = await Promise.all(record.files.map(async (file) => ({ name: file.name, content: { recordId: `${record.id}/file/${encodeURIComponent(file.name)}`, textSha256: await sha256(file.body), totalCodeUnits: file.body.length } })));
      const memoryRefs = await Promise.all(record.memory.map(async ({ hex, ...memory }) => ({ ...memory, content: { recordId: `${record.id}/memory/${encodeURIComponent(memory.file)}/${encodeURIComponent(memory.name)}`, textSha256: await sha256(hex), totalCodeUnits: hex.length } })));
      return { ok: true, value: { ...common, delivery: 'manifest', completeProjectInResponse: false, files: fileRefs, memory: memoryRefs } };
    } catch (cause) { return error(this.disposed ? 'PAGE_DISPOSED' : 'HELP_UNAVAILABLE', cause instanceof Error ? cause.message : 'Reference assets are unavailable.', !this.disposed); }
  }
}
