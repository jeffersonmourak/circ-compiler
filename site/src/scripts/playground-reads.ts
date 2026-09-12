import type { FileChunk, ProjectManifest, ProjectSummary, ProjectVersion } from './playground-contract.ts';
import type { SourceFile } from './playground-revisions.ts';

export const DEFAULT_PAGE_LIMIT = 20;
export const MAX_PAGE_LIMIT = 50;
export const DEFAULT_CHUNK_SIZE = 2048;
export const MAX_CHUNK_SIZE = 4096;

export interface ReadProject {
  id: string; name: string; kind: 'example' | 'tour' | 'scratch'; active: boolean;
  version: ProjectVersion; files: readonly SourceFile[];
  sourceOrigin: ProjectManifest['sourceOrigin']; selectedEntryFile: string | null;
}

export interface WorkspaceSnapshot { revision: string; projects: readonly ReadProject[]; }
export type ReadResult<T> = { ok: true; value: T } | { ok: false; code: 'PROJECT_NOT_FOUND' | 'FILE_NOT_FOUND' | 'REVISION_CONFLICT' | 'INVALID_RANGE' | 'INVALID_ARGUMENT'; message: string };

interface Cursor { tool: 'projects' | 'project'; revision: string; projectId?: string; offset: number; }
const encode = (cursor: Cursor) => encodeURIComponent(JSON.stringify(cursor));
const decode = (value: string): Cursor | null => {
  try {
    const parsed = JSON.parse(decodeURIComponent(value));
    return parsed && typeof parsed === 'object' && (parsed.tool === 'projects' || parsed.tool === 'project')
      && typeof parsed.revision === 'string' && Number.isSafeInteger(parsed.offset) && parsed.offset >= 0 ? parsed : null;
  } catch { return null; }
};
const failure = <T>(code: 'PROJECT_NOT_FOUND' | 'FILE_NOT_FOUND' | 'REVISION_CONFLICT' | 'INVALID_RANGE' | 'INVALID_ARGUMENT', message: string): ReadResult<T> => ({ ok: false, code, message });
const countLines = (body: string) => body.length === 0 ? 1 : body.split('\n').length;
const metadata = (file: SourceFile) => ({ name: file.name, utf16Length: file.body.length, utf8Bytes: new TextEncoder().encode(file.body).byteLength, lineCount: countLines(file.body) });

function page<T>(items: readonly T[], offset: number, limit: number, cursor: (next: number) => string): { items: T[]; nextCursor: string | null } {
  const slice = items.slice(offset, offset + limit);
  const next = offset + slice.length;
  return { items: slice, nextCursor: next < items.length ? cursor(next) : null };
}

function validLimit(value: unknown, fallback: number): number | null {
  if (value === undefined) return fallback;
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 1 && value <= MAX_PAGE_LIMIT ? value : null;
}

export function listProjects(snapshot: WorkspaceSnapshot, input: { cursor?: string; limit?: number }): ReadResult<{ workspaceRevision: string; projects: ProjectSummary[]; nextCursor: string | null }> {
  const limit = validLimit(input.limit, DEFAULT_PAGE_LIMIT);
  if (!limit) return failure('INVALID_ARGUMENT', 'limit must be a safe integer from 1 through 50.');
  const parsed = input.cursor === undefined ? null : decode(input.cursor);
  if (input.cursor !== undefined && (!parsed || parsed.tool !== 'projects')) return failure('INVALID_ARGUMENT', 'cursor is invalid for this tool.');
  if (parsed && parsed.revision !== snapshot.revision) return failure('REVISION_CONFLICT', 'Workspace contents changed; start listing again.');
  const offset = parsed?.offset ?? 0;
  const projects = snapshot.projects.map(({ files, sourceOrigin, selectedEntryFile, ...summary }) => ({ ...summary, version: { ...summary.version }, fileCount: files.length }));
  const result = page(projects, offset, limit, (next) => encode({ tool: 'projects', revision: snapshot.revision, offset: next }));
  return { ok: true, value: { workspaceRevision: snapshot.revision, projects: result.items, nextCursor: result.nextCursor } };
}

