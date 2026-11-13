// The dev playground's model of projects on disk (`bun run playground`).
//
// A project is one directory; its files are the `.circ` files directly inside
// it. The playground holds a project as one combined marker text, so this
// module turns a directory into that text and turns an edited text back into
// the smallest set of file writes. It is pure: the dev server reads and writes
// the files (`scripts/dev-playground/plugin.mjs`) and the page carries the
// operations (`src/scripts/disk-storage.ts`).

import { joinFiles, splitFiles, type NamedFile } from './split-files.ts';

export interface DiskProject {
  /** Relative to the workspace root, `/`-separated; `.` is the root itself. */
  dir: string;
  files: NamedFile[];
  /** Newest file modification, epoch ms. */
  mtimeMs: number;
}

export type DiskOp =
  | { op: 'write'; dir: string; file: string; body: string }
  /** The server moves the file to the workspace trash; nothing is unlinked. */
  | { op: 'remove'; dir: string; file: string };

/** What the playground stores per project; a structural subset of
 *  `ScratchProject`, so this module needs nothing from the store. */
export interface ProjectRecord {
  id: string;
  name: string;
  source: string;
  updatedAt: number;
}

export const DISK_ID_PREFIX = 'scratch:disk:';
export const diskId = (dir: string): string => `${DISK_ID_PREFIX}${dir}`;

const SEGMENT = /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/;
export const FILE_NAME = /^[\w_.-]+\.circ$/;

/** A directory the server will accept: no empty, dotted or parent segments. */
export function isSafeDir(dir: string): boolean {
  if (dir === '.') return true;
  return dir.split('/').every((segment) => SEGMENT.test(segment) && segment !== '..');
}

/** The directory a project name maps to, or null when the name has no
 *  usable characters. `a b/c` becomes `a-b/c`. */
export function dirForName(name: string): string | null {
  const segments = name
    .split('/')
    .map((segment) => segment.trim().replace(/[^A-Za-z0-9_.-]+/g, '-').replace(/^[-.]+|-+$/g, ''))
    .filter((segment) => segment.length > 0);
  if (segments.length === 0) return null;
  const dir = segments.join('/');
  return isSafeDir(dir) ? dir : null;
}

