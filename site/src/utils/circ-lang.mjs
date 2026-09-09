// TextMate grammar for the circ language. Used by both:
//  - the markdown pipeline (registered in astro.config.mjs > markdown.shikiConfig.langs),
//    so ```circ fences in DOCS/language.md highlight on the reference page; and
//  - the <Code> component in CodePreview.astro, where it's passed directly as
//    the `lang` prop (because <Code> ignores the markdown shikiConfig and only
//    accepts a bundled-lang string or a LanguageRegistration object inline).
//
// The keyword and builtin-type alternations are built from ./circ-tokens.mjs,
// the one token table the CodeMirror editor (src/scripts/circ-editor.ts) reads
// too, so a type can never be highlighted in one and not the other.
//
// A third consumer lives out of tree and cannot be edited from this repo: the
// editor extension's vendored TextMate copy at
// https://github.com/jeffersonmourak/circ-lsp (syntaxes/circ.tmLanguage.json,
// same scopes, JSON form), which names this file canonical and drifts from it.
//
// Highlights:
//   declarations   input, output, import
//   primitives     and, not, wire, led, or, nand, nor, xor, xnor, bus, rom, ram
//   numbers        integer widths and bit indices (4, 0..7)
//   operators      <> (connection), = (port assignment), .. (slice range)
//   parameters     <W> parameter introductions and named port arguments (in=)
//   instances      a component/sub-circuit name immediately before '('
//   members        .port references
//   string lits    "..." (used in `import "<path>"`)
//   line comments  // ...

import { BUILTIN_MATCH, KEYWORD_MATCH } from './circ-tokens.mjs';

export const circLang = {
  name: 'circ',
  scopeName: 'source.circ',
  fileTypes: ['circ'],
  patterns: [
    { include: '#comment' },
    { include: '#string' },
    { include: '#keyword' },
    { include: '#type' },
    { include: '#number' },
    { include: '#connection' },
    { include: '#paramIntro' },
    { include: '#instance' },
    { include: '#portName' },
    { include: '#operator' },
    { include: '#port' },
  ],
  repository: {
    comment: {
      patterns: [{ match: '//.*$', name: 'comment.line.double-slash.circ' }],
    },
    string: {
      patterns: [{ match: '"[^"]*"', name: 'string.quoted.double.circ' }],
    },
    keyword: {
      patterns: [
        {
          match: KEYWORD_MATCH,
          name: 'keyword.declaration.circ',
        },
      ],
    },
    type: {
      patterns: [
        {
          match: BUILTIN_MATCH,
          name: 'support.type.builtin.circ',
        },
      ],
    },
    number: {
      patterns: [{ match: '\\b[0-9]+\\b', name: 'constant.numeric.circ' }],
    },
    connection: {
      patterns: [{ match: '<>', name: 'keyword.operator.connection.circ' }],
    },
    paramIntro: {
      begin: '<',
      end: '>|$',
      beginCaptures: { 0: { name: 'punctuation.definition.parameters.begin.circ' } },
      endCaptures: { 0: { name: 'punctuation.definition.parameters.end.circ' } },
      patterns: [
        { match: '\\b[a-zA-Z_][a-zA-Z0-9_]*\\b', name: 'variable.parameter.circ' },
        { match: ',', name: 'punctuation.separator.circ' },
      ],
    },
    instance: {
      patterns: [
        {
          match: '\\b[a-zA-Z_][a-zA-Z0-9_]*\\b(?=\\s*\\()',
          name: 'entity.name.function.circ',
        },
      ],
    },
    portName: {
      patterns: [
        {
          match: '\\b[a-zA-Z_][a-zA-Z0-9_]*\\b(?=\\s*=)',
          name: 'variable.parameter.circ',
        },
      ],
    },
    operator: {
      patterns: [
        { match: '\\.\\.', name: 'keyword.operator.range.circ' },
        { match: '=', name: 'keyword.operator.assignment.circ' },
      ],
    },
    port: {
      patterns: [
        {
          match: '\\.([a-zA-Z_][a-zA-Z0-9_]*)\\b',
          captures: { 1: { name: 'variable.other.member.circ' } },
        },
      ],
    },
  },
};
