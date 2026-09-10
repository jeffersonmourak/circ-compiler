// The status bar is a pure function of one record, so its precedence — which
// state wins when several are true at once — is provable without a browser.
import { describe, expect, test } from 'bun:test';
import {
  Stage,
  formatBytes,
  outputsShouldClear,
  plural,
  shouldCompile,
  statusFor,
  type StatusInput,
  type TimerLike,
} from '../src/scripts/pipeline.ts';

const base: StatusInput = {
  ready: true,
  loading: false,
  analyzing: false,
  building: false,
  errors: 0,
  warnings: 0,
  artifactBytes: null,
  stale: false,
  failure: null,
};

describe('pipeline status', () => {
  test('a failure outranks every other state', () => {
    const view = statusFor({
      ...base,
      loading: true,
      analyzing: true,
      errors: 3,
      failure: 'compile failed: 5',
    });
    expect(view.kind).toBe('error');
    expect(view.detail).toBe('compile failed: 5');
  });

  test('loading, then idle, then compiling', () => {
    expect(statusFor({ ...base, ready: false, loading: true }).kind).toBe('loading');
    expect(statusFor({ ...base, ready: false }).kind).toBe('idle');
    expect(statusFor({ ...base, analyzing: true }).kind).toBe('compiling');
    expect(statusFor({ ...base, building: true }).kind).toBe('compiling');
    // Work in flight outranks a stale error count from the previous run.
    expect(statusFor({ ...base, building: true, errors: 2 }).kind).toBe('compiling');
  });

  test('errors are pluralised and carry their warnings', () => {
    expect(statusFor({ ...base, errors: 1 }).detail).toBe('1 error');
    expect(statusFor({ ...base, errors: 2 }).detail).toBe('2 errors');
    expect(statusFor({ ...base, errors: 2, warnings: 1 }).detail).toBe('2 errors · 1 warning');
    expect(statusFor({ ...base, errors: 2 }).kind).toBe('error');
  });

  test('live carries the artifact size', () => {
    const view = statusFor({ ...base, artifactBytes: 1434 });
    expect(view.kind).toBe('live');
    expect(view.label).toBe('Live');
    expect(view.detail).toBe('1.4 KB');
    expect(statusFor({ ...base, artifactBytes: 1434, warnings: 2 }).detail).toBe('1.4 KB · 2 warnings');
    // No artifact yet is still Live, just without a size.
    expect(statusFor(base).detail).toBe('');
  });

  test('stale says so, in every state that can be stale', () => {
    expect(statusFor({ ...base, stale: true, artifactBytes: 100 }).detail).toContain(
      'showing the last good build',
    );
    expect(statusFor({ ...base, stale: true, errors: 1 }).detail).toContain('showing the last good build');
    expect(statusFor({ ...base, stale: true, building: true }).detail).toContain(
      'showing the last good build',
    );
    expect(statusFor({ ...base, stale: false, artifactBytes: 100 }).detail).not.toContain('last good');
  });

  test('formatBytes and plural', () => {
    expect(formatBytes(812)).toBe('812 B');
    expect(formatBytes(1434)).toBe('1.4 KB');
    expect(formatBytes(1023)).toBe('1023 B');
    expect(formatBytes(1024)).toBe('1.0 KB');
    expect(formatBytes(0)).toBe('0 B');
    expect(formatBytes(-1)).toBe('0 B');
    expect(formatBytes(Number.NaN)).toBe('0 B');
    expect(plural(1, 'error')).toBe('1 error');
    expect(plural(0, 'error')).toBe('0 errors');
  });
});

describe('pipeline decisions', () => {
  test('shouldCompile is false only for a fresh analysis with errors', () => {
    expect(shouldCompile(null, 5)).toBe(true);
    expect(shouldCompile({ doc: 5, errors: 0 }, 5)).toBe(true);
    expect(shouldCompile({ doc: 5, errors: 2 }, 5)).toBe(false);
    // A stale analysis must not block the build, or one ordering of the two
    // debounces could wedge the pipeline.
    expect(shouldCompile({ doc: 4, errors: 2 }, 5)).toBe(true);
  });

  test('warningsAsErrors makes a warning block the compile too', () => {
    // With the option on the library refuses the same build, so spending the
    // compile only to be told so is pure latency.
    expect(shouldCompile({ doc: 5, errors: 0, warnings: 1 }, 5, false)).toBe(true);
    expect(shouldCompile({ doc: 5, errors: 0, warnings: 1 }, 5, true)).toBe(false);
    // A clean analysis is unaffected either way.
    expect(shouldCompile({ doc: 5, errors: 0, warnings: 0 }, 5, true)).toBe(true);
    expect(shouldCompile({ doc: 5, errors: 0 }, 5, true)).toBe(true);
    // …and a stale one still compiles, whatever the flag says.
    expect(shouldCompile({ doc: 4, errors: 0, warnings: 3 }, 5, true)).toBe(true);
  });

  test('outputsShouldClear only on a file-name change', () => {
    const files = ['half_adder.circ', 'root.circ'];
    expect(outputsShouldClear(files, ['half_adder.circ', 'root.circ'])).toBe(false);
    expect(outputsShouldClear(files, ['half_adder.circ'])).toBe(true);
    expect(outputsShouldClear(files, [...files, 'extra.circ'])).toBe(true);
    expect(outputsShouldClear(files, ['root.circ', 'half_adder.circ'])).toBe(true);
    expect(outputsShouldClear(files, ['ha.circ', 'root.circ'])).toBe(true);
    expect(outputsShouldClear([], [])).toBe(false);
  });
});

