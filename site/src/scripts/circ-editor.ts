// The CodeMirror 6 editor, mounted by the playground island and (from Phase 7)
// by `<LiveEditor>`. It is the ONLY file in this tree that imports
// `@codemirror/*`, and nothing ever imports it statically: it is reached
// through a dynamic `import()` so no page's eager module graph carries it
// (`site/test/bundle-graph.test.ts` is the build-free gate for that).
//
// It imports nothing playground-specific.
//
// Phase 1 slice 1 stands up the surface: the extension set, the theme
// compartment (seeded with an empty spec whose `{ dark }` flag alone selects
// CodeMirror's dark base variant) and the handle. The circ `StreamLanguage`
// (slice 2), the derived palette (slice 3) and `lintGutter()` (slice 4) fill
// in behind the same surface without changing it.
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
import { indentUnit } from '@codemirror/language';
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

/** Slice 3 moves this declaration into `circ-editor-theme.ts` and re-exports it
 *  from here, so no consumer's import ever changes. */
export type ThemeMode = 'light' | 'dark';

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

/** The compartment's content. Slice 3 fills the spec and adds
 *  `syntaxHighlighting(HighlightStyle.define(...))` beside it; the `{ dark }`
 *  flag is what keeps the editor from being a light box in a dark pane until
 *  then. */
function themeExtension(mode: ThemeMode): Extension {
  return EditorView.theme({}, { dark: mode === 'dark' });
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
