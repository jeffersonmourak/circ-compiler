// The circ token vocabulary: one table, two consumers.
//
// Consumer 1 — `./circ-lang.mjs`, the TextMate grammar Shiki registers in
//   `astro.config.mjs` (markdown ```circ fences) and `CodePreview.astro`
//   consumes inline. It builds its `keyword` and `type` `match` strings from
//   `KEYWORD_MATCH` / `BUILTIN_MATCH` below.
// Consumer 2 — `../scripts/circ-editor.ts`, whose CodeMirror `StreamParser`
//   calls `nextToken` once per token. It imports nothing else from here.
//
// This file is `.mjs`, not `.ts`: `astro.config.mjs` reaches it through
// `circ-lang.mjs`, and an `.mjs` Astro config cannot import a `.ts` module.
// Plain JavaScript carries no annotations, so every exported shape is
// documented with JSDoc — which is what lets `circ-editor.ts` write
// `import { type CircTokenState } from '../utils/circ-tokens.mjs'` under
// `astro/tsconfigs/strict`. Nothing in CI typechecks it (`bun test` and
// `astro build` both strip types with esbuild, and there is no `typecheck`
// script), so the JSDoc exists for the editor and for the phases that reuse
// these exports.
//
// Why `input_pin` / `output_pin` are NOT in `BUILTIN_TYPES`. `lib/ir/resolver.zig`
// recognises both as primitives and `lib/resolver/scan_imports.zig` reserves
// both, so they look like missing entries next to the `rom` / `ram` fix. They
// are deliberately left out. Grepped 2026-09-09: the two names occur 17 times
// across `DOCS/*.md` — all of them Zig identifiers, preview-box labels or
// prose about the topology encoding (`architecture.md`, `simulation-engine.md`,
// `preview.md`, `wasm-api.md`, `getting-started.md`) — and **zero** times
// inside a ```circ fence of any doc the site publishes, zero times in
// `DOCS/language.md`, and zero times in `site/src/content/{examples,tour}.ts`.
// No circ source anywhere in this repo instantiates them. Adding them would
// therefore highlight nothing that exists today while changing how every
// future docs code block renders an identifier that happens to carry one of
// those names — a scope change, not a bug fix, which is what the `rom` / `ram`
// addition is. If a `.circ` source ever declares one, add it here and the two
// grammars move together by construction.

/**
 * The three declaration keywords the grammar reserves
 * (`lib/grammar/proto-circ.peg`: `import` at :15, `input` at :17, and `output`
 * as the first `ComponentType` alternative at :22).
 * @type {readonly string[]}
 */
export const DECLARATION_KEYWORDS = Object.freeze(['input', 'output', 'import']);

/**
 * Builtin component types. The first ten are the list `circ-lang.mjs` carried
 * as a hand-written literal; `rom` and `ram` are the fix — they are primitives
 * (`lib/ir/resolver.zig:69-70` recognises them, `lib/resolver/scan_imports.zig:33`
 * reserves them) that rendered unhighlighted in every docs code block on the
 * site. See the header comment for why `input_pin` / `output_pin` are absent.
 * @type {readonly string[]}
 */
export const BUILTIN_TYPES = Object.freeze([
  'and',
  'not',
  'wire',
  'led',
  'or',
  'nand',
  'nor',
  'xor',
  'xnor',
  'bus',
  'rom',
  'ram',
]);

/**
 * Multi-character operators, longest first so `<>` wins over `<`.
 * This array is the tokenizer's ONLY source for steps 4, 5 and 8 of the state
 * machine in `nextToken`: they match longest-first out of `OPERATORS` and never
 * repeat the literals. The three TextMate patterns stay hand-written literals
 * (`circ-lang.mjs`'s `connection` and the two `operator` patterns) because they
 * carry three different scopes and different regex escaping, so collapsing them
 * into one alternation would be wrong; `site/test/circ-tokens.test.ts` pins the
 * two grammars against each other instead.
 * @type {readonly string[]}
 */
export const OPERATORS = Object.freeze(['<>', '..', '=']);

/**
 * `\b(a|b|c)\b` — the exact string shape `circ-lang.mjs`'s `keyword` and `type`
 * patterns use.
 * @param {readonly string[]} words
 * @returns {string}
 */
export function alternation(words) {
  return `\\b(${words.join('|')})\\b`;
}

/** @type {string} */
export const KEYWORD_MATCH = alternation(DECLARATION_KEYWORDS);

/** @type {string} */
export const BUILTIN_MATCH = alternation(BUILTIN_TYPES);

/**
 * Per-line tokenizer state. `params` is true between a `<` and the matching
 * `>` on the SAME line, mirroring `circ-lang.mjs`'s `paramIntro` rule
 * (`begin: '<'`, `end: '>|$'`), so it is reset whenever `pos === 0`.
 * @typedef {{ params: boolean }} CircTokenState
 */

/**
 * @returns {CircTokenState}
 */
export function startState() {
  return { params: false };
}

/**
 * @param {CircTokenState} state
 * @returns {CircTokenState}
 */
export function copyState(state) {
  return { params: state.params };
}

