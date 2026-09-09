// The editor palette, derived at build time from the same `shikiLight` /
// `shikiDark` objects the docs code blocks use, so the playground editor and a
// ```circ fence on /reference can never drift apart.
//
// Pure and DOM-free on purpose: it imports no CodeMirror package and no
// `@lezer/highlight`, naming every tag as a plain string instead. That is what
// lets `bun test` prove the derivation without a browser — `createEditor`
// builds real DOM nodes unconditionally, so the wiring in `circ-editor.ts`
// cannot be exercised headlessly, but this can.
import { shikiLight, shikiDark } from './shiki-themes.mjs';

export type ThemeMode = 'light' | 'dark';

/**
 * One `HighlightStyle` spec, with the tag named as a STRING.
 *
 * Shiki's `settings.fontStyle` is a TextMate token setting, not a CSS
 * property, and it must be split here rather than passed through.
 * `HighlightStyle.define` hands every non-`tag`, non-`class` key straight to
 * style-mod as a CSS property, and style-mod kebab-cases it — so a
 * pass-through `fontStyle: 'bold'` emits `font-style: bold`, invalid CSS that
 * every browser drops without warning. `keyword` is exactly the scope that
 * carries `fontStyle: 'bold'` in both themes, so the most prominent token
 * class is the one that would silently lose its weight.
 */
export interface TagSpec {
  tag: string;
  color: string;
  fontStyle?: 'italic';
  fontWeight?: 'bold';
  textDecoration?: 'underline';
}

/** The scope each CodeMirror tag reads out of a shiki theme's `tokenColors`. */
export const TAG_SCOPES: readonly { tag: string; scope: string }[] = [
  { tag: 'comment', scope: 'comment' },
  { tag: 'string', scope: 'string' },
  { tag: 'number', scope: 'constant.numeric' },
  { tag: 'keyword', scope: 'keyword' },
  { tag: 'typeName', scope: 'support.type' },
  { tag: 'operator', scope: 'keyword.operator' },
  { tag: 'variableName.function', scope: 'entity.name.function' },
  { tag: 'variableName', scope: 'variable' },
  { tag: 'propertyName', scope: 'variable.parameter' },
  { tag: 'punctuation', scope: 'punctuation' },
  { tag: 'invalid', scope: 'invalid' },
];

/** The shape this module reads out of a shiki theme. Structural, so the theme
 *  objects need no annotation of their own. */
interface ShikiThemeLike {
  colors: Record<string, string>;
  tokenColors: { scope: string[]; settings: { foreground?: string; fontStyle?: string } }[];
}

/** Every dotted prefix of `scope`, longest first: `a.b.c` → a.b.c, a.b, a. */
function prefixesOf(scope: string): string[] {
  const parts = scope.split('.');
  const out: string[] = [];
  for (let n = parts.length; n > 0; n -= 1) out.push(parts.slice(0, n).join('.'));
  return out;
}

/**
 * The style a shiki theme gives `scope`: the LAST `tokenColors` entry naming
 * that scope or a dotted prefix of it, matching TextMate's own precedence
 * (later entries win) and its prefix rule (a `keyword` rule covers
 * `keyword.operator`).
 *
 * Last-wins is what makes `keyword.operator` resolve to the accent rather than
 * to `keyword`'s green: both entries match, and the more specific one is
 * written later.
 *
 * Throws when no entry matches. That is the drift alarm: a scope removed from
 * `shiki-themes.mjs` must fail a test here, not silently fall back to a
 * default the editor would then render in the wrong colour.
 */
export function scopeStyle(theme: unknown, scope: string): { foreground: string; fontStyle?: string } {
  const { tokenColors } = theme as ShikiThemeLike;
  const wanted = prefixesOf(scope);
  let found: { foreground?: string; fontStyle?: string } | null = null;
  for (const entry of tokenColors) {
    if (entry.scope.some((s) => wanted.includes(s))) found = entry.settings;
  }
  if (!found || !found.foreground) {
    throw new Error(`shiki theme has no foreground for scope '${scope}'`);
  }
  return { foreground: found.foreground, ...(found.fontStyle ? { fontStyle: found.fontStyle } : {}) };
}

/** The three TextMate font settings, each mapped to the one CSS property it
 *  actually means. A word outside this table throws rather than leaking into
 *  CSS as an invalid declaration. */
const FONT_SETTING: Record<string, 'fontStyle' | 'fontWeight' | 'textDecoration'> = {
  italic: 'fontStyle',
  bold: 'fontWeight',
  underline: 'textDecoration',
};

/** `TAG_SCOPES` resolved against one shiki theme. The raw TextMate
 *  `fontStyle` string — which may be any whitespace-separated combination of
 *  `italic`, `bold` and `underline` — is split, and each word lands on the CSS
 *  property it belongs to. */
export function styleSpecs(theme: unknown): TagSpec[] {
  return TAG_SCOPES.map(({ tag, scope }) => {
    const style = scopeStyle(theme, scope);
    const spec: TagSpec = { tag, color: style.foreground };
    for (const word of (style.fontStyle ?? '').split(/\s+/).filter(Boolean)) {
      const property = FONT_SETTING[word];
      if (!property) throw new Error(`unknown TextMate fontStyle '${word}' on scope '${scope}'`);
      if (property === 'fontStyle') spec.fontStyle = 'italic';
      else if (property === 'fontWeight') spec.fontWeight = 'bold';
      else spec.textDecoration = 'underline';
    }
    return spec;
  });
}

/** Editor chrome. Background and foreground come from the theme's own
 *  `colors`; everything else is a site CSS variable, so the editor matches the
 *  pane it sits in and follows the theme toggle without a second palette. */
export interface EditorPalette {
  background: string;
  foreground: string;
  gutterBackground: string;
  gutterForeground: string;
  gutterBorder: string;
  /** Overrides the base theme's `&light .cm-content { caretColor: black }`. */
  caret: string;
  /**
   * The NATIVE selection colour. `drawSelection()` is deliberately not in the
   * extension set, so `.cm-selectionBackground` — the only selection class the
   * base theme knows — is never in the DOM; `::selection` is what a reader
   * actually sees. It is not `var(--border)`: light `--border` `#e6dff5`
   * against the editor background `#e8def0`, and dark `#1a1228` against
   * `#1f1438`, are near-invisible in both themes.
   */
  selection: string;
  activeLine: string;
  /** Fed to the lint underline's SVG data URI in slice 4, not to a colour
   *  property: `@codemirror/lint` bakes its colours into `backgroundImage`. */
  errorUnderline: string;
  warningUnderline: string;
}

export function editorPalette(theme: unknown): EditorPalette {
  const { colors } = theme as ShikiThemeLike;
  return {
    background: colors['editor.background'],
    foreground: colors['editor.foreground'],
    gutterBackground: 'var(--pane-label-bg)',
    gutterForeground: 'var(--muted)',
    gutterBorder: 'var(--border)',
    caret: 'var(--accent)',
    selection: 'color-mix(in srgb, var(--accent) 28%, transparent)',
    activeLine: 'var(--pane-label-bg)',
    errorUnderline: scopeStyle(theme, 'invalid').foreground,
    warningUnderline: scopeStyle(theme, 'constant.numeric').foreground,
  };
}

export function themeFor(mode: ThemeMode): { specs: TagSpec[]; palette: EditorPalette } {
  const theme = mode === 'dark' ? shikiDark : shikiLight;
  return { specs: styleSpecs(theme), palette: editorPalette(theme) };
}
