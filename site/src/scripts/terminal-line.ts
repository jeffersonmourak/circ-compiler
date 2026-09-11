// The closed terminal line: what the drawer says about itself in one row.
//
// Row 3 of the bench (design file: `circ-compile nand.circ --sim > set a 1 ·
// ok`) shows the last thing typed at the console — by the reader, or by a
// face on their behalf — and the first line the protocol answered with. The
// transcript already holds every line the log shows (`console.ts`), so the
// summary is read off it rather than tracked beside it: one source, and a
// clear or a new session empties both at once.

import type { MemorySymbol } from '../utils/rom-image.ts';

export function memoryHeader(mem: Pick<MemorySymbol, 'kind' | 'width' | 'addrWidth'>, total: number): string {
  return `${mem.kind}[${mem.width},${mem.addrWidth}] · ${total} word${total === 1 ? '' : 's'}`;
}

export function legendFor(mem: Pick<MemorySymbol, 'addrWidth'>, addressed: number | null): string {
  const address = addressed === null ? '' : ` · addr = 0x${addressed.toString(16).padStart(Math.ceil(mem.addrWidth / 4), '0')}`;
  return `double-click a word to edit · ? unknown${address}`;
}

export function imageLine(mem: Pick<MemorySymbol, 'kind'>, meta: { file: string | null; words: number } | null): string {
  if (mem.kind === 'ram') return 'contents live in the circuit';
  if (!meta || meta.words === 0) return 'no image · the rom starts undefined';
  return `image · ${meta.file ?? 'hex bytes'} · ${meta.words} word${meta.words === 1 ? '' : 's'}`;
}

export interface TermSummary {
  /** The last line typed, without its `> ` echo prefix; null with no echo. */
  command: string | null;
  /** The first line the protocol printed after it; null while it is pending
   *  (or when nothing has been typed). */
  reply: string | null;
}

const ECHO = '> ';
const NOTE = '#';

/** The last echo in the transcript and the reply that followed it. Notes
 *  (`# …`) after the echo are skipped: a `reset` prints one before its `ok`. */
export function summaryOf(lines: readonly string[]): TermSummary {
  let at = -1;
  for (let i = lines.length - 1; i >= 0; i--) {
    if (lines[i].startsWith(ECHO)) {
      at = i;
      break;
    }
  }
  if (at === -1) return { command: null, reply: null };
  const command = lines[at].slice(ECHO.length);
  for (let i = at + 1; i < lines.length; i++) {
    const line = lines[i];
    if (line.startsWith(ECHO)) break;
    if (line.startsWith(NOTE)) continue;
    return { command, reply: line };
  }
  return { command, reply: null };
}
