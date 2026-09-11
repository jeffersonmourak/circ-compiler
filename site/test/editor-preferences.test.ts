import { describe, expect, test } from 'bun:test';
import { Window } from 'happy-dom';
import { EditorState } from '@codemirror/state';
import { indentUnit } from '@codemirror/language';
import { undo } from '@codemirror/commands';
import { createEditor, type EditorHandle } from '../src/scripts/circ-editor.ts';
import { DEFAULT_EDITOR_PREFERENCES, normalizeEditorPreferences } from '../src/utils/editor-preferences.ts';

describe('editor preferences', () => {
  test('defaults preserve the existing wrapping and indentation', () => {
    expect(normalizeEditorPreferences(undefined)).toEqual({ wrapLines: true, fontSize: 14, tabSize: 2 });
    expect(normalizeEditorPreferences({ wrapLines: false, fontSize: 18, tabSize: 4 })).toEqual({ wrapLines: false, fontSize: 18, tabSize: 4 });
  });

  test('invalid fields default independently and sizes stay within bounds', () => {
    expect(normalizeEditorPreferences({ wrapLines: 'no', fontSize: Infinity, tabSize: null })).toEqual(DEFAULT_EDITOR_PREFERENCES);
    expect(normalizeEditorPreferences({ wrapLines: false, fontSize: 99, tabSize: 0 })).toEqual({ wrapLines: false, fontSize: 24, tabSize: 1 });
    expect(normalizeEditorPreferences({ fontSize: 9, tabSize: 20 })).toEqual({ wrapLines: true, fontSize: 10, tabSize: 8 });
    expect(normalizeEditorPreferences({ fontSize: 16.6, tabSize: 3.6 })).toEqual({ wrapLines: true, fontSize: 17, tabSize: 4 });
  });

  test('reconfiguration keeps documents, selections and undo, including hidden and new files', () => {
    const window = new Window();
    const globals = globalThis as unknown as Record<string, unknown>;
    const saved = new Map<string, unknown>();
    for (const key of ['window', 'document', 'Window', 'HTMLElement', 'MutationObserver', 'ResizeObserver', 'requestAnimationFrame', 'cancelAnimationFrame', 'getComputedStyle']) {
      saved.set(key, globals[key]);
      globals[key] = key === 'window' ? window : key === 'Window' ? Window : (window as unknown as Record<string, unknown>)[key];
    }
    let handle: EditorHandle | undefined;
    try {
      const parent = window.document.createElement('div');
      window.document.body.appendChild(parent);
      const edits: string[] = [];
      handle = createEditor(parent as unknown as HTMLElement, { onChange: (doc) => edits.push(doc) });
      handle.setDocuments(['input a', 'input b'], 0);
      handle.view.dispatch({ changes: { from: 0, insert: '// mine\n' } });
      handle.select(3);
      handle.showDocument(1); handle.select(2); handle.showDocument(0);
      handle.setPreferences({ wrapLines: false, fontSize: 18, tabSize: 4 });
      expect(handle.getDoc()).toBe('// mine\ninput a');
      expect(handle.view.state.selection.main.head).toBe(3);
      expect(edits).toEqual(['// mine\ninput a']);
      expect(handle.view.state.facet(EditorState.tabSize)).toBe(4);
      expect(handle.view.state.facet(indentUnit)).toBe('    ');
      expect(handle.view.contentDOM.classList.contains('cm-lineWrapping')).toBe(false);
      expect(handle.view.scrollDOM.style.fontSize).toBe('18px');
      expect(undo(handle.view)).toBe(true);
      expect(handle.getDoc()).toBe('input a');
      handle.setTheme('dark');
      handle.showDocument(1);
      expect(handle.getDoc()).toBe('input b');
      expect(handle.view.state.selection.main.head).toBe(2);
      expect(handle.view.state.facet(EditorState.tabSize)).toBe(4);
      expect(handle.view.contentDOM.classList.contains('cm-lineWrapping')).toBe(false);
      handle.insertDocument(1, 'input c'); handle.showDocument(1);
      expect(handle.view.state.facet(indentUnit)).toBe('    ');
      handle.setDocuments(['input d'], 0);
      expect(handle.view.state.facet(EditorState.tabSize)).toBe(4);
      handle.setPreferences({ ...DEFAULT_EDITOR_PREFERENCES });
      expect(handle.view.contentDOM.classList.contains('cm-lineWrapping')).toBe(true);
      expect(handle.view.scrollDOM.style.fontSize).toBe('14px');
    } finally {
      handle?.destroy();
      for (const [key, value] of saved) {
        if (value === undefined) delete globals[key]; else globals[key] = value;
      }
    }
  });
});
