// One key, one schema-versioned envelope, one origin-local store.
//
// Everything here is pure over an injected storage and timer, so `bun test`
// drives the quota path, the eviction path and the debounce without touching a
// global or waiting on a real clock. The island passes `browserStorage()`.
//
// Phase 3 populates `layout.ratios` only. The other fields ship with their
// defaults so later phases fill them without a second key and without a
// version bump.

export const STORE_KEY = 'circ.playground.v1';
export const STORE_VERSION = 1;
export const MAX_SCRATCH = 16;
export const MAX_SOURCE_BYTES = 32 * 1024;
export const MAX_ENVELOPE_BYTES = 256 * 1024;
export const WRITE_DEBOUNCE_MS = 500;

/** The four output tabs. */
export type OutputTab = 'diagnostics' | 'preview' | 'truth' | 'simulate';

/** `example:<slug>` | `tour:<n>` | `scratch:<id>`. */
export type PickId = string;

export interface ScratchProject {
  id: PickId;
  name: string;
  /** The combined marker text. Never an example or tour body — those are
   *  stored by id, because a copy goes stale the moment the content changes. */
  source: string;
  /** Epoch ms. The key eviction sorts on. */
  updatedAt: number;
}

export interface LayoutState {
  /** Splitter id → first-pane fraction, strictly between 0 and 1. A record so
   *  a second divider costs no schema change. */
  ratios: Record<string, number>;
}

/**
 * Stored in camelCase deliberately: an envelope key must never be spreadable
 * into a libcirc `options` object, where an unknown key is a bad request and
 * never a silent default. The translation is field by field, elsewhere.
 */
export interface PlaygroundSettings {
  expandMacros: boolean;
  expandDisplay: boolean;
  format: 'markdown' | 'csv' | 'json';
  valueFormat: 'binary' | 'hex' | 'decimal';
  /** 1..24; the page default is 12 while the library's own is 16, which is why
   *  the page always sends the option explicitly. */
  truthTableCap: number;
  warningsAsErrors: boolean;
  /** Declared `rom` name → hex image. */
  romImages: Record<string, string>;
}

export interface PlaygroundEnvelope {
  version: number;
  scratch: ScratchProject[];
  activeId: PickId | null;
  /** A file name inside the active project, not a path. */
  activeFile: string | null;
  layout: LayoutState;
  settings: PlaygroundSettings;
  tab: OutputTab;
}

export type StoreNote =
  | { kind: 'reset'; reason: 'version' | 'corrupt' }
  | { kind: 'evicted'; names: string[] }
  | { kind: 'disabled'; reason: 'quota' | 'unavailable' };

/** Injected so a test never touches a global. */
export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export interface TimerLike {
  setTimeout(fn: () => void, ms: number): number;
  clearTimeout(id: number): void;
}

const OUTPUT_TABS: readonly OutputTab[] = ['diagnostics', 'preview', 'truth', 'simulate'];
const FORMATS: readonly PlaygroundSettings['format'][] = ['markdown', 'csv', 'json'];
const VALUE_FORMATS: readonly PlaygroundSettings['valueFormat'][] = ['binary', 'hex', 'decimal'];

export function defaultSettings(): PlaygroundSettings {
  return {
    expandMacros: false,
    expandDisplay: false,
    // The page parses the truth table as JSON; the library's own default is
    // markdown, which is why this is always sent explicitly.
    format: 'json',
    valueFormat: 'binary',
    truthTableCap: 12,
    warningsAsErrors: false,
    romImages: {},
  };
}

export function defaultEnvelope(): PlaygroundEnvelope {
  return {
    version: STORE_VERSION,
    scratch: [],
    activeId: null,
    activeFile: null,
    layout: { ratios: {} },
    settings: defaultSettings(),
    tab: 'diagnostics',
  };
}

const utf8Bytes = (s: string): number => new TextEncoder().encode(s).length;

const isObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

function normalizeSettings(raw: unknown): PlaygroundSettings {
  const out = defaultSettings();
  if (!isObject(raw)) return out;
  if (typeof raw.expandMacros === 'boolean') out.expandMacros = raw.expandMacros;
  if (typeof raw.expandDisplay === 'boolean') out.expandDisplay = raw.expandDisplay;
  if (typeof raw.warningsAsErrors === 'boolean') out.warningsAsErrors = raw.warningsAsErrors;
  if (FORMATS.includes(raw.format as PlaygroundSettings['format'])) {
    out.format = raw.format as PlaygroundSettings['format'];
  }
  if (VALUE_FORMATS.includes(raw.valueFormat as PlaygroundSettings['valueFormat'])) {
    out.valueFormat = raw.valueFormat as PlaygroundSettings['valueFormat'];
  }
  if (typeof raw.truthTableCap === 'number' && Number.isFinite(raw.truthTableCap)) {
    out.truthTableCap = Math.max(1, Math.min(24, Math.round(raw.truthTableCap)));
  }
  if (isObject(raw.romImages)) {
    for (const [name, hex] of Object.entries(raw.romImages)) {
      if (typeof hex === 'string') out.romImages[name] = hex;
    }
  }
  return out;
}

