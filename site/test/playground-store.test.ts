// The store's failure paths are the point: a private window, a corrupt
// envelope, a full quota. All three are silent in a browser and none can be
// reached from a real one on demand, so they are driven here against an
// injected storage and a fake clock.
import { describe, expect, test } from 'bun:test';
import {
  MAX_ENVELOPE_BYTES,
  MAX_SCRATCH,
  MAX_SOURCE_BYTES,
  STORE_KEY,
  createStore,
  defaultEnvelope,
  describeNote,
  evictOldest,
  normalize,
  readEnvelope,
  writeEnvelope,
  type PlaygroundEnvelope,
  type ScratchProject,
  type StorageLike,
  type StoreNote,
  type TimerLike,
} from '../src/utils/playground-store.ts';

/** A storage whose failure mode each test chooses. */
function fakeStorage(opts: { throwOnGet?: boolean; failWrites?: number | 'always'; seed?: string } = {}) {
  const map = new Map<string, string>();
  if (opts.seed !== undefined) map.set(STORE_KEY, opts.seed);
  let failsLeft = opts.failWrites === 'always' ? Infinity : (opts.failWrites ?? 0);
  const quota = () => {
    const err = new Error('quota') as Error & { name: string };
    err.name = 'QuotaExceededError';
    return err;
  };
  const storage: StorageLike & { writes: string[] } = {
    writes: [],
    getItem(key) {
      if (opts.throwOnGet) throw new Error('access denied');
      return map.get(key) ?? null;
    },
    setItem(key, value) {
      if (failsLeft > 0) {
        failsLeft -= 1;
        throw quota();
      }
      map.set(key, value);
      storage.writes.push(value);
    },
    removeItem(key) {
      map.delete(key);
    },
  };
  return storage;
}

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

const project = (id: string, updatedAt: number, source = 'input a\n'): ScratchProject => ({
  id: `scratch:${id}`,
  name: id,
  source,
  updatedAt,
});

