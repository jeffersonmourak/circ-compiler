// The playground's pipeline: what the status bar says, and (from slice 5) the
// two debounced stages that drive it.
//
// Pure by design. The island cannot be imported by a test, so anything that
// could be wrong about a number or a precedence rule lives here instead of in
// a closure.

export const ANALYZE_DEBOUNCE_MS = 120;
export const BUILD_DEBOUNCE_MS = 350;

export interface TimerLike {
  setTimeout(fn: () => void, ms: number): number;
  clearTimeout(id: number): void;
}

export type StatusKind = 'idle' | 'loading' | 'compiling' | 'live' | 'error';

export interface StatusInput {
  /** The version handshake resolved. */
  ready: boolean;
  /** The handshake is in flight. */
  loading: boolean;
  analyzing: boolean;
  building: boolean;
  /** From the freshest analysis, or from a status-1 compile body. */
  errors: number;
  warnings: number;
  /** Captured at reply time: the worker transfers the buffer, so a detached
   *  view would report 0. */
  artifactBytes: number | null;
  /** The outputs on screen are older than the current source. */
  stale: boolean;
  /** A transport error or a refusal. Outranks everything else. */
  failure: string | null;
}

export interface StatusView {
  kind: StatusKind;
  label: string;
  detail: string;
}

export function plural(n: number, word: string): string {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}

export function formatBytes(n: number): string {
  if (!Number.isFinite(n) || n < 0) return '0 B';
  if (n < 1024) return `${Math.round(n)} B`;
  return `${(n / 1024).toFixed(1)} KB`;
}

const staleHint = (stale: boolean): string => (stale ? 'showing the last good build' : '');

const join = (...parts: string[]): string => parts.filter(Boolean).join(' · ');

/**
 * One view of the whole pipeline, in a fixed precedence: a failure outranks
 * everything (it is the only state a reader can do nothing about), then the
 * handshake, then work in flight, then diagnostics, then a good build.
 */
export function statusFor(input: StatusInput): StatusView {
  if (input.failure) {
    return { kind: 'error', label: 'Error', detail: input.failure };
  }
  if (input.loading) {
    return { kind: 'loading', label: 'Loading the compiler…', detail: '' };
  }
  if (!input.ready) {
    return { kind: 'idle', label: 'Idle', detail: 'Type to compile.' };
  }
  if (input.analyzing || input.building) {
    return { kind: 'compiling', label: 'Compiling…', detail: staleHint(input.stale) };
  }
  if (input.errors > 0) {
    return {
      kind: 'error',
      label: 'Error',
      detail: join(
        plural(input.errors, 'error'),
        input.warnings > 0 ? plural(input.warnings, 'warning') : '',
        staleHint(input.stale),
      ),
    };
  }
  return {
    kind: 'live',
    label: 'Live',
    detail: join(
      input.artifactBytes === null ? '' : formatBytes(input.artifactBytes),
      input.warnings > 0 ? plural(input.warnings, 'warning') : '',
      staleHint(input.stale),
    ),
  };
}

/**
 * Whether to spend a compile. False only when a *fresh* analysis — one for
 * this exact document — already reported errors. A stale or missing analysis
 * compiles anyway, so no ordering assumption between the two debounces can
 * wedge the pipeline.
 */
export function shouldCompile(analysis: { doc: number; errors: number } | null, doc: number): boolean {
  if (!analysis) return true;
  if (analysis.doc !== doc) return true;
  return analysis.errors === 0;
}

/**
 * Whether the outputs must be cleared rather than dimmed. Only a change to the
 * file NAME list qualifies: an edit inside a body leaves the last good preview,
 * table and canvas meaningful, while a renamed, added, removed or reordered
 * file makes them describe a project that no longer exists.
 */
export function outputsShouldClear(prev: readonly string[], next: readonly string[]): boolean {
  if (prev.length !== next.length) return true;
  for (let i = 0; i < prev.length; i += 1) if (prev[i] !== next[i]) return true;
  return false;
}
