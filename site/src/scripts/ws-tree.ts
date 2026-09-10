// The workspace explorer's shape, as data.
//
// The sidebar is a tree of three levels: a GROUP folder ("Introduction",
// "Yours"), the PROJECTS inside it, and — under the one project that is open —
// its FILES. Only the open project has file children, because a project that
// is not open is a single combined string in the envelope and splitting every
// one of them to draw a subtree nobody asked for would be work for nothing.
//
// Everything here is pure and DOM-free: the island renders `visibleNodes` and
// wires events to the ids, and `bun test` drives the flattening, the expansion
// rules and the whole keyboard model without a browser.
//
// The flat list is the point. A tree's keyboard contract (up/down walk what
// the reader can SEE, not what the data contains) is unimplementable against a
// nested structure without re-walking it on every keystroke; against a flat
// array of visible rows it is an index ± 1.

import type { TabCounts } from './file-tabs.ts';

/** A workspace group heading, e.g. `Introduction` or `Yours`. */
export interface GroupNode {
  kind: 'group';
  /** Stable id, used as the DOM id suffix and as the persisted expansion key. */
  id: string;
  label: string;
  level: 1;
  expanded: boolean;
  /** Rendered as `3 items`; a group with none is still shown, so "Yours"
   *  does not vanish before the reader has made anything. */
  count: number;
}

export interface ProjectNode {
  kind: 'project';
  /** The catalogue/scratch pick id, e.g. `example:half-adder`. */
  id: string;
  label: string;
  level: 2;
  /** The project the editor currently holds. */
  active: boolean;
  /** Only an active project has file children to expand. */
  expandable: boolean;
  expanded: boolean;
  /** Scratch projects can be renamed, duplicated and deleted; content cannot. */
  editable: boolean;
  /** Worst severity across its files, or null. Only ever set on the active
   *  project, since it is the only one that has been analysed. */
  severity: Severity | null;
  /** The count behind that severity. */
  badge: number;
}

export interface FileNode {
  kind: 'file';
  /** `<projectId>/<index>`, unique across the tree. */
  id: string;
  label: string;
  level: 3;
  /** Index into `FileTabsState.files`. */
  index: number;
  /** The file the editor is showing. */
  active: boolean;
  /** The last file is the root; the compiler starts there. */
  root: boolean;
  severity: Severity | null;
  badge: number;
  /** Why this file cannot be written back to the combined source, or null. */
  conflict: string | null;
}

export type Severity = 'error' | 'warning';
export type TreeNode = GroupNode | ProjectNode | FileNode;

export interface TreeInput {
  /** Groups in display order, each with its projects in display order. */
  groups: readonly { id: string; label: string; projects: readonly ProjectInput[] }[];
  /** The open project, or null before one is loaded. */
  activeId: string | null;
  /** The open project's files. Empty when nothing is loaded. */
  files: readonly { name: string }[];
  /** Which of those files the editor is showing. */
  activeFile: number;
  /** Per-file diagnostic counts, parallel to `files`. */
  counts: readonly TabCounts[];
  /** File index → why it is unrepresentable. */
  conflicts: ReadonlyMap<number, string>;
  /** Ids of the groups and projects the reader has open. */
  expanded: ReadonlySet<string>;
  /**
   * What the last analysis of each project said, by pick id.
   *
   * Only one project is loaded at a time, so `counts` describes that one and
   * nothing else. Without this, switching away from a broken project made its
   * badge vanish — the reader was told the problem had gone when all that had
   * gone was the analysis. A project stays in here until it is deleted, and
   * its source cannot change while it is not the open one.
   */
  remembered?: ReadonlyMap<string, TabCounts>;
}

export interface ProjectInput {
  id: string;
  label: string;
  editable: boolean;
}

const worst = (c: TabCounts): { severity: Severity | null; badge: number } =>
  c.errors > 0
    ? { severity: 'error', badge: c.errors }
    : c.warnings > 0
      ? { severity: 'warning', badge: c.warnings }
      : { severity: null, badge: 0 };

/** `<projectId>/<index>` — the id a file row carries. */
export const fileNodeId = (projectId: string, index: number): string => `${projectId}/${index}`;

/**
 * Flatten the tree to exactly the rows a reader can see, in visual order.
 *
 * A collapsed group contributes its own row and nothing below it, which is
 * what makes every keyboard move an index step. The active project's files
 * appear only when both its group and the project itself are expanded.
 */
