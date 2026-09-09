// An author writes these as component attributes, so every value is untrusted
// text and every fallback has to be deliberate.
import { describe, expect, test } from 'bun:test';
import {
  ANALYZE_DEBOUNCE_MS,
  BUILD_DEBOUNCE_MS,
  LIVE_EDITOR_DEFAULTS,
  SHARE_CAP,
  Stage,
  clampHeight,
  expandTarget,
  parseLiveEditorConfig,
} from '../src/utils/live-editor-config.ts';
import { SHARE_CAP as CODEC_CAP } from '../src/utils/share-link.ts';
import { ANALYZE_DEBOUNCE_MS as PIPE_ANALYZE } from '../src/scripts/pipeline.ts';

describe('shared constants are re-exported, not re-declared', () => {
  test('the cap and the debounces are the originals', () => {
    // A second copy of a locked number is the drift this guards.
    expect(SHARE_CAP).toBe(CODEC_CAP);
    expect(ANALYZE_DEBOUNCE_MS).toBe(PIPE_ANALYZE);
    expect(BUILD_DEBOUNCE_MS).toBe(350);
    expect(typeof Stage).toBe('function');
  });
});

describe('clampHeight', () => {
  test('accepts a plain CSS length', () => {
    for (const ok of ['14rem', '200px', '3.5em', '40ch', '50vh', '8.25rem']) {
      expect(clampHeight(ok)).toBe(ok);
    }
    expect(clampHeight('  14rem  ')).toBe('14rem');
  });

  test('falls back on anything else', () => {
    for (const bad of [
      undefined,
      null,
      '',
      'calc(100% - 2rem)',
      '14',
      '14 rem',
      'expression(alert(1))',
      '100%',
      '-4rem',
      'var(--x)',
    ]) {
      expect(clampHeight(bad)).toBe(LIVE_EDITOR_DEFAULTS.height);
    }
  });
});

describe('parseLiveEditorConfig', () => {
  test('reads a full dataset', () => {
    expect(
      parseLiveEditorConfig({
        leOutput: 'simulate',
        leHeight: '20rem',
        leReadonly: 'true',
        lePick: 'tour:1',
        leWasm: '/wasm/tour-1.wasm',
        leLabel: 'half adder',
      }),
    ).toEqual({
      output: 'simulate',
      height: '20rem',
      readonly: true,
      pickId: 'tour:1',
      wasmHref: '/wasm/tour-1.wasm',
      label: 'half adder',
    });
  });

  test('every field falls back on its own', () => {
    expect(parseLiveEditorConfig({})).toEqual({
      output: 'preview',
      height: LIVE_EDITOR_DEFAULTS.height,
      readonly: false,
      pickId: null,
      wasmHref: null,
      label: 'circ source',
    });
    // An unknown output is not an error, it is a preview.
    expect(parseLiveEditorConfig({ leOutput: 'nonsense' }).output).toBe('preview');
    // Only the exact string enables readonly.
    expect(parseLiveEditorConfig({ leReadonly: 'yes' }).readonly).toBe(false);
    expect(parseLiveEditorConfig({ leLabel: '   ' }).label).toBe('circ source');
  });
});

describe('expandTarget', () => {
  const ok = (fragment: string) =>
    async () => ({ ok: true as const, key: 'src' as const, fragment, chars: fragment.length });
  const tooLarge = async () => ({ ok: false as const, reason: 'too-large' as const, chars: 9000, cap: 8192 });

  test('an unedited shipped source expands by id, without encoding', async () => {
    let called = false;
    const r = await expandTarget({
      pickId: 'tour:1',
      original: 'input a\n',
      current: 'input a\n',
      encode: async () => {
        called = true;
        return { ok: true, key: 'src', fragment: '#src=X', chars: 6 };
      },
    });
    expect(r).toEqual({ kind: 'pick', hash: '#pick=tour:1' });
    // The short URL is the point, and so is not doing the work.
    expect(called).toBe(false);
  });

  test('an edited source carries itself', async () => {
    const r = await expandTarget({
      pickId: 'tour:1',
      original: 'input a\n',
      current: 'input b\n',
      encode: ok('#src=AAA'),
    });
    expect(r).toEqual({ kind: 'src', hash: '#src=AAA' });
  });

  test('the fragment is used verbatim, leading # included', async () => {
    const r = await expandTarget({
      pickId: null,
      original: 'a',
      current: 'b',
      encode: ok('#src0=BBB'),
    });
    expect(r.kind).toBe('src');
    if (r.kind === 'src') {
      expect(r.hash).toBe('#src0=BBB');
      expect(r.hash.startsWith('##')).toBe(false);
    }
  });

  test('an over-cap edit degrades to the id and says the edit was left behind', async () => {
    const r = await expandTarget({
      pickId: 'example:half-adder',
      original: 'a',
      current: 'b',
      encode: tooLarge,
    });
    expect(r.kind).toBe('pick');
    if (r.kind === 'pick') {
      expect(r.hash).toBe('#pick=example:half-adder');
      // Silently opening the original would lose the reader's work with no word.
      expect(r.note).toContain('too long');
      expect(r.note).toContain('8192');
    }
  });

  test('an over-cap edit with no id refuses rather than pretending', async () => {
    const r = await expandTarget({ pickId: null, original: 'a', current: 'b', encode: tooLarge });
    expect(r.kind).toBe('refuse');
    if (r.kind === 'refuse') expect(r.reason).toContain('too long');
  });

  test('an unedited source with no id still encodes', async () => {
    // Nothing to point at, so the source has to travel.
    const r = await expandTarget({ pickId: null, original: 'a', current: 'a', encode: ok('#src=Z') });
    expect(r).toEqual({ kind: 'src', hash: '#src=Z' });
  });
});
