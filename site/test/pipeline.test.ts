// The status bar is a pure function of one record, so its precedence — which
// state wins when several are true at once — is provable without a browser.
import { describe, expect, test } from 'bun:test';
import {
  formatBytes,
  outputsShouldClear,
  plural,
  shouldCompile,
  statusFor,
  type StatusInput,
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
