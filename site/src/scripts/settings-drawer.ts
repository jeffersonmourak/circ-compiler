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

/**
 * Why the truth table cannot run right now, or null.
 *
 * Two refusals, in the order they matter. A circuit with errors has no
 * artifact to enumerate, so the cap is moot until it builds; only then does
 * the width matter. The island puts this string on the tab as its tooltip and
 * in the panel as its body, so the reader gets the same sentence whichever way
 * they arrive at it.
 *
 * `errors` is a count of error-severity diagnostics, and `bits` is null until
 * an analysis lands — neither being known yet is not a refusal.
 */
export interface TruthTableState {
  /** How many error-severity diagnostics the analysis reported. */
  errors: number;
  /** The first of them, `code message`, so the tooltip names something the
   *  reader can act on rather than only counting. Null when unknown. */
  firstError?: string | null;
  /** Total input width of the root file; null until an analysis lands. */
  bits: number | null;
}

export function truthTableRefusal(t: TruthTableState, s: PlaygroundSettings): string | null {
  if (t.errors > 0) {
    const tail = 'A truth table needs a circuit that compiles.';
    if (!t.firstError) {
      return `${t.errors} error${t.errors === 1 ? '' : 's'} to fix first. ${tail}`;
    }
    return t.errors === 1
      ? `One error to fix first — ${t.firstError}. ${tail}`
      : `${t.errors} errors to fix first, starting with ${t.firstError}. ${tail}`;
  }
  return capRefusal(t.bits, s);
}

// ---------------------------------------------------------------------------
// The drawer's DOM wiring. Kept here rather than in the island so the island
// stays markup plus a script, and so this can change without touching it.
// ---------------------------------------------------------------------------

export interface SettingsDeps {
  get(): PlaygroundSettings;
  /** Applies a mutation to the stored settings and re-runs whatever reads them. */
  set(mutate: (draft: PlaygroundSettings) => void): void;
}

/** Which control shape each setting uses, derived from the value's type. */
type BoolKey = 'expandMacros' | 'expandDisplay' | 'warningsAsErrors';
type ChoiceKey = 'format' | 'valueFormat';

/**
 * Bind every `data-setting` control in the drawer to the stored settings.
 *
 * Each control is read once to paint the current value and then writes back on
 * change; nothing here validates, because the store already clamps and falls
 * back key by key, and a second validator is a second thing to disagree with.
 */
export function mountSettingsDrawer(root: ParentNode, deps: SettingsDeps): void {
  const controls = root.querySelectorAll<HTMLInputElement | HTMLSelectElement>('[data-setting]');

  const paint = () => {
    const s = deps.get();
    for (const el of controls) {
      const key = el.dataset.setting as keyof PlaygroundSettings;
      if (el instanceof HTMLInputElement && el.type === 'checkbox') {
        el.checked = Boolean(s[key as BoolKey]);
      } else if (el instanceof HTMLInputElement && el.type === 'number') {
        el.value = String(s.truthTableCap);
      } else {
        el.value = String(s[key as ChoiceKey]);
      }
    }
  };

  for (const el of controls) {
    el.addEventListener('change', () => {
      const key = el.dataset.setting as keyof PlaygroundSettings;
      deps.set((draft) => {
        if (el instanceof HTMLInputElement && el.type === 'checkbox') {
          (draft[key as BoolKey] as boolean) = el.checked;
        } else if (el instanceof HTMLInputElement && el.type === 'number') {
          const n = Number.parseInt(el.value, 10);
          // The store clamps; this only refuses to write a non-number.
          if (Number.isFinite(n)) draft.truthTableCap = n;
        } else {
          (draft[key as ChoiceKey] as string) = el.value;
        }
      });
      // Repaint from the store, so a clamped value is shown as stored rather
      // than as typed.
      paint();
    });
  }

  paint();
}

