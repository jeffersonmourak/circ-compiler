// Analyze JSON → absolute offsets in the playground's combined document.
//
// Two conversions have to happen and both are easy to get silently wrong:
// the compiler reports 1-based BYTE columns while an editor counts UTF-16
// code units, and it reports file-LOCAL line numbers while the playground
// edits one string in which each `// <name>.circ` file starts at its own
// `SplitFile.startLine`. A mapper that forgets either lands the squiggle on
// the wrong text without ever failing.
//
// Pure and DOM-free: no CodeMirror import, so `bun test` can prove the
// mapping against the committed `libcirc.wasm` without a browser.
import { byteColToUtf16 } from '../utils/columns.ts';
import { PLAYGROUND_DIR, type SplitFile } from '../utils/split-files.ts';

/** 1-based line, 1-based BYTE column, end exclusive (`DOCS/analyze-api.md`). */
export interface AnalyzeRange {
  start_line: number;
  start_col: number;
  end_line: number;
  end_col: number;
}

export interface AnalyzeRelated {
  file_id: number;
  range: AnalyzeRange;
  message: string;
}

export interface AnalyzeDiagnostic {
  file_id: number;
  severity: 'error' | 'warning';
  /** `E001`-`E018`, `W001`-`W003`, or `syntax`. */
  code: string;
  range: AnalyzeRange;
  message: string;
  related?: AnalyzeRelated[];
}

export interface AnalyzeSymbol {
  file_id: number;
  name: string;
  kind: 'input' | 'output' | 'and' | 'not' | 'led' | 'rom' | 'ram' | 'instance';
  width: number;
  /** `rom`/`ram` only. */
  addr_width?: number;
  range: AnalyzeRange;
}

export interface AnalyzeReference {
  file_id: number;
  range: AnalyzeRange;
  target_file: number;
  target_range: AnalyzeRange;
  hover: string;
}

export interface Analysis {
  files: { file_id: number; path: string }[];
  diagnostics: AnalyzeDiagnostic[];
  symbols: AnalyzeSymbol[];
  references: AnalyzeReference[];
}

/** Line texts and their absolute UTF-16 start offsets, computed once per doc. */
export interface DocIndex {
  readonly lines: readonly string[];
  readonly starts: readonly number[];
  readonly length: number;
}

export function indexDoc(doc: string): DocIndex {
  const lines = doc.split('\n');
  const starts: number[] = new Array(lines.length);
  let offset = 0;
  for (let i = 0; i < lines.length; i += 1) {
    starts[i] = offset;
    offset += lines[i].length + 1; // +1 for the '\n' that split removed
  }
  return { lines, starts, length: doc.length };
}

/** `/playground/<name>.circ` → `<name>.circ`. Null for `<builtin>/…` sources
 *  and anything else outside the playground's virtual directory: those have no
 *  editor buffer, so no span can be computed for them. */
export function fileNameFor(analysis: Analysis, fileId: number): string | null {
  const path = analysis.files.find((f) => f.file_id === fileId)?.path;
  if (!path || !path.startsWith(`${PLAYGROUND_DIR}/`)) return null;
  return path.slice(PLAYGROUND_DIR.length + 1);
}

/** File-local 1-based line → 0-based line in the combined document. Null when
 *  the named file is not open. */
export function docLine(files: readonly SplitFile[], name: string, fileLine1: number): number | null {
  const file = files.find((f) => f.name === name);
  if (!file) return null;
  return file.startLine + fileLine1 - 1;
}

const clampLine = (index: DocIndex, line0: number): number =>
  Math.max(0, Math.min(line0, index.lines.length - 1));

/** Absolute UTF-16 offset of a 0-based document line and a 1-based byte
 *  column, clamped to that line's end and to the document's end. */
export function offsetAt(index: DocIndex, docLine0: number, byteCol1: number): number {
  const line0 = clampLine(index, docLine0);
  const line = index.lines[line0] ?? '';
  const col = byteColToUtf16(line, byteCol1); // 1-based UTF-16, already clamped to the line
  const offset = index.starts[line0] + Math.min(col - 1, line.length);
  return Math.max(0, Math.min(offset, index.length));
}