export function visibleNodes(input: TreeInput): TreeNode[] {
  const out: TreeNode[] = [];
  for (const group of input.groups) {
    const groupOpen = input.expanded.has(group.id);
    out.push({
      kind: 'group',
      id: group.id,
      label: group.label,
      level: 1,
      expanded: groupOpen,
      count: group.projects.length,
    });
    if (!groupOpen) continue;

    for (const project of group.projects) {
      const active = project.id === input.activeId;
      // Only the open project has files to show, and only when it has any:
      // an expandable node with an empty child list is a twisty that does
      // nothing, which is worse than no twisty at all.
      const expandable = active && input.files.length > 0;
      const projectOpen = expandable && input.expanded.has(project.id);
      // Live counts for the project that is loaded; the last known ones for
      // every other project that has been visited this session.
      const roll = active
        ? rollUp(input.counts)
        : worst(input.remembered?.get(project.id) ?? { errors: 0, warnings: 0 });
      out.push({
        kind: 'project',
        id: project.id,
        label: project.label,
        level: 2,
        active,
        expandable,
        expanded: projectOpen,
        editable: project.editable,
        severity: roll.severity,
        badge: roll.badge,
      });
      if (!projectOpen) continue;

      const last = input.files.length - 1;
      input.files.forEach((file, index) => {
        const w = worst(input.counts[index] ?? { errors: 0, warnings: 0 });
        out.push({
          kind: 'file',
          id: fileNodeId(project.id, index),
          label: file.name,
          level: 3,
          index,
          active: index === input.activeFile,
          root: index === last,
          severity: w.severity,
          badge: w.badge,
          conflict: input.conflicts.get(index) ?? null,
        });
      });
    }
  }
  return out;
}

/** Every file's diagnostics added up. What the island remembers per project. */
export function sumCounts(counts: readonly TabCounts[]): TabCounts {
  let errors = 0;
  let warnings = 0;
  for (const c of counts) {
    errors += c.errors;
    warnings += c.warnings;
  }
  return { errors, warnings };
}

/** The project row's badge: the whole project's worst news, so a collapsed
 *  project still says that something inside it is broken. */
export function rollUp(counts: readonly TabCounts[]): { severity: Severity | null; badge: number } {
  return worst(sumCounts(counts));
}

/**
 * Which group holds a pick id, or null.
 *
 * Used to reveal the active project: switching to something inside a collapsed
 * group must open that group, or the reader is looking at a sidebar that does
 * not contain what the editor is showing.
 */
export function groupOf(input: Pick<TreeInput, 'groups'>, pickId: string | null): string | null {
  if (pickId === null) return null;
  for (const group of input.groups) {
    if (group.projects.some((p) => p.id === pickId)) return group.id;
  }
  return null;
}

// ---------------------------------------------------------------------------
// The keyboard model.
// ---------------------------------------------------------------------------

export type TreeKey =
  | 'ArrowDown'
  | 'ArrowUp'
  | 'ArrowRight'
  | 'ArrowLeft'
  | 'Home'
  | 'End';

export type Move =
  | { kind: 'focus'; index: number }
  | { kind: 'expand'; id: string }
  | { kind: 'collapse'; id: string }
  | null;

/** Can this row be opened at all? Groups always; projects only when active. */
const isExpandable = (n: TreeNode): boolean =>
  n.kind === 'group' || (n.kind === 'project' && n.expandable);

const isExpanded = (n: TreeNode): boolean =>
  (n.kind === 'group' || n.kind === 'project') && n.expanded;

/**
 * The standard tree keyboard contract, as a value.
 *
 * Right opens a closed row, then steps into it. Left closes an open one, then
 * steps out to its parent. Up and down walk what is visible. Nothing here
 * mutates: the island applies the returned move, so every branch is testable
 * without a DOM and without a store.
 *
 * `null` means the key is not ours — the caller must NOT preventDefault, or a
 * reader loses Home/End inside a rename input.
 */
export function moveFor(nodes: readonly TreeNode[], from: number, key: TreeKey): Move {
  if (nodes.length === 0) return null;
  const node = nodes[from];
  if (!node) return null;

  switch (key) {
    case 'ArrowDown':
      return from < nodes.length - 1 ? { kind: 'focus', index: from + 1 } : null;
    case 'ArrowUp':
      return from > 0 ? { kind: 'focus', index: from - 1 } : null;
    case 'Home':
      return { kind: 'focus', index: 0 };
    case 'End':
      return { kind: 'focus', index: nodes.length - 1 };
    case 'ArrowRight':
      if (!isExpandable(node)) return null;
      if (!isExpanded(node)) return { kind: 'expand', id: node.id };
      // Already open: step to the first child, which is simply the next row.
      return from < nodes.length - 1 ? { kind: 'focus', index: from + 1 } : null;
    case 'ArrowLeft':
      if (isExpandable(node) && isExpanded(node)) return { kind: 'collapse', id: node.id };
      return parentOf(nodes, from);
  }
}

/** The nearest row above with a smaller level — a tree's "go to parent". */
function parentOf(nodes: readonly TreeNode[], from: number): Move {
  const level = nodes[from].level;
  for (let i = from - 1; i >= 0; i -= 1) {
    if (nodes[i].level < level) return { kind: 'focus', index: i };
  }
  return null;
}

/**
 * The expansion set after a toggle, as a new set.
 *
 * Returned rather than mutated so the caller decides what to persist, and so
 * a test can assert the value instead of a side effect.
 */
export function toggle(expanded: ReadonlySet<string>, id: string): Set<string> {
  const next = new Set(expanded);
  if (!next.delete(id)) next.add(id);
  return next;
}

/** Open every ancestor of `pickId`, so a project the editor just loaded is on
 *  screen even when the reader had its group closed. */
export function reveal(
  expanded: ReadonlySet<string>,
  input: Pick<TreeInput, 'groups'>,
  pickId: string | null,
): Set<string> {
  const next = new Set(expanded);
  const group = groupOf(input, pickId);
  if (group) next.add(group);
  if (pickId) next.add(pickId);
  return next;
}
