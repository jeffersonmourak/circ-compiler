import { decodeFullTopology } from 'circ-renderer/topology';
import type { CircRuntime } from 'circ-renderer';
import { NoSettleError } from './simulation-error.ts';

/** Use the renderer's public constructor, retaining the additive WASM status
 * query so a settle-budget trap is distinguishable from an unrelated trap.
 * Loads floating; SimSession owns preloads, boot-low, and reset policy. */
export async function loadSimulationRuntime(Runtime: typeof CircRuntime, bytes: Uint8Array): Promise<CircRuntime> {
  const module = await WebAssembly.compile(bytes as BufferSource);
  const instance = await WebAssembly.instantiate(module, {
    env: { debugEnabled: () => 0, onDebugLog: () => {}, onStateChange: () => {} },
  });
  const w = instance.exports as unknown as {
    memory: WebAssembly.Memory; topology_alloc(size: number): number; init(): void;
    getSimulationStatus?: () => number;
  };
  const min = WebAssembly.Module.customSections(module, 'circ.topology.v0.min')[0];
  const full = WebAssembly.Module.customSections(module, 'circ.topology.v0.full')[0];
  if (!min || !full) throw new Error('Runtime topology sections are missing.');
  const ptr = w.topology_alloc(min.byteLength);
  if (ptr <= 0) throw new Error('Runtime topology allocation failed.');
  new Uint8Array(w.memory.buffer, ptr, min.byteLength).set(new Uint8Array(min));
  w.init();
  if (w.getSimulationStatus?.() === -1) throw new Error('Runtime initialization failed.');
  const runtime = new Runtime(instance, bytes, decodeFullTopology(new Uint8Array(full)));
  // Canvas drives use this same runtime instance, so they also get typed errors.
  for (const method of ['setValue', 'run', 'writeMemWord', 'clearMem', 'loadMemImage'] as const) {
    const original = runtime[method];
    Object.defineProperty(runtime, method, { configurable: true, value: (...args: unknown[]) => {
      if (w.getSimulationStatus?.() === 1) throw new NoSettleError();
      try {
        return Reflect.apply(original, runtime, args);
      } catch (error) {
        if (w.getSimulationStatus?.() === 1) throw new NoSettleError();
        throw error;
      }
    } });
  }
  return runtime;
}
