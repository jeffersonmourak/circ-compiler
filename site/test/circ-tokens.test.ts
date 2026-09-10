import { describe, expect, test } from 'bun:test';
import {
  BUILTIN_MATCH,
  BUILTIN_TYPES,
  DECLARATION_KEYWORDS,
  KEYWORD_MATCH,
  OPERATORS,
  alternation,
  nextToken,
  startState,
  tokenizeLine,
} from '../src/utils/circ-tokens.mjs';
import { circLang } from '../src/utils/circ-lang.mjs';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';

/** The 17 sources the site actually ships: 10 gallery examples, 7 tour steps. */
const sources: string[] = [...examples.map((e) => e.source), ...tour.map((t) => t.source)];

/** Tags of the non-whitespace tokens of one line, in order. */
const tagsOf = (line: string): string[] =>
  tokenizeLine(line)
    .filter((t) => t.tag !== null)
    .map((t) => t.tag as string);

/** `[text, tag]` pairs of the non-whitespace tokens of one line, in order. */
const pairsOf = (line: string): [string, string][] =>
  tokenizeLine(line)
    .filter((t) => t.tag !== null)
    .map((t) => [line.slice(t.from, t.to), t.tag as string]);

describe('circ tokens', () => {
  test('the shipped corpus is the 14 examples and the 7 tour steps', () => {
    expect(examples.length).toBe(14);
    expect(tour.length).toBe(7);
    expect(sources.length).toBe(21);
  });

  test('tokenizeLine partitions every shipped source', () => {
    for (const source of sources) {
      for (const line of source.split('\n')) {
        const tokens = tokenizeLine(line);
        let cursor = 0;
        for (const token of tokens) {
          expect(token.from).toBe(cursor); // contiguous: no gap, no overlap
          expect(token.to).toBeGreaterThan(token.from);
          cursor = token.to;
        }
        expect(cursor).toBe(line.length);
        expect(tokens.map((t) => line.slice(t.from, t.to)).join('')).toBe(line);
      }
    }
  });

  test('nextToken always advances', () => {
    for (const source of sources) {
      for (const line of source.split('\n')) {
        for (let pos = 0; pos < line.length; pos += 1) {
          expect(nextToken(line, pos, startState()).end).toBeGreaterThan(pos);
          // The same, with a parameter list open: `state.params` must not be
          // able to stall the machine either.
          expect(nextToken(line, pos, { params: true }).end).toBeGreaterThan(pos);
        }
      }
    }
    // Characters the grammar has no rule for: step 13's `invalid` catch-all is
    // what keeps `readToken` from throwing "Stream parser failed to advance".
    for (const ch of ['\t', '%', '@', '#', ';']) {
      const result = nextToken(ch, 0, startState());
      expect(result.end).toBeGreaterThan(0);
      expect(result.tag).toBe(ch === '\t' ? null : 'invalid');
    }
  });

  test('rom and ram tokenize as builtin types', () => {
    expect(pairsOf('rom code[8, 4](addr = pc.out)')[0]).toEqual(['rom', 'typeName']);
    expect(pairsOf('ram cells[8, 4](addr = pc.out)')[0]).toEqual(['ram', 'typeName']);
    expect(pairsOf('bus b<8>(in = a)')[0]).toEqual(['bus', 'typeName']);
    expect(pairsOf('xnor g(a = a, b = b)')[0]).toEqual(['xnor', 'typeName']);
    expect(pairsOf('led l(in = a)')[0]).toEqual(['led', 'typeName']);
    // The whole table, each word standing alone.
    for (const word of BUILTIN_TYPES) expect(tagsOf(word)).toEqual(['typeName']);
    for (const word of DECLARATION_KEYWORDS) expect(tagsOf(word)).toEqual(['keyword']);
  });

  test('markers and builtin imports tokenize as expected', () => {
    expect(tokenizeLine('// half_adder.circ')).toEqual([
      { from: 0, to: 18, tag: 'comment' },
    ]);
    expect(pairsOf('import xor "<builtin>/xor.circ"')).toEqual([
      ['import', 'keyword'],
      ['xor', 'typeName'],
      ['"<builtin>/xor.circ"', 'string'],
    ]);
    expect(tagsOf('not n(in=a)')).toEqual([
      'typeName',
      'variableName.function',
      'punctuation',
      'propertyName',
      'operator',
      'variableName',
      'punctuation',
    ]);
  });

  test('the TextMate grammar is built from the token table', () => {
    expect(circLang.repository.keyword.patterns[0].match).toBe(KEYWORD_MATCH);
    expect(circLang.repository.type.patterns[0].match).toBe(BUILTIN_MATCH);
    expect(BUILTIN_MATCH).toContain('rom');
    expect(BUILTIN_MATCH).toContain('ram');
    expect(circLang.repository.type.patterns[0].match).toContain('rom');
    expect(circLang.repository.type.patterns[0].match).toContain('ram');
    expect(alternation(['a', 'b'])).toBe('\\b(a|b)\\b');

    // Everything else about the grammar object is byte-identical, because
    // `astro.config.mjs` and `CodePreview.astro` consume it unchanged.
    expect(circLang.scopeName).toBe('source.circ');
    expect(circLang.patterns.map((p) => p.include)).toEqual([
      '#comment',
      '#string',
      '#keyword',
      '#type',
      '#number',
      '#connection',
      '#paramIntro',
      '#instance',
      '#portName',
      '#operator',
      '#port',
    ]);
  });

  test('operators come from the token table', () => {
    expect(OPERATORS).toEqual(['<>', '..', '=']);
    for (let i = 1; i < OPERATORS.length; i += 1) {
      expect(OPERATORS[i].length).toBeLessThanOrEqual(OPERATORS[i - 1].length);
    }

    // The three TextMate patterns stay three hand-written literals (three
    // scopes, three escapings), so this is the assertion that keeps them from
    // drifting: every operator in the table is spelled by exactly one of them,
    // and no pattern is left without an operator.
    const patterns = [
      circLang.repository.connection.patterns[0].match,
      circLang.repository.operator.patterns[0].match,
      circLang.repository.operator.patterns[1].match,
    ];
    for (const op of OPERATORS) {
      const hits = patterns.filter((p) => new RegExp(`^(?:${p})$`).test(op));
      expect(hits.length).toBe(1);
    }
    for (const pattern of patterns) {
      const hits = OPERATORS.filter((op) => new RegExp(`^(?:${pattern})$`).test(op));
      expect(hits.length).toBe(1);
    }

    // And the tokenizer reads that same table.
    for (const op of OPERATORS) expect(tagsOf(op)).toEqual(['operator']);
  });
});
