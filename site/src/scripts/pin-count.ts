// The Data button's count (design file, board 3d: `Data  8 → 3`): the root
// file's input pins and output pins. Pins, not bits — a 4-wide `input[4] a`
// is one pin here, where the truth table's cap counts its four bits.
import type { AnalyzeSymbol } from './circ-diagnostics.ts';

/** `N → M` over the root file's `input` and `output` symbols; the empty
 *  string when the root is unknown (no analysis, or the root path unmapped). */
export function pinCountLabel(symbols: readonly AnalyzeSymbol[], rootId: number | null): string {
  if (rootId === null) return '';
  let inputs = 0;
  let outputs = 0;
  for (const s of symbols) {
    if (s.file_id !== rootId) continue;
    if (s.kind === 'input') inputs++;
    else if (s.kind === 'output') outputs++;
  }
  return `${inputs} → ${outputs}`;
}
