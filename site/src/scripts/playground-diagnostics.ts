import type { Analysis, AnalyzeDiagnostic, AnalyzeRange } from './circ-diagnostics.ts';
import type { AgentDiagnostic, DiagnosticCompilerIdentity, DiagnosticLocation, DiagnosticPage, OperationId, Revision, WorkInputs } from './playground-contract.ts';
import { byteColToUtf16 } from '../utils/columns.ts';
import { PLAYGROUND_DIR } from '../utils/split-files.ts';

export const DEFAULT_DIAGNOSTIC_LIMIT = 20;
export const MAX_DIAGNOSTIC_LIMIT = 100;
export const MAX_RETAINED_DIAGNOSTIC_SETS = 32;
export const MAX_RETAINED_DIAGNOSTIC_BYTES = 2 * 1024 * 1024;
export const MAX_DIAGNOSTIC_SET_BYTES = 1024 * 1024;

type SetRecord = { id: string; producerOperationId: OperationId; requestedOperationId: OperationId; producerInputs: WorkInputs; requestedInputs: WorkInputs; compiler: DiagnosticCompilerIdentity; counts: { errors: number; warnings: number }; diagnostics: AgentDiagnostic[]; bytes: number };

function clone<T>(value: T): T { return JSON.parse(JSON.stringify(value)) as T; }
function validCoordinate(value: number): boolean { return Number.isSafeInteger(value) && value > 0; }
function sourcePosition(body: string, range: AnalyzeRange): DiagnosticLocation['sourceRange'] | null {
  const lines = body.split('\n');
  if (![range.start_line, range.end_line, range.start_col, range.end_col].every(validCoordinate) || range.start_line > range.end_line || (range.start_line === range.end_line && range.start_col > range.end_col) || range.start_line > lines.length || range.end_line > lines.length) return null;
  const position = (lineNumber: number, byteColumn: number) => {
    const line = lines[lineNumber - 1]!;
    const bytes = new TextEncoder().encode(line).byteLength;
    if (byteColumn > bytes + 1) return null;
    let byte = 0;
    for (const char of line) {
      if (byte === byteColumn - 1) break;
      byte += new TextEncoder().encode(char).byteLength;
      if (byte > byteColumn - 1) return null;
    }
    if (byte !== byteColumn - 1 && byteColumn !== bytes + 1) return null;
    const column = byteColToUtf16(line, byteColumn);
    const offset = lines.slice(0, lineNumber - 1).reduce((sum, item) => sum + item.length + 1, 0) + column - 1;
    return { column, offset };
  };
  const start = position(range.start_line, range.start_col);
  const end = position(range.end_line, range.end_col);
  if (!start || !end) return null;
  return { lineBase: 1, columnBase: 1, columnEncoding: 'utf16', offsetBase: 0, endExclusive: true, startLine: range.start_line, startColumn: start.column, endLine: range.end_line, endColumn: end.column, startOffset: start.offset, endOffset: end.offset };
}

function location(analysis: Analysis, files: ReadonlyMap<string, string>, fileId: number, range: AnalyzeRange): DiagnosticLocation {
  const path = analysis.files.find((file) => file.file_id === fileId)?.path ?? null;
  const fileName = path?.startsWith(`${PLAYGROUND_DIR}/`) ? path.slice(PLAYGROUND_DIR.length + 1) : null;
  const source = path ? files.get(path) : undefined;
  return {
    fileId, path, fileName, sourceAvailable: source !== undefined, currentlyEditable: false,
    nativeRange: { lineBase: 1, columnBase: 1, columnEncoding: 'utf8-bytes', endExclusive: true, startLine: range.start_line, startColumn: range.start_col, endLine: range.end_line, endColumn: range.end_col },
    sourceRange: source === undefined ? null : sourcePosition(source, range),
  };
}

export function convertDiagnostics(analysis: Analysis, requestFiles: Record<string, string>): AgentDiagnostic[] | null {
  const files = new Map(Object.entries(requestFiles));
  const convert = (diagnostic: AnalyzeDiagnostic): AgentDiagnostic | null => {
    const primary = location(analysis, files, diagnostic.file_id, diagnostic.range);
    if (primary.sourceAvailable && primary.sourceRange === null) return null;
    const related = (diagnostic.related ?? []).map((item) => ({ message: item.message, location: location(analysis, files, item.file_id, item.range) }));
    if (related.some((item) => item.location.sourceAvailable && item.location.sourceRange === null)) return null;
    return { severity: diagnostic.severity, code: diagnostic.code, message: diagnostic.message, location: primary, related };
  };
  const diagnostics = analysis.diagnostics.map(convert);
  return diagnostics.every((diagnostic): diagnostic is AgentDiagnostic => diagnostic !== null) ? diagnostics : null;
}

