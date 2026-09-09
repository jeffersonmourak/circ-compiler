// The tab model is where a file can silently disappear, so every reducer is
// proven here rather than in the DOM. The purity case is not decoration: it is
// what keeps this module reachable from `bun test` at all.
import { describe, expect, test } from 'bun:test';
import { resolve } from 'node:path';
import {
  activeFile,
  addFile,
  canDelete,
  deleteFile,
  fromSource,
  moveFile,
  nameError,
  nextFileName,
  renameFile,
  rootIndex,
  seedBody,
  select,
  setBody,
  toSource,
  type FileTabsState,
} from '../src/scripts/file-tabs.ts';
import { joinConflicts, requestFor, rootOf } from '../src/utils/split-files.ts';
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

describe('add, rename and delete', () => {
  const two = () => fromSource(tour[5].source);

  test('addFile lands before the root and seeds a joinable body', () => {
    const next = addFile(two());
    expect(next.files.map((f) => f.name)).toEqual(['half_adder.circ', 'file1.circ', 'root.circ']);
    // The root does not move.
    expect(rootOf(next.files).name).toBe('root.circ');
    expect(rootIndex(next)).toBe(2);
    // The new tab is the active one.
    expect(next.active).toBe(1);
    expect(activeFile(next).name).toBe('file1.circ');
    // And the seeded body survives a round trip: non-blank, and not a marker.
    expect(joinConflicts(next.files)).toEqual([]);
    expect(fromSource(toSource(next)).files.map((f) => f.name)).toEqual(next.files.map((f) => f.name));
  });

  test('nextFileName skips names already taken', () => {
    expect(nextFileName([])).toBe('file1.circ');
    const one = addFile(two());
    expect(nextFileName(one.files)).toBe('file2.circ');
    expect(nextFileName([{ name: 'file1.circ', body: '' }, { name: 'file3.circ', body: '' }])).toBe('file2.circ');
  });

  test('seedBody is non-blank and is not itself a marker', () => {
    const body = seedBody('file1.circ');
    expect(body.trim().length).toBeGreaterThan(0);
    // A marker needs the .circ suffix; the seed deliberately drops it, or the
    // splitter would read the new file's own first line as a second file.
    expect(fromSource(body).files).toHaveLength(1);
  });

  test('nameError enforces the marker name and uniqueness', () => {
    const state = two();
    for (const bad of ['', 'foo', 'foo.circ ', 'a/b.circ', '<builtin>/xor.circ', 'main']) {
      expect(nameError(state, 0, bad)).not.toBeNull();
    }
    expect(nameError(state, 0, 'a-b_1.circ')).toBeNull();
    // Renaming a file to the name it already has is not a duplicate.
    expect(nameError(state, 0, 'half_adder.circ')).toBeNull();
    // …but taking another file's name is.
    expect(nameError(state, 0, 'root.circ')).not.toBeNull();
  });

  test('renameFile is a no-op on an invalid name', () => {
    const state = two();
    expect(renameFile(state, 0, 'foo')).toBe(state);
    expect(renameFile(state, 0, 'root.circ')).toBe(state);
    expect(renameFile(state, 9, 'ok.circ')).toBe(state);
    expect(renameFile(state, 0, 'half_adder.circ')).toBe(state);

    const renamed = renameFile(state, 0, 'ha.circ');
    expect(renamed.files.map((f) => f.name)).toEqual(['ha.circ', 'root.circ']);
    expect(renamed.files[0].body).toBe(state.files[0].body);
    expect(renamed.active).toBe(state.active);
    // The rename reaches the request, which is why an import can break.
    expect(Object.keys(requestFor(renamed.files))).toContain('files');
    expect(Object.keys(requestFor(renamed.files).files)).toEqual([
      '/playground/ha.circ',
      '/playground/root.circ',
    ]);
  });

  test('deleteFile refuses the last remaining file', () => {
    const one = fromSource('input a\n');
    expect(canDelete(one)).toBe(false);
    expect(deleteFile(one, 0)).toBe(one);
    expect(canDelete(two())).toBe(true);
  });

  test('deleteFile promotes a new root and clamps active', () => {
    // Deleting the root promotes the file before it.
    const afterRoot = deleteFile(two(), 1);
    expect(afterRoot.files.map((f) => f.name)).toEqual(['half_adder.circ']);
    expect(rootOf(afterRoot.files).name).toBe('half_adder.circ');

    const three = addFile(two()); // [half_adder, file1, root], active 1
    // active > index: shifts down with it.
    expect(deleteFile(three, 0).active).toBe(0);
    // active === index: clamps to a surviving neighbour.
    expect(deleteFile(three, 1).active).toBe(1);
    // active < index: unchanged.
    expect(deleteFile({ ...three, active: 0 }, 2).active).toBe(0);
    // Deleting the last entry while it is active clamps into range.
    const atEnd = { files: three.files, active: 2 };
    expect(deleteFile(atEnd, 2).active).toBe(1);
  });

  test('every reducer leaves its input untouched', () => {
    const state = two();
    const before = JSON.stringify(state);
    addFile(state);
    renameFile(state, 0, 'ha.circ');
    deleteFile(state, 0);
    expect(JSON.stringify(state)).toBe(before);
  });
});

describe('reorder', () => {
  const three = () => addFile(fromSource(tour[5].source)); // [half_adder, file1, root], active 1

  test('moving a tab to the end changes the root', () => {
    const state = three();
    expect(rootOf(state.files).name).toBe('root.circ');
    const moved = moveFile(state, 0, 2);
    expect(moved.files.map((f) => f.name)).toEqual(['file1.circ', 'root.circ', 'half_adder.circ']);
    expect(rootOf(moved.files).name).toBe('half_adder.circ');
    expect(requestFor(moved.files).root).toBe('/playground/half_adder.circ');
  });

  test('the previously active file stays active after any move', () => {
    const state = three();
    const activeName = state.files[state.active].name;
    for (let from = 0; from < 3; from += 1) {
      for (let to = 0; to < 3; to += 1) {
        const moved = moveFile(state, from, to);
        expect(moved.files[moved.active].name).toBe(activeName);
        // …and the file set itself is only permuted.
        expect([...moved.files.map((f) => f.name)].sort()).toEqual(
          [...state.files.map((f) => f.name)].sort(),
        );
      }
    }
  });

  test('out-of-range indices clamp', () => {
    const state = three();
    expect(moveFile(state, 0, 99).files.map((f) => f.name)).toEqual([
      'file1.circ',
      'root.circ',
      'half_adder.circ',
    ]);
    expect(moveFile(state, -4, 0)).toBe(state); // src and dst both clamp to 0
    expect(moveFile(state, 1, 1)).toBe(state);
  });

  test('toSource after a move re-emits the markers in the new order', () => {
    const moved = moveFile(three(), 0, 2);
    const back = fromSource(toSource(moved));
    expect(back.files.map((f) => f.name)).toEqual(['file1.circ', 'root.circ', 'half_adder.circ']);
    expect(rootOf(back.files).name).toBe('half_adder.circ');
    // Bodies survive the reorder untouched.
    expect(back.files.map((f) => f.body)).toEqual(moved.files.map((f) => f.body));
  });

  test('moveFile leaves its input untouched', () => {
    const state = three();
    const before = JSON.stringify(state);
    moveFile(state, 0, 2);
    expect(JSON.stringify(state)).toBe(before);
  });
});
