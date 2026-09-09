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
// derived from the shiki themes, and slice 4 added `lintGutter()` and the
// rebuilt squiggle underlines — all behind the same handle.
import {
  Annotation,
  Compartment,
  EditorSelection,
  EditorState,
  StateEffect,
  StateField,
  type Extension,
} from '@codemirror/state';
import {
  Decoration,
  EditorView,
  highlightActiveLine,
  highlightActiveLineGutter,
  keymap,
  lineNumbers,
  type DecorationSet,
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
import { lintGutter, setDiagnostics as lintSetDiagnostics, type Diagnostic } from '@codemirror/lint';
import { tags, type Tag } from '@lezer/highlight';
import {
  copyState,
  nextToken,
  startState,
  type CircTokenState,
} from '../utils/circ-tokens.mjs';
import { themeFor, type EditorPalette, type TagSpec, type ThemeMode } from '../utils/circ-editor-theme.ts';
import { activeAfter, insert, move, remove } from './doc-registry.ts';

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
  /** Fires for every user edit, never for `setDoc`. The index is APPENDED to
   *  Phase 1's single-argument shape so a one-document consumer stays
   *  source-compatible; without `setDocuments` it is always 0. */
  onChange?: (doc: string, index: number) => void;
  /** Fires whenever the selection moves, with the caret's 1-based line and
   *  UTF-16 column and that line's text — everything a host needs to resolve a
   *  declaration without reaching into the view. */
  onCursor?: (index: number, line: number, col: number, lineText: string) => void;
}

export interface EditorHandle {
  readonly view: EditorView;

  // ---- the visible document (Phase 1's surface, unchanged in meaning) ----
  getDoc(): string;
  /** Replaces the visible document without firing onChange. Keeps undo history. */
  setDoc(next: string): void;
  setDiagnostics(list: readonly Diagnostic[]): void;
  /** Rewrites EVERY stored document's theme, not only the visible one, so a
   *  file shown after a theme flip is never left in the old palette. */
  setTheme(mode: ThemeMode): void;
  /** Selects [from, to) in the visible document and scrolls it into view. */
  select(from: number, to?: number): void;
  /** Marks a span without moving the caret, the selection or the scroll —
   *  a hover must never steal the reader's place. `null` clears it. */
  setLinkHighlight(span: { from: number; to: number } | null): void;
  focus(): void;
  destroy(): void;

  // ---- the document registry: one state per file ----
  /** Replaces the whole set. Each text gets its own state, and therefore its
   *  own selection and its own undo history. */
  setDocuments(texts: readonly string[], active: number): void;
  /** Swaps the visible document synchronously, so a caller can select a range
   *  in the incoming file on the very next statement. */
  showDocument(index: number): void;
  insertDocument(index: number, text: string): void;
  removeDocument(index: number): void;
  moveDocument(from: number, to: number): void;
  textOf(index: number): string;
  /** Stores diagnostics against one file, visible or not. */
  setDiagnosticsFor(index: number, list: readonly Diagnostic[]): void;
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

/**
 * `@codemirror/lint` bakes its squiggle colours into SVG data URIs, not into
 * CSS colour properties, so a `color` or `textDecorationColor` override is a
 * silent no-op — the underline has to be rebuilt. This is the package's own
 * `underline()` (`@codemirror/lint/dist/index.js:642-647`) with the palette's
 * colour substituted: same path, same stroke width, same encoding.
 *
 * Exported so a test can prove the colour reaches the CSS without a browser.
 */
export function underline(color: string): string {
  const path = `<path d="m0 2.5 l2 -1.5 l1 0 l2 1.5 l1 0" stroke="${color}" fill="none" stroke-width=".7"/>`;
  return `url('data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="6" height="3">${encodeURIComponent(path)}</svg>')`;
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
    // A theme spec outranks a package `baseTheme`, so no `!important` is
    // needed. The lint GUTTER markers keep their defaults: their colours are
    // baked into both a `fill` and a `stroke` inside a `content:` data URI,
    // and the palette carries one hex per severity, not two.
    '.cm-lintRange-error': { backgroundImage: underline(palette.errorUnderline) },
    '.cm-lintRange-warning': { backgroundImage: underline(palette.warningUnderline) },
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

/**
 * Marks one span as "this is what you are pointing at" — the canvas hovering a
 * box, a truth-table header, a diagnostics row. One effect and one field, no
 * view plugin: the decoration has to survive a document swap, and only state
 * does that.
 */
export const setLinkHighlight = StateEffect.define<{ from: number; to: number } | null>();

const linkMark = Decoration.mark({ class: 'cm-circ-linked' });

const linkHighlightField = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(deco, tr) {
    // Map through the edit first, so a highlight set before a keystroke lands
    // on the text it was pointing at rather than on a stale offset.
    deco = deco.map(tr.changes);
    for (const e of tr.effects) {
      if (!e.is(setLinkHighlight)) continue;
      deco =
        e.value === null || e.value.from >= e.value.to
          ? Decoration.none
          : Decoration.set([linkMark.range(e.value.from, e.value.to)]);
    }
    return deco;
  },
  provide: (f) => EditorView.decorations.from(f),
});

