import { describe, expect, test } from 'bun:test';
import { convertDiagnostics, DiagnosticStore } from '../src/scripts/playground-diagnostics.ts';
import type { WorkInputs } from '../src/scripts/playground-contract.ts';

const inputs: WorkInputs = { target: { projectId: 'scratch:one', sourceRevision: 'source:1', entryFile: 'main.circ', targetEpoch: 'target:1' }, optionsRevision: 'options:1', imageRevision: null, artifactId: null, liveStateRevision: null };
const analysis = { files: [{ file_id: 0, path: '/playground/main.circ' }], diagnostics: [{ file_id: 0, severity: 'error' as const, code: 'E001', message: 'bad 😀 name', range: { start_line: 1, start_col: 5, end_line: 1, end_col: 9 } }], symbols: [], references: [] };

describe('playground diagnostics', () => {
  test('diagnostic_locations_preserve_both_encodings', () => {
    const diagnostics = convertDiagnostics(analysis, { '/playground/main.circ': 'abc 😀x\n' });
    expect(diagnostics?.[0].location.nativeRange).toMatchObject({ columnEncoding: 'utf8-bytes', startColumn: 5, endColumn: 9 });
    expect(diagnostics?.[0].location.sourceRange).toMatchObject({ columnEncoding: 'utf16', startColumn: 5, endColumn: 7, startOffset: 4, endOffset: 6 });
  });

  test('diagnostic_pages_are_bounded_and_revision_bound', () => {
    const diagnostics = convertDiagnostics(analysis, { '/playground/main.circ': 'abc 😀x\n' })!;
    const store = new DiagnosticStore();
    store.retain({ requestedOperationId: 'operation:1', producerOperationId: 'operation:1', requestedInputs: inputs, producerInputs: inputs, compiler: { version: '0', revision: 'r', parser: 'p', parserRuntimeSha256: 'p', grammarSha256: 'g', topologyVersion: 1, fullVersion: 1 }, counts: { errors: 1, warnings: 0 }, diagnostics });
    expect(store.page('operation:1', 'source:1', undefined, 1, 'observation:1', { projectId: 'scratch:one', sourceRevision: 'source:1', files: ['main.circ'] })).toMatchObject({ ok: true, value: { diagnostics: [{ location: { currentlyEditable: true } }] } });
    expect(store.page('operation:1', 'other', undefined, 1, 'observation:1', { projectId: 'scratch:one', sourceRevision: 'source:1', files: ['main.circ'] })).toMatchObject({ ok: false, code: 'REVISION_CONFLICT' });
  });
});
