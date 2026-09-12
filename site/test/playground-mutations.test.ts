import { describe, expect, test } from 'bun:test';
import { planMutations } from '../src/scripts/playground-mutations.ts';

describe('playground mutations', () => {
  test('ordered_file_mutations_are_atomic', () => {
    const files = [{ name: 'dep.circ', body: 'input a\n' }, { name: 'main.circ', body: 'import dep\n' }];
    const result = planMutations(files, 'main.circ', [
      { kind: 'rename', name: 'dep.circ', newName: 'part.circ' },
      { kind: 'delete', name: 'missing.circ' },
    ]);
    expect(result.ok).toBe(false);
    expect(files).toEqual([{ name: 'dep.circ', body: 'input a\n' }, { name: 'main.circ', body: 'import dep\n' }]);
  });

  test('text_edits_use_utf16_exclusive_ranges', () => {
    const result = planMutations([{ name: 'main.circ', body: 'a😀b' }], 'main.circ', [{ kind: 'edit', name: 'main.circ', edits: [{ from: 1, to: 3, text: 'x' }, { from: 3, to: 4, text: 'y' }] }]);
    expect(result).toMatchObject({ ok: true, value: { files: [{ name: 'main.circ', body: 'axy' }] } });
    const split = planMutations([{ name: 'main.circ', body: 'a😀b' }], 'main.circ', [{ kind: 'edit', name: 'main.circ', edits: [{ from: 2, to: 3, text: '' }] }]);
    expect(split.ok).toBe(false);
  });

  test('later_operations_name_the_current_draft', () => {
    const result = planMutations([{ name: 'main.circ', body: 'x\n' }], 'main.circ', [
      { kind: 'rename', name: 'main.circ', newName: 'root.circ' },
      { kind: 'edit', name: 'root.circ', edits: [{ from: 0, to: 1, text: 'y' }] },
    ]);
    expect(result).toMatchObject({ ok: true, value: { files: [{ name: 'root.circ', body: 'y\n' }], renamed: [{ oldName: 'main.circ', newName: 'root.circ' }] } });
  });
});
