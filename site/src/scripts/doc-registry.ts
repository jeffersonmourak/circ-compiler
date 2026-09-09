// Index bookkeeping for the editor's per-file document registry, extracted so
// it can be proven without a browser. `circ-editor.ts` imports the editor
// package, which touches the host at module scope in places `bun test` cannot
// provide, so the arithmetic that decides which document is visible after an
// insert, a removal or a reorder lives here instead.
//
// Opaque in its element type: it moves whatever it is given. The editor stores
// editor states, the island's tab array stores names and bodies, and this
// module knows about neither.

/** What just happened to the array, in terms of positions only. */
export type RegistryOp =
  | { kind: 'insert'; at: number }
  /** `length` is the array's length BEFORE the removal. */
  | { kind: 'remove'; at: number; length: number }
  | { kind: 'move'; from: number; to: number };

const clamp = (n: number, lo: number, hi: number): number => Math.max(lo, Math.min(n, hi));

/** A new array with `item` at `at`; `at` clamps into `[0, items.length]`, so
 *  inserting past the end appends. Never mutates. */
export function insert<T>(items: readonly T[], at: number, item: T): T[] {
  const index = clamp(at, 0, items.length);
  return [...items.slice(0, index), item, ...items.slice(index)];
}

/** A new array without `at`. Out-of-range indices return a copy unchanged, so
 *  a stale index can never silently delete the wrong entry. */
export function remove<T>(items: readonly T[], at: number): T[] {
  if (at < 0 || at >= items.length) return [...items];
  return [...items.slice(0, at), ...items.slice(at + 1)];
}

/** A new array with `from` relocated to `to`; both clamp into range. The
 *  result is always a permutation of the input. */
export function move<T>(items: readonly T[], from: number, to: number): T[] {
  if (items.length === 0) return [];
  const src = clamp(from, 0, items.length - 1);
  const dst = clamp(to, 0, items.length - 1);
  if (src === dst) return [...items];
  const out = [...items];
  const [moved] = out.splice(src, 1);
  out.splice(dst, 0, moved);
  return out;
}

/**
 * Where the active index lands after `op`, on the rule that the previously
 * active ENTRY stays active wherever it moved to. The one case with no such
 * entry is removing the active one, which clamps to the nearest surviving
 * neighbour.
 */
export function activeAfter(active: number, op: RegistryOp): number {
  switch (op.kind) {
    case 'insert':
      // An entry inserted at or before the active one shifts it right.
      return op.at <= active ? active + 1 : active;
    case 'remove': {
      const remaining = Math.max(0, op.length - 1);
      if (remaining === 0) return 0;
      if (active > op.at) return active - 1;
      if (active < op.at) return active;
      return clamp(active, 0, remaining - 1);
    }
    case 'move': {
      if (active === op.from) return op.to;
      let next = active;
      if (op.from < next) next -= 1;
      if (op.to <= next) next += 1;
      return next;
    }
  }
}
