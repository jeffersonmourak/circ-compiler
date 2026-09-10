// The offset mapping: 1-based byte columns and file-local line numbers on one
// side, absolute UTF-16 offsets into the combined document on the other. The
// wasm-driven cases run the real compiler against the committed module, so the
// ranges under test are the ones a reader will actually see.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  docLine,
  fileNameFor,
  indexDoc,
  mapDiagnostics,
  offsetAt,
  rangeToSpan,
  mapPerTab,
  toLintDiagnostics,
  type Analysis,
  type AnalyzeRange,
} from '../src/scripts/circ-diagnostics.ts';
import { byteColToUtf16, caretOffset } from '../src/utils/columns.ts';
import { splitFiles, requestFor, PLAYGROUND_DIR } from '../src/utils/split-files.ts';
import { callOp, instantiateLibcirc, type LibcircExports } from '../src/scripts/libcirc-abi.ts';
import { tour } from '../src/content/tour.ts';
import { examples } from '../src/content/examples.ts';
import { fromSource } from '../src/scripts/file-tabs.ts';

const range = (sl: number, sc: number, el = sl, ec = sc): AnalyzeRange => ({
  start_line: sl,
  start_col: sc,
  end_line: el,
  end_col: ec,
});

const analysisOf = (paths: string[], diagnostics: Analysis['diagnostics'] = []): Analysis => ({
  files: paths.map((path, file_id) => ({ file_id, path })),
  diagnostics,
  symbols: [],
  references: [],
});

const diag = (file_id: number, r: AnalyzeRange, over: Partial<Analysis['diagnostics'][number]> = {}) => ({
  file_id,
  severity: 'error' as const,
  code: 'E001',
  range: r,
  message: 'undeclared name',
  ...over,
});

