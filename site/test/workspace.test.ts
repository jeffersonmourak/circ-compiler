// The workspace model: what a project is, what gets written, and what never
// does. The "no content text in the envelope" case is the load-bearing one —
// a stored copy of an example goes stale the moment the shipped text changes.
import { describe, expect, test } from 'bun:test';
import {
  MAX_SCRATCH,
  MAX_SOURCE_BYTES,
  MAX_ENVELOPE_BYTES,
  NEW_PROJECT_SOURCE,
  STORE_KEY,
  CATALOGUE_GROUPS,
  GROUP_OF_LEVEL,
  buildCatalogue,
  createScratch,
  createStore,
  defaultEnvelope,
  deleteScratch,
  describeNote,
  duplicateScratch,
  evictOldest,
  idKind,
  newScratchId,
  readEnvelope,
  renameScratch,
  resolveInitial,
  resolveSource,
  touchScratch,
  uniqueName,
  writeEnvelope,
  type PlaygroundEnvelope,
  type ScratchProject,
  type StorageLike,
  type StoreNote,
  type TimerLike,
} from '../src/utils/playground-store.ts';
import { readHash, type DecodeResult } from '../src/utils/share-link.ts';
import { splitFiles, joinFiles } from '../src/utils/split-files.ts';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';

const catalogue = buildCatalogue(examples, tour);
const sources = [...examples.map((e) => e.source), ...tour.map((t) => t.source)];

function fakeStorage(opts: { failWrites?: number | 'always' } = {}) {
  const map = new Map<string, string>();
  let failsLeft = opts.failWrites === 'always' ? Infinity : (opts.failWrites ?? 0);
  const storage: StorageLike & { writes: string[] } = {
    writes: [],
    getItem: (k) => map.get(k) ?? null,
    setItem(k, v) {
      if (failsLeft > 0) {
        failsLeft -= 1;
        const err = new Error('quota') as Error & { name: string };
        err.name = 'QuotaExceededError';
        throw err;
      }
      map.set(k, v);
      storage.writes.push(v);
    },
    removeItem: (k) => { map.delete(k); },
  };
  return storage;
}

function fakeTimers() {
  let next = 1;
  const pending = new Map<number, () => void>();
  const timers: TimerLike & { run(): number } = {
    setTimeout(fn) { const id = next++; pending.set(id, fn); return id; },
    clearTimeout(id) { pending.delete(id); },
    run() { const fns = [...pending.values()]; pending.clear(); for (const fn of fns) fn(); return fns.length; },
  };
  return timers;
}

const project = (id: string, updatedAt: number, source = 'input a\n'): ScratchProject => ({
  id: `scratch:${id}`, name: id, source, updatedAt,
});