describe('playground store', () => {
  test('defaults and round-trip', () => {
    const env = defaultEnvelope();
    expect(Object.keys(env).sort()).toEqual(
      ['activeFile', 'activeId', 'dock', 'layout', 'scratch', 'settings', 'tab', 'version'].sort(),
    );
    expect(env.version).toBe(1);
    expect(env.settings.truthTableCap).toBe(12);
    expect(env.settings.format).toBe('json');
    expect(env.tab).toBe('preview');
    expect(env.dock).toEqual({ open: true, tab: 'diagnostics' });
    // normalize is a fixed point on its own output.
    const round = normalize(JSON.parse(JSON.stringify(env)));
    expect(round.note).toBeNull();
    expect(round.envelope).toEqual(env);
  });

  test('unknown keys are dropped', () => {
    const raw = { ...defaultEnvelope(), sneaky: 'value', settings: { expand_macros: true } };
    const { envelope } = normalize(raw);
    expect('sneaky' in envelope).toBe(false);
    // A snake_case key must never survive into anything option-shaped.
    expect(JSON.stringify(envelope)).not.toContain('expand_macros');
    expect(envelope.settings).toEqual(defaultEnvelope().settings);
  });

  test('version mismatch and corruption reset', () => {
    expect(normalize({ ...defaultEnvelope(), version: 2 })).toEqual({
      envelope: defaultEnvelope(),
      note: { kind: 'reset', reason: 'version' },
    });
    expect(normalize('not an object').note).toEqual({ kind: 'reset', reason: 'corrupt' });
    expect(normalize(null).note).toEqual({ kind: 'reset', reason: 'corrupt' });
    // Non-JSON text through the real read path.
    const read = readEnvelope(fakeStorage({ seed: '{{{' }));
    expect(read.envelope).toEqual(defaultEnvelope());
    expect(read.note).toEqual({ kind: 'reset', reason: 'corrupt' });
  });

  test('a throwing storage disables persistence', () => {
    const read = readEnvelope(fakeStorage({ throwOnGet: true }));
    expect(read.envelope).toEqual(defaultEnvelope());
    expect(read.note).toEqual({ kind: 'disabled', reason: 'unavailable' });

    const store = createStore({ storage: null, timers: fakeTimers() });
    expect(store.enabled).toBe(false);
    const notes: StoreNote[] = [];
    store.onNote((n) => notes.push(n));
    expect(notes).toEqual([{ kind: 'disabled', reason: 'unavailable' }]);
  });

  test('normalisation limits', () => {
    const many = Array.from({ length: MAX_SCRATCH + 4 }, (_, i) => project(`p${i}`, i));
    const { envelope } = normalize({ ...defaultEnvelope(), scratch: many });
    expect(envelope.scratch).toHaveLength(MAX_SCRATCH);
    // Newest first, so the trim drops the least recently updated.
    expect(envelope.scratch[0].updatedAt).toBe(many.length - 1);
    expect(envelope.scratch.some((p) => p.updatedAt === 0)).toBe(false);

    // An oversized source drops its project rather than truncating it.
    const huge = project('huge', 99, 'x'.repeat(MAX_SOURCE_BYTES + 1));
    expect(normalize({ ...defaultEnvelope(), scratch: [huge] }).envelope.scratch).toEqual([]);

    // Ratios must be finite and strictly inside (0, 1).
    const ratios = normalize({
      ...defaultEnvelope(),
      layout: { ratios: { main: 0.4, zero: 0, one: 1, nan: Number.NaN, text: '0.5' } },
    }).envelope.layout.ratios;
    expect(ratios).toEqual({ main: 0.4 });

    // Settings clamp and fall back key by key.
    const settings = normalize({
      ...defaultEnvelope(),
      settings: { truthTableCap: 99, format: 'nope', valueFormat: 'hex', expandMacros: 'yes' },
    }).envelope.settings;
    expect(settings.truthTableCap).toBe(24);
    expect(settings.format).toBe('json');
    expect(settings.valueFormat).toBe('hex');
    expect(settings.expandMacros).toBe(false);
    expect(normalize({ ...defaultEnvelope(), settings: { truthTableCap: 0 } }).envelope.settings.truthTableCap).toBe(1);

    // A bad tab falls back.
    expect(normalize({ ...defaultEnvelope(), tab: 'nope' }).envelope.tab).toBe('preview');
    // …and so does the one written by every envelope from before diagnostics
    // left the output pane. This is the real migration, and it is not a reset:
    // the scratch projects in that same envelope must survive it.
    const legacy = normalize({ ...defaultEnvelope(), tab: 'diagnostics', scratch: [project('kept', 5)] });
    expect(legacy.note).toBeNull();
    expect(legacy.envelope.tab).toBe('preview');
    expect(legacy.envelope.scratch.map((p) => p.name)).toEqual(['kept']);

    // The dock defaults field by field, since no envelope written before this
    // change carries one at all.
    const noDock = { ...defaultEnvelope() } as Record<string, unknown>;
    delete noDock.dock;
    expect(normalize(noDock).envelope.dock).toEqual({ open: true, tab: 'diagnostics' });
    expect(normalize({ ...defaultEnvelope(), dock: 'nope' }).envelope.dock).toEqual({ open: true, tab: 'diagnostics' });
    expect(normalize({ ...defaultEnvelope(), dock: { open: false } }).envelope.dock).toEqual({
      open: false,
      tab: 'diagnostics',
    });
    expect(normalize({ ...defaultEnvelope(), dock: { tab: 'settings' } }).envelope.dock).toEqual({
      open: true,
      tab: 'settings',
    });
    // A tab the dock does not have falls back without touching `open`.
    expect(normalize({ ...defaultEnvelope(), dock: { open: false, tab: 'preview' } }).envelope.dock).toEqual({
      open: false,
      tab: 'diagnostics',
    });

    // An activeId naming a scratch project that is gone becomes null.
    expect(normalize({ ...defaultEnvelope(), activeId: 'scratch:missing' }).envelope.activeId).toBeNull();
    // …but a content id is kept, since it names nothing in the envelope.
    expect(normalize({ ...defaultEnvelope(), activeId: 'example:half-adder' }).envelope.activeId).toBe(
      'example:half-adder',
    );
  });

  test('writes are debounced and flushable', () => {
    const storage = fakeStorage();
    const timers = fakeTimers();
    const store = createStore({ storage, timers });

    store.update((d) => { d.layout.ratios.main = 0.3; });
    store.update((d) => { d.layout.ratios.main = 0.4; });
    store.update((d) => { d.layout.ratios.main = 0.5; });
    expect(storage.writes).toHaveLength(0);
    timers.run();
    expect(storage.writes).toHaveLength(1);
    expect(JSON.parse(storage.writes[0]).layout.ratios.main).toBe(0.5);

    store.update((d) => { d.layout.ratios.main = 0.6; });
    store.flush();
    expect(storage.writes).toHaveLength(2);
    // The pending timer was cancelled, so running the clock writes nothing more.
    expect(timers.run()).toBe(0);
    expect(storage.writes).toHaveLength(2);
  });

  test('the envelope cap trims by LRU before writing', () => {
    const storage = fakeStorage();
    const big = 'y'.repeat(MAX_SOURCE_BYTES - 100);
    const env: PlaygroundEnvelope = {
      ...defaultEnvelope(),
      scratch: Array.from({ length: 12 }, (_, i) => project(`p${i}`, i, big)),
    };
    expect(JSON.stringify(env).length).toBeGreaterThan(MAX_ENVELOPE_BYTES);

    const result = writeEnvelope(env, storage);
    expect(result.ok).toBe(true);
    expect(result.note?.kind).toBe('evicted');
    // What survived is the most recently updated.
    expect(env.scratch.every((p) => p.updatedAt >= 0)).toBe(true);
    expect(JSON.stringify(env).length).toBeLessThanOrEqual(MAX_ENVELOPE_BYTES);
    expect(storage.writes).toHaveLength(1);
  });

  test('quota eviction retries exactly once', () => {
    const storage = fakeStorage({ failWrites: 1 });
    const env: PlaygroundEnvelope = {
      ...defaultEnvelope(),
      scratch: [project('old', 1), project('new', 9)],
    };
    const result = writeEnvelope(env, storage);
    expect(result.ok).toBe(true);
    expect(result.note).toEqual({ kind: 'evicted', names: ['old'] });
    expect(env.scratch.map((p) => p.name)).toEqual(['new']);
    expect(storage.writes).toHaveLength(1);
  });

  test('a persistent quota error disables the session', () => {
    const storage = fakeStorage({ failWrites: 'always' });
    const timers = fakeTimers();
    const store = createStore({ storage, timers });
    const notes: StoreNote[] = [];
    store.onNote((n) => notes.push(n));

    store.update((d) => { d.scratch.push(project('a', 1)); });
    timers.run();
    expect(store.enabled).toBe(false);
    expect(notes.filter((n) => n.kind === 'disabled')).toEqual([{ kind: 'disabled', reason: 'quota' }]);

    // Once disabled, further updates attempt no further writes.
    store.update((d) => { d.layout.ratios.main = 0.7; });
    expect(timers.run()).toBe(0);
    expect(storage.writes).toHaveLength(0);
    // …and the in-memory envelope still tracks the change, so the page works.
    expect(store.envelope.layout.ratios.main).toBe(0.7);
  });

  test('nothing left to evict disables rather than looping', () => {
    const storage = fakeStorage({ failWrites: 'always' });
    const result = writeEnvelope(defaultEnvelope(), storage);
    expect(result).toEqual({ ok: false, note: { kind: 'disabled', reason: 'quota' }, skipped: [] });
  });

  test('a non-quota write error disables as unavailable', () => {
    const storage: StorageLike = {
      getItem: () => null,
      setItem: () => { throw new Error('nope'); },
      removeItem: () => {},
    };
    expect(writeEnvelope(defaultEnvelope(), storage)).toEqual({
      ok: false,
      note: { kind: 'disabled', reason: 'unavailable' },
      skipped: [],
    });
  });

  test('evictOldest picks the least recently updated', () => {
    const env: PlaygroundEnvelope = {
      ...defaultEnvelope(),
      scratch: [project('b', 5), project('a', 1), project('c', 9)],
    };
    expect(evictOldest(env)).toBe('a');
    expect(env.scratch.map((p) => p.name)).toEqual(['b', 'c']);
    expect(evictOldest(defaultEnvelope())).toBeNull();
  });

  test('notes buffered before a subscriber arrives are delivered on subscribe', () => {
    const store = createStore({ storage: fakeStorage({ seed: '{{{' }), timers: fakeTimers() });
    const notes: StoreNote[] = [];
    store.onNote((n) => notes.push(n));
    expect(notes).toEqual([{ kind: 'reset', reason: 'corrupt' }]);
  });

  test('describeNote says something a reader can act on', () => {
    expect(describeNote({ kind: 'reset', reason: 'version' })).toContain('older version');
    expect(describeNote({ kind: 'evicted', names: ['brave-otter'] })).toContain('brave-otter');
    expect(describeNote({ kind: 'disabled', reason: 'quota' })).toContain('full');
    expect(describeNote({ kind: 'disabled', reason: 'unavailable' })).toContain('not saving');
  });
});
