import type { VerificationAssertionResult, VerificationCase, VerificationPage, VerificationStepResult, VerificationSummary, WorkInputs } from './playground-contract.ts';
import type { MemRef, PinRef, SimSession } from './sim-session.ts';
import { canonical, imageBytes, parseHex, signal } from './playground-simulation.ts';

export const VERIFICATION_YIELD_ACTIONS = 32;
export const MAX_RETAINED_VERIFICATION_RESULTS = 16;
export const MAX_RETAINED_VERIFICATION_BYTES = 1024 * 1024;
export const MAX_VERIFICATION_RESULT_BYTES = 512 * 1024;

export interface VerificationShape { pins: readonly PinRef[]; memories: readonly MemRef[]; }
export interface VerificationRuntime {
  create(caseInput: VerificationCase): Promise<SimSession>;
  now(): number;
  yield(): Promise<void>;
  cancelled(): boolean;
}
export interface VerificationResult {
  operationId: string; resultId: string; inputs: WorkInputs; imageRevision: string; artifactValidation: VerificationPage['artifactValidation'];
  summary: VerificationSummary; steps: VerificationStepResult[];
}

const invalid = (message: string) => ({ ok: false as const, message });
const validId = (id: unknown) => typeof id === 'string' && id.length > 0 && id.length <= 80 && !/[\u0000-\u001f\u007f-\u009f]/.test(id);

/** Fully validate before a disposable runtime is allocated. */
export function validateVerification(cases: unknown, shape: VerificationShape) {
  if (!Array.isArray(cases) || cases.length < 1 || cases.length > 128) return invalid('cases must contain 1 to 128 cases.');
  let actions = 0; let assertions = 0; let steps = 0;
  const caseIds = new Set<string>();
  const pin = (name: unknown) => typeof name === 'string' ? shape.pins.find((item) => item.name === name) : undefined;
  const mem = (name: unknown) => typeof name === 'string' ? shape.memories.find((item) => item.name === name) : undefined;
  for (const c of cases as VerificationCase[]) {
    if (!c || !validId(c.id) || caseIds.has(c.id) || (c.initialization !== 'floating' && c.initialization !== 'low') || (c.sourcePreloads !== 'current' && c.sourcePreloads !== 'none') || !Array.isArray(c.steps)) return invalid('A case is malformed.');
    caseIds.add(c.id);
    if ((c.images?.length ?? 0) > 16) return invalid('A case has too many explicit images.');
    const imageNames = new Set<string>();
    for (const image of c.images ?? []) {
      const target = mem(image.memory);
      if (!target || imageNames.has(image.memory) || !imageBytes(image.hex, target).ok) return invalid('An explicit image is invalid.');
      imageNames.add(image.memory);
    }
    const stepIds = new Set<string>();
    for (const step of c.steps) {
      if (!step || !validId(step.id) || stepIds.has(step.id) || !Array.isArray(step.actions) || !Array.isArray(step.expect) || step.actions.length + step.expect.length === 0) return invalid('A step is malformed.');
      stepIds.add(step.id); steps += 1; actions += step.actions.length; assertions += step.expect.length;
      for (const action of step.actions) {
        if (!action || typeof action.kind !== 'string') return invalid('An action is malformed.');
        if (action.kind === 'drive') { const target = pin(action.pin); if (!target || target.kind !== 'in' || parseHex(action.value, target.width) === null || (action.defined !== undefined && parseHex(action.defined, target.width) === null)) return invalid('A drive action is invalid.'); }
        else if (action.kind === 'poke') { const target = mem(action.memory); if (!target || parseHex(action.address) === null || parseHex(action.address)! >= (1n << BigInt(target.addrWidth)) || parseHex(action.value, target.width) === null || (action.defined !== undefined && parseHex(action.defined, target.width) === null)) return invalid('A poke action is invalid.'); }
        else if (action.kind === 'clear') { if (!mem(action.memory)) return invalid('A clear action targets no root memory.'); }
        else if (action.kind === 'load') { const target = mem(action.memory); if (!target || !imageBytes(action.hex, target).ok) return invalid('A load action is invalid.'); }
        else if (action.kind !== 'reset') return invalid('An action kind is invalid.');
      }
      for (const expectation of step.expect) {
        if (!expectation || (expectation.kind !== 'pin' && expectation.kind !== 'memory')) return invalid('An expectation is malformed.');
        const target = expectation.kind === 'pin' ? pin(expectation.name) : mem(expectation.name);
        if (!target || parseHex(expectation.value, target.width) === null || (expectation.defined !== undefined && parseHex(expectation.defined, target.width) === null)) return invalid('An expectation is invalid.');
        if (expectation.kind === 'memory') {
          const memory = mem(expectation.name);
          if (!memory || parseHex(expectation.address) === null || parseHex(expectation.address)! >= (1n << BigInt(memory.addrWidth))) return invalid('A memory expectation address is invalid.');
        }
      }
    }
  }
  if (steps < 1 || steps > 512 || actions > 2048 || assertions > 2048) return invalid('Verification aggregate limits were exceeded.');
  return { ok: true as const, caseCount: cases.length, stepCount: steps, assertionCount: assertions };
}