describe('catalogue', () => {
  test('buildCatalogue yields the 21 shipped items with the expected ids', () => {
    expect(catalogue).toHaveLength(21);
    expect(catalogue.filter((c) => c.group === 'Introduction')).toHaveLength(5);
    expect(catalogue.filter((c) => c.group === 'Building blocks')).toHaveLength(5);
    expect(catalogue.filter((c) => c.group === 'Advanced')).toHaveLength(4);
    expect(catalogue.filter((c) => c.group === 'Tour')).toHaveLength(7);
    expect(catalogue.map((c) => c.id)).toEqual([
      ...examples.map((e) => `example:${e.slug}`),
      ...tour.map((_, i) => `tour:${i + 1}`),
    ]);
    // Labels are the shipped titles, numbered for the tour.
    expect(catalogue[0].label).toBe(examples[0].title);
    expect(catalogue[examples.length].label).toBe(`1. ${tour[0].title}`);
  });

  test('every group is one of the declared ones, in the declared order', () => {
    for (const item of catalogue) expect(CATALOGUE_GROUPS).toContain(item.group);
    // The catalogue is grouped, not interleaved: each group occupies one run.
    const runs = catalogue.map((c) => c.group).filter((g, i, a) => g !== a[i - 1]);
    expect(runs).toEqual([...new Set(runs)]);
    expect(runs).toEqual(CATALOGUE_GROUPS.filter((g) => catalogue.some((c) => c.group === g)));
  });

  test('every example carries a level and every level maps to a group', () => {
    for (const e of examples) {
      expect(Object.keys(GROUP_OF_LEVEL)).toContain(e.level);
      expect(catalogue.find((c) => c.id === `example:${e.slug}`)!.group).toBe(GROUP_OF_LEVEL[e.level]);
    }
  });

  test('no example repeats a tour step, and no slug appears twice', () => {
    // The gallery is a reference and the tour is a lesson; meeting the same
    // circuit twice in one workspace is what this whole tier split undid.
    const tourSources = new Set(tour.map((t) => t.source.trim()));
    for (const e of examples) expect(tourSources.has(e.source.trim())).toBe(false);
    expect(new Set(examples.map((e) => e.slug)).size).toBe(examples.length);
    expect(new Set(examples.map((e) => e.title)).size).toBe(examples.length);
  });

  test('resolveSource returns the shipped source byte for byte', () => {
    for (const item of catalogue) {
      expect(resolveSource(item.id, catalogue, [])).toBe(item.source);
    }
    expect(resolveSource('nope', catalogue, [])).toBeNull();
  });

  test('every catalogue id opens through #pick=', () => {
    for (const item of catalogue) {
      expect(readHash(`#pick=${item.id}`).pick).toBe(item.id);
      expect(resolveSource(item.id, catalogue, [])).toBe(item.source);
    }
  });

  test('idKind classifies the three id shapes', () => {
    expect(idKind('example:half-adder')).toBe('example');
    expect(idKind('tour:5')).toBe('tour');
    expect(idKind('scratch:abc')).toBe('scratch');
    expect(idKind('nope')).toBeNull();
    expect(idKind('')).toBeNull();
  });

  test('newScratchId is unique and well-shaped', () => {
    const a = newScratchId(1000, () => 0.1);
    const b = newScratchId(1000, () => 0.9);
    expect(a.startsWith('scratch:')).toBe(true);
    expect(a).not.toBe(b);
  });
});

describe('scratch CRUD', () => {
  test('uniqueName appends the first free suffix', () => {
    expect(uniqueName('Half-adder', [])).toBe('Half-adder');
    expect(uniqueName('Half-adder', ['Half-adder'])).toBe('Half-adder 2');
    expect(uniqueName('Half-adder', ['Half-adder', 'Half-adder 2'])).toBe('Half-adder 3');
  });

  test('createScratch evicts the least-recently-updated past the cap', () => {
    let list: ScratchProject[] = [];
    let evictedNames: string[] = [];
    for (let i = 0; i < MAX_SCRATCH + 1; i += 1) {
      const r = createScratch(list, { name: `p${i}`, source: NEW_PROJECT_SOURCE, now: i + 1, rand: () => i / 100 });
      list = r.list;
      evictedNames = [...evictedNames, ...r.evicted.map((p) => p.name)];
      expect(r.created).not.toBeNull();
    }
    expect(list).toHaveLength(MAX_SCRATCH);
    // The oldest went, the newest stayed.
    expect(evictedNames).toEqual(['p0']);
    expect(list.some((p) => p.name === `p${MAX_SCRATCH}`)).toBe(true);
  });

  test('createScratch refuses an over-size source rather than storing it', () => {
    const r = createScratch([], { name: 'big', source: 'x'.repeat(MAX_SOURCE_BYTES + 1), now: 1 });
    expect(r.created).toBeNull();
    expect(r.list).toEqual([]);
    expect(r.skipped).toHaveLength(1);
  });

  test('rename, delete and duplicate', () => {
    const list = [project('a', 1), project('b', 2)];
    const renamed = renameScratch(list, 'scratch:a', 'Renamed');
    expect(renamed[0].name).toBe('Renamed');
    expect(renamed[0].source).toBe(list[0].source);
    expect(renamed[1]).toEqual(list[1]);
    // An empty name is refused rather than storing a nameless row.
    expect(renameScratch(list, 'scratch:a', '   ')).toEqual(list);

    expect(deleteScratch(list, 'scratch:a').map((p) => p.id)).toEqual(['scratch:b']);
    expect(deleteScratch(list, 'nope')).toEqual(list);

    const dup = duplicateScratch(list, 'scratch:a', { now: 99, rand: () => 0.5 });
    expect(dup).not.toBeNull();
    expect(dup!.created!.id).not.toBe('scratch:a');
    expect(dup!.created!.name).toBe('a 2');
    expect(dup!.created!.source).toBe(list[0].source);
    expect(dup!.created!.updatedAt).toBe(99);
    expect(duplicateScratch(list, 'nope', { now: 1 })).toBeNull();
  });

  test('touchScratch refuses an over-size source and updates only its own id', () => {
    const list = [project('a', 1), project('b', 2)];
    const big = touchScratch(list, 'scratch:a', 'x'.repeat(33 * 1024), 9);
    expect(big.list).toEqual(list);
    expect(big.skipped).toHaveLength(1);

    const ok = touchScratch(list, 'scratch:a', 'y'.repeat(31 * 1024), 9);
    expect(ok.skipped).toEqual([]);
    expect(ok.list[0].source.length).toBe(31 * 1024);
    expect(ok.list[0].updatedAt).toBe(9);
    // The sibling is referentially unchanged.
    expect(ok.list[1]).toBe(list[1]);
  });
});

