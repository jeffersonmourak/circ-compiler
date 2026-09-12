import { MAX_TOPOLOGY_COMPONENTS, MAX_TOPOLOGY_CONNECTIONS, MAX_TOPOLOGY_ORIGIN_FRAMES, MAX_TOPOLOGY_SECTION_BYTES, type TopologyComponent, type TopologyConnection, type TopologyOrigin } from './playground-contract.ts';

const KINDS = ['input_pin', 'not', 'and', 'wire', 'led', 'output_pin', 'slice', 'concat', 'rom', 'ram'] as const;
type Decoded = { components: Array<{ id: number; kind: number; width: number; name: string; origin?: Array<{ alias: string; subcircuit: string; targetFile: number }>; slice?: { start: number; end: number }; memory?: { addrWidth: number } }>; connections: Array<{ fromId: number; toId: number; port: number }> };

export function normalizeTopology(decoded: Decoded, fileById: ReadonlyMap<number, string>): { components: TopologyComponent[]; connections: TopologyConnection[] } | null {
  if (!Array.isArray(decoded.components) || !Array.isArray(decoded.connections) || decoded.components.length > MAX_TOPOLOGY_COMPONENTS || decoded.connections.length > MAX_TOPOLOGY_CONNECTIONS) return null;
  let frames = 0;
  const ids = new Set<number>();
  const components: TopologyComponent[] = [];
  for (const component of decoded.components) {
    if (!Number.isSafeInteger(component.id) || component.id < 0 || ids.has(component.id) || !Number.isInteger(component.kind) || !KINDS[component.kind] || !Number.isInteger(component.width) || component.width < 1 || component.width > 64 || typeof component.name !== 'string') return null;
    ids.add(component.id);
    const origins: TopologyOrigin[] = [];
    for (const frame of component.origin ?? []) {
      if (!frame || typeof frame.alias !== 'string' || typeof frame.subcircuit !== 'string' || !Number.isSafeInteger(frame.targetFile) || ++frames > MAX_TOPOLOGY_ORIGIN_FRAMES) return null;
      origins.push({ alias: frame.alias, subcircuit: frame.subcircuit, targetFileId: frame.targetFile, targetFile: fileById.get(frame.targetFile) ?? null });
    }
    const memory = component.memory ? (KINDS[component.kind] === 'rom' || KINDS[component.kind] === 'ram') && Number.isInteger(component.memory.addrWidth) && component.memory.addrWidth >= 1 && component.memory.addrWidth <= 16 ? { kind: KINDS[component.kind] as 'rom' | 'ram', addressWidth: component.memory.addrWidth } : null : null;
    if (component.memory && !memory) return null;
    components.push({ id: component.id, kind: KINDS[component.kind], width: component.width, name: component.name, origins, slice: component.slice && Number.isInteger(component.slice.start) && Number.isInteger(component.slice.end) ? { start: component.slice.start, end: component.slice.end } : null, memory });
  }
  const connections: TopologyConnection[] = [];
  for (const connection of decoded.connections) {
    if (!Number.isSafeInteger(connection.fromId) || !Number.isSafeInteger(connection.toId) || !ids.has(connection.fromId) || !ids.has(connection.toId) || !Number.isInteger(connection.port) || connection.port < 0 || connection.port > 255) return null;
    connections.push({ fromId: connection.fromId, toId: connection.toId, port: connection.port, portLabel: null });
  }
  return { components, connections };
}

export async function decodeTopology(bytes: Uint8Array, fileById: ReadonlyMap<number, string>) {
  if (bytes.byteLength > MAX_TOPOLOGY_SECTION_BYTES) return null;
  try {
    const module = await WebAssembly.compile(bytes);
    const sections = WebAssembly.Module.customSections(module, 'circ.topology.v0.full');
    if (sections.length !== 1 || sections[0].byteLength > MAX_TOPOLOGY_SECTION_BYTES) return null;
    const { decodeFullTopology } = await import('circ-renderer');
    return normalizeTopology(decodeFullTopology(new Uint8Array(sections[0])) as Decoded, fileById);
  } catch { return null; }
}
