// Multi-file sources are recognised by `// <name>.circ` line markers. The
// LAST file is the root (it imports the others). A marker only opens a new
// file when there is no current file yet or the current one has non-blank
// content; otherwise the marker line stays in the current body as an
// ordinary comment. Shared by scripts/compile-content.ts and the playground.

export interface SplitFile {
  name: string;
  body: string;
  /** 0-based line index, in the combined text, of this file's first body line. */
  startLine: number;
}

const MARKER = /^\/\/\s+([\w_.-]+\.circ)\s*$/;

export function splitFiles(source: string): SplitFile[] {
  const lines = source.split('\n');
  const files: { name: string; body: string[]; startLine: number }[] = [];
  let cur: { name: string; body: string[]; startLine: number } | null = null;
  lines.forEach((line, i) => {
    const m = line.match(MARKER);
    if (m && (!cur || cur.body.some((l) => l.trim().length > 0))) {
      if (cur) files.push(cur);
      cur = { name: m[1], body: [], startLine: i + 1 };
    } else {
      cur ??= { name: 'main.circ', body: [], startLine: 0 };
      cur.body.push(line);
    }
  });
  if (cur) files.push(cur);
  return files.map((f) => ({ name: f.name, body: f.body.join('\n'), startLine: f.startLine }));
}

export const rootOf = (files: SplitFile[]): SplitFile => files[files.length - 1];

/** The playground's virtual directory: every file keyed under /playground/. */
export const PLAYGROUND_DIR = '/playground';

/** Build the libcirc request for a split source (root = last file). */
export function requestFor(files: SplitFile[], options?: Record<string, unknown>) {
  const map: Record<string, string> = {};
  for (const f of files) map[`${PLAYGROUND_DIR}/${f.name}`] = f.body;
  return {
    root: `${PLAYGROUND_DIR}/${rootOf(files).name}`,
    files: map,
    ...(options ? { options } : {}),
  };
}
