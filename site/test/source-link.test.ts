// The join between the reader's source and the drawn circuit. It runs against
// a committed artifact through the pinned renderer's own layout, so it is the
// real grid rather than a hand-built stand-in — including the synthetic id a
// collapsed macro box carries, which the topology alone does not have.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ComponentKind, decodeFullTopology } from 'circ-renderer';
import { buildLayout } from 'circ-renderer';
import {
  TOPOLOGY_KIND_OF,
  declarationAt,
  declsFor,
  headerSymbolName,
  linkLayout,
  rootDeclarations,
  rootFileId,
  rootPathFor,
  type Declaration,
  type LayoutLike,
} from '../src/scripts/source-link.ts';
import { callOp, instantiateLibcirc, type LibcircExports } from '../src/scripts/libcirc-abi.ts';
import { requestFor, splitFiles, PLAYGROUND_DIR } from '../src/utils/split-files.ts';
import type { Analysis } from '../src/scripts/circ-diagnostics.ts';

const range = (sl: number, sc: number, el = sl, ec = sc) => ({
  start_line: sl,
  start_col: sc,
  end_line: el,
  end_col: ec,
});

const decl = (name: string, kind: Declaration['kind'], r = range(1, 1, 1, 2)): Declaration => ({
  name,
  kind,
  fileId: 0,
  range: r,
});

describe('the kind table', () => {
  test('matches the renderer enum it stands in for', () => {
    expect(TOPOLOGY_KIND_OF.input).toBe(ComponentKind.InputPin);
    expect(TOPOLOGY_KIND_OF.not).toBe(ComponentKind.NotGate);
    expect(TOPOLOGY_KIND_OF.and).toBe(ComponentKind.AndGate);
    expect(TOPOLOGY_KIND_OF.led).toBe(ComponentKind.Led);
    expect(TOPOLOGY_KIND_OF.output).toBe(ComponentKind.OutputPin);
    expect(TOPOLOGY_KIND_OF.rom).toBe(ComponentKind.Rom);
    expect(TOPOLOGY_KIND_OF.ram).toBe(ComponentKind.Ram);
    expect(TOPOLOGY_KIND_OF.instance).toBe('subcircuit');
  });
});

describe('rootFileId', () => {
  const files = [
    { file_id: 0, path: '/playground/half_adder.circ' },
    { file_id: 1, path: '/playground/root.circ' },
    { file_id: 2, path: '<builtin>/xor.circ' },
  ];

  test('finds the root and returns null when it is absent', () => {
    expect(rootFileId(files, '/playground/root.circ')).toBe(1);
    expect(rootFileId(files, '/playground/half_adder.circ')).toBe(0);
    // Null, never 0: a 0 here silently disables the truth-table pre-flight.
    expect(rootFileId(files, '/playground/gone.circ')).toBeNull();
    expect(rootFileId([], '/playground/root.circ')).toBeNull();
  });

  test('rootPathFor builds the shape analyze reports back', () => {
    expect(rootPathFor('root.circ')).toBe(`${PLAYGROUND_DIR}/root.circ`);
  });
});

describe('rootDeclarations', () => {
  const symbols = [
    { file_id: 0, name: 'a', kind: 'input' as const, width: 1, range: range(1, 7, 1, 8) },
    { file_id: 0, name: 'g', kind: 'and' as const, width: 1, range: range(2, 1, 2, 16) },
    { file_id: 1, name: 'other', kind: 'input' as const, width: 1, range: range(1, 1, 1, 2) },
    { file_id: 0, name: '', kind: 'and' as const, width: 1, range: range(3, 1, 3, 2) },
  ];

  test('keeps the root file only, named only, in analyze order', () => {
    const out = rootDeclarations(symbols, 0);
    expect(out.map((d) => d.name)).toEqual(['a', 'g']);
    // A sibling file's symbols are excluded, not resolved.
    expect(out.some((d) => d.fileId === 1)).toBe(false);
  });

  test('a null root id yields nothing', () => {
    expect(rootDeclarations(symbols, null)).toEqual([]);
  });

  test('declsFor is the island call, and tolerates a null analysis', () => {
    const analysis = {
      files: [{ file_id: 0, path: '/playground/main.circ' }],
      diagnostics: [],
      symbols,
      references: [],
    } as unknown as Analysis;
    expect(declsFor(analysis, '/playground/main.circ').map((d) => d.name)).toEqual(['a', 'g']);
    expect(declsFor(null, '/playground/main.circ')).toEqual([]);
    // A root the analysis does not name resolves to nothing rather than to file 0.
    expect(declsFor(analysis, '/playground/nope.circ')).toEqual([]);
  });
});