describe('eviction keeps the active project', () => {
  test('evictOldest never drops the kept id', () => {
    const env: PlaygroundEnvelope = {
      ...defaultEnvelope(),
      scratch: [project('oldest', 1), project('middle', 5), project('newest', 9)],
    };
    // Without a keep, the oldest goes.
    const copy = { ...env, scratch: [...env.scratch] };
    expect(evictOldest(copy)).toBe('oldest');

    // With the oldest kept, the second-oldest goes instead.
    expect(evictOldest(env, 'scratch:oldest')).toBe('middle');
    expect(env.scratch.map((p) => p.name)).toEqual(['oldest', 'newest']);

    // When only the kept one remains there is nothing to do.
    const solo: PlaygroundEnvelope = { ...defaultEnvelope(), scratch: [project('only', 1)] };
    expect(evictOldest(solo, 'scratch:only')).toBeNull();
    expect(solo.scratch).toHaveLength(1);
  });

  test('writeEnvelope trims until the envelope fits and keeps the active project', () => {
    const storage = fakeStorage();
    const big = 'y'.repeat(MAX_SOURCE_BYTES - 100);
    const env: PlaygroundEnvelope = {
      ...defaultEnvelope(),
      scratch: Array.from({ length: 12 }, (_, i) => project(`p${i}`, i, big)),
      activeId: 'scratch:p0', // the OLDEST, deliberately
    };
    const result = writeEnvelope(env, storage, env.activeId);
    expect(result.ok).toBe(true);
    expect(new TextEncoder().encode(JSON.stringify(env)).length).toBeLessThanOrEqual(MAX_ENVELOPE_BYTES);
    // The project the reader is typing into survived, despite being oldest.
    expect(env.scratch.some((p) => p.id === 'scratch:p0')).toBe(true);
    expect(result.note?.kind).toBe('evicted');
  });

  test('an over-size source is omitted from the write and reported', () => {
    const storage = fakeStorage();
    const env: PlaygroundEnvelope = {
      ...defaultEnvelope(),
      scratch: [project('ok', 1), project('huge', 2, 'x'.repeat(MAX_SOURCE_BYTES + 1))],
    };
    const result = writeEnvelope(env, storage, null);
    expect(result.ok).toBe(true);
    expect(result.skipped.map((p) => p.name)).toEqual(['huge']);
    // Written without it — but still in memory, so the reader keeps typing.
    expect(JSON.parse(storage.writes[0]).scratch.map((p: ScratchProject) => p.name)).toEqual(['ok']);
    expect(env.scratch).toHaveLength(2);
  });

  test('describeNote covers the skipped variant', () => {
    expect(describeNote({ kind: 'skipped', names: ['big'] })).toContain('big');
    expect(describeNote({ kind: 'skipped', names: ['a', 'b'] })).toContain('2 projects');
  });

  test('createStore passes the active id as the kept project', () => {
    const storage = fakeStorage();
    const timers = fakeTimers();
    const store = createStore({ storage, timers });
    const big = 'y'.repeat(MAX_SOURCE_BYTES - 100);
    store.update((d) => {
      d.scratch = Array.from({ length: 12 }, (_, i) => project(`p${i}`, i, big));
      d.activeId = 'scratch:p0';
    });
    timers.run();
    expect(storage.writes).toHaveLength(1);
    expect(JSON.parse(storage.writes[0]).scratch.some((p: ScratchProject) => p.id === 'scratch:p0')).toBe(true);
  });
});

