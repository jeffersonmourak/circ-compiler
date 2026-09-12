import { describe, expect, test } from 'bun:test';
import { listProjects, readFile, readProject, type WorkspaceSnapshot } from '../src/scripts/playground-reads.ts';

function snapshot(source = 'a\n😀b'): WorkspaceSnapshot {
  return {
    revision: 'workspace-1',
    projects: [{
      id: 'scratch:one', name: 'Draft', kind: 'scratch', active: true, sourceOrigin: 'active_buffer', selectedEntryFile: 'main.circ',
      version: { projectId: 'scratch:one', revision: 'project-1', sourceRevision: 'source-1', imageRevision: 'image-1' },
      files: [{ name: 'main.circ', body: source }, { name: 'root.circ', body: '' }],
    }],
  };
}

describe('playground reads', () => {
  test('lists_and_reads_a_manifest_without_source_bodies', () => {
    const workspace = snapshot();
    const listed = listProjects(workspace, {});
    expect(listed).toMatchObject({ ok: true, value: { workspaceRevision: 'workspace-1', projects: [{ id: 'scratch:one', fileCount: 2 }] } });
    const manifest = readProject(workspace, { projectId: 'scratch:one' });
    expect(manifest.ok && manifest.value.sourceOrigin).toBe('active_buffer');
    expect(manifest.ok && manifest.value.defaultEntryFile).toBe('root.circ');
    expect(manifest.ok && manifest.value.files[0]).toMatchObject({ name: 'main.circ', utf16Length: 5 });
  });

  test('chunks_source_on_utf16_boundaries_and_requires_revision_after_first_chunk', () => {
    const workspace = snapshot();
    const first = readFile(workspace, { name: 'main.circ', maxCodeUnits: 3 });
    expect(first).toMatchObject({ ok: true, value: { text: 'a\n', nextOffset: 2, eof: false } });
    const conflict = readFile(workspace, { name: 'main.circ', offset: 2, maxCodeUnits: 2 });
    expect(conflict).toMatchObject({ ok: false, code: 'REVISION_CONFLICT' });
    const second = readFile(workspace, { name: 'main.circ', offset: 2, maxCodeUnits: 2, expectedSourceRevision: 'source-1' });
    expect(second).toMatchObject({ ok: true, value: { text: '😀', endOffset: 4 } });
  });

  test('rejects_changed_revision_cursors_and_invalid_offsets', () => {
    const first = readProject(snapshot(), { limit: 1 });
    if (!first.ok) throw new Error('expected manifest');
    const changed = snapshot();
    changed.projects[0].version.revision = 'project-2';
    expect(readProject(changed, { cursor: first.value.nextCursor! })).toMatchObject({ ok: false, code: 'REVISION_CONFLICT' });
    expect(readFile(snapshot(), { name: 'main.circ', offset: 3, expectedSourceRevision: 'source-1' })).toMatchObject({ ok: false, code: 'INVALID_RANGE' });
  });
});