describe('linkLayout against the committed half-adder artifact', () => {
  const wasm = readFileSync(resolve(import.meta.dir, '..', 'public', 'wasm', 'half-adder.wasm'));

  async function layout(): Promise<LayoutLike> {
    const mod = await WebAssembly.compile(wasm);
    const section = WebAssembly.Module.customSections(mod, 'circ.topology.v0.full')[0];
    const topo = decodeFullTopology(new Uint8Array(section));
    return buildLayout(topo, {}) as never;
  }

  test('joins every top-level declaration to its box', async () => {
    const grid = await layout();
    // The shipped half-adder: two inputs, an AND, two outputs and one macro.
    const decls = [
      decl('a', 'input'),
      decl('b', 'input'),
      decl('c', 'and'),
      decl('s', 'instance'),
      decl('sum', 'output'),
      decl('carry', 'output'),
    ];
    const table = linkLayout(decls, grid);
    expect(table.unlinked).toEqual([]);
    expect(table.byName.size).toBe(6);
    expect(table.byComponentId.size).toBe(6);

    // The macro instance resolves to the synthetic box id, which exists only
    // in the layout — the case a topology-only lookup gets wrong.
    const macro = grid.components.find((c) => c.kind.tag === 'subcircuit')!;
    expect(table.byName.get('s')!.componentId).toBe(macro.id);
    expect(table.byComponentId.get(macro.id)!.name).toBe('s');

    // Every mapping is bidirectional.
    for (const [id, link] of table.byComponentId) {
      expect(table.byName.get(link.name)!.componentId).toBe(id);
    }
  });

  test('a name that is not drawn comes back unlinked', async () => {
    const grid = await layout();
    const table = linkLayout([decl('nowhere', 'and')], grid);
    expect(table.byName.size).toBe(0);
    expect(table.unlinked.map((d) => d.name)).toEqual(['nowhere']);
  });

  test('the kind must match, not only the name', async () => {
    const grid = await layout();
    // 'c' is drawn as an AND; asking for an output of that name finds nothing.
    const table = linkLayout([decl('c', 'output')], grid);
    expect(table.unlinked.map((d) => d.name)).toEqual(['c']);
  });

  test('boxes from inside a macro never take part', async () => {
    const grid = await layout();
    const inner: LayoutLike = {
      components: [
        { id: 99, name: 'hidden', origin: ['s'], kind: { tag: 'primitive', kind: 2 } },
      ],
    };
    expect(linkLayout([decl('hidden', 'and')], inner).unlinked).toHaveLength(1);
    // …and the real grid's own boxes are all top-level, so nothing is dropped.
    expect(grid.components.every((c) => c.origin.length === 0)).toBe(true);
  });

  test('a duplicate name resolves once, first declaration winning', async () => {
    const grid = await layout();
    const table = linkLayout([decl('c', 'and'), decl('c', 'and')], grid);
    expect(table.byName.size).toBe(1);
    expect(table.unlinked).toEqual([]);
  });
});

