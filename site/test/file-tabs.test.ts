// The tab model is where a file can silently disappear, so every reducer is
// proven here rather than in the DOM. The purity case is not decoration: it is
// what keeps this module reachable from `bun test` at all.
import { describe, expect, test } from 'bun:test';
import { resolve } from 'node:path';
import {
  activeFile,
  fromSource,
  rootIndex,
  select,
  setBody,
  toSource,
  type FileTabsState,
} from '../src/scripts/file-tabs.ts';
import { joinConflicts, rootOf } from '../src/utils/split-files.ts';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';

const sources = [...examples.map((e) => e.source), ...tour.map((t) => t.source)];

describe('file tabs model', () => {
  test('fromSource/toSource round-trip every content source', () => {
    expect(sources).toHaveLength(17);
    for (const source of sources) expect(toSource(fromSource(source))).toBe(source);
  });

  test('fromSource of an empty string is one main.circ tab', () => {
    const state = fromSource('');
    expect(state.files).toHaveLength(1);
    expect(state.files[0].name).toBe('main.circ');
    expect(state.active).toBe(0);
    expect(rootIndex(state)).toBe(0);
  });

  test('tour step 6 is two tabs whose last is the root', () => {
    const state = fromSource(tour[5].source);
    expect(state.files.map((f) => f.name)).toEqual(['half_adder.circ', 'root.circ']);
    expect(rootIndex(state)).toBe(1);
    expect(rootOf(state.files).name).toBe('root.circ');
    expect(activeFile(state).name).toBe('half_adder.circ');
    expect(joinConflicts(state.files)).toEqual([]);
  });

  test('select clamps out-of-range indices', () => {
    const state = fromSource(tour[5].source);
    expect(select(state, 1).active).toBe(1);
    expect(select(state, 99).active).toBe(1);
    expect(select(state, -3).active).toBe(0);
    // Selecting the current tab is identity, so no re-render is triggered.
    expect(select(state, 0)).toBe(state);
  });

  test('select never touches the files array', () => {
    const state = fromSource(tour[5].source);
    const next = select(state, 1);
    expect(next.files).toBe(state.files);
    expect(toSource(next)).toBe(toSource(state));
  });

  test('setBody is pure and leaves the input untouched', () => {
    const state = fromSource(tour[5].source);
    const before = state.files.map((f) => ({ ...f }));
    const next = setBody(state, 0, 'input x\n');

    expect(next).not.toBe(state);
    expect(next.files[0].body).toBe('input x\n');
    expect(next.files[0].name).toBe('half_adder.circ');
    expect(next.files[1]).toBe(state.files[1]); // untouched entries are shared
    expect(next.active).toBe(state.active);
    // The input state is byte-for-byte what it was.
    expect(state.files.map((f) => ({ ...f }))).toEqual(before);
  });

  test('setBody ignores an out-of-range index and an unchanged body', () => {
    const state = fromSource(tour[5].source);
    expect(setBody(state, 5, 'x')).toBe(state);
    expect(setBody(state, -1, 'x')).toBe(state);
    expect(setBody(state, 0, state.files[0].body)).toBe(state);
  });

  test('an edit survives the round trip into the combined source', () => {
    const state = fromSource(tour[5].source);
    const edited = setBody(state, 0, 'input a, b\n');
    const back: FileTabsState = fromSource(toSource(edited));
    expect(back.files.map((f) => f.name)).toEqual(['half_adder.circ', 'root.circ']);
    expect(back.files[0].body).toBe('input a, b\n');
    expect(back.files[1].body).toBe(state.files[1].body);
  });

  test('file-tabs.ts stays free of CodeMirror and the DOM', async () => {
    const source = await Bun.file(resolve(import.meta.dir, '..', 'src', 'scripts', 'file-tabs.ts')).text();
    expect(source).not.toMatch(/@codemirror\//);
    expect(source).not.toMatch(/\bdocument\.|localStorage/);
  });
});
