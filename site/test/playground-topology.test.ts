import { describe, expect, test } from 'bun:test';
import { normalizeTopology } from '../src/scripts/playground-topology.ts';

describe('playground topology inspection', () => {
  test('validates_ids_endpoints_and_resolves_origin_files', () => {
    const decoded = { components: [{ id: 0, kind: 0, width: 1, name: 'a', origin: [] }, { id: 1, kind: 8, width: 8, name: 'rom', origin: [{ alias: 'x', subcircuit: 'child', targetFile: 7 }], memory: { addrWidth: 4 } }], connections: [{ fromId: 0, toId: 1, port: 0 }] };
    const topology = normalizeTopology(decoded, new Map([[7, '/playground/child.circ']]));
    expect(topology).toMatchObject({ components: [{ kind: 'input_pin' }, { kind: 'rom', origins: [{ targetFile: '/playground/child.circ' }], memory: { addressWidth: 4 } }], connections: [{ fromId: 0, toId: 1 }] });
    expect(normalizeTopology({ ...decoded, connections: [{ fromId: 9, toId: 1, port: 0 }] }, new Map())).toBeNull();
  });
});
