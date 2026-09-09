// Multi-file sources are recognised by `// <name>.circ` line markers. The
// LAST file is the root (it imports the others). A marker only opens a new
// file when there is no current file yet or the current one has non-blank
// content; otherwise the marker line stays in the current body as an
// ordinary comment. Shared by scripts/compile-content.ts and the playground.

/** The two fields a tab edits. `SplitFile` adds `startLine` for callers that
 *  map a diagnostic into a COMBINED document; tabs never need it. */
export interface NamedFile {
  name: string;
  body: string;
}

export interface SplitFile extends NamedFile {
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

/**
 * Exact inverse of `splitFiles`. Every file emits `// <name>` on its own line
 * followed by its body, and the segments join with '\n' — precisely the line
 * list `splitFiles` consumes, since a marker line is consumed by the splitter
 * and never becomes a body line. Bodies therefore keep their exact leading and
 * trailing newlines.
 *
 * Round-tripping is byte-exact except for three normalisations, each pinned by
 * a test: a redundant leading `// main.circ` marker is dropped, a source whose
 * LAST line is a marker gains one trailing newline (that file's body-line list
 * is empty), and a non-canonical marker (`//   a.circ`, `// a.circ `) re-emits
 * canonically, because MARKER captures neither the inner nor the trailing
 * whitespace.
 */
export function joinFiles(files: readonly NamedFile[]): string {
  return files
    .map((f, i) => (omitsMarker(f, i) ? f.body : `// ${f.name}\n${f.body}`))
    .join('\n');
}

/** Only a LEADING `main.circ` may go unmarked, and only when its first body
 *  line would not itself be read as a marker: `splitFiles` opens a file on a
 *  marker whenever there is no current file, so an unmarked first body line
 *  matching MARKER would be eaten as the file name. */
function omitsMarker(f: NamedFile, i: number): boolean {
  return i === 0 && f.name === 'main.circ' && !MARKER.test(f.body.split('\n', 1)[0]);
}

/** Would `// ${name}` be read back as a marker naming exactly `name`? Derived
 *  from MARKER so the tab UI and the splitter cannot drift: this rejects '',
 *  'foo', 'a/b.circ', '<builtin>/xor.circ' and 'a.circ ' (whose trailing space
 *  MARKER tolerates but does not capture). */
export function isFileName(name: string): boolean {
  const m = `// ${name}`.match(MARKER);
  return m !== null && m[1] === name;
}

/** File arrays the marker format — or the request builder — cannot represent.
 *  The first two are body-level; the last two are name-level. */
export type JoinConflict = 'blank-body' | 'marker-in-body' | 'illegal-name' | 'duplicate-name';

/**
 * Every way `files` fails to survive a round trip, by index.
 *
 * - `blank-body`: a non-last file with no non-blank line. The marker that
 *   should end it is swallowed as a comment, so the pair silently merges.
 * - `marker-in-body`: a marker-looking line AFTER non-blank content. The
 *   splitter opens a new file there. A marker line before any content is fine.
 * - `illegal-name`: `// <name>` would not read back as a marker naming exactly
 *   `name`, so the emitted marker is not a marker and the files merge.
 * - `duplicate-name`: `requestFor` keys by `/playground/<name>`, so the earlier
 *   body would be dropped from the request with no diagnostic at all.
 */
export function joinConflicts(files: readonly NamedFile[]): { index: number; reason: JoinConflict }[] {
  const out: { index: number; reason: JoinConflict }[] = [];
  const seen = new Set<string>();
  files.forEach((f, i) => {
    if (!isFileName(f.name)) out.push({ index: i, reason: 'illegal-name' });
    if (seen.has(f.name)) out.push({ index: i, reason: 'duplicate-name' });
    seen.add(f.name);

    const lines = f.body.split('\n');
    const isLast = i === files.length - 1;
    if (!isLast && !lines.some((l) => l.trim().length > 0)) {
      out.push({ index: i, reason: 'blank-body' });
    }
    // A marker line only opens a new file once the body holds non-blank
    // content — the same condition `splitFiles` applies.
    let sawContent = false;
    for (const line of lines) {
      if (sawContent && MARKER.test(line)) {
        out.push({ index: i, reason: 'marker-in-body' });
        break;
      }
      if (line.trim().length > 0) sawContent = true;
    }
  });
  return out;
}

export const rootOf = <T extends NamedFile>(files: readonly T[]): T => files[files.length - 1];

/** The playground's virtual directory: every file keyed under /playground/. */
export const PLAYGROUND_DIR = '/playground';

/** Build the libcirc request for a split source (root = last file). */
export function requestFor(files: readonly NamedFile[], options?: Record<string, unknown>) {
  const map: Record<string, string> = {};
  for (const f of files) map[`${PLAYGROUND_DIR}/${f.name}`] = f.body;
  return {
    root: `${PLAYGROUND_DIR}/${rootOf(files).name}`,
    files: map,
    ...(options ? { options } : {}),
  };
}