export function readProject(snapshot: WorkspaceSnapshot, input: { projectId?: string; expectedRevision?: string; cursor?: string; limit?: number }): ReadResult<ProjectManifest> {
  const project = snapshot.projects.find((candidate) => candidate.id === (input.projectId ?? snapshot.projects.find((item) => item.active)?.id));
  if (!project) return failure('PROJECT_NOT_FOUND', 'The requested project is not available.');
  if (input.expectedRevision !== undefined && input.expectedRevision !== project.version.revision) return failure('REVISION_CONFLICT', 'Project contents changed; reread its manifest.');
  const limit = validLimit(input.limit, DEFAULT_PAGE_LIMIT);
  if (!limit) return failure('INVALID_ARGUMENT', 'limit must be a safe integer from 1 through 50.');
  const parsed = input.cursor === undefined ? null : decode(input.cursor);
  if (input.cursor !== undefined && (!parsed || parsed.tool !== 'project' || parsed.projectId !== project.id)) return failure('INVALID_ARGUMENT', 'cursor is invalid for this project.');
  if (parsed && parsed.revision !== project.version.revision) return failure('REVISION_CONFLICT', 'Project contents changed; reread its manifest.');
  const result = page(project.files.map(metadata), parsed?.offset ?? 0, limit, (next) => encode({ tool: 'project', revision: project.version.revision, projectId: project.id, offset: next }));
  return { ok: true, value: { project: { id: project.id, name: project.name, kind: project.kind, active: project.active, version: { ...project.version }, fileCount: project.files.length }, sourceOrigin: project.sourceOrigin, defaultEntryFile: project.files.at(-1)?.name ?? '', selectedEntryFile: project.selectedEntryFile, files: result.items, nextCursor: result.nextCursor } };
}

export function readFile(snapshot: WorkspaceSnapshot, input: { projectId?: string; name: string; expectedSourceRevision?: string; offset?: number; maxCodeUnits?: number }): ReadResult<FileChunk> {
  const project = snapshot.projects.find((candidate) => candidate.id === (input.projectId ?? snapshot.projects.find((item) => item.active)?.id));
  if (!project) return failure('PROJECT_NOT_FOUND', 'The requested project is not available.');
  const file = project.files.find((candidate) => candidate.name === input.name);
  if (!file) return failure('FILE_NOT_FOUND', 'The requested file is not available.');
  const offset = input.offset ?? 0;
  const size = input.maxCodeUnits ?? DEFAULT_CHUNK_SIZE;
  if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(size) || size < 2 || size > MAX_CHUNK_SIZE || offset > file.body.length || (offset > 0 && /[\uDC00-\uDFFF]/.test(file.body[offset] ?? ''))) return failure('INVALID_RANGE', 'offset or maxCodeUnits is outside the valid UTF-16 range.');
  if (offset > 0 && input.expectedSourceRevision !== project.version.sourceRevision) return failure('REVISION_CONFLICT', 'Source changed; restart the file read.');
  if (input.expectedSourceRevision !== undefined && input.expectedSourceRevision !== project.version.sourceRevision) return failure('REVISION_CONFLICT', 'Source changed; restart the file read.');
  let end = Math.min(file.body.length, offset + size);
  if (end < file.body.length && /[\uDC00-\uDFFF]/.test(file.body[end] ?? '')) end -= 1;
  const text = file.body.slice(offset, end);
  const eof = end === file.body.length;
  return { ok: true, value: { projectId: project.id, sourceRevision: project.version.sourceRevision, name: file.name, encoding: 'utf16', offset, endOffset: end, totalCodeUnits: file.body.length, text, nextOffset: eof ? null : end, eof } };
}
