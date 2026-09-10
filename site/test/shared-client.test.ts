// One worker per page, not one per editor. Phase 7 mounts several editors on a
// docs page; each spawning its own worker would instantiate libcirc.wasm once
// per editor.
import { describe, expect, test } from 'bun:test';
import { LibcircClient, getSharedClient } from '../src/scripts/libcirc-client.ts';

describe('shared libcirc client', () => {
  test('memoises per URL', () => {
    const a = getSharedClient('/wasm/libcirc.wasm');
    const b = getSharedClient('/wasm/libcirc.wasm');
    expect(a).toBe(b);
    expect(a).toBeInstanceOf(LibcircClient);
  });

  test('different URLs get different clients', () => {
    expect(getSharedClient('/a.wasm')).not.toBe(getSharedClient('/b.wasm'));
  });

  test('construction spawns no worker', () => {
    // `Worker` does not exist under bun test, so merely constructing without
    // throwing is the proof: the worker is spawned lazily, from send().
    expect(() => getSharedClient('/lazy.wasm')).not.toThrow();
    expect(() => new LibcircClient('/lazy2.wasm')).not.toThrow();
  });
});