/** A clock a test advances by hand. */
function fakeTimers() {
  let next = 1;
  const pending = new Map<number, () => void>();
  const timers: TimerLike & { run(): number } = {
    setTimeout(fn) {
      const id = next++;
      pending.set(id, fn);
      return id;
    },
    clearTimeout(id) {
      pending.delete(id);
    },
    run() {
      const fns = [...pending.values()];
      pending.clear();
      for (const fn of fns) fn();
      return fns.length;
    },
  };
  return timers;
}

describe('pipeline Stage', () => {
  test('five schedules inside the window run once', () => {
    const timers = fakeTimers();
    const stage = new Stage(120, timers);
    const runs: number[] = [];
    for (let i = 0; i < 5; i += 1) stage.schedule((seq) => runs.push(seq));
    expect(runs).toEqual([]);
    expect(stage.pending).toBe(true);
    timers.run();
    expect(runs).toEqual([1]);
    expect(stage.pending).toBe(false);
  });

  test('the sequence is claimed at fire time, not at schedule time', () => {
    const timers = fakeTimers();
    const stage = new Stage(120, timers);
    stage.schedule(() => {});
    // Merely scheduling must not move the counter: a call in flight would be
    // invalidated by a keystroke, and the panes would empty between builds.
    expect(stage.seq).toBe(0);
    timers.run();
    expect(stage.seq).toBe(1);
  });

  test('an in-flight call stays current while a later timer is only pending', () => {
    const timers = fakeTimers();
    const stage = new Stage(120, timers);
    let inFlight = -1;
    stage.schedule((seq) => { inFlight = seq; });
    timers.run();
    expect(stage.isCurrent(inFlight)).toBe(true);

    // A keystroke arrives: a new timer is armed but has not fired.
    stage.schedule(() => {});
    expect(stage.isCurrent(inFlight)).toBe(true);

    // Once it fires, the older call is stale — at every await, not just one.
    timers.run();
    expect(stage.isCurrent(inFlight)).toBe(false);
  });

  test('a second-stage check fails even after the first one passed', () => {
    const timers = fakeTimers();
    const stage = new Stage(350, timers);
    let seq = -1;
    stage.schedule((s) => { seq = s; });
    timers.run();
    // First await boundary: still ours.
    expect(stage.isCurrent(seq)).toBe(true);
    // …a newer run lands between the two awaits…
    stage.schedule(() => {});
    timers.run();
    // …and the follow-on call must be dropped too. This is the guard the
    // langlang playground omits on its second stage.
    expect(stage.isCurrent(seq)).toBe(false);
  });

  test('flush cancels the pending timer and runs now', () => {
    const timers = fakeTimers();
    const stage = new Stage(120, timers);
    const runs: number[] = [];
    stage.schedule((seq) => runs.push(seq));
    stage.flush((seq) => runs.push(seq));
    expect(runs).toEqual([1]);
    expect(timers.run()).toBe(0);
    expect(runs).toEqual([1]);
  });

  test('cancel runs nothing, and claim moves the counter with no timer', () => {
    const timers = fakeTimers();
    const stage = new Stage(120, timers);
    let ran = false;
    stage.schedule(() => { ran = true; });
    stage.cancel();
    expect(timers.run()).toBe(0);
    expect(ran).toBe(false);
    expect(stage.pending).toBe(false);

    const before = stage.seq;
    expect(stage.claim()).toBe(before + 1);
    expect(stage.isCurrent(before)).toBe(false);
  });

  test('the two stages carry independent counters', () => {
    const timers = fakeTimers();
    const analyze = new Stage(120, timers);
    const build = new Stage(350, timers);
    analyze.schedule(() => {});
    timers.run();
    expect(analyze.seq).toBe(1);
    // A tab switch re-uses build.seq rather than claiming, so a compile in
    // flight stays current.
    expect(build.seq).toBe(0);
    expect(build.isCurrent(0)).toBe(true);
  });
});