describe('circ diagnostics mapping', () => {
  test('offsetAt converts byte columns', () => {
    // The same inputs columns.test.ts pins, now as absolute document offsets.
    const index = indexDoc('abc\néé x\n😀x');
    expect(offsetAt(index, 0, 1)).toBe(0);
    expect(offsetAt(index, 0, 3)).toBe(2);
    // 'éé x': é is two bytes, so byte column 5 is the 3rd UTF-16 unit.
    expect(offsetAt(index, 1, 5) - index.starts[1]).toBe(2);
    // '😀x': the emoji is four bytes and two UTF-16 units.
    expect(offsetAt(index, 2, 5) - index.starts[2]).toBe(2);
    // Past the end of the line clamps to the line's end, never past it.
    expect(offsetAt(index, 0, 99) - index.starts[0]).toBe(3);
    expect(offsetAt(index, 99, 1)).toBeLessThanOrEqual(index.length);
  });

  test('docLine crosses file markers', () => {
    const files = splitFiles(tour[5].source);
    expect(files.map((f) => f.name)).toEqual(['half_adder.circ', 'root.circ']);
    expect(docLine(files, 'half_adder.circ', 1)).toBe(files[0].startLine);
    expect(docLine(files, 'root.circ', 1)).toBe(files[1].startLine);
    // The second file starts strictly after the first — the shift a naive
    // mapper drops on the floor.
    expect(files[1].startLine).toBeGreaterThan(files[0].startLine);
    expect(docLine(files, 'nope.circ', 1)).toBeNull();
  });

  test('builtin files have no span but still have a row', () => {
    const doc = 'input a\nnot n(in=a)\n';
    const files = splitFiles(doc);
    const analysis = analysisOf(
      [`${PLAYGROUND_DIR}/main.circ`, '<builtin>/xor.circ'],
      [diag(1, range(2, 1, 2, 4), { message: 'inside a builtin' })],
    );
    expect(fileNameFor(analysis, 0)).toBe('main.circ');
    expect(fileNameFor(analysis, 1)).toBeNull();

    const mapped = mapDiagnostics(doc, files, analysis);
    expect(mapped).toHaveLength(1);
    expect(mapped[0].from).toBeNull();
    expect(mapped[0].to).toBeNull();
    expect(mapped[0].docLine).toBeNull();
    expect(mapped[0].fileName).toBe('<builtin>/xor.circ');
    expect(mapped[0].line).toBe(2);
    expect(mapped[0].column).toBe(1);
    // Dropped only here, so the visible list stays total.
    expect(toLintDiagnostics(mapped)).toEqual([]);
  });

  test('spans clamp and never invert', () => {
    const doc = 'input a\nnot n(in=a)\n';
    const files = splitFiles(doc);
    const analysis = analysisOf([`${PLAYGROUND_DIR}/main.circ`]);
    const index = indexDoc(doc);
    const spanFor = (r: AnalyzeRange) => rangeToSpan(index, files, analysis, 0, r)!;

    for (const r of [
      range(99, 1, 99, 4), // past EOF
      range(1, 1, 1, 999), // past EOL
      range(2, 8, 2, 2), // inverted
      range(1, 1, 1, 1), // empty
    ]) {
      const span = spanFor(r);
      expect(span.from).toBeGreaterThanOrEqual(0);
      expect(span.to).toBeGreaterThanOrEqual(span.from);
      expect(span.to).toBeLessThanOrEqual(doc.length);
    }
    // An empty range widens by one so the squiggle is visible.
    const empty = spanFor(range(1, 1, 1, 1));
    expect(empty.to).toBe(empty.from + 1);
    // …but not past the end of an empty document.
    const emptyDoc = indexDoc('');
    const atEnd = rangeToSpan(emptyDoc, splitFiles(''), analysis, 0, range(1, 1, 1, 1))!;
    expect(atEnd.from).toBe(0);
    expect(atEnd.to).toBe(0);
  });

  test('a surrogate pair is never split', () => {
    const doc = '😀';
    const index = indexDoc(doc);
    const analysis = analysisOf([`${PLAYGROUND_DIR}/main.circ`]);
    const span = rangeToSpan(index, splitFiles(doc), analysis, 0, range(1, 1, 1, 1))!;
    expect(span.from).toBe(0);
    expect(span.to).toBe(2);
    expect(doc.slice(span.from, span.to)).toBe('😀');
  });

  test('toLintDiagnostics matches the lint Diagnostic shape', () => {
    const doc = 'input a\nnot n(in=a)\n';
    const analysis = analysisOf(
      [`${PLAYGROUND_DIR}/main.circ`],
      [diag(0, range(2, 1, 2, 4)), diag(0, range(1, 1, 1, 6), { severity: 'warning', code: 'W001' })],
    );
    const lint = toLintDiagnostics(mapDiagnostics(doc, splitFiles(doc), analysis));
    expect(lint).toHaveLength(2);
    for (const d of lint) {
      expect(Object.keys(d).sort()).toEqual(['from', 'message', 'severity', 'source', 'to']);
      expect(['error', 'warning']).toContain(d.severity);
    }
    expect(lint[1].source).toBe('W001');
  });

  test('list rows carry the compiler\'s own file-local position', () => {
    const doc = tour[5].source;
    const files = splitFiles(doc);
    const analysis = analysisOf(
      [`${PLAYGROUND_DIR}/half_adder.circ`, `${PLAYGROUND_DIR}/root.circ`],
      [diag(0, range(1, 1, 1, 6)), diag(1, range(1, 1, 1, 6))],
    );
    const mapped = mapDiagnostics(doc, files, analysis);
    // Unshifted by startLine: the position the compiler reported, file-locally.
    expect(mapped[0].line).toBe(1);
    expect(mapped[1].line).toBe(1);
    expect(mapped[0].fileName).toBe('half_adder.circ');
    expect(mapped[1].fileName).toBe('root.circ');
    expect(mapped[0].column).toBe(1);
  });

  test('docLine reproduces today\'s combined line, and the jump does not regress', () => {
    const doc = tour[5].source;
    const files = splitFiles(doc);
    const analysis = analysisOf(
      [`${PLAYGROUND_DIR}/half_adder.circ`, `${PLAYGROUND_DIR}/root.circ`],
      [diag(0, range(2, 1, 2, 6)), diag(1, range(2, 1, 2, 6))],
    );
    const mapped = mapDiagnostics(doc, files, analysis);
    mapped.forEach((m, i) => {
      // The old locate(), recomputed here: file.startLine + start_line - 1.
      const file = files[analysis.diagnostics[i].file_id];
      const line0 = file.startLine + analysis.diagnostics[i].range.start_line - 1;
      const lineText = doc.split('\n')[line0] ?? '';
      const col = byteColToUtf16(lineText, analysis.diagnostics[i].range.start_col);
      expect(m.docLine).toBe(line0);
      expect(m.column).toBe(col);
      // …and the click target is exactly where it lands today.
      expect(m.from).toBe(caretOffset(doc, line0, col));
    });
  });

  test('the rendered row string is the file-local label', () => {
    // Pins the exact text the list shows, which deliberately replaced the old
    // combined-document `<line>:<col>` label carrying no filename.
    const doc = tour[5].source;
    const files = splitFiles(doc);
    const analysis = analysisOf(
      [`${PLAYGROUND_DIR}/half_adder.circ`, `${PLAYGROUND_DIR}/root.circ`],
      [diag(1, range(1, 1, 1, 6), { code: 'E004', message: "required input 'in' is unconnected" })],
    );
    const m = mapDiagnostics(doc, files, analysis)[0];
    const label = `${m.fileName}:${m.line}:${m.column} ${m.code} ${m.message}`;
    expect(label).toBe("root.circ:1:1 E004 required input 'in' is unconnected");
  });

  test('a status-1 compile body maps like the same diagnostics from analyze', () => {
    const doc = 'input a\nnot n(in=b)\noutput o(in=n.out)\n';
    const files = splitFiles(doc);
    const diagnostics = [diag(0, range(2, 1, 2, 12))];
    // The compile reply carries its own files[]; the shapes are otherwise equal.
    const fromAnalyze = analysisOf([`${PLAYGROUND_DIR}/main.circ`], diagnostics);
    const fromCompile: Analysis = {
      files: [{ file_id: 0, path: `${PLAYGROUND_DIR}/main.circ` }],
      diagnostics,
      symbols: [],
      references: [],
    };
    expect(mapDiagnostics(doc, files, fromCompile)).toEqual(mapDiagnostics(doc, files, fromAnalyze));
    // A source that analyzes clean but fails to compile still yields rows.
    const clean = analysisOf([`${PLAYGROUND_DIR}/main.circ`], []);
    expect(mapDiagnostics(doc, files, clean)).toEqual([]);
    expect(mapDiagnostics(doc, files, fromCompile).length).toBeGreaterThan(0);
  });
});