export function createEditor(parent: HTMLElement, options: EditorOptions = {}): EditorHandle {
  const {
    doc = '',
    theme = currentThemeMode(),
    readOnly = false,
    compact = false,
    ariaLabel = 'circ source',
    onChange,
    onCursor,
  } = options;

  const themeCompartment = new Compartment();
  /** The compartment's current content, so a state created after a theme flip
   *  is born in the new palette rather than the old one. */
  let themeContent = themeExtension(theme);

  /** One entry per file. `scroll` is a saved scroll snapshot: scroll position
   *  is not part of an `EditorState`, so it is carried alongside. */
  interface Doc {
    state: EditorState;
    scroll: StateEffect<unknown> | null;
  }

  let active = 0;
  /** The decoration lives in the state being swapped away, so the handle keeps
   *  the span and re-applies it after a swap. */
  let linkSpan: { from: number; to: number } | null = null;

  // Built once and shared by every state. Only the theme compartment is
  // per-state, and it is seeded from `themeContent` at creation time.
  const staticExtensions: Extension[] = [];
  if (!compact) {
    staticExtensions.push(lineNumbers(), highlightActiveLine(), highlightActiveLineGutter(), lintGutter());
  }
  staticExtensions.push(
    circLanguage,
    linkHighlightField,
    history(),
    keymap.of([...circKeymap]),
    EditorState.tabSize.of(2),
    indentUnit.of('  '),
    EditorView.lineWrapping,
    EditorView.contentAttributes.of({ 'aria-label': ariaLabel }),
    EditorView.updateListener.of((update) => {
      // Keep the mirror fresh on EVERY update, not only document changes: a
      // selection move or a lint transaction must not be lost when this file
      // is swapped out.
      if (docs[active]) docs[active].state = update.state;
      if (onCursor && (update.selectionSet || update.docChanged)) {
        const head = update.state.selection.main.head;
        const line = update.state.doc.lineAt(head);
        onCursor(active, line.number, head - line.from + 1, line.text);
      }
      if (!update.docChanged) return;
      if (update.transactions.some((tr) => tr.annotation(external))) return;
      onChange?.(update.state.doc.toString(), active);
    }),
  );
  if (readOnly) staticExtensions.push(EditorState.readOnly.of(true), EditorView.editable.of(false));

  const makeState = (text: string): EditorState =>
    EditorState.create({ doc: text, extensions: [staticExtensions, themeCompartment.of(themeContent)] });

  const docs: Doc[] = [{ state: makeState(doc), scroll: null }];
  const view = new EditorView({ state: docs[0].state, parent });

  const clampOffset = (n: number): number => Math.max(0, Math.min(n, view.state.doc.length));
  const clampIndex = (n: number): number => Math.max(0, Math.min(n, docs.length - 1));
  /** The view owns the active state; the mirror can lag by one dispatch. */
  const syncActive = (): void => {
    if (docs[active]) docs[active].state = view.state;
  };

  const show = (index: number): void => {
    const next = clampIndex(index);
    if (next === active) return;
    syncActive();
    docs[active].scroll = view.scrollSnapshot();
    active = next;
    view.setState(docs[active].state);
    const saved = docs[active].scroll;
    if (saved) view.dispatch({ effects: saved });
    // The highlight belongs to the state that just went away.
    if (linkSpan) view.dispatch({ effects: setLinkHighlight.of(linkSpan) });
  };

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
      themeContent = themeExtension(mode);
      const effects = themeCompartment.reconfigure(themeContent);
      syncActive();
      // Every hidden document too: a compartment reconfigure is a StateEffect
      // and applies to one state only, so a file shown after the flip would
      // otherwise still be painted in the previous palette.
      docs.forEach((entry, i) => {
        if (i !== active) entry.state = entry.state.update({ effects }).state;
      });
      view.dispatch({ effects });
    },
    select(from: number, to: number = from) {
      const a = clampOffset(from);
      const b = clampOffset(to);
      view.dispatch({
        selection: EditorSelection.create([EditorSelection.range(a, b)]),
        scrollIntoView: true,
      });
      view.focus();
    },
    setLinkHighlight(span: { from: number; to: number } | null) {
      const clamped =
        span === null ? null : { from: clampOffset(span.from), to: clampOffset(span.to) };
      view.dispatch({ effects: setLinkHighlight.of(clamped) });
      linkSpan = clamped;
    },
    focus() {
      view.focus();
    },
    destroy() {
      view.destroy();
    },

    setDocuments(texts: readonly string[], nextActive: number) {
      const list = texts.length > 0 ? texts : [''];
      docs.length = 0;
      for (const text of list) docs.push({ state: makeState(text), scroll: null });
      active = Math.max(0, Math.min(nextActive, docs.length - 1));
      view.setState(docs[active].state);
    },
    showDocument(index: number) {
      show(index);
    },
    insertDocument(index: number, text: string) {
      syncActive();
      const at = Math.max(0, Math.min(index, docs.length));
      const next = insert(docs, at, { state: makeState(text), scroll: null });
      docs.length = 0;
      docs.push(...next);
      active = activeAfter(active, { kind: 'insert', at });
    },
    removeDocument(index: number) {
      if (docs.length <= 1) return;
      syncActive();
      const length = docs.length;
      const next = remove(docs, index);
      if (next.length === length) return; // out of range: nothing removed
      docs.length = 0;
      docs.push(...next);
      active = activeAfter(active, { kind: 'remove', at: index, length });
      view.setState(docs[active].state);
    },
    moveDocument(from: number, to: number) {
      syncActive();
      const next = move(docs, from, to);
      docs.length = 0;
      docs.push(...next);
      active = activeAfter(active, { kind: 'move', from, to });
      // The visible state object is unchanged by a reorder, so no setState.
    },
    textOf(index: number): string {
      if (index === active) return view.state.doc.toString();
      return docs[index]?.state.doc.toString() ?? '';
    },
    setDiagnosticsFor(index: number, list: readonly Diagnostic[]) {
      if (index === active) {
        view.dispatch(lintSetDiagnostics(view.state, list));
        return;
      }
      const entry = docs[index];
      if (!entry) return;
      entry.state = entry.state.update(lintSetDiagnostics(entry.state, list)).state;
    },
  };
}
