import { describe, expect, test } from 'bun:test';
import { SchematicResults, TruthResults, schematicDimensions, textPage } from '../src/scripts/playground-inspection.ts';

const inputs = { target: { projectId: 'p', sourceRevision: 's', entryFile: 'main.circ', targetEpoch: 't' }, optionsRevision: 'o', imageRevision: null, artifactId: null, liveStateRevision: null };
const compiler = { version: 'v', revision: 'r', parser: 'p', parserRuntimeSha256: 'a', grammarSha256: 'b', topologyVersion: 1, fullVersion: 1 };

describe('playground inspection retention', () => {
  test('schematic_pages_reassemble_unicode_without_splitting_surrogates', () => {
    const text = 'a\ud83d\ude00bc';
    expect(textPage(text, 0, 2)).toEqual({ text: 'a', nextCursor: '1' });
    const values = new SchematicResults();
    values.admit({ operationId: 'op', page: { operationId: 'op', inputs, compiler, settings: { expandMacros: false, expandDisplay: false, color: 'never' }, dimensions: schematicDimensions(text), text } });
    const first = values.get('op', undefined, 2)!; const second = values.get('op', first.nextCursor!, 2)!; const third = values.get('op', second.nextCursor!, 2)!;
    expect(first.text + second.text + third.text).toBe(text);
    expect(values.get('op', 'wrong', 2)).toBeNull();
  });

  test('truth_pages_only_read_retained_rows', () => {
    const values = new TruthResults();
    expect(values.admit({ operationId: 'truth', page: { operationId: 'truth', inputs, compiler, scope: { kind: 'exhaustive', engine: 'compiler', inputBits: 2, enumeratedBits: 2, rowCount: 2, cap: 12, heldInputs: [], unknownInputs: [], partialBusPolicy: 'whole_bus_unknown' }, columns: [{ name: 'a', kind: 'in', width: 1 }], rows: [{ index: 0, inputs: ['0x0'], outputs: [] }, { index: 1, inputs: ['0x1'], outputs: [] }] } })).toBe(true);
    expect(values.get('truth', undefined, 1)).toMatchObject({ rows: [{ index: 0 }], nextCursor: '1' });
    expect(values.get('truth', '1', 1)).toMatchObject({ rows: [{ index: 1 }], nextCursor: null });
    expect(values.get('truth', '3', 1)).toBeNull();
  });
});