function normalizeScratch(raw: unknown): ScratchProject[] {
  if (!Array.isArray(raw)) return [];
  const kept: ScratchProject[] = [];
  for (const entry of raw) {
    if (!isObject(entry)) continue;
    const { id, name, source, updatedAt } = entry;
    if (typeof id !== 'string' || typeof name !== 'string' || typeof source !== 'string') continue;
    if (typeof updatedAt !== 'number' || !Number.isFinite(updatedAt)) continue;
    // Drop the project rather than silently truncating someone's source.
    if (utf8Bytes(source) > MAX_SOURCE_BYTES) continue;
    kept.push({ id, name, source, updatedAt });
  }
  kept.sort((a, b) => b.updatedAt - a.updatedAt);
  return kept.slice(0, MAX_SCRATCH);
}

function normalizeRatios(raw: unknown): Record<string, number> {
  const out: Record<string, number> = {};
  if (!isObject(raw)) return out;
  for (const [key, value] of Object.entries(raw)) {
    if (typeof value === 'number' && Number.isFinite(value) && value > 0 && value < 1) {
      out[key] = value;
    }
  }
  return out;
}

/**
 * Never throws. Every unrecognised key is dropped, which is what stops a
 * hand-edited envelope from smuggling anything downstream. Only a parse
 * failure or a wrong version yields a note; everything else degrades quietly
 * to a default.
 */
export function normalize(raw: unknown): { envelope: PlaygroundEnvelope; note: StoreNote | null } {
  if (!isObject(raw)) return { envelope: defaultEnvelope(), note: { kind: 'reset', reason: 'corrupt' } };
  if (raw.version !== STORE_VERSION) {
    // No migration path before v2: a mismatch resets rather than guesses.
    return { envelope: defaultEnvelope(), note: { kind: 'reset', reason: 'version' } };
  }

  const scratch = normalizeScratch(raw.scratch);
  const ids = new Set(scratch.map((p) => p.id));
  const activeId =
    typeof raw.activeId === 'string' && (!raw.activeId.startsWith('scratch:') || ids.has(raw.activeId))
      ? raw.activeId
      : null;

  return {
    envelope: {
      version: STORE_VERSION,
      scratch,
      activeId,
      activeFile: typeof raw.activeFile === 'string' ? raw.activeFile : null,
      layout: { ratios: normalizeRatios(isObject(raw.layout) ? raw.layout.ratios : null) },
      settings: normalizeSettings(raw.settings),
      tab: OUTPUT_TABS.includes(raw.tab as OutputTab) ? (raw.tab as OutputTab) : 'diagnostics',
    },
    note: null,
  };
}

export function readEnvelope(storage: StorageLike | null): {
  envelope: PlaygroundEnvelope;
  note: StoreNote | null;
} {
  if (!storage) return { envelope: defaultEnvelope(), note: { kind: 'disabled', reason: 'unavailable' } };
  let text: string | null;
  try {
    text = storage.getItem(STORE_KEY);
  } catch {
    // Access itself throws in a private window or with site data blocked.
    return { envelope: defaultEnvelope(), note: { kind: 'disabled', reason: 'unavailable' } };
  }
  if (text === null) return { envelope: defaultEnvelope(), note: null };
  try {
    return normalize(JSON.parse(text));
  } catch {
    return { envelope: defaultEnvelope(), note: { kind: 'reset', reason: 'corrupt' } };
  }
}

/** Removes the least-recently-updated project; returns its name, or null. */
export function evictOldest(env: PlaygroundEnvelope): string | null {
  if (env.scratch.length === 0) return null;
  let oldest = 0;
  for (let i = 1; i < env.scratch.length; i += 1) {
    if (env.scratch[i].updatedAt < env.scratch[oldest].updatedAt) oldest = i;
  }
  const [removed] = env.scratch.splice(oldest, 1);
  return removed.name;
}

function isQuotaError(err: unknown): boolean {
  if (typeof err !== 'object' || err === null) return false;
  const e = err as { name?: unknown; code?: unknown };
  return (
    e.name === 'QuotaExceededError' ||
    e.name === 'NS_ERROR_DOM_QUOTA_REACHED' ||
    e.code === 22
  );
}

/**
 * Serialise, trim to the envelope cap by evicting least-recently-updated
 * projects, then write. A quota error evicts once more and retries exactly
 * once; a second failure — or a non-quota error — disables persistence for the
 * session, which the caller surfaces.
 */
