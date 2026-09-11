// The console's pure parts: what the prompt remembers, what the scrollback
// holds, where a `load` or `save` is sent, and the two things the console
// prints that the executor does not — the echo of a line and the help.
//
// Everything the console shows is the executor's reply, so a reader can
// paste the scrollback into a `--sim` script and expect the same answers.
// The echo is prefixed so it cannot be mistaken for a reply, and the help
// is comment lines, which the protocol ignores.

import type { FileSource } from './sim-executor.ts';

/**
 * The prompt's ↑/↓ history: the last `cap` submitted lines, newest last.
 * `up` walks back and stays on the oldest; `down` walks forward and, past
 * the newest, gives back the empty line the reader started from. A submit
 * pushes and resets the cursor.
 */
export class HistoryRing {
  private lines: string[] = [];
  private cursor: number;

  constructor(readonly cap = 100) {
    this.cursor = 0;
  }

  get size(): number {
    return this.lines.length;
  }

  push(line: string): void {
    if (line.length > 0 && this.lines[this.lines.length - 1] !== line) {
      this.lines.push(line);
      if (this.lines.length > this.cap) this.lines.splice(0, this.lines.length - this.cap);
    }
    this.reset();
  }

  up(): string | null {
    if (this.lines.length === 0) return null;
    if (this.cursor > 0) this.cursor -= 1;
    return this.lines[this.cursor];
  }

  down(): string | null {
    if (this.lines.length === 0) return null;
    if (this.cursor >= this.lines.length) return null;
    this.cursor += 1;
    return this.cursor === this.lines.length ? '' : this.lines[this.cursor];
  }

  /** Back to the prompt's own line, past the newest entry. */
  reset(): void {
    this.cursor = this.lines.length;
  }
}

/** The scrollback: the newest `cap` lines, joined for a `<pre>`. */
export class Transcript {
  private lines: string[] = [];

  constructor(readonly cap = 2000) {}

  append(lines: readonly string[]): void {
    if (lines.length === 0) return;
    this.lines.push(...lines);
    if (this.lines.length > this.cap) this.lines.splice(0, this.lines.length - this.cap);
  }

  clear(): void {
    this.lines = [];
  }

  get length(): number {
    return this.lines.length;
  }

  get text(): string {
    return this.lines.join('\n');
  }

  /** The last line, for the status announcement. */
  get last(): string | null {
    return this.lines.length === 0 ? null : this.lines[this.lines.length - 1];
  }
}

export const LOAD_REFUSAL = 'load images in the Memory tab';
export const SAVE_REFUSAL = 'save images from the Memory tab';

/**
 * The page's `FileSource`: a browser has no working directory, and the page
 * already has one place that reads and shows an image. Every path is
 * refused with a reason that names it, and the executor keeps the reply
 * protocol-shaped: `err E_IO <path>: load images in the Memory tab`.
 */
export class MemoryTabFiles implements FileSource {
  read(_path: string): { ok: false; error: string } {
    return { ok: false, error: LOAD_REFUSAL };
  }

  write(_path: string, _bytes: Uint8Array): { ok: false; error: string } {
    return { ok: false, error: SAVE_REFUSAL };
  }
}

/** How a submitted line appears in the scrollback, so it cannot read as a reply. */
export const promptEcho = (line: string): string => `> ${line}`;

/** The browser's one extra verb. */
export const HELP_VERB = 'help';

/**
 * The command table as comment lines, which a `--sim` script would ignore.
 * `help` and the two file verbs are the browser's own notes; every other row
 * is `DOCS/sim-protocol.md`'s.
 */
export function helpLines(): string[] {
  const rows: [string, string][] = [
    ['pins', 'the root pins, as the handshake lists them'],
    ['set <pin> <value> [<mask>]', 'drive an input and settle; `set a 0 0` is unknown'],
    ['get <pin>', 'read a pin: `ok <value> <defined>`'],
    ['dump <in|out|all>', 'read every pin of a kind'],
    ['eval <pin>=<value>[/<mask>] ... => <pin> ...', 'drive, then read, in one line'],
    ['run', 'drain the event queue (a `set` already settles)'],
    ['reset', 'every pin unknown; the Memory tab\'s images reloaded'],
    ['quit', '`ok bye`, then the same as reset'],
    ['mems', 'the root memories'],
    ['peek <mem> <addr>', 'read one cell'],
    ['poke <mem> <addr> <value> [<mask>]', 'write one cell and settle'],
    ['mem <mem> [<start> [<count>]]', 'read a range of cells'],
    ['clear <mem>', 'every cell unknown'],
    ['load <mem> <path>', 'refused here: load images in the Memory tab'],
    ['save <mem> <path>', 'refused here: save images from the Memory tab'],
    ['help', 'this table'],
  ];
  const width = Math.max(...rows.map(([cmd]) => cmd.length));
  return [
    '# values: decimal, 0x, 0o or 0b, with _ between digits; replies are 0x hex',
    ...rows.map(([cmd, note]) => `# ${cmd.padEnd(width)}  ${note}`),
  ];
}