/** The 0-based line an absolute offset falls on. */
function lineOfOffset(index: DocIndex, offset: number): number {
  let lo = 0;
  let hi = index.starts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (index.starts[mid] <= offset) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

/**
 * Both ends of one analyze range as absolute UTF-16 offsets, or null when the
 * blamed file has no editor buffer. Guarantees `0 <= from <= to <= length`,
 * and widens an empty span by one code point where the line has room, so the
 * squiggle is visible rather than a zero-width point.
 */
export function rangeToSpan(
  index: DocIndex,
  files: readonly SplitFile[],
  analysis: Analysis,
  fileId: number,
  range: AnalyzeRange,
): { from: number; to: number } | null {
  const name = fileNameFor(analysis, fileId);
  if (name === null) return null;
  const startLine = docLine(files, name, range.start_line);
  if (startLine === null) return null;
  const endLine = docLine(files, name, range.end_line) ?? startLine;

  const from = offsetAt(index, startLine, range.start_col);
  let to = offsetAt(index, endLine, range.end_col);
  if (to < from) to = from;
  if (to === from) {
    const line0 = lineOfOffset(index, from);
    const line = index.lines[line0] ?? '';
    const col = from - index.starts[line0];
    if (col < line.length) {
      // Step a whole code point so a surrogate pair is never split.
      const code = line.charCodeAt(col);
      const step = code >= 0xd800 && code <= 0xdbff && col + 1 < line.length ? 2 : 1;
      to = Math.min(from + step, index.length);
    }
  }
  return { from, to };
}

export interface MappedDiagnostic {
  /** Absolute UTF-16 span, or null when the compiler blamed a file with no
   *  editor buffer. Nullable so the list stays total. */
  from: number | null;
  to: number | null;
  severity: 'error' | 'warning';
  code: string;
  message: string;
  /** The file the compiler blamed: the playground-local name, or the raw
   *  `files[].path` when there is no buffer for it. */
  fileName: string;
  /** The compiler's own FILE-LOCAL position: `line` is `range.start_line`
   *  verbatim, `column` the UTF-16 conversion of `range.start_col`. */
  line: number;
  column: number;
  /** 0-based line in the combined document — the number the old label showed.
   *  Null whenever `from` is null. */
  docLine: number | null;
}

/** One entry per analyze diagnostic, in order. Entries whose file has no
 *  buffer keep their row (with a null span) rather than vanishing. */
export function mapDiagnostics(
  doc: string,
  files: readonly SplitFile[],
  analysis: Analysis,
): MappedDiagnostic[] {
  const index = indexDoc(doc);
  return analysis.diagnostics.map((d) => {
    const name = fileNameFor(analysis, d.file_id);
    const span = rangeToSpan(index, files, analysis, d.file_id, d.range);
    const line0 = name === null ? null : docLine(files, name, d.range.start_line);
    const lineText = line0 === null ? null : (index.lines[clampLine(index, line0)] ?? '');
    return {
      from: span ? span.from : null,
      to: span ? span.to : null,
      severity: d.severity,
      code: d.code,
      message: d.message,
      fileName: name ?? analysis.files.find((f) => f.file_id === d.file_id)?.path ?? `file ${d.file_id}`,
      line: d.range.start_line,
      column: lineText === null ? d.range.start_col : byteColToUtf16(lineText, d.range.start_col),
      docLine: span ? line0 : null,
    };
  });
}

/** Structurally a `@codemirror/lint` `Diagnostic`, without importing the
 *  package — `circ-editor.ts` does the hand-off. Entries with no span are
 *  dropped here and only here. */
export function toLintDiagnostics(
  mapped: readonly MappedDiagnostic[],
): { from: number; to: number; severity: 'error' | 'warning'; message: string; source: string }[] {
  const out: { from: number; to: number; severity: 'error' | 'warning'; message: string; source: string }[] = [];
  for (const m of mapped) {
    if (m.from === null || m.to === null) continue;
    out.push({
      from: m.from,
      to: m.to,
      severity: m.severity,
      message: m.message,
      source: m.code,
    });
  }
  return out;
}

/** A mapped diagnostic plus the file tab it belongs to, or `null` when the
 *  compiler blamed a file with no tab. */
export type TabbedDiagnostic = MappedDiagnostic & { tab: number | null };

/**
 * Map one analysis against a set of tabs, each file on its own.
 *
 * Each per-tab call passes a synthetic single-entry file array, so `docLine`
 * degenerates to the file-local line and the offsets address that tab's own
 * document. The mapper is total — one entry per analyze diagnostic, every
 * time — so every call returns the whole list; a tab keeps only the rows it
 * could actually place, and the placeless ones are emitted once from a single
 * extra pass. Without that, an N-tab project would list every unplaceable
 * diagnostic N times.
 *
 * `rows` is the flat list the panel renders; `perTab[i]` is what tab `i`'s
 * editor document should be given, after `toLintDiagnostics`.
 */
export function mapPerTab(
  files: readonly { name: string; body: string }[],
  analysis: Analysis,
): { perTab: MappedDiagnostic[][]; rows: TabbedDiagnostic[] } {
  const perTab = files.map((f) =>
    mapDiagnostics(f.body, [{ name: f.name, body: f.body, startLine: 0 }], analysis),
  );
  const rows: TabbedDiagnostic[] = [];
  perTab.forEach((mapped, tab) => {
    for (const m of mapped) if (m.from !== null) rows.push({ ...m, tab });
  });
  const placed = new Set(rows.map(keyOf));
  for (const m of perTab[0] ?? []) {
    if (m.from === null && !placed.has(keyOf(m))) rows.push({ ...m, tab: null });
  }
  return { perTab, rows };
}

const keyOf = (m: MappedDiagnostic): string => `${m.fileName}:${m.line}:${m.column}:${m.code}:${m.message}`;