const skip = process.env.SKIP_LIBCIRC_TEST === '1';
const wasmPath = resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.wasm');
let cached: Promise<LibcircExports> | null = null;
const lib = () => (cached ??= instantiateLibcirc(readFileSync(wasmPath)));
const decode = (b: Uint8Array) => new TextDecoder().decode(b);

/** The substring a 1-based byte range names, computed independently of the
 *  module under test. */
function sliceByBytes(doc: string, files: ReturnType<typeof splitFiles>, fileIndex: number, r: AnalyzeRange): string {
  const lines = doc.split('\n');
  const line0 = files[fileIndex].startLine + r.start_line - 1;
  const line = lines[line0] ?? '';
  const from = byteColToUtf16(line, r.start_col) - 1;
  const to = byteColToUtf16(line, r.end_col) - 1;
  return line.slice(from, to);
}

describe.skipIf(skip)('circ diagnostics against the committed module', () => {
  test('maps an analyze diagnostic onto the exact source text', async () => {
    const w = await lib();
    // The phase's headline check. E001 is raised for an unresolved component
    // TYPE and carries the whole declaration's span, so the squiggle covers a
    // declaration, not a bare identifier — pinned here rather than assumed.
    const src = 'input b\nmystery n(in=b)\noutput o(in=n.out)\n';
    const files = splitFiles(src);
    const out = callOp(w, 'analyze', requestFor(files));
    expect(out.status).toBe(0);
    const analysis = JSON.parse(decode(out.bytes)) as Analysis;
    const errors = analysis.diagnostics.filter((d) => d.severity === 'error');
    expect(errors.length).toBeGreaterThan(0);

    const mapped = mapDiagnostics(src, files, analysis).filter((m) => m.severity === 'error');
    expect(mapped.length).toBe(errors.length);
    expect(mapped[0].from).not.toBeNull();
    expect(src.slice(mapped[0].from!, mapped[0].to!)).toBe(sliceByBytes(src, files, 0, errors[0].range));
    expect(errors[0].code).toBe('E001');
  });

  test('the headline example reports E004 over the whole declaration', async () => {
    const w = await lib();
    // Resolves the plan's spike. `DOCS/PLANS_PROMPT.md` promised a squiggle
    // "under exactly `a`" from `E001`; the compiler emits no per-identifier
    // spans for validator codes, so what it actually reports is pinned here.
    const src = 'input b\nnot n(in=a)\noutput o(in=n.out)\n';
    const files = splitFiles(src);
    const out = callOp(w, 'analyze', requestFor(files));
    expect(out.status).toBe(0);
    const analysis = JSON.parse(decode(out.bytes)) as Analysis;
    const mapped = mapDiagnostics(src, files, analysis);

    const error = mapped.find((m) => m.severity === 'error')!;
    expect(error.code).toBe('E004');
    expect(src.slice(error.from!, error.to!)).toBe('not n(in=a)');

    // The warning on the unused input DOES span exactly its identifier.
    const warning = mapped.find((m) => m.severity === 'warning')!;
    expect(warning.code).toBe('W001');
    expect(src.slice(warning.from!, warning.to!)).toBe('b');
  });

  test('maps a diagnostic in the first file of a two-file source', async () => {
    const w = await lib();
    // tour step 6's two files, with the error injected into the FIRST one.
    const src = tour[5].source.replace('input a, b', 'input a, b\nnot broken(in=nowhere)');
    const files = splitFiles(src);
    expect(files).toHaveLength(2);
    const out = callOp(w, 'analyze', requestFor(files));
    expect(out.status).toBe(0);
    const analysis = JSON.parse(decode(out.bytes)) as Analysis;
    const mapped = mapDiagnostics(src, files, analysis).filter((m) => m.severity === 'error' && m.from !== null);
    expect(mapped.length).toBeGreaterThan(0);

    const secondFileOffset = caretOffset(src, files[1].startLine, 1);
    // The assertion a mapper that forgets SplitFile.startLine fails.
    expect(mapped[0].from!).toBeLessThan(secondFileOffset);
    expect(mapped[0].fileName).toBe('half_adder.circ');
  });

  test('multi-byte padding does not shift the mapping', async () => {
    const w = await lib();
    const plain = 'input b\nmystery n(in=b)\noutput o(in=n.out)\n';
    const padded = `// éé 😀\n${plain}`;
    const results = await Promise.all(
      [plain, padded].map(async (src) => {
        const files = splitFiles(src);
        const out = callOp(w, 'analyze', requestFor(files));
        const analysis = JSON.parse(decode(out.bytes)) as Analysis;
        const mapped = mapDiagnostics(src, files, analysis).filter((m) => m.severity === 'error');
        return src.slice(mapped[0].from!, mapped[0].to!);
      }),
    );
    expect(results[0]).toBe(results[1]);
    expect(results[0]).toContain('mystery');
  });
});

