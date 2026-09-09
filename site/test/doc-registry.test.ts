// The registry decides which file is on screen after a tab is added, deleted
// or dragged. Getting it wrong shows the reader someone else's file, so every
// branch is proven here rather than left to the DOM.
import { describe, expect, test } from 'bun:test';
import { resolve } from 'node:path';
import { activeAfter, insert, move, remove } from '../src/scripts/doc-registry.ts';

const base = ['a', 'b', 'c', 'd'];

describe('doc registry', () => {
  test('insert, remove and move are pure permutations', () => {
    const input = [...base];
    const frozen = [...base];

    expect(insert(input, 1, 'x')).toEqual(['a', 'x', 'b', 'c', 'd']);
    expect(remove(input, 1)).toEqual(['a', 'c', 'd']);
    expect(move(input, 0, 3)).toEqual(['b', 'c', 'd', 'a']);
    // None of the three touched the input.
    expect(input).toEqual(frozen);

    // move composed with its inverse restores the input.
    for (const [from, to] of [[0, 3], [3, 0], [1, 2], [2, 1]]) {
      expect(move(move(base, from, to), to, from)).toEqual(base);
    }
    // and every move is a permutation.
    expect([...move(base, 0, 3)].sort()).toEqual([...base].sort());
  });

  test('insert at the root index shifts every later entry', () => {
    // The shape addFile uses: land before the root, so the root stays last.
    const rootIndex = base.length - 1;
    const next = insert(base, rootIndex, 'x');
    expect(next).toEqual(['a', 'b', 'c', 'x', 'd']);
    expect(next[next.length - 1]).toBe('d');
  });

  test('insert and remove clamp rather than corrupt', () => {
    expect(insert(base, 99, 'x')).toEqual([...base, 'x']);
    expect(insert(base, -5, 'x')).toEqual(['x', ...base]);
    expect(remove(base, 99)).toEqual(base);
    expect(remove(base, -1)).toEqual(base);
    expect(remove([], 0)).toEqual([]);
    expect(move([], 0, 1)).toEqual([]);
    expect(move(base, 99, -4)).toEqual(['d', 'a', 'b', 'c']);
  });

  test('activeAfter clamps in all three remove branches', () => {
    const length = base.length; // 4
    // active < removed: unchanged.
    expect(activeAfter(0, { kind: 'remove', at: 2, length })).toBe(0);
    // active > removed: shifts down with it.
    expect(activeAfter(3, { kind: 'remove', at: 1, length })).toBe(2);
    // active === removed: clamps to the nearest surviving neighbour.
    expect(activeAfter(2, { kind: 'remove', at: 2, length })).toBe(2);
    expect(activeAfter(3, { kind: 'remove', at: 3, length })).toBe(2);
    // Removing the only entry leaves nothing to be active.
    expect(activeAfter(0, { kind: 'remove', at: 0, length: 1 })).toBe(0);
  });

  test('activeAfter keeps the previously active entry active on insert', () => {
    for (let active = 0; active < base.length; active += 1) {
      for (let at = 0; at <= base.length; at += 1) {
        const next = insert(base, at, 'x');
        expect(next[activeAfter(active, { kind: 'insert', at })]).toBe(base[active]);
      }
    }
  });

  test('activeAfter keeps the previously active entry active on move', () => {
    for (let active = 0; active < base.length; active += 1) {
      for (let from = 0; from < base.length; from += 1) {
        for (let to = 0; to < base.length; to += 1) {
          const next = move(base, from, to);
          const landed = activeAfter(active, { kind: 'move', from, to });
          expect(next[landed]).toBe(base[active]);
        }
      }
    }
  });

  test('doc-registry.ts stays free of the editor package and the DOM', async () => {
    const source = await Bun.file(resolve(import.meta.dir, '..', 'src', 'scripts', 'doc-registry.ts')).text();
    expect(source).not.toMatch(/@codemirror\//);
    // Host ACCESS, not the English word: this module's subject is documents,
    // so a bare /\bdocument\b/ would forbid its own prose. The dotted form is
    // what the sibling purity case in file-tabs.test.ts uses, and it is what
    // actually catches a DOM reach.
    expect(source).not.toMatch(/\bdocument\.|\bwindow\.|\bglobalThis\.|localStorage/);
  });
});