/**
 * One token starting at `pos` on `line`. ALWAYS advances: `end > pos` for every
 * `pos`. `tag` is a @lezer/highlight tag name (dot-separated modifiers allowed)
 * or `null` for whitespace.
 *
 * The steps below are the state machine of `DOCS/PLANS/PHASE_1_editor.md`, in
 * order — first match wins, mirroring `circ-lang.mjs`'s `patterns` order.
 *
 * @param {string} line
 * @param {number} pos
 * @param {CircTokenState} state
 * @returns {{ end: number, tag: string | null }}
 */
export function nextToken(line, pos, state) {
  // 0. The line restarts: a parameter list never spans one.
  if (pos === 0) state.params = false;

  // Past the end there is nothing to read, but the caller still gets an
  // advance, so no driver loop can hang on an off-by-one.
  if (pos >= line.length) return { end: pos + 1, tag: null };

  const ch = line[pos];

  // 1. Whitespace run.
  if (WHITESPACE.test(ch)) {
    let end = pos + 1;
    while (end < line.length && WHITESPACE.test(line[end])) end += 1;
    return { end, tag: null };
  }

  // 2. Line comment, to end of line. `comment.line.double-slash.circ`.
  if (ch === '/' && line[pos + 1] === '/') return { end: line.length, tag: 'comment' };

  // 3. Double-quoted string, to the closing quote inclusive, else to EOL.
  //    `string.quoted.double.circ`.
  if (ch === '"') {
    const close = line.indexOf('"', pos + 1);
    return { end: close === -1 ? line.length : close + 1, tag: 'string' };
  }

  // 4, 5, 8. The operators, matched longest-first out of OPERATORS — one loop,
  //    so an operator cannot be added to the table and missed by the tokenizer.
  //    `keyword.operator.{connection,range,assignment}.circ`.
  for (const op of OPERATORS) {
    if (line.startsWith(op, pos)) return { end: pos + op.length, tag: 'operator' };
  }

  // 6, 7. Parameter-list delimiters. `punctuation.definition.parameters.*.circ`.
  if (ch === '<') {
    state.params = true;
    return { end: pos + 1, tag: 'punctuation' };
  }
  if (ch === '>') {
    state.params = false;
    return { end: pos + 1, tag: 'punctuation' };
  }

  // 9. `.port` member reference. `variable.other.member.circ`.
  if (ch === '.' && pos + 1 < line.length && IDENT_START.test(line[pos + 1])) {
    let end = pos + 2;
    while (end < line.length && IDENT_PART.test(line[end])) end += 1;
    return { end, tag: 'propertyName' };
  }

  // 10. Digit run. `constant.numeric.circ`.
  if (DIGIT.test(ch)) {
    let end = pos + 1;
    while (end < line.length && DIGIT.test(line[end])) end += 1;
    return { end, tag: 'number' };
  }

  // 11. Identifier, then classified against the tables and the rest of the line.
  if (IDENT_START.test(ch)) {
    let end = pos + 1;
    while (end < line.length && IDENT_PART.test(line[end])) end += 1;
    return { end, tag: classifyIdentifier(line.slice(pos, end), line.slice(end), state) };
  }

  // 12. Structural punctuation.
  if (PUNCTUATION.test(ch)) return { end: pos + 1, tag: 'punctuation' };

  // 13. Anything else, one code unit at a time. This is what guarantees the
  //     advance CodeMirror's `readToken` enforces by throwing.
  return { end: pos + 1, tag: 'invalid' };
}

/**
 * Convenience wrapper used by the tests and by anything that wants a whole
 * line at once; drives `nextToken` to end of line.
 * @param {string} line
 * @param {CircTokenState} [state]
 * @returns {{ from: number, to: number, tag: string | null }[]}
 */
export function tokenizeLine(line, state = startState()) {
  /** @type {{ from: number, to: number, tag: string | null }[]} */
  const tokens = [];
  let pos = 0;
  while (pos < line.length) {
    const { end, tag } = nextToken(line, pos, state);
    tokens.push({ from: pos, to: end, tag });
    pos = end;
  }
  return tokens;
}

const WHITESPACE = /\s/;
const IDENT_START = /[A-Za-z_]/;
const IDENT_PART = /[A-Za-z0-9_]/;
const DIGIT = /[0-9]/;
const PUNCTUATION = /[(),[\]{}]/;
/** An instance call site: the identifier is immediately before an open paren. */
const CALL_AHEAD = /^\s*\(/;
/** A named port argument: the identifier is immediately before an assignment. */
const ASSIGN_AHEAD = /^\s*=/;

/**
 * Step 11's classification, in order.
 * @param {string} word the identifier just consumed
 * @param {string} rest the remainder of the line after it
 * @param {CircTokenState} state
 * @returns {string}
 */
function classifyIdentifier(word, rest, state) {
  if (DECLARATION_KEYWORDS.includes(word)) return 'keyword'; // keyword.declaration.circ
  if (BUILTIN_TYPES.includes(word)) return 'typeName'; // support.type.builtin.circ
  if (CALL_AHEAD.test(rest)) return 'variableName.function'; // entity.name.function.circ
  if (ASSIGN_AHEAD.test(rest)) return 'propertyName'; // variable.parameter.circ
  if (state.params) return 'propertyName'; // variable.parameter.circ, inside <…>
  return 'variableName';
}
