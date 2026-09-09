// One key, one schema-versioned envelope, one origin-local store.
//
// Everything here is pure over an injected storage and timer, so `bun test`
// drives the quota path, the eviction path and the debounce without touching a
// global or waiting on a real clock. The island passes `browserStorage()`.
//
// Phase 3 populates `layout.ratios` only. The other fields ship with their
// defaults so later phases fill them without a second key and without a
// version bump.

import type { DecodeResult, HashIntent, ShareKey } from './share-link.ts';
/** The content owns the tier vocabulary; this module only maps it to a
 *  heading. A type import is erased, so the store still pulls no content
 *  into the playground bundle. */
import type { ExampleLevel } from '../content/examples.ts';

export const STORE_KEY = 'circ.playground.v1';
export const STORE_VERSION = 1;
export const MAX_SCRATCH = 16;
export const MAX_SOURCE_BYTES = 32 * 1024;
export const MAX_ENVELOPE_BYTES = 256 * 1024;
export const WRITE_DEBOUNCE_MS = 500;

/**
 * The three output tabs. Diagnostics is not among them: it belongs to the
 * source, not to the compiled result, so it lives in the editor's own dock
 * beside the settings rather than competing with the preview for the pane a
 * reader is watching.
 */
export type OutputTab = 'preview' | 'truth' | 'simulate';

/** The editor dock's panels. `memory` only exists while the circuit declares
 *  a rom or a ram; a stored `memory` for a circuit that has none is treated
 *  like any other unreachable tab and falls back at render time. */
export type DockTab = 'diagnostics' | 'settings' | 'memory';

/** Which rows of the workspace explorer the reader has open. Ids, not
 *  indices: a group or project keeps its expansion across a content change
 *  that renumbers everything around it. */
export interface WorkspaceState {
  expanded: string[];
}

/** The dock is collapsible, and which panel it was left on is remembered
 *  separately from whether it was left open. */
export interface DockState {
  open: boolean;
  tab: DockTab;
}

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
  dock: DockState;
  ws: WorkspaceState;
}

export type StoreNote =
  | { kind: 'reset'; reason: 'version' | 'corrupt' }
  | { kind: 'evicted'; names: string[] }
  /** Sources over `MAX_SOURCE_BYTES`: kept in memory so the reader keeps
   *  typing, omitted from what is written. */
  | { kind: 'skipped'; names: string[] }
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

const OUTPUT_TABS: readonly OutputTab[] = ['preview', 'truth', 'simulate'];
const DOCK_TABS: readonly DockTab[] = ['diagnostics', 'settings', 'memory'];
// Shut. The dock holds diagnostics, and the explorer now carries the per-file
// error badge, so a reader sees that something is wrong without it — opening it
// is for reading the messages, which is a deliberate act.
export const DEFAULT_DOCK: DockState = { open: false, tab: 'diagnostics' };
/** The reader's own projects, open. Everything else starts shut, and whichever
 *  group holds the open project is revealed at load without being persisted. */
export const DEFAULT_WS: WorkspaceState = { expanded: ['yours'] };
/** Enough for every group plus every project; past this the envelope is being
 *  used as a scratchpad by something other than a reader. */
const MAX_EXPANDED = 128;
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
    tab: 'preview',
    dock: { ...DEFAULT_DOCK },
    ws: { expanded: [...DEFAULT_WS.expanded] },
  };
}

const utf8Bytes = (s: string): number => new TextEncoder().encode(s).length;

const isObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

/** Missing entirely in every envelope written before the dock existed, which
 *  is why each field falls back on its own rather than the object as a whole. */
function normalizeDock(raw: unknown): DockState {
  const out: DockState = { ...DEFAULT_DOCK };
  if (!isObject(raw)) return out;
  if (typeof raw.open === 'boolean') out.open = raw.open;
  if (DOCK_TABS.includes(raw.tab as DockTab)) out.tab = raw.tab as DockTab;
  return out;
}

/** Ids only, deduped and capped. An id names nothing in the envelope, so one
 *  that no longer matches a group or project is simply never read. */
