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
