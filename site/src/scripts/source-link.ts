// The join between what the reader wrote and what the canvas drew.
//
// It is a join on the declared NAME, never on a span: a compiled artifact
// carries no source positions, so there is nothing else to match on. The
// analysis supplies the names and their ranges; the layout supplies the boxes.
//
// Pure and DOM-free, and it imports no value from anywhere — the renderer's
// types are restated structurally so this module never drags the renderer into
// the playground's eager bundle. `bun test` drives all of it headlessly.

/** The analyze contract has exactly one definition and the diagnostics module
 *  owns it; re-declaring it here would fork it. An `import type` is erased, so
 *  this costs nothing at runtime. */
import type { AnalyzeRange, AnalyzeSymbol, Analysis } from './circ-diagnostics.ts';
import { byteColToUtf16 } from '../utils/columns.ts';
import { PLAYGROUND_DIR } from '../utils/split-files.ts';

/** The kinds `--analyze` emits for a declaration. Derived from the analysis
 *  type rather than restated, so it cannot drift. */
export type SymbolKind = AnalyzeSymbol['kind'];
type AnalyzeFile = Analysis['files'][number];

/**
 * Structural subset of the renderer's placed component. Declared, not
 * imported: a type import would be erased, but keeping the shape local also
 * documents exactly which fields this join depends on.
 */
export interface PlacedLike {
  id: number;
  name: string;
  origin: readonly unknown[];
  kind: { tag: 'primitive'; kind: number } | { tag: 'subcircuit'; subcircuit: string };
}

export interface LayoutLike {
  components: readonly PlacedLike[];
}

/**
 * The topology kind byte each symbol kind draws as. Hard-coded for the same
 * reason the island hard-codes the input-pin byte; a test asserts it against
 * the renderer's own enum, so a renumbering fails here rather than silently
 * mis-joining.
 */
export const TOPOLOGY_KIND_OF: Record<SymbolKind, number | 'subcircuit'> = {
  input: 0,
  not: 1,
  and: 2,
  led: 4,
  output: 5,
  rom: 8,
  ram: 9,
  instance: 'subcircuit',
};

/** A root-file declaration a reader can navigate to. */
export interface Declaration {
  name: string;
  kind: SymbolKind;
  fileId: number;
  range: AnalyzeRange;
}

/**
 * A declaration joined to the box that draws it. It deliberately carries **no
 * range**: the last good canvas — and therefore this table — stays on screen
 * across an unbounded number of failing edits, while the analysis behind it
 * keeps refreshing. A range snapshotted here would come to point at whatever
 * text had since moved into those columns.
 */
export interface SourceLink {
  name: string;
  kind: SymbolKind;
  fileId: number;
  componentId: number;
}

export interface LinkTable {
  byComponentId: Map<number, SourceLink>;
  byName: Map<string, SourceLink>;
  /** Root declarations with no box — a macro instance whose internals the
   *  canvas never draws, or a declaration the compiler dropped. */
  unlinked: Declaration[];
}

/**
 * The `file_id` of the root path, or null when the analysis does not name it.
 *
 * Null must stay null in every caller: the truth-table pre-flight reads a null
 * as "unknown, do not gate" and a 0 as "no input bits", and a wrong 0 there
 * silently disables the only defence against an enumeration that cannot be
 * stopped once started.
 */
export function rootFileId(files: readonly AnalyzeFile[], rootPath: string): number | null {
  const entry = files.find((f) => f.path === rootPath);
  return entry ? entry.file_id : null;
}

/** Symbols of the root file only, in analyze order, with a known kind and a
 *  non-empty name — an anonymous instance has neither. */
export function rootDeclarations(
  symbols: readonly AnalyzeSymbol[],
  rootId: number | null,
): Declaration[] {
  if (rootId === null) return [];
  const out: Declaration[] = [];
  for (const s of symbols) {
    if (s.file_id !== rootId) continue;
    if (!s.name) continue;
    if (!(s.kind in TOPOLOGY_KIND_OF)) continue;
    out.push({ name: s.name, kind: s.kind, fileId: s.file_id, range: s.range });
  }
  return out;
}

/** The exact call the island makes after each successful analysis, exported so
 *  it has a test rather than living inside an island a test cannot import. */
export function declsFor(analysis: Analysis | null, rootPath: string): Declaration[] {
  if (!analysis) return [];
  return rootDeclarations(analysis.symbols, rootFileId(analysis.files, rootPath));
}

/** `/playground/<name>` for the root tab, the shape analyze reports back. */
export function rootPathFor(rootName: string): string {
  return `${PLAYGROUND_DIR}/${rootName}`;
}

/**
 * Join declarations to boxes on (name, kind).
 *
 * Only top-level boxes take part: a box with a non-empty `origin` came from
 * inside a macro, and the reader never wrote it. A duplicate name means the
 * source is already broken, so the first declaration wins rather than the join
 * inventing a rule.
 */
export function linkLayout(decls: readonly Declaration[], layout: LayoutLike): LinkTable {
  const byComponentId = new Map<number, SourceLink>();
  const byName = new Map<string, SourceLink>();
  const unlinked: Declaration[] = [];

  const boxes = layout.components.filter((c) => c.origin.length === 0);

  for (const decl of decls) {
    if (byName.has(decl.name)) continue; // first wins
    const wanted = TOPOLOGY_KIND_OF[decl.kind];
    const box = boxes.find(
      (c) =>
        c.name === decl.name &&
        (wanted === 'subcircuit'
          ? c.kind.tag === 'subcircuit'
          : c.kind.tag === 'primitive' && c.kind.kind === wanted),
    );
    if (!box) {
      unlinked.push(decl);
      continue;
    }
    const link: SourceLink = {
      name: decl.name,
      kind: decl.kind,
      fileId: decl.fileId,
      componentId: box.id,
    };
    byName.set(decl.name, link);
    // A box can only draw one declaration, so this cannot collide.
    byComponentId.set(box.id, link);
  }
  return { byComponentId, byName, unlinked };
}

/**
 * The declaration under a cursor.
 *
 * Symbol columns are 1-based byte columns, so they are converted before the
 * containment test. Ranges are end-exclusive. When no range contains the
 * column — a cursor sitting on the `input ` keyword of `input a, b`, whose
 * symbols carry per-name spans rather than one declaration span — the leftmost
 * declaration starting on that line is used, so the common case still resolves.
 */
export function declarationAt(
  decls: readonly Declaration[],
  line: number,
  col: number,
  lineText: string,
): Declaration | null {
  let onLine: Declaration | null = null;
  for (const d of decls) {
    if (d.range.start_line > line || d.range.end_line < line) continue;
    if (d.range.start_line === line) {
      const startCol = byteColToUtf16(lineText, d.range.start_col);
      if (onLine === null || startCol < byteColToUtf16(lineText, onLine.range.start_col)) {
        onLine = d;
      }
    }
    const from = d.range.start_line === line ? byteColToUtf16(lineText, d.range.start_col) : -Infinity;
    const to = d.range.end_line === line ? byteColToUtf16(lineText, d.range.end_col) : Infinity;
    if (col >= from && col < to) return d;
  }
  return onLine;
}

/** Truth-table headers are `name` or `name[W]` when the width is above 1.
 *  Strip the suffix to get the join key. */
export function headerSymbolName(header: string): string {
  const m = header.match(/^(.*)\[\d+\]$/);
  return m ? m[1] : header;
}
