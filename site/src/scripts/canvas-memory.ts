// Loading a memory's contents into a compiled artifact, with no analysis.
//
// The playground can validate an image against `--analyze`, which tells it
// every declared memory's name and shape. A gallery card has no analysis and
// no compiler: it has a `.wasm` and a renderer. So the shape comes from the
// runtime's own answer, through `memories()`, which is the runtime's
// statement of what it will accept — an image validated against it cannot be
// refused for a shape reason afterwards, whereas an analysis can drift from
// the artifact beside it.
//
// Roms and rams are both loadable. `romPlan` skips a ram because preloading
// one into a TRUTH TABLE would be stating an initial condition the table does
// not otherwise have; a canvas is a live circuit a reader pokes at, and
// starting it with something in memory is the whole point of a demo.

import { parseRomImage, type MemoryRuntime } from '../utils/rom-image.ts';

export interface LoadResult {
  /** Names whose image reached the circuit. */
  applied: string[];
  /** name → why it did not. */
  errors: Map<string, string>;
}

/**
 * Write each named image into the running circuit.
 *
 * Nothing throws. A name the artifact does not declare, an image that does not
 * parse, a runtime that refuses the load: each is a message against that name,
 * and the other memories still load. A card with one bad image should show the
 * rest of its circuit rather than nothing.
 */
export function loadMemoryImages(
  runtime: MemoryRuntime,
  images: Readonly<Record<string, string>>,
): LoadResult {
  const applied: string[] = [];
  const errors = new Map<string, string>();
  const names = Object.keys(images);
  if (names.length === 0) return { applied, errors };

  const found = new Map(runtime.memories().map((m) => [m.name, m]));
  for (const name of names) {
    const target = found.get(name);
    if (!target) {
      errors.set(name, `${name} is not a memory in this circuit.`);
      continue;
    }
    const parsed = parseRomImage(images[name], {
      name,
      kind: target.info.kind,
      width: target.info.width,
      addrWidth: target.info.addrWidth,
    });
    if (!parsed.ok) {
      errors.set(name, parsed.message);
      continue;
    }
    if (parsed.words === 0) continue; // an empty image asks for nothing

    const rc = runtime.loadMemImage(target.id, parsed.bytes);
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