function normalizeWorkspace(raw: unknown): WorkspaceState {
  if (!isObject(raw) || !Array.isArray(raw.expanded)) {
    return { expanded: [...DEFAULT_WS.expanded] };
  }
  const seen = new Set<string>();
  for (const id of raw.expanded) {
    if (typeof id !== 'string' || id === '') continue;
    seen.add(id);
    if (seen.size >= MAX_EXPANDED) break;
  }
  return { expanded: [...seen] };
}

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
      // An envelope written before diagnostics left the output pane carries
      // `tab: 'diagnostics'`, which is no longer an output tab. It falls back
      // here like any other unrecognised value rather than resetting anything.
      tab: OUTPUT_TABS.includes(raw.tab as OutputTab) ? (raw.tab as OutputTab) : 'preview',
      dock: normalizeDock(raw.dock),
      ws: normalizeWorkspace(raw.ws),
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

/**
 * Removes the least-recently-updated project and returns its name, or null
 * when there is nothing left to remove.
 *
 * `keep` is never evicted — it is the project the reader is typing into, and
 * losing that one to make room for older ones is the worst possible trade.
 * When only `keep` remains this returns null and the caller stops.
 */
export function evictOldest(env: PlaygroundEnvelope, keep?: PickId | null): string | null {
  let oldest = -1;
  for (let i = 0; i < env.scratch.length; i += 1) {
    if (keep && env.scratch[i].id === keep) continue;
    if (oldest === -1 || env.scratch[i].updatedAt < env.scratch[oldest].updatedAt) oldest = i;
  }
  if (oldest === -1) return null;
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
  keep?: PickId | null,
): { ok: boolean; note: StoreNote | null; skipped: ScratchProject[] } {
  if (!storage) {
    return { ok: false, note: { kind: 'disabled', reason: 'unavailable' }, skipped: [] };
  }
  // A source over the per-source cap is omitted WHOLE from what is written —
  // never as a record with a missing source, which `normalize` would drop on
  // the next read with no note at all. It stays in memory, so the reader keeps
  // typing and only loses persistence for that one project.
  const skipped = env.scratch.filter((p) => utf8Bytes(p.source) > MAX_SOURCE_BYTES);
  const skippedIds = new Set(skipped.map((p) => p.id));
  const serialize = () =>
    JSON.stringify({ ...env, scratch: env.scratch.filter((p) => !skippedIds.has(p.id)) });

  const evicted: string[] = [];
  let text = serialize();
  while (utf8Bytes(text) > MAX_ENVELOPE_BYTES) {
    const name = evictOldest(env, keep);
    if (name === null) break;
    evicted.push(name);
    text = serialize();
  }

  const evictedNote = (): StoreNote | null =>
    evicted.length > 0 ? { kind: 'evicted', names: [...evicted] } : null;

  try {
    storage.setItem(STORE_KEY, text);
    return { ok: true, note: evictedNote(), skipped };
  } catch (err) {
    if (!isQuotaError(err)) {
      return { ok: false, note: { kind: 'disabled', reason: 'unavailable' }, skipped };
    }
    const name = evictOldest(env, keep);
    if (name === null) return { ok: false, note: { kind: 'disabled', reason: 'quota' }, skipped };
    evicted.push(name);
    try {
      storage.setItem(STORE_KEY, serialize());
      return { ok: true, note: evictedNote(), skipped };
    } catch {
      return { ok: false, note: { kind: 'disabled', reason: 'quota' }, skipped };
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
    case 'skipped':
      return `${note.names.length === 1 ? 'One project is' : `${note.names.length} projects are`} too large to save (${note.names.join(', ')}); they stay open but will not survive a reload.`;
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

  /** Never evict the project the reader is in. */
  const writeNow = () => {
    if (!enabled) return;
    const result = writeEnvelope(envelope, storage, envelope.activeId);
    if (!result.ok) enabled = false;
    emit(result.note);
    if (result.skipped.length > 0) {
      emit({ kind: 'skipped', names: result.skipped.map((p) => p.name) });
    }
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

// ---------------------------------------------------------------------------
// The workspace: content projects by id, scratch projects by value.
// ---------------------------------------------------------------------------

export type ProjectKind = 'example' | 'tour' | 'scratch';

/**
 * One row of the workspace. The sidebar, the page's embedded catalogue blob and
 * the "Open in playground" links all come from one `buildCatalogue` call, so
 * they cannot drift from each other or from the shipped content.
 */
export type CatalogueGroup = 'Introduction' | 'Building blocks' | 'Advanced' | 'Tour';

/**
 * The heading each example level sits under. The levels are a content
 * judgement and the headings are a reader-facing label, so the two are mapped
 * here rather than being the same string — renaming a heading must not mean
 * rewriting fifteen content entries.
 */
export const GROUP_OF_LEVEL: Record<ExampleLevel, CatalogueGroup> = {
  intro: 'Introduction',
  medium: 'Building blocks',
  advanced: 'Advanced',
};

/**
 * Every group the workspace can show, shallow end first and the tour last.
 * The sidebar iterates this rather than a literal pair, so adding a level
 * cannot leave a group of examples unreachable in the picker.
 */
export const CATALOGUE_GROUPS: readonly CatalogueGroup[] = [
  'Introduction',
  'Building blocks',
  'Advanced',
  'Tour',
];

export interface CatalogueItem {
  id: PickId;
  label: string;
  group: CatalogueGroup;
  source: string;
}

export function buildCatalogue(
  examples: readonly { slug: string; title: string; level: ExampleLevel; source: string }[],
  tour: readonly { title: string; source: string }[],
): CatalogueItem[] {
  // Grouped by level rather than taken in file order, so the catalogue stays
  // tiered even if the content array is ever reordered.
  const tier = (level: ExampleLevel) =>
    examples
      .filter((e) => e.level === level)
      .map((e) => ({
        id: `example:${e.slug}`,
        label: e.title,
        group: GROUP_OF_LEVEL[level],
        source: e.source,
      }));
  return [
    ...tier('intro'),
    ...tier('medium'),
    ...tier('advanced'),
    ...tour.map((t, i) => ({
      id: `tour:${i + 1}`,
      label: `${i + 1}. ${t.title}`,
      group: 'Tour' as const,
      source: t.source,
    })),
  ];
}

/** What a fresh project starts as. */
export const NEW_PROJECT_SOURCE = 'input a\nnot n(in=a)\noutput out(in=n.out)\n';

export function idKind(id: PickId): ProjectKind | null {
  if (id.startsWith('example:')) return 'example';
  if (id.startsWith('tour:')) return 'tour';
  if (id.startsWith('scratch:')) return 'scratch';
  return null;
}

/** `now` and `rand` are injected so a test is deterministic and no `crypto`
 *  global is required — `randomUUID` is absent on older Safari and on any
 *  non-secure origin. */
export function newScratchId(now: number, rand: () => number = Math.random): PickId {
  const salt = Math.floor(rand() * 0x100000).toString(36);
  return `scratch:${now.toString(36)}${salt}`;
}

/** `base`, or the first free `base N`. */
export function uniqueName(base: string, taken: readonly string[]): string {
  if (!taken.includes(base)) return base;
  for (let n = 2; ; n += 1) {
    const candidate = `${base} ${n}`;
    if (!taken.includes(candidate)) return candidate;
  }
}

export interface ScratchEdit {
  list: ScratchProject[];
  evicted: ScratchProject[];
  /** Refused for exceeding `MAX_SOURCE_BYTES`. Kept by the caller in memory,
   *  never written. */
  skipped: ScratchProject[];
}

/** Trim to `MAX_SCRATCH` by dropping the least recently updated, never `keep`. */
function trimToMax(list: ScratchProject[], keep?: PickId | null): { list: ScratchProject[]; evicted: ScratchProject[] } {
  const evicted: ScratchProject[] = [];
  const out = [...list];
  while (out.length > MAX_SCRATCH) {
    let oldest = -1;
    for (let i = 0; i < out.length; i += 1) {
      if (keep && out[i].id === keep) continue;
      if (oldest === -1 || out[i].updatedAt < out[oldest].updatedAt) oldest = i;
    }
    if (oldest === -1) break;
    evicted.push(out.splice(oldest, 1)[0]);
  }
  return { list: out, evicted };
}

export function createScratch(
  list: readonly ScratchProject[],
  init: { name: string; source: string; now: number; keep?: PickId | null; rand?: () => number },
): ScratchEdit & { created: ScratchProject | null } {
  const created: ScratchProject = {
    id: newScratchId(init.now, init.rand),
    name: uniqueName(init.name, list.map((p) => p.name)),
    source: init.source,
    updatedAt: init.now,
  };
  if (utf8Bytes(created.source) > MAX_SOURCE_BYTES) {
    // Over the per-source cap at birth: report it rather than storing
    // something the next read would silently drop.
    return { list: [...list], evicted: [], skipped: [created], created: null };
  }
  const trimmed = trimToMax([...list, created], init.keep ?? created.id);
  return { ...trimmed, skipped: [], created };
}

export function duplicateScratch(
  list: readonly ScratchProject[],
  id: PickId,
  init: { now: number; rand?: () => number },
): (ScratchEdit & { created: ScratchProject | null }) | null {
  const source = list.find((p) => p.id === id);
  if (!source) return null;
  return createScratch(list, { name: source.name, source: source.source, now: init.now, rand: init.rand });
}

export function renameScratch(list: readonly ScratchProject[], id: PickId, name: string): ScratchProject[] {
  const trimmed = name.trim();
  if (trimmed === '') return [...list];
  return list.map((p) => (p.id === id ? { ...p, name: trimmed } : p));
}

export function deleteScratch(list: readonly ScratchProject[], id: PickId): ScratchProject[] {
  return list.filter((p) => p.id !== id);
}

/**
 * Record an edit. An over-size body is refused **at the source**: the list
 * comes back unchanged with the offending project in `skipped`, so nothing
 * over the cap ever reaches the envelope and no second fitting pass is needed.
 */
export function touchScratch(
  list: readonly ScratchProject[],
  id: PickId,
  source: string,
  now: number,
): ScratchEdit {
  const existing = list.find((p) => p.id === id);
  if (!existing) return { list: [...list], evicted: [], skipped: [] };
  if (utf8Bytes(source) > MAX_SOURCE_BYTES) {
    return { list: [...list], evicted: [], skipped: [{ ...existing, source }] };
  }
  return {
    list: list.map((p) => (p.id === id ? { ...p, source, updatedAt: now } : p)),
    evicted: [],
    skipped: [],
  };
}

/** The text behind an id: a catalogue entry's shipped source, or a scratch
 *  project's stored one. Null when the id names neither. */
export function resolveSource(
  id: PickId,
  catalogue: readonly CatalogueItem[],
  scratch: readonly ScratchProject[],
): string | null {
  const item = catalogue.find((c) => c.id === id);
  if (item) return item.source;
  const project = scratch.find((p) => p.id === id);
  return project ? project.source : null;
}

export type LoadOutcome =
  | { kind: 'share'; source: string; key: ShareKey }
  | { kind: 'pick'; id: PickId; source: string }
  | { kind: 'active'; id: PickId; source: string }
  | { kind: 'default'; id: PickId; source: string };

/**
 * What to open, walked one rule at a time: a share fragment, then a `#pick=`,
 * then the project the reader last had open, then the first catalogue entry.
 *
 * Each failure falls through to the NEXT rule rather than straight to the
 * default, which is why the hash intent keeps every key it found instead of
 * resolving to one.
 */
export function resolveInitial(input: {
  intent: HashIntent;
  decoded: DecodeResult | null;
  env: PlaygroundEnvelope;
  catalogue: readonly CatalogueItem[];
  defaultId: PickId;
}): { outcome: LoadOutcome; note: string | null } {
  const { intent, decoded, env, catalogue, defaultId } = input;
  const hadIntent = Boolean(intent.src || intent.pick || (intent.unknown && intent.unknown.length > 0));
  let failed = false;

  if (intent.src) {
    if (decoded && decoded.ok) {
      return { outcome: { kind: 'share', source: decoded.source, key: decoded.key }, note: null };
    }
    failed = true;
  }

  if (intent.pick) {
    const source = resolveSource(intent.pick, catalogue, env.scratch);
    if (source !== null) {
      return {
        outcome: { kind: 'pick', id: intent.pick, source },
        note: failed ? 'That share link could not be decoded; opened the linked example instead.' : null,
      };
    }
    failed = true;
  }

  if (env.activeId) {
    const source = resolveSource(env.activeId, catalogue, env.scratch);
    if (source !== null) {
      return {
        outcome: { kind: 'active', id: env.activeId, source },
        note: failed || (intent.unknown && intent.unknown.length > 0)
          ? (intent.src
              ? 'That share link could not be decoded; opened the last project instead.'
              : 'Unknown example id in the link; opened the last project instead.')
          : null,
      };
    }
    failed = true;
  }

  const fallbackId = catalogue.some((c) => c.id === defaultId) ? defaultId : (catalogue[0]?.id ?? defaultId);
  return {
    outcome: {
      kind: 'default',
      id: fallbackId,
      source: resolveSource(fallbackId, catalogue, env.scratch) ?? '',
    },
    note: hadIntent
      ? (intent.src && failed
          ? 'That share link could not be decoded; opened the first example instead.'
          : 'Unknown example id in the link; opened the first example instead.')
      : null,
  };
}

