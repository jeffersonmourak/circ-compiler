// The option projection is the one place a request can acquire a key the
// library refuses, and a refusal is a whole failed build. Every operation's
// key set is pinned here.
import { describe, expect, test } from 'bun:test';
import {
  DOCUMENTED_OPTION_KEYS,
  capRefusal,
  optionsFor,
  type LibcircOp,
} from '../src/scripts/settings-drawer.ts';
import {
  createStore,
  defaultSettings,
  readEnvelope,
  type PlaygroundSettings,
  type StorageLike,
  type TimerLike,
} from '../src/utils/playground-store.ts';

const settings = (over: Partial<PlaygroundSettings> = {}): PlaygroundSettings => ({
  ...defaultSettings(),
  ...over,
});

const OPS: LibcircOp[] = ['analyze', 'compile', 'preview', 'truth_table'];

describe('optionsFor', () => {
  test('never sends a key outside the documented set', () => {
    for (const op of OPS) {
      const keys = Object.keys(optionsFor(op, settings(), { code: 'ff' }));
      for (const k of keys) expect(DOCUMENTED_OPTION_KEYS).toContain(k as never);
    }
  });

  test('analyze sends nothing at all', () => {
    expect(optionsFor('analyze', settings())).toEqual({});
    // …even when preloads are on offer.
    expect(optionsFor('analyze', settings(), { code: 'ff' })).toEqual({});
  });

  test('compile sends only the one key it uses', () => {
    expect(optionsFor('compile', settings())).toEqual({ warnings_as_errors: false });
    expect(optionsFor('compile', settings({ warningsAsErrors: true }))).toEqual({
      warnings_as_errors: true,
    });
    // Not a truth-table key, not a preview key.
    expect(Object.keys(optionsFor('compile', settings()))).toEqual(['warnings_as_errors']);
  });

  test('preview pins colour off and carries both expansions', () => {
    const opts = optionsFor('preview', settings({ expandMacros: true, expandDisplay: true }));
    expect(opts).toEqual({
      color: 'never',
      expand_macros: true,
      expand_display: true,
      warnings_as_errors: false,
    });
    // The page has no TTY, so colour is never reader-facing.
    expect(optionsFor('preview', settings()).color).toBe('never');
  });

  test('truth_table carries its four keys, and preloads only when non-empty', () => {
    expect(optionsFor('truth_table', settings())).toEqual({
      format: 'json',
      value_format: 'binary',
      truth_table_cap: 12,
      warnings_as_errors: false,
    });
    expect(optionsFor('truth_table', settings(), {})).not.toHaveProperty('preloads');
    expect(optionsFor('truth_table', settings(), { code: 'ff00' })).toMatchObject({
      preloads: { code: 'ff00' },
    });
  });

  test('the wire names are snake_case, the stored names are not', () => {
    const opts = optionsFor('truth_table', settings());
    // A stored envelope must never be spreadable into a request.
    for (const k of Object.keys(opts)) expect(k).not.toMatch(/[A-Z]/);
    expect(Object.keys(defaultSettings())).toContain('truthTableCap');
    expect(Object.keys(opts)).toContain('truth_table_cap');
  });

  test('every setting reaches exactly the operations that use it', () => {
    const s = settings({
      expandMacros: true,
      expandDisplay: true,
      format: 'csv',
      valueFormat: 'hex',
      truthTableCap: 20,
      warningsAsErrors: true,
    });
    expect(optionsFor('preview', s).expand_macros).toBe(true);
    expect(optionsFor('truth_table', s).format).toBe('csv');
    expect(optionsFor('truth_table', s).value_format).toBe('hex');
    expect(optionsFor('truth_table', s).truth_table_cap).toBe(20);
    // warnings_as_errors is the one key three operations share.
    for (const op of ['compile', 'preview', 'truth_table'] as LibcircOp[]) {
      expect(optionsFor(op, s).warnings_as_errors).toBe(true);
    }
    // …and the expansions never leak into a compile or a table.
    expect(optionsFor('compile', s)).not.toHaveProperty('expand_macros');
    expect(optionsFor('truth_table', s)).not.toHaveProperty('expand_macros');
  });
});

describe('capRefusal', () => {
  test('refuses above the cap and stays quiet at or below it', () => {
    expect(capRefusal(13, settings())).not.toBeNull();
    expect(capRefusal(12, settings())).toBeNull();
    expect(capRefusal(0, settings())).toBeNull();
    // No analysis yet is not a refusal.
    expect(capRefusal(null, settings())).toBeNull();
  });

  test('the pre-flight and the request read one field', () => {
    // This is the whole point: they used to be two constants that could drift.
    const s = settings({ truthTableCap: 4 });
    expect(capRefusal(5, s)).not.toBeNull();
    expect(capRefusal(4, s)).toBeNull();
    expect(optionsFor('truth_table', s).truth_table_cap).toBe(4);
    // Raising the cap moves both at once.
    const raised = settings({ truthTableCap: 24 });
    expect(capRefusal(20, raised)).toBeNull();
    expect(optionsFor('truth_table', raised).truth_table_cap).toBe(24);
  });

  test('the message names the cap and the row count a reader would face', () => {
    const msg = capRefusal(20, settings({ truthTableCap: 12 }))!;
    expect(msg).toContain('20 input bits');
    expect(msg).toContain('12');
    expect(msg).toContain(String(2 ** 12));
  });
});

describe('settings survive a store round-trip', () => {
  function fakes() {
    const map = new Map<string, string>();
    const storage: StorageLike = {
      getItem: (k) => map.get(k) ?? null,
      setItem: (k, v) => { map.set(k, v); },
      removeItem: (k) => { map.delete(k); },
    };
    const pending: (() => void)[] = [];
    const timers: TimerLike & { run(): void } = {
      setTimeout: (fn) => { pending.push(fn); return pending.length; },
      clearTimeout: () => {},
      run: () => { for (const fn of pending.splice(0)) fn(); },
    };
    return { storage, timers };
  }

  test('a changed setting is written and read back, and reaches the request', () => {
    const { storage, timers } = fakes();
    const store = createStore({ storage, timers });
    store.update((d) => {
      d.settings.truthTableCap = 18;
      d.settings.valueFormat = 'hex';
      d.settings.expandMacros = true;
    });
    store.flush();

    const back = readEnvelope(storage).envelope.settings;
    expect(back.truthTableCap).toBe(18);
    expect(back.valueFormat).toBe('hex');
    expect(back.expandMacros).toBe(true);
    // And the projection off the restored settings is what the page sends.
    expect(optionsFor('truth_table', back).truth_table_cap).toBe(18);
    expect(optionsFor('preview', back).expand_macros).toBe(true);
  });

  test('an out-of-range cap is clamped by the store, not by this module', () => {
    const { storage, timers } = fakes();
    const store = createStore({ storage, timers });
    store.update((d) => { d.settings.truthTableCap = 99; });
    store.flush();
    // The store owns normalisation; there is no second normaliser here.
    expect(readEnvelope(storage).envelope.settings.truthTableCap).toBe(24);
  });
});
