import { describe, expect, test } from 'bun:test';
import { StreamLanguage, type StringStream } from '@codemirror/language';
import { circLanguage, circStreamParser } from '../src/scripts/circ-editor.ts';
import { startState } from '../src/utils/circ-tokens.mjs';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';

// `circ-editor.ts` imports cleanly without a DOM: `@codemirror/view` guards
// both of its module-scope host accesses, `style-mod` reaches `document` only
// inside `StyleModule.mount()` (i.e. when a view is constructed), and
// `@codemirror/language`'s single module-scope host read is guarded too. Only
// `createEditor` needs a browser, and nothing here calls it.

const sources: string[] = [...examples.map((e) => e.source), ...tour.map((t) => t.source)];

/** The subset of `StringStream` the adapter touches, duck-typed. */
const streamFor = (line: string): StringStream =>
  ({ string: line, pos: 0, start: 0 }) as unknown as StringStream;

describe('circ stream parser', () => {
  test('the stream parser always advances', () => {
    let tokens = 0;
    for (const source of sources) {
      for (const line of source.split('\n')) {
        const stream = streamFor(line);
        const state = circStreamParser.startState!(2);
        let guard = 0;
        while (stream.pos < line.length) {
          const before = stream.pos;
          stream.start = before;
          const tag = circStreamParser.token(stream, state);
          // Exactly the precondition `readToken` enforces by throwing
          // "Stream parser failed to advance stream."
          expect(stream.pos).toBeGreaterThan(before);
          expect(tag === null || typeof tag === 'string').toBe(true);
          tokens += 1;
          guard += 1;
          expect(guard).toBeLessThanOrEqual(line.length + 1);
        }
        expect(stream.pos).toBe(line.length);
      }
    }
    expect(tokens).toBeGreaterThan(100); // non-vacuous: the corpus was walked
  });

  test('the parser state round-trips through copyState', () => {
    const state = circStreamParser.startState!(2);
    expect(state).toEqual(startState());
    const stream = streamFor('bus b<8>(in = a)');
    // Bounded, so a tokenizer that stops advancing fails here rather than hanging.
    for (let step = 0; stream.pos < stream.string.length; step += 1) {
      expect(step).toBeLessThanOrEqual(stream.string.length);
      const before = stream.pos;
      stream.start = before;
      circStreamParser.token(stream, state);
      expect(stream.pos).toBeGreaterThan(before);
    }
    const copy = circStreamParser.copyState!(state);
    expect(copy).toEqual(state);
    expect(copy).not.toBe(state);
  });

  test('the parser spec is accepted and carries its language data', () => {
    expect(() => StreamLanguage.define(circStreamParser)).not.toThrow();
    expect(circStreamParser.languageData?.commentTokens).toEqual({ line: '//' });
    // The module-level `StreamLanguage.define` also ran at import time.
    expect(circLanguage).toBeInstanceOf(StreamLanguage);
  });
});
