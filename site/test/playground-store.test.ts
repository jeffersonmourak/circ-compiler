// The store's failure paths are the point: a private window, a corrupt
// envelope, a full quota. All three are silent in a browser and none can be
// reached from a real one on demand, so they are driven here against an
// injected storage and a fake clock.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
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
      ['activeFile', 'activeId', 'dataOpen', 'dataPanel', 'drawerHeight', 'footer', 'layout', 'scratch', 'settings', 'version', 'view', 'ws'].sort(),
    );
    expect(env.version).toBe(2);
    expect(env.settings.truthTableCap).toBe(12);
    expect(env.settings.format).toBe('json');
    expect(env.view).toBe('schematic');
    expect(env.dataOpen).toBe(false);
    expect(env.dataPanel).toEqual({});
    expect(env.drawerHeight).toBe(320);
    expect(env.footer).toEqual({ open: false, tab: 'diagnostics' });
    expect(env.layout).toEqual({ sourceWidth: 480, ratios: {} });
    // The reader's own projects open; every catalogue group starts shut, and
    // whichever one holds the open project is revealed at load.
    expect(env.ws).toEqual({ expanded: ['tour', 'examples', 'yours'] });
    // normalize is a fixed point on its own output.
    const round = normalize(JSON.parse(JSON.stringify(env)));
    expect(round.note).toBeNull();
    expect(round.envelope).toEqual(env);
  });

  test('panel positions round-trip, default under v2, and drop invalid entries', () => {
    const raw = {
      ...defaultEnvelope(), dataOpen: true,
      scratch: [{ id: 'scratch:abc', name: 'mine', source: 'input a\n', updatedAt: 1 }],
      dataPanel: { 'scratch:abc': { x: 10, y: 20 }, 'example:half-adder': { x: 800, y: -10 } },
    };
    expect(normalize(JSON.parse(JSON.stringify(raw))).envelope).toEqual(raw);
    const missing = { ...raw } as Record<string, unknown>;
    delete missing.dataPanel;
    expect(normalize(missing).envelope.dataPanel).toEqual({});
    expect(normalize(missing).note).toBeNull();
    const invalid = normalize({ ...raw, dataPanel: {
      ...raw.dataPanel, nope: { x: 1, y: 2 }, 'scratch:gone': { x: 1, y: 2 },
      'example:bad': { x: NaN, y: 2 }, 'tour:bad': { x: 0, y: Infinity },
      'example:': { x: 1, y: 2 }, 'tour:2': { x: '1', y: 2 },
    } });
    expect(invalid.envelope.dataPanel).toEqual(raw.dataPanel);
    expect(invalid.envelope.scratch).toEqual(raw.scratch);
    expect(invalid.note).toBeNull();
  });

  test('drawer height keeps intent and replaces the old share', () => {
    for (const drawerHeight of [160, 480, 2000]) expect(normalize({ ...defaultEnvelope(), drawerHeight }).envelope.drawerHeight).toBe(drawerHeight);
    for (const drawerHeight of [undefined, null, -1, 0, Infinity, '480']) expect(normalize({ ...defaultEnvelope(), drawerHeight }).envelope.drawerHeight).toBe(320);
    const migrated = normalize({ version: 1, layout: { ratios: { drawer: 0.62 } } });
    expect(migrated.envelope.drawerHeight).toBe(320);
    expect(migrated.envelope.layout.ratios).toEqual({});
    expect(migrated.note).toBeNull();
  });

  test('unknown keys are dropped', () => {
    const raw = { ...defaultEnvelope(), sneaky: 'value', settings: { expand_macros: true } };
    const { envelope } = normalize(raw);
    expect('sneaky' in envelope).toBe(false);
    // A snake_case key must never survive into anything option-shaped.
    expect(JSON.stringify(envelope)).not.toContain('expand_macros');
    expect(envelope.settings).toEqual(defaultEnvelope().settings);
  });

  test('a version-1 envelope migrates, and keeps every project', () => {
    // A literal envelope as `writeEnvelope` wrote it on main at 59e884c, not
    // one built from today's defaults: the point is what the old writer put
    // there. Version 1 is the one schema a reader's browser can hold from
    // before the bench, so a reset here would cost them their projects.
    const raw = JSON.parse(readFileSync(resolve(import.meta.dir, 'fixtures', 'store', 'envelope-v1.json'), 'utf8'));
    const { envelope, note } = normalize(raw);
    expect(note).toBeNull();
    expect(envelope.version).toBe(2);
    expect(envelope.scratch.map((p) => p.name)).toEqual(['my adder', 'scratch two']);
    expect(envelope.activeId).toBe('scratch:1757500000000-abc123');
    expect(envelope.activeFile).toBe('main.circ');
    expect(envelope.settings.valueFormat).toBe('hex');
    expect(envelope.settings.truthTableCap).toBe(10);
    expect(envelope.settings.romImages).toEqual({ code: '0a0b' });
    expect(envelope.ws).toEqual({ expanded: ['yours', 'examples'] });
    // The Data tab was a face of the live session, so it lands on the live
    // view, with the panel open over it.
    expect(envelope.view).toBe('live');
    expect(envelope.dataOpen).toBe(true);
    expect(normalize({ ...raw, tab: 'simulate' }).envelope.dataOpen).toBe(false);
    expect(envelope.footer).toEqual({ open: true, tab: 'settings' });
    // The main splitter's share is gone; the drawer's rides through.
    expect(envelope.layout).toEqual({ sourceWidth: 480, ratios: {} });
    expect(envelope.drawerHeight).toBe(320);
    expect('tab' in envelope).toBe(false);
    expect('dock' in envelope).toBe(false);
    // The rest of the map, and a version-1 body with nothing but its version.
    for (const [tab, view] of [['preview', 'schematic'], ['truth', 'truth'], ['simulate', 'live'], ['diagnostics', 'schematic']] as const) {
      expect(normalize({ ...raw, tab }).envelope.view).toBe(view);
    }
    const bare = normalize({ version: 1 });
    expect(bare.note).toBeNull();
    expect(bare.envelope).toEqual(defaultEnvelope());
  });

  test('version mismatch and corruption reset', () => {
    expect(normalize({ ...defaultEnvelope(), version: 3 })).toEqual({
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

    // A view this code does not have falls back; the old tab names are views
    // only through the migrator, never at version 2.
    expect(normalize({ ...defaultEnvelope(), view: 'nope' }).envelope.view).toBe('schematic');
    expect(normalize({ ...defaultEnvelope(), view: 'data' }).envelope.view).toBe('schematic');
    expect(normalize({ ...defaultEnvelope(), view: 'truth' }).envelope.view).toBe('truth');
    // The panel's flag is a boolean or nothing.
    expect(normalize({ ...defaultEnvelope(), dataOpen: 'yes' }).envelope.dataOpen).toBe(false);
    expect(normalize({ ...defaultEnvelope(), dataOpen: true }).envelope.dataOpen).toBe(true);

    // The footer defaults field by field.
    const noFooter = { ...defaultEnvelope() } as Record<string, unknown>;
    delete noFooter.footer;
    expect(normalize(noFooter).envelope.footer).toEqual({ open: false, tab: 'diagnostics' });
    expect(normalize({ ...defaultEnvelope(), footer: 'nope' }).envelope.footer).toEqual({ open: false, tab: 'diagnostics' });
    expect(normalize({ ...defaultEnvelope(), footer: { open: true } }).envelope.footer).toEqual({
      open: true,
      tab: 'diagnostics',
    });
    expect(normalize({ ...defaultEnvelope(), footer: { tab: 'settings' } }).envelope.footer).toEqual({
      open: false,
      tab: 'settings',
    });
    // A panel the footer does not have falls back without touching `open`.
    expect(normalize({ ...defaultEnvelope(), footer: { open: true, tab: 'memory' } }).envelope.footer).toEqual({
      open: true,
      tab: 'diagnostics',
    });

    // The source column: whole pixels the bench can show, else the default.
    const width = (v: unknown) => normalize({ ...defaultEnvelope(), layout: { sourceWidth: v, ratios: {} } }).envelope.layout.sourceWidth;
    expect(width(640)).toBe(640);
    expect(width(640.4)).toBe(640);
    expect(width(100)).toBe(480);
    expect(width(9000)).toBe(480);
    expect(width('x')).toBe(480);
    expect(width(Number.NaN)).toBe(480);
    const noLayout = { ...defaultEnvelope() } as Record<string, unknown>;
    delete noLayout.layout;
    expect(normalize(noLayout).envelope.layout).toEqual({ sourceWidth: 480, ratios: {} });

    // The explorer's expansion set: ids only, deduped, and defaulted when the
    // envelope predates it. An id naming nothing is harmless — it is never read.
    const noWs = { ...defaultEnvelope() } as Record<string, unknown>;
    delete noWs.ws;
    expect(normalize(noWs).envelope.ws).toEqual({ expanded: ['tour', 'examples', 'yours'] });
    expect(normalize({ ...defaultEnvelope(), ws: 'nope' }).envelope.ws).toEqual({ expanded: ['tour', 'examples', 'yours'] });
    for (const version of [1, 2]) {
      const result = normalize({ ...defaultEnvelope(), version, ws: { expanded: ['building-blocks', 'yours', 'advanced', 'introduction'] } });
      expect(result.envelope.ws.expanded).toEqual(['examples', 'yours']);
      expect(result.note).toBeNull();
      expect(normalize(result.envelope).envelope.ws).toEqual(result.envelope.ws);
    }
    expect(normalize({ ...defaultEnvelope(), ws: { expanded: [] } }).envelope.ws).toEqual({ expanded: [] });
    expect(
      normalize({ ...defaultEnvelope(), ws: { expanded: ['a', 'a', 'b', 7, '', null] } }).envelope.ws,
    ).toEqual({ expanded: ['a', 'b'] });
    // A runaway list is capped rather than stored whole.
    const manyIds = Array.from({ length: 500 }, (_, i) => `g${i}`);
    expect(normalize({ ...defaultEnvelope(), ws: { expanded: manyIds } }).envelope.ws.expanded.length)
      .toBeLessThanOrEqual(128);

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
