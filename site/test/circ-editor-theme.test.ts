// The editor palette must be the docs palette. These cases pin every colour
// against `shiki-themes.mjs` itself, so a themed code block on /reference and
// the playground editor cannot drift, and pin the TextMate→CSS split that a
// pass-through would get silently wrong.
import { describe, expect, test } from 'bun:test';
import { tags } from '@lezer/highlight';
import {
  TAG_SCOPES,
  editorPalette,
  scopeStyle,
  styleSpecs,
  themeFor,
  type TagSpec,
} from '../src/utils/circ-editor-theme.ts';
import { shikiDark, shikiLight } from '../src/utils/shiki-themes.mjs';
import { tokenizeLine } from '../src/utils/circ-tokens.mjs';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';

const sources = [...examples.map((e) => e.source), ...tour.map((t) => t.source)];
const specOf = (specs: TagSpec[], tag: string) => specs.find((s) => s.tag === tag);

describe('circ editor theme', () => {
  test('every palette tag resolves through @lezer/highlight', () => {
    const table = tags as unknown as Record<string, unknown>;
    for (const { tag } of TAG_SCOPES) {
      const [base, ...modifiers] = tag.split('.');
      expect(typeof table[base]).toBe('object');
      expect(table[base]).not.toBeNull();
      for (const modifier of modifiers) expect(typeof table[modifier]).toBe('function');
    }
  });

  test('the palette is total over the emitted tag set', () => {
    const emitted = new Set<string>();
    for (const source of sources) {
      for (const line of source.split('\n')) {
        for (const token of tokenizeLine(line)) if (token.tag) emitted.add(token.tag);
      }
    }
    expect(emitted.size).toBeGreaterThan(0);
    for (const themeSpecs of [styleSpecs(shikiLight), styleSpecs(shikiDark)]) {
      const covered = new Set(themeSpecs.map((s) => s.tag));
      for (const tag of emitted) expect(covered.has(tag)).toBe(true);
    }
  });

  test('one spec per TAG_SCOPES entry, in order', () => {
    for (const theme of [shikiLight, shikiDark]) {
      expect(styleSpecs(theme).map((s) => s.tag)).toEqual(TAG_SCOPES.map((t) => t.tag));
    }
  });

  test('the palette is the shiki palette', () => {
    const light = styleSpecs(shikiLight);
    const dark = styleSpecs(shikiDark);
    expect(specOf(light, 'keyword')?.color).toBe('#0a6634');
    expect(specOf(dark, 'keyword')?.color).toBe('#1ee17d');
    expect(specOf(light, 'comment')?.color).toBe('#8a7e9a');
    expect(specOf(dark, 'comment')?.color).toBe('#7d6e94');
    expect(specOf(light, 'string')?.color).toBe('#8e4a0e');
    expect(specOf(light, 'number')?.color).toBe('#8e4a0e');
    expect(specOf(dark, 'string')?.color).toBe('#e17d1e');
    expect(specOf(dark, 'number')?.color).toBe('#e17d1e');
    expect(specOf(light, 'operator')?.color).toBe('#6e49ab');
    expect(specOf(dark, 'operator')?.color).toBe('#b097d1');
    expect(specOf(light, 'typeName')?.color).toBe('#0a6634');
    expect(specOf(dark, 'typeName')?.color).toBe('#1ee17d');
    expect(specOf(light, 'invalid')?.color).toBe('#a83737');
    expect(specOf(dark, 'invalid')?.color).toBe('#ff6b8a');
    expect(editorPalette(shikiLight).background).toBe('#e8def0');
    expect(editorPalette(shikiDark).background).toBe('#1f1438');
    expect(editorPalette(shikiLight).foreground).toBe('#443856');
    expect(editorPalette(shikiDark).foreground).toBe('#c0abda');
  });

  test('the more specific scope wins over its prefix', () => {
    // `keyword` and `keyword.operator` both match a lookup of the latter; the
    // later, more specific entry is the one that must win, or every operator
    // would render in the keyword green.
    expect(scopeStyle(shikiLight, 'keyword.operator').foreground).toBe('#6e49ab');
    expect(scopeStyle(shikiLight, 'keyword').foreground).toBe('#0a6634');
  });

  test('scopeStyle throws for a scope the theme does not carry', () => {
    expect(() => scopeStyle(shikiLight, 'nope.not.a.scope')).toThrow();
    expect(() => scopeStyle(shikiDark, 'nope.not.a.scope')).toThrow();
  });

  test('the TextMate fontStyle is split, not passed through', () => {
    expect(specOf(styleSpecs(shikiLight), 'keyword')).toEqual({
      tag: 'keyword',
      color: '#0a6634',
      fontWeight: 'bold',
    });
    expect(specOf(styleSpecs(shikiDark), 'keyword')).toEqual({
      tag: 'keyword',
      color: '#1ee17d',
      fontWeight: 'bold',
    });
    expect(specOf(styleSpecs(shikiLight), 'comment')).toEqual({
      tag: 'comment',
      color: '#8a7e9a',
      fontStyle: 'italic',
    });
    // `font-style: bold` is invalid CSS that browsers drop in silence, so no
    // spec may carry any fontStyle value other than 'italic'.
    for (const themeSpecs of [styleSpecs(shikiLight), styleSpecs(shikiDark)]) {
      for (const spec of themeSpecs) {
        if (spec.fontStyle !== undefined) expect(spec.fontStyle).toBe('italic');
        if (spec.fontWeight !== undefined) expect(spec.fontWeight).toBe('bold');
      }
    }
  });

  test('the lint underline carries the palette colour', () => {
    expect(editorPalette(shikiLight).errorUnderline).toBe('#a83737');
    expect(editorPalette(shikiDark).errorUnderline).toBe('#ff6b8a');
    expect(editorPalette(shikiLight).warningUnderline).toBe('#8e4a0e');
    expect(editorPalette(shikiDark).warningUnderline).toBe('#e17d1e');
  });

  test('the selection is visible against the background', () => {
    for (const theme of [shikiLight, shikiDark]) {
      const palette = editorPalette(theme);
      expect(palette.selection).not.toBe(palette.background);
      expect(palette.selection).not.toBe('var(--border)');
    }
  });

  test('themeFor picks the theme the mode names', () => {
    expect(themeFor('light').palette.background).toBe('#e8def0');
    expect(themeFor('dark').palette.background).toBe('#1f1438');
    expect(themeFor('dark').specs).toEqual(styleSpecs(shikiDark));
  });
});