describe.skipIf(skip)('per-tab mapping against the committed module', () => {
  test('a two-tab project lists every diagnostic exactly once', async () => {
    const w = await lib();
    // Errors in BOTH files, so each tab places its own and neither repeats the
    // other's — the N-times-on-N-tabs bug the placeless pass exists to avoid.
    const src = tour[5].source
      .replace('input a, b', 'input a, b\nnot broken(in=nowhere)')
      .replace('output cout', 'not alsobroken(in=missing)\noutput cout');
    const files = fromSource(src).files;
    expect(files).toHaveLength(2);

    const out = callOp(w, 'analyze', requestFor(files));
    expect(out.status).toBe(0);
    const analysis = JSON.parse(decode(out.bytes)) as Analysis;
    expect(analysis.diagnostics.length).toBeGreaterThan(1);

    const { perTab, rows } = mapPerTab(files, analysis);
    // The flat list is total and duplicate-free.
    expect(rows).toHaveLength(analysis.diagnostics.length);
    // Every row is placed on the tab whose file the compiler blamed.
    for (const row of rows) {
      if (row.tab === null) continue;
      expect(files[row.tab].name).toBe(row.fileName);
      expect(row.from).not.toBeNull();
      expect(files[row.tab].body.slice(row.from!, row.to!).length).toBeGreaterThan(0);
    }
    // Each tab's own editor list holds only that tab's diagnostics.
    perTab.forEach((mapped, i) => {
      for (const d of toLintDiagnostics(mapped)) {
        expect(d.to).toBeLessThanOrEqual(files[i].body.length);
      }
    });
    expect(toLintDiagnostics(perTab[0]).length + toLintDiagnostics(perTab[1]).length).toBe(
      rows.filter((r) => r.tab !== null).length,
    );
  });

  test('no diagnostic is blamed on a builtin source for the shipped content', async () => {
    // TODO(phase2)-C: Phase 0 resolves implicit builtins on the compile route,
    // so `<builtin>/…` entries appear in analysis.files. This asserts none of
    // them ever carries a DIAGNOSTIC for the 21 shipped sources, which is what
    // would put an unclickable, confusing row in the reader's list.
    const w = await lib();
    let builtinDiagnostics = 0;
    for (const src of [...examples.map((e) => e.source), ...tour.map((t) => t.source)]) {
      const out = callOp(w, 'analyze', requestFor(fromSource(src).files));
      const analysis = JSON.parse(decode(out.bytes)) as Analysis;
      for (const d of analysis.diagnostics) {
        const path = analysis.files.find((f) => f.file_id === d.file_id)?.path ?? '';
        if (path.startsWith('<builtin>/')) builtinDiagnostics += 1;
      }
    }
    expect(builtinDiagnostics).toBe(0);
  });
});
