import { describe, expect, test } from 'bun:test';
import { SOURCE_OMISSIONS, pageExport } from '../src/scripts/playground-handoff.ts';

describe('playground handoff snapshots', () => {
  test('source_export_pages_reassemble_and_declares_omissions', () => {
    const base = { exportId: 'e', contentType: 'text/plain', provenance: { target: { projectId: 'p', sourceRevision: 's', entryFile: 'main.circ', targetEpoch: 't' }, sourceRevision: 's', sessionId: null }, contents: ['combined marker source'], omissions: SOURCE_OMISSIONS, text: 'abc\ud83d\ude00def' };
    const first = pageExport(base, undefined, 4)!; const second = pageExport(base, first.nextCursor!, 4)!; const third = pageExport(base, second.nextCursor!, 4)!;
    expect(first.text + second.text + third.text).toBe(base.text);
    expect(first.omissions).toContain('source_images');
    expect(pageExport(base, 'bad', 4)).toBeNull();
  });
});
