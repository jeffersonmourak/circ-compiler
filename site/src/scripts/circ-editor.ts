// The CodeMirror 6 editor, mounted by the playground island and (from Phase 7)
// by `<LiveEditor>`. It is the ONLY file in this tree that imports
// `@codemirror/*`, and nothing ever imports it statically: it is reached
// through a dynamic `import()` so no page's eager module graph carries it
// (`site/test/bundle-graph.test.ts` is the build-free gate for that).
//
// It imports nothing playground-specific.
//
// Phase 1 slice 1 stood up the surface: the extension set, the theme
// compartment and the handle. Slice 2 added the circ `StreamLanguage` over
// `../utils/circ-tokens.mjs`. Slice 3 filled the compartment with the palette
// derived from the shiki themes; `lintGutter()` (slice 4) fills in behind the
// same surface without changing it.
import {
  Annotation,
  Compartment,
  EditorSelection,
  EditorState,
  type Extension,
} from '@codemirror/state';
import {
  EditorView,
  highlightActiveLine,
  highlightActiveLineGutter,
  keymap,
  lineNumbers,
  type KeyBinding,
} from '@codemirror/view';
import {
  HighlightStyle,
  StreamLanguage,
  indentUnit,
  syntaxHighlighting,
  type StreamParser,
  type StringStream,
} from '@codemirror/language';
import {
  history,
  indentLess,
  indentMore,
  insertNewlineAndIndent,
  redo,
  toggleComment,
  toggleTabFocusMode,
  undo,
} from '@codemirror/commands';
import { setDiagnostics as lintSetDiagnostics, type Diagnostic } from '@codemirror/lint';
import { tags, type Tag } from '@lezer/highlight';
import {
  copyState,
  nextToken,
  startState,
  type CircTokenState,
} from '../utils/circ-tokens.mjs';
import { themeFor, type EditorPalette, type TagSpec, type ThemeMode } from '../utils/circ-editor-theme.ts';

export type { ThemeMode };

/**
 * The keymap, hand-rolled from individual commands instead of `defaultKeymap`
 * + `historyKeymap` + `indentWithTab`. Importing `defaultKeymap` retains every
 * command in `@codemirror/commands` (it references nearly all of them), and
 * the measurement in `DOCS/STATUS.md` put the full-keymap chunk inside the
 * pre-agreed 20 % band around the 120 KB gzip ceiling, which fires the
 * keymap-only split of `DOCS/PLANS/PHASE_1_editor.md`'s Open Questions.
 * `history()` is kept — Phase 2's per-file undo is built on it.
 *
 * Backspace, Delete and Enter-without-indent still work unbound: the view
 * translates them from `beforeinput` / DOM changes (`PendingKeys`,
 * `@codemirror/view/dist/index.js:4722-4727`), and cursor motion is the
 * browser's own contenteditable selection. `Ctrl-m` / `Shift-Alt-m` is
 * CodeMirror's own Tab-trap escape hatch and is bound exactly as
 * `defaultKeymap` binds it (`@codemirror/commands/dist/index.js:1816`).
 */
const circKeymap: readonly KeyBinding[] = [
  { key: 'Tab', run: indentMore, shift: indentLess }, // indentWithTab, verbatim
  { key: 'Enter', run: insertNewlineAndIndent },
  { key: 'Mod-[', run: indentLess },
  { key: 'Mod-]', run: indentMore },
  { key: 'Mod-/', run: toggleComment },
  { key: 'Ctrl-m', mac: 'Shift-Alt-m', run: toggleTabFocusMode },
  { key: 'Mod-z', run: undo, preventDefault: true },
  { key: 'Mod-y', mac: 'Mod-Shift-z', run: redo, preventDefault: true },
  { linux: 'Ctrl-Shift-z', run: redo, preventDefault: true },
];

