// The explorer's shape and its keyboard contract, driven headlessly.
//
// The flattening is where a tree goes wrong: a collapsed group that still
// contributes its children turns every arrow key into a jump to a row nobody
// can see. Every case below is about what is VISIBLE, never about what the
// data contains.
import { describe, expect, test } from 'bun:test';
import {
  fileNodeId,
  groupOf,
  moveFor,
  reveal,
  rollUp,
  sumCounts,
  toggle,
  visibleNodes,
  type TreeInput,
  type TreeNode,
} from '../src/scripts/ws-tree.ts';

const NO_COUNTS = { errors: 0, warnings: 0 };

function input(over: Partial<TreeInput> = {}): TreeInput {
  return {
    groups: [
      {
        id: 'introduction',
        label: 'Introduction',
        projects: [
          { id: 'example:a', label: 'A', editable: false },
          { id: 'example:b', label: 'B', editable: false },
        ],
      },
      { id: 'yours', label: 'Yours', projects: [{ id: 'scratch:1', label: 'Mine', editable: true }] },
    ],
    activeId: 'scratch:1',
    files: [{ name: 'half.circ' }, { name: 'main.circ' }],
    activeFile: 0,
    counts: [NO_COUNTS, NO_COUNTS],
    conflicts: new Map(),
    expanded: new Set(['introduction', 'yours', 'scratch:1']),
    ...over,
  };
}

const shape = (nodes: readonly TreeNode[]) => nodes.map((n) => `${'  '.repeat(n.level - 1)}${n.kind}:${n.label}`);