function expected(kind: 'pin' | 'memory', name: string, address: string | null, value: string, defined: string | undefined, width: number) {
  const v = parseHex(value, width)!; const d = defined === undefined ? (1n << BigInt(width)) - 1n : parseHex(defined, width)!;
  return { kind, name, address, state: canonical(v, d, width) };
}

async function applyImages(session: SimSession, c: VerificationCase) {
  for (const image of c.images ?? []) {
    const mem = session.mems.find((item) => item.name === image.memory)!;
    const bytes = imageBytes(image.hex, mem);
    if (!bytes.ok) throw new Error(bytes.message);
    const loaded = session.loadImage(mem.name, bytes.bytes);
    if (!loaded.ok) throw new Error(`${loaded.code} ${loaded.arg}`);
  }
}

export async function executeVerification(
  operationId: string,
  inputs: WorkInputs,
  imageRevision: string,
  cases: readonly VerificationCase[],
  runtime: VerificationRuntime,
  timeoutMs: number,
  stopOnFailure: boolean,
): Promise<VerificationResult> {
  const started = runtime.now();
  const steps: VerificationStepResult[] = [];
  let passed = 0; let failed = 0; let halted = false; let actionCount = 0; let terminal: VerificationSummary['state'] = 'passed';
  for (const c of cases) {
    if (halted) { for (const step of c.steps) steps.push({ caseId: c.id, stepId: step.id, state: 'not_run', actionsCompleted: 0, assertions: [] }); continue; }
    let session: SimSession | null = null;
    try {
      session = await runtime.create(c);
      await applyImages(session, c);
      if (c.initialization === 'low') {
        for (const pin of session.pins) if (pin.kind === 'in') {
          const set = session.set(pin.name, 0n);
          if (!set.ok) throw new Error(`${set.code} ${set.arg}`);
        }
      }
      for (const step of c.steps) {
        if (halted) { steps.push({ caseId: c.id, stepId: step.id, state: 'not_run', actionsCompleted: 0, assertions: [] }); continue; }
        let completed = 0; let actionError = false;
        for (const action of step.actions) {
          let result: { ok: boolean; code?: string; arg?: string } = { ok: true };
          if (action.kind === 'drive') result = session.set(action.pin, parseHex(action.value)!, action.defined === undefined ? undefined : parseHex(action.defined)!);
          else if (action.kind === 'poke') result = session.poke(action.memory, parseHex(action.address)!, parseHex(action.value)!, action.defined === undefined ? undefined : parseHex(action.defined)!);
          else if (action.kind === 'clear') result = session.clear(action.memory);
          else if (action.kind === 'load') { const mem = session.mems.find((item) => item.name === action.memory)!; const bytes = imageBytes(action.hex, mem); result = bytes.ok ? session.loadImage(action.memory, bytes.bytes) : { ok: false, code: 'E_MEMFMT', arg: bytes.message }; }
          else { await session.reset(); await applyImages(session, c); }
          completed += 1; actionCount += 1;
          if (!result.ok) { actionError = true; terminal = 'error'; break; }
          if (actionCount % VERIFICATION_YIELD_ACTIONS === 0) await runtime.yield();
          if (runtime.cancelled()) { terminal = 'cancelled'; halted = true; break; }
          if (runtime.now() - started >= timeoutMs) { terminal = 'timed_out'; halted = true; break; }
        }
        if (actionError) { steps.push({ caseId: c.id, stepId: step.id, state: 'error', actionsCompleted: completed, assertions: [] }); if (stopOnFailure) halted = true; continue; }
        if (halted) { steps.push({ caseId: c.id, stepId: step.id, state: 'not_run', actionsCompleted: completed, assertions: [] }); continue; }
        const assertions: VerificationAssertionResult[] = [];
        for (let index = 0; index < step.expect.length; index += 1) {
          const exp = step.expect[index]!;
          const target = exp.kind === 'pin' ? session.pins.find((item) => item.name === exp.name)! : session.mems.find((item) => item.name === exp.name)!;
          const address = exp.kind === 'memory' ? exp.address : null;
          const wanted = expected(exp.kind, exp.name, address, exp.value, exp.defined, target.width);
          const actualRead = exp.kind === 'pin' ? session.get(exp.name) : session.peek(exp.name, parseHex(exp.address)!);
          if (!actualRead.ok) { assertions.push({ expectationIndex: index, expected: wanted, actual: null, passed: false, error: { simCode: actualRead.code, arg: actualRead.arg } }); failed += 1; terminal = 'error'; continue; }
          const actual = { kind: exp.kind, name: exp.name, address, state: signal(actualRead.value, target.width) };
          const ok = actual.state.value === wanted.state.value && actual.state.defined === wanted.state.defined;
          assertions.push({ expectationIndex: index, expected: wanted, actual, passed: ok, error: null });
          if (ok) passed += 1; else { failed += 1; terminal = terminal === 'passed' ? 'failed' : terminal; if (stopOnFailure) halted = true; }
          if (halted) break;
        }
        steps.push({ caseId: c.id, stepId: step.id, state: actionError ? 'error' : assertions.some((item) => !item.passed) ? 'failed' : 'passed', actionsCompleted: completed, assertions });
      }
    } catch {
      terminal = 'error';
      const first = c.steps.find((step) => !steps.some((item) => item.caseId === c.id && item.stepId === step.id));
      if (first) steps.push({ caseId: c.id, stepId: first.id, state: 'error', actionsCompleted: 0, assertions: [] });
      halted = stopOnFailure;
    } finally { session?.destroy(); }
  }
  for (const c of cases) for (const step of c.steps) if (!steps.some((item) => item.caseId === c.id && item.stepId === step.id)) steps.push({ caseId: c.id, stepId: step.id, state: 'not_run', actionsCompleted: 0, assertions: [] });
  const summary: VerificationSummary = { operationId, state: terminal, cases: cases.length, steps: steps.length, assertions: passed + failed, passedAssertions: passed, failedAssertions: failed, notRunSteps: steps.filter((step) => step.state === 'not_run').length, elapsedMs: Math.max(0, runtime.now() - started) };
  return { operationId, resultId: `${operationId}:result`, inputs, imageRevision, artifactValidation: { operationId, inputs, counts: null }, summary, steps };
}