/**
 * The circ mode: a `StreamParser` over the one token table, not a Lezer
 * grammar. `token` is the whole adapter — CodeMirror sets `stream.start` before
 * each call and reads it after, so assigning `stream.pos` is the entire
 * contract. `readToken` throws `"Stream parser failed to advance stream."`
 * after ten non-advancing calls, which is why `nextToken` always advances (its
 * `invalid` catch-all is what guarantees it).
 *
 * `languageData.commentTokens` is what makes `Mod-/` (`toggleComment`, bound in
 * `circKeymap` above) comment circ correctly: the command reads it as
 * `state.languageDataAt('commentTokens', pos, 1)`.
 *
 * Exported for Phase 2/5 reuse; inside this phase only `createEditor` consumes
 * `circLanguage`.
 */
export const circStreamParser: StreamParser<CircTokenState> = {
  name: 'circ',
  startState,
  copyState,
  token(stream: StringStream, state: CircTokenState): string | null {
    const { end, tag } = nextToken(stream.string, stream.pos, state);
    stream.pos = end;
    return tag;
  },
  languageData: { commentTokens: { line: '//' } },
};

export const circLanguage: StreamLanguage<CircTokenState> =
  StreamLanguage.define(circStreamParser);

export interface EditorOptions {
  doc?: string;
  theme?: ThemeMode;
  readOnly?: boolean;
  /** Phase 7's <LiveEditor>: drops lineNumbers, both activeLine extensions
   *  and lintGutter. Nothing in Phase 1 passes it; it ships now so the module
   *  never needs a second consumer-driven change. */
  compact?: boolean;
  ariaLabel?: string;
  onChange?: (doc: string) => void;
}

export interface EditorHandle {
  readonly view: EditorView;
  getDoc(): string;
  /** Replaces the whole document without firing onChange. Keeps undo history. */
  setDoc(next: string): void;
  setDiagnostics(list: readonly Diagnostic[]): void;
  setTheme(mode: ThemeMode): void;
  /** Selects [from, to) and scrolls it into view. `to` defaults to `from`. */
  select(from: number, to?: number): void;
  focus(): void;
  destroy(): void;
}

/** Marks a transaction this module dispatched itself, so the update listener
 *  can skip it and `setDoc` never re-enters `onChange`. */
const external = Annotation.define<boolean>();

/** `document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light'`
 *  — the attribute Base.astro pre-paints and ThemeToggle.astro flips. */
export function currentThemeMode(): ThemeMode {
  if (typeof document === 'undefined') return 'light';
  return document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light';
}

/**
 * `'variableName.function'` → `tags.function(tags.variableName)`. The base is a
 * plain key of `tags`; every dotted suffix is a modifier, which `tags` exposes
 * as a function. Naming tags as strings is what keeps `circ-editor-theme.ts`
 * free of any CodeMirror import, and therefore testable without a DOM.
 */
function resolveTag(name: string): Tag {
  const [base, ...modifiers] = name.split('.');
  const table = tags as unknown as Record<string, unknown>;
  let tag = table[base];
  if (typeof tag !== 'object' || tag === null) throw new Error(`unknown highlight tag '${base}'`);
  for (const modifier of modifiers) {
    const apply = table[modifier];
    if (typeof apply !== 'function') throw new Error(`unknown highlight tag modifier '${modifier}'`);
    tag = (apply as (t: unknown) => unknown)(tag);
  }
  return tag as Tag;
}

/** A `TagSpec`'s CSS half, verbatim: `color` plus whichever of `fontStyle` /
 *  `fontWeight` / `textDecoration` the theme derivation set. style-mod
 *  kebab-cases each key, which is why the TextMate→CSS split happens in
 *  `circ-editor-theme.ts` and never here. */
function tagStyle(spec: TagSpec) {
  return {
    tag: resolveTag(spec.tag),
    color: spec.color,
    ...(spec.fontStyle ? { fontStyle: spec.fontStyle } : {}),
    ...(spec.fontWeight ? { fontWeight: spec.fontWeight } : {}),
    ...(spec.textDecoration ? { textDecoration: spec.textDecoration } : {}),
  };
}

