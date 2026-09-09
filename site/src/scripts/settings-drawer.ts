// The compiler options a reader can change, and the one place that decides
// which of them each request carries.
//
// An unknown or mistyped option key is a bad request, never a silent default,
// so nothing here builds a key from a variable and nothing sends a key the
// library does not document for that operation. `PlaygroundSettings` and its
// normalisation belong to the store; this module only projects them.
import type { PlaygroundSettings } from '../utils/playground-store.ts';

/** Every key the library documents. Nothing outside this list is ever sent. */
export const DOCUMENTED_OPTION_KEYS = [
  'expand_macros',
  'expand_display',
  'color',
  'format',
  'value_format',
  'truth_table_cap',
  'preloads',
  'warnings_as_errors',
] as const;

export type DocumentedOptionKey = (typeof DOCUMENTED_OPTION_KEYS)[number];

export type LibcircOp = 'analyze' | 'compile' | 'preview' | 'truth_table';

/**
 * The options one request carries.
 *
 * Only the keys the library marks as *used by* that operation are sent. A key
 * that means nothing to an operation is not merely useless there — sending it
 * is indistinguishable from sending a typo, and both are refused.
 *
 * The names are snake_case because that is the wire contract; the stored
 * settings are camelCase precisely so an envelope can never be spread into a
 * request.
 */
export function optionsFor(
  op: LibcircOp,
  s: PlaygroundSettings,
  preloads?: Record<string, string>,
): Record<string, unknown> {
  switch (op) {
    case 'analyze':
      // The analyze entry point never reads options.
      return {};
    case 'compile':
      return { warnings_as_errors: s.warningsAsErrors };
    case 'preview':
      return {
        // Not reader-facing: the page has no TTY and never wants ANSI.
        color: 'never',
        expand_macros: s.expandMacros,
        expand_display: s.expandDisplay,
        warnings_as_errors: s.warningsAsErrors,
      };
    case 'truth_table':
      return {
        format: s.format,
        value_format: s.valueFormat,
        truth_table_cap: s.truthTableCap,
        warnings_as_errors: s.warningsAsErrors,
        ...(preloads && Object.keys(preloads).length > 0 ? { preloads } : {}),
      };
  }
}

/**
 * The page's own refusal before a truth table is requested, or null.
 *
 * This reads the same field `optionsFor` sends as `truth_table_cap`, so the
 * pre-flight and the request cannot disagree — they used to be two constants.
 * The pre-flight matters because an enumeration cannot be stopped once it has
 * started: the worker has no abort.
 *
 * `bits` is null when no analysis has landed yet, which is not a refusal.
 */
export function capRefusal(bits: number | null, s: PlaygroundSettings): string | null {
  if (bits === null || bits <= s.truthTableCap) return null;
  return (
    `This circuit has ${bits} input bits; the playground enumerates up to ${s.truthTableCap} ` +
    `(${2 ** s.truthTableCap} rows). Raise the cap in settings, or use circ-compile --truth-table.`
  );
}
