// Loading a memory's contents into a compiled artifact, with no analysis.
//
// The playground can validate an image against `--analyze`, which tells it
// every declared memory's name and shape. A gallery card has no analysis and
// no compiler: it has a `.wasm` and a renderer. So the shape is read back out
// of the artifact instead, through `getMemInfo` on the id the topology gives.
//
// That is not a lesser check. `getMemInfo` is the runtime's own answer about
// what it will accept, so an image validated against it cannot be refused for
// a shape reason afterwards — whereas an analysis can drift from the artifact
// beside it.
//
// Roms and rams are both loadable. `romPlan` skips a ram because preloading
// one into a TRUTH TABLE would be stating an initial condition the table does
// not otherwise have; a canvas is a live circuit a reader pokes at, and
// starting it with something in memory is the whole point of a demo.

import {
  RAM_KIND,
  ROM_KIND,
  decodeMemInfo,
  parseRomImage,
  type MemorySymbol,
} from '../utils/rom-image.ts';

/** The structural subset of the renderer's topology this needs. Declared
 *  rather than imported so the gallery's canvas does not drag the renderer's
 *  types into a module a test drives headlessly. */
export interface TopologyLike {
  components: readonly {
    id: number;
    kind: number;
    name: string;
    origin?: readonly unknown[];
  }[];
}

/** The artifact's own exports. Every member optional: a `.wasm` built before
 *  memories existed has none of them. */
export interface MemoryHost {
  memory?: { buffer: ArrayBufferLike };
  getMemInfo?: (id: number) => number;
  memBuffer?: (id: number) => number;
  memLoad?: (id: number, len: number) => number;
}

export interface FoundMemory {
  id: number;
  mem: MemorySymbol;
}

export interface LoadResult {
  /** Names whose image reached the circuit. */
  applied: string[];
  /** name → why it did not. */
  errors: Map<string, string>;
}

const kindOf = (byte: number): MemorySymbol['kind'] | null =>
  byte === ROM_KIND ? 'rom' : byte === RAM_KIND ? 'ram' : null;

/**
 * Every memory the artifact declares, by name, with the shape the RUNTIME
 * reports for it.
 *
 * Top-level components only: a box with a non-empty `origin` came from inside
 * a macro, and its name is not one the reader wrote or can address.
 */
export function memoriesOf(topology: TopologyLike, host: MemoryHost): Map<string, FoundMemory> {
  const out = new Map<string, FoundMemory>();
  if (!host.getMemInfo) return out;
  for (const c of topology.components) {
    if ((c.origin?.length ?? 0) !== 0) continue;
    const kind = kindOf(c.kind);
    if (kind === null || !c.name) continue;
    const info = decodeMemInfo(host.getMemInfo(c.id));
    // A component the topology calls a memory but the runtime does not is a
    // disagreement, and writing into it on a guess is worse than skipping it.
    if (!info || kindOf(info.kind) !== kind) continue;
    if (out.has(c.name)) continue; // first wins; a duplicate name is already broken
    out.set(c.name, {
      id: c.id,
      mem: { name: c.name, kind, width: info.width, addrWidth: info.addrWidth },
    });
  }
  return out;
}

/**
 * Write each named image into the running circuit.
 *
 * Nothing throws. A name the artifact does not declare, an image that does not
 * parse, a runtime that refuses the load: each is a message against that name,
 * and the other memories still load. A card with one bad image should show the
 * rest of its circuit rather than nothing.
 *
 * `memBuffer` may grow linear memory, so the byte view is re-taken after every
 * call — one held across it is detached and writes into nothing.
 */
export function loadMemoryImages(
  host: MemoryHost,
  topology: TopologyLike,
  images: Readonly<Record<string, string>>,
): LoadResult {
  const applied: string[] = [];
  const errors = new Map<string, string>();
  const names = Object.keys(images);
  if (names.length === 0) return { applied, errors };
  if (!host.memory || !host.getMemInfo || !host.memBuffer || !host.memLoad) {
    for (const name of names) errors.set(name, 'This artifact has no memory support.');
    return { applied, errors };
  }

  const found = memoriesOf(topology, host);
  for (const name of names) {
    const target = found.get(name);
    if (!target) {
      errors.set(name, `${name} is not a memory in this circuit.`);
      continue;
    }
    const parsed = parseRomImage(images[name], target.mem);
    if (!parsed.ok) {
      errors.set(name, parsed.message);
      continue;
    }
    if (parsed.words === 0) continue; // an empty image asks for nothing

    const ptr = host.memBuffer(target.id);
    if (ptr < 0) {
      errors.set(name, `${name} has no staging buffer.`);
      continue;
    }
    // Re-taken here, after memBuffer, and never hoisted out of the loop.
    new Uint8Array(host.memory.buffer).set(parsed.bytes, ptr);
    const rc = host.memLoad(target.id, parsed.bytes.length);
    if (rc !== 0) {
      errors.set(name, `${name} was refused by the runtime (code ${rc}).`);
      continue;
    }
    applied.push(name);
  }
  return { applied, errors };
}

/** Parse the JSON a card carries in `data-circ-memory`, or an empty map.
 *  Never throws: the attribute is markup, and markup can be wrong. */
export function readMemoryAttr(raw: string | undefined | null): Record<string, string> {
  if (!raw) return {};
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) return {};
    const out: Record<string, string> = {};
    for (const [key, value] of Object.entries(parsed as Record<string, unknown>)) {
      if (typeof value === 'string') out[key] = value;
    }
    return out;
  } catch {
    return {};
  }
}
