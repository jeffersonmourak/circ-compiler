// The tab model: pure data over the one interchange format. Every reducer
// returns a new state and mutates nothing, so the island can swap `state.tabs`
// in one assignment and the editor's document registry mirrors it afterwards.
//
// No DOM, no editor package, no browser storage — `bun test` reaches all of
// it, which is the whole reason the model lives here and not in the island's
// closure. Persistence is Phase 3's; this module never learns about it. The
// purity case in `test/file-tabs.test.ts` scans this file's own source text,
// so even a mention in a comment is a failure; that bluntness is deliberate.
import {
  PLAYGROUND_DIR,
  isFileName,
  joinFiles,
  splitFiles,
  type NamedFile,
} from '../utils/split-files.ts';

/** A tab is exactly a named body. `startLine` belongs to callers that map into
 *  the COMBINED document; tabs are file-local and never need it. */
export type FileTab = NamedFile;

export interface FileTabsState {
  /** Never empty. The LAST entry is the root. */
  readonly files: readonly FileTab[];
  /** Always in `[0, files.length - 1]`. */
  readonly active: number;
}

/** `splitFiles` always returns at least one entry (an unmarked source becomes
 *  a single `main.circ`), so the never-empty invariant holds by construction. */
export function fromSource(source: string): FileTabsState {
  const files = splitFiles(source).map((f) => ({ name: f.name, body: f.body }));
  return { files, active: 0 };
}

export function toSource(state: FileTabsState): string {
  return joinFiles(state.files);
}

export const rootIndex = (state: FileTabsState): number => state.files.length - 1;

export const activeFile = (state: FileTabsState): FileTab => state.files[state.active];

const clampIndex = (state: FileTabsState, index: number): number =>
  Math.max(0, Math.min(index, state.files.length - 1));

/**
 * Selects a TAB. Always call this qualified — `fileTabs.select(...)` — because
 * `EditorHandle.select(from, to)` places a CURSOR and the two meet on one code
 * path when a diagnostic jumps into another file.
 */
export function select(state: FileTabsState, index: number): FileTabsState {
  const active = clampIndex(state, index);
  return active === state.active ? state : { files: state.files, active };
}

export function setBody(state: FileTabsState, index: number, body: string): FileTabsState {
  if (index < 0 || index >= state.files.length) return state;
  if (state.files[index].body === body) return state;
  const files = state.files.map((f, i) => (i === index ? { name: f.name, body } : f));
  return { files, active: state.active };
}

/** The first free `file<N>.circ`, counting from 1. */
export function nextFileName(files: readonly FileTab[]): string {
  const taken = new Set(files.map((f) => f.name));
  for (let n = 1; ; n += 1) {
    const name = `file${n}.circ`;
    if (!taken.has(name)) return name;
  }
}

/**
 * A new file's starting text: one comment line naming it.
 *
 * It must be non-blank, or the marker that ends this file would be swallowed
 * as a comment and the next file would merge into it; and it must not itself
 * look like a marker, or the splitter would read it as a second file. Dropping
 * the `.circ` suffix satisfies the second condition, since the marker pattern
 * requires it.
 */
export function seedBody(name: string): string {
  return `// ${name.replace(/\.circ$/, '')}\n`;
}

/** Inserts before the root so the root stays last, and activates the new tab. */
export function addFile(state: FileTabsState, name?: string): FileTabsState {
  const chosen = name ?? nextFileName(state.files);
  const at = rootIndex(state);
  const files = [
    ...state.files.slice(0, at),
    { name: chosen, body: seedBody(chosen) },
    ...state.files.slice(at),
  ];
  return { files, active: at };
}

/** Null when the rename is legal. Skips `index` itself, so renaming a file to
 *  the name it already has is not a duplicate. */
export function nameError(state: FileTabsState, index: number, name: string): string | null {
  if (!isFileName(name)) {
    return 'A file name must look like `name.circ` — letters, digits, dot, dash and underscore only.';
  }
  const clash = state.files.some((f, i) => i !== index && f.name === name);
  return clash ? `There is already a file called ${name}.` : null;
}

/** No-op when `nameError` is non-null; the caller shows the message. */
export function renameFile(state: FileTabsState, index: number, name: string): FileTabsState {
  if (index < 0 || index >= state.files.length) return state;
  if (nameError(state, index, name) !== null) return state;
  if (state.files[index].name === name) return state;
  const files = state.files.map((f, i) => (i === index ? { name, body: f.body } : f));
  return { files, active: state.active };
}

export const canDelete = (state: FileTabsState): boolean => state.files.length > 1;

/** No-op when only one file remains — the model's never-empty invariant. */
export function deleteFile(state: FileTabsState, index: number): FileTabsState {
  if (!canDelete(state)) return state;
  if (index < 0 || index >= state.files.length) return state;
  const files = state.files.filter((_, i) => i !== index);
  const active =
    state.active > index ? state.active - 1 : Math.min(state.active, files.length - 1);
  return { files, active };
}

/**
 * Relocates one file; `to` clamps into range. The previously active FILE stays
 * active wherever it lands, so a reorder never swaps the visible file out from
 * under the reader.
 *
 * Moving a tab past the end is how the root changes — the root is a position,
 * not a flag.
 */
export function moveFile(state: FileTabsState, from: number, to: number): FileTabsState {
  const last = state.files.length - 1;
  const src = Math.max(0, Math.min(from, last));
  const dst = Math.max(0, Math.min(to, last));
  if (src === dst) return state;

  const files = [...state.files];
  const [moved] = files.splice(src, 1);
  files.splice(dst, 0, moved);

  let active = state.active;
  if (active === src) {
    active = dst;
  } else {
    if (src < active) active -= 1;
    if (dst <= active) active += 1;
  }
  return { files, active };
}

export interface TabCounts {
  errors: number;
  warnings: number;
}

/**
 * Per-tab diagnostic counts.
 *
 * The analysis parameter is structural rather than the mapper's `Analysis`
 * interface, so this module stays independent of where that type lives.
 *
 * A file id counts only when its path is under the playground directory AND
 * names a tab that currently exists. Everything else is dropped: the builtin
 * macro sources, and any path left over from a reply that outlived a rename or
 * a delete. A late reply therefore degrades to NO badge rather than to a badge
 * on the wrong tab.
 */
export function countsByFile(
  files: readonly FileTab[],
  analysis: {
    files: readonly { file_id: number; path: string }[];
    diagnostics: readonly { file_id: number; severity: string }[];
  } | null,
): TabCounts[] {
  const counts: TabCounts[] = files.map(() => ({ errors: 0, warnings: 0 }));
  if (!analysis) return counts;

  const tabOf = new Map<number, number>();
  for (const entry of analysis.files) {
    if (!entry.path.startsWith(`${PLAYGROUND_DIR}/`)) continue;
    const name = entry.path.slice(PLAYGROUND_DIR.length + 1);
    const index = files.findIndex((f) => f.name === name);
    if (index >= 0) tabOf.set(entry.file_id, index);
  }

  for (const d of analysis.diagnostics) {
    const index = tabOf.get(d.file_id);
    if (index === undefined) continue;
    if (d.severity === 'error') counts[index].errors += 1;
    else counts[index].warnings += 1;
  }
  return counts;
}