const IMPORT = /^\s*import\s+\w+\s+"([^"<][^"]*)"/gm;

/**
 * Tab order for a directory: alphabetical, with the root last, because the
 * playground opens a project on its last file. The root is the file no
 * sibling imports; among several, `root.circ`, then `main.circ`, then the one
 * named after the directory, then the last by name.
 */
export function orderFiles(dir: string, files: readonly NamedFile[]): NamedFile[] {
  const sorted = [...files].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  if (sorted.length < 2) return sorted;
  const imported = new Set<string>();
  for (const file of sorted) {
    for (const match of file.body.matchAll(IMPORT)) imported.add(match[1]);
  }
  const roots = sorted.filter((file) => !imported.has(file.name));
  const candidates = roots.length > 0 ? roots : sorted;
  const base = dir.split('/').pop() ?? '';
  const preferred = ['root.circ', 'main.circ', `${base}.circ`];
  const root =
    preferred.map((name) => candidates.find((file) => file.name === name)).find((file) => file !== undefined) ??
    candidates[candidates.length - 1];
  return [...sorted.filter((file) => file !== root), root];
}

/**
 * Whether the combined text splits back into exactly these files. A comment
 * line that reads like a `// name.circ` marker in the middle of a file would
 * split it in two, and a save would then write the halves to disk; such a
 * project is left out instead.
 */
export function roundTrips(files: readonly NamedFile[]): boolean {
  if (files.length === 0) return false;
  if (!files.every((file) => FILE_NAME.test(file.name))) return false;
  const back = splitFiles(joinFiles(files));
  return back.length === files.length && back.every((file, i) => file.name === files[i].name && file.body === files[i].body);
}

export interface Skipped {
  dir: string;
  reason: string;
}

/**
 * The page's view of the workspace: which project id is which directory, and
 * what each directory held at the last read or write. `plan` compares an
 * edited project list against that and returns the writes that close the gap.
 */
export class DiskMirror {
  private readonly dirOf = new Map<string, string>();
  private readonly held = new Map<string, Map<string, string>>();
  /** Directories on disk the playground did not load; never written. */
  private readonly reserved = new Set<string>();

  load(projects: readonly DiskProject[]): { records: ProjectRecord[]; skipped: Skipped[] } {
    this.dirOf.clear();
    this.held.clear();
    this.reserved.clear();
    const records: ProjectRecord[] = [];
    const skipped: Skipped[] = [];
    for (const project of projects) {
      const files = orderFiles(project.dir, project.files);
      if (!isSafeDir(project.dir)) {
        skipped.push({ dir: project.dir, reason: 'the directory name has characters the playground cannot address' });
        this.reserved.add(project.dir);
        continue;
      }
      if (!roundTrips(files)) {
        skipped.push({ dir: project.dir, reason: 'a comment line reads like a `// name.circ` file marker' });
        this.reserved.add(project.dir);
        continue;
      }
      const id = diskId(project.dir);
      this.dirOf.set(id, project.dir);
      this.held.set(project.dir, new Map(files.map((file) => [file.name, file.body])));
      records.push({ id, name: project.dir, source: joinFiles(files), updatedAt: project.mtimeMs });
    }
    return { records, skipped };
  }

  /** The directory a project lives in, or null for one that is not on disk. */
  dirFor(id: string | null): string | null {
    return id === null ? null : this.dirOf.get(id) ?? null;
  }

  /** The id a project will have after a reload: its directory's. */
  stableId(id: string | null): string | null {
    if (id === null) return null;
    const dir = this.dirOf.get(id);
    return dir === undefined ? id : diskId(dir);
  }

  private taken(dir: string): boolean {
    return this.held.has(dir) || this.reserved.has(dir);
  }

  private freeDir(wanted: string): string {
    if (!this.taken(wanted)) return wanted;
    for (let n = 2; ; n += 1) {
      const candidate = `${wanted}-${n}`;
      if (!this.taken(candidate)) return candidate;
    }
  }

  /**
   * The writes that make the disk match `records`, applied to the mirror as
   * they are planned. A project gone from the list has its files removed; a
   * renamed project moves to the directory its new name maps to. Refuses a
   * plan that would remove more than one whole project, which no single
   * action in the playground does: that shape means the list is wrong.
   */
  plan(records: readonly ProjectRecord[]): { ops: DiskOp[]; refused: string | null } {
    const present = new Set(records.map((record) => record.id));
    const gone = [...this.dirOf.keys()].filter((id) => !present.has(id));
    if (gone.length > 1) {
      return { ops: [], refused: `refusing to remove ${gone.length} projects in one write` };
    }

    const ops: DiskOp[] = [];
    for (const id of gone) {
      const dir = this.dirOf.get(id)!;
      for (const file of this.held.get(dir)?.keys() ?? []) ops.push({ op: 'remove', dir, file });
      this.dirOf.delete(id);
      this.held.delete(dir);
    }

    for (const record of records) {
      const wanted = dirForName(record.name);
      let dir = this.dirOf.get(record.id);
      if (dir === undefined) {
        dir = this.freeDir(wanted ?? 'project');
        this.dirOf.set(record.id, dir);
        this.held.set(dir, new Map());
      } else if (wanted !== null && wanted !== dir && !this.taken(wanted)) {
        // Renamed: the files leave the old directory and land in the new one.
        for (const file of this.held.get(dir)?.keys() ?? []) ops.push({ op: 'remove', dir, file });
        this.held.delete(dir);
        dir = wanted;
        this.dirOf.set(record.id, dir);
        this.held.set(dir, new Map());
      }

      const before = this.held.get(dir)!;
      const after = new Map<string, string>();
      for (const file of splitFiles(record.source)) {
        if (FILE_NAME.test(file.name)) after.set(file.name, file.body);
      }
      for (const [file, body] of after) {
        if (before.get(file) !== body) ops.push({ op: 'write', dir, file, body });
      }
      for (const file of before.keys()) {
        if (!after.has(file)) ops.push({ op: 'remove', dir, file });
      }
      this.held.set(dir, after);
    }
    return { ops, refused: null };
  }
}
