export interface TileMeta { inputs: number; outputs: number; words: number | null }

/** Counts declarations in the single-file sources used by home-page tiles. */
export function tileMeta(source: string): TileMeta {
  if (/^\s*\/\/\s*\S+\.circ\s*$/m.test(source)) throw new Error('Tile metadata requires a single-file source without file markers');
  const text = source.replace(/\/\/[^\n]*/g, '');
  const meta: TileMeta = { inputs: 0, outputs: 0, words: null };
  for (const match of text.matchAll(/^\s*(input|output)\s*(?:\[\d+\])?\s+([^\n]+)/gm)) {
    // Remove bindings before counting names: a concat's commas are not pins.
    const names = match[2].replace(/\([^)]*\)/g, '').split(',').filter(name => name.trim());
    meta[match[1] === 'input' ? 'inputs' : 'outputs'] += names.length;
  }
  for (const match of text.matchAll(/^\s*(?:rom|ram)\s+\w+\s*\[\s*\d+\s*,\s*(\d+)\s*\]/gm)) {
    if (meta.words !== null) throw new Error('Tile metadata supports one memory per source');
    meta.words = 2 ** Number(match[1]);
  }
  return meta;
}

export function tileMetaLabel(meta: TileMeta): string {
  return `${meta.inputs} in · ${meta.outputs} out${meta.words === null ? '' : ` · ${meta.words} words`}`;
}
