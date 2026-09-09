// The docs' live editors.
//
// Everything expensive is deferred: a page with seven of these ships one small
// script, and the editor, the compiler and the renderer arrive only when a
// reader touches one. All of them then share a single worker, because seven
// workers would mean seven copies of the compiler in memory.
import { getSharedClient } from './libcirc-client.ts';
import { requestFor, splitFiles } from '../utils/split-files.ts';
import {
  ANALYZE_DEBOUNCE_MS,
  BUILD_DEBOUNCE_MS,
  Stage,
  browserEncoder,
  expandTarget,
  parseLiveEditorConfig,
  type LiveEditorConfig,
} from '../utils/live-editor-config.ts';
import { mapDiagnostics, toLintDiagnostics, type Analysis } from './circ-diagnostics.ts';

type EditorMod = typeof import('./circ-editor.ts');
type EditorHandle = ReturnType<EditorMod['createEditor']>;

let editorMod: Promise<EditorMod> | null = null;
const loadEditor = () => (editorMod ??= import('./circ-editor.ts'));

const ROOT = '/playground/main.circ';

function mountOne(root: HTMLElement): void {
  const config: LiveEditorConfig = parseLiveEditorConfig(root.dataset as Record<string, string>);
  const statusEl = root.querySelector<HTMLElement>('.le-status')!;
  const expandEl = root.querySelector<HTMLAnchorElement>('.le-expand')!;
  const host = root.querySelector<HTMLElement>('.le-editor')!;
  const fallback = root.querySelector<HTMLElement>('.le-source')!;
  const previewEl = root.querySelector<HTMLElement>('.le-preview')!;
  const blob = root.querySelector('.le-src');

  const original: string = blob ? (JSON.parse(blob.textContent || '""') as string) : '';
  let current = original;
  let editor: EditorHandle | null = null;
  let activated = false;

  const analyze = new Stage(ANALYZE_DEBOUNCE_MS);
  const build = new Stage(BUILD_DEBOUNCE_MS);
  const client = getSharedClient(root.dataset.leWasmUrl ?? '/wasm/libcirc.wasm');

  const request = () => requestFor(splitFiles(current));

  async function runAnalyze(seq: number): Promise<void> {
    const snapshot = current;
    const r = await client.call('analyze', request());
    if (!analyze.isCurrent(seq) || !editor) return;
    if (r.status !== 0 || !r.text) return;
    const analysis = JSON.parse(r.text) as Analysis;
    const errors = analysis.diagnostics.filter((d) => d.severity === 'error').length;
    statusEl.textContent = errors === 0 ? 'Live' : `${errors} error${errors === 1 ? '' : 's'}`;
    // Offsets are computed against the text that was sent; a reply that
    // outlived its document must not be mapped onto the new one.
    if (snapshot !== current) return;
    const files = splitFiles(snapshot);
    editor.setDiagnostics(toLintDiagnostics(mapDiagnostics(snapshot, files, analysis)));
  }

  async function runBuild(seq: number): Promise<void> {
    const r = await client.call('preview', requestFor(splitFiles(current), { color: 'never' }));
    if (!build.isCurrent(seq)) return;
    if (r.status === 0 && r.text) {
      previewEl.textContent = r.text;
      previewEl.hidden = false;
      root.removeAttribute('data-stale');
    } else {
      // The last good schematic stays, dimmed: a snippet mid-edit is broken
      // most of the time, and blanking it on every keystroke is unreadable.
      root.setAttribute('data-stale', '');
    }
    void refreshExpand();
  }

  async function refreshExpand(): Promise<void> {
    const target = await expandTarget({
      pickId: config.pickId,
      original,
      current,
      encode: browserEncoder,
    });
    if (target.kind === 'refuse') {
      expandEl.removeAttribute('href');
      expandEl.title = target.reason;
      return;
    }
    expandEl.href = `${expandEl.pathname}${target.hash}`;
    // Only the degrade path carries a note, and it is the one the reader has
    // to be told about: their edit was left behind.
    expandEl.title = target.kind === 'pick' ? (target.note ?? '') : '';
  }

  function schedule(): void {
    analyze.schedule((seq) => void runAnalyze(seq));
    build.schedule((seq) => void runBuild(seq));
  }

  async function activate(): Promise<void> {
    if (activated) return;
    activated = true;
    statusEl.textContent = 'Loading…';
    try {
      const mod = await loadEditor();
      editor = mod.createEditor(host, {
        doc: original,
        theme: mod.currentThemeMode(),
        // Compact drops the line numbers, the active-line highlight and the
        // lint gutter: a six-line snippet has no room for them.
        compact: true,
        readOnly: config.readonly,
        ariaLabel: config.label,
        onChange: (doc) => {
          current = doc;
          schedule();
        },
      });
      host.hidden = false;
      fallback.hidden = true;
      statusEl.textContent = 'Live';
      build.flush((seq) => void runBuild(seq));
      analyze.flush((seq) => void runAnalyze(seq));
    } catch {
      // The snippet is still readable; that is the whole fallback.
      activated = false;
      statusEl.textContent = 'Editor unavailable';
    }
  }

  // Touch, not sight: a reader scrolling past a tour page pays nothing.
  root.addEventListener('pointerdown', () => void activate(), { once: true });
  root.addEventListener('focusin', () => void activate(), { once: true });
}

let mounted = false;

/** Idempotent: the component includes this script once per instance, and
 *  Astro hoists it into one module either way. */
export function mountLiveEditors(): void {
  if (mounted) return;
  mounted = true;
  for (const root of document.querySelectorAll<HTMLElement>('.le')) mountOne(root);
}
