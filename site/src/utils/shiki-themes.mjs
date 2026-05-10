// Custom Shiki TextMate themes that mirror the blog's purple palette
// (jeffersonmourak.github.io). Used by both the markdown pipeline
// (astro.config.mjs) and the <Code> component in CodePreview.astro,
// so the two stay in lockstep — changing one place was the original
// drift hazard. With defaultColor:false at the call sites, Shiki emits
// both --shiki-light and --shiki-dark variables and global.css picks
// which one applies via the [data-theme] attribute on <html>.
//
// Color strategy: purple shades carry IDENTIFIERS / chrome (functions,
// variables, comments, punctuation). Two complementary hues carry the
// language's core vocabulary — green for declarations and built-in types
// (input/output/import, and/not/wire/led/or/nand/...), orange for literal
// data (strings like "<builtin>/...", numbers, constants, escape chars).
// Dark theme uses the user-provided hexes (#1ee17d / #e17d1e) directly;
// light theme darkens both so they clear WCAG AA on the code-block bg.
// The bg itself is intentionally a touch darker than --bg so code blocks
// read as distinct containers rather than blending into the page.

const lightBg = '#e8def0';
const lightFg = '#443856';
const lightMuted = '#8a7e9a';
const lightAccent = '#6e49ab';
const lightAccentDark = '#5d3a96';
const lightAccentSoft = '#8a6dc4';
const lightKeywordGreen = '#0a6634';  // ~5.4:1 on lightBg, AA pass
const lightLiteralOrange = '#8e4a0e'; // ~5.3:1 on lightBg, AA pass

const darkBg = '#1f1438';
const darkFg = '#c0abda';
const darkMuted = '#7d6e94';
const darkAccent = '#b097d1';
const darkAccentDeep = '#a385c5';
const darkAccentSoft = '#c8b3e0';
const darkAccentBright = '#d8c5e8';
const darkKeywordGreen = '#1ee17d';   // user-provided, ~9:1 on darkBg
const darkLiteralOrange = '#e17d1e';  // user-provided, ~5:1 on darkBg

export const shikiLight = {
  name: 'circ-purple-light',
  type: 'light',
  colors: {
    'editor.background': lightBg,
    'editor.foreground': lightFg,
  },
  tokenColors: [
    { scope: ['comment', 'punctuation.definition.comment'], settings: { foreground: lightMuted, fontStyle: 'italic' } },
    { scope: ['string', 'string.quoted', 'punctuation.definition.string'], settings: { foreground: lightLiteralOrange } },
    { scope: ['constant.character.escape'], settings: { foreground: lightLiteralOrange, fontStyle: 'bold' } },
    { scope: ['constant.numeric', 'constant.language', 'support.constant'], settings: { foreground: lightLiteralOrange } },
    { scope: ['keyword', 'storage.type', 'storage.modifier', 'keyword.control', 'keyword.declaration'], settings: { foreground: lightKeywordGreen, fontStyle: 'bold' } },
    { scope: ['keyword.operator'], settings: { foreground: lightAccent } },
    { scope: ['entity.name.function', 'support.function', 'meta.function-call'], settings: { foreground: lightAccentSoft } },
    { scope: ['entity.name.type', 'entity.name.class', 'support.type', 'support.class'], settings: { foreground: lightKeywordGreen } },
    { scope: ['entity.name.tag'], settings: { foreground: lightKeywordGreen } },
    { scope: ['entity.other.attribute-name'], settings: { foreground: lightAccentSoft } },
    { scope: ['variable', 'variable.parameter', 'variable.other'], settings: { foreground: lightFg } },
    { scope: ['variable.language'], settings: { foreground: lightKeywordGreen, fontStyle: 'italic' } },
    { scope: ['punctuation', 'meta.brace', 'meta.delimiter'], settings: { foreground: lightMuted } },
    { scope: ['markup.heading'], settings: { foreground: lightKeywordGreen, fontStyle: 'bold' } },
    { scope: ['markup.bold'], settings: { foreground: lightFg, fontStyle: 'bold' } },
    { scope: ['markup.italic'], settings: { foreground: lightFg, fontStyle: 'italic' } },
    { scope: ['invalid'], settings: { foreground: '#a83737' } },
  ],
};

export const shikiDark = {
  name: 'circ-purple-dark',
  type: 'dark',
  colors: {
    'editor.background': darkBg,
    'editor.foreground': darkFg,
  },
  tokenColors: [
    { scope: ['comment', 'punctuation.definition.comment'], settings: { foreground: darkMuted, fontStyle: 'italic' } },
    { scope: ['string', 'string.quoted', 'punctuation.definition.string'], settings: { foreground: darkLiteralOrange } },
    { scope: ['constant.character.escape'], settings: { foreground: darkLiteralOrange, fontStyle: 'bold' } },
    { scope: ['constant.numeric', 'constant.language', 'support.constant'], settings: { foreground: darkLiteralOrange } },
    { scope: ['keyword', 'storage.type', 'storage.modifier', 'keyword.control', 'keyword.declaration'], settings: { foreground: darkKeywordGreen, fontStyle: 'bold' } },
    { scope: ['keyword.operator'], settings: { foreground: darkAccent } },
    { scope: ['entity.name.function', 'support.function', 'meta.function-call'], settings: { foreground: darkAccentBright } },
    { scope: ['entity.name.type', 'entity.name.class', 'support.type', 'support.class'], settings: { foreground: darkKeywordGreen } },
    { scope: ['entity.name.tag'], settings: { foreground: darkKeywordGreen } },
    { scope: ['entity.other.attribute-name'], settings: { foreground: darkAccentSoft } },
    { scope: ['variable', 'variable.parameter', 'variable.other'], settings: { foreground: darkFg } },
    { scope: ['variable.language'], settings: { foreground: darkKeywordGreen, fontStyle: 'italic' } },
    { scope: ['punctuation', 'meta.brace', 'meta.delimiter'], settings: { foreground: darkMuted } },
    { scope: ['markup.heading'], settings: { foreground: darkKeywordGreen, fontStyle: 'bold' } },
    { scope: ['markup.bold'], settings: { foreground: darkFg, fontStyle: 'bold' } },
    { scope: ['markup.italic'], settings: { foreground: darkFg, fontStyle: 'italic' } },
    { scope: ['invalid'], settings: { foreground: '#ff6b8a' } },
  ],
};

export const shikiThemes = { light: shikiLight, dark: shikiDark };
