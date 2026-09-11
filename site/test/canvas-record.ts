// A 2D context that writes down what it was asked to do, and the assets a
// skin needs, as stubs. `bun test` has no canvas; the site's skins draw into
// this instead, and what they drew is compared to a golden op log — so a
// change to a skin is a diff a reviewer can read, not a pixel nobody saw.
//
// Numbers are rounded to three decimals, so a golden does not move with the
// last bits of a float. An image handed to `drawImage` is written as
// `sprite:<name>`, and anything else as its string.

export type OpArg = string | number | boolean | null;
export type Op = OpArg[];

export interface Recording {
  ctx: CanvasRenderingContext2D;
  ops: Op[];
  /** The stable object `ctx.canvas` answers with, for per-canvas state. */
  canvas: { width: number; height: number };
}

function round(v: unknown): OpArg {
  if (typeof v === 'number') return Math.round(v * 1000) / 1000;
  if (typeof v === 'string' || typeof v === 'boolean' || v === null) return v;
  if (Array.isArray(v)) return `[${v.map(round).join(',')}]`;
  if (v && typeof v === 'object' && 'name' in v) return `sprite:${String((v as { name: unknown }).name)}`;
  if (v && typeof v === 'object' && 'getContext' in v) {
    const c = v as unknown as { width: number; height: number };
    return `canvas:${c.width}x${c.height}`;
  }
  return String(v);
}

/**
 * A recording context. Every method call becomes `[name, ...args]`, every
 * property assignment `["set", name, value]`. `measureText` answers with a
 * width of 0.6 cells per character, so text-dependent geometry is stable.
 */
export function recordingContext(cell: number): Recording {
  const ops: Op[] = [];
  const canvas = { width: 0, height: 0 };
  const state: Record<string, unknown> = {};
  const ctx = new Proxy(state, {
    get(target, prop) {
      if (prop === 'canvas') return canvas;
      if (prop === 'measureText') return (text: string) => ({ width: text.length * cell * 0.6 });
      if (typeof prop !== 'string') return undefined;
      if (prop in target) return target[prop];
      return (...args: unknown[]) => {
        ops.push([prop, ...args.map(round)]);
      };
    },
    set(target, prop, value) {
      target[prop as string] = value;
      ops.push(['set', String(prop), round(value)]);
      return true;
    },
  }) as unknown as CanvasRenderingContext2D;
  return { ctx, ops, canvas };
}

export const SPRITE_NAMES = ['AND', 'NAND', 'OR', 'XOR', 'NOT'] as const;

export interface Bounds { l: number; r: number; t: number; b: number; apex: number }

/** What a real sprite measures to, near enough: the OR's back apex is in from its left edge. */
export const STUB_BOUNDS: Bounds = { l: 0.2, r: 0.84, t: 0.2, b: 0.8, apex: 0.28 };

export interface StubAssets {
  sprite(name: string): CanvasImageSource | null;
  bounds(name: string): Bounds | null;
  offscreen(width: number, height: number): HTMLCanvasElement;
  /** Every offscreen canvas handed out, with its own recording. */
  offscreens: { width: number; height: number; recording: Recording }[];
  /** How many times each stub method was asked. */
  calls: { sprite: number; bounds: number; offscreen: number };
}

/**
 * Assets as the skins see them, without a page. With `loaded` false every
 * sprite is null, the way the site draws before its PNGs decode; with it true
 * each of the five names answers with a tagged stand-in and fixed bounds.
 */
export function stubAssets(loaded: boolean): StubAssets {
  const offscreens: StubAssets['offscreens'] = [];
  const calls = { sprite: 0, bounds: 0, offscreen: 0 };
  const known = (name: string) => loaded && (SPRITE_NAMES as readonly string[]).includes(name);
  return {
    calls,
    sprite: (name) => {
      calls.sprite++;
      return known(name) ? ({ width: 100, height: 100, name } as unknown as CanvasImageSource) : null;
    },
    bounds: (name) => {
      calls.bounds++;
      return known(name) ? { ...STUB_BOUNDS } : null;
    },
    offscreen: (width, height) => {
      calls.offscreen++;
      const recording = recordingContext(1);
      const c = { width, height, getContext: () => recording.ctx } as unknown as HTMLCanvasElement;
      offscreens.push({ width, height, recording });
      return c;
    },
    offscreens,
  };
}
