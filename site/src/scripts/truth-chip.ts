// The Truth chip's words (design file 3f: `N input bits · R rows · cap C`,
// and why, when the reader is blocked). Eager: the chip is on screen before
// a table is asked for, and `truth-view.ts` reaches the renderer.

export interface ChipInput {
  /** The root's input bits, or null before an analysis. */
  bits: number | null;
  /** Rows on screen, or null. */
  rows: number | null;
  cap: number;
  /** The refusal, or null. */
  blocked: string | null;
  /** The over-cap path is on screen. */
  filtered: boolean;
  unknownBits?: number;
}

/** The first clause of a refusal: up to its first `;` or `.`. */
const firstClause = (s: string): string => {
  const at = s.search(/[;.]/);
  return (at === -1 ? s : s.slice(0, at)).trim();
};

/** `N input bits · R rows · cap C`, then why it is filtered or blocked. */
export function chipText(c: ChipInput): string {
  const parts: string[] = [];
  if (c.bits !== null) parts.push(`${c.bits} input bit${c.bits === 1 ? '' : 's'}`);
  if (c.rows !== null) parts.push(`${c.rows} row${c.rows === 1 ? '' : 's'}`);
  parts.push(`cap ${c.cap}`);
  if (c.blocked) parts.push(firstClause(c.blocked));
  else if (c.filtered) parts.push('filtered to the current pins');
  else if (c.unknownBits !== undefined && c.unknownBits > c.cap) parts.push(`over the cap: ${c.unknownBits} unknown bits`);
  return parts.join(' · ');
}