/** The editor chrome, as an `EditorView.theme` spec. The selection is styled
 *  through `::selection` because `drawSelection()` is not in the extension set,
 *  so `.cm-selectionBackground` never exists in the DOM. */
function chromeSpec(palette: EditorPalette): Record<string, Record<string, string>> {
  return {
    '&': { backgroundColor: palette.background, color: palette.foreground },
    '.cm-content': { caretColor: palette.caret },
    '.cm-cursor, .cm-dropCursor': { borderLeftColor: palette.caret },
    '.cm-content ::selection': { backgroundColor: palette.selection },
    '.cm-content::selection': { backgroundColor: palette.selection },
    '.cm-gutters': {
      backgroundColor: palette.gutterBackground,
      color: palette.gutterForeground,
      borderRight: `1px solid ${palette.gutterBorder}`,
    },
    '.cm-activeLine': { backgroundColor: palette.activeLine },
    '.cm-activeLineGutter': { backgroundColor: palette.activeLine, color: palette.foreground },
  };
}

/** The compartment's content: the chrome and the token colours together, so one
 *  `reconfigure` flips both. The view is never destroyed for a theme change —
 *  unlike the simulation canvas, which captures its theme at construction. */
function themeExtension(mode: ThemeMode): Extension {
  const { specs, palette } = themeFor(mode);
  return [
    EditorView.theme(chromeSpec(palette), { dark: mode === 'dark' }),
    syntaxHighlighting(HighlightStyle.define(specs.map(tagStyle))),
  ];
}

export function createEditor(parent: HTMLElement, options: EditorOptions = {}): EditorHandle {
  const {
    doc = '',
    theme = currentThemeMode(),
    readOnly = false,
    compact = false,
    ariaLabel = 'circ source',
    onChange,
  } = options;

  const themeCompartment = new Compartment();

  const extensions: Extension[] = [];
  if (!compact) {
    extensions.push(lineNumbers(), highlightActiveLine(), highlightActiveLineGutter());
  }
  extensions.push(
    circLanguage,
    history(),
    keymap.of([...circKeymap]),
    EditorState.tabSize.of(2),
    indentUnit.of('  '),
    EditorView.lineWrapping,
    EditorView.contentAttributes.of({ 'aria-label': ariaLabel }),
    EditorView.updateListener.of((update) => {
      if (!update.docChanged) return;
      if (update.transactions.some((tr) => tr.annotation(external))) return;
      onChange?.(update.state.doc.toString());
    }),
    themeCompartment.of(themeExtension(theme)),
  );
  if (readOnly) extensions.push(EditorState.readOnly.of(true), EditorView.editable.of(false));

  const view = new EditorView({ state: EditorState.create({ doc, extensions }), parent });

  const clamp = (n: number): number => Math.max(0, Math.min(n, view.state.doc.length));

  return {
    view,
    getDoc: () => view.state.doc.toString(),
    setDoc(next: string) {
      view.dispatch({
        changes: { from: 0, to: view.state.doc.length, insert: next },
        annotations: external.of(true),
      });
    },
    setDiagnostics(list: readonly Diagnostic[]) {
      // `setDiagnostics` is a TransactionSpec, not an extension: the spec
      // enables the lint state itself, so this works without `linter()`.
      view.dispatch(lintSetDiagnostics(view.state, list));
    },
    setTheme(mode: ThemeMode) {
      view.dispatch({ effects: themeCompartment.reconfigure(themeExtension(mode)) });
    },
    select(from: number, to: number = from) {
      const a = clamp(from);
      const b = clamp(to);
      view.dispatch({
        selection: EditorSelection.create([EditorSelection.range(a, b)]),
        scrollIntoView: true,
      });
      view.focus();
    },
    focus() {
      view.focus();
    },
    destroy() {
      view.destroy();
    },
  };
}