describe('visibleNodes', () => {
  test('flattens groups, projects and the open project’s files in visual order', () => {
    expect(shape(visibleNodes(input()))).toEqual([
      'group:Introduction',
      '  project:A',
      '  project:B',
      'group:Yours',
      '  project:Mine',
      '    file:half.circ',
      '    file:main.circ',
    ]);
  });

  test('a collapsed group contributes its own row and nothing beneath it', () => {
    const nodes = visibleNodes(input({ expanded: new Set(['yours', 'scratch:1']) }));
    expect(shape(nodes)).toEqual([
      'group:Introduction',
      'group:Yours',
      '  project:Mine',
      '    file:half.circ',
      '    file:main.circ',
    ]);
    // This is the whole reason the list is flat: with the group shut, the row
    // after it is the NEXT GROUP, so ArrowDown cannot land on a hidden child.
    expect(nodes[1].kind).toBe('group');
  });

  test('a collapsed project hides its files but keeps its own row', () => {
    const nodes = visibleNodes(input({ expanded: new Set(['introduction', 'yours']) }));
    expect(shape(nodes).filter((s) => s.includes('file:'))).toEqual([]);
    expect(nodes.at(-1)!.kind).toBe('project');
  });

  test('only the active project is expandable, and only when it has files', () => {
    const nodes = visibleNodes(input());
    const byId = new Map(nodes.map((n) => [n.id, n]));
    const mine = byId.get('scratch:1')!;
    const other = byId.get('example:a')!;
    expect(mine.kind === 'project' && mine.expandable).toBe(true);
    expect(mine.kind === 'project' && mine.active).toBe(true);
    // An inactive project is a single stored string, not a file set. A twisty
    // there would open onto nothing.
    expect(other.kind === 'project' && other.expandable).toBe(false);
    expect(other.kind === 'project' && other.active).toBe(false);

    // …and an active project with no files loaded yet is not expandable either.
    const empty = visibleNodes(input({ files: [], counts: [] }));
    const m = empty.find((n) => n.id === 'scratch:1')!;
    expect(m.kind === 'project' && m.expandable).toBe(false);
  });

  test('the last file is the root, and the active file is marked', () => {
    const files = visibleNodes(input({ activeFile: 1 })).filter((n) => n.kind === 'file');
    expect(files.map((f) => f.kind === 'file' && f.root)).toEqual([false, true]);
    expect(files.map((f) => f.kind === 'file' && f.active)).toEqual([false, true]);
  });

  test('a file carries its own worst severity, errors ahead of warnings', () => {
    const nodes = visibleNodes(
      input({ counts: [{ errors: 2, warnings: 5 }, { errors: 0, warnings: 3 }] }),
    );
    const files = nodes.filter((n) => n.kind === 'file');
    expect(files.map((f) => [f.severity, f.badge])).toEqual([
      ['error', 2],
      ['warning', 3],
    ]);
  });

  test('the project rolls its files up, so a collapsed project still reports', () => {
    // This is what makes collapsing safe: shutting a project must not hide the
    // fact that something inside it is broken.
    const nodes = visibleNodes(
      input({
        expanded: new Set(['yours']),
        counts: [{ errors: 0, warnings: 1 }, { errors: 4, warnings: 0 }],
      }),
    );
    const mine = nodes.find((n) => n.id === 'scratch:1')!;
    expect(mine.kind === 'project' && mine.severity).toBe('error');
    expect(mine.kind === 'project' && mine.badge).toBe(4);
  });

  test('an inactive project never borrows the open project’s counts', () => {
    // `counts` describes the project that is LOADED. Spilling it onto the
    // others would put the open project's errors on every row in the tree.
    const nodes = visibleNodes(input({ counts: [{ errors: 9, warnings: 9 }, NO_COUNTS] }));
    const other = nodes.find((n) => n.id === 'example:a')!;
    expect(other.kind === 'project' && other.severity).toBeNull();
    expect(other.kind === 'project' && other.badge).toBe(0);
  });

  test('an inactive project keeps the badge from the last time it was analysed', () => {
    // Switching away from a broken project used to make its badge vanish,
    // which reads as "the errors are gone" rather than "nobody is looking".
    const nodes = visibleNodes(
      input({ remembered: new Map([['example:a', { errors: 3, warnings: 1 }]]) }),
    );
    const remembered = nodes.find((n) => n.id === 'example:a')!;
    expect(remembered.kind === 'project' && remembered.severity).toBe('error');
    expect(remembered.kind === 'project' && remembered.badge).toBe(3);
    // A project nobody has opened still claims nothing.
    const unseen = nodes.find((n) => n.id === 'example:b')!;
    expect(unseen.kind === 'project' && unseen.severity).toBeNull();
  });

  test('the open project always uses live counts, never the remembered ones', () => {
    // The memory is stale by definition the moment the project is reopened.
    const nodes = visibleNodes(
      input({
        counts: [NO_COUNTS, NO_COUNTS],
        remembered: new Map([['scratch:1', { errors: 7, warnings: 0 }]]),
      }),
    );
    const open = nodes.find((n) => n.id === 'scratch:1')!;
    expect(open.kind === 'project' && open.severity).toBeNull();
    expect(open.kind === 'project' && open.badge).toBe(0);
  });

  test('a clean remembered project shows no badge rather than a zero', () => {
    const nodes = visibleNodes(
      input({ remembered: new Map([['example:a', { errors: 0, warnings: 0 }]]) }),
    );
    const clean = nodes.find((n) => n.id === 'example:a')!;
    expect(clean.kind === 'project' && clean.severity).toBeNull();
    expect(clean.kind === 'project' && clean.badge).toBe(0);
  });

  test('conflicts reach the file row that cannot be written', () => {
    const nodes = visibleNodes(input({ conflicts: new Map([[1, 'this file is empty']]) }));
    const files = nodes.filter((n) => n.kind === 'file');
    expect(files.map((f) => f.kind === 'file' && f.conflict)).toEqual([null, 'this file is empty']);
  });

  test('file ids are unique across the tree', () => {
    const nodes = visibleNodes(input());
    expect(new Set(nodes.map((n) => n.id)).size).toBe(nodes.length);
    expect(fileNodeId('scratch:1', 0)).toBe('scratch:1/0');
  });

  test('an empty group still shows, so "Yours" does not vanish', () => {
    const nodes = visibleNodes(
      input({ groups: [{ id: 'yours', label: 'Yours', projects: [] }], activeId: null }),
    );
    expect(shape(nodes)).toEqual(['group:Yours']);
    expect(nodes[0].kind === 'group' && nodes[0].count).toBe(0);
  });
});

describe('sumCounts', () => {
  test('adds every file up, which is what a project remembers', () => {
    expect(sumCounts([{ errors: 1, warnings: 2 }, { errors: 3, warnings: 4 }])).toEqual({
      errors: 4,
      warnings: 6,
    });
    expect(sumCounts([])).toEqual({ errors: 0, warnings: 0 });
  });
});

