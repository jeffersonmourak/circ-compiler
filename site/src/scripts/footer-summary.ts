// The diagnostics footer's two strings.
//
// The bar under the editor (design file 3b) says what the compiler thinks of
// the source on the left — `N errors · N warnings` — and what the source is
// made of on the right — `N lines · N components · N <noun>`. Both are pure
// functions of what the island already holds: the tab bodies, the last
// analysis and the mapped diagnostics. The noun is the boards' own: a project
// with a memory counts memories, one with chips counts chips, and a plain one
// counts pins. The analyze reply carries no nets, so the boards' `4 nets` has
// no source and is not shown.
import type { Analysis, AnalyzeSymbol } from './circ-diagnostics.ts';
import { PLAYGROUND_DIR } from '../utils/split-files.ts';

export interface FooterSummary {
  errors: number;
  warnings: number;
  /** Lines over every file of the project, a trailing newline counted once. */
  lines: number;
  /** Project symbols whose kind is neither `input` nor `output`; null before
   *  an analysis. */
  components: number | null;
  /** The third slot: what the circuit is made of, in the boards' noun. */
  extra: { count: number; noun: 'memory' | 'chip' | 'pin' } | null;
}

/** Lines in a body: one more than its newlines, less one when the body ends
 *  with a newline, so `a\nb\n` is two lines and `a\nb` is two lines too. */
export function lineCount(body: string): number {
  if (body === '') return 1;
  let n = 1;
  for (let i = 0; i < body.length; i++) if (body.charCodeAt(i) === 10) n++;
  if (body.endsWith('\n')) n--;
  return n;
}

/** The symbols declared in the project's own files, by the rule
 *  `countsByFile` uses: a path under `PLAYGROUND_DIR`. Builtin files never
 *  count, whatever they declare. */
export function projectSymbols(analysis: Analysis): AnalyzeSymbol[] {
  const own = new Set<number>();
  for (const f of analysis.files) if (f.path.startsWith(`${PLAYGROUND_DIR}/`)) own.add(f.file_id);
  return analysis.symbols.filter((s) => own.has(s.file_id));
}

export function summarize(
  files: readonly { name: string; body: string }[],
  analysis: Analysis | null,
  mapped: readonly { severity: 'error' | 'warning' }[],
): FooterSummary {
  let errors = 0;
  for (const m of mapped) if (m.severity === 'error') errors++;
  const warnings = mapped.length - errors;
  let lines = 0;
  for (const f of files) lines += lineCount(f.body);
  if (!analysis) return { errors, warnings, lines, components: null, extra: null };

  const symbols = projectSymbols(analysis);
  const of = (...kinds: AnalyzeSymbol['kind'][]) => symbols.filter((s) => kinds.includes(s.kind)).length;
  const components = symbols.length - of('input', 'output');
  const memories = of('rom', 'ram');
  const chips = of('instance');
  const extra =
    memories > 0 ? { count: memories, noun: 'memory' as const }
    : chips > 0 ? { count: chips, noun: 'chip' as const }
    : { count: of('input', 'output'), noun: 'pin' as const };
  return { errors, warnings, lines, components, extra };
}

const plural = (n: number, noun: string, many = `${noun}s`): string => `${n} ${n === 1 ? noun : many}`;

/** `['0 errors · 1 warning', '16 lines · 16 components · 22 pins']`; the
 *  right string is `'16 lines'` alone before an analysis. */
export function summaryLabels(s: FooterSummary): [left: string, right: string] {
  const left = `${plural(s.errors, 'error')} · ${plural(s.warnings, 'warning')}`;
  const parts = [plural(s.lines, 'line')];
  if (s.components !== null) parts.push(plural(s.components, 'component'));
  if (s.extra) parts.push(plural(s.extra.count, s.extra.noun, s.extra.noun === 'memory' ? 'memories' : `${s.extra.noun}s`));
  return [left, parts.join(' · ')];
}