export class DiagnosticStore {
  private sequence = 0;
  private bytes = 0;
  private readonly records = new Map<string, SetRecord>();

  retain(input: Omit<SetRecord, 'id' | 'bytes'>): string | null {
    const bytes = new TextEncoder().encode(JSON.stringify(input.diagnostics)).byteLength;
    if (bytes > MAX_DIAGNOSTIC_SET_BYTES) return null;
    while ((this.records.size >= MAX_RETAINED_DIAGNOSTIC_SETS || this.bytes + bytes > MAX_RETAINED_DIAGNOSTIC_BYTES) && this.records.size) {
      const oldest = this.records.values().next().value as SetRecord;
      this.records.delete(oldest.id); this.bytes -= oldest.bytes;
    }
    if (this.bytes + bytes > MAX_RETAINED_DIAGNOSTIC_BYTES) return null;
    const id = `diagnostics:${++this.sequence}`;
    this.records.set(id, { ...input, id, bytes }); this.bytes += bytes;
    return id;
  }

  page(operationId: string, expectedSourceRevision: Revision | undefined, cursor: string | undefined, limit: number | undefined, observationRevision: Revision, current: { projectId: string; sourceRevision: Revision; files: readonly string[] }): { ok: true; value: DiagnosticPage } | { ok: false; code: 'DIAGNOSTICS_EXPIRED' | 'REVISION_CONFLICT' | 'INVALID_ARGUMENT'; message: string } {
    const requested = [...this.records.values()].find((record) => record.requestedOperationId === operationId);
    if (!requested) return { ok: false, code: 'DIAGNOSTICS_EXPIRED', message: 'The diagnostic set is no longer retained.' };
    const parsed = cursor ? (() => { try { return JSON.parse(decodeURIComponent(cursor)) as { id: string; offset: number; operationId: string }; } catch { return null; } })() : null;
    if (cursor && (!parsed || parsed.id !== requested.id || parsed.operationId !== operationId || !Number.isSafeInteger(parsed.offset))) return { ok: false, code: 'INVALID_ARGUMENT', message: 'cursor is invalid for this diagnostic set.' };
    if (expectedSourceRevision !== undefined && expectedSourceRevision !== requested.requestedInputs.target.sourceRevision) return { ok: false, code: 'REVISION_CONFLICT', message: 'The requested operation used another source revision.' };
    const take = limit ?? DEFAULT_DIAGNOSTIC_LIMIT;
    if (!Number.isSafeInteger(take) || take < 1 || take > MAX_DIAGNOSTIC_LIMIT) return { ok: false, code: 'INVALID_ARGUMENT', message: 'limit must be a safe integer from 1 through 100.' };
    const offset = parsed?.offset ?? 0;
    const diagnostics = requested.diagnostics.slice(offset, offset + take).map((diagnostic) => {
      const editable = requested.requestedInputs.target.projectId === current.projectId && requested.requestedInputs.target.sourceRevision === current.sourceRevision && diagnostic.location.fileName !== null && current.files.includes(diagnostic.location.fileName);
      return { ...diagnostic, location: { ...diagnostic.location, currentlyEditable: editable }, related: diagnostic.related.map((item) => ({ ...item, location: { ...item.location, currentlyEditable: editable && item.location.fileName !== null && current.files.includes(item.location.fileName) } })) };
    });
    const next = offset + diagnostics.length;
    return { ok: true, value: { requestedOperationId: operationId, producerOperationId: requested.producerOperationId, diagnosticSetId: requested.id, observationRevision, requestedInputs: clone(requested.requestedInputs), producerInputs: clone(requested.producerInputs), compiler: clone(requested.compiler), counts: { ...requested.counts }, diagnostics, nextCursor: next < requested.diagnostics.length ? encodeURIComponent(JSON.stringify({ id: requested.id, operationId, offset: next })) : null } };
  }
}
