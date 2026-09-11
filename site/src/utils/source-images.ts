import { parseRomImage, type ApplyResult } from './rom-image.ts';
import { ComponentKind } from 'circ-renderer/topology';
import type { RuntimeLike } from '../scripts/sim-session.ts';

/** A source image belongs to a project, file and declaration, not an instance. */
export type SourceImages = Record<string, Record<string, string>>;
export const sourceImageKey = (project: string | null, file: string): string => JSON.stringify([project, file]);

export function normalizeSourceImages(raw: unknown): SourceImages {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
  return Object.fromEntries(Object.entries(raw).flatMap(([key, value]) => {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return [];
    return [[key, Object.fromEntries(Object.entries(value).filter((entry): entry is [string, string] => typeof entry[1] === 'string'))]];
  }));
}

export interface ImportedImages {
  /** Captured from analysis of the exact request that produced the artifact. */
  files: ReadonlyMap<number, string>;
  images: ReadonlyMap<string, ReadonlyMap<string, string>>;
}

/** Resolve every flattened instance by its innermost source file and runtime ID. */
export function applyImportedImages(runtime: RuntimeLike, source: ImportedImages): ApplyResult {
  const result: ApplyResult = { applied: [], errors: new Map() };
  for (const c of runtime.topology.components) {
    if (c.kind !== ComponentKind.Rom || !c.memory || c.origin.length === 0) continue;
    const frame = c.origin[c.origin.length - 1] as { targetFile?: number };
    const file = frame.targetFile === undefined ? undefined : source.files.get(frame.targetFile);
    const text = file === undefined ? undefined : source.images.get(file)?.get(c.name);
    if (text === undefined) continue;
    const name = `${file}:${c.name}#${c.id}`;
    const parsed = parseRomImage(text, { name: c.name, kind: 'rom', width: c.width, addrWidth: c.memory.addrWidth });
    if (!parsed.ok) { result.errors.set(name, parsed.message); continue; }
    const rc = parsed.words === 0 ? runtime.clearMem(c.id) : runtime.loadMemImage(c.id, parsed.bytes);
    if (rc !== 0) result.errors.set(name, `${name} was refused by the runtime (code ${rc}).`);
    else result.applied.push(name);
  }
  return result;
}
