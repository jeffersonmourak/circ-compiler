import { describe, expect, test } from 'bun:test';
import { splitFiles, rootOf, requestFor } from '../src/utils/split-files.ts';
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