export function writeEnvelope(
  env: PlaygroundEnvelope,
  storage: StorageLike | null,
): { ok: boolean; note: StoreNote | null } {
  if (!storage) return { ok: false, note: { kind: 'disabled', reason: 'unavailable' } };
  const evicted: string[] = [];

  let text = JSON.stringify(env);
  while (utf8Bytes(text) > MAX_ENVELOPE_BYTES && env.scratch.length > 0) {
    const name = evictOldest(env);
    if (name === null) break;
    evicted.push(name);
    text = JSON.stringify(env);
  }

  const evictedNote = (): StoreNote | null =>
    evicted.length > 0 ? { kind: 'evicted', names: [...evicted] } : null;

  try {
    storage.setItem(STORE_KEY, text);
    return { ok: true, note: evictedNote() };
  } catch (err) {
    if (!isQuotaError(err)) return { ok: false, note: { kind: 'disabled', reason: 'unavailable' } };
    const name = evictOldest(env);
    if (name === null) return { ok: false, note: { kind: 'disabled', reason: 'quota' } };
    evicted.push(name);
    try {
      storage.setItem(STORE_KEY, JSON.stringify(env));
      return { ok: true, note: evictedNote() };
    } catch {
      return { ok: false, note: { kind: 'disabled', reason: 'quota' } };
    }
  }
}

/** `globalThis.localStorage` behind a try/catch: access throws in a private
 *  window or with site data blocked, not merely on write. */
export function browserStorage(): StorageLike | null {
  try {
    const ls = (globalThis as { localStorage?: StorageLike }).localStorage;
    if (!ls) return null;
    // Probe: some browsers only throw on first use.
    const probe = `${STORE_KEY}.probe`;
    ls.setItem(probe, '1');
    ls.removeItem(probe);
    return ls;
  } catch {
    return null;
  }
}

export function describeNote(note: StoreNote): string {
  switch (note.kind) {
    case 'reset':
      return note.reason === 'version'
        ? 'Saved playground settings were from an older version and have been reset.'
        : 'Saved playground settings could not be read and have been reset.';
    case 'evicted':
      return `Storage was full, so ${note.names.length === 1 ? 'the oldest saved project' : 'the oldest saved projects'} (${note.names.join(', ')}) ${note.names.length === 1 ? 'was' : 'were'} removed.`;
    case 'disabled':
      return note.reason === 'quota'
        ? 'Storage is full, so this session will not be saved.'
        : 'This browser is not saving playground state, so your work will not persist.';
  }
}

export interface PlaygroundStore {
  readonly envelope: PlaygroundEnvelope;
  /** False once persistence has been disabled for the session. */
  readonly enabled: boolean;
  update(mutate: (draft: PlaygroundEnvelope) => void): void;
  /** Writes now, cancelling any pending debounce. */
  flush(): void;
  /** Notes buffered before the first subscriber are delivered on subscribe. */
  onNote(fn: (note: StoreNote) => void): () => void;
}

const defaultTimers: TimerLike = {
  setTimeout: (fn, ms) => globalThis.setTimeout(fn, ms) as unknown as number,
  clearTimeout: (id) => globalThis.clearTimeout(id),
};

export function createStore(opts: {
  storage?: StorageLike | null;
  timers?: TimerLike;
} = {}): PlaygroundStore {
  const storage = opts.storage === undefined ? browserStorage() : opts.storage;
  const timers = opts.timers ?? defaultTimers;

  const initial = readEnvelope(storage);
  let envelope = initial.envelope;
  let enabled = storage !== null;
  let timer: number | null = null;

  const buffered: StoreNote[] = [];
  const listeners = new Set<(note: StoreNote) => void>();
  const emit = (note: StoreNote | null) => {
    if (!note) return;
    if (listeners.size === 0) {
      buffered.push(note);
      return;
    }
    for (const fn of listeners) fn(note);
  };
  emit(initial.note);
  if (initial.note?.kind === 'disabled') enabled = false;

  const writeNow = () => {
    if (!enabled) return;
    const result = writeEnvelope(envelope, storage);
    if (!result.ok) enabled = false;
    emit(result.note);
  };

  return {
    get envelope() {
      return envelope;
    },
    get enabled() {
      return enabled;
    },
    update(mutate) {
      mutate(envelope);
      if (!enabled) return;
      if (timer !== null) timers.clearTimeout(timer);
      timer = timers.setTimeout(() => {
        timer = null;
        writeNow();
      }, WRITE_DEBOUNCE_MS);
    },
    flush() {
      if (timer !== null) {
        timers.clearTimeout(timer);
        timer = null;
      }
      writeNow();
    },
    onNote(fn) {
      listeners.add(fn);
      while (buffered.length > 0) fn(buffered.shift()!);
      return () => listeners.delete(fn);
    },
  };
}
