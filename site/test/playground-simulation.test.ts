import { describe, expect, test } from 'bun:test';
import { canonical, imageBytes, parseHex, validateDrive } from '../src/scripts/playground-simulation.ts';
import { SimSession } from '../src/scripts/sim-session.ts';
import { AND_GATE, evaluateAnd, stubRuntime } from './sim-stub.ts';

describe('simulation scalar and drive validation', () => {
  test('simulation_scalars_are_lossless_canonical_hex', () => {
    expect(parseHex('0x0')).toBe(0n);
    expect(parseHex('0xffffffffffffffff', 64)).toBe(0xffffffffffffffffn);
    for (const bad of ['0x00', '0X1', '1', '-0x1', '0x', '0x01', 1]) expect(parseHex(bad)).toBeNull();
    expect(canonical(0xffffffffffffffffn, 0xfn, 64)).toEqual({ value: '0xf', defined: '0xf', width: 64 });
    expect(imageBytes('0a0b', { name: 'code', kind: 'rom', width: 8, addrWidth: 2 })).toMatchObject({ ok: true, words: 2 });
    expect(imageBytes('0A', { name: 'code', kind: 'rom', width: 8, addrWidth: 2 }).ok).toBe(false);
  });

  test('drive_validates_all_before_any_write', async () => {
    const runtime = stubRuntime(AND_GATE, evaluateAnd);
    const session = await SimSession.build({ bytes: new Uint8Array([0]), load: async () => runtime });
    const result = validateDrive(session, [{ pin: 'a', value: '0x1' }, { pin: 'b', value: '0x2' }], ['out']);
    expect(result.ok).toBe(false);
    expect(runtime.calls).toEqual([]);
  });

  test('drive_settles_assignments_in_order', async () => {
    const runtime = stubRuntime(AND_GATE, evaluateAnd);
    const session = await SimSession.build({ bytes: new Uint8Array([0]), load: async () => runtime });
    const checked = validateDrive(session, [{ pin: 'a', value: '0x1' }, { pin: 'a', value: '0x0' }, { pin: 'b', value: '0x1' }], ['out']);
    expect(checked.ok).toBe(true);
    if (!checked.ok) return;
    const result = session.eval(checked.assignments, ['out']);
    expect(result.ok && result.values[0]?.value).toMatchObject({ value: 0n, defined: 1n });
    expect(runtime.calls.filter((call) => call === 'run')).toHaveLength(3);
  });
});