describe('declarationAt', () => {
  // `input a, b` carries a span per name; every other kind spans its whole
  // declaration. Both shapes have to resolve.
  const decls = [
    decl('a', 'input', range(1, 7, 1, 8)),
    decl('b', 'input', range(1, 10, 1, 11)),
    decl('g', 'and', range(2, 1, 2, 16)),
    decl('out', 'output', range(3, 1, 3, 21)),
  ];

  test('resolves a cursor inside a span', () => {
    expect(declarationAt(decls, 1, 7, 'input a, b')!.name).toBe('a');
    expect(declarationAt(decls, 1, 10, 'input a, b')!.name).toBe('b');
    expect(declarationAt(decls, 2, 5, 'and g(a=a, b=b)')!.name).toBe('g');
    expect(declarationAt(decls, 3, 1, 'output out(in=g.out)')!.name).toBe('out');
  });

  test('a span is end-exclusive', () => {
    // Column 8 is one past `a`, which is where `,` sits.
    const at8 = declarationAt(decls, 1, 8, 'input a, b');
    expect(at8!.name).toBe('a'); // falls back to the leftmost on the line
  });

  test('a cursor on the keyword falls back to the leftmost declaration', () => {
    // `input a, b`: column 2 is inside the keyword, in no symbol's span.
    expect(declarationAt(decls, 1, 2, 'input a, b')!.name).toBe('a');
  });

  test('a line with no declaration resolves to nothing', () => {
    expect(declarationAt(decls, 9, 1, '')).toBeNull();
    expect(declarationAt([], 1, 1, 'input a')).toBeNull();
  });

  test('byte columns are converted before the test', () => {
    // `// éé` is 5 characters but 7 bytes; a symbol at byte column 8 is at
    // UTF-16 column 6.
    const multi = [decl('x', 'and', range(1, 8, 1, 9))];
    expect(declarationAt(multi, 1, 6, '// éé x')!.name).toBe('x');
  });
});

describe('headerSymbolName', () => {
  test('strips a width suffix and leaves a plain name alone', () => {
    expect(headerSymbolName('a')).toBe('a');
    expect(headerSymbolName('a[4]')).toBe('a');
    expect(headerSymbolName('sum[16]')).toBe('sum');
    // A name that merely contains brackets is not a width suffix.
    expect(headerSymbolName('a[b]')).toBe('a[b]');
    expect(headerSymbolName('')).toBe('');
  });
});

const skip = process.env.SKIP_LIBCIRC_TEST === '1';
let cached: Promise<LibcircExports> | null = null;
const lib = () =>
  (cached ??= instantiateLibcirc(
    readFileSync(resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.wasm')),
  ));

describe.skipIf(skip)('end to end through the committed module', () => {
  test('a source analyses, compiles, and every declaration finds its box', async () => {
    const w = await lib();
    const src = 'input a, b\nand c(a=a, b=b)\noutput out(in=c.out)\n';
    const files = splitFiles(src);

    const an = callOp(w, 'analyze', requestFor(files));
    expect(an.status).toBe(0);
    const analysis = JSON.parse(new TextDecoder().decode(an.bytes)) as Analysis;
    const decls = declsFor(analysis, rootPathFor(files[files.length - 1].name));
    expect(decls.map((d) => d.name).sort()).toEqual(['a', 'b', 'c', 'out']);

    const out = callOp(w, 'compile', requestFor(files));
    expect(out.status).toBe(0);
    const mod = await WebAssembly.compile(out.bytes);
    const section = WebAssembly.Module.customSections(mod, 'circ.topology.v0.full')[0];
    const grid = buildLayout(decodeFullTopology(new Uint8Array(section)), {}) as never as LayoutLike;

    const table = linkLayout(decls, grid);
    // Everything the reader wrote is on screen and reachable from the source.
    expect(table.unlinked).toEqual([]);
    expect([...table.byName.keys()].sort()).toEqual(['a', 'b', 'c', 'out']);

    // And the cursor resolution agrees with the join.
    const lines = src.split('\n');
    const atAnd = declarationAt(decls, 2, 5, lines[1])!;
    expect(table.byName.get(atAnd.name)!.kind).toBe('and');
  });
});
