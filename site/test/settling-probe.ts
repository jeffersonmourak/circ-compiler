// Run only in the subprocess owned by bounded-settling.test.ts: a regression
// must time out the child rather than block the test runner's JavaScript thread.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { CircRuntime } from 'circ-renderer';
import { callOp, instantiateLibcirc } from '../src/scripts/libcirc-abi.ts';
import { SimSession } from '../src/scripts/sim-session.ts';
import { execute } from '../src/scripts/sim-executor.ts';
import { loadSimulationRuntime } from '../src/scripts/simulation-runtime.ts';
import { examples } from '../src/content/examples.ts';
import { rowsForPins } from '../src/scripts/truth-view.ts';

const lib = await instantiateLibcirc(readFileSync(resolve(import.meta.dir, '../public/wasm/libcirc.wasm')));
const request = (source: string) => ({ root: '/playground/main.circ', files: { '/playground/main.circ': source } });
const compile = (source: string) => {
  const analysis = callOp(lib, 'analyze', request(source));
  if (analysis.status !== 0 || JSON.parse(new TextDecoder().decode(analysis.bytes)).diagnostics.some((d: { severity: string }) => d.severity === 'error')) throw new Error('Feedback was rejected by validation.');
  const artifact = callOp(lib, 'compile', request(source));
  if (artifact.status !== 0) throw new Error('Feedback was rejected by compilation.');
  return artifact.bytes;
};
const source = (name: string) => readFileSync(resolve(import.meta.dir, '../../tests/fixtures/circuits', name), 'utf8');
const load = (bytes: Uint8Array) => loadSimulationRuntime(CircRuntime, bytes);
const noFiles = { read: () => ({ ok: false as const, error: 'unavailable' }), write: () => ({ ok: false as const, error: 'unavailable' }) };
const feedback = await SimSession.build({ bytes: compile(source('feedback_register.circ')), load });
const events: string[] = [];
feedback.subscribeLifecycle(e => events.push(e.kind));
const transcript: string[] = [];
const start = performance.now();
for (const command of ['set dado 0', 'set clock 0', 'set dado 1', 'set clock 1', 'set clock 0', 'get s', 'run', 'set clock 0', 'reset', 'get s', 'set dado 0', 'set clock 0']) {
  transcript.push(...await execute(feedback, noFiles, command));
}
const elapsedMs = performance.now() - start;
feedback.destroy();

const oscillatorBytes = compile(source('gated_oscillator.circ'));
const oscillator = await SimSession.build({ bytes: oscillatorBytes, load });
oscillator.set('enable', 0n);
// Use the same write-first path as canvas interactions.
let canvasError = '';
try { oscillator.runtime.setValue(oscillator.pins[0].id, 1n, 1n); }
catch (error) { canvasError = (error as Error).message; }
const poisoned = oscillator.failedToSettle;
oscillator.destroy();

const module = await WebAssembly.compile(oscillatorBytes);
const raw = await WebAssembly.instantiate(module, { env: { debugEnabled: () => 0, onDebugLog: () => {} } });
const w = raw.exports as any;
const beforeInit = w.getSimulationStatus();
const topology = new Uint8Array(WebAssembly.Module.customSections(module, 'circ.topology.v0.min')[0]);
const ptr = w.topology_alloc(topology.length);
new Uint8Array(w.memory.buffer, ptr, topology.length).set(topology);
w.init();
const afterInit = w.getSimulationStatus();
w.setPin(0, 0n, 1n);
let trapped = false;
try { w.setPin(0, 1n, 1n); } catch (error) { trapped = error instanceof WebAssembly.RuntimeError; }
const afterFailure = w.getSimulationStatus();
const invalidDefined = String(w.getOutputDefined(3));
let repeatTrapped = false;
try { w.run(); } catch (error) { repeatTrapped = error instanceof WebAssembly.RuntimeError; }

const truth = callOp(lib, 'truth_table', request(source('gated_oscillator.circ')));
const truthError = JSON.parse(new TextDecoder().decode(truth.bytes));
const scratch = await SimSession.build({ bytes: oscillatorBytes, load });
let scratchError = '';
try { rowsForPins(scratch, scratch, 2); }
catch (error) { scratchError = (error as Error).message; }
finally { scratch.destroy(); }
const latch = await SimSession.build({ bytes: compile(examples.find(e => e.slug === 'sr-latch')!.source), load });
const latchValues: string[] = [];
for (const [pin, value] of [['r', 0n], ['s', 1n], ['s', 0n], ['r', 1n], ['r', 0n]] as const) {
  const result = latch.set(pin, value);
  if (!result.ok) throw new Error(JSON.stringify(result));
  const q = latch.get('q');
  latchValues.push(q.ok ? `${q.value.value}/${q.value.defined}` : q.code);
}
latch.destroy();
console.log(JSON.stringify({ transcript, events, elapsedMs, canvasError, poisoned, beforeInit, afterInit, trapped, afterFailure, invalidDefined, repeatTrapped, truthStatus: truth.status, truthError, scratchError, latchValues }));
