export type SearchKind = 'reference' | 'diagnostic' | 'example';
export type RecordKind = SearchKind | 'example_file' | 'memory_image';

export interface Citation {
  sourcePath: string;
  sourceHash: string;
  startLine: number | null;
  endLine: number | null;
  htmlPath: string | null;
  markdownPath: string | null;
  heading: string | null;
}

export interface ResolvedCitation extends Citation { htmlUrl: string | null; markdownUrl: string | null; }
export interface RecordHeader { id: string; kind: RecordKind; title: string; parentId: string | null; relatedIds: string[]; citation: Citation; }
export interface PublicRecordHeader extends Omit<RecordHeader, 'citation'> { citation: ResolvedCitation; }
export interface TextRecord extends RecordHeader { kind: 'reference' | 'diagnostic' | 'example_file' | 'memory_image'; format: 'markdown' | 'circ' | 'hex'; text: string; textSha256: string; }
export interface ExampleFile { name: string; body: string; }
export interface ExampleMemory { file: string; name: string; kind: 'rom' | 'ram'; width: number; addrWidth: number; encoding: 'hex-bytes-little-endian'; hex: string; initialization: 'load-before-driving-inputs'; }
export interface ExampleRecord extends RecordHeader {
  kind: 'example'; playgroundId: string; level: 'intro' | 'medium' | 'advanced' | null;
  description: string; entryFile: string; files: ExampleFile[]; memory: ExampleMemory[]; projectSha256: string;
  validation: { compile: 'passed'; warnings: { code: string; file: string; line: number; message: string }[]; memoryShapes: 'passed'; behavior: 'passed' | 'not_checked'; scenarioIds: string[]; };
}
export interface AssetRef { path: string; sha256: string; bytes: number; }
export interface CompilerIdentity { version: string; revision: string; grammarSha256: string; parserRuntimeSha256: string; topologyVersion: number; fullVersion: number; wasmSha256: string; }
export interface KnowledgeManifest { schemaVersion: 1; corpusId: string; sourceSetSha256: string; repositoryRevision: string | null; compiler: CompilerIdentity; searchVersion: 1; index: AssetRef; shards: Record<string, AssetRef>; counts: { reference: number; diagnostic: number; example: number }; }
export interface IndexedRecord extends RecordHeader { kind: SearchKind; shardKey: string; headingPath: string[]; tags: string[]; excerpt: string; directContentLength: number; terms: Record<'title' | 'headings' | 'tags' | 'prose' | 'code', Record<string, number>>; }
export interface KnowledgeIndex { schemaVersion: 1; corpusId: string; records: IndexedRecord[]; aliases: Record<string, string>; removed: Record<string, { replacementId: string | null }>; resources: Record<string, { shardKey: string; kind: 'example_file' | 'memory_image' }>; }
export type CorpusRecord = TextRecord | ExampleRecord;

export type HelpInput =
  | { action: 'search'; query: string; kind?: SearchKind; limit?: number; cursor?: string; expectedCorpusId?: string }
  | { action: 'read'; id: string; offset?: number; maxCodeUnits?: number; expectedCorpusId?: string }
  | { action: 'example'; id: string; expectedCorpusId?: string };
export interface HelpContext { corpusId: string; compiler: CompilerIdentity; activeCompilerComparison: 'match' | 'mismatch' | 'not_initialized'; }
