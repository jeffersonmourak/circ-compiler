// TextMate grammar for the circ language. Used by both:
//  - the markdown pipeline (registered in astro.config.mjs > markdown.shikiConfig.langs),
//    so ```circ fences in DOCS/language.md highlight on the reference page; and
//  - the <Code> component in CodePreview.astro, where it's passed directly as
//    the `lang` prop (because <Code> ignores the markdown shikiConfig and only
//    accepts a bundled-lang string or a LanguageRegistration object inline).
//
// Highlights:
//   declarations   input, output, import
//   primitives     and, not, wire, led
//   macros         or, nand, nor, xor, xnor
//   string lits    "..." (used in `import "<path>"`)
//   line comments  // ...

export const circLang = {
  name: 'circ',
  scopeName: 'source.circ',
  fileTypes: ['circ'],
  patterns: [
    { include: '#comment' },
    { include: '#string' },
    { include: '#decl' },
    { include: '#type' },
    { include: '#port' },
  ],
  repository: {
    comment: {
      patterns: [{ match: '//.*$', name: 'comment.line.double-slash.circ' }],
    },
    string: {
      patterns: [{ match: '"[^"]*"', name: 'string.quoted.double.circ' }],
    },
    decl: {
      patterns: [
        {
          match: '\\b(input|output|import)\\b',
          name: 'keyword.declaration.circ',
        },
      ],
    },
    type: {
      patterns: [
        {
          match: '\\b(and|not|wire|led|or|nand|nor|xor|xnor)\\b',
          name: 'support.type.builtin.circ',
        },
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