describe('what is never persisted', () => {
  test('a browse-only session stores no content text', () => {
    const storage = fakeStorage();
    const timers = fakeTimers();
    const store = createStore({ storage, timers });
    // Open every catalogue item without editing anything.
    for (const item of catalogue) {
      store.update((d) => {
        d.activeId = item.id;
        d.activeFile = 'main.circ';
      });
    }
    store.flush();
    const written = storage.writes[storage.writes.length - 1];
    for (const source of sources) expect(written).not.toContain(source);
    expect(JSON.parse(written).scratch).toEqual([]);
    expect(JSON.parse(written).activeId).toBe(catalogue[catalogue.length - 1].id);
  });

  test('the marker source round-trips through the store', () => {
    const storage = fakeStorage();
    const timers = fakeTimers();
    const store = createStore({ storage, timers });
    const twoFile = joinFiles(splitFiles(tour[5].source));
    store.update((d) => {
      d.scratch = [{ id: 'scratch:m', name: 'two files', source: twoFile, updatedAt: 1 }];
      d.activeId = 'scratch:m';
    });
    store.flush();
    const back = readEnvelope(storage).envelope;
    expect(resolveSource('scratch:m', catalogue, back.scratch)).toBe(tour[5].source);
  });
});

describe('resolveInitial', () => {
  const env = (over: Partial<PlaygroundEnvelope> = {}): PlaygroundEnvelope => ({ ...defaultEnvelope(), ...over });
  const okDecode = (source: string): DecodeResult => ({ ok: true, key: 'src', source });
  const badDecode: DecodeResult = { ok: false, reason: 'bad-deflate' };
  const defaultId = catalogue[0].id;

  test('a decoded share beats a stored active project', () => {
    const r = resolveInitial({
      intent: readHash('#src=AAA'),
      decoded: okDecode('input a\n'),
      env: env({ activeId: 'example:half-adder' }),
      catalogue,
      defaultId,
    });
    expect(r.outcome).toEqual({ kind: 'share', source: 'input a\n', key: 'src' });
    expect(r.note).toBeNull();
  });

  test('a known pick beats a stored active project', () => {
    const r = resolveInitial({
      intent: readHash('#pick=tour:5'),
      decoded: null,
      env: env({ activeId: 'example:half-adder' }),
      catalogue,
      defaultId,
    });
    expect(r.outcome.kind).toBe('pick');
    expect(r.note).toBeNull();
    if (r.outcome.kind === 'pick') expect(r.outcome.id).toBe('tour:5');
  });

  test('a failed decode falls through to a pick in the same fragment', () => {
    const r = resolveInitial({
      intent: readHash('#src=AAA&pick=tour:5'),
      decoded: badDecode,
      env: env({ activeId: 'example:half-adder' }),
      catalogue,
      defaultId,
    });
    expect(r.outcome.kind).toBe('pick');
    if (r.outcome.kind === 'pick') expect(r.outcome.id).toBe('tour:5');
    expect(r.note).toContain('could not be decoded');
  });

  test('a failed decode with no pick lands on the stored project, with a note', () => {
    const r = resolveInitial({
      intent: readHash('#src=AAA'),
      decoded: badDecode,
      env: env({ activeId: 'example:half-adder' }),
      catalogue,
      defaultId,
    });
    expect(r.outcome.kind).toBe('active');
    expect(r.note).toContain('opened the last project instead');
  });

  test('an unknown pick id lands on the stored project, with a note', () => {
    const r = resolveInitial({
      intent: readHash('#pick=example:nope'),
      decoded: null,
      env: env({ activeId: 'example:half-adder' }),
      catalogue,
      defaultId,
    });
    expect(r.outcome.kind).toBe('active');
    expect(r.note).not.toBeNull();
  });

  test('only an empty activeId reaches the default', () => {
    const clean = resolveInitial({ intent: {}, decoded: null, env: env(), catalogue, defaultId });
    expect(clean.outcome.kind).toBe('default');
    // No intent was present, so there is nothing to explain.
    expect(clean.note).toBeNull();

    const failed = resolveInitial({
      intent: readHash('#src=AAA'),
      decoded: badDecode,
      env: env(),
      catalogue,
      defaultId,
    });
    expect(failed.outcome.kind).toBe('default');
    expect(failed.note).toContain('first example');
  });

  test('a stored active project reopens with no note', () => {
    const r = resolveInitial({
      intent: {},
      decoded: null,
      env: env({ activeId: 'tour:3' }),
      catalogue,
      defaultId,
    });
    expect(r.outcome.kind).toBe('active');
    expect(r.note).toBeNull();
    if (r.outcome.kind === 'active') expect(r.outcome.source).toBe(tour[2].source);
  });

  test('a stored scratch project reopens from the envelope', () => {
    const scratch = [{ id: 'scratch:x', name: 'mine', source: 'input z\n', updatedAt: 1 }];
    const r = resolveInitial({
      intent: {},
      decoded: null,
      env: env({ activeId: 'scratch:x', scratch }),
      catalogue,
      defaultId,
    });
    expect(r.outcome).toEqual({ kind: 'active', id: 'scratch:x', source: 'input z\n' });
  });

  test('an unrecognised fragment key still explains itself', () => {
    const r = resolveInitial({
      intent: readHash('#other=1'),
      decoded: null,
      env: env({ activeId: 'tour:1' }),
      catalogue,
      defaultId,
    });
    expect(r.outcome.kind).toBe('active');
    expect(r.note).not.toBeNull();
  });
});