describe('rollUp', () => {
  test('sums across files and reports the worse severity', () => {
    expect(rollUp([{ errors: 0, warnings: 2 }, { errors: 0, warnings: 3 }])).toEqual({
      severity: 'warning',
      badge: 5,
    });
    expect(rollUp([{ errors: 1, warnings: 9 }, NO_COUNTS])).toEqual({ severity: 'error', badge: 1 });
    expect(rollUp([])).toEqual({ severity: null, badge: 0 });
  });
});

describe('moveFor', () => {
  const nodes = visibleNodes(input());
  // group:Introduction 0, project:A 1, project:B 2, group:Yours 3,
  // project:Mine 4, file:half 5, file:main 6

  test('up and down walk visible rows and stop at the ends', () => {
    expect(moveFor(nodes, 0, 'ArrowDown')).toEqual({ kind: 'focus', index: 1 });
    expect(moveFor(nodes, 6, 'ArrowDown')).toBeNull();
    expect(moveFor(nodes, 6, 'ArrowUp')).toEqual({ kind: 'focus', index: 5 });
    expect(moveFor(nodes, 0, 'ArrowUp')).toBeNull();
  });

  test('home and end reach the whole visible list', () => {
    expect(moveFor(nodes, 4, 'Home')).toEqual({ kind: 'focus', index: 0 });
    expect(moveFor(nodes, 0, 'End')).toEqual({ kind: 'focus', index: 6 });
  });

  test('right opens a shut row, then steps into it', () => {
    const shut = visibleNodes(input({ expanded: new Set(['yours', 'scratch:1']) }));
    expect(moveFor(shut, 0, 'ArrowRight')).toEqual({ kind: 'expand', id: 'introduction' });
    // Already open: the first child is simply the next visible row.
    expect(moveFor(nodes, 0, 'ArrowRight')).toEqual({ kind: 'focus', index: 1 });
  });

  test('left shuts an open row, then steps out to its parent', () => {
    expect(moveFor(nodes, 0, 'ArrowLeft')).toEqual({ kind: 'collapse', id: 'introduction' });
    // A leaf goes to its parent instead: file:half → project:Mine.
    expect(moveFor(nodes, 5, 'ArrowLeft')).toEqual({ kind: 'focus', index: 4 });
    // …and a project inside a group goes to the group.
    expect(moveFor(nodes, 2, 'ArrowLeft')).toEqual({ kind: 'focus', index: 0 });
  });

  test('a leaf refuses right rather than pretending to open', () => {
    expect(moveFor(nodes, 5, 'ArrowRight')).toBeNull();
    // An inactive project is a leaf too.
    expect(moveFor(nodes, 1, 'ArrowRight')).toBeNull();
  });

  test('a top-level row has no parent to step out to', () => {
    const shut = visibleNodes(input({ expanded: new Set() }));
    expect(moveFor(shut, 0, 'ArrowLeft')).toBeNull();
  });

  test('an empty tree and an out-of-range index are values, not throws', () => {
    expect(moveFor([], 0, 'ArrowDown')).toBeNull();
    expect(moveFor(nodes, 99, 'ArrowDown')).toBeNull();
  });
});

describe('toggle and reveal', () => {
  test('toggle adds what is missing and removes what is there', () => {
    expect([...toggle(new Set(['a']), 'b')].sort()).toEqual(['a', 'b']);
    expect([...toggle(new Set(['a', 'b']), 'a')]).toEqual(['b']);
    // A new set every time: the caller decides what to persist.
    const before = new Set(['a']);
    expect(toggle(before, 'b')).not.toBe(before);
    expect([...before]).toEqual(['a']);
  });

  test('reveal opens the project and the group that holds it', () => {
    const opened = reveal(new Set(), input(), 'example:b');
    expect([...opened].sort()).toEqual(['example:b', 'introduction']);
    // A project the tree does not contain opens nothing but itself.
    expect([...reveal(new Set(), input(), 'nope')]).toEqual(['nope']);
    expect([...reveal(new Set(['x']), input(), null)]).toEqual(['x']);
  });

  test('groupOf finds the holder, or null', () => {
    expect(groupOf(input(), 'example:a')).toBe('introduction');
    expect(groupOf(input(), 'scratch:1')).toBe('yours');
    expect(groupOf(input(), 'nope')).toBeNull();
    expect(groupOf(input(), null)).toBeNull();
  });
});
