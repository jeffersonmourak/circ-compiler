import { describe, expect, test } from 'bun:test';
import {
  splitFiles,
  rootOf,
  requestFor,
  joinFiles,
  isFileName,
  joinConflicts,
  type NamedFile,
} from '../src/utils/split-files.ts';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';

describe('splitFiles', () => {
  test('single source becomes main.circ at line 0', () => {
    const files = splitFiles('input a\n');
    expect(files).toEqual([{ name: 'main.circ', body: 'input a\n', startLine: 0 }]);
    expect(rootOf(files).name).toBe('main.circ');
  });

  test('markers split files and the last is root', () => {
    const files = splitFiles(tour[5].source);
    expect(files.map((f) => f.name)).toEqual(['half_adder.circ', 'root.circ']);
    expect(files[0].startLine).toBe(1);
    expect(files[1].startLine).toBe(9);
    expect(files[0].body.startsWith('import xor "<builtin>/xor.circ"')).toBe(true);
    expect(files[1].body.startsWith('import half_adder "half_adder.circ"')).toBe(true);
    expect(rootOf(files).name).toBe('root.circ');
    const req = requestFor(files, { color: 'never' });
    expect(req.root).toBe('/playground/root.circ');
    expect(Object.keys(req.files)).toEqual(['/playground/half_adder.circ', '/playground/root.circ']);
    expect(req.options).toEqual({ color: 'never' });
  });

  test('a marker after only blank lines stays a comment of main.circ', () => {
    const files = splitFiles('\n// a.circ\ninput a\n');
    expect(files.length).toBe(1);
    expect(files[0].name).toBe('main.circ');
    expect(files[0].startLine).toBe(0);
    expect(files[0].body).toBe('\n// a.circ\ninput a\n');
  });
});

const sources = [...examples.map((e) => e.source), ...tour.map((t) => t.source)];
const named = (name: string, body: string): NamedFile => ({ name, body });

describe('joinFiles', () => {
  test('round-trips every example and tour source byte for byte', () => {
    expect(sources).toHaveLength(22);
    for (const source of sources) expect(joinFiles(splitFiles(source))).toBe(source);
  });

  test('is a left inverse of splitFiles', () => {
    const cases: NamedFile[][] = [
      [named('main.circ', 'input a\n')],
      [named('half_adder.circ', 'input a, b\n')],
      [named('a.circ', 'input a\n'), named('b.circ', 'input b\n'), named('c.circ', 'input c\n')],
      // A marker-looking comment as the FIRST body line round-trips: the owning
      // file's marker is emitted before it, so the splitter sees an empty body.
      [named('a.circ', '// notes.circ\ninput a\n'), named('b.circ', 'input b\n')],
      // A blank LAST file is fine.
      [named('a.circ', 'input a\n'), named('b.circ', '')],
    ];
    for (const files of cases) {
      expect(joinConflicts(files)).toEqual([]);
      const back = splitFiles(joinFiles(files));
      expect(back.map((f) => f.name)).toEqual(files.map((f) => f.name));
      expect(back.map((f) => f.body)).toEqual(files.map((f) => f.body));
    }
  });

  test('drops a redundant leading main.circ marker', () => {
    expect(joinFiles(splitFiles('// main.circ\ninput a\n'))).toBe('input a\n');
  });

  test('keeps a leading main.circ marker that shields a marker line', () => {
    // Dropping it would promote line 1 to the file marker.
    const source = '// main.circ\n// a.circ\ninput a\n';
    expect(joinFiles(splitFiles(source))).toBe(source);
  });

  test('normalises a trailing marker line', () => {
    // That file's body-line list is empty, so one newline appears.
    expect(joinFiles(splitFiles('input a\n// b.circ'))).toBe('input a\n// b.circ\n');
    // With a body line after the marker it is byte-identical.
    const withBody = 'input a\n// b.circ\ninput b\n';
    expect(joinFiles(splitFiles(withBody))).toBe(withBody);
  });

  test('normalises a non-canonical marker', () => {
    expect(joinFiles(splitFiles('input a\n//   b.circ\ninput b\n'))).toBe('input a\n// b.circ\ninput b\n');
    expect(joinFiles(splitFiles('input a\n// b.circ \ninput b\n'))).toBe('input a\n// b.circ\ninput b\n');
    const canonical = 'input a\n// b.circ\ninput b\n';
    expect(joinFiles(splitFiles(canonical))).toBe(canonical);
  });
});

describe('joinConflicts', () => {
  test('flags a blank non-root body', () => {
    const files = [named('main.circ', ''), named('a.circ', 'input a\n')];
    expect(joinConflicts(files)).toEqual([{ index: 0, reason: 'blank-body' }]);
    // …and the collapse it predicts really happens.
    expect(splitFiles(joinFiles(files))).toHaveLength(1);
  });

  test('flags a marker line after content', () => {
    expect(joinConflicts([named('a.circ', 'input a\n// b.circ\n')])).toEqual([
      { index: 0, reason: 'marker-in-body' },
    ]);
    // A marker line BEFORE any content is not a conflict.
    expect(joinConflicts([named('a.circ', '// b.circ\ninput a\n')])).toEqual([]);
  });

  test('flags an illegal file name', () => {
    const files = [named('foo', 'input a\n'), named('b.circ', 'x\n')];
    expect(joinConflicts(files)).toEqual([{ index: 0, reason: 'illegal-name' }]);
    // `// foo` is not a marker, so the name is LOST: the file comes back as
    // the invented `main.circ` with its own marker line stranded in the body.
    // (The phase plan predicted a merge to one file; the count is preserved
    // here and the identity is not — recorded in DOCS/STATUS.md.)
    const back = splitFiles(joinFiles(files));
    expect(back[0].name).toBe('main.circ');
    expect(back[0].body).toBe('// foo\ninput a\n');
    expect(back.map((f) => f.name)).not.toEqual(files.map((f) => f.name));
  });

  test('flags a duplicate file name', () => {
    const files = [named('a.circ', 'input a\n'), named('a.circ', 'input b\n')];
    expect(joinConflicts(files)).toEqual([{ index: 1, reason: 'duplicate-name' }]);
    // requestFor keys by name, so one body is silently dropped.
    expect(Object.keys(requestFor(files).files)).toHaveLength(1);
  });

  test('splitFiles output is always conflict-free', () => {
    for (const source of sources) expect(joinConflicts(splitFiles(source))).toEqual([]);
  });
});

describe('isFileName', () => {
  test('follows the MARKER regex exactly', () => {
    for (const name of ['main.circ', 'a-b_1.circ', 'x.y.circ']) expect(isFileName(name)).toBe(true);
    for (const name of ['', 'foo', 'foo.circ ', 'a/b.circ', '<builtin>/xor.circ', 'a.circ\nb.circ', '.circ '])
      expect(isFileName(name)).toBe(false);
  });
});

describe('requestFor', () => {
  test('accepts a startLine-free file array', () => {
    const split = splitFiles(tour[5].source);
    const bare = split.map((f) => named(f.name, f.body));
    expect(requestFor(bare)).toEqual(requestFor(split));
  });
});
