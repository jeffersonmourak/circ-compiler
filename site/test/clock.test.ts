// The Clock panel's arithmetic and the session's batched clock drive.
import { describe, expect, test } from 'bun:test';
import {
  ClockPacer, RateMeter, MAX_GAP_MS, MAX_HZ, MIN_HZ, SLIDER_STEPS,
  clampHz, clockable, formatHz, hzToSlider, nextLevel, parseHz, pickClockPin, sliderToHz,
} from '../src/scripts/clock.ts';
import { SimSession, type SessionEvent } from '../src/scripts/sim-session.ts';
import { AND_GATE, MEMORIES, evaluateAnd, evaluateRom, stubRuntime, type StubRuntime } from './sim-stub.ts';

describe('frequencies', () => {
  test('parse reads plain numbers, units and a k', () => {
    expect(parseHz('2')).toBe(2);
    expect(parseHz(' 0.5 Hz ')).toBe(0.5);
    expect(parseHz('.25')).toBe(0.25);
    expect(parseHz('1k')).toBe(1000);
    expect(parseHz('1.5 kHz')).toBe(1500);
    for (const bad of ['', 'fast', '-1', '0', '1e3', '2 3']) expect(parseHz(bad)).toBeNull();
  });

  test('out-of-range values clamp', () => {
    expect(parseHz('0.001')).toBe(MIN_HZ);
    expect(parseHz('999k')).toBe(MAX_HZ);
    expect(clampHz(5)).toBe(5);
  });

  test('format is short and reads back', () => {
    expect(formatHz(0.5)).toBe('0.5');
    expect(formatHz(1)).toBe('1');
    expect(formatHz(12.34)).toBe('12.3');
    expect(formatHz(250)).toBe('250');
    expect(formatHz(2500)).toBe('2.5k');
    for (const hz of [0.1, 0.75, 3, 60, 440, 2500, 10000]) expect(parseHz(formatHz(hz))).toBe(hz);
  });

  test('the slider is logarithmic and spans the range', () => {
    expect(sliderToHz(0)).toBe(MIN_HZ);
    expect(sliderToHz(SLIDER_STEPS)).toBe(MAX_HZ);
    expect(sliderToHz(SLIDER_STEPS / 5)).toBeCloseTo(1, 5);
    for (const hz of [0.1, 1, 10, 100, 1000, 10000]) expect(sliderToHz(hzToSlider(hz))).toBeCloseTo(hz, 5);
    expect(hzToSlider(0.0001)).toBe(0);
  });
});

describe('pins', () => {
  const pins = [
    { name: 'data', kind: 'in' as const, width: 8 },
    { name: 'reset', kind: 'in' as const, width: 1 },
    { name: 'cpu_clock', kind: 'in' as const, width: 1 },
    { name: 'q', kind: 'out' as const, width: 1 },
  ];

  test('only one-bit inputs can carry a clock', () => {
    expect(clockable(pins).map((p) => p.name)).toEqual(['reset', 'cpu_clock']);
  });

  test('a pin named for a clock is offered first', () => {
    expect(pickClockPin(pins)).toBe('cpu_clock');
    expect(pickClockPin([{ name: 'clk', kind: 'in', width: 1 }])).toBe('clk');
    expect(pickClockPin([{ name: 'a', kind: 'in', width: 1 }, { name: 'b', kind: 'in', width: 1 }])).toBe('a');
    // `clicks` is not a clock.
    expect(pickClockPin([{ name: 'clicks', kind: 'in', width: 1 }, { name: 'ck', kind: 'in', width: 1 }])).toBe('ck');
    expect(pickClockPin([{ name: 'bus', kind: 'in', width: 4 }])).toBeNull();
  });

  test('a pin that is not low goes low first', () => {
    expect(nextLevel(0)).toBe(1);
    expect(nextLevel(1)).toBe(0);
    expect(nextLevel(2)).toBe(0);
  });
});

describe('ClockPacer', () => {
  test('owes two edges per cycle and carries the fraction', () => {
    const pacer = new ClockPacer(1);
    expect(pacer.due(0)).toBe(0);
    expect(pacer.due(200)).toBe(0);
    expect(pacer.due(400)).toBe(0);
    expect(pacer.due(600)).toBe(1);
    expect(pacer.due(800)).toBe(0);
    expect(pacer.due(1000)).toBe(1);
  });

  test('a fast clock owes many edges a frame, without drift', () => {
    const pacer = new ClockPacer(1000);
    pacer.due(0);
    let edges = 0;
    for (let t = 16; t <= 1600; t += 16) edges += pacer.due(t);
    expect(edges).toBe(3200);
  });

  test('a hidden tab is not a backlog', () => {
    const pacer = new ClockPacer(10);
    pacer.due(0);
    expect(pacer.due(60_000)).toBe((MAX_GAP_MS * 2 * 10) / 1000);
  });

  test('a new frequency applies from the next frame', () => {
    const pacer = new ClockPacer(1);
    pacer.due(0);
    pacer.setHz(50);
    expect(pacer.frequency).toBe(50);
    expect(pacer.due(100)).toBe(10);
  });
});

describe('RateMeter', () => {
  test('reports cycles per second over the last second', () => {
    const meter = new RateMeter();
    expect(meter.hz(0)).toBeNull();
    for (let t = 0; t <= 2000; t += 100) meter.add(t, 4);
    expect(meter.hz(2000)).toBeCloseTo(20, 5);
  });
});

describe('SimSession.clock', () => {
  async function session() {
    const made: StubRuntime[] = [];
    const s = await SimSession.build({
      bytes: new Uint8Array([0]),
      load: async () => { const rt = stubRuntime(AND_GATE, evaluateAnd); made.push(rt); return rt; },
    });
    const events: SessionEvent[] = [];
    s.subscribe((e) => events.push(e));
    return { s, events };
  }

  test('a run of edges settles each one and is reported once', async () => {
    const { s, events } = await session();
    s.set('b', 1n);
    events.length = 0;
    const r = s.clock('a', [0, 1, 0, 1]);
    expect(r).toEqual({ ok: true, edges: 4 });
    expect(events).toEqual([
      { kind: 'drive', names: ['a'], assigns: [{ name: 'a', value: 1n, defined: 1n }], origin: 'clock', edges: 4 },
    ]);
    const out = s.get('out');
    expect(out.ok && out.value.value).toBe(1n);
  });

  test('the caller can end a run early, after at least one edge', async () => {
    const { s, events } = await session();
    let asked = 0;
    const r = s.clock('a', [0, 1, 0, 1, 0], () => { asked += 1; return asked >= 2; });
    expect(r).toEqual({ ok: true, edges: 2 });
    expect(events.at(-1)).toMatchObject({ origin: 'clock', edges: 2, assigns: [{ value: 1n }] });
  });

  test('refusals drive nothing and report nothing', async () => {
    const { s, events } = await session();
    expect(s.clock('out', [1])).toMatchObject({ ok: false, code: 'E_NOTIN' });
    expect(s.clock('nope', [1])).toMatchObject({ ok: false, code: 'E_NOPIN' });
    expect(s.clock('a', [])).toEqual({ ok: true, edges: 0 });
    expect(events).toEqual([]);
    const wide = await SimSession.build({ bytes: new Uint8Array([0]), load: async () => stubRuntime(MEMORIES, evaluateRom) });
    expect(wide.clock('pc', [1])).toMatchObject({ ok: false, code: 'E_WIDTH' });
  });
});