describe('copy-on-write forking', () => {
  test('an edited example forks and survives a write/read cycle', () => {
    const storage = fakeStorage();
    const timers = fakeTimers();
    const store = createStore({ storage, timers });
    const edited = `${examples.find((e) => e.slug === 'half-adder')!.source}// mine\n`;

    // The island's persistSource, in model terms: activeId names a content
    // project, so the first edit forks rather than overwriting.
    store.update((d) => { d.activeId = 'example:half-adder'; });
    const label = catalogue.find((c) => c.id === 'example:half-adder')!.label;
    expect(label).toBe('Half-adder');

    let forkedId = '';
    store.update((d) => {
      const r = createScratch(d.scratch, { name: label, source: edited, now: 100, keep: d.activeId });
      d.scratch = r.list;
      d.activeId = r.created!.id;
      forkedId = r.created!.id;
    });
    store.flush();

    const back = readEnvelope(storage).envelope;
    expect(back.activeId).toBe(forkedId);
    expect(idKind(back.activeId!)).toBe('scratch');
    expect(back.scratch[0].name).toBe('Half-adder');
    expect(resolveSource(forkedId, catalogue, back.scratch)).toBe(edited);
    // The shipped example is untouched by the fork.
    expect(resolveSource('example:half-adder', catalogue, back.scratch)).toBe(
      examples.find((e) => e.slug === 'half-adder')!.source,
    );

    // A second fork of the same example is numbered rather than colliding.
    let secondName = '';
    store.update((d) => {
      const r = createScratch(d.scratch, { name: label, source: edited, now: 200, keep: d.activeId });
      d.scratch = r.list;
      secondName = r.created!.name;
    });
    expect(secondName).toBe('Half-adder 2');
  });

  test('a later edit updates the fork in place rather than forking again', () => {
    let list = createScratch([], { name: 'Half-adder', source: 'a', now: 1 }).list;
    const id = list[0].id;
    list = touchScratch(list, id, 'b', 2).list;
    expect(list).toHaveLength(1);
    expect(list[0].source).toBe('b');
    expect(list[0].updatedAt).toBe(2);
  });
});