export class VerificationResults {
  private readonly values = new Map<string, VerificationResult>();
  admit(result: VerificationResult): boolean {
    const bytes = new TextEncoder().encode(JSON.stringify(result)).byteLength;
    if (bytes > MAX_VERIFICATION_RESULT_BYTES) return false;
    this.values.set(result.operationId, result);
    while (this.values.size > MAX_RETAINED_VERIFICATION_RESULTS || this.totalBytes() > MAX_RETAINED_VERIFICATION_BYTES) this.values.delete(this.values.keys().next().value!);
    return this.values.has(result.operationId);
  }
  get(operationId: string, cursor: string | undefined, limit: number | undefined, observationRevision: string): { ok: true; page: VerificationPage } | { ok: false; reason: 'not_ready' | 'expired' | 'invalid' } {
    const result = this.values.get(operationId);
    if (!result) return { ok: false, reason: 'not_ready' };
    const start = cursor === undefined ? 0 : Number(cursor);
    const count = limit ?? 20;
    if (!Number.isSafeInteger(start) || start < 0 || start > result.steps.length || !Number.isSafeInteger(count) || count < 1 || count > 100) return { ok: false, reason: 'invalid' };
    const records = result.steps.slice(start, start + count);
    return { ok: true, page: { operationId, resultId: result.resultId, observationRevision, inputs: result.inputs, artifactValidation: result.artifactValidation, imageRevision: result.imageRevision, summary: result.summary, steps: records, nextCursor: start + records.length < result.steps.length ? String(start + records.length) : null } };
  }
  private totalBytes() { return [...this.values.values()].reduce((n, value) => n + new TextEncoder().encode(JSON.stringify(value)).byteLength, 0); }
}
