import { describe, expect, test } from 'bun:test';
import { executeVerification, validateVerification, VerificationResults } from '../src/scripts/playground-verification.ts';
import { SimSession } from '../src/scripts/sim-session.ts';
import { AND_GATE, evaluateAnd, stubRuntime } from './sim-stub.ts';
import type { VerificationCase } from '../src/scripts/playground-contract.ts';

const shape = { pins: [{ name: 'a', id: 0, width: 1, kind: 'in' as const }, { name: 'b', id: 1, width: 1, kind: 'in' as const }, { name: 'out', id: 3, width: 1, kind: 'out' as const }], memories: [] };
const inputs = { target: { projectId: 'scratch:one', sourceRevision: 'source', entryFile: 'main.circ', targetEpoch: 'target' }, optionsRevision: 'verification', imageRevision: 'image', artifactId: 'artifact', liveStateRevision: null };

describe('isolated verification', () => {
  test('verification_preflight_is_total_and_inert', () => {
    expect(validateVerification([], shape).ok).toBe(false);
    expect(validateVerification([{ id: 'bad\n', initialization: 'low', sourcePreloads: 'none', steps: [] }], shape).ok).toBe(false);
    expect(validateVerification([{ id: 'one', initialization: 'low', sourcePreloads: 'none', steps: [{ id: 'step', actions: [{ kind: 'drive', pin: 'out', value: '0x1' }], expect: [] }] }], shape).ok).toBe(false);
  });

  test('verification_cases_are_independent_steps_are_stateful', async () => {
    const cases: VerificationCase[] = [
      { id: 'low', initialization: 'low', sourcePreloads: 'none', steps: [{ id: 'and', actions: [{ kind: 'drive', pin: 'a', value: '0x1' }, { kind: 'drive', pin: 'b', value: '0x1' }], expect: [{ kind: 'pin', name: 'out', value: '0x1' }] }] },
      { id: 'fresh', initialization: 'floating', sourcePreloads: 'none', steps: [{ id: 'unknown', actions: [], expect: [{ kind: 'pin', name: 'out', value: '0x0', defined: '0x0' }] }] },
    ];
    expect(validateVerification(cases, shape)).toMatchObject({ ok: true, caseCount: 2 });
    const made: ReturnType<typeof stubRuntime>[] = [];
    let time = 0;
    const result = await executeVerification('op', inputs, 'image', cases, {
      create: async () => { const runtime = stubRuntime(AND_GATE, evaluateAnd); made.push(runtime); return SimSession.build({ bytes: new Uint8Array([0]), load: async () => runtime }); },
      now: () => time++, yield: async () => {}, cancelled: () => false,
    }, 100, false);
    expect(result.summary).toMatchObject({ state: 'passed', passedAssertions: 2, failedAssertions: 0 });
    expect(made).toHaveLength(2);
    expect(made.every((runtime) => runtime.destroyed)).toBe(true);
  });

  test('verification_results_are_bounded_and_paged', async () => {
    const cases: VerificationCase[] = [{ id: 'case', initialization: 'low', sourcePreloads: 'none', steps: [{ id: 'one', actions: [], expect: [{ kind: 'pin', name: 'out', value: '0x0' }] }, { id: 'two', actions: [], expect: [{ kind: 'pin', name: 'out', value: '0x0' }] }] }];
    let now = 0;
    const result = await executeVerification('op', inputs, 'image', cases, { create: async () => SimSession.build({ bytes: new Uint8Array([0]), load: async () => stubRuntime(AND_GATE, evaluateAnd) }), now: () => now++, yield: async () => {}, cancelled: () => false }, 100, false);
    const retained = new VerificationResults();
    expect(retained.admit(result)).toBe(true);
    expect(retained.get('op', undefined, 1, 'observation')).toMatchObject({ ok: true, page: { steps: [{ stepId: 'one' }], nextCursor: '1' } });
    expect(retained.get('op', 'wrong', 1, 'observation')).toMatchObject({ ok: false, reason: 'invalid' });
  });
});
